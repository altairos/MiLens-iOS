import XCTest
import SwiftData
@testable import MiLens

/// P1.2 宠物档案仓储测试（in-memory SwiftData）。
/// 覆盖 CRUD、排序、照片计数刷新、关系删除规则（cascade events / nullify photos）。
@MainActor
final class PetRepositoryTests: XCTestCase {

    private func makeRepo() -> (SwiftDataPetRepository, ModelContainer) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: SchemaV1.models, configurations: [config])
        let repo = SwiftDataPetRepository(context: container.mainContext)
        return (repo, container)
    }

    // MARK: - CRUD

    func testInsertAndFetchById() throws {
        let (repo, _) = makeRepo()
        let pet = Pet(name: "小橘", species: .cat, gender: .male)
        try repo.insertPet(pet)

        let fetched = try repo.getPet(id: pet.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "小橘")
        XCTAssertEqual(fetched?.species, .cat)
        XCTAssertEqual(fetched?.gender, .male)
    }

    func testGetAllPetsSortedByCreation() throws {
        let (repo, _) = makeRepo()
        let p1 = Pet(name: "A", createdAt: Date(timeIntervalSince1970: 100))
        let p2 = Pet(name: "B", createdAt: Date(timeIntervalSince1970: 200))
        try repo.insertPet(p2)
        try repo.insertPet(p1)

        let pets = try repo.getAllPets()
        XCTAssertEqual(pets.count, 2)
        XCTAssertEqual(pets[0].name, "A")
        XCTAssertEqual(pets[1].name, "B")
    }

    func testUpdatePet() throws {
        let (repo, _) = makeRepo()
        let pet = Pet(name: "原名")
        try repo.insertPet(pet)

        let originalUpdated = pet.updatedAt
        pet.name = "新名字"
        try repo.updatePet(pet)

        XCTAssertEqual(pet.name, "新名字")
        XCTAssertGreaterThanOrEqual(pet.updatedAt, originalUpdated)
    }

    func testDeletePet() throws {
        let (repo, _) = makeRepo()
        let pet = Pet(name: "待删除")
        try repo.insertPet(pet)
        XCTAssertEqual(try repo.getAllPets().count, 1)

        try repo.deletePet(pet)
        XCTAssertEqual(try repo.getAllPets().count, 0)
        XCTAssertNil(try repo.getPet(id: pet.id))
    }

    // MARK: - 照片计数

    func testRefreshPhotoCount() throws {
        let (petRepo, container) = makeRepo()
        let photoRepo = SwiftDataPhotoRepository(context: container.mainContext)

        let pet = Pet(name: "有照片的猫")
        try petRepo.insertPet(pet)

        // 插入 3 张照片关联到此宠物
        for i in 0..<3 {
            let photo = Photo(uri: "uri_\(i)", pet: pet)
            try photoRepo.insertPhoto(photo)
        }

        try petRepo.refreshPhotoCount(for: pet)
        XCTAssertEqual(pet.photoCount, 3)
    }

    // MARK: - 关系删除规则

    func testDeletePetNullifiesPhotos() throws {
        let (petRepo, container) = makeRepo()
        let photoRepo = SwiftDataPhotoRepository(context: container.mainContext)

        let pet = Pet(name: "将被删除")
        try petRepo.insertPet(pet)
        let photo = Photo(uri: "test_uri", pet: pet)
        try photoRepo.insertPhoto(photo)
        let photoID = photo.id

        // 删除宠物——照片应保留但 pet 变 nil（nullify 规则）
        try petRepo.deletePet(pet)

        let surviving = try photoRepo.getPhoto(id: photoID)
        XCTAssertNotNil(surviving, "删宠物不应删除照片")
        XCTAssertNil(surviving?.pet, "照片归属应被解除")
    }

    func testDeletePetCascadesEvents() throws {
        let (repo, container) = makeRepo()
        let pet = Pet(name: "有事件的宠物")
        try repo.insertPet(pet)

        let event = PetEvent(pet: pet, eventType: "birthday", eventDate: Date(), title: "生日")
        container.mainContext.insert(event)
        try container.mainContext.save()
        let eventID = event.id

        // 删除宠物——事件应级联删除（cascade 规则）
        try repo.deletePet(pet)

        let descriptor = FetchDescriptor<PetEvent>(
            predicate: #Predicate { $0.id == eventID }
        )
        let surviving = try container.mainContext.fetch(descriptor)
        XCTAssertEqual(surviving.count, 0, "删宠物应级联删除纪念事件")
    }
}
