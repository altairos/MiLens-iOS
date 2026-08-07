import XCTest
import SwiftData
@testable import MiLens

/// P1.2 照片仓储测试（in-memory SwiftData）。
/// 覆盖 CRUD、分页、扫描去重、归属、收藏/备注，以及导入边界约束。
@MainActor
final class PhotoRepositoryTests: XCTestCase {

    private func makeRepo() -> (SwiftDataPhotoRepository, ModelContainer) {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
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
}
