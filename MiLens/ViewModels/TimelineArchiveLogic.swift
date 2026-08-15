//  TimelineArchiveLogic —— 生命档案增强纯决策逻辑（Life-Archive-Design.md P3.6），
//  从 TimelineLogic.swift 拆出（ADR-0011 §5 规模守卫拆分批次）。
//  含：档案统计快照、置顶记忆选择、相处章节分组、年度回看四组纯函数及其结果类型，
//  以 extension TimelineLogic 命名空间组织，输入输出均为值类型投影。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

// MARK: - 结果类型

/// 档案统计快照：用于档案首页统计带展示。
struct ArchiveStatsResult: Equatable, Sendable {
    /// 照片总数。
    let photoCount: Int
    /// 记忆（事件）总数。
    let memoryCount: Int
    /// 相伴天数（从领养日/首张照片至今）。
    let daysTogether: Int
    /// 作品（编辑产物）数。
    let workCount: Int
    /// 重要日子数（生日 + 领养日 + 用户标记的事件）。
    let importantDayCount: Int
    /// 档案起点日期（最早的记录/照片日期），nil = 无任何记录。
    let archiveOriginDate: Date?
}

/// 置顶记忆选择结果。
struct PinnedMemoryResult: Equatable, Sendable {
    /// 条目 id（用于定位与删除关联）。
    let entryID: String
    /// 标题。
    let title: String
    /// 正文（用户记录可能有）。
    let bodyText: String
    /// 日期标签。
    let date: Date?
    /// 关联照片 ID（可能为 nil）。
    let photoID: UUID?
    /// 来源标签。
    let sourceType: String
}

/// 章节分组结果：按日期范围将条目分组为「相处章节」。
struct ChapterGroup: Equatable, Sendable {
    /// 章节起始日期。
    let startDate: Date
    /// 章节结束日期。
    let endDate: Date
    /// 章节标题（自动推导或用户自定义）。
    let title: String
    /// 章节包含的条目。
    let entries: [TimelineEntry]
    /// 是否为最后一个章节（用于「继续记录」入口判定）。
    let isLastChapter: Bool
}

/// 年度回看快照：用于首页「年度回忆」入口。
struct YearlyRecapResult: Equatable, Sendable {
    /// 年份。
    let year: Int
    /// 该年精选条目（按质量分/日期排序）。
    let highlights: [TimelineEntry]
    /// 该年总记录数。
    let totalCount: Int
    /// 月度代表（每月最多一条，用于网格预览）。
    let monthlyPicks: [Int: TimelineEntry] // month (1-12) → entry
}

// MARK: - 纯决策函数（生命档案增强）

extension TimelineLogic {

    // ─── 档案统计 ───

    /// 计算档案统计快照（对照 Life-Archive-Design.md §3.1 统计带）。
    ///
    /// - Parameters:
    ///   - photoCount: 照片总数。
    ///   - events: 纪念事件列表。
    ///   - photos: 照片列表（用于作品计数与起点日期）。
    ///   - adoptionDay: 领养日（用于相伴天数）。
    ///   - now: 当前时间。
    ///   - calendar: 日历。
    /// - Returns: 统计快照。
    static func computeArchiveStats(
        photoCount: Int,
        events: [TimelinePetEvent],
        photos: [TimelinePhoto],
        adoptionDay: Date?,
        now: Date,
        calendar: Calendar = PetDateCalendar.gregorian
    ) -> ArchiveStatsResult {
        let workCount = photos.filter { $0.uri.contains("/Edits/") }.count

        // 重要日子：生日 + 领养日 + 用户标记事件（每个事件算一个重要日子）
        let userEvents = events.filter { $0.sourceType == "user" || $0.eventType == "birthday" || $0.eventType == "adoption" }
        let importantDayCount = userEvents.count

        // 档案起点：最早的事件日期或照片日期
        let eventDates = events.map { $0.eventDate }
        let photoDates = photos.compactMap { $0.takenAt }
        let allDates = eventDates + photoDates
        let archiveOriginDate = allDates.min()

        // 相伴天数
        let daysTogether: Int
        if let origin = adoptionDay {
            daysTogether = max(0, calendar.dateComponents([.day], from: origin, to: now).day ?? 0)
        } else if let origin = archiveOriginDate {
            daysTogether = max(0, calendar.dateComponents([.day], from: origin, to: now).day ?? 0)
        } else {
            daysTogether = 0
        }

        return ArchiveStatsResult(
            photoCount: photoCount,
            memoryCount: events.count,
            daysTogether: daysTogether,
            workCount: workCount,
            importantDayCount: importantDayCount,
            archiveOriginDate: archiveOriginDate
        )
    }

    // ─── 置顶记忆选择 ───

    /// 从事件列表中选择置顶记忆（对照 Life-Archive-Design.md §3.2）。
    ///
    /// 优先级：isPinned 事件 > 用户文本记忆（sourceType="user" 且 body 非空）> 无置顶（返回 nil）。
    /// 多个候选取最近日期的一个。
    ///
    /// - Parameters:
    ///   - events: 事件列表。
    ///   - pinnedEventIDs: 被置顶的事件 ID 集合（对应 PetEvent.isPinned）。
    /// - Returns: 置顶记忆结果，无候选时返回 nil。
    static func selectPinnedMemory(
        events: [TimelinePetEvent],
        pinnedEventIDs: Set<UUID>,
        calendar: Calendar = PetDateCalendar.gregorian
    ) -> PinnedMemoryResult? {
        // 优先 isPinned 事件
        let pinnedEvents = events.filter { pinnedEventIDs.contains($0.id) }
        let candidates = pinnedEvents.isEmpty
            ? events.filter { $0.sourceType == "user" && !$0.body.isEmpty }
            : pinnedEvents

        guard let chosen = candidates.sorted(by: { $0.eventDate > $1.eventDate }).first else {
            return nil
        }

        return PinnedMemoryResult(
            entryID: chosen.id.uuidString,
            title: chosen.title.isEmpty
                ? String(localized: "timeline.memoryType.text")
                : chosen.title,
            bodyText: chosen.body,
            date: chosen.eventDate,
            photoID: chosen.relatedPhotoID,
            sourceType: chosen.sourceType
        )
    }

    // ─── 日期范围章节分组 ───

    /// 按日期范围将条目分组为「相处章节」（对照 Life-Archive-Design.md §3.4）。
    ///
    /// 章节以年为边界自动划分；未命名章节只显示日期范围，不臆测宠物生命阶段。
    /// 每个章节标题用公式自动推导（「一起生活的第N年」），自定义命名属 P1 扩展。
    ///
    /// - Parameters:
    ///   - entries: 时间线条目。
    ///   - customNames: 可选的自定义章节名（年份 → 名称）。
    ///   - now: 当前时间。
    ///   - calendar: 日历。
    /// - Returns: 按时间正序排列的章节列表。
    static func buildDateRangeChapters(
        entries: [TimelineEntry],
        customNames: [Int: String] = [:],
        now: Date,
        calendar: Calendar = PetDateCalendar.gregorian
    ) -> [ChapterGroup] {
        // 按年份分组
        var yearMap: [Int: [TimelineEntry]] = [:]
        for entry in entries {
            guard let date = entry.date else { continue }
            let year = calendar.component(.year, from: date)
            yearMap[year, default: []].append(entry)
        }

        let sortedYears = yearMap.keys.sorted()
        let totalYears = sortedYears.count

        return sortedYears.enumerated().map { idx, year in
            let yearEntries = yearMap[year] ?? []
            let dates = yearEntries.compactMap { $0.date }
            let startDate = dates.min() ?? now
            let endDate = dates.max() ?? now

            // 标题：自定义名 > 公式推导（复用已有 timeline.chapter.together key）
            let title: String
            if let custom = customNames[year] {
                title = custom
            } else {
                title = String(localized: "timeline.chapter.together \(idx + 1)")
            }

            return ChapterGroup(
                startDate: startDate,
                endDate: endDate,
                title: title,
                entries: yearEntries,
                isLastChapter: idx == totalYears - 1
            )
        }
    }

    // ─── 年度回看 ───

    /// 构建年度回看快照（对照首页「年度回忆」入口 + RecapView）。
    ///
    /// - Parameters:
    ///   - entries: 时间线条目。
    ///   - year: 目标年份。
    ///   - calendar: 日历。
    /// - Returns: 年度回看结果；该年无记录时返回空快照。
    static func buildYearlyRecap(
        entries: [TimelineEntry],
        year: Int,
        calendar: Calendar = PetDateCalendar.gregorian
    ) -> YearlyRecapResult {
        let yearEntries = entries.filter { entry in
            guard let date = entry.date else { return false }
            return calendar.component(.year, from: date) == year
        }

        // 月度代表：每月取第一条（已按日期排序）
        var monthlyPicks: [Int: TimelineEntry] = [:]
        for entry in yearEntries {
            guard let date = entry.date else { continue }
            let month = calendar.component(.month, from: date)
            if monthlyPicks[month] == nil {
                monthlyPicks[month] = entry
            }
        }

        // 精选：最多 12 条（每月最多 1 条）
        let highlights = Array(monthlyPicks.values.sorted { a, b in
            (a.date ?? .distantPast) < (b.date ?? .distantPast)
        })

        return YearlyRecapResult(
            year: year,
            highlights: highlights,
            totalCount: yearEntries.count,
            monthlyPicks: monthlyPicks
        )
    }

    // ─── 删除/取消关联边界 ───

    /// 删除事件后计算剩余重要日子数（验证删除/取消关联后的统计一致性）。
    /// 用于确认删除置顶记忆后档案统计正确更新。
    ///
    /// - Parameters:
    ///   - events: 剩余事件列表。
    ///   - removedEventID: 被删除的事件 ID。
    /// - Returns: 剩余重要日子数。
    static func importantDayCountAfterRemoval(
        events: [TimelinePetEvent],
        removedEventID: UUID
    ) -> Int {
        let remaining = events.filter { $0.id != removedEventID }
        let userEvents = remaining.filter {
            $0.sourceType == "user" || $0.eventType == "birthday" || $0.eventType == "adoption"
        }
        return userEvents.count
    }
}
