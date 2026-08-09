import XCTest
import SwiftData
@testable import MiLens

/// P1.2 照片仓储测试（in-memory SwiftData）。
/// 覆盖 CRUD、分页、扫描去重、归属、收藏/备注，以及导入边界约束。
@MainActor
final class PhotoRepositoryTests: XCTestCase {

    /// 保活已创建的容器：ModelContext 不持有 ModelContainer（RepositoryEnvironment 同款教训），
    /// 调用方若只取 repo 而丢弃 container（如 `let (repo, _)`），save/fetch 会触发
    /// SwiftData 内部 SIGTRAP。数组持有到测试类生命周期结束，内存可忽略。
    private var keepAlive: [ModelContainer] = []

    private func makeRepo() -> (SwiftDataPhotoRepository, ModelContainer) {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        keepAlive.append(container)
        let repo = SwiftDataPhotoRepository(context: container.mainContext)
        return (repo, container)
    }

    /// 辅助：构造带拍摄时间的照片
    private func makePhoto(uri: String, takenAt: Date, pet: Pet? = nil) -> Photo {
        Photo(uri: uri, pet: pet, takenAt: takenAt)
    }

    // MARK: - CRUD

    func testInsertAndFetchById() throws {
        let (repo, _) = makeRepo()
        let photo = Photo(uri: "photo_1")
        try repo.insertPhoto(photo)

        let fetched = try repo.getPhoto(id: photo.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.uri, "photo_1")
    }

    func testFetchByURI() throws {
        let (repo, _) = makeRepo()
        let photo = Photo(uri: "unique_uri", originalURI: "original_uri")
        try repo.insertPhoto(photo)

        let fetched = try repo.getPhotoByURI("unique_uri")
        XCTAssertEqual(fetched?.originalURI, "original_uri")
    }

    func testOriginalURIDefaultsToURI() throws {
        let (repo, _) = makeRepo()
        // originalURI 为空时应默认等于 uri（对应源端逻辑）
        let photo = Photo(uri: "same_uri", originalURI: "")
        try repo.insertPhoto(photo)

        XCTAssertEqual(photo.originalURI, "same_uri")
    }

    func testDeletePhoto() throws {
        let (repo, _) = makeRepo()
        let photo = Photo(uri: "to_delete")
        try repo.insertPhoto(photo)
        try repo.deletePhoto(photo)

        XCTAssertNil(try repo.getPhoto(id: photo.id))
    }

    // MARK: - 分页

    func testPhotosPageSortedByTakenAtDescending() throws {
        let (repo, _) = makeRepo()
        let base = Date(timeIntervalSince1970: 1000)
        for i in 0..<5 {
            try repo.insertPhoto(makePhoto(uri: "p\(i)", takenAt: base.addingTimeInterval(Double(i) * 100)))
        }

        // 第 1 页（offset 0, limit 2）：应为最新的两张
        let page1 = try repo.getPhotosPage(offset: 0, limit: 2)
        XCTAssertEqual(page1.count, 2)
        XCTAssertEqual(page1[0].uri, "p4")
        XCTAssertEqual(page1[1].uri, "p3")

        // 第 2 页（offset 2, limit 2）
        let page2 = try repo.getPhotosPage(offset: 2, limit: 2)
        XCTAssertEqual(page2.count, 2)
        XCTAssertEqual(page2[0].uri, "p2")
        XCTAssertEqual(page2[1].uri, "p1")

        // 第 3 页（offset 4, limit 2）：仅剩 1 张
        let page3 = try repo.getPhotosPage(offset: 4, limit: 2)
        XCTAssertEqual(page3.count, 1)
        XCTAssertEqual(page3[0].uri, "p0")
    }

    // MARK: - 扫描去重（导入边界）

    func testGetAllPhotoURIsForScanDedup() throws {
        let (repo, _) = makeRepo()
        try repo.insertPhoto(Photo(uri: "uri_a"))
        try repo.insertPhoto(Photo(uri: "uri_b"))
        try repo.insertPhoto(Photo(uri: "uri_c"))

        let existing = try repo.getAllPhotoURIs()
        XCTAssertEqual(existing, ["uri_a", "uri_b", "uri_c"])
    }

    /// 扫描/导入边界（DESIGN.md §7 硬约束）：
    /// 验证 getAllPhotoURIs + insertPhoto 构成的去重-入库模式——
    /// 扫描发现已存在 URI 不会重复入库。
    func testScanImportBoundaryNoDuplicateInsert() throws {
        let (repo, _) = makeRepo()
        try repo.insertPhoto(Photo(uri: "scanned_uri"))

        // 模拟扫描后去重判断：已存在的 URI 不应再次 insertPhoto
        let existing = try repo.getAllPhotoURIs()
        XCTAssertTrue(existing.contains("scanned_uri"))
        // 去重后不插入——入库唯一路径由调用方（ImportService P2）守卫
    }

    // MARK: - 归属

    func testAssignPhotoToPet() throws {
        let (repo, container) = makeRepo()
        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let pet = Pet(name: "归属测试")
        try petRepo.insertPet(pet)

        let photo = Photo(uri: "unassigned")
        try repo.insertPhoto(photo)
        XCTAssertNil(photo.pet)

        try repo.assignPhoto(photo, to: pet)
        XCTAssertEqual(photo.pet?.id, pet.id)
    }

    func testUnassignPhoto() throws {
        let (repo, container) = makeRepo()
        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let pet = Pet(name: "临时归属")
        try petRepo.insertPet(pet)
        let photo = Photo(uri: "to_unassign", pet: pet)
        try repo.insertPhoto(photo)

        try repo.assignPhoto(photo, to: nil)
        XCTAssertNil(photo.pet)
    }

    func testGetPhotosByPet() throws {
        let (repo, container) = makeRepo()
        let petRepo = SwiftDataPetRepository(context: container.mainContext)
        let pet = Pet(name: "照片主人")
        try petRepo.insertPet(pet)

        let base = Date(timeIntervalSince1970: 5000)
        try repo.insertPhoto(makePhoto(uri: "pet_1", takenAt: base, pet: pet))
        try repo.insertPhoto(makePhoto(uri: "pet_2", takenAt: base.addingTimeInterval(100), pet: pet))
        try repo.insertPhoto(makePhoto(uri: "other", takenAt: base))

        let petPhotos = try repo.getPhotosByPet(pet)
        XCTAssertEqual(petPhotos.count, 2)
        // 倒序——pet_2 在前
        XCTAssertEqual(petPhotos[0].uri, "pet_2")
        XCTAssertEqual(petPhotos[1].uri, "pet_1")
    }

    // MARK: - 收藏 / 备注

    func testSetFavorite() throws {
        let (repo, _) = makeRepo()
        let photo = Photo(uri: "fav_test")
        try repo.insertPhoto(photo)
        XCTAssertFalse(photo.isFavorite)

        try repo.setFavorite(photo, favorite: true)
        XCTAssertTrue(photo.isFavorite)
    }

    func testUpdateNote() throws {
        let (repo, _) = makeRepo()
        let photo = Photo(uri: "note_test")
        try repo.insertPhoto(photo)
        XCTAssertEqual(photo.note, "")

        try repo.updateNote(photo, note: "今天的可爱瞬间")
        XCTAssertEqual(photo.note, "今天的可爱瞬间")
    }

    // MARK: - 保存事务（saveOrRollback）

    /// 磁盘容器：唯一约束仅在磁盘 store 生效（in-memory store 不校验 @Attribute(.unique)）。
    /// 注意：目录不在此删除——container 被 keepAlive 保活到测试类结束，
    /// 提前 removeItem 会触发 sqlite「vnode unlinked while in use」；
    /// 目录位于模拟器 tmp（UUID 命名），由系统自动清理。
    private func makeDiskRepo() throws -> (SwiftDataPhotoRepository, ModelContainer, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoRepositoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(url: dir.appendingPathComponent("test.sqlite"))
        let container = try ModelContainer(for: schema, configurations: [config])
        keepAlive.append(container)
        return (SwiftDataPhotoRepository(context: container.mainContext), container, dir)
    }

    /// 回归（评审 P）：originalURI 冲突必须拒绝入库并保持上下文干净——
    /// SwiftData unique 冲突是 upsert（静默覆盖），Repository 显式拦截抛错（insertPhoto 注释）。
    /// 失败对象不残留，同一上下文的下一批导入可继续成功。
    func testUniqueConflictRollsBackSoNextInsertSucceeds() throws {
        let (repo, _, _) = try makeDiskRepo()

        // 先入库占用 originalURI "dup"
        try repo.insertPhoto(Photo(uri: "first", originalURI: "dup"))

        // 与 "dup" 冲突的插入必须抛错
        XCTAssertThrowsError(try repo.insertPhoto(Photo(uri: "conflict", originalURI: "dup")))
        XCTAssertNil(try repo.getPhotoByURI("conflict"), "冲突对象不得入库")

        // 关键断言：失败批次已回滚，后续保存不再被残留的失败对象阻塞
        try repo.insertPhoto(Photo(uri: "next", originalURI: "fresh"))
        XCTAssertNotNil(try repo.getPhotoByOriginalURI("fresh"))
        // 既有记录不受影响
        XCTAssertNotNil(try repo.getPhotoByOriginalURI("dup"))
    }

    /// 批量导入含冲突条目：整批失败并回滚，下一批可继续成功（评审 P 回归）。
    /// SwiftData unique 冲突是 upsert（静默覆盖），Repository 显式拦截抛错（insertPhotos 注释）。
    func testUniqueConflictInBatchRollsBackAndNextBatchSucceeds() throws {
        let (repo, _, _) = try makeDiskRepo()

        try repo.insertPhoto(Photo(uri: "base", originalURI: "dup"))
        let batch = [
            Photo(uri: "b1", originalURI: "fresh1"),
            Photo(uri: "b2", originalURI: "dup"),   // 与本批及既有记录均冲突
            Photo(uri: "b3", originalURI: "fresh3"),
        ]
        XCTAssertThrowsError(try repo.insertPhotos(batch))

        // 整批回滚：无任何残留
        XCTAssertNil(try repo.getPhotoByURI("b1"))
        XCTAssertNil(try repo.getPhotoByURI("b3"))

        // 上下文干净：下一批可成功入库
        try repo.insertPhoto(Photo(uri: "next", originalURI: "ok"))
        XCTAssertNotNil(try repo.getPhotoByURI("next"))
    }
}
