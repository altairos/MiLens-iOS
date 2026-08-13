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

import Foundation
import MiLensKit

/// 备份包内头像目录名（照片统一走 `BackupConfig.photosDirName`，头像独立目录避免命名冲突）。
private let avatarsDirName = "avatars"

/// 分卷决策阈值（可注入，便于测试用小阈值触发多卷）。
/// 生产默认值取 `BackupConfig`（2 GB 触发多卷，每卷约 1.8 GB）。
struct VolumeSplitConfig: Sendable {
    /// 预估总字节数（含每条目开销）超过此值时触发多卷导出。
    let multiVolumeThreshold: Int
    /// 多卷导出时每卷的目标字节数（贪心分组上限）。
    let volumeTargetSizeBytes: Int

    static let `default` = VolumeSplitConfig(
        multiVolumeThreshold: BackupConfig.maxTotalExportSizeBytes,
        volumeTargetSizeBytes: BackupConfig.volumeTargetSizeBytes)
}

final class ZipBackupService: BackupService, @unchecked Sendable {

    private let petRepo: any PetRepositoryProtocol
    private let photoRepo: any PhotoRepositoryProtocol
    private let fileStorage: any FileStorage
    private let sandboxDir: String
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
        let allPets = try petRepo.getAllPets()
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
                tempPhotos.append(contentsOf: try photoRepo.getPhotosByPet(pet))
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

    // MARK: - JSON 编解码（ISO8601 日期，键排序保证 manifest 可 diff）

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - 导出

    func exportBackup(
        petIDs: [UUID]?,
        progress: @Sendable @MainActor (BackupProgress) -> Void
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
        progress: @Sendable @MainActor (BackupProgress) -> Void,
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
        let photos: [Photo]
        if petIDs != nil {
            photos = selectedPets.flatMap { try photoRepo.getPhotosByPet($0) }
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

    // MARK: - 恢复

    func importBackup(
        from urls: [URL],
        progress: @Sendable @MainActor (RestoreProgress) -> Void
    ) async throws -> RestoreResult {

        guard !urls.isEmpty else {
            throw BackupServiceError.invalidFormat
        }

        await progress(RestoreProgress(current: 0, total: 1, phase: .decompressing))

        // security-scoped resource：DocumentPicker 选择的 iCloud/Files 文件需先获取访问权。
        var didStartAccesses: [Bool] = []
        for url in urls {
            didStartAccesses.append(url.startAccessingSecurityScopedResource())
        }
        defer {
            for (url, didStart) in zip(urls, didStartAccesses) where didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // 原子性保证：跟踪本次写入的所有文件路径，任意阶段失败时统一清理，
        // 避免文件已写入但数据库未完成、或数据库只恢复了一部分留下孤儿文件。
        var writtenPaths: [String] = []
        // volumes 提到 do 块外：拷贝阶段 CRC 错误/取消/输出失败时，外层 catch
        // 需关闭仍打开的输入流，避免文件句柄泄漏（成功路径下方会关闭后置空）。
        var volumes: [RestoreVolume] = []

        do {
            // 阶段 1：读取并校验全部卷的元数据
            volumes = try await readAndValidateVolumes(urls: urls, progress: progress)

            // 合并 metadata：photos 取并集，pets/events 取任一卷（每卷重复包含全集）。
            let mergedPhotos = volumes.flatMap { $0.metadata.photos }
            let mergedPets = volumes.first?.metadata.pets ?? []
            let mergedEvents = volumes.first?.metadata.petEvents ?? []
            let mergedMetadata = BackupMetadata(
                pets: mergedPets, photos: mergedPhotos, petEvents: mergedEvents)

            // 预校验（MainActor）：在写文件前确定哪些照片/宠物会被实际导入。
            let prevalidated = try await prevalidateImport(metadata: mergedMetadata)

            await progress(RestoreProgress(
                current: 0, total: mergedPhotos.count, phase: .copyingFiles))
            var photoPathByID: [UUID: String] = [:]
            var written = 0
            var processedPhotoIDs: Set<UUID> = []

            // 阶段 2：按卷拷贝照片文件
            for volume in volumes {
                if Task.isCancelled { throw BackupServiceError.cancelled }
                let input = volume.input
                let recordMap = volume.recordMap

                for photoSnap in volume.metadata.photos {
                    if Task.isCancelled { throw BackupServiceError.cancelled }
                    guard prevalidated.photos.contains(photoSnap.id) else {
                        written += 1
                        await progress(RestoreProgress(
                            current: written, total: mergedPhotos.count, phase: .copyingFiles))
                        continue
                    }
                    // 备份内部重复 id → 只为首条写文件
                    guard !processedPhotoIDs.contains(photoSnap.id) else {
                        written += 1
                        await progress(RestoreProgress(
                            current: written, total: mergedPhotos.count, phase: .copyingFiles))
                        continue
                    }
                    processedPhotoIDs.insert(photoSnap.id)
                    // 路径穿越防御：拒绝非纯文件名
                    if Self.isSafeFileName(photoSnap.photoFileName) {
                        let zipPath = "\(BackupConfig.photosDirName)/\(photoSnap.photoFileName)"
                        if let record = recordMap[zipPath] {
                            let dest = "\(sandboxDir)/\(photoSnap.photoFileName)"
                            if !fileStorage.fileExists(at: dest) {
                                let output = try await fileStorage.makeOutputStream(at: dest)
                                writtenPaths.append(dest)
                                do {
                                    try await ZipReader.copyEntry(
                                        record, from: input, to: output,
                                        chunkSize: BackupConfig.backupChunkSizeBytes)
                                    try await output.close()
                                } catch {
                                    try? await output.close()
                                    throw error
                                }
                                photoPathByID[photoSnap.id] = dest
                            }
                        }
                    }
                    written += 1
                    await progress(RestoreProgress(
                        current: written, total: mergedPhotos.count, phase: .copyingFiles))
                }
            }

            // 头像拷贝：只需从任意包含头像的卷读取（多卷时仅卷 1）
            for volume in volumes {
                if Task.isCancelled { throw BackupServiceError.cancelled }
                let input = volume.input
                let recordMap = volume.recordMap

                for petSnap in mergedMetadata.pets {
                    guard prevalidated.pets.contains(petSnap.id),
                          let avatarName = petSnap.avatarFileName,
                          prevalidated.avatarOwnerByFileName[avatarName] != nil,
                          Self.isSafeFileName(avatarName) else { continue }
                    let zipPath = "\(avatarsDirName)/\(avatarName)"
                    if let record = recordMap[zipPath] {
                        let dest = "\(sandboxDir)/\(avatarsDirName)/\(avatarName)"
                        if !fileStorage.fileExists(at: dest) {
                            let output = try await fileStorage.makeOutputStream(at: dest)
                            writtenPaths.append(dest)
                            do {
                                try await ZipReader.copyEntry(
                                    record, from: input, to: output,
                                    chunkSize: BackupConfig.backupChunkSizeBytes)
                                try await output.close()
                            } catch {
                                try? await output.close()
                                throw error
                            }
                        }
                    }
                }
                // 头像只在卷 1，拷贝完跳出
                break
            }

            // 关闭全部输入流后再合并元数据
            for volume in volumes {
                try? await volume.input.close()
            }
            volumes = []

            await progress(RestoreProgress(current: 0, total: 1, phase: .importingMetadata))
            let result = try await applyImport(
                metadata: mergedMetadata,
                photoPathByID: photoPathByID,
                importablePhotoIDs: prevalidated.photos,
                avatarOwnerByFileName: prevalidated.avatarOwnerByFileName)

            await progress(RestoreProgress(current: 1, total: 1, phase: .done))
            return result
        } catch {
            // 关闭仍打开的输入流（拷贝阶段失败时 volumes 非空），避免文件句柄泄漏
            for volume in volumes {
                try? await volume.input.close()
            }
            // 清理本次写入的文件，避免孤儿残留
            for path in writtenPaths {
                try? await fileStorage.removeItem(at: path)
            }
            throw error
        }
    }

    /// 读取并校验全部卷：打开输入流、读 CD、校验大小、读 manifest+metadata、验证卷集完整性。
    /// 返回按卷号排序的卷信息列表（含仍打开的输入流，供后续文件拷贝使用）。
    private func readAndValidateVolumes(
        urls: [URL],
        progress: @Sendable @MainActor (RestoreProgress) -> Void
    ) async throws -> [RestoreVolume] {
        struct RawVolume {
            let url: URL
            let manifest: BackupManifest
            let metadata: BackupMetadata
            let input: any ZipInputStream
            let recordMap: [String: ZipReader.ZipEntryRecord]
        }

        var rawVolumes: [RawVolume] = []
        for url in urls {
            let input: any ZipInputStream
            do {
                input = try await fileStorage.makeInputStream(at: url.path)
            } catch {
                throw BackupServiceError.readFailed(error.localizedDescription)
            }
            do {
                let records = try await ZipReader.readCentralDirectory(from: input)
                try Self.validateRecords(
                    records,
                    maxTotalUncompressedSize: BackupConfig.maxBackupSizeBytes,
                    maxEntryCount: BackupConfig.maxEntryCount,
                    maxSingleEntrySize: BackupConfig.maxSingleEntrySizeBytes)

                var recordMap: [String: ZipReader.ZipEntryRecord] = [:]
                for record in records {
                    if recordMap[record.path] == nil {
                        recordMap[record.path] = record
                    }
                }

                await progress(RestoreProgress(current: 0, total: urls.count, phase: .validating))

                guard let manifestRecord = recordMap[BackupConfig.manifestFileName] else {
                    throw BackupServiceError.invalidFormat
                }
                let manifestData = try await ZipReader.readEntryData(manifestRecord, from: input)
                let manifest = try Self.decoder.decode(BackupManifest.self, from: manifestData)
                guard manifest.schemaVersion == BackupConfig.currentSchemaVersion else {
                    throw BackupServiceError.unsupportedVersion(
                        found: manifest.schemaVersion,
                        supported: BackupConfig.currentSchemaVersion)
                }

                guard let metadataRecord = recordMap[BackupConfig.metadataFileName] else {
                    throw BackupServiceError.invalidFormat
                }
                let metadataData = try await ZipReader.readEntryData(metadataRecord, from: input)
                let metadata = try Self.decoder.decode(BackupMetadata.self, from: metadataData)

                rawVolumes.append(RawVolume(
                    url: url, manifest: manifest, metadata: metadata,
                    input: input, recordMap: recordMap))
            } catch {
                try? await input.close()
                // 清理已打开的输入流
                for v in rawVolumes { try? await v.input.close() }
                throw error
            }
        }

        // 卷集完整性校验
        guard let first = rawVolumes.first else {
            throw BackupServiceError.invalidFormat
        }

        let isMultiVolume = first.manifest.backupID != nil
            && first.manifest.totalVolumes != nil
            && first.manifest.totalVolumes! > 1

        if isMultiVolume {
            // 多卷模式：先校验 backupID 一致，再校验卷号完整覆盖。
            // 先查 backupID 可让用户区分「选错了导出」与「少选了卷」两种错误。
            let backupID = first.manifest.backupID!
            let expectedTotal = first.manifest.totalVolumes!
            for v in rawVolumes {
                guard v.manifest.backupID == backupID else {
                    throw BackupServiceError.mismatchedBackupID
                }
            }
            guard rawVolumes.count == expectedTotal else {
                throw BackupServiceError.incompleteVolumeSet(
                    found: rawVolumes.count, expected: expectedTotal)
            }
            var seenVolumeNumbers = Set<Int>()
            for v in rawVolumes {
                guard let volNum = v.manifest.volumeNumber,
                      volNum >= 1, volNum <= expectedTotal else {
                    throw BackupServiceError.invalidFormat
                }
                guard !seenVolumeNumbers.contains(volNum) else {
                    throw BackupServiceError.invalidFormat
                }
                seenVolumeNumbers.insert(volNum)
            }
            // 卷号须覆盖 1...expectedTotal
            guard seenVolumeNumbers.count == expectedTotal,
                  (1...expectedTotal).allSatisfy({ seenVolumeNumbers.contains($0) }) else {
                throw BackupServiceError.incompleteVolumeSet(
                    found: seenVolumeNumbers.count, expected: expectedTotal)
            }
            // 按卷号排序
            rawVolumes.sort { ($0.manifest.volumeNumber ?? 0) < ($1.manifest.volumeNumber ?? 0) }
        } else {
            // 单卷模式（旧格式无 backupID，或新格式 volumeNumber=1/totalVolumes=1）
            // urls.count 必须为 1
            guard rawVolumes.count == 1 else {
                throw BackupServiceError.invalidFormat
            }
        }

        return rawVolumes.map {
            RestoreVolume(
                manifest: $0.manifest,
                metadata: $0.metadata,
                input: $0.input,
                recordMap: $0.recordMap)
        }
    }

    /// 基于 central directory records 做大小校验（不加载数据本体，防 OOM）。
    private static func validateRecords(
        _ records: [ZipReader.ZipEntryRecord],
        maxTotalUncompressedSize: Int,
        maxEntryCount: Int,
        maxSingleEntrySize: Int
    ) throws {
        guard records.count <= maxEntryCount else {
            throw BackupServiceError.restoreTooLarge("条目数超限（\(records.count) > \(maxEntryCount)）")
        }
        var total = 0
        for record in records {
            guard record.uncompSize <= maxSingleEntrySize else {
                throw BackupServiceError.restoreTooLarge("单条目超限（\(record.path)：\(record.uncompSize) > \(maxSingleEntrySize)）")
            }
            total += record.uncompSize
            guard total <= maxTotalUncompressedSize else {
                throw BackupServiceError.restoreTooLarge("总大小超限（\(total) > \(maxTotalUncompressedSize)）")
            }
        }
    }

    /// 预校验：在写文件前确定哪些照片/宠物会被实际导入（MainActor）。
    ///
    /// 双层去重：
    /// 1. **备份包内部**——同一备份中出现重复 id / originalURI / photoFileName 时，
    ///    只取首条导入。防止第二条记录写入文件后因重复被跳过留下孤儿文件，
    ///    或多条 Photo 共用同一文件路径导致删除一条误删另一条。
    /// 2. **与现有 DB**——同 id 宠物 / 同 id 或同 originalURI 照片已存在时跳过。
    ///
    /// 返回可导入集合——文件复制阶段仅写入这些记录的文件。
    /// `importablePhotoIDs` 也传给 applyImport，确保被预校验过滤的照片不会被插入 DB（P1 修复）。
    /// `avatarOwnerByFileName` 记录每个头像文件名的首主宠物 id：只有 owner 绑定头像路径，
    /// 冲突的第二只宠物仍导入但 avatarPath 为空（避免两宠物指向同一头像文件）。
    @MainActor
    private func prevalidateImport(
        metadata: BackupMetadata
    ) async throws -> PrevalidationResult {
        var importablePets: Set<UUID> = []
        var avatarOwnerByFileName: [String: UUID] = [:]
        var seenPetIDs: Set<UUID> = []
        for petSnap in metadata.pets {
            // 备份内部重复 pet id → 只导入首条
            guard !seenPetIDs.contains(petSnap.id) else { continue }
            seenPetIDs.insert(petSnap.id)
            // 备份内部重复 avatarFileName → 只让首个声明的宠物拥有（防两宠物指向同一头像文件）。
            // 注意：不跳过冲突宠物本身——它仍会被导入，仅不绑定头像。
            if let avatarName = petSnap.avatarFileName, !avatarName.isEmpty {
                if avatarOwnerByFileName[avatarName] == nil {
                    avatarOwnerByFileName[avatarName] = petSnap.id
                }
            }
            if try petRepo.getPet(id: petSnap.id) == nil {
                importablePets.insert(petSnap.id)
            }
        }

        var importablePhotos: Set<UUID> = []
        var seenPhotoIDs: Set<UUID> = []
        var seenOriginalURIs: Set<String> = []
        var seenPhotoFileNames: Set<String> = []
        for photoSnap in metadata.photos {
            // 备份内部重复 id → 跳过（防孤儿文件：第二条写文件后因重复 id 被 applyImport 跳过）
            guard !seenPhotoIDs.contains(photoSnap.id) else { continue }
            seenPhotoIDs.insert(photoSnap.id)
            // 备份内部重复 originalURI → 跳过（防共用文件路径 / 删除一条误删另一条）
            guard !seenOriginalURIs.contains(photoSnap.originalURI) else { continue }
            seenOriginalURIs.insert(photoSnap.originalURI)
            // 备份内部重复 photoFileName → 跳过（防多张照片写同一 dest 路径）
            guard !seenPhotoFileNames.contains(photoSnap.photoFileName) else { continue }
            seenPhotoFileNames.insert(photoSnap.photoFileName)
            // 同 id 或同 originalURI 已在 DB 中存在 → 跳过（不导入、不写文件）
            if try photoRepo.getPhoto(id: photoSnap.id) != nil { continue }
            if try photoRepo.getPhotoByOriginalURI(photoSnap.originalURI) != nil { continue }
            importablePhotos.insert(photoSnap.id)
        }
        return PrevalidationResult(
            photos: importablePhotos,
            pets: importablePets,
            avatarOwnerByFileName: avatarOwnerByFileName)
    }

    /// 合并导入元数据（MainActor）。同 id 宠物 / 同 id 或同 originalURI 照片跳过，不覆盖。
    /// 原子性：任意阶段失败时回滚已插入的记录，避免半成品残留。
    ///
    /// `importablePhotoIDs` 确保被预校验过滤的照片（重复 photoFileName 等）不会插入 DB（P1 修复）。
    /// `avatarOwnerByFileName` 确保只有头像首主宠物绑定头像路径，冲突宠物 avatarPath 为空。
    @MainActor
    private func applyImport(
        metadata: BackupMetadata,
        photoPathByID: [UUID: String],
        importablePhotoIDs: Set<UUID>,
        avatarOwnerByFileName: [String: UUID]
    ) async throws -> RestoreResult {
        var importedPets = 0
        var importedPhotos = 0
        var importedEvents = 0
        var skipped = 0

        // 跟踪已插入记录，失败时回滚
        var insertedPets: [Pet] = []
        var insertedPhotos: [Photo] = []

        do {
            // 1) 宠物
            var petByID: [UUID: Pet] = [:]
            for petSnap in metadata.pets {
                if Task.isCancelled { throw BackupServiceError.cancelled }
                if try petRepo.getPet(id: petSnap.id) != nil {
                    skipped += 1
                    continue
                }
                let pet = Self.recreate(
                    pet: petSnap, sandboxDir: sandboxDir,
                    avatarOwnerByFileName: avatarOwnerByFileName)
                try petRepo.insertPet(pet)
                petByID[petSnap.id] = pet
                insertedPets.append(pet)
                importedPets += 1
            }

            // 2) 事件（关联到已导入或已存在的宠物）
            for eventSnap in metadata.petEvents {
                if Task.isCancelled { throw BackupServiceError.cancelled }
                // 只为本次导入的宠物追加事件；已存在宠物的事件不重复导入
                guard let pet = petByID[eventSnap.petID] else {
                    skipped += 1
                    continue
                }
                let event = PetEvent(
                    id: eventSnap.id, pet: pet,
                    eventType: eventSnap.eventType,
                    eventDate: eventSnap.eventDate,
                    title: eventSnap.title,
                    notify: eventSnap.notify, body: eventSnap.body,
                    sourceType: eventSnap.sourceType, isPinned: eventSnap.isPinned,
                    relatedPhotoID: eventSnap.relatedPhotoID)
                pet.events.append(event)
                importedEvents += 1
            }
            // 批量持久化事件（updatePet 内部 saveOrRollback）
            for pet in petByID.values {
                try petRepo.updatePet(pet)
            }

            // 3) 照片（关联宠物，写文件路径）
            // 跟踪被新增照片影响的宠物，末尾统一刷新 photoCount 缓存。
            var affectedPetIDs: Set<UUID> = []
            for photoSnap in metadata.photos {
                if Task.isCancelled { throw BackupServiceError.cancelled }
                // 预校验过滤的照片（重复 photoFileName 等）不插入 DB（P1 修复）。
                guard importablePhotoIDs.contains(photoSnap.id) else {
                    skipped += 1
                    continue
                }
                // 双重校验（安全网）：预校验已过滤，但 applyImport 独立调用时仍需保护
                if try photoRepo.getPhoto(id: photoSnap.id) != nil
                    || try photoRepo.getPhotoByOriginalURI(photoSnap.originalURI) != nil {
                    skipped += 1
                    continue
                }
                let pet = photoSnap.petID.flatMap { try petRepo.getPet(id: $0) }
                // uri 仅取本次实际写入的路径——文件未写入（缺失、文件名不安全、
                // 目标已存在但非本次写入）时留空。DB 是事实源，缺失文件按
                // auditOrphans 占位处理；不得绑定到未经校验的未知文件。
                let uri = photoPathByID[photoSnap.id] ?? ""
                let photo = Self.recreate(
                    photo: photoSnap, uri: uri, pet: pet)
                try photoRepo.insertPhoto(photo)
                insertedPhotos.append(photo)
                if let pet {
                    try photoRepo.assignPhoto(photo, to: pet)
                    affectedPetIDs.insert(pet.id)
                }
                importedPhotos += 1
            }

            // 4) 刷新受影响宠物的 photoCount 缓存。
            // assignPhoto 只更新关系不更新计数——合并到已有宠物时缓存会过期；
            // 新导入宠物的 photoCount 来自快照，部分照片被跳过时也会偏高。
            // 统一按实际 photos 关系重新计数，保证与 DB 一致。
            for petID in affectedPetIDs {
                if let pet = try petRepo.getPet(id: petID) {
                    try petRepo.refreshPhotoCount(for: pet)
                }
            }

            return RestoreResult(
                importedPets: importedPets,
                importedPhotos: importedPhotos,
                importedEvents: importedEvents,
                skipped: skipped)
        } catch {
            // 回滚已插入的记录，避免半成品残留
            for photo in insertedPhotos {
                try? photoRepo.deletePhoto(photo)
            }
            for pet in insertedPets {
                try? petRepo.deletePet(pet)
            }
            throw error
        }
    }

    // MARK: - Snapshot 转换辅助

    private struct ResolvedAvatar {
        let fileName: String
        let sourcePath: String
    }

    private static func resolveAvatar(
        for pet: Pet,
        fileExists: (String) -> Bool
    ) -> ResolvedAvatar? {
        guard !pet.avatarPath.isEmpty, fileExists(pet.avatarPath) else { return nil }
        let ext = fileExtension(for: pet.avatarPath)
        return ResolvedAvatar(fileName: "\(pet.id.uuidString).\(ext)", sourcePath: pet.avatarPath)
    }

    /// 校验外部备份中的文件名是否为安全的纯文件名（防路径穿越）。
    /// 合法文件名：非空、不含路径分隔符（`/` `\`）、非 `.` / `..`。
    /// photoFileName / avatarFileName 均由导出端生成（`{uuid}.{ext}`），
    /// 但恢复端面对的是外部文件，必须防御手写/篡改的备份包。
    private static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty
            && !name.contains("/")
            && !name.contains("\\")
            && name != "."
            && name != ".."
    }

    private static func snapshot(pet: Pet, avatarFileName: String?) -> PetSnapshot {
        PetSnapshot(
            id: pet.id,
            name: pet.name,
            species: Self.semanticSpecies(for: pet.species),
            breed: pet.breed,
            gender: Self.semanticGender(for: pet.gender),
            birthday: pet.birthday,
            adoptionDay: pet.adoptionDay,
            avatarFileName: avatarFileName,
            notes: pet.notes,
            photoCount: pet.photoCount,
            createdAt: pet.createdAt)
    }

    // MARK: - 枚举语义化（跨平台可读）

    /// 导出端：Species → 语义字符串（"cat" / "dog" / "unknown"）。
    private static func semanticSpecies(for species: Species) -> String {
        switch species {
        case .unknown: return "unknown"
        case .cat: return "cat"
        case .dog: return "dog"
        }
    }

    /// 导出端：Gender → 语义字符串（"male" / "female" / "unknown"）。
    private static func semanticGender(for gender: Gender) -> String {
        switch gender {
        case .unknown: return "unknown"
        case .male: return "male"
        case .female: return "female"
        }
    }

    /// 恢复端：语义字符串 → Species。
    /// 向后兼容：旧版备份包存数字字符串（"0"/"1"/"2"），自动回退解析。
    private static func parseSpecies(_ raw: String) -> Species {
        switch raw.lowercased() {
        case "cat", "1": return .cat
        case "dog", "2": return .dog
        default: return .unknown   // "unknown" / "0" / 未知值
        }
    }

    /// 恢复端：语义字符串 → Gender。
    /// 向后兼容：旧版备份包存数字字符串（"0"/"1"/"2"），自动回退解析。
    private static func parseGender(_ raw: String) -> Gender {
        switch raw.lowercased() {
        case "male", "1": return .male
        case "female", "2": return .female
        default: return .unknown   // "unknown" / "0" / 未知值
        }
    }

    private static func snapshot(photo: Photo, petID: UUID?, fileName: String) -> PhotoSnapshot {
        PhotoSnapshot(
            id: photo.id,
            originalURI: photo.originalURI,
            petID: petID,
            takenAt: photo.takenAt,
            latitude: photo.latitude,
            longitude: photo.longitude,
            placeName: photo.placeName,
            note: photo.note,
            isFavorite: photo.isFavorite,
            eventNotify: photo.eventNotify,
            width: photo.width,
            height: photo.height,
            fileSize: photo.fileSize,
            category: photo.category,
            subCategory: photo.subCategory,
            phash: photo.phash,
            qualityScore: photo.qualityScore,
            photoFileName: fileName,
            createdAt: photo.createdAt,
            sharpness: photo.sharpness,
            duplicateOf: photo.duplicateOf,
            isBest: photo.isBest)
    }

    private static func recreate(
        pet snap: PetSnapshot, sandboxDir: String,
        avatarOwnerByFileName: [String: UUID]
    ) -> Pet {
        let species = Self.parseSpecies(snap.species)
        let gender = Self.parseGender(snap.gender)
        let avatarPath: String
        // 只有头像首主宠物（owner == snap.id）才绑定头像路径；冲突的第二只宠物
        // avatarPath 为空，避免两宠物指向同一头像文件。
        if let avatarName = snap.avatarFileName,
           avatarOwnerByFileName[avatarName] == snap.id,
           Self.isSafeFileName(avatarName) {
            avatarPath = "\(sandboxDir)/\(avatarsDirName)/\(avatarName)"
        } else {
            avatarPath = ""
        }
        return Pet(
            id: snap.id,
            name: snap.name,
            species: species,
            breed: snap.breed,
            gender: gender,
            birthday: snap.birthday,
            adoptionDay: snap.adoptionDay,
            avatarPath: avatarPath,
            notes: snap.notes,
            featureData: nil,
            photoCount: snap.photoCount,
            createdAt: snap.createdAt,
            updatedAt: snap.createdAt)
    }

    private static func recreate(
        photo snap: PhotoSnapshot, uri: String, pet: Pet?
    ) -> Photo {
        Photo(
            id: snap.id,
            uri: uri,
            originalURI: snap.originalURI,
            pet: pet,
            takenAt: snap.takenAt,
            latitude: snap.latitude,
            longitude: snap.longitude,
            placeName: snap.placeName,
            thumbnailPath: "",
            note: snap.note,
            isFavorite: snap.isFavorite,
            eventNotify: snap.eventNotify,
            width: snap.width,
            height: snap.height,
            fileSize: snap.fileSize,
            category: snap.category,
            subCategory: snap.subCategory,
            createdAt: snap.createdAt,
            phash: snap.phash,
            sharpness: snap.sharpness,
            qualityScore: snap.qualityScore,
            duplicateOf: snap.duplicateOf,
            isBest: snap.isBest)
    }

    private static func fileExtension(for path: String) -> String {
        let ext = (path as NSString).pathExtension
        return ext.isEmpty ? "jpg" : ext.lowercased()
    }

    /// 取照片文件的真实大小（字节）：优先 stat 文件系统，失败时 fallback DB fileSize。
    /// 分卷决策与预估均基于此值，避免 DB fileSize 过期（0 或偏小）导致误判单卷。
    private static func actualSize(for photo: Photo, fileStorage: any FileStorage) -> Int64 {
        if let size = fileStorage.fileSize(at: photo.uri), size > 0 {
            return size
        }
        return photo.fileSize
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        // 包含时分秒，避免同一天多次导出覆盖同一文件名路径。
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}

// MARK: - 导出包内部模型

/// 导出收集结果：宠物/事件快照（全集）+ 照片快照（全集）+ 文件清单。
/// 分卷导出时按 volumePhotoGroups 分割照片，头像只在卷 1 包含。
private struct ExportBundle {
    let petSnaps: [PetSnapshot]
    let eventSnaps: [PetEventSnapshot]
    let photoSnaps: [PhotoSnapshot]
    /// 照片文件清单（zipPath → sourcePath → stat 真实字节数）。
    let photoFiles: [(zipPath: String, sourcePath: String, size: Int64)]
    /// 头像文件清单（每卷都包含，体积小）。
    let avatarFiles: [(zipPath: String, sourcePath: String, size: Int64)]
    /// 所有照片的预估总字节数（基于文件系统真实大小，stat 失败时 fallback DB fileSize）。
    let estimatedPhotoBytes: Int64
    /// 所有头像的预估总字节数（stat 真实大小）。
    let estimatedAvatarBytes: Int64
}

/// 预校验结果：确定哪些照片/宠物会被实际导入，以及头像首主映射。
struct PrevalidationResult: Sendable {
    let photos: Set<UUID>
    let pets: Set<UUID>
    /// 头像文件名 → 首个声明的宠物 id。只有 owner 绑定头像路径，
    /// 冲突的第二只宠物 avatarPath 为空。
    let avatarOwnerByFileName: [String: UUID]
}

/// 恢复时单个卷的读取结果（输入流保持打开，供后续文件拷贝使用）。
struct RestoreVolume {
    let manifest: BackupManifest
    let metadata: BackupMetadata
    let input: any ZipInputStream
    let recordMap: [String: ZipReader.ZipEntryRecord]
}

/// 线程安全进度计数器（流式导出闭包按序递增，供进度回调使用）。
/// writeArchive 顺序处理 entries，但闭包是 @Sendable，需保证计数器本身线程安全。
final class StreamProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    let total: Int

    init(total: Int) { self.total = total }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    @discardableResult
    func next() -> Int {
        lock.lock()
        _value += 1
        let result = _value
        lock.unlock()
        return result
    }
}

/// 导出总量守卫（线程安全累计器）。
///
/// `ZipWriter.writeArchive` 顺序处理 entries，但闭包是 @Sendable，累计器本身
/// 需保证线程安全。每次 `add` 累计字节数，超限时抛 `backupTooLarge` 阻止
/// 生成超 ZIP32 4GB 地址范围的不可恢复备份。
final class ExportSizeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var _total = 0
    private let maxBytes: Int

    init(maxBytes: Int) { self.maxBytes = maxBytes }

    func add(_ bytes: Int) throws {
        lock.lock()
        _total += bytes
        let total = _total
        lock.unlock()
        guard total <= maxBytes else {
            throw BackupServiceError.backupTooLarge
        }
    }
}
