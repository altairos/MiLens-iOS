import XCTest
import MiLensKit
@testable import MiLens

/// ZipBackupService 导出/恢复测试（App 层，需 Mac 运行）。
///
/// 覆盖往返还原、合并去重（同 ID 宠物 / 同 originalURI 照片跳过）、版本校验、
/// 照片文件写回沙盒、Pro 可用性。使用 InMemory 仓储 + MockFileStorage，不依赖真实沙盒。
///
/// 注意：exportBackup 经 fileStorage.write 写临时备份文件，importBackup 经 fileStorage.read
/// 读取——往返用例必须让 source 与 target 共享同一 MockFileStorage，否则导入端读不到导出文件。
@MainActor
final class ZipBackupServiceTests: XCTestCase {

    /// 构造服务。fileStorage 可注入——往返用例共享同一实例。
    private func makeService(
        pets: [Pet] = [],
        photos: [Photo] = [],
        fileStorage: MockFileStorage = MockFileStorage()
    ) -> (service: ZipBackupService, petRepo: InMemoryPetRepository, photoRepo: InMemoryPhotoRepository, fs: MockFileStorage, sandboxDir: String) {
        let petRepo = InMemoryPetRepository(pets: pets)
        let photoRepo = InMemoryPhotoRepository(photos: photos)
        let sandboxDir = "/test-sandbox-\(UUID().uuidString)"
        let service = ZipBackupService(
            petRepo: petRepo,
            photoRepo: photoRepo,
            fileStorage: fileStorage,
            sandboxDir: sandboxDir,
            appVersion: "1.0.0",
            temporaryDirectory: "/test-tmp-\(UUID().uuidString)")
        return (service, petRepo, photoRepo, fileStorage, sandboxDir)
    }

    // MARK: - 可用性

    func testIsAvailableTrue() {
        let (service, _, _, _, _) = makeService()
        XCTAssertTrue(service.isAvailable, "ZipBackupService 必须声明可用（替换 UnavailableBackupService）")
    }

    // MARK: - 导出

    func testExportProducesNonEmptyBackupFile() async throws {
        let pet = Pet(name: "小橘", species: .cat, gender: .male)
        let (service, _, _, fs, _) = makeService(pets: [pet])
        let result = try await service.exportBackup(petIDs: nil, progress: { _ in })

        XCTAssertTrue(fs.fileExists(at: result.fileURL.path), "导出后临时文件必须存在")
        let data = try await fs.read(at: result.fileURL.path)
        XCTAssertFalse(data.isEmpty, "备份文件不得为空")
        XCTAssertEqual(result.manifest.petCount, 1)
        XCTAssertEqual(result.manifest.schemaVersion, BackupConfig.currentSchemaVersion)
    }

    func testExportIncludesPhotoFilesAndManifest() async throws {
        let pet = Pet(name: "豆豆", species: .dog)
        let photo = Photo(uri: "/src/a.jpg", originalURI: "L0/001", pet: pet)
        let (service, _, _, fs, _) = makeService(pets: [pet], photos: [photo])
        fs.preset(Data([0x01, 0x02, 0x03]), at: "/src/a.jpg")

        let result = try await service.exportBackup(petIDs: nil, progress: { _ in })
        let zipData = try await fs.read(at: result.fileURL.path)
        let entries = try ZipReader.extract(zipData)
        let paths = Set(entries.map(\.path))

        XCTAssertTrue(paths.contains(BackupConfig.manifestFileName), "备份包须含 manifest.json")
        XCTAssertTrue(paths.contains(BackupConfig.metadataFileName), "备份包须含 metadata.json")
        let photoEntry = entries.first { $0.path.hasPrefix("\(BackupConfig.photosDirName)/") }
        XCTAssertNotNil(photoEntry, "备份包须含照片文件")
        XCTAssertEqual(photoEntry?.data, Data([0x01, 0x02, 0x03]))
    }

    // MARK: - 往返还原

    func testExportImportRoundTripRestoresData() async throws {
        // 源库：1 宠物 + 1 事件 + 1 照片（source 与 target 共享 fs）
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat, gender: .male, notes: "橘猫")
        let event = PetEvent(pet: pet, eventType: "birthday", eventDate: Date(), title: "生日")
        pet.events.append(event)
        let photo = Photo(uri: "/src/p1.jpg", originalURI: "L0/001", pet: pet, note: "可爱")
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo], fileStorage: sharedFS)
        sharedFS.preset(Data("jpeg-bytes".utf8), at: "/src/p1.jpg")

        let result = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 目标空库恢复（共享 fs 才能读到导出的备份文件）
        let (target, tPetRepo, tPhotoRepo, tFs, _) = makeService(fileStorage: sharedFS)
        let restoreResult = try await target.importBackup(from: result.fileURL, progress: { _ in })

        XCTAssertEqual(restoreResult.importedPets, 1)
        XCTAssertEqual(restoreResult.importedPhotos, 1)
        XCTAssertEqual(restoreResult.importedEvents, 1)
        XCTAssertEqual(restoreResult.skipped, 0)

        let restoredPets = try tPetRepo.getAllPets()
        XCTAssertEqual(restoredPets.first?.name, "小橘")
        XCTAssertEqual(restoredPets.first?.notes, "橘猫")
        XCTAssertEqual(restoredPets.first?.events.count, 1, "事件须随宠物还原")

        let restoredPhotos = try tPhotoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(restoredPhotos.first?.originalURI, "L0/001")
        XCTAssertEqual(restoredPhotos.first?.note, "可爱")
        // 照片文件写回目标沙盒
        let writtenPath = restoredPhotos.first?.uri ?? ""
        XCTAssertTrue(tFs.fileExists(at: writtenPath), "恢复后照片文件须写回沙盒")
        XCTAssertEqual(try await tFs.read(at: writtenPath), Data("jpeg-bytes".utf8))
    }

    // MARK: - 合并去重（不覆盖现有数据）

    func testImportSkipsExistingPetByID() async throws {
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let (source, _, _, _, _) = makeService(pets: [pet], fileStorage: sharedFS)
        let backup = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 目标库已有同 id 宠物（不同名字验证不被覆盖）
        let existing = Pet(id: pet.id, name: "已存在", species: .dog)
        let (target, tPetRepo, _, _, _) = makeService(pets: [existing], fileStorage: sharedFS)

        let result = try await target.importBackup(from: backup.fileURL, progress: { _ in })

        XCTAssertEqual(result.importedPets, 0)
        XCTAssertEqual(result.skipped, 1)
        let pets = try tPetRepo.getAllPets()
        XCTAssertEqual(pets.count, 1)
        XCTAssertEqual(pets.first?.name, "已存在", "现有数据不得被覆盖")
    }

    func testImportSkipsExistingPhotoByOriginalURI() async throws {
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let photo = Photo(uri: "/src/a.jpg", originalURI: "L0/001", pet: pet)
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo], fileStorage: sharedFS)
        sharedFS.preset(Data([0x01]), at: "/src/a.jpg")
        let backup = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 目标库已有相同 originalURI 的照片
        let targetPet = Pet(id: pet.id, name: "小橘", species: .cat)
        let existingPhoto = Photo(uri: "/existing/a.jpg", originalURI: "L0/001", pet: targetPet)
        let (target, _, tPhotoRepo, _, _) = makeService(pets: [targetPet], photos: [existingPhoto], fileStorage: sharedFS)

        let result = try await target.importBackup(from: backup.fileURL, progress: { _ in })

        XCTAssertEqual(result.importedPhotos, 0, "相同 originalURI 照片须跳过")
        let photos = try tPhotoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos.first?.uri, "/existing/a.jpg", "现有照片不得被覆盖")
    }

    // MARK: - 版本校验

    func testImportUnsupportedVersionThrows() async throws {
        let sharedFS = MockFileStorage()
        let (source, _, _, _, _) = makeService(fileStorage: sharedFS)
        let backup = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 篡改 manifest 的 schemaVersion 为不兼容值
        let zipData = try await sharedFS.read(at: backup.fileURL.path)
        var entries = try ZipReader.extract(zipData)
        let manifestIdx = entries.firstIndex { $0.path == BackupConfig.manifestFileName }!
        let tampered = BackupManifest(
            schemaVersion: BackupConfig.currentSchemaVersion + 1,
            appVersion: "9.9.9",
            exportDate: Date(),
            photoCount: 0,
            petCount: 0)
        entries[manifestIdx] = ZipEntry(path: BackupConfig.manifestFileName, data: JSONEncoder().encode(tampered))
        let tamperedZip = ZipWriter.archive(entries: entries)
        try await sharedFS.write(tamperedZip, to: backup.fileURL.path)

        let (target, _, _, _, _) = makeService(fileStorage: sharedFS)
        XCTAssertThrowsError(try await target.importBackup(from: backup.fileURL, progress: { _ in })) { error in
            guard case .unsupportedVersion = error as? BackupServiceError else {
                return XCTFail("应抛 unsupportedVersion，实际：\(error)")
            }
        }
    }

    func testImportInvalidFormatThrows() async throws {
        let sharedFS = MockFileStorage()
        let (source, _, _, _, _) = makeService(fileStorage: sharedFS)
        let backup = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 删除 manifest，制造无效格式
        let zipData = try await sharedFS.read(at: backup.fileURL.path)
        let entries = try ZipReader.extract(zipData).filter { $0.path != BackupConfig.manifestFileName }
        try await sharedFS.write(ZipWriter.archive(entries: entries), to: backup.fileURL.path)

        let (target, _, _, _, _) = makeService(fileStorage: sharedFS)
        XCTAssertThrowsError(try await target.importBackup(from: backup.fileURL, progress: { _ in })) { error in
            XCTAssertEqual(error as? BackupServiceError, .invalidFormat)
        }
    }
}
