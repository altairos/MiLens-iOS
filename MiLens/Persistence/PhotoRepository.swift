//  PhotoRepository —— 照片数据访问（对应源端 repository/PhotoRepository.ets）。
//  扫描/导入边界（DESIGN.md §7）：扫描只调用 getAllPhotoURIs() 做去重，
//  入库唯一路径是用户主动触发的 insertPhoto()。

import Foundation
import SwiftData

/// 重复标记组（对应源端 `DuplicateMarkGroup`）。
/// `replaceDuplicateMarks` 用此结构原子替换所有重复关系。
struct DuplicateMarkGroup: Equatable, Sendable {
    let bestID: UUID
    let duplicateIDs: [UUID]
}

/// 照片仓储协议（@MainActor —— SwiftData ModelContext 隔离）。
@MainActor
protocol PhotoRepositoryProtocol {
    func getPhoto(id: UUID) throws -> Photo?
    func getPhotoByURI(_ uri: String) throws -> Photo?
    /// 已入库的所有 URI（扫描去重用——对应源端 getAllPhotoUris）。
    func getAllPhotoURIs() throws -> Set<String>
    /// 相册分页（按拍摄时间倒序，对应源端 getPhotosPage）。
    func getPhotosPage(offset: Int, limit: Int) throws -> [Photo]
    /// 某宠物的全部照片（对应源端 getPhotosByPetId）。
    func getPhotosByPet(_ pet: Pet) throws -> [Photo]
    /// 指定月日拍摄、参与纪念事件的照片（对应源端 getAnniversaryEvents）。
    /// - Parameters:
    ///   - month: 1–12
    ///   - day: 1–31
    ///   - excludeYear: 排除指定年份的照片（时光机用，nil = 不排除）
    func getAnniversaryPhotos(month: Int, day: Int, excludeYear: Int?) throws -> [Photo]
    /// 用户主动导入——唯一入库路径（DESIGN.md §7 硬约束）。
    func insertPhoto(_ photo: Photo) throws
    func deletePhoto(_ photo: Photo) throws
    /// 分配/取消归属（对应源端 assignPhotoToPet）。
    func assignPhoto(_ photo: Photo, to pet: Pet?) throws
    func setFavorite(_ photo: Photo, favorite: Bool) throws
    func updateNote(_ photo: Photo, note: String) throws

    // ── 质量评分 / 重复分组（ADR-0008）──
    /// 质量评分待处理的照片（qualityScore == 0），按 createdAt 升序（对应源端 `getPendingQualityScorePage`）。
    func getPendingQualityScorePhotos(limit: Int) throws -> [Photo]
    /// 重复分析候选（phash 非空），按 createdAt 升序（对应源端 `getDuplicateCandidates`）。
    func getDuplicateCandidates() throws -> [Photo]
    /// 更新照片质量数据（对应源端 `updateQualityScore`，扩展为同时写入 phash）。
    func updateQualityData(_ photo: Photo, sharpness: Double, qualityScore: Double, phash: String) throws
    /// 原子替换所有重复标记（对应源端 `replaceDuplicateMarks`）。
    func replaceDuplicateMarks(_ groups: [DuplicateMarkGroup]) throws
}

/// SwiftData 实现的照片仓储。
@MainActor
final class SwiftDataPhotoRepository: PhotoRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func getPhoto(id: UUID) throws -> Photo? {
        let descriptor = FetchDescriptor<Photo>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func getPhotoByURI(_ uri: String) throws -> Photo? {
        let descriptor = FetchDescriptor<Photo>(
            predicate: #Predicate { $0.uri == uri }
        )
        return try context.fetch(descriptor).first
    }

    func getAllPhotoURIs() throws -> Set<String> {
        let descriptor = FetchDescriptor<Photo>()
        let photos = try context.fetch(descriptor)
        return Set(photos.map(\.uri))
    }

    func getPhotosPage(offset: Int, limit: Int) throws -> [Photo] {
        var descriptor = FetchDescriptor<Photo>(
            sortBy: [SortDescriptor(\.takenAt, order: .reverse)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func getPhotosByPet(_ pet: Pet) throws -> [Photo] {
        // 用已加载的关系排序，避免可选关系 predicate 的不确定性。
        return pet.photos.sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }
    }

    /// 指定月日拍摄、参与纪念事件的照片（对应源端 `getAnniversaryEvents`）。
    /// 过滤语义：eventNotify = true、note 非空、拍摄日期 MM-DD 匹配、可选排除年份；
    /// 按拍摄时间倒序。
    func getAnniversaryPhotos(month: Int, day: Int, excludeYear: Int?) throws -> [Photo] {
        var descriptor = FetchDescriptor<Photo>(
            predicate: #Predicate { $0.eventNotify },
            sortBy: [SortDescriptor(\.takenAt, order: .reverse)]
        )
        // SwiftData 谓词无法表达月日匹配，先取 eventNotify 子集再内存过滤
        // （与 getDuplicateCandidates 同模式，量级可控）。
        let photos = try context.fetch(descriptor)
        return photos.filter { photo in
            guard !photo.note.isEmpty,
                  NotifyCheckLogic.matchesMonthDay(photo.takenAt, month: month, day: day) else {
                return false
            }
            if let excludeYear,
               NotifyCheckLogic.isInYear(photo.takenAt, year: excludeYear) {
                return false
            }
            return true
        }
    }

    func insertPhoto(_ photo: Photo) throws {
        context.insert(photo)
        try context.save()
    }

    func deletePhoto(_ photo: Photo) throws {
        context.delete(photo)
        try context.save()
    }

    func assignPhoto(_ photo: Photo, to pet: Pet?) throws {
        photo.pet = pet
        try context.save()
    }

    func setFavorite(_ photo: Photo, favorite: Bool) throws {
        photo.isFavorite = favorite
        try context.save()
    }

    func updateNote(_ photo: Photo, note: String) throws {
        photo.note = note
        try context.save()
    }

    // MARK: - 质量评分 / 重复分组

    func getPendingQualityScorePhotos(limit: Int) throws -> [Photo] {
        var descriptor = FetchDescriptor<Photo>(
            predicate: #Predicate { $0.qualityScore == 0 },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func getDuplicateCandidates() throws -> [Photo] {
        let descriptor = FetchDescriptor<Photo>(
            predicate: #Predicate { !$0.phash.isEmpty },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    func updateQualityData(_ photo: Photo, sharpness: Double, qualityScore: Double, phash: String) throws {
        photo.sharpness = sharpness
        photo.qualityScore = qualityScore
        if !phash.isEmpty { photo.phash = phash }
        try context.save()
    }

    func replaceDuplicateMarks(_ groups: [DuplicateMarkGroup]) throws {
        // 先清除所有标记（源端 SQL 原子 UPDATE 的等价语义）
        let all = try context.fetch(FetchDescriptor<Photo>())
        for photo in all {
            photo.duplicateOf = nil
            photo.isBest = true
        }
        // 再写入分组关系
        var duplicateToBest: [UUID: UUID] = [:]
        for group in groups {
            for dupID in group.duplicateIDs {
                duplicateToBest[dupID] = group.bestID
            }
        }
        for photo in all {
            if let bestID = duplicateToBest[photo.id] {
                photo.duplicateOf = bestID
                photo.isBest = false
            }
        }
        try context.save()
    }
}
