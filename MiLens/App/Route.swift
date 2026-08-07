//  类型安全路由枚举（DESIGN.md §6）。
//  用于 NavigationStack 的 navigationDestination，替代源端 router.pushUrl 字符串路由。
//  P1.1 先定义枚举骨架；具体目标视图随 P2+ 逐步实现。

import Foundation

enum Route: Hashable {
    case photoView(photoID: UUID)
    case petProfile(petID: UUID)
    case beadPattern(photoID: UUID)
    case petEdit(petID: UUID)
}
