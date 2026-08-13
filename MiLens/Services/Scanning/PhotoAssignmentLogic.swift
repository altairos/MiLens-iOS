//  PhotoAssignmentLogic —— 照片归属/移出的纯逻辑编排。
//
//  职责（DESIGN.md §7 扫描只筛选不入库；归属写入唯一入库路径在导入/手动操作）：
//  - assign：将一组照片归属到指定宠物（nil = 移出归属），逐张写入 photoRepo.assignPhoto，
//    并对受影响的宠物（旧归属 + 目标归属）统一刷新 photoCount 缓存。
//
//  受影响宠物集合 = 各照片旧宠物 ∪ {目标宠物}（去重），确保：
//  - 归属到新宠物：新宠物计数 +N，旧宠物计数 -N（若不同）
//  - 移出归属（nil）：旧宠物计数 -N
//  - 幂等（归属到同一宠物）：旧=新，计数不变
//
//  仓储层 assignPhoto(_:to:) 已就绪（含 to:nil），本逻辑是唯一的"归属 + 计数同步"来源，
//  供 ViewModelFactory.assignPhotos（手动归属）和 GalleryViewModel.batchAssignSelected 复用。

/// 照片归属/移出的纯逻辑编排（@MainActor——仓储均为 MainActor 隔离）。
enum PhotoAssignmentLogic {

    /// 将 photos 归属到 targetPet（nil = 移出归属），同步刷新受影响宠物的 photoCount 缓存。
    /// - Parameters:
    ///   - photos: 待归属的照片列表（空列表直接返回）
    ///   - targetPet: 目标宠物（nil = 移出归属，不归属任何宠物）
    ///   - photoRepo: 照片仓储（执行 assignPhoto 写入）
    ///   - petRepo: 宠物仓储（刷新 photoCount 缓存）
    /// - Returns: 受影响（已刷新 photoCount）的宠物列表
    @MainActor
    @discardableResult
    static func assign(
        photos: [Photo],
        to targetPet: Pet?,
        photoRepo: any PhotoRepositoryProtocol,
        petRepo: any PetRepositoryProtocol
    ) throws -> [Pet] {
        guard !photos.isEmpty else { return [] }

        // 收集受影响的宠物 ID（旧归属 + 目标归属），去重
        var affectedPetIDs: Set<UUID> = []
        for photo in photos {
            if let oldPet = photo.pet {
                affectedPetIDs.insert(oldPet.id)
            }
        }
        if let targetPet {
            affectedPetIDs.insert(targetPet.id)
        }

        // 记录原始归属，用于中途失败时回滚到一致的已写入状态。
        let originalPets = photos.map(\.pet)

        // 逐张归属写入（仓储设置 Photo.pet 关系，SwiftData 自动维护 Pet.photos 双向关系）。
        // 中途失败 → 回滚已修改的照片，避免部分已转移、部分未转移的不一致状态。
        for (index, photo) in photos.enumerated() {
            do {
                try photoRepo.assignPhoto(photo, to: targetPet)
            } catch {
                // 回滚 index 之前的所有照片到原始归属
                for rollbackIndex in 0..<index {
                    try? photoRepo.assignPhoto(photos[rollbackIndex], to: originalPets[rollbackIndex])
                }
                throw error
            }
        }

        // 刷新受影响宠物的 photoCount 缓存（对应源端 updatePetPhotoCount）
        var refreshedPets: [Pet] = []
        for petID in affectedPetIDs {
            if let pet = try petRepo.getPet(id: petID) {
                try petRepo.refreshPhotoCount(for: pet)
                refreshedPets.append(pet)
            }
        }
        return refreshedPets
    }
}
