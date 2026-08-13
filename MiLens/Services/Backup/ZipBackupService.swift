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

final class ZipBackupService: BackupService, @unchecked Sendable {

    private let petRepo: any PetRepositoryProtocol
    private let photoRepo: any PhotoRepositoryProtocol
    private let fileStorage: any FileStorage
    private let sandboxDir: String
    private let appVersion: String
    private let temporaryDirectory: String

    init(petRepo: any PetRepositoryProtocol,
         photoRepo: any PhotoRepositoryProtocol,
         fileStorage: any FileStorage,
         sandboxDir: String,
         appVersion: String,
         temporaryDirectory: String = NSTemporaryDirectory()) {
        self.petRepo = petRepo
        self.photoRepo = photoRepo
        self.fileStorage = fileStorage
        self.sandboxDir = sandboxDir
        self.appVersion = appVersion
        self.temporaryDirectory = temporaryDirectory
    }

    var isAvailable: Bool { true }

    // MARK: - 预估

    /// 预估将导出的内容规模（仅统计计数，不读取照片文件、不打包）。
    /// 与 collectExportBundle 同样的 petIDs 过滤语义，保证预估与实际导出一致。
    func estimateBackup(petIDs: [UUID]?) async throws -> BackupEstimate {
        let allPets = try petRepo.getAllPets()
        let selectedPets: [Pet]
        if let petIDs, !petIDs.isEmpty {
            let wanted = Set(petIDs)
            selectedPets = allPets.filter { wanted.contains($0.id) }
        } else {
            selectedPets = allPets
        }

        let photoCount: Int
        if petIDs != nil {
            photoCount = try selectedPets.reduce(0) { acc, pet in
                acc + (try photoRepo.getPhotosByPet(pet)).count
            }
        } else {
            photoCount = try photoRepo.countAllPhotos()
        }
        return BackupEstimate(petCount: selectedPets.count, photoCount: photoCount)
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

        // 流式导出：逐 entry 读取数据（闭包）→ 算 CRC → 写 local header + data → 释放。
        // 峰值内存≈最大单个 entry（单张照片），不再一次性加载全部照片数据。
        await progress(BackupProgress(current: 0, total: bundle.files.count, phase: .copyingPhotos))

        let manifestData = try Self.encoder.encode(bundle.manifest)
        let metadataData = try Self.encoder.encode(bundle.metadata)

        var streamEntries: [ZipStreamEntry] = [
            ZipStreamEntry(path: BackupConfig.manifestFileName) { manifestData },
            ZipStreamEntry(path: BackupConfig.metadataFileName) { metadataData },
        ]

        // 进度计数器（writeArchive 顺序处理 entries，counter 顺序递增）
        let progressCounter = StreamProgressCounter(total: bundle.files.count)
        // 导出总量守卫：防止大图库生成超 ZIP32 4GB 地址范围的不可恢复备份。
        // manifest/metadata 体积极小，此处主要累计照片数据。
        let sizeGuard = ExportSizeGuard(maxBytes: BackupConfig.maxTotalExportSizeBytes)

        for file in bundle.files {
            guard fileStorage.fileExists(at: file.sourcePath) else {
                // 文件缺失：跳过（DB 是事实源；元数据已记录，恢复时按缺失处理）
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
                // 单文件大小检查
                guard data.count <= BackupConfig.maxSingleEntrySizeBytes else {
                    throw BackupServiceError.backupTooLarge
                }
                // 总量检查（含 header/CD 开销的近似余量已留在 maxTotalExportSizeBytes 内）
                try sizeGuard.add(data.count)
                let current = progressCounter.next()
                await progress(BackupProgress(current: current, total: progressCounter.total, phase: .copyingPhotos))
                return data
            })
        }

        // 条目数检查（总量上限由 ExportSizeGuard 在逐条目累计时守护）
        guard streamEntries.count <= BackupConfig.maxEntryCount else {
            throw BackupServiceError.backupTooLarge
        }

        // 写临时文件供 ShareSheet 分享。
        // 时间戳 + UUID：同秒内连续导出不会得到相同路径，避免覆盖。
        let fileName = "MiLens-Backup-\(Self.dateStamp())-\(UUID().uuidString.prefix(8)).\(BackupConfig.fileExtension)"
        let fileURL = URL(fileURLWithPath: temporaryDirectory)
            .appendingPathComponent(fileName)

        await progress(BackupProgress(current: 0, total: 1, phase: .compressing))
        let output = try await fileStorage.makeOutputStream(at: fileURL.path)
        do {
            try await ZipWriter.writeArchive(entries: streamEntries, to: output)
            try await output.close()
        } catch {
            try? await output.close()
            throw error
        }

        await progress(BackupProgress(current: 1, total: 1, phase: .done))
        return BackupResult(fileURL: fileURL, manifest: bundle.manifest, metadata: bundle.metadata)
    }

    /// 收集元数据快照与待打包文件清单（MainActor——SwiftData ModelContext 隔离）。
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
        var files: [(zipPath: String, sourcePath: String)] = []

        for pet in selectedPets {
            let avatar = Self.resolveAvatar(for: pet, fileExists: { fileStorage.fileExists(at: $0) })
            petSnaps.append(Self.snapshot(pet: pet, avatarFileName: avatar?.fileName))
            if let avatar {
                files.append((zipPath: "\(avatarsDirName)/\(avatar.fileName)",
                              sourcePath: avatar.sourcePath))
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
        for photo in photos {
            let fileName = "\(photo.id.uuidString).\(Self.fileExtension(for: photo.uri))"
            photoSnaps.append(Self.snapshot(photo: photo, petID: photo.pet?.id, fileName: fileName))
            files.append((zipPath: "\(BackupConfig.photosDirName)/\(fileName)",
                          sourcePath: photo.uri))
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

        let manifest = BackupManifest(
            schemaVersion: BackupConfig.currentSchemaVersion,
            appVersion: appVersion,
            platform: "ios",
            exportDate: Date(),
            photoCount: photoSnaps.count,
            petCount: petSnaps.count)

        let metadata = BackupMetadata(pets: petSnaps, photos: photoSnaps, petEvents: eventSnaps)
        return ExportBundle(manifest: manifest, metadata: metadata, files: files)
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
        from url: URL,
        progress: @Sendable @MainActor (RestoreProgress) -> Void
    ) async throws -> RestoreResult {

        await progress(RestoreProgress(current: 0, total: 1, phase: .decompressing))
        // security-scoped resource：DocumentPicker 选择的 iCloud/Files 文件需先获取访问权。
        // startAccessing 返回 false 表示无需（本地沙盒文件），defer 守卫避免误 stop。
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }

        // 流式输入：不一次性加载整个 ZIP，用 InputStream 随机访问。
        let input: any ZipInputStream
        do {
            input = try await fileStorage.makeInputStream(at: url.path)
        } catch {
            throw BackupServiceError.readFailed(error.localizedDescription)
        }

        // 原子性保证：跟踪本次写入的所有文件路径，任意阶段失败时统一清理，
        // 避免文件已写入但数据库未完成、或数据库只恢复了一部分留下孤儿文件。
        var writtenPaths: [String] = []

        do {
            // 流式读取 central directory：只读索引，不加载条目数据
            let records = try await ZipReader.readCentralDirectory(from: input)

            // 基于 records 做大小校验（不加载数据本体）
            try Self.validateRecords(
                records,
                maxTotalUncompressedSize: BackupConfig.maxBackupSizeBytes,
                maxEntryCount: BackupConfig.maxEntryCount,
                maxSingleEntrySize: BackupConfig.maxSingleEntrySizeBytes)

            // 构建路径 → record 映射（保留首次出现，静默忽略重复，不崩溃）
            var recordMap: [String: ZipReader.ZipEntryRecord] = [:]
            for record in records {
                if recordMap[record.path] == nil {
                    recordMap[record.path] = record
                }
            }

            await progress(RestoreProgress(current: 0, total: 1, phase: .validating))

            // 读 manifest + metadata（小条目，直接读入内存）
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

            // 预校验（MainActor）：在写文件前确定哪些照片/宠物会被实际导入。
            let prevalidated = try await prevalidateImport(metadata: metadata)

            await progress(RestoreProgress(current: 0, total: metadata.photos.count, phase: .copyingFiles))
            var photoPathByID: [UUID: String] = [:]
            var written = 0

            // 流式拷贝照片文件：分块读写（峰值≈64KB），不一次性加载全部条目数据。
            // processedPhotoIDs 防止备份内部重复 id 的第二条也写文件
            //（prevalidated.photos 是 Set<UUID>，重复 id 只存一份，
            // 但遍历 metadata.photos 会遇到两条同 id 记录）。
            var processedPhotoIDs: Set<UUID> = []
            for photoSnap in metadata.photos {
                if Task.isCancelled { throw BackupServiceError.cancelled }
                guard prevalidated.photos.contains(photoSnap.id) else {
                    written += 1
                    await progress(RestoreProgress(current: written, total: metadata.photos.count, phase: .copyingFiles))
                    continue
                }
                // 备份内部重复 id → 只为首条写文件（第二条由 applyImport 的 DB 检查跳过）
                guard !processedPhotoIDs.contains(photoSnap.id) else {
                    written += 1
                    await progress(RestoreProgress(current: written, total: metadata.photos.count, phase: .copyingFiles))
                    continue
                }
                processedPhotoIDs.insert(photoSnap.id)
                // 路径穿越防御：拒绝非纯文件名
                if Self.isSafeFileName(photoSnap.photoFileName) {
                    let zipPath = "\(BackupConfig.photosDirName)/\(photoSnap.photoFileName)"
                    if let record = recordMap[zipPath] {
                        let dest = "\(sandboxDir)/\(photoSnap.photoFileName)"
                        // 目标已存在时不覆盖，且不绑定到该未知文件——
                        // 先前文件的内容不可信（可能是上一轮恢复残留或跨平台冲突），
                        // 将 uri 留空由 DB 事实源 + auditOrphans 占位处理。
                        if !fileStorage.fileExists(at: dest) {
                            let output = try await fileStorage.makeOutputStream(at: dest)
                            // 创建输出流后立即记录路径：copyEntry 中途失败时 output.close()
                            // 仍会保留已写入的部分文件，必须纳入清理列表避免孤儿残留。
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
                            // 仅在本次实际写入后才记录路径，确保 DB 绑定到可信内容。
                            photoPathByID[photoSnap.id] = dest
                        }
                    }
                }
                written += 1
                await progress(RestoreProgress(current: written, total: metadata.photos.count, phase: .copyingFiles))
            }

            // 流式拷贝头像文件
            for petSnap in metadata.pets {
                if Task.isCancelled { throw BackupServiceError.cancelled }
                guard prevalidated.pets.contains(petSnap.id),
                      let avatarName = petSnap.avatarFileName,
                      Self.isSafeFileName(avatarName) else { continue }
                let zipPath = "\(avatarsDirName)/\(avatarName)"
                if let record = recordMap[zipPath] {
                    let dest = "\(sandboxDir)/\(avatarsDirName)/\(avatarName)"
                    if !fileStorage.fileExists(at: dest) {
                        let output = try await fileStorage.makeOutputStream(at: dest)
                        // 创建输出流后立即记录路径（与照片路径一致，防半截文件残留）。
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

            // 所有文件读取完成，关闭输入流后再合并元数据
            try? await input.close()

            await progress(RestoreProgress(current: 0, total: 1, phase: .importingMetadata))
            let result = try await applyImport(metadata: metadata, photoPathByID: photoPathByID)

            await progress(RestoreProgress(current: 1, total: 1, phase: .done))
            return result
        } catch {
            // 关闭输入流 + 清理本次写入的文件，避免孤儿残留
            try? await input.close()
            for path in writtenPaths {
                try? await fileStorage.removeItem(at: path)
            }
            throw error
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
    @MainActor
    private func prevalidateImport(
        metadata: BackupMetadata
    ) async throws -> (photos: Set<UUID>, pets: Set<UUID>) {
        var importablePets: Set<UUID> = []
        var seenPetIDs: Set<UUID> = []
        for petSnap in metadata.pets {
            // 备份内部重复 pet id → 只导入首条
            guard !seenPetIDs.contains(petSnap.id) else { continue }
            seenPetIDs.insert(petSnap.id)
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
        return (importablePhotos, importablePets)
    }

    /// 合并导入元数据（MainActor）。同 id 宠物 / 同 id 或同 originalURI 照片跳过，不覆盖。
    /// 原子性：任意阶段失败时回滚已插入的记录，避免半成品残留。
    @MainActor
    private func applyImport(
        metadata: BackupMetadata,
        photoPathByID: [UUID: String]
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
                let pet = Self.recreate(pet: petSnap, sandboxDir: sandboxDir)
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

    private static func recreate(pet snap: PetSnapshot, sandboxDir: String) -> Pet {
        let species = Self.parseSpecies(snap.species)
        let gender = Self.parseGender(snap.gender)
        let avatarPath: String
        if let avatarName = snap.avatarFileName,
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

private struct ExportBundle {
    let manifest: BackupManifest
    let metadata: BackupMetadata
    let files: [(zipPath: String, sourcePath: String)]
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
