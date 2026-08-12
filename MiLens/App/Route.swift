//  类型安全路由枚举（DESIGN.md §6）。
//  用于 NavigationStack 的 navigationDestination，替代源端 router.pushUrl 字符串路由。
//  P1.1 先定义枚举骨架；具体目标视图随 P2+ 逐步实现。

import Foundation
import MiLensKit

enum Route: Hashable {
    case gallery          // 相册网格（从首页/宠物档案进入）
    case photoView(photoID: UUID)  // 大图查看
    case editor(photoID: UUID)     // 图片编辑器（从大图查看进入）
    case petProfile(petID: UUID)
    case beadPhotoPicker   // 拼豆：选择照片（CreateView 大卡片入口进入）
    case beadPattern(photoID: UUID)
    case petCardPhotoPicker  // 宠物卡片：选择照片（CreateView 入口进入，P4）
    case petCard(photoID: UUID, kind: MemoryCardKind?)
    case petEdit(petID: UUID)
    case timeline         // 成长时间线（全部宠物）
    // 成长对比卡片（ADR-0010 §3.3，Stage 2）
    case growthComparePhotoPicker
    case growthCompare(earlyPhotoID: UUID, latePhotoID: UUID, petID: UUID?)
    // 宠物名片卡（创作 Tab 新增项目，信息导向社交分享）
    case businessCardPicker
    case businessCard(petID: UUID)
    // 微信红包封面（创作 Tab 新增项目，导出规格素材 + 场景预览）
    case redPacketCoverPicker
    case redPacketCover(photoID: UUID, petID: UUID?)
    case redPacketUploadGuide(photoID: UUID, petID: UUID?)
    // 月度精选 / 年度回忆册（情感触点系统 Stage 3）
    case recap(year: Int?)

    /// 便捷构造：不带 kind 的纪念卡路由（保持调用点简洁）。
    static func petCard(photoID: UUID) -> Route {
        .petCard(photoID: photoID, kind: nil)
    }

    var requiresPro: Bool {
        // 当前 V1 的创作入口均可体验；未来模板等细粒度权益在功能层门控。
        false
    }
}
