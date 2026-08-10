//  TimelineExportLogic —— 成长时间线导出数据准备（ADR-0010 §5）。
//
//  纯函数：从 TimelineMonth[] 准备导出视图所需的数据结构。
//  不依赖 SwiftUI，可单元测试。
//  DESIGN.md §4：纯决策逻辑。

import Foundation

/// 时间线导出数据（供 TimelineExportCanvas 渲染）。
struct TimelineExportData: Equatable, Sendable {
    /// 导出标题（如「全部宠物」或宠物名）。
    let title: String
    /// 日期范围文案（如「2024-01 — 2026-08」）。
    let dateRangeText: String
    /// 总条目数。
    let entryCount: Int
    /// 按月分组（复用 TimelineMonth 投影）。
    let months: [TimelineMonth]
    /// 是否包含底部水印签名。
    let includeWatermark: Bool
}

enum TimelineExportLogic {

    /// 从时间线月份构建导出数据。
    /// - Parameters:
    ///   - months: 当前筛选后的月份列表。
    ///   - filterTitle: 筛选标题（「全部宠物」或指定宠物名）。
    ///   - includeWatermark: 免费版带水印，Pro 无水印。
    ///   - calendar: 日历（注入保证可测）。
    ///   - locale: 文案语言（默认当前环境；测试传固定 locale）。
    /// - Returns: 导出数据；月份为空时返回 nil。
    static func buildExportData(
        months: [TimelineMonth],
        filterTitle: String,
        includeWatermark: Bool,
        calendar: Calendar = PetDateCalendar.gregorian,
        locale: Locale = .current
    ) -> TimelineExportData? {
        guard !months.isEmpty else { return nil }

        let entryCount = months.reduce(0) { $0 + $1.entries.count }
        let dateRangeText = buildDateRange(from: months, calendar: calendar, locale: locale)

        return TimelineExportData(
            title: filterTitle,
            dateRangeText: dateRangeText,
            entryCount: entryCount,
            months: months,
            includeWatermark: includeWatermark
        )
    }

    /// 从月份列表提取日期范围文案。
    /// 最早月份 → 最晚月份，格式「YYYY-MM — YYYY-MM」（占位符经本地化 key 拼接）。
    private static func buildDateRange(
        from months: [TimelineMonth], calendar: Calendar, locale: Locale
    ) -> String {
        guard let first = months.first, let last = months.last else { return "" }
        if first.yearMonth == last.yearMonth {
            return first.yearMonth
        }
        return String(localized: "timeline.export.dateRange \(first.yearMonth) \(last.yearMonth)", locale: locale)
    }
}
