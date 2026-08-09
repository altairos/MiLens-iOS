//  PetPhotoCategoryLogicTests —— 档案照片分类逻辑测试（P3）。
//  覆盖：三分段筛选（全部/待整理/作品）、计数、编辑产物标记、
//  仓储 getUnassignedPhotos（SwiftData in-memory 集成断言）。
//  对应 UI-DESIGN.md §6.4：分类只显示可靠来源维度，V1 无自动「幼年/玩耍/睡觉」。

import XCTest
import SwiftData
@testable import MiLens

@MainActor
final class PetPhotoCategoryLogicTests: XCTestCase {

    private func makePhoto(
        id: UUID = UUID(),
        uri: String = "/documents/MiPhotos/a.jpg",
        originalURI: String = "",
        category: String = PhotoCategory.unknown.rawValue,
        takenAt: Date? = nil
    ) -> Photo {
        Photo(uri: uri, originalURI: originalURI, takenAt: takenAt, category: category)
    }

    // MARK: - 纯逻辑筛选

    func testFilterAllReturnsPetPhotos() {
        let petPhotos = [makePhoto(), makePhoto(category: PhotoCategory.edited.rawValue)]
        let result = PetPhotoCategoryLogic.filter(
            petPhotos: petPhotos, unassigned: [], category: .all)
        XCTAssertEqual(result.count, 2)
    }

    func testFilterEditedOnlyReturnsEditedPhotos() {
        let edited = makePhoto(category: PhotoCategory.edited.rawValue)
        let petPhotos = [makePhoto(), edited, makePhoto(category: PhotoCategory.petPhoto.rawValue)]
        let result = PetPhotoCategoryLogic.filter(
            petPhotos: petPhotos, unassigned: [], category: .edited)
        XCTAssertEqual(result.map(\.id), [edited.id])
    }

    func testFilterUnassignedUsesUnassignedCollection() {
        let unassigned = [makePhoto(uri: "/documents/MiPhotos/u.jpg")]
        let result = PetPhotoCategoryLogic.filter(
            petPhotos: [], unassigned: unassigned, category: .unassigned)
        XCTAssertEqual(result.map(\.id), [unassigned[0].id])
    }

    func testFilterUnassignedIgnoresPetPhotos() {
        // 待整理数据源独立于当前宠物照片：宠物照片即使 category 非 edited 也不混入
        let petPhotos = [makePhoto(), makePhoto()]
        let unassigned = [makePhoto(uri: "/documents/MiPhotos/u.jpg")]
        let result = PetPhotoCategoryLogic.filter(
            petPhotos: petPhotos, unassigned: unassigned, category: .unassigned)
        XCTAssertEqual(result.count, 1)
    }

    func testCountMatchesFilterLength() {
        let petPhotos = [
            makePhoto(),
            makePhoto(category: PhotoCategory.edited.rawValue),
            makePhoto(category: PhotoCategory.edited.rawValue)
        ]
        let unassigned = [makePhoto(uri: "/documents/MiPhotos/u.jpg")]
        XCTAssertEqual(
            PetPhotoCategoryLogic.count(petPhotos: petPhotos, unassigned: unassigned, category: .all), 3)
        XCTAssertEqual(
            PetPhotoCategoryLogic.count(petPhotos: petPhotos, unassigned: unassigned, category: .edited), 2)
        XCTAssertEqual(
            PetPhotoCategoryLogic.count(petPhotos: petPhotos, unassigned: unassigned, category: .unassigned), 1)
    }

    func testIsEditedPhoto() {
        XCTAssertTrue(PetPhotoCategoryLogic.isEditedPhoto(makePhoto(category: PhotoCategory.edited.rawValue)))
        XCTAssertFalse(PetPhotoCategoryLogic.isEditedPhoto(makePhoto()))
        XCTAssertFalse(PetPhotoCategoryLogic.isEditedPhoto(makePhoto(category: PhotoCategory.petPhoto.rawValue)))
    }

    func testCategoryTitlesAreStable() {
        // 分段标题与设计稿 §6.4 一致（用户可见文案的回归保护）
        XCTAssertEqual(PetPhotoCategory.all.title, "全部照片")
        XCTAssertEqual(PetPhotoCategory.unassigned.title, "待整理")
        XCTAssertEqual(PetPhotoCategory.edited.title, "作品")
        XCTAssertEqual(PetPhotoCategory.profileOrder, [.all, .unassigned, .edited])
    }

    // MARK: - SwiftData 仓储集成

    func testGetUnassignedPhotosReturnsOnlyUnassignedSortedByTakenAt() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let repo = SwiftDataPhotoRepository(context: container.mainContext)
        let petRepo = SwiftDataPetRepository(context: container.mainContext)

        let pet = Pet(name: "咪咪")
        try petRepo.insertPet(pet)
        let old = makePhoto(uri: "/documents/MiPhotos/old.jpg", takenAt: Date(timeIntervalSince1970: 100))
        let recent = makePhoto(uri: "/documents/MiPhotos/recent.jpg", takenAt: Date(timeIntervalSince1970: 200))
        let assigned = makePhoto(uri: "/documents/MiPhotos/assigned.jpg", takenAt: Date(timeIntervalSince1970: 300))
        try repo.insertPhoto(old)
        try repo.insertPhoto(recent)
        try repo.insertPhoto(assigned)
        try repo.assignPhoto(assigned, to: pet)

        let result = try repo.getUnassignedPhotos(limit: 10)
        XCTAssertEqual(result.map(\.uri), ["/documents/MiPhotos/recent.jpg", "/documents/MiPhotos/old.jpg"],
                       "只返回未归属照片且按拍摄时间倒序")
    }

    func testGetUnassignedPhotosRespectsLimit() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let repo = SwiftDataPhotoRepository(context: container.mainContext)

        try repo.insertPhoto(makePhoto(uri: "/documents/MiPhotos/1.jpg"))
        try repo.insertPhoto(makePhoto(uri: "/documents/MiPhotos/2.jpg"))
        try repo.insertPhoto(makePhoto(uri: "/documents/MiPhotos/3.jpg"))

        let result = try repo.getUnassignedPhotos(limit: 2)
        XCTAssertEqual(result.count, 2)
    }

    func testCountAllPhotos() throws {
        // H2：总数走 fetchCount，不物化全表（GalleryViewModel.loadInitial 依赖）
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let repo = SwiftDataPhotoRepository(context: container.mainContext)

        XCTAssertEqual(try repo.countAllPhotos(), 0)
        try repo.insertPhoto(makePhoto(uri: "/documents/MiPhotos/1.jpg"))
        try repo.insertPhoto(makePhoto(uri: "/documents/MiPhotos/2.jpg"))
        XCTAssertEqual(try repo.countAllPhotos(), 2)
    }

    func testGetAllOriginalURIsOnlyFetchesOriginalURI() throws {
        // H2：去重集合只读 originalURI 列（propertiesToFetch），行为与全表等价
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let repo = SwiftDataPhotoRepository(context: container.mainContext)

        try repo.insertPhoto(makePhoto(uri: "/documents/MiPhotos/1.jpg", originalURI: "L0/001"))
        try repo.insertPhoto(makePhoto(uri: "/documents/MiPhotos/2.jpg", originalURI: "L0/002"))
        XCTAssertEqual(try repo.getAllOriginalURIs(), ["L0/001", "L0/002"])
        XCTAssertEqual(try repo.getAllPhotoURIs(), ["/documents/MiPhotos/1.jpg", "/documents/MiPhotos/2.jpg"])
    }
}
