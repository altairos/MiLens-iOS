//  TimelineChapterLogic —— 成长时间线章节/年份筛选纯决策逻辑。
//  从 TimelineView 下沉（audit-6 P1-4：0% 覆盖大文件补测，参照 *Logic 下沉惯例）。
//  纯决策逻辑，无 IO/无 SwiftUI 依赖（DESIGN.md §4）。

import Foundation

/// 时间线章节分组与年份筛选决策（对照 Figma「03·生命时间线」年份选择器 + 章节标题）。
enum TimelineChapterLogic {

    /// 从 months 提取可用年份列表（升序去重）。
    static func availableYears(_ months: [TimelineMonth]) -> [Int] {
        Set(months.map { $0.year }).sorted()
    }

    /// 按选中年份过滤月份组；nil = 全部年份。
    static func filteredByYear(_ months: [TimelineMonth], selectedYear: Int?) -> [TimelineMonth] {
        guard let year = selectedYear else { return months }
        return months.filter { $0.year == year }
    }

    /// 按年份分组月份（组按年份升序，组内保持传入顺序）。
    static func groupByYear(_ months: [TimelineMonth]) -> [(year: Int, months: [TimelineMonth])] {
        let years = Set(months.map { $0.year }).sorted()
        return years.map { year in
            (year: year, months: months.filter { $0.year == year })
        }
    }

    /// 实际高亮的年份：未筛选（nil）时视为最新一年（与 yearChip 的 isSelected 判定一致）。
    static func effectiveSelectedYear(selectedYear: Int?, years: [Int]) -> Int? {
        selectedYear ?? years.last
    }

    /// 相处年数：从时间线最早年份推导「一起生活的第 N 年」（至少 1）。
    /// firstYear 应传全时间线（未筛选）的最早年份；nil 时回退 1。
    /// 修正记录：原 View 实现误传分组内 months，导致每个章节恒为「第 1 年」；
    /// 下沉时按原注释意图（用最早月份年份与当前年份的差）修复（audit-6 P1-4）。
    static func chapterTogetherYears(year: Int, firstYear: Int?) -> Int {
        guard let firstYear else { return 1 }
        return max(1, year - firstYear + 1)
    }

    /// 导出分享用当前筛选标题：选中宠物返回其展示名，否则「全部宠物」。
    /// pets 传 (id, displayName) 轻量投影（displayName 已含物种 emoji 前缀），
    /// 避免 Logic 依赖 SwiftData @Model（TimelineLogic.swift TimelinePet 投影同惯例）。
    static func filterTitle(selectedPetID: UUID?, pets: [(id: UUID, displayName: String)]) -> String {
        if let petID = selectedPetID,
           let pet = pets.first(where: { $0.id == petID }) {
            return pet.displayName
        }
        return String(localized: "timeline.allPets")
    }
}
