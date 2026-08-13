//  MediaLifecycleServiceTests —— 媒体文件-数据库事务一致性测试（P1 可靠性）。
//  覆盖：导入回滚（DB 失败删文件）、编辑保存（失败回滚新文件 / 成功清理旧文件）、
//  删除联动（DB + 文件 + 宠物计数）、孤儿审计（清理无记录文件）。
//  in-memory SwiftData + MockFileStorage，无需真机。

import XCTest
import SwiftData
@testable import MiLens

@MainActor
final class MediaLifecycleServiceTests: XCTestCase {

    private let sandboxDir = "/documents/MiPhotos"

    private func makeService(
        photoRepo: (any PhotoRepositoryProtocol)? = nil
    ) -> (MediaLifecycleService, SwiftDataPhotoRepository, SwiftDataPetRepository, MockFileStorage, ModelContainer) {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let photoRepo = SwiftDataPhotoRepository(context: container.mainContext)
        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let fileStorage = MockFileStorage()
        let service = MediaLifecycleService(
            photoRepo: photoRepo, petRepo: petRepo,
            fileStorage: fileStorage, sandboxDir: sandboxDir)
        return (service, photoRepo, petRepo, fileStorage, container)
    }

    // MARK: - 导入事务段

    func testCommitImportWritesFileAndRecord() async throws {
        let (service, photoRepo, _, fs, container) = makeService()
        let photo = Photo(uri: "\(sandboxDir)/a.jpg", originalURI: "a")
        let data = Data([1, 2, 3])

        try await service.commitImport(data: data, to: photo.uri, photo: photo)

        XCTAssertTrue(fs.fileExists(at: photo.uri))
        XCTAssertNotNil(try photoRepo.getPhotoByOriginalURI("a"))
    }

    func testCommitImportRollsBackFileWhenDBFails() async throws {
        let (_, _, _, fs, container) = makeService()
        // DB 失败包装：insertPhoto 抛错
        let failingRepo = FailingPhotoRepository(wrapped: SwiftDataPhotoRepository(context: container.mainContext), failOnInsert: true)
        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let service = MediaLifecycleService(
            photoRepo: failingRepo, petRepo: petRepo,
            fileStorage: fs, sandboxDir: sandboxDir)
        let photo = Photo(uri: "\(sandboxDir)/a.jpg", originalURI: "a")

        do {
            try await service.commitImport(data: Data([1]), to: photo.uri, photo: photo)
            XCTFail("应当抛出 DB 错误")
        } catch {
            // 回滚：文件必须被删除
            XCTAssertFalse(fs.fileExists(at: photo.uri), "DB 失败后孤儿文件必须回滚删除")
        }
    }

    // MARK: - 导入事务段（批量，L2）

    func testCommitImportBatchInsertsAllInOneTransaction() async throws {
        let (service, photoRepo, _, fs, container) = makeService()
        let photos = (1...3).map { Photo(uri: "\(sandboxDir)/b\($0).jpg", originalURI: "orig-\($0)") }
        let paths = photos.map { $0.uri }
        for (index, path) in paths.enumerated() {
            fs.preset(Data([index == 0 ? 1 : 2]), at: path)
        }

        try await service.commitImportBatch(photos: photos, paths: paths)

        for photo in photos {
            XCTAssertNotNil(try photoRepo.getPhotoByOriginalURI(photo.originalURI), "批量入库后记录必须存在")
        }
        for path in paths {
            XCTAssertTrue(fs.fileExists(at: path), "入库成功后文件必须保留")
        }
    }

    func testCommitImportBatchRollsBackAllFilesWhenDBFails() async throws {
        let (_, _, _, fs, container) = makeService()
        let failingRepo = FailingPhotoRepository(wrapped: SwiftDataPhotoRepository(context: container.mainContext), failOnInsert: true)
        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let service = MediaLifecycleService(
            photoRepo: failingRepo, petRepo: petRepo,
            fileStorage: fs, sandboxDir: sandboxDir)
        let photos = (1...3).map { Photo(uri: "\(sandboxDir)/c\($0).jpg", originalURI: "orig-\($0)") }
        let paths = photos.map { $0.uri }

        do {
            try await service.commitImportBatch(photos: photos, paths: paths)
            XCTFail("应当抛出 DB 错误")
        } catch {
            // 回滚：本批全部文件必须被删除
            for path in paths {
                XCTAssertFalse(fs.fileExists(at: path), "批量 DB 失败后本批孤儿文件必须全部回滚删除")
            }
        }
    }

    // MARK: - 编辑保存事务段

    func testSaveEditedPhotoCleansUpOldFile() async throws {
        let (service, photoRepo, _, fs, container) = makeService()
        let oldPath = "\(sandboxDir)/old.jpg"
        let photo = Photo(uri: oldPath, width: 100, height: 100)
        try photoRepo.insertPhoto(photo)
        fs.preset(Data([0xAA]), at: oldPath)
        let newPath = "\(sandboxDir)/MiLens_Edit_1.jpg"

        let saved = try await service.saveEditedPhoto(
            photo, data: Data([0xBB]), to: newPath, width: 200, height: 150)

        XCTAssertEqual(saved, newPath)
        XCTAssertTrue(fs.fileExists(at: newPath))
        XCTAssertFalse(fs.fileExists(at: oldPath), "旧版本文件必须清理")
        XCTAssertEqual(photo.width, 200)
        XCTAssertEqual(photo.height, 150)
        XCTAssertEqual(photo.fileSize, 1)
        XCTAssertEqual(photo.category, PhotoCategory.edited.rawValue,
                       "编辑保存必须打「作品」标记（档案分类唯一来源）")
    }

    func testSaveEditedPhotoRollsBackNewFileWhenDBFails() async throws {
        let (_, _, _, fs, container) = makeService()
        let oldPath = "\(sandboxDir)/old.jpg"
        let photo = Photo(uri: oldPath, width: 100, height: 100)
        let realRepo = SwiftDataPhotoRepository(context: container.mainContext)
        try realRepo.insertPhoto(photo)
        fs.preset(Data([0xAA]), at: oldPath)
        // DB 失败包装：updatePhoto 抛错
        let failingRepo = FailingPhotoRepository(wrapped: realRepo, failOnUpdate: true)
        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let service = MediaLifecycleService(
            photoRepo: failingRepo, petRepo: petRepo,
            fileStorage: fs, sandboxDir: sandboxDir)
        let newPath = "\(sandboxDir)/MiLens_Edit_2.jpg"

        do {
            _ = try await service.saveEditedPhoto(
                photo, data: Data([0xBB]), to: newPath, width: 200, height: 150)
            XCTFail("应当抛出 DB 错误")
        } catch {
            XCTAssertFalse(fs.fileExists(at: newPath), "更新失败后新文件必须回滚删除")
            XCTAssertTrue(fs.fileExists(at: oldPath), "记录保持指向旧文件")
            XCTAssertEqual(photo.uri, oldPath)
            XCTAssertEqual(photo.category, PhotoCategory.unknown.rawValue,
                           "编辑失败后 category 必须恢复原值（完整回滚，评审 P）")
        }
    }

    func testSaveEditedPhotoKeepsOldFileWhenReferenceQueryFails() async throws {
        let (_, _, _, fs, container) = makeService()
        let oldPath = "\(sandboxDir)/old.jpg"
        let photo = Photo(uri: oldPath, width: 100, height: 100)
        let realRepo = SwiftDataPhotoRepository(context: container.mainContext)
        try realRepo.insertPhoto(photo)
        fs.preset(Data([0xAA]), at: oldPath)
        // 引用查询失败注入：getPhotoByURI 抛错——必须保守保留旧文件，不得按“未引用”删除
        let failingRepo = FailingPhotoRepository(wrapped: realRepo, failOnGetByURI: true)
        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let service = MediaLifecycleService(
            photoRepo: failingRepo, petRepo: petRepo,
            fileStorage: fs, sandboxDir: sandboxDir)
        let newPath = "\(sandboxDir)/MiLens_Edit_3.jpg"

        _ = try await service.saveEditedPhoto(
            photo, data: Data([0xBB]), to: newPath, width: 200, height: 150)

        XCTAssertTrue(fs.fileExists(at: newPath), "新文件必须写入")
        XCTAssertTrue(fs.fileExists(at: oldPath), "引用查询失败时必须保守保留旧文件")
    }

    // MARK: - 删除联动

    func testDeletePhotoRemovesRecordAndFileAndRefreshesCount() async throws {
        let (service, photoRepo, petRepo, fs, container) = makeService()
        let pet = Pet(name: "咪咪")
        try petRepo.insertPet(pet)
        let photo = Photo(uri: "\(sandboxDir)/a.jpg", originalURI: "a")
        try photoRepo.insertPhoto(photo)
        photo.pet = pet
        try photoRepo.updatePhoto(photo)
        try petRepo.refreshPhotoCount(for: pet)
        XCTAssertEqual(pet.photoCount, 1)
        fs.preset(Data([1]), at: photo.uri)

        try await service.deletePhoto(photo)

        XCTAssertNil(try photoRepo.getPhotoByOriginalURI("a"), "DB 记录必须删除")
        XCTAssertFalse(fs.fileExists(at: photo.uri), "媒体文件必须联动删除")
        XCTAssertEqual(pet.photoCount, 0, "宠物照片计数必须刷新")
    }

    // MARK: - 孤儿审计

    func testAuditOrphansRemovesUnreferencedFiles() async throws {
        let (service, photoRepo, _, fs, container) = makeService()
        // 一张正常记录 + 两个孤儿文件（上次崩溃残留）
        let photo = Photo(uri: "\(sandboxDir)/kept.jpg", originalURI: "kept")
        try photoRepo.insertPhoto(photo)
        fs.preset(Data([1]), at: photo.uri)
        fs.preset(Data([2]), at: "\(sandboxDir)/orphan1.jpg")
        fs.preset(Data([3]), at: "\(sandboxDir)/orphan2.jpg")
        // 子目录文件不应被审计到（listFiles 仅直接子项）
        fs.preset(Data([4]), at: "\(sandboxDir)/sub/deep.jpg")

        await service.auditOrphans()

        XCTAssertTrue(fs.fileExists(at: photo.uri))
        XCTAssertFalse(fs.fileExists(at: "\(sandboxDir)/orphan1.jpg"))
        XCTAssertFalse(fs.fileExists(at: "\(sandboxDir)/orphan2.jpg"))
        XCTAssertTrue(fs.fileExists(at: "\(sandboxDir)/sub/deep.jpg"), "子目录文件不在审计范围")
    }

    func testAuditOrphansKeepsRecordWhenFileMissing() async throws {
        let (service, photoRepo, _, fs, container) = makeService()
        // 记录存在但文件缺失：不删 DB（记录是事实源）
        let photo = Photo(uri: "\(sandboxDir)/missing.jpg", originalURI: "missing")
        try photoRepo.insertPhoto(photo)

        await service.auditOrphans()

        XCTAssertNotNil(try photoRepo.getPhotoByOriginalURI("missing"), "文件缺失不应删除 DB 记录")
    }
}

/// 包装仓储：按需在 insertPhoto / updatePhoto / getPhotoByURI 抛错（模拟 DB 故障）。
@MainActor
private final class FailingPhotoRepository: PhotoRepositoryProtocol {
    private let wrapped: any PhotoRepositoryProtocol
    private let failOnInsert: Bool
    private let failOnUpdate: Bool
    private let failOnGetByURI: Bool

    init(wrapped: any PhotoRepositoryProtocol, failOnInsert: Bool = false, failOnUpdate: Bool = false, failOnGetByURI: Bool = false) {
        self.wrapped = wrapped
        self.failOnInsert = failOnInsert
        self.failOnUpdate = failOnUpdate
        self.failOnGetByURI = failOnGetByURI
    }

    private enum FailingError: Error { case simulatedDBFailure }

    func getPhoto(id: UUID) throws -> Photo? { try wrapped.getPhoto(id: id) }
    func getPhotoByURI(_ uri: String) throws -> Photo? {
        if failOnGetByURI { throw FailingError.simulatedDBFailure }
        return try wrapped.getPhotoByURI(uri)
    }
    func getPhotoByOriginalURI(_ originalURI: String) throws -> Photo? { try wrapped.getPhotoByOriginalURI(originalURI) }
    func getAllOriginalURIs() throws -> Set<String> { try wrapped.getAllOriginalURIs() }
    func getAllPhotoURIs() throws -> Set<String> { try wrapped.getAllPhotoURIs() }
    func countAllPhotos() throws -> Int { try wrapped.countAllPhotos() }
    func getPhotosPage(offset: Int, limit: Int) throws -> [Photo] { try wrapped.getPhotosPage(offset: offset, limit: limit) }
    func getPhotosByPet(_ pet: Pet) throws -> [Photo] { try wrapped.getPhotosByPet(pet) }
    func getUnassignedPhotos(limit: Int) throws -> [Photo] { try wrapped.getUnassignedPhotos(limit: limit) }
    func getAnniversaryPhotos(month: Int, day: Int, excludeYear: Int?) throws -> [Photo] { try wrapped.getAnniversaryPhotos(month: month, day: day, excludeYear: excludeYear) }
    func insertPhoto(_ photo: Photo) throws {
        if failOnInsert { throw FailingError.simulatedDBFailure }
        try wrapped.insertPhoto(photo)
    }
    func insertPhotos(_ photos: [Photo]) throws {
        if failOnInsert { throw FailingError.simulatedDBFailure }
        try wrapped.insertPhotos(photos)
    }
    func deletePhoto(_ photo: Photo) throws { try wrapped.deletePhoto(photo) }
    func updatePhoto(_ photo: Photo) throws {
        if failOnUpdate { throw FailingError.simulatedDBFailure }
        try wrapped.updatePhoto(photo)
    }
    func assignPhoto(_ photo: Photo, to pet: Pet?) throws { try wrapped.assignPhoto(photo, to: pet) }
    func batchAssignPhotos(_ photos: [Photo], to targetPet: Pet?) throws -> [Pet] { try wrapped.batchAssignPhotos(photos, to: targetPet) }
    func setFavorite(_ photo: Photo, favorite: Bool) throws { try wrapped.setFavorite(photo, favorite: favorite) }
    func updateNote(_ photo: Photo, note: String) throws { try wrapped.updateNote(photo, note: note) }
    func getPendingQualityScorePhotos(limit: Int) throws -> [Photo] { try wrapped.getPendingQualityScorePhotos(limit: limit) }
    func getDuplicateCandidates() throws -> [Photo] { try wrapped.getDuplicateCandidates() }
    func updateQualityData(_ photo: Photo, sharpness: Double, qualityScore: Double, phash: String) throws { try wrapped.updateQualityData(photo, sharpness: sharpness, qualityScore: qualityScore, phash: phash) }
    func replaceDuplicateMarks(_ groups: [DuplicateMarkGroup]) throws { try wrapped.replaceDuplicateMarks(groups) }
}
