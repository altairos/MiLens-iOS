//  PhotoAssignmentLogicTests —— 手动归属/移出纯逻辑测试。
//  覆盖：归属到新宠物、移出、跨宠物转移、幂等、批量、空列表、返回受影响宠物。
//  使用 InMemoryRepositories（assignPhoto 维护双向关系 + refreshPhotoCount 计数，
//  与 SwiftData 行为一致）。

import XCTest
@testable import MiLens

@MainActor
final class PhotoAssignmentLogicTests: XCTestCase {

    // MARK: - 基础归属

    func testAssignToPetUpdatesPhotoCount() throws {
        let pet = Pet(name: "小橘")
        let photo = Photo(uri: "/test/a.jpg", originalURI: "a")
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository(pets: [pet])
        try photoRepo.insertPhoto(photo)

        try PhotoAssignmentLogic.assign(
            photos: [photo], to: pet,
            photoRepo: photoRepo, petRepo: petRepo)

        XCTAssertEqual(photo.pet?.id, pet.id, "照片应归属到目标宠物")
        XCTAssertEqual(pet.photoCount, 1, "目标宠物计数应增加")
    }

    func testUnassignUpdatesPhotoCount() throws {
        let pet = Pet(name: "小橘")
        let photo = Photo(uri: "/test/a.jpg", originalURI: "a")
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository(pets: [pet])
        try photoRepo.insertPhoto(photo)

        // 先归属到 pet
        try PhotoAssignmentLogic.assign(
            photos: [photo], to: pet,
            photoRepo: photoRepo, petRepo: petRepo)
        XCTAssertEqual(pet.photoCount, 1)

        // 移出归属
        try PhotoAssignmentLogic.assign(
            photos: [photo], to: nil,
            photoRepo: photoRepo, petRepo: petRepo)

        XCTAssertNil(photo.pet, "照片应移出归属")
        XCTAssertEqual(pet.photoCount, 0, "原宠物计数应减少")
    }

    // MARK: - 跨宠物转移

    func testTransferBetweenPetsUpdatesBothCounts() throws {
        let petA = Pet(name: "小橘")
        let petB = Pet(name: "黑黑")
        let photo = Photo(uri: "/test/a.jpg", originalURI: "a")
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository(pets: [petA, petB])
        try photoRepo.insertPhoto(photo)

        // 先归属到 petA
        try PhotoAssignmentLogic.assign(
            photos: [photo], to: petA,
            photoRepo: photoRepo, petRepo: petRepo)
        XCTAssertEqual(petA.photoCount, 1)
        XCTAssertEqual(petB.photoCount, 0)

        // 转移到 petB
        try PhotoAssignmentLogic.assign(
            photos: [photo], to: petB,
            photoRepo: photoRepo, petRepo: petRepo)

        XCTAssertEqual(photo.pet?.id, petB.id, "照片归属应转移到 petB")
        XCTAssertEqual(petA.photoCount, 0, "原宠物计数应减少")
        XCTAssertEqual(petB.photoCount, 1, "新宠物计数应增加")
    }

    // MARK: - 幂等

    func testIdempotentAssignmentDoesNotChangeCount() throws {
        let pet = Pet(name: "小橘")
        let photo = Photo(uri: "/test/a.jpg", originalURI: "a")
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository(pets: [pet])
        try photoRepo.insertPhoto(photo)

        // 归属到 pet
        try PhotoAssignmentLogic.assign(
            photos: [photo], to: pet,
            photoRepo: photoRepo, petRepo: petRepo)
        XCTAssertEqual(pet.photoCount, 1)

        // 再次归属到同一宠物
        try PhotoAssignmentLogic.assign(
            photos: [photo], to: pet,
            photoRepo: photoRepo, petRepo: petRepo)

        XCTAssertEqual(photo.pet?.id, pet.id)
        XCTAssertEqual(pet.photoCount, 1, "幂等：计数不应重复增加")
    }

    // MARK: - 批量归属

    func testBatchAssignUpdatesCount() throws {
        let pet = Pet(name: "小橘")
        let p1 = Photo(uri: "/test/1.jpg", originalURI: "1")
        let p2 = Photo(uri: "/test/2.jpg", originalURI: "2")
        let p3 = Photo(uri: "/test/3.jpg", originalURI: "3")
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository(pets: [pet])
        try photoRepo.insertPhoto(p1)
        try photoRepo.insertPhoto(p2)
        try photoRepo.insertPhoto(p3)

        try PhotoAssignmentLogic.assign(
            photos: [p1, p2, p3], to: pet,
            photoRepo: photoRepo, petRepo: petRepo)

        XCTAssertEqual(p1.pet?.id, pet.id)
        XCTAssertEqual(p2.pet?.id, pet.id)
        XCTAssertEqual(p3.pet?.id, pet.id)
        XCTAssertEqual(pet.photoCount, 3, "批量归属后计数应为 3")
    }

    func testBatchTransferUpdatesBothCounts() throws {
        let petA = Pet(name: "小橘")
        let petB = Pet(name: "黑黑")
        let p1 = Photo(uri: "/test/1.jpg", originalURI: "1")
        let p2 = Photo(uri: "/test/2.jpg", originalURI: "2")
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository(pets: [petA, petB])
        try photoRepo.insertPhoto(p1)
        try photoRepo.insertPhoto(p2)

        // 先归属到 petA
        try PhotoAssignmentLogic.assign(
            photos: [p1, p2], to: petA,
            photoRepo: photoRepo, petRepo: petRepo)
        XCTAssertEqual(petA.photoCount, 2)

        // 批量转移到 petB
        try PhotoAssignmentLogic.assign(
            photos: [p1, p2], to: petB,
            photoRepo: photoRepo, petRepo: petRepo)

        XCTAssertEqual(petA.photoCount, 0)
        XCTAssertEqual(petB.photoCount, 2)
    }

    // MARK: - 边界

    func testEmptyPhotosReturnsEmpty() throws {
        let pet = Pet(name: "小橘")
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository(pets: [pet])

        let affected = try PhotoAssignmentLogic.assign(
            photos: [], to: pet,
            photoRepo: photoRepo, petRepo: petRepo)

        XCTAssertTrue(affected.isEmpty, "空照片列表应返回空")
        XCTAssertEqual(pet.photoCount, 0, "无照片归属，计数不变")
    }

    // MARK: - 返回受影响宠物

    func testReturnsAffectedPetsOnTransfer() throws {
        let petA = Pet(name: "小橘")
        let petB = Pet(name: "黑黑")
        let photo = Photo(uri: "/test/a.jpg", originalURI: "a")
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository(pets: [petA, petB])
        try photoRepo.insertPhoto(photo)

        // 先归属到 petA
        try PhotoAssignmentLogic.assign(
            photos: [photo], to: petA,
            photoRepo: photoRepo, petRepo: petRepo)

        // 转移到 petB：受影响 = {petA（旧）, petB（新）}
        let affected = try PhotoAssignmentLogic.assign(
            photos: [photo], to: petB,
            photoRepo: photoRepo, petRepo: petRepo)
        let affectedIDs = Set(affected.map(\.id))

        XCTAssertEqual(affectedIDs, [petA.id, petB.id], "应返回新旧两只宠物")
    }

    func testReturnsOnlyTargetWhenAssigningUnassigned() throws {
        let pet = Pet(name: "小橘")
        let photo = Photo(uri: "/test/a.jpg", originalURI: "a")
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository(pets: [pet])
        try photoRepo.insertPhoto(photo)

        let affected = try PhotoAssignmentLogic.assign(
            photos: [photo], to: pet,
            photoRepo: photoRepo, petRepo: petRepo)

        XCTAssertEqual(affected.count, 1, "无旧归属时只返回目标宠物")
        XCTAssertEqual(affected.first?.id, pet.id)
    }
}
