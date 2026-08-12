//  QuotaGatingLogic —— 配额降级门控纯函数（ADR-0010 §10.1 扩展）。
//
//  处理「Pro 期间导入 >50 张照片，订阅到期降级后超额照片成为僵尸数据」的缺陷。
//  策略：超额照片「可见但锁定」（最新 50 张可见，更早的显示锁标蒙层、可删除但不可
//  进大图/创作）；降级且超额时弹一次温和提示（续费恢复 / 清理释放空间）。
//
//  所有判定为纯函数，输入状态输出决策，不访问 IO，可单测（DESIGN.md §4 决策下沉）。

import Foundation

enum QuotaGatingLogic {

    // MARK: - 超额计算

    /// 超出免费配额的照片张数。Pro 用户或未超额返回 0。
    /// - Parameters:
    ///   - photoCount: 当前已存储的照片总数
    ///   - isPro: 当前是否为 Pro 权益
    /// - Returns: 超出 `CommercialRules.freePhotoLimit` 的张数
    static func overLimitCount(photoCount: Int, isPro: Bool) -> Int {
        guard !isPro else { return 0 }
        return max(0, photoCount - CommercialRules.freePhotoLimit)
    }

    // MARK: - 锁定照片集合

    /// 返回应被锁定的照片 ID 集合。
    ///
    /// 输入照片列表必须按 `takenAt` **倒序**排列（最新在前），与 `PhotoRepository.getPhotosPage`
    /// 的排序一致。第 `freePhotoLimit` 张之后的照片被锁定。Pro 或不足上限时返回空集合。
    /// - Parameters:
    ///   - photos: 按 takenAt 倒序的照片列表（与 GalleryViewModel.photos 一致）
    ///   - isPro: 当前是否为 Pro 权益
    /// - Returns: 被锁定的照片 ID 集合
    static func lockedPhotoIDs(photos: [Photo], isPro: Bool) -> Set<UUID> {
        guard !isPro, photos.count > CommercialRules.freePhotoLimit else { return [] }
        return Set(photos.dropFirst(CommercialRules.freePhotoLimit).map(\.id))
    }

    // MARK: - 降级检测

    /// 是否应弹出降级提示。
    ///
    /// 四个条件全部满足才返回 true：
    /// 1. 上次已知状态是 Pro（排除从未购买的用户）
    /// 2. 当前已不是 Pro（发生降级）
    /// 3. 照片总数超过免费上限（有超额数据需要处理）
    /// 4. 本次降级尚未提示过（防重复打扰）
    static func shouldPromptDowngrade(
        lastKnownIsPro: Bool, currentIsPro: Bool,
        photoCount: Int, promptPending: Bool
    ) -> Bool {
        lastKnownIsPro
            && !currentIsPro
            && photoCount > CommercialRules.freePhotoLimit
            && !promptPending
    }

    // MARK: - 提示重置

    /// 续费后是否应重置降级提示标记。
    ///
    /// 用户重新变为 Pro 后重置 `quotaDowngradePromptPending`，为下一次降级周期准备。
    static func promptShouldReset(isPro: Bool) -> Bool {
        isPro
    }
}
