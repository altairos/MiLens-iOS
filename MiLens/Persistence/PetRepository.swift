//  PetRepository —— 宠物档案数据访问（对应源端 repository/PetRepository.ets）。
//  窄接口协议 + SwiftData 实现。业务层只依赖协议，测试注入 mock 或 in-memory container。

import Foundation
import SwiftData

/// 宠物档案仓储协议（@MainActor —— SwiftData ModelContext 隔离）。
@MainActor
protocol PetRepositoryProtocol {
    func getAllPets() throws -> [Pet]
    func getPet(id: UUID) throws -> Pet?
    func insertPet(_ pet: Pet) throws
    func updatePet(_ pet: Pet) throws
    func deletePet(_ pet: Pet) throws
    /// 刷新宠物照片计数缓存（对应源端 updatePetPhotoCount）。
    func refreshPhotoCount(for pet: Pet) throws
}

/// SwiftData 实现的宠物档案仓储。
@MainActor
final class SwiftDataPetRepository: PetRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func getAllPets() throws -> [Pet] {
        let descriptor = FetchDescriptor<Pet>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func getPet(id: UUID) throws -> Pet? {
        let descriptor = FetchDescriptor<Pet>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func insertPet(_ pet: Pet) throws {
        context.insert(pet)
        try context.save()
    }

    func updatePet(_ pet: Pet) throws {
        pet.updatedAt = Date()
        try context.save()
    }

    func deletePet(_ pet: Pet) throws {
        context.delete(pet)
        try context.save()
    }

    func refreshPhotoCount(for pet: Pet) throws {
        // 关系查询——直接计数 photos 数组（SwiftData 延迟加载关系）
        pet.photoCount = pet.photos.count
        pet.updatedAt = Date()
        try context.save()
    }
}
