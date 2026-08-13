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

    // MARK: - 预估

    func testEstimateMatchesFullLibrary() async throws {
        let pet = Pet(name: "小橘", species: .cat)
        let photos = (0..<3).map { i in
            Photo(uri: "/src/\(i).jpg", originalURI: "L0/00\(i)", pet: pet)
        }
        let (service, _, _, _, _) = makeService(pets: [pet], photos: photos)

        let estimate = try await service.estimateBackup(petIDs: nil)

        XCTAssertEqual(estimate.petCount, 1)
        XCTAssertEqual(estimate.photoCount, 3, "预估照片数须等于全库照片数")
    }

    func testEstimateMatchesActualExportManifest() async throws {
        // 预估计数须与实际导出的 manifest 一致（核心不变量：预估不能骗用户）。
        let pet1 = Pet(name: "小橘", species: .cat)
        let pet2 = Pet(name: "豆豆", species: .dog)
        let photos = [
            Photo(uri: "/a.jpg", originalURI: "L0/001", pet: pet1),
            Photo(uri: "/b.jpg", originalURI: "L0/002", pet: pet2),
        ]
        let (service, _, _, _, _) = makeService(pets: [pet1, pet2], photos: photos)

        let estimate = try await service.estimateBackup(petIDs: nil)
        let result = try await service.exportBackup(petIDs: nil, progress: { _ in })

        XCTAssertEqual(estimate.petCount, result.manifest.petCount, "预估宠物数须与导出一致")
        XCTAssertEqual(estimate.photoCount, result.manifest.photoCount, "预估照片数须与导出一致")
    }

    func testEstimateWithPetIDsFiltersPhotos() async throws {
        let pet1 = Pet(name: "小橘", species: .cat)
        let pet2 = Pet(name: "豆豆", species: .dog)
        let photos = [
            Photo(uri: "/a.jpg", originalURI: "L0/001", pet: pet1),
            Photo(uri: "/b.jpg", originalURI: "L0/002", pet: pet2),
            Photo(uri: "/c.jpg", originalURI: "L0/003", pet: pet2),
        ]
        let (service, _, _, _, _) = makeService(pets: [pet1, pet2], photos: photos)

        let estimate = try await service.estimateBackup(petIDs: [pet2.id])

        XCTAssertEqual(estimate.petCount, 1, "petIDs 过滤后只统计选中宠物")
        XCTAssertEqual(estimate.photoCount, 2, "petIDs 过滤后只统计选中宠物的照片")
    }

    func testEstimateEmptyLibrary() async throws {
        let (service, _, _, _, _) = makeService()
        let estimate = try await service.estimateBackup(petIDs: nil)
        XCTAssertEqual(estimate.petCount, 0)
        XCTAssertEqual(estimate.photoCount, 0)
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

    // MARK: - PetEvent 字段完整性（P1 修复）

    func testRoundTripPreservesPetEventAllFields() async throws {
        // 验证 notify/body/sourceType/isPinned/relatedPhotoID 全部存活往返
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let relatedPhotoID = UUID()
        let event = PetEvent(
            pet: pet, eventType: "memory", eventDate: Date(timeIntervalSince1970: 123456),
            title: "第一次回家", notify: false, body: "那天她特别紧张", 
            sourceType: "user", isPinned: true, relatedPhotoID: relatedPhotoID)
        pet.events.append(event)
        let (source, _, _, _, _) = makeService(pets: [pet], fileStorage: sharedFS)

        let result = try await source.exportBackup(petIDs: nil, progress: { _ in })

        let (target, tPetRepo, _, _, _) = makeService(fileStorage: sharedFS)
        _ = try await target.importBackup(from: result.fileURL, progress: { _ in })

        let restoredEvent = try tPetRepo.getAllPets().first?.events.first
        XCTAssertNotNil(restoredEvent)
        XCTAssertEqual(restoredEvent?.notify, false, "notify 须保留")
        XCTAssertEqual(restoredEvent?.body, "那天她特别紧张", "body 须保留")
        XCTAssertEqual(restoredEvent?.sourceType, "user", "sourceType 须保留")
        XCTAssertEqual(restoredEvent?.isPinned, true, "isPinned 须保留")
        XCTAssertEqual(restoredEvent?.relatedPhotoID, relatedPhotoID, "relatedPhotoID 须保留")
    }

    // MARK: - 照片分析字段完整性（P2 修复）

    func testRoundTripPreservesPhotoAnalysisFields() async throws {
        // 验证 sharpness / duplicateOf / isBest 全部存活往返
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let dupOf = UUID()
        let photo = Photo(
            uri: "/src/p1.jpg", originalURI: "L0/001", pet: pet,
            phash: "a1b2c3d4e5f6a7b8",
            sharpness: 123.45,
            qualityScore: 0.87,
            duplicateOf: dupOf,
            isBest: false)
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo], fileStorage: sharedFS)
        sharedFS.preset(Data("jpeg-bytes".utf8), at: "/src/p1.jpg")

        let result = try await source.exportBackup(petIDs: nil, progress: { _ in })

        let (target, _, tPhotoRepo, _, _) = makeService(fileStorage: sharedFS)
        _ = try await target.importBackup(from: result.fileURL, progress: { _ in })

        let restoredPhoto = try tPhotoRepo.getPhotosPage(offset: 0, limit: 10).first
        XCTAssertNotNil(restoredPhoto)
        XCTAssertEqual(restoredPhoto?.sharpness, 123.45, "sharpness 须保留")
        XCTAssertEqual(restoredPhoto?.qualityScore, 0.87, "qualityScore 须保留")
        XCTAssertEqual(restoredPhoto?.duplicateOf, dupOf, "duplicateOf 须保留")
        XCTAssertEqual(restoredPhoto?.isBest, false, "isBest 须保留")
        XCTAssertEqual(restoredPhoto?.phash, "a1b2c3d4e5f6a7b8", "phash 须保留")
    }

    func testOldPhotoBackupWithoutAnalysisFieldsDecodesWithDefaults() throws {
        // 旧版备份包缺 sharpness/duplicateOf/isBest 字段，
        // 解码须回退为 Photo 默认值而非抛错。
        let oldFormatJSON = """
        {"id":"\(UUID().uuidString)","originalURI":"L0/001","petID":null,
         "takenAt":null,"latitude":0,"longitude":0,"placeName":"",
         "note":"","isFavorite":false,"eventNotify":true,
         "width":1080,"height":1920,"fileSize":0,
         "category":"pet_photo","subCategory":"other",
         "phash":"","qualityScore":0,
         "photoFileName":"test.jpg","createdAt":"2024-01-01T00:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snap = try decoder.decode(PhotoSnapshot.self, from: Data(oldFormatJSON.utf8))

        XCTAssertEqual(snap.sharpness, 0, "缺省 sharpness 回退为 0")
        XCTAssertNil(snap.duplicateOf, "缺省 duplicateOf 回退为 nil")
        XCTAssertEqual(snap.isBest, true, "缺省 isBest 回退为 true")
    }

    // MARK: - PetEvent 字段完整性（P1 修复）

    func testOldBackupWithoutNewFieldsDecodesWithDefaults() throws {
        // 旧版备份包缺 notify/body/sourceType/isPinned/relatedPhotoID 字段，
        // 解码须回退为 PetEvent 默认值而非抛错。
        let oldFormatJSON = """
        {"id":"\(UUID().uuidString)","petID":"\(UUID().uuidString)",
         "eventType":"birthday","eventDate":"2024-01-01T00:00:00Z","title":"生日"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snap = try decoder.decode(PetEventSnapshot.self, from: Data(oldFormatJSON.utf8))

        XCTAssertEqual(snap.notify, true, "缺省 notify 回退为 true")
        XCTAssertEqual(snap.body, "", "缺省 body 回退为空字符串")
        XCTAssertEqual(snap.sourceType, "system", "缺省 sourceType 回退为 system")
        XCTAssertEqual(snap.isPinned, false, "缺省 isPinned 回退为 false")
        XCTAssertNil(snap.relatedPhotoID, "缺省 relatedPhotoID 回退为 nil")
    }

    // MARK: - 原子性（P1 修复：失败时清理文件）

    func testRestoreCleansUpFilesOnDBFailure() async throws {
        // 使用会抛错的仓储模拟 DB 失败，验证恢复失败后文件被清理
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let photo = Photo(uri: "/src/a.jpg", originalURI: "L0/001", pet: pet)
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo], fileStorage: sharedFS)
        sharedFS.preset(Data([0x01, 0x02]), at: "/src/a.jpg")

        let result = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 目标库使用会抛错的 petRepo（模拟 DB 写入失败）
        let failingRepo = ThrowingPetRepository()
        let sandboxDir = "/restore-sandbox-\(UUID().uuidString)"
        let target = ZipBackupService(
            petRepo: failingRepo,
            photoRepo: InMemoryPhotoRepository(),
            fileStorage: sharedFS,
            sandboxDir: sandboxDir,
            appVersion: "1.0.0",
            temporaryDirectory: "/test-tmp-\(UUID().uuidString)")

        do {
            _ = try await target.importBackup(from: result.fileURL, progress: { _ in })
            XCTFail("DB 失败时应抛错")
        } catch {
            // 预期抛错——验证文件已清理
        }

        // 恢复失败后，沙盒目录下不应残留本次写入的照片文件
        let writtenFiles = sharedFS.listFiles(in: sandboxDir)
        XCTAssertEqual(writtenFiles.count, 0, "恢复失败时写入的文件须全部清理")
    }

    func testRestoreRollsBackInsertedRecordsOnLateFailure() async throws {
        // ThrowingPetRepository 在 insertPet 立即抛错，无法覆盖「部分记录已入库后再失败」
        // 的回滚分支。本例用 PartiallyThrowingPetRepository：insertPet 正常，updatePet
        // 抛错（模拟事件持久化阶段失败）。此时宠物已 insertPet 成功（insertedPets 非空），
        // applyImport catch 须 deletePet 回滚已插入记录，importBackup catch 须清理文件。
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let event = PetEvent(pet: pet, eventType: "birthday", eventDate: Date(), title: "生日")
        pet.events.append(event)
        let photo = Photo(uri: "/src/a.jpg", originalURI: "L0/001", pet: pet)
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo], fileStorage: sharedFS)
        sharedFS.preset(Data([0x01, 0x02]), at: "/src/a.jpg")

        let result = try await source.exportBackup(petIDs: nil, progress: { _ in })

        let failingRepo = PartiallyThrowingPetRepository()
        let sandboxDir = "/rollback-sandbox-\(UUID().uuidString)"
        let target = ZipBackupService(
            petRepo: failingRepo,
            photoRepo: InMemoryPhotoRepository(),
            fileStorage: sharedFS,
            sandboxDir: sandboxDir,
            appVersion: "1.0.0",
            temporaryDirectory: "/test-tmp-\(UUID().uuidString)")

        do {
            _ = try await target.importBackup(from: result.fileURL, progress: { _ in })
            XCTFail("事件持久化（updatePet）失败时应抛错")
        } catch {
            // 预期抛错
        }

        // 已插入的宠物记录须被回滚（applyImport catch → deletePet），不留半成品
        XCTAssertTrue(
            try failingRepo.allPets.isEmpty,
            "事件持久化失败时已 insertPet 成功的宠物记录须回滚删除")
        // 已写入的照片文件须被清理（importBackup catch → removeItem）
        XCTAssertTrue(
            sharedFS.listFiles(in: sandboxDir).isEmpty,
            "恢复失败时已写入的照片文件须清理，避免孤儿文件")
    }

    // MARK: - 头像还原

    func testExportImportRestoresAvatarFile() async throws {
        // 头像导出写入 avatars/ 目录，恢复须写回沙盒，否则 avatarPath 悬空。
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat, gender: .male, avatarPath: "/src/avatar.jpg")
        let (source, _, _, _, _) = makeService(pets: [pet], fileStorage: sharedFS)
        sharedFS.preset(Data("avatar-bytes".utf8), at: "/src/avatar.jpg")

        let result = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 备份包须含头像条目
        let zipData = try await sharedFS.read(at: result.fileURL.path)
        let entries = try ZipReader.extract(zipData)
        let avatarEntry = entries.first { $0.path.hasPrefix("avatars/") }
        XCTAssertNotNil(avatarEntry, "备份包须含头像文件")
        XCTAssertEqual(avatarEntry?.data, Data("avatar-bytes".utf8))

        // 目标空库恢复（共享 fs 才能读到导出的备份文件）
        let (target, tPetRepo, _, tFs, sandboxDir) = makeService(fileStorage: sharedFS)
        let restoreResult = try await target.importBackup(from: result.fileURL, progress: { _ in })
        XCTAssertEqual(restoreResult.importedPets, 1)

        let restoredPet = try tPetRepo.getAllPets().first!
        XCTAssertFalse(restoredPet.avatarPath.isEmpty, "恢复后 avatarPath 不得为空")
        XCTAssertTrue(tFs.fileExists(at: restoredPet.avatarPath), "恢复后头像文件须写回沙盒")
        XCTAssertTrue(restoredPet.avatarPath.hasPrefix("\(sandboxDir)/avatars/"),
                      "avatarPath 须指向沙盒 avatars 目录")
        XCTAssertEqual(try await tFs.read(at: restoredPet.avatarPath), Data("avatar-bytes".utf8))
    }

    // MARK: - 路径穿越防御

    func testImportRejectsPathTraversalPhotoFileName() async throws {
        // 恶意备份包：photoFileName 含 "../"，直接拼接可越权写入沙盒外。
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let photo = Photo(uri: "/src/a.jpg", originalURI: "L0/001", pet: pet)
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo], fileStorage: sharedFS)
        sharedFS.preset(Data([0x01]), at: "/src/a.jpg")
        let result = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 篡改 metadata：把 photoFileName 改为穿越路径
        let zipData = try await sharedFS.read(at: result.fileURL.path)
        var entries = try ZipReader.extract(zipData)
        let metaIdx = entries.firstIndex { $0.path == BackupConfig.metadataFileName }!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var metadata = try decoder.decode(BackupMetadata.self, from: entries[metaIdx].data)
        let orig = metadata.photos.first!
        let maliciousName = "../../\(orig.photoFileName)"
        metadata = BackupMetadata(
            pets: metadata.pets,
            photos: [PhotoSnapshot(
                id: orig.id, originalURI: orig.originalURI + "#evil", petID: orig.petID,
                takenAt: orig.takenAt, latitude: orig.latitude, longitude: orig.longitude,
                placeName: orig.placeName, note: orig.note, isFavorite: orig.isFavorite,
                eventNotify: orig.eventNotify, width: orig.width, height: orig.height,
                fileSize: orig.fileSize, category: orig.category, subCategory: orig.subCategory,
                phash: orig.phash, qualityScore: orig.qualityScore,
                photoFileName: maliciousName, createdAt: orig.createdAt)],
            petEvents: metadata.petEvents)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        entries[metaIdx] = ZipEntry(path: BackupConfig.metadataFileName,
                                     data: try encoder.encode(metadata))
        try await sharedFS.write(ZipWriter.archive(entries: entries), to: result.fileURL.path)

        let (target, _, _, tFs, sandboxDir) = makeService(fileStorage: sharedFS)
        _ = try await target.importBackup(from: result.fileURL, progress: { _ in })

        // 恶意文件名不得被写入：直接拼接的穿越目标路径不应存在。
        let maliciousDest = "\(sandboxDir)/\(maliciousName)"
        XCTAssertFalse(tFs.fileExists(at: maliciousDest),
                       "恢复不得写入路径穿越目标：\(maliciousDest)")
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

    // MARK: - 预校验（P1 修复：不写孤儿文件、不覆盖已有文件）

    func testImportDuplicatePhotoWritesNoOrphanFile() async throws {
        // 相同 originalURI 的照片须跳过——且不写文件到沙盒（预校验拦截）。
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let photo = Photo(uri: "/src/a.jpg", originalURI: "L0/001", pet: pet)
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo], fileStorage: sharedFS)
        sharedFS.preset(Data([0x01, 0x02, 0x03]), at: "/src/a.jpg")
        let backup = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 目标库已有相同 originalURI 的照片
        let targetPet = Pet(id: pet.id, name: "小橘", species: .cat)
        let existingPhoto = Photo(uri: "/existing/a.jpg", originalURI: "L0/001", pet: targetPet)
        let (target, _, _, tFs, sandboxDir) = makeService(pets: [targetPet], photos: [existingPhoto], fileStorage: sharedFS)

        _ = try await target.importBackup(from: backup.fileURL, progress: { _ in })

        // 沙盒目录不应有任何新写入的照片文件（预校验拦截，跳过写入）
        let sandboxFiles = tFs.listFiles(in: sandboxDir)
        XCTAssertTrue(sandboxFiles.isEmpty, "重复照片不应写入孤儿文件")
    }

    func testImportSkipsExistingPhotoByID() async throws {
        // 相同 id 但不同 originalURI 的照片也须跳过（Photo.id 是 unique 约束）。
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let photo = Photo(uri: "/src/a.jpg", originalURI: "L0/001", pet: pet)
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo], fileStorage: sharedFS)
        sharedFS.preset(Data([0x01]), at: "/src/a.jpg")
        let backup = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 目标库已有相同 id 的照片（不同 originalURI，验证 id 去重也生效）
        let targetPet = Pet(id: pet.id, name: "小橘", species: .cat)
        let existingPhoto = Photo(id: photo.id, uri: "/existing/a.jpg", originalURI: "L0/DIFFERENT", pet: targetPet)
        let (target, _, tPhotoRepo, _, _) = makeService(pets: [targetPet], photos: [existingPhoto], fileStorage: sharedFS)

        let result = try await target.importBackup(from: backup.fileURL, progress: { _ in })

        XCTAssertEqual(result.importedPhotos, 0, "相同 id 照片须跳过")
        let photos = try tPhotoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos.first?.originalURI, "L0/DIFFERENT", "现有照片不得被覆盖")
    }

    func testRestoreDoesNotOverwriteExistingFile() async throws {
        // 目标路径已有文件时，恢复不得覆盖（跨平台备份不同 originalURI 但同文件名冲突）。
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let photo = Photo(uri: "/src/a.jpg", originalURI: "L0/001", pet: pet)
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo], fileStorage: sharedFS)
        sharedFS.preset(Data("source-bytes".utf8), at: "/src/a.jpg")
        let backup = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 目标库为空（照片会被导入），但在恢复前手动写入同名文件
        let (target, _, _, tFs, sandboxDir) = makeService(fileStorage: sharedFS)
        let photoFileName = "\(photo.id.uuidString).jpg"
        let destPath = "\(sandboxDir)/\(photoFileName)"
        sharedFS.preset(Data("pre-existing".utf8), at: destPath)

        _ = try await target.importBackup(from: backup.fileURL, progress: { _ in })

        // 原有文件应保留，不被备份包中的数据覆盖
        XCTAssertTrue(tFs.fileExists(at: destPath), "目标路径应存在")
        XCTAssertEqual(try await tFs.read(at: destPath), Data("pre-existing".utf8),
                       "恢复不得覆盖已存在的文件")
    }

    // MARK: - 流式读写验证（重构后行为不变 + 大 entry 正确性）

    func testStreamingRoundTripMultiPhotoPreservesData() async throws {
        // 多照片往返：验证流式导出+恢复后每张照片文件字节一致。
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let photoData = [
            Data("photo-alpha-bytes".utf8),
            Data("photo-beta-bytes".utf8),
            Data([0x00, 0x01, 0x02, 0x03, 0xFF]),
        ]
        let photos = (0..<3).map { i in
            Photo(uri: "/src/\(i).jpg", originalURI: "L0/00\(i)", pet: pet)
        }
        let (source, _, _, _, _) = makeService(pets: [pet], photos: photos, fileStorage: sharedFS)
        for (i, data) in photoData.enumerated() {
            sharedFS.preset(data, at: "/src/\(i).jpg")
        }

        let backup = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 目标空库流式恢复
        let (target, tPetRepo, tPhotoRepo, tFs, _) = makeService(fileStorage: sharedFS)
        let result = try await target.importBackup(from: backup.fileURL, progress: { _ in })
        XCTAssertEqual(result.importedPhotos, 3)

        // 验证每张照片文件字节一致
        let restored = try tPhotoRepo.getPhotosPage(offset: 0, limit: 10)
        for photo in restored {
            XCTAssertTrue(tFs.fileExists(at: photo.uri), "恢复后照片文件须存在")
            let data = try await tFs.read(at: photo.uri)
            XCTAssertTrue(photoData.contains(data), "恢复的照片数据须与原数据一致")
        }
    }

    func testStreamingHandlesLargePhotoEntry() async throws {
        // 大照片文件（100KB）往返：验证流式分块拷贝正确。
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let bigData = Data((0..<(100 * 1024)).map { UInt8($0 & 0xFF) })
        let photo = Photo(uri: "/src/big.jpg", originalURI: "L0/BIG", pet: pet)
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo], fileStorage: sharedFS)
        sharedFS.preset(bigData, at: "/src/big.jpg")

        let backup = try await source.exportBackup(petIDs: nil, progress: { _ in })

        let (target, _, tPhotoRepo, tFs, _) = makeService(fileStorage: sharedFS)
        _ = try await target.importBackup(from: backup.fileURL, progress: { _ in })

        let restored = try tPhotoRepo.getPhotosPage(offset: 0, limit: 10).first!
        let data = try await tFs.read(at: restored.uri)
        XCTAssertEqual(data, bigData, "大文件流式往返数据须完全一致")
    }

    func testStreamingExportProducesValidZIP() async throws {
        // 流式导出的备份包须是合法 ZIP，可被旧 extract 解出。
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let photo = Photo(uri: "/src/a.jpg", originalURI: "L0/001", pet: pet)
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo], fileStorage: sharedFS)
        sharedFS.preset(Data([0x01, 0x02, 0x03]), at: "/src/a.jpg")

        let result = try await source.exportBackup(petIDs: nil, progress: { _ in })
        let zipData = try await sharedFS.read(at: result.fileURL.path)

        // 旧 extract 须能解出——格式与旧 archive 兼容
        let entries = try ZipReader.extract(zipData)
        let paths = Set(entries.map(\.path))
        XCTAssertTrue(paths.contains(BackupConfig.manifestFileName))
        XCTAssertTrue(paths.contains(BackupConfig.metadataFileName))
        XCTAssertTrue(paths.contains(where: { $0.hasPrefix("\(BackupConfig.photosDirName)/") }))
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
            platform: "ios",
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

// MARK: - 测试辅助：总会抛错的宠物仓储

/// 在 insertPet 时抛错，用于模拟 DB 写入失败（测试恢复原子性）。
@MainActor
final class ThrowingPetRepository: PetRepositoryProtocol {
    private struct FakeError: Error {}

    func getAllPets() throws -> [Pet] { [] }
    func getPet(id: UUID) throws -> Pet? { nil }
    func insertPet(_ pet: Pet) throws { throw FakeError() }
    func updatePet(_ pet: Pet) throws { throw FakeError() }
    func deletePet(_ pet: Pet) throws {}
    func refreshPhotoCount(for pet: Pet) throws {}
    func updateFeatureData(_ pet: Pet, data: Data?) throws {}
    func addEvent(_ event: PetEvent, to pet: Pet) throws {}
}

/// insertPet 正常但 updatePet 抛错——模拟「宠物已入库、事件持久化阶段失败」。
/// 用于覆盖 applyImport 的记录回滚分支（deletePet 已插入的宠物），
/// 这是 ThrowingPetRepository（insertPet 立即抛错）无法触达的路径。
@MainActor
final class PartiallyThrowingPetRepository: PetRepositoryProtocol {
    private struct FakeError: Error {}

    /// 暴露内部状态供测试断言回滚是否生效。
    private(set) var allPets: [Pet] = []

    func getAllPets() throws -> [Pet] { allPets }
    func getPet(id: UUID) throws -> Pet? { allPets.first { $0.id == id } }
    func insertPet(_ pet: Pet) throws { allPets.append(pet) }
    func updatePet(_ pet: Pet) throws { throw FakeError() }
    func deletePet(_ pet: Pet) throws { allPets.removeAll { $0.id == pet.id } }
    func refreshPhotoCount(for pet: Pet) throws {}
    func updateFeatureData(_ pet: Pet, data: Data?) throws {}
    func addEvent(_ event: PetEvent, to pet: Pet) throws {}
}
