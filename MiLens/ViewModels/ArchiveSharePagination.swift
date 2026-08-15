//  ArchiveSharePagination —— 成长时间线 / 年度回忆册共享导出分页。
//
//  以 390 × 1260pt 手机阅读画布为规格，把无限长内容拆成图片组。
//  纯函数不依赖 SwiftUI / UIKit，分页边界可由 XCTest 直接守护。

import Foundation
import MiLensKit

struct TimelineArchiveSharePage: Equatable, Sendable {
    let isCover: Bool
    let months: [TimelineMonth]
}

struct AnnualArchiveSharePage: Equatable, Sendable {
    let isCover: Bool
    let months: [MonthlyRecap]
}

enum ArchiveSharePagination {
    /// 封面页余下的时间线内容高度；与 520pt 封面和 76pt 页脚配套。
    static let timelineCoverContentBudget = 624
    /// 普通内容页的安全内容高度，预留页首/页尾留白。
    static let timelineContentBudget = 1_108
    static let monthHeaderHeight = 56
    static let monthSpacing = 16

    /// 年度回忆册封面页展示两个月，后续页每页三个月。
    static let annualCoverMonthCount = 2
    static let annualContentMonthCount = 3

    static func timelinePages(from months: [TimelineMonth]) -> [TimelineArchiveSharePage] {
        var pages: [TimelineArchiveSharePage] = []
        var currentMonths: [TimelineMonth] = []
        var usedHeight = 0

        func currentBudget() -> Int {
            pages.isEmpty ? timelineCoverContentBudget : timelineContentBudget
        }

        func appendCurrentPage() {
            guard !currentMonths.isEmpty else { return }
            pages.append(TimelineArchiveSharePage(isCover: pages.isEmpty, months: currentMonths))
            currentMonths.removeAll(keepingCapacity: true)
            usedHeight = 0
        }

        for month in months where !month.entries.isEmpty {
            for entry in month.entries {
                var startsMonth = currentMonths.last?.yearMonth != month.yearMonth
                var requiredHeight = entryHeight(for: entry.type)
                if startsMonth {
                    requiredHeight += monthHeaderHeight
                    if !currentMonths.isEmpty { requiredHeight += monthSpacing }
                }

                if !currentMonths.isEmpty, usedHeight + requiredHeight > currentBudget() {
                    appendCurrentPage()
                    startsMonth = true
                    requiredHeight = monthHeaderHeight + entryHeight(for: entry.type)
                }

                if startsMonth {
                    currentMonths.append(TimelineMonth(
                        year: month.year,
                        month: month.month,
                        yearMonth: month.yearMonth,
                        isYearStart: currentMonths.isEmpty ? month.isYearStart : false,
                        entries: [entry]
                    ))
                } else if let last = currentMonths.popLast() {
                    currentMonths.append(TimelineMonth(
                        year: last.year,
                        month: last.month,
                        yearMonth: last.yearMonth,
                        isYearStart: last.isYearStart,
                        entries: last.entries + [entry]
                    ))
                }
                usedHeight += requiredHeight
            }
        }

        appendCurrentPage()
        return pages
    }

    static func annualPages(from months: [MonthlyRecap]) -> [AnnualArchiveSharePage] {
        guard !months.isEmpty else { return [] }

        var pages = [AnnualArchiveSharePage(
            isCover: true,
            months: Array(months.prefix(annualCoverMonthCount))
        )]
        var start = min(annualCoverMonthCount, months.count)

        while start < months.count {
            let end = min(start + annualContentMonthCount, months.count)
            pages.append(AnnualArchiveSharePage(
                isCover: false,
                months: Array(months[start..<end])
            ))
            start = end
        }
        return pages
    }

    static func preferredImagePath(thumbnailPath: String, photoURI: String) -> String? {
        let thumbnail = thumbnailPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !thumbnail.isEmpty { return thumbnail }

        let original = photoURI.trimmingCharacters(in: .whitespacesAndNewlines)
        return original.isEmpty ? nil : original
    }

    static func entryHeight(for type: TimelineEntryType) -> Int {
        switch type {
        case .photoNote:
            return 200
        case .workRecord:
            return 156
        case .birthday, .adoption, .textNote:
            return 124
        }
    }
}
