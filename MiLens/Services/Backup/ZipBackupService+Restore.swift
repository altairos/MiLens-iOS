//  ZipBackupService+Restore —— 恢复（导入）链路。
//
//  从 ZipBackupService.swift 拆出（600 行规模守卫，见 docs/audit/remediation-plan.md
//  P1-1），代码逐字保持，行为零变更（ZipBackupServiceTests 往返/去重/多卷用例守护）。
//
//  恢复语义（与主文件头注释一致）：校验 manifest.schemaVersion 后合并导入；
//  宠物按 id、照片按 originalURI 去重跳过，绝不覆盖现有数据；原子性保证——
//  任意阶段失败时关闭输入流、清理已写文件、回滚已插入记录。

import Foundation
import MiLensKit

extension ZipBackupService {

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
                // 双重校验（安全网）：预校验已过滤，但 applyImport 独立调用时仍需保护。
                // try 不能出现在 || 右侧与 flatMap 闭包内，拆为显式语句再组合。
                let duplicateByID = try photoRepo.getPhoto(id: photoSnap.id) != nil
                let duplicateByURI = try photoRepo.getPhotoByOriginalURI(photoSnap.originalURI) != nil
                if duplicateByID || duplicateByURI {
                    skipped += 1
                    continue
                }
                var pet: Pet? = nil
                if let petID = photoSnap.petID {
                    pet = try petRepo.getPet(id: petID)
                }
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
}
