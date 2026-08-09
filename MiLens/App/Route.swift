//  类型安全路由枚举（DESIGN.md §6）。
//  用于 NavigationStack 的 navigationDestination，替代源端 router.pushUrl 字符串路由。
//  P1.1 先定义枚举骨架；具体目标视图随 P2+ 逐步实现。

import Foundation

enum Route: Hashable {
    case gallery          // 相册网格（从首页/宠物档案进入）
    case photoView(photoID: UUID)  // 大图查看
    case editor(photoID: UUID)     // 图片编辑器（从大图查看进入）
    case petProfile(petID: UUID)
    case beadPhotoPicker   // 拼豆：选择照片（CreateView 大卡片入口进入）
    case beadPattern(photoID: UUID)
    case petCardPhotoPicker  // 宠物卡片：选择照片（CreateView 入口进入，P4）
    case petCard(photoID: UUID)
    case petEdit(petID: UUID)
    case timeline         // 成长时间线（全部宠物）

    var requiresPro: Bool {
        switch self {
        case .editor, .beadPhotoPicker, .beadPattern:
            true
        default:
            false
        }
    }
}
