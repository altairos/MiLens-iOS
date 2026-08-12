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

        // 构建 ZipEntry：manifest + metadata + 全部文件
        await progress(BackupProgress(current: 0, total: bundle.files.count, phase: .copyingPhotos))
        var entries: [ZipEntry] = [
            ZipEntry(path: BackupConfig.manifestFileName,
                     data: try Self.encoder.encode(bundle.manifest)),
            ZipEntry(path: BackupConfig.metadataFileName,
                     data: try Self.encoder.encode(bundle.metadata)),
        ]

        var copied = 0
        for file in bundle.files {
            if fileStorage.fileExists(at: file.sourcePath) {
                let data = try await fileStorage.read(at: file.sourcePath)
                entries.append(ZipEntry(path: file.zipPath, data: data))
            }
            // 文件缺失：跳过（DB 是事实源；元数据已记录，恢复时按缺失处理）
            copied += 1
            await progress(BackupProgress(current: copied, total: bundle.files.count, phase: .copyingPhotos))
        }

        await progress(BackupProgress(current: 0, total: 1, phase: .compressing))
        let zipData = ZipWriter.archive(entries: entries)

        // 写临时文件供 ShareSheet 分享
        let fileName = "MiLens-Backup-\(Self.dateStamp()).\(BackupConfig.fileExtension)"
        let fileURL = URL(fileURLWithPath: temporaryDirectory)
            .appendingPathComponent(fileName)
        try await fileStorage.write(zipData, to: fileURL.path)

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

        // 事件：选中宠物的全部纪念事件
        var eventSnaps: [PetEventSnapshot] = []
        for pet in selectedPets {
            for event in pet.events {
                eventSnaps.append(PetEventSnapshot(
                    id: event.id, petID: pet.id,
                    eventType: event.eventType, eventDate: event.eventDate, title: event.title))
            }
        }

        let manifest = BackupManifest(
            schemaVersion: BackupConfig.currentSchemaVersion,
            appVersion: appVersion,
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

        let data: Data
        do {
            data = try await fileStorage.read(at: url.path)
        } catch {
            throw BackupServiceError.readFailed(error.localizedDescription)
        }

        let entries = try ZipReader.extract(data)

        await progress(RestoreProgress(current: 0, total: 1, phase: .validating))
        let entryMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.data) })

        guard let manifestData = entryMap[BackupConfig.manifestFileName] else {
            throw BackupServiceError.invalidFormat
        }
        let manifest = try Self.decoder.decode(BackupManifest.self, from: manifestData)
        guard manifest.schemaVersion == BackupConfig.currentSchemaVersion else {
            throw BackupServiceError.unsupportedVersion(
                found: manifest.schemaVersion,
                supported: BackupConfig.currentSchemaVersion)
        }

        guard let metadataData = entryMap[BackupConfig.metadataFileName] else {
            throw BackupServiceError.invalidFormat
        }
        let metadata = try Self.decoder.decode(BackupMetadata.self, from: metadataData)

        await progress(RestoreProgress(current: 0, total: metadata.photos.count, phase: .copyingFiles))
        // 先复制照片文件（IO），再 MainActor 合并元数据——合并是事实源写入，放最后。
        var photoPathByID: [UUID: String] = [:]
        var written = 0
        for photoSnap in metadata.photos {
            let zipPath = "\(BackupConfig.photosDirName)/\(photoSnap.photoFileName)"
            if let fileData = entryMap[zipPath] {
                let dest = "\(sandboxDir)/\(photoSnap.photoFileName)"
                try await fileStorage.write(fileData, to: dest)
                photoPathByID[photoSnap.id] = dest
            }
            written += 1
            await progress(RestoreProgress(current: written, total: metadata.photos.count, phase: .copyingFiles))
        }

        await progress(RestoreProgress(current: 0, total: 1, phase: .importingMetadata))
        let result = try await applyImport(metadata: metadata, photoPathByID: photoPathByID)

        await progress(RestoreProgress(current: 1, total: 1, phase: .done))
        return result
    }

    /// 合并导入元数据（MainActor）。同 id 宠物 / 同 originalURI 照片跳过，不覆盖。
    @MainActor
    private func applyImport(
        metadata: BackupMetadata,
        photoPathByID: [UUID: String]
    ) async throws -> RestoreResult {
        var importedPets = 0
        var importedPhotos = 0
        var importedEvents = 0
        var skipped = 0

        // 1) 宠物
        var petByID: [UUID: Pet] = [:]
        for petSnap in metadata.pets {
            if try petRepo.getPet(id: petSnap.id) != nil {
                skipped += 1
                continue
            }
            let pet = Self.recreate(pet: petSnap, sandboxDir: sandboxDir)
            try petRepo.insertPet(pet)
            petByID[petSnap.id] = pet
            importedPets += 1
        }

        // 2) 事件（关联到已导入或已存在的宠物）
        for eventSnap in metadata.petEvents {
            // 只为本次导入的宠物追加事件；已存在宠物的事件不重复导入
            guard let pet = petByID[eventSnap.petID] else {
                skipped += 1
                continue
            }
            let event = PetEvent(
                id: eventSnap.id, pet: pet,
                eventType: eventSnap.eventType,
                eventDate: eventSnap.eventDate,
                title: eventSnap.title)
            pet.events.append(event)
            importedEvents += 1
        }
        // 批量持久化事件（updatePet 内部 saveOrRollback）
        for pet in petByID.values {
            try petRepo.updatePet(pet)
        }

        // 3) 照片（关联宠物，写文件路径）
        for photoSnap in metadata.photos {
            if try photoRepo.getPhotoByOriginalURI(photoSnap.originalURI) != nil {
                skipped += 1
                continue
            }
            let pet = photoSnap.petID.flatMap { try petRepo.getPet(id: $0) }
            let uri = photoPathByID[photoSnap.id] ?? "\(sandboxDir)/\(photoSnap.photoFileName)"
            let photo = Self.recreate(
                photo: photoSnap, uri: uri, pet: pet)
            try photoRepo.insertPhoto(photo)
            if let pet {
                try photoRepo.assignPhoto(photo, to: pet)
            }
            importedPhotos += 1
        }

        return RestoreResult(
            importedPets: importedPets,
            importedPhotos: importedPhotos,
            importedEvents: importedEvents,
            skipped: skipped)
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

    private static func snapshot(pet: Pet, avatarFileName: String?) -> PetSnapshot {
        PetSnapshot(
            id: pet.id,
            name: pet.name,
            species: String(pet.species.rawValue),
            breed: pet.breed,
            gender: String(pet.gender.rawValue),
            birthday: pet.birthday,
            adoptionDay: pet.adoptionDay,
            avatarFileName: avatarFileName,
            notes: pet.notes,
            photoCount: pet.photoCount,
            createdAt: pet.createdAt)
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
            createdAt: photo.createdAt)
    }

    private static func recreate(pet snap: PetSnapshot, sandboxDir: String) -> Pet {
        let species = Species(rawValue: Int(snap.species)) ?? .unknown
        let gender = Gender(rawValue: Int(snap.gender)) ?? .unknown
        let avatarPath: String
        if let avatarName = snap.avatarFileName {
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
            sharpness: 0,
            qualityScore: snap.qualityScore,
            duplicateOf: nil,
            isBest: true)
    }

    private static func fileExtension(for path: String) -> String {
        let ext = (path as NSString).pathExtension
        return ext.isEmpty ? "jpg" : ext.lowercased()
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - 导出包内部模型

private struct ExportBundle {
    let manifest: BackupManifest
    let metadata: BackupMetadata
    let files: [(zipPath: String, sourcePath: String)]
}
