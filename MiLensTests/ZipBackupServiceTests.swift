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

        XCTAssertTrue(fs.fileExists(at: result.fileURLs[0].path), "导出后临时文件必须存在")
        let data = try await fs.read(at: result.fileURLs[0].path)
        XCTAssertFalse(data.isEmpty, "备份文件不得为空")
        XCTAssertEqual(result.manifest.petCount, 1)
        XCTAssertEqual(result.manifest.schemaVersion, BackupConfig.currentSchemaVersion)
    }

    // MARK: - 导出文件名唯一性（P1 修复：同秒内连续导出不覆盖）

    func testExportFileNameIsUniqueAcrossSameSecond() async throws {
        let pet = Pet(name: "小橘", species: .cat)
        let (service, _, _, _, _) = makeService(pets: [pet])
        // 同秒内连续导出两次——文件名含 UUID 后缀不得冲突
        let result1 = try await service.exportBackup(petIDs: nil, progress: { _ in })
        let result2 = try await service.exportBackup(petIDs: nil, progress: { _ in })
        XCTAssertNotEqual(result1.fileURLs[0].lastPathComponent,
                          result2.fileURLs[0].lastPathComponent,
                          "同秒内连续导出须得到不同文件名（含 UUID 后缀）")
    }

    func testExportIncludesPhotoFilesAndManifest() async throws {
        let pet = Pet(name: "豆豆", species: .dog)
        let photo = Photo(uri: "/src/a.jpg", originalURI: "L0/001", pet: pet)
        let (service, _, _, fs, _) = makeService(pets: [pet], photos: [photo])
        fs.preset(Data([0x01, 0x02, 0x03]), at: "/src/a.jpg")

        let result = try await service.exportBackup(petIDs: nil, progress: { _ in })
        let zipData = try await fs.read(at: result.fileURLs[0].path)
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
        let restoreResult = try await target.importBackup(from: [result.fileURLs[0]], progress: { _ in })

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
        _ = try await target.importBackup(from: [result.fileURLs[0]], progress: { _ in })

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
        _ = try await target.importBackup(from: [result.fileURLs[0]], progress: { _ in })

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
            _ = try await target.importBackup(from: [result.fileURLs[0]], progress: { _ in })
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
            _ = try await target.importBackup(from: [result.fileURLs[0]], progress: { _ in })
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

    // MARK: - 恢复时半截文件清理（P1 修复：copyEntry 中途失败不残留）

    func testRestoreCleansUpPartialFileOnCopyEntryFailure() async throws {
        // copyEntry 中途失败（CRC 不匹配）时，已写入的部分文件须被清理。
        // 修复前：dest 仅在 copyEntry 成功后才加入 writtenPaths，半截文件会残留。
        // 修复后：创建输出流后立即记录路径，失败时纳入清理列表。
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let photo = Photo(uri: "/src/a.jpg", originalURI: "L0/001", pet: pet)
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo], fileStorage: sharedFS)
        sharedFS.preset(Data([0x01, 0x02, 0x03, 0x04]), at: "/src/a.jpg")
        let result = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 读取 ZIP 数据，定位 photo 数据区偏移
        var zipData = try await sharedFS.read(at: result.fileURLs[0].path)
        let records = try await ZipReader.readCentralDirectory(
            from: MockInputStream(data: zipData))
        let photoRecord = try XCTUnwrap(
            records.first { $0.path.hasPrefix("\(BackupConfig.photosDirName)/") },
            "备份包须含 photo entry")
        // 篡改 photo 数据首字节（保持长度不变）→ CRC 不匹配 → copyEntry 抛 crcMismatch
        let dataOffset = Int(photoRecord.dataOffset)
        zipData[dataOffset] ^= 0xFF
        try await sharedFS.write(zipData, to: result.fileURLs[0].path)

        // 目标空库恢复：copyEntry 失败时应清理半截文件
        let (target, _, _, _, sandboxDir) = makeService(fileStorage: sharedFS)
        do {
            _ = try await target.importBackup(from: [result.fileURLs[0]], progress: { _ in })
            XCTFail("CRC 不匹配时应抛错")
        } catch {
            // 预期抛错
        }

        // copyEntry 失败后，沙盒目录不应残留半截照片文件
        let writtenFiles = sharedFS.listFiles(in: sandboxDir)
        XCTAssertEqual(writtenFiles.count, 0,
                       "copyEntry 中途失败时半截文件须清理，避免孤儿残留")
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
        let zipData = try await sharedFS.read(at: result.fileURLs[0].path)
        let entries = try ZipReader.extract(zipData)
        let avatarEntry = entries.first { $0.path.hasPrefix("avatars/") }
        XCTAssertNotNil(avatarEntry, "备份包须含头像文件")
        XCTAssertEqual(avatarEntry?.data, Data("avatar-bytes".utf8))

        // 目标空库恢复（共享 fs 才能读到导出的备份文件）
        let (target, tPetRepo, _, tFs, sandboxDir) = makeService(fileStorage: sharedFS)
        let restoreResult = try await target.importBackup(from: [result.fileURLs[0]], progress: { _ in })
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
        let zipData = try await sharedFS.read(at: result.fileURLs[0].path)
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
        try await sharedFS.write(ZipWriter.archive(entries: entries), to: result.fileURLs[0].path)

        let (target, _, _, tFs, sandboxDir) = makeService(fileStorage: sharedFS)
        _ = try await target.importBackup(from: [result.fileURLs[0]], progress: { _ in })

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

        let result = try await target.importBackup(from: [backup.fileURLs[0]], progress: { _ in })

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

        let result = try await target.importBackup(from: [backup.fileURLs[0]], progress: { _ in })

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

        _ = try await target.importBackup(from: [backup.fileURLs[0]], progress: { _ in })

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

        let result = try await target.importBackup(from: [backup.fileURLs[0]], progress: { _ in })

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

        _ = try await target.importBackup(from: [backup.fileURLs[0]], progress: { _ in })

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
        let result = try await target.importBackup(from: [backup.fileURLs[0]], progress: { _ in })
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
        _ = try await target.importBackup(from: [backup.fileURLs[0]], progress: { _ in })

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
        let zipData = try await sharedFS.read(at: result.fileURLs[0].path)

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
        let zipData = try await sharedFS.read(at: backup.fileURLs[0].path)
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
        try await sharedFS.write(tamperedZip, to: backup.fileURLs[0].path)

        let (target, _, _, _, _) = makeService(fileStorage: sharedFS)
        XCTAssertThrowsError(try await target.importBackup(from: [backup.fileURLs[0]], progress: { _ in })) { error in
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
        let zipData = try await sharedFS.read(at: backup.fileURLs[0].path)
        let entries = try ZipReader.extract(zipData).filter { $0.path != BackupConfig.manifestFileName }
        try await sharedFS.write(ZipWriter.archive(entries: entries), to: backup.fileURLs[0].path)

        let (target, _, _, _, _) = makeService(fileStorage: sharedFS)
        XCTAssertThrowsError(try await target.importBackup(from: [backup.fileURLs[0]], progress: { _ in })) { error in
            XCTAssertEqual(error as? BackupServiceError, .invalidFormat)
        }
    }

    // MARK: - 恢复不绑定已有未知文件（P1 修复）

    func testRestoreDoesNotBindToPreExistingFile() async throws {
        // 目标路径已有文件时，恢复不得将 DB 记录绑定到该未知文件。
        // 修复前：跳过写入但 photoPathByID 仍记录 dest → uri 指向不相关文件。
        // 修复后：跳过写入且不记录路径 → uri 为空（DB 事实源 + auditOrphans 占位）。
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let photo = Photo(uri: "/src/a.jpg", originalURI: "L0/001", pet: pet)
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo], fileStorage: sharedFS)
        sharedFS.preset(Data("source-bytes".utf8), at: "/src/a.jpg")
        let backup = try await source.exportBackup(petIDs: nil, progress: { _ in })

        let (target, _, tPhotoRepo, tFs, sandboxDir) = makeService(fileStorage: sharedFS)
        let photoFileName = "\(photo.id.uuidString).jpg"
        let destPath = "\(sandboxDir)/\(photoFileName)"
        sharedFS.preset(Data("pre-existing-unrelated".utf8), at: destPath)

        _ = try await target.importBackup(from: [backup.fileURLs[0]], progress: { _ in })

        // 原有文件保留
        XCTAssertTrue(tFs.fileExists(at: destPath))
        XCTAssertEqual(try await tFs.read(at: destPath), Data("pre-existing-unrelated".utf8))
        // 照片记录须导入（元数据有效），但 uri 须为空——不绑定到未知文件
        let restoredPhoto = try tPhotoRepo.getPhotosPage(offset: 0, limit: 10).first!
        XCTAssertEqual(restoredPhoto.uri, "", "恢复不得将 uri 绑定到非本次写入的未知文件")
    }

    // MARK: - 备份内部重复元数据校验（P1 修复）

    func testImportSkipsDuplicatePhotoIDWithinBackup() async throws {
        // 备份包内部两条照片共用同一 id → 只导入首条，不写孤儿文件。
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let photo1 = Photo(uri: "/src/p1.jpg", originalURI: "L0/001", pet: pet)
        let photo2 = Photo(uri: "/src/p2.jpg", originalURI: "L0/002", pet: pet)
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo1, photo2], fileStorage: sharedFS)
        sharedFS.preset(Data("p1".utf8), at: "/src/p1.jpg")
        sharedFS.preset(Data("p2".utf8), at: "/src/p2.jpg")
        let backup = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 篡改 metadata：把 photo2 的 id 改为 photo1 的 id（制造备份内部重复 id）
        let zipData = try await sharedFS.read(at: backup.fileURLs[0].path)
        var entries = try ZipReader.extract(zipData)
        let metaIdx = entries.firstIndex { $0.path == BackupConfig.metadataFileName }!
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var metadata = try decoder.decode(BackupMetadata.self, from: entries[metaIdx].data)
        let snap1 = metadata.photos[0]
        var snap2 = metadata.photos[1]
        snap2 = PhotoSnapshot(
            id: snap1.id, originalURI: snap2.originalURI, petID: snap2.petID,
            takenAt: snap2.takenAt, latitude: snap2.latitude, longitude: snap2.longitude,
            placeName: snap2.placeName, note: snap2.note, isFavorite: snap2.isFavorite,
            eventNotify: snap2.eventNotify, width: snap2.width, height: snap2.height,
            fileSize: snap2.fileSize, category: snap2.category, subCategory: snap2.subCategory,
            phash: snap2.phash, qualityScore: snap2.qualityScore,
            photoFileName: snap2.photoFileName, createdAt: snap2.createdAt)
        metadata = BackupMetadata(pets: metadata.pets, photos: [snap1, snap2], petEvents: metadata.petEvents)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        entries[metaIdx] = ZipEntry(path: BackupConfig.metadataFileName, data: try encoder.encode(metadata))
        try await sharedFS.write(ZipWriter.archive(entries: entries), to: backup.fileURLs[0].path)

        let (target, _, tPhotoRepo, tFs, sandboxDir) = makeService(fileStorage: sharedFS)
        let result = try await target.importBackup(from: [backup.fileURLs[0]], progress: { _ in })

        // 只导入 1 张照片（重复 id 的第二条被跳过）
        XCTAssertEqual(result.importedPhotos, 1, "备份内部重复 id 的照片只导入首条")
        let photos = try tPhotoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 1)
        // 不应残留孤儿文件（第二条的 photoFileName 对应的文件不写入）
        let sandboxFiles = tFs.listFiles(in: sandboxDir)
        let photoFiles = sandboxFiles.filter { $0.hasSuffix(".jpg") }
        XCTAssertEqual(photoFiles.count, 1, "重复 id 的第二条不应写入孤儿文件")
    }

    func testImportSkipsDuplicateOriginalURIWithinBackup() async throws {
        // 备份包内部两条照片共用同一 originalURI → 只导入首条。
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let photo1 = Photo(uri: "/src/p1.jpg", originalURI: "L0/001", pet: pet)
        let photo2 = Photo(uri: "/src/p2.jpg", originalURI: "L0/002", pet: pet)
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo1, photo2], fileStorage: sharedFS)
        sharedFS.preset(Data("p1".utf8), at: "/src/p1.jpg")
        sharedFS.preset(Data("p2".utf8), at: "/src/p2.jpg")
        let backup = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 篡改 metadata：把 photo2 的 originalURI 改为 photo1 的
        let zipData = try await sharedFS.read(at: backup.fileURLs[0].path)
        var entries = try ZipReader.extract(zipData)
        let metaIdx = entries.firstIndex { $0.path == BackupConfig.metadataFileName }!
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var metadata = try decoder.decode(BackupMetadata.self, from: entries[metaIdx].data)
        let snap1 = metadata.photos[0]
        var snap2 = metadata.photos[1]
        snap2 = PhotoSnapshot(
            id: snap2.id, originalURI: snap1.originalURI, petID: snap2.petID,
            takenAt: snap2.takenAt, latitude: snap2.latitude, longitude: snap2.longitude,
            placeName: snap2.placeName, note: snap2.note, isFavorite: snap2.isFavorite,
            eventNotify: snap2.eventNotify, width: snap2.width, height: snap2.height,
            fileSize: snap2.fileSize, category: snap2.category, subCategory: snap2.subCategory,
            phash: snap2.phash, qualityScore: snap2.qualityScore,
            photoFileName: snap2.photoFileName, createdAt: snap2.createdAt)
        metadata = BackupMetadata(pets: metadata.pets, photos: [snap1, snap2], petEvents: metadata.petEvents)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        entries[metaIdx] = ZipEntry(path: BackupConfig.metadataFileName, data: try encoder.encode(metadata))
        try await sharedFS.write(ZipWriter.archive(entries: entries), to: backup.fileURLs[0].path)

        let (target, _, tPhotoRepo, _, _) = makeService(fileStorage: sharedFS)
        let result = try await target.importBackup(from: [backup.fileURLs[0]], progress: { _ in })

        XCTAssertEqual(result.importedPhotos, 1, "备份内部重复 originalURI 的照片只导入首条")
        let photos = try tPhotoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 1)
    }

    // MARK: - 导出总量守卫（P1 修复：ZIP32 安全边界）

    func testExportSizeGuardThrowsWhenExceedingLimit() {
        let guard_ = ExportSizeGuard(maxBytes: 100)
        XCTAssertNoThrow(try guard_.add(50))
        XCTAssertNoThrow(try guard_.add(49))
        XCTAssertThrowsError(try guard_.add(2)) { error in
            XCTAssertEqual(error as? BackupServiceError, .backupTooLarge)
        }
    }

    func testExportSizeGuardAccumulatesThreadSafely() {
        // 累计未超限时正常返回
        let guard_ = ExportSizeGuard(maxBytes: 1000)
        for _ in 0..<10 { try? guard_.add(50) }
        // 再加 600 超限
        XCTAssertThrowsError(try guard_.add(600)) { error in
            XCTAssertEqual(error as? BackupServiceError, .backupTooLarge)
        }
    }

    // MARK: - 恢复后 photoCount 刷新（P1 修复）

    func testRestoreRefreshesPhotoCountForExistingPet() async throws {
        // 合并到已有宠物时，新增照片不会自动更新 photoCount 缓存。
        // 修复后：applyImport 末尾对受影响宠物批量 refreshPhotoCount。
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let photo1 = Photo(uri: "/src/p1.jpg", originalURI: "L0/001", pet: pet)
        let photo2 = Photo(uri: "/src/p2.jpg", originalURI: "L0/002", pet: pet)
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo1, photo2], fileStorage: sharedFS)
        sharedFS.preset(Data("p1".utf8), at: "/src/p1.jpg")
        sharedFS.preset(Data("p2".utf8), at: "/src/p2.jpg")
        let backup = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 目标库已有同 id 宠物（但 photoCount=0，无照片）
        let targetPet = Pet(id: pet.id, name: "小橘", species: .cat)
        let (target, tPetRepo, _, _, _) = makeService(pets: [targetPet], fileStorage: sharedFS)

        let result = try await target.importBackup(from: [backup.fileURLs[0]], progress: { _ in })
        XCTAssertEqual(result.importedPhotos, 2)

        // photoCount 须刷新为实际照片数（2），不能保持旧缓存值 0
        let restoredPet = try tPetRepo.getPet(id: pet.id)!
        XCTAssertEqual(restoredPet.photoCount, 2, "恢复后 photoCount 须与实际照片关系一致")
    }

    // MARK: - Bug 1（P1）：重复 photoFileName 不再导入空 uri 记录

    func testImportDuplicatePhotoFileNameSkipsSecondRecord() async throws {
        // 两条照片 photoFileName 相同但 id/originalURI 不同 →
        // 修复前：第二条因 photoFileName 重复被预校验过滤，但 applyImport 仍插入（uri=""）。
        // 修复后：applyImport 受 importablePhotoIDs 守卫，第二条不插入 DB。
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let photo1 = Photo(uri: "/src/p1.jpg", originalURI: "L0/001", pet: pet)
        let photo2 = Photo(uri: "/src/p2.jpg", originalURI: "L0/002", pet: pet)
        let (source, _, _, _, _) = makeService(pets: [pet], photos: [photo1, photo2], fileStorage: sharedFS)
        sharedFS.preset(Data("p1".utf8), at: "/src/p1.jpg")
        sharedFS.preset(Data("p2".utf8), at: "/src/p2.jpg")
        let backup = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 篡改 metadata：把 photo2 的 photoFileName 改为 photo1 的（制造重复 photoFileName）
        let zipData = try await sharedFS.read(at: backup.fileURLs[0].path)
        var entries = try ZipReader.extract(zipData)
        let metaIdx = entries.firstIndex { $0.path == BackupConfig.metadataFileName }!
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var metadata = try decoder.decode(BackupMetadata.self, from: entries[metaIdx].data)
        let snap1 = metadata.photos[0]
        var snap2 = metadata.photos[1]
        snap2 = PhotoSnapshot(
            id: snap2.id, originalURI: snap2.originalURI, petID: snap2.petID,
            takenAt: snap2.takenAt, latitude: snap2.latitude, longitude: snap2.longitude,
            placeName: snap2.placeName, note: snap2.note, isFavorite: snap2.isFavorite,
            eventNotify: snap2.eventNotify, width: snap2.width, height: snap2.height,
            fileSize: snap2.fileSize, category: snap2.category, subCategory: snap2.subCategory,
            phash: snap2.phash, qualityScore: snap2.qualityScore,
            photoFileName: snap1.photoFileName, createdAt: snap2.createdAt)
        metadata = BackupMetadata(pets: metadata.pets, photos: [snap1, snap2], petEvents: metadata.petEvents)
        let encoder = JSONEncoder(); encoder.dateDecodingStrategy = .iso8601
        entries[metaIdx] = ZipEntry(path: BackupConfig.metadataFileName, data: try encoder.encode(metadata))
        try await sharedFS.write(ZipWriter.archive(entries: entries), to: backup.fileURLs[0].path)

        let (target, _, tPhotoRepo, _, _) = makeService(fileStorage: sharedFS)
        let result = try await target.importBackup(from: [backup.fileURLs[0]], progress: { _ in })

        // 只导入 1 张照片（重复 photoFileName 的第二条不插入 DB）
        XCTAssertEqual(result.importedPhotos, 1, "重复 photoFileName 的照片不应导入第二条")
        let photos = try tPhotoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(photos.count, 1, "不应存在空 uri 的第二条记录")
    }

    // MARK: - Bug 2（P1/P2）：头像文件名冲突

    func testImportDuplicateAvatarFileNameOnlyFirstGetsAvatar() async throws {
        // 两宠物 avatarFileName 相同 → 只有第一个宠物获得头像，第二个 avatarPath 为空。
        let sharedFS = MockFileStorage()
        let pet1 = Pet(name: "猫一", species: .cat, avatarPath: "/src/a1.jpg")
        let pet2 = Pet(name: "猫二", species: .cat, avatarPath: "/src/a2.jpg")
        let (source, _, _, _, _) = makeService(pets: [pet1, pet2], fileStorage: sharedFS)
        sharedFS.preset(Data("avatar1".utf8), at: "/src/a1.jpg")
        sharedFS.preset(Data("avatar2".utf8), at: "/src/a2.jpg")
        let backup = try await source.exportBackup(petIDs: nil, progress: { _ in })

        // 篡改 metadata：把 pet2 的 avatarFileName 改为 pet1 的
        let zipData = try await sharedFS.read(at: backup.fileURLs[0].path)
        var entries = try ZipReader.extract(zipData)
        let metaIdx = entries.firstIndex { $0.path == BackupConfig.metadataFileName }!
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var metadata = try decoder.decode(BackupMetadata.self, from: entries[metaIdx].data)
        let snap1 = metadata.pets[0]
        var snap2 = metadata.pets[1]
        snap2 = PetSnapshot(
            id: snap2.id, name: snap2.name, species: snap2.species, breed: snap2.breed,
            gender: snap2.gender, birthday: snap2.birthday, adoptionDay: snap2.adoptionDay,
            avatarFileName: snap1.avatarFileName, notes: snap2.notes,
            photoCount: snap2.photoCount, createdAt: snap2.createdAt)
        metadata = BackupMetadata(pets: [snap1, snap2], photos: metadata.photos, petEvents: metadata.petEvents)
        let encoder = JSONEncoder(); encoder.dateDecodingStrategy = .iso8601
        entries[metaIdx] = ZipEntry(path: BackupConfig.metadataFileName, data: try encoder.encode(metadata))
        try await sharedFS.write(ZipWriter.archive(entries: entries), to: backup.fileURLs[0].path)

        let (target, tPetRepo, _, _, _) = makeService(fileStorage: sharedFS)
        _ = try await target.importBackup(from: [backup.fileURLs[0]], progress: { _ in })

        let pets = try tPetRepo.getAllPets().sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(pets.count, 2)
        XCTAssertFalse(pets[0].avatarPath.isEmpty, "第一个宠物应获得头像")
        XCTAssertTrue(pets[1].avatarPath.isEmpty, "第二个宠物的 avatarPath 须为空（头像冲突时不绑定错误文件）")
    }

    // MARK: - estimatedBytes 预估

    func testEstimateIncludesEstimatedBytes() async throws {
        let pet = Pet(name: "小橘", species: .cat)
        let photo1 = Photo(uri: "/src/p1.jpg", originalURI: "L0/001", pet: pet, fileSize: 1024)
        let photo2 = Photo(uri: "/src/p2.jpg", originalURI: "L0/002", pet: pet, fileSize: 2048)
        let (service, _, _, _, _) = makeService(pets: [pet], photos: [photo1, photo2])

        let estimate = try await service.estimateBackup(petIDs: nil)

        XCTAssertEqual(estimate.estimatedBytes, 3072, "estimatedBytes 须等于照片 fileSize 之和")
    }

    // MARK: - 单卷新格式向后兼容

    func testSingleVolumeNewFormatHasVolumeInfo() async throws {
        // 新格式单卷须包含 backupID + volumeNumber=1 + totalVolumes=1
        let pet = Pet(name: "小橘", species: .cat)
        let (source, _, _, _, _) = makeService(pets: [pet])
        let result = try await source.exportBackup(petIDs: nil, progress: { _ in })

        XCTAssertNotNil(result.manifest.backupID, "新格式单卷须包含 backupID")
        XCTAssertEqual(result.manifest.volumeNumber, 1)
        XCTAssertEqual(result.manifest.totalVolumes, 1)
        XCTAssertEqual(result.fileURLs.count, 1)
    }

    // MARK: - 多卷分卷导出

    func testMultiVolumeExportProducesMultipleFiles() async throws {
        // 构造预估超过 2GB 的照片集 → 触发多卷导出
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        // 每张照片 fileSize = 1GB（Int64），3 张 = 3GB > 2GB → 多卷
        let bigSize: Int64 = 1_000_000_000
        let photos = (0..<3).map { i in
            Photo(uri: "/src/p\(i).jpg", originalURI: "L0/00\(i)", pet: pet, fileSize: bigSize)
        }
        let (source, _, _, fs, _) = makeService(
            pets: [pet], photos: photos, fileStorage: sharedFS)
        // 实际文件数据很小（测试无法真填 3GB），但预估基于 fileSize 触发分卷
        for i in 0..<3 {
            sharedFS.preset(Data("photo\(i)".utf8), at: "/src/p\(i).jpg")
        }

        let result = try await source.exportBackup(petIDs: nil, progress: { _ in })

        XCTAssertGreaterThan(result.fileURLs.count, 1, "超过 2GB 须生成多个分卷文件")
        // 每个文件须实际存在
        for url in result.fileURLs {
            XCTAssertTrue(fs.fileExists(at: url.path), "分卷文件须存在：\(url.lastPathComponent)")
        }
        // 文件名须含 part{N}of{M}
        for url in result.fileURLs {
            let name = url.lastPathComponent
            XCTAssertTrue(name.contains("part"), "多卷文件名须含 part 标识：\(name)")
            XCTAssertTrue(name.contains("of"), "多卷文件名须含 of 总卷数：\(name)")
        }
    }

    func testMultiVolumeRoundTripRestoresAllPhotos() async throws {
        // 多卷往返：全部照片须恢复成功
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let bigSize: Int64 = 1_000_000_000
        let photos = (0..<3).map { i in
            Photo(uri: "/src/p\(i).jpg", originalURI: "L0/00\(i)", pet: pet, fileSize: bigSize)
        }
        let (source, _, _, _, _) = makeService(
            pets: [pet], photos: photos, fileStorage: sharedFS)
        for i in 0..<3 {
            sharedFS.preset(Data("photo\(i)".utf8), at: "/src/p\(i).jpg")
        }

        let result = try await source.exportBackup(petIDs: nil, progress: { _ in })

        let (target, _, tPhotoRepo, _, _) = makeService(fileStorage: sharedFS)
        let restoreResult = try await target.importBackup(from: result.fileURLs, progress: { _ in })

        XCTAssertEqual(restoreResult.importedPhotos, 3, "多卷往返后全部照片须恢复")
        let restored = try tPhotoRepo.getPhotosPage(offset: 0, limit: 10)
        XCTAssertEqual(restored.count, 3)
    }

    func testMultiVolumeRestoreRejectsIncompleteSet() async throws {
        // 缺少一卷时须抛 incompleteVolumeSet
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let bigSize: Int64 = 1_000_000_000
        let photos = (0..<3).map { i in
            Photo(uri: "/src/p\(i).jpg", originalURI: "L0/00\(i)", pet: pet, fileSize: bigSize)
        }
        let (source, _, _, _, _) = makeService(
            pets: [pet], photos: photos, fileStorage: sharedFS)
        for i in 0..<3 {
            sharedFS.preset(Data("photo\(i)".utf8), at: "/src/p\(i).jpg")
        }

        let result = try await source.exportBackup(petIDs: nil, progress: { _ in })
        let totalVolumes = result.fileURLs.count
        XCTAssertGreaterThan(totalVolumes, 1)

        // 只选择前 totalVolumes - 1 个卷（缺少最后一卷）
        let incompleteURLs = Array(result.fileURLs.dropLast())
        let (target, _, _, _, _) = makeService(fileStorage: sharedFS)

        XCTAssertThrowsError(
            try await target.importBackup(from: incompleteURLs, progress: { _ in })
        ) { error in
            guard case .incompleteVolumeSet = error as? BackupServiceError else {
                return XCTFail("应抛 incompleteVolumeSet，实际：\(error)")
            }
        }
    }

    func testMultiVolumeRestoreRejectsMismatchedBackupID() async throws {
        // 混入不同 backupID 的卷时须抛 mismatchedBackupID
        let sharedFS = MockFileStorage()
        let pet = Pet(name: "小橘", species: .cat)
        let bigSize: Int64 = 1_000_000_000
        let photos1 = (0..<3).map { i in
            Photo(uri: "/src/a\(i).jpg", originalURI: "A/00\(i)", pet: pet, fileSize: bigSize)
        }
        let photos2 = (0..<3).map { i in
            Photo(uri: "/src/b\(i).jpg", originalURI: "B/00\(i)", pet: pet, fileSize: bigSize)
        }
        let (source1, _, _, _, _) = makeService(
            pets: [pet], photos: photos1, fileStorage: sharedFS)
        let (source2, _, _, _, _) = makeService(
            pets: [pet], photos: photos2, fileStorage: sharedFS)
        for i in 0..<3 {
            sharedFS.preset(Data("a\(i)".utf8), at: "/src/a\(i).jpg")
            sharedFS.preset(Data("b\(i)".utf8), at: "/src/b\(i).jpg")
        }

        let result1 = try await source1.exportBackup(petIDs: nil, progress: { _ in })
        let result2 = try await source2.exportBackup(petIDs: nil, progress: { _ in })

        // 混合两份导出的第一卷
        let mixedURLs = [result1.fileURLs[0], result2.fileURLs[0]]
        let (target, _, _, _, _) = makeService(fileStorage: sharedFS)

        XCTAssertThrowsError(
            try await target.importBackup(from: mixedURLs, progress: { _ in })
        ) { error in
            guard case .mismatchedBackupID = error as? BackupServiceError else {
                return XCTFail("应抛 mismatchedBackupID，实际：\(error)")
            }
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
