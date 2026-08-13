//  PhotoAssignmentLogic —— 照片归属/移出的纯逻辑编排。
//
//  职责（DESIGN.md §7 扫描只筛选不入库；归属写入唯一入库路径在导入/手动操作）：
//  - assign：将一组照片归属到指定宠物（nil = 移出归属），
//    通过 photoRepo.batchAssignPhotos 在单次事务内完成归属写入 + 受影响宠物 photoCount 刷新，
//    保证关系与计数的原子性。
//
//  受影响宠物集合 = 各照片旧宠物 ∪ {目标宠物}（去重），确保：
//  - 归属到新宠物：新宠物计数 +N，旧宠物计数 -N（若不同）
//  - 移出归属（nil）：旧宠物计数 -N
//  - 幂等（归属到同一宠物）：旧=新，计数不变
//
//  本逻辑是唯一的"归属 + 计数同步"入口，
//  供 ViewModelFactory.assignPhotos（手动归属）、GalleryViewModel（导入强制归属）
//  和 AppDependencies（引导导入强制归属）复用。

/// 照片归属/移出的纯逻辑编排（@MainActor——仓储均为 MainActor 隔离）。
enum PhotoAssignmentLogic {

    /// 将 photos 归属到 targetPet（nil = 移出归属），单次事务内同步刷新受影响宠物的 photoCount 缓存。
    /// - Parameters:
    ///   - photos: 待归属的照片列表（空列表直接返回）
    ///   - targetPet: 目标宠物（nil = 移出归属，不归属任何宠物）
    ///   - photoRepo: 照片仓储（执行原子批量归属写入）
    ///   - petRepo: 宠物仓储（保留兼容签名，批量方法内部完成计数刷新）
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
        // 原子批量：关系变更 + 计数刷新在单次 saveOrRollback 中提交。
        // 任一步骤失败回滚全部 pending changes，不留部分归属或计数不一致的中间态。
        return try photoRepo.batchAssignPhotos(photos, to: targetPet)
    }
}
