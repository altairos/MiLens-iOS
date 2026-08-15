//  ZipBackupService —— BackupService 的 ZIP 实现（ADR-0010 §8）。
//
//  将照片原图 + 编辑产物 + 完整元数据（Pet/Photo/PetEvent 的 Codable 快照）打包为
//  `.milensbackup`（store ZIP，由 MiLensKit `ZIPArchive` 提供）。导出经 ShareSheet 交给
//  用户选择存储位置（Files/iCloud Drive/AirDrop），不联网；恢复经 DocumentPicker 选择
//  备份文件，校验 manifest.schemaVersion 后合并导入（同 ID/originalURI 跳过，不覆盖）。
//
//  设计要点：
//  - 元数据收集在 MainActor（SwiftData ModelContext 隔离）；文件读取与 ZIP 打包在非隔离
//    async 上下文，避免阻塞主线程。
//  - DB 是事实源：照片文件缺失时仍记录元数据（恢复后视图按 auditOrphans 语义处理占位）。
//  - 恢复合并语义：宠物按 id、照片按 originalURI 去重跳过，绝不覆盖现有数据。
//  - featureData（CLIP 特征）不导出——可从照片重新生成（与 PetSnapshot 注释一致）。
//
//  文件组织（600 行规模守卫拆分，docs/audit/remediation-plan.md P1-1）：
//  - 本文件：导出链路（预估/收集/分卷决策/单卷写入）
//  - ZipBackupService+Restore.swift：恢复链路（导入编排/卷校验/预校验/合并落库）
//  - ZipBackupSupport.swift：支撑类型（分卷配置/中间模型/线程安全计数器/JSON
//    编解码器）与快照 ⇄ SwiftData 纯函数转换

import Foundation
import MiLensKit

/// @unchecked Sendable 就地理由（DESIGN.md §9.1）：全部存储属性为 `let` 不可变引用
/// （组合根注入的 repo/存储协议实例与字符串配置），服务自身不持有可变状态，跨任务
/// 共享同一实例安全；导出期间的可变进度/累计状态收敛在持锁的 StreamProgressCounter
/// / ExportSizeGuard 内（见 ZipBackupSupport.swift）。
final class ZipBackupService: BackupService, @unchecked Sendable {

    // 以下 4 个属性为 internal（非 private）：恢复链路 extension
    // （ZipBackupService+Restore.swift）需跨文件访问；全部为 let 只读，无可变状态。
    let petRepo: any PetRepositoryProtocol
    let photoRepo: any PhotoRepositoryProtocol
    let fileStorage: any FileStorage
    let sandboxDir: String
    private let appVersion: String
    private let temporaryDirectory: String
    private let volumeSplitConfig: VolumeSplitConfig

    init(petRepo: any PetRepositoryProtocol,
         photoRepo: any PhotoRepositoryProtocol,
         fileStorage: any FileStorage,
         sandboxDir: String,
         appVersion: String,
         temporaryDirectory: String = NSTemporaryDirectory(),
         volumeSplitConfig: VolumeSplitConfig = .default) {
        self.petRepo = petRepo
        self.photoRepo = photoRepo
        self.fileStorage = fileStorage
        self.sandboxDir = sandboxDir
        self.appVersion = appVersion
        self.temporaryDirectory = temporaryDirectory
        self.volumeSplitConfig = volumeSplitConfig
    }

    var isAvailable: Bool { true }

    // MARK: - 预估

    /// 预估将导出的内容规模（仅统计计数与字节数，不读取照片文件、不打包）。
    /// 与 collectExportBundle 同样的 petIDs 过滤语义，保证预估与实际导出一致。
    ///
    /// 字节数优先取文件系统真实大小（stat），fallback 到 DB fileSize——
    /// 保证预估与实际导出分卷决策一致，避免 DB fileSize 过期导致预估偏小。
    func estimateBackup(petIDs: [UUID]?) async throws -> BackupEstimate {
        // repo 协议为 @MainActor，本方法非隔离——跨 actor 调用需 await。
        let allPets = try await petRepo.getAllPets()
        let selectedPets: [Pet]
        if let petIDs, !petIDs.isEmpty {
            let wanted = Set(petIDs)
            selectedPets = allPets.filter { wanted.contains($0.id) }
        } else {
            selectedPets = allPets
        }

        let photos: [Photo]
        if petIDs != nil {
            var tempPhotos: [Photo] = []
            for pet in selectedPets {
                tempPhotos.append(contentsOf: try await photoRepo.getPhotosByPet(pet))
            }
            photos = tempPhotos
        } else {
            photos = try await collectAllPhotos()
        }
        let totalBytes = photos.reduce(Int64(0)) { sum, photo in
            sum + Self.actualSize(for: photo, fileStorage: fileStorage)
        }
        return BackupEstimate(
            petCount: selectedPets.count,
            photoCount: photos.count,
            estimatedBytes: totalBytes)
    }

    // JSON 编解码器（ISO8601，键排序）已移至 ZipBackupSupport.swift 的 extension，
    // 调用点 `Self.encoder` / `encoder` / `Self.decoder` 不变。

    // MARK: - 导出

    func exportBackup(
        petIDs: [UUID]?,
        progress: @escaping @Sendable @MainActor (BackupProgress) -> Void
    ) async throws -> BackupResult {

        await progress(BackupProgress(current: 0, total: 1, phase: .collectingMetadata))
        let bundle = try await collectExportBundle(petIDs: petIDs)

        // 分卷决策：预估总字节数（含每条目 ZIP 开销）超过多卷阈值时自动拆分。
        // 使用文件系统真实大小 + 每条目开销预算，避免 DB fileSize 过期导致误判单卷。
        let perEntryOverhead = BackupConfig.zipEntryOverheadBytes
        let totalEstimated = Int(bundle.estimatedPhotoBytes)
            + bundle.photoFiles.count * perEntryOverhead
        let needsMultiVolume = totalEstimated > volumeSplitConfig.multiVolumeThreshold

        let backupID = UUID().uuidString
        let dateStamp = Self.dateStamp()
        let idSuffix = String(backupID.prefix(8))

        if !needsMultiVolume {
            // 单卷导出
            let fileName = "MiLens-Backup-\(dateStamp)-\(idSuffix).\(BackupConfig.fileExtension)"
            let fileURL = URL(fileURLWithPath: temporaryDirectory)
                .appendingPathComponent(fileName)
            let manifest = BackupManifest(
                schemaVersion: BackupConfig.currentSchemaVersion,
                appVersion: appVersion,
                platform: "ios",
                exportDate: Date(),
                photoCount: bundle.photoSnaps.count,
                petCount: bundle.petSnaps.count,
                backupID: backupID,
                volumeNumber: 1,
                totalVolumes: 1)
            let metadata = BackupMetadata(
                pets: bundle.petSnaps,
                photos: bundle.photoSnaps,
                petEvents: bundle.eventSnaps)
            try await writeSingleVolume(
                manifest: manifest,
                metadata: metadata,
                photoFiles: bundle.photoFiles,
                avatarFiles: bundle.avatarFiles,
                to: fileURL,
                progress: progress)
            await progress(BackupProgress(current: 1, total: 1, phase: .done))
            return BackupResult(fileURLs: [fileURL], manifest: manifest, metadata: metadata)
        }

        // 多卷导出：每卷预算 = 目标大小 - 每卷固定开销（每卷重复的 pets/events 元数据
        // + manifest + 头像字节，头像只在卷 1 但保守计入所有卷的预算）。为每张照片额外
        // 预留 perEntryOverhead（ZIP header/CD + metadata.json 余量），避免写到中途超限。
        let perVolumeReserve = Self.estimatePerVolumeReserve(
            petSnaps: bundle.petSnaps, eventSnaps: bundle.eventSnaps,
            avatarBytes: Int(bundle.estimatedAvatarBytes))
        let effectiveTarget = max(1, volumeSplitConfig.volumeTargetSizeBytes - perVolumeReserve)

        let volumeGroups = Self.splitPhotoFilesIntoVolumes(
            bundle.photoFiles,
            bundle.photoSnaps,
            effectiveTarget: effectiveTarget,
            perEntryOverhead: perEntryOverhead)
        let totalVolumes = volumeGroups.count

        await progress(BackupProgress(
            current: 0, total: bundle.photoFiles.count, phase: .copyingPhotos))

        var generatedURLs: [URL] = []
        let globalProgressCounter = StreamProgressCounter(total: bundle.photoFiles.count)
        var firstManifest: BackupManifest?
        var firstMetadata: BackupMetadata?

        do {
            for (volIndex, group) in volumeGroups.enumerated() {
                let volumeNumber = volIndex + 1
                let fileName = "MiLens-Backup-\(dateStamp)-\(idSuffix)-part\(volumeNumber)of\(totalVolumes).\(BackupConfig.fileExtension)"
                let fileURL = URL(fileURLWithPath: temporaryDirectory)
                    .appendingPathComponent(fileName)

                let manifest = BackupManifest(
                    schemaVersion: BackupConfig.currentSchemaVersion,
                    appVersion: appVersion,
                    platform: "ios",
                    exportDate: Date(),
                    photoCount: group.snaps.count,
                    petCount: bundle.petSnaps.count,
                    backupID: backupID,
                    volumeNumber: volumeNumber,
                    totalVolumes: totalVolumes)
                // 多卷：pets/events 全集在每卷重复（供恢复时从任一卷读取），
                // photos 仅本卷子集。
                let metadata = BackupMetadata(
                    pets: bundle.petSnaps,
                    photos: group.snaps,
                    petEvents: bundle.eventSnaps)
                // 头像只在卷 1 包含（体积小，集中管理）
                let avatarFilesForVolume = volumeNumber == 1 ? bundle.avatarFiles : []
                try await writeSingleVolume(
                    manifest: manifest,
                    metadata: metadata,
                    photoFiles: group.files,
                    avatarFiles: avatarFilesForVolume,
                    to: fileURL,
                    progress: progress,
                    sharedProgressCounter: globalProgressCounter)
                if volumeNumber == 1 {
                    firstManifest = manifest
                    firstMetadata = metadata
                }
                generatedURLs.append(fileURL)
            }
        } catch {
            // 原子性：任一卷失败 → 删除全部已生成的卷文件
            for url in generatedURLs {
                try? await fileStorage.removeItem(at: url.path)
            }
            throw error
        }

        await progress(BackupProgress(current: 1, total: 1, phase: .done))
        // manifest/metadata 取卷 1 的实际值（与卷 1 文件内部一致），避免调用方读到
        // 与文件内容不一致的统计。
        return BackupResult(
            fileURLs: generatedURLs,
            manifest: firstManifest!,
            metadata: firstMetadata!)
    }

    /// 估算多卷导出时每卷的固定开销字节数（每卷重复的 pets/events 元数据 + manifest + 头像）。
    /// 头像只在卷 1，但保守地计入所有卷的预算，确保卷 1 不超限。
    private static func estimatePerVolumeReserve(
        petSnaps: [PetSnapshot], eventSnaps: [PetEventSnapshot], avatarBytes: Int
    ) -> Int {
        let petsEventsOnly = BackupMetadata(
            pets: petSnaps, photos: [], petEvents: eventSnaps)
        let metadataBytes = (try? encoder.encode(petsEventsOnly).count) ?? 0
        // manifest JSON 约 300 字节，保守预留 1 KB。
        return metadataBytes + avatarBytes + 1024
    }

    /// 将照片文件+快照按有效目标字节数贪心分组为多个卷。
    /// 每张照片成本 = 真实文件大小（stat）+ perEntryOverhead（ZIP header/CD + metadata 余量），
    /// 按 effectiveTarget（已扣除每卷固定开销）贪心分组。
    /// 单张超大照片独占一卷（仍受 maxTotalExportSizeBytes 硬守卫）。
    private static func splitPhotoFilesIntoVolumes(
        _ photoFiles: [(zipPath: String, sourcePath: String, size: Int64)],
        _ photoSnaps: [PhotoSnapshot],
        effectiveTarget: Int,
        perEntryOverhead: Int
    ) -> [(files: [(zipPath: String, sourcePath: String, size: Int64)], snaps: [PhotoSnapshot])] {
        guard !photoFiles.isEmpty else {
            return []
        }
        // photoFiles 与 photoSnaps 顺序一致（collectExportBundle 中同步生成）
        var volumes: [(files: [(zipPath: String, sourcePath: String, size: Int64)], snaps: [PhotoSnapshot])] = []
        var currentFiles: [(zipPath: String, sourcePath: String, size: Int64)] = []
        var currentSnaps: [PhotoSnapshot] = []
        var currentSize = 0

        for (index, file) in photoFiles.enumerated() {
            let snap = photoSnaps[index]
            // 成本基于真实文件大小 + 每条目开销，不再依赖可能过期的 DB fileSize
            let entryCost = Int(file.size) + perEntryOverhead
            // 单张超大照片独占一卷
            if entryCost > effectiveTarget {
                // 先刷新当前卷
                if !currentFiles.isEmpty {
                    volumes.append((currentFiles, currentSnaps))
                    currentFiles = []
                    currentSnaps = []
                    currentSize = 0
                }
                volumes.append(([file], [snap]))
                continue
            }
            if currentSize + entryCost > effectiveTarget {
                // 当前卷已满，开启新卷
                volumes.append((currentFiles, currentSnaps))
                currentFiles = [file]
                currentSnaps = [snap]
                currentSize = entryCost
            } else {
                currentFiles.append(file)
                currentSnaps.append(snap)
                currentSize += entryCost
            }
        }
        if !currentFiles.isEmpty {
            volumes.append((currentFiles, currentSnaps))
        }
        return volumes
    }

    /// 写入单个卷（单卷/多卷共用）。
    /// `sharedProgressCounter` 非 nil 时用于多卷导出全局进度（跨卷累加）。
    /// 无论单卷/多卷，拷贝阶段进度始终回调（多卷此前传空闭包导致用户只能转圈）。
    private func writeSingleVolume(
        manifest: BackupManifest,
        metadata: BackupMetadata,
        photoFiles: [(zipPath: String, sourcePath: String, size: Int64)],
        avatarFiles: [(zipPath: String, sourcePath: String, size: Int64)],
        to fileURL: URL,
        progress: @escaping @Sendable @MainActor (BackupProgress) -> Void,
        sharedProgressCounter: StreamProgressCounter? = nil
    ) async throws {
        let manifestData = try Self.encoder.encode(manifest)
        let metadataData = try Self.encoder.encode(metadata)

        var streamEntries: [ZipStreamEntry] = [
            ZipStreamEntry(path: BackupConfig.manifestFileName) { manifestData },
            ZipStreamEntry(path: BackupConfig.metadataFileName) { metadataData },
        ]

        let allFiles = avatarFiles + photoFiles
        let progressCounter = sharedProgressCounter ?? StreamProgressCounter(total: allFiles.count)

        let sizeGuard = ExportSizeGuard(maxBytes: BackupConfig.maxTotalExportSizeBytes)

        for file in allFiles {
            guard fileStorage.fileExists(at: file.sourcePath) else {
                _ = progressCounter.next()
                let current = progressCounter.value
                await progress(BackupProgress(current: current, total: progressCounter.total, phase: .copyingPhotos))
                continue
            }
            let sourcePath = file.sourcePath
            let zipPath = file.zipPath
            let fileStorageRef = fileStorage
            streamEntries.append(ZipStreamEntry(path: zipPath) {
                if Task.isCancelled { throw BackupServiceError.cancelled }
                let data = try await fileStorageRef.read(at: sourcePath)
                guard data.count <= BackupConfig.maxSingleEntrySizeBytes else {
                    throw BackupServiceError.backupTooLarge
                }
                try sizeGuard.add(data.count)
                let current = progressCounter.next()
                await progress(BackupProgress(current: current, total: progressCounter.total, phase: .copyingPhotos))
                return data
            })
        }

        guard streamEntries.count <= BackupConfig.maxEntryCount else {
            throw BackupServiceError.backupTooLarge
        }

        await progress(BackupProgress(current: 0, total: 1, phase: .compressing))
        let output = try await fileStorage.makeOutputStream(at: fileURL.path)
        do {
            try await ZipWriter.writeArchive(entries: streamEntries, to: output)
            try await output.close()
        } catch {
            try? await output.close()
            try? await fileStorage.removeItem(at: fileURL.path)
            throw error
        }
    }

    /// 收集元数据快照与待打包文件清单（MainActor——SwiftData ModelContext 隔离）。
    /// 分卷导出/单卷导出共用此结果；卷分割在外层按 estimatedPhotoBytes 决策。
    @MainActor
    private func collectExportBundle(petIDs: [UUID]?) async throws -> ExportBundle {
        let allPets = try petRepo.getAllPets()
        let selectedPets: [Pet]
        if let petIDs, !petIDs.isEmpty {
            let wanted = Set(petIDs)
            selectedPets = allPets.filter { wanted.contains($0.id) }
        } else {
            selectedPets = allPets
        }

        var petSnaps: [PetSnapshot] = []
        var avatarFiles: [(zipPath: String, sourcePath: String, size: Int64)] = []

        for pet in selectedPets {
            let avatar = Self.resolveAvatar(for: pet, fileExists: { fileStorage.fileExists(at: $0) })
            petSnaps.append(Self.snapshot(pet: pet, avatarFileName: avatar?.fileName))
            if let avatar {
                let size = fileStorage.fileSize(at: avatar.sourcePath) ?? 0
                avatarFiles.append((zipPath: "\(avatarsDirName)/\(avatar.fileName)",
                              sourcePath: avatar.sourcePath,
                              size: size))
            }
        }

        // 照片范围：petIDs=nil 全量；否则仅选中宠物的照片。
        // flatMap 闭包内不能 try，改循环累积（与 estimateBackup 的写法一致）。
        let photos: [Photo]
        if petIDs != nil {
            var selectedPetPhotos: [Photo] = []
            for pet in selectedPets {
                selectedPetPhotos.append(contentsOf: try photoRepo.getPhotosByPet(pet))
            }
            photos = selectedPetPhotos
        } else {
            photos = try collectAllPhotos()
        }

        var photoSnaps: [PhotoSnapshot] = []
        var photoFiles: [(zipPath: String, sourcePath: String, size: Int64)] = []
        var estimatedPhotoBytes: Int64 = 0
        for photo in photos {
            let fileName = "\(photo.id.uuidString).\(Self.fileExtension(for: photo.uri))"
            photoSnaps.append(Self.snapshot(photo: photo, petID: photo.pet?.id, fileName: fileName))
            // 优先取文件系统真实大小（stat），fallback 到 DB fileSize。
            // 分卷决策基于真实大小，避免 DB 值过期导致写到中途才抛 backupTooLarge。
            let actualSize = Self.actualSize(for: photo, fileStorage: fileStorage)
            photoFiles.append((zipPath: "\(BackupConfig.photosDirName)/\(fileName)",
                          sourcePath: photo.uri,
                          size: actualSize))
            estimatedPhotoBytes += actualSize
        }

        // 事件：选中宠物的全部纪念事件（含 notify/body/sourceType/isPinned/relatedPhotoID）
        var eventSnaps: [PetEventSnapshot] = []
        for pet in selectedPets {
            for event in pet.events {
                eventSnaps.append(PetEventSnapshot(
                    id: event.id, petID: pet.id,
                    eventType: event.eventType, eventDate: event.eventDate, title: event.title,
                    notify: event.notify, body: event.body, sourceType: event.sourceType,
                    isPinned: event.isPinned, relatedPhotoID: event.relatedPhotoID))
            }
        }

        let avatarBytes = avatarFiles.reduce(Int64(0)) { $0 + $1.size }
        return ExportBundle(
            petSnaps: petSnaps,
            eventSnaps: eventSnaps,
            photoSnaps: photoSnaps,
            photoFiles: photoFiles,
            avatarFiles: avatarFiles,
            estimatedPhotoBytes: estimatedPhotoBytes,
            estimatedAvatarBytes: avatarBytes)
    }

    /// 分页拉取全部照片（避免改 Repository 协议新增 getAllPhotos）。
    @MainActor
    private func collectAllPhotos() throws -> [Photo] {
        var all: [Photo] = []
        var offset = 0
        let limit = 200
        while true {
            let page = try photoRepo.getPhotosPage(offset: offset, limit: limit)
            if page.isEmpty { break }
            all.append(contentsOf: page)
            offset += page.count
            if page.count < limit { break }
        }
        return all
    }

    // 恢复链路（importBackup 及卷校验/预校验/合并落库）已移至 ZipBackupService+Restore.swift；
    // 快照转换与支撑类型（分卷配置/中间模型/计数器/JSON 编解码）已移至 ZipBackupSupport.swift。
}
