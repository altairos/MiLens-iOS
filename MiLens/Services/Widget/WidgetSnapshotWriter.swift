//  WidgetSnapshotWriter —— 主 App → App Group 共享快照写入器。
//
//  WidgetKit-Design.md §6.1：主 App 在以下事件后更新 App Group 快照并调用
//  WidgetCenter.reloadAllTimelines：
//  - 导入、删除或重新归属照片；
//  - 新建/编辑伙伴档案与纪念事件；
//  - 添加记忆或生成新作品；
//  - 前台启动完成数据迁移后。
//
//  共享内容只包含 Widget 所需投影（UUID、显示名、日期、计数、最多一行标题、
//  深链目标和降采样缩略图）。不复制全尺寸照片，不让 Widget 直接打开 SwiftData store。

import Foundation
import UIKit
import ImageIO
import WidgetKit
import SwiftData
import os
import MiLensKit

/// 从 SwiftData 读取数据 → 投影为 WidgetSnapshot → 降采样缩略图写入 App Group →
/// JSON 序列化 → reloadAllTimelines。
///
/// `@MainActor` —— 依赖 Repository 协议（均为 @MainActor，SwiftData ModelContext 隔离）。
/// 缩略图降采样与文件 IO 在 `Task.detached` 中执行，不阻塞主线程。
@MainActor
final class WidgetSnapshotWriter {
    private let petRepo: any PetRepositoryProtocol
    private let photoRepo: any PhotoRepositoryProtocol
    private let logger = Logger(subsystem: "com.milens.app", category: "WidgetSnapshotWriter")

    /// 快照中保留的最大照片投影数。
    private let maxPhotos = 50
    /// 共享缩略图最大数量。
    private let maxThumbnails = 20
    /// 缩略图降采样最大边长（pt × scale）。
    private let thumbnailMaxSize: CGFloat = 300
    /// 写入代数：每次 writeSnapshot 递增。后台缩略图任务提交结果前
    /// 检查是否仍为最新代，防止旧任务清理掉新任务所需的缩略图。
    private var writeGeneration = 0
    /// 当前待完成的后台缩略图写入任务（新写入时取消旧任务）。
    private var pendingThumbnailTask: Task<Void, Never>?

    init(petRepo: any PetRepositoryProtocol, photoRepo: any PhotoRepositoryProtocol) {
        self.petRepo = petRepo
        self.photoRepo = photoRepo
    }

    // MARK: - 公开接口

    /// 组装快照并写入 App Group，然后 reload Widget timelines。
    /// 失败仅记日志不阻断主流程（Widget 是增强，不是关键路径）。
    func writeSnapshot() {
        guard let containerURL = appGroupContainerURL() else {
            logger.warning("writeSnapshot: App Group 容器不可用，跳过 Widget 快照写入")
            return
        }
        do {
            let pets = try petRepo.getAllPets()
            let allPhotos = try photoRepo.getPhotosPage(offset: 0, limit: maxPhotos)
            let totalPhotos = try photoRepo.countAllPhotos()
            let snapshot = buildSnapshot(
                pets: pets, photos: allPhotos, totalPhotos: totalPhotos
            )
            try writeJSON(snapshot, to: containerURL)
            // 在 MainActor 上收集缩略图源路径（Photo 对象只在 MainActor 可访问）
            let thumbnails = collectThumbnailSources(from: allPhotos)
            let thumbMax = thumbnailMaxSize

            // 取消上一次未完成的后台写入（旧任务的清理会清掉新任务所需的缩略图）
            pendingThumbnailTask?.cancel()
            writeGeneration += 1
            let generation = writeGeneration

            // 代数检查闭包：供 copyThumbnails 在降采样前和写入前各调用一次，
            // 防止旧代任务的降采样结果覆盖新代任务已写入的同名缩略图。
            // 同时检查 Task.isCancelled 与 generation，任一过期即返回 true。
            let isStale: @Sendable () async -> Bool = { [weak self] in
                guard !Task.isCancelled else { return true }
                let latest = await MainActor.run { self?.writeGeneration == generation }
                return !latest
            }

            pendingThumbnailTask = Task.detached(priority: .utility) { [weak self] in
                await Self.copyThumbnails(
                    thumbnails, to: containerURL, maxSize: thumbMax, isStale: isStale)
                // 只有未被取消且仍为最新代的任务才 reload（旧代已被新代取代）
                guard !Task.isCancelled else { return }
                let isLatest = await MainActor.run { self?.writeGeneration == generation }
                guard isLatest else { return }
                WidgetCenter.shared.reloadAllTimelines()
            }
            // 立即 reload 一次（让文字数据先更新，图片随后）
            WidgetCenter.shared.reloadAllTimelines()
            logger.info("writeSnapshot: 快照已写入（\(snapshot.pets.count) 宠物 / \(snapshot.photos.count) 照片）")
        } catch {
            logger.error("writeSnapshot: 失败（\(error.localizedDescription)）")
        }
    }

    // MARK: - 组装快照

    private func buildSnapshot(pets: [Pet], photos: [Photo], totalPhotos: Int) -> WidgetSnapshot {
        // 投影宠物
        let petProjections = pets.map { pet in
            PetProjection(
                id: pet.id, name: pet.name, species: pet.species.rawValue,
                birthday: pet.birthday, adoptionDay: pet.adoptionDay,
                photoCount: pet.photoCount
            )
        }

        // 投影照片
        let photoProjections = photos.map { photo in
            PhotoProjection(
                id: photo.id,
                petID: photo.pet?.id,
                petName: photo.pet?.name,
                thumbnailFileName: thumbnailFileName(for: photo),
                takenAt: photo.takenAt,
                note: String(photo.note.prefix(60)),
                qualityScore: photo.qualityScore,
                isWork: photo.category == "edited"
            )
        }

        // 纪念日候选
        let upcomingDays = buildUpcomingDays(from: pets)

        // 档案统计
        let memoryCount = pets.reduce(0) { $0 + $1.events.filter { $0.sourceType == "user" }.count }
        let workCount = photos.filter { $0.category == "edited" }.count
        let archiveStart = photos.compactMap { $0.takenAt }.min()
            ?? pets.map(\.createdAt).min()
        let stats = ArchiveStats(
            totalPhotos: totalPhotos,
            totalMemories: memoryCount,
            totalWorks: workCount,
            archiveStartDate: archiveStart,
            petCount: pets.count
        )

        return WidgetSnapshot(
            pets: petProjections,
            photos: photoProjections,
            upcomingDays: upcomingDays,
            archiveStats: stats,
            lastUpdated: Date()
        )
    }

    /// 从全部宠物构建纪念日候选（生日 / 领养日 / 用户纪念事件）。
    ///
    /// 每个候选带稳定 id，用作 App Intents 的实体主键，让用户能在 Widget 配置中
    /// 指名某个特定纪念日：生日/领养日按 petID 派生（每只宠物各一个），纪念事件
    /// 用 event.id 保证同宠物的多个事件互不冲突。
    private func buildUpcomingDays(from pets: [Pet]) -> [UpcomingDayProjection] {
        var days: [UpcomingDayProjection] = []
        for pet in pets {
            if let birthday = pet.birthday {
                days.append(UpcomingDayProjection(
                    kind: .birthday, petID: pet.id, petName: pet.name,
                    title: "\(pet.name)的生日", originalDate: birthday,
                    id: "birthday:\(pet.id.uuidString)"
                ))
            }
            if let adoption = pet.adoptionDay {
                days.append(UpcomingDayProjection(
                    kind: .adoption, petID: pet.id, petName: pet.name,
                    title: "成为家人的日子", originalDate: adoption,
                    id: "adoption:\(pet.id.uuidString)"
                ))
            }
            for event in pet.events where event.sourceType != "user" {
                days.append(UpcomingDayProjection(
                    kind: .memorial, petID: pet.id, petName: pet.name,
                    title: event.title, originalDate: event.eventDate,
                    id: "memorial:\(event.id.uuidString)"
                ))
            }
        }
        return days
    }

    // MARK: - 缩略图

    /// 缩略图文件名：复用沙盒缩略图路径的文件名部分，存入 App Group 供 Widget 读取。
    private func thumbnailFileName(for photo: Photo) -> String? {
        let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
        guard !path.isEmpty else { return nil }
        // 用 photoID 保证文件名唯一且稳定
        return "\(photo.id.uuidString).jpg"
    }

    /// 收集需要复制的缩略图源路径 → 目标文件名映射（最多 maxThumbnails 个）。
    /// 必须在 MainActor 上调用（Photo 对象只在 MainActor 可访问）。
    private func collectThumbnailSources(from photos: [Photo]) -> [(sourcePath: String, destName: String)] {
        photos.prefix(maxThumbnails).compactMap { photo in
            let destName = thumbnailFileName(for: photo)
            // 优先用 thumbnailPath，回退到 uri（原图路径）
            let sourcePath = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
            guard !sourcePath.isEmpty else { return nil }
            return (sourcePath: sourcePath, destName: destName ?? "")
        }
        .filter { !$0.destName.isEmpty }
    }

    /// 把沙盒缩略图降采样后复制到 App Group 缩略图目录（后台线程）。
    /// `sources` 是 (源路径, 目标文件名) 对；源路径为空时跳过。
    /// `isStale` 在每次文件操作前调用，返回 true 时中止（旧代任务或已取消）。
    nonisolated static func copyThumbnails(
        _ sources: [(sourcePath: String, destName: String)],
        to containerURL: URL,
        maxSize: CGFloat,
        isStale: @Sendable () async -> Bool = { Task.isCancelled }
    ) async {
        let thumbDir = containerURL.appendingPathComponent(WidgetSharedConfig.thumbnailsDirName)
        let fm = FileManager.default

        // 确保缩略图目录存在
        try? fm.createDirectory(at: thumbDir, withIntermediateDirectories: true)

        // 清理过期缩略图（不在本次 sources 中的）；旧代任务跳过清理
        // （旧代任务不应清理新代任务仍需要的缩略图）
        if await !isStale(),
           let existing = try? fm.contentsOfDirectory(at: thumbDir, includingPropertiesForKeys: nil) {
            let validNames = Set(sources.map(\.destName))
            for url in existing where !validNames.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        }

        let scale = await MainActor.run { UIScreen.main.scale }
        for source in sources {
            // 降采样前检查代数：旧代任务提前中止
            if await isStale() { return }
            guard !source.sourcePath.isEmpty,
                  fm.fileExists(atPath: source.sourcePath) else { continue }
            let destURL = thumbDir.appendingPathComponent(source.destName)
            // 先降采样（CPU 密集，不写磁盘），拿到 JPEG 数据后再检查代数。
            guard let data = downsample(
                sourcePath: source.sourcePath,
                maxPixelSize: maxSize * scale
            ) else { continue }
            // 写入前二次检查代数：旧代降采样完成后可能已被新代取代，
            // 此时写入会覆盖新代结果。检查失败则中止，不写磁盘。
            if await isStale() { return }
            try? data.write(to: destURL, options: .atomic)
        }
    }

    /// 用 ImageIO 降采样源图片为 JPEG 数据（不写磁盘）。
    /// 与文件写入分离，使调用方能在降采样完成、写入前插入代数检查。
    nonisolated static func downsample(
        sourcePath: String, maxPixelSize: CGFloat
    ) -> Data? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.8)
    }

    // MARK: - JSON 写入

    private func writeJSON(_ snapshot: WidgetSnapshot, to containerURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let fileURL = containerURL.appendingPathComponent(WidgetSharedConfig.snapshotFileName)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - App Group 容器

    private func appGroupContainerURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSharedConfig.appGroupID
        )
    }
}
