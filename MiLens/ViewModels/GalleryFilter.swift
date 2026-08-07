//  GalleryFilter —— 相册筛选条件（对应源端 viewmodels/GalleryViewModel.ets GalleryFilter）。
//  petID 为 nil 表示「全部宠物」（对应源端 petId=-1）。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖，XCTest 完整覆盖。

import Foundation

struct GalleryFilter: Equatable, Sendable {
    /// 归属宠物筛选；nil = 全部（对应源端 petId=-1）
    var petID: UUID? = nil
    /// 日期范围标签（如「近7天」，空串 = 不限）
    var dateRange: String = ""
    /// 地点筛选标签（空串 = 不限）
    var location: String = ""

    /// 默认空筛选条件（对应源端 GalleryViewModel.emptyFilter()）
    static let empty = GalleryFilter()
}
