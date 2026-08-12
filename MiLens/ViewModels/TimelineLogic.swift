//  TimelineLogic —— 成长时间线纯决策逻辑
//  （对应源端 viewmodels/TimelineViewModel.ets）。
//
//  从宠物档案、纪念事件、照片构建时间线条目，并按年月分组。
//  所有函数接收不可变投影 + now/Calendar 注入，返回结果，不读取全局状态。
//
//  架构差异：
//  - 源端 id 为自增整数，petId/photoId 用 -1 表示「无」；iOS 用 UUID，nil 表示「无」。
//  - 源端 birthday/takenAt 为 ISO 字符串，用 new Date(string) 解析；
//    iOS 投影用 Date?，纯逻辑用 Calendar 做年/月/日运算。
//  - 源端 now?: number（时间戳）默认 Date.now()；iOS now 为必传参数保证可复现。
//  - 复合 String id（birthday_/retrain_/photo_/pet_）保留用于视图定位与测试断言。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

// MARK: - 投影类型（脱离 SwiftData @Model 以便纯逻辑测试）

/// 时间线输入用的宠物投影（对应源端 TimelineInput.pets）。
struct TimelinePet: Equatable, Sendable {
    let id: UUID
    let name: String
    let birthday: Date?
    /// 是否已注册视觉特征（对应源端 featureBlob != null）。
    let hasFeatureData: Bool
}

/// 时间线输入用的纪念事件投影（对应源端 TimelineInput.petEvents）。
struct TimelinePetEvent: Equatable, Sendable {
    let id: UUID
    let petID: UUID?
    /// "birthday" / "adoption"（对应源端 eventType 字符串）
    let eventType: String
    let eventDate: Date
    let title: String
    /// SchemaV2：用户记录正文（空=纯事件，非空=用户文本记忆）。
    var body: String = ""
    /// SchemaV2：来源标签 "system" / "user" / "work"。
    var sourceType: String = "system"
    /// SchemaV2：关联照片 ID（作品记录回链来源照片；用户记录可关联一张代表照片）。
    var relatedPhotoID: UUID? = nil
}

/// 时间线输入用的照片投影（对应源端 TimelineInput.photoEvents）。
struct TimelinePhoto: Equatable, Sendable {
    let id: UUID
    let petID: UUID?
    let takenAt: Date?
    let note: String
    let uri: String
    let thumbnailPath: String
}

/// 时间线输入聚合（对应源端 TimelineInput）。
struct TimelineInput: Sendable {
    let pets: [TimelinePet]
    let petEvents: [TimelinePetEvent]
    let photoEvents: [TimelinePhoto]
    let now: Date
}

// MARK: - 条目与分组

/// 时间线条目类型（对应源端 TimelineEntry.type）。
enum TimelineEntryType: String, Equatable, Sendable {
    case birthday
    case adoption
    case photoNote   // 源端 'photo_note'
    case textNote    // SchemaV2：用户文本记忆（sourceType="user" 且 body 非空）
    case workRecord  // SchemaV2：作品记录（拼豆等，预留）
}

/// 时间线条目（对应源端 TimelineEntry）。
struct TimelineEntry: Equatable, Identifiable, Sendable {
    let id: String
    let type: TimelineEntryType
    /// nil 表示无有效日期（对应源端空串），排序时按 epoch 0 处理。
    let date: Date?
    let title: String
    let subtitle: String
    /// 归属宠物；nil = 无归属（对应源端 petId = -1）。
    let petID: UUID?
    let petName: String
    /// 关联照片；nil = 非照片事件（对应源端 photoId = -1）。
    let photoID: UUID?
    let photoURI: String
    let thumbnailPath: String
    // SchemaV2 扩展字段
    /// 文本记忆正文（仅 .textNote 使用）。
    var bodyText: String = ""
    /// 来源标签："system" / "user" / "work"（供 UI 显示来源标签）。
    var sourceType: String = "system"
}

/// 年月分组（对应源端 TimelineMonth）。
struct TimelineMonth: Equatable, Sendable {
    let year: Int
    let month: Int
    /// "YYYY-MM" 键（对应源端 yearMonth）
    let yearMonth: String
    /// 是否为该年首个有内容的月份（对应源端 isYearStart）
    var isYearStart: Bool
    let entries: [TimelineEntry]
}

/// 年月可比较键（用于分组排序）。
private struct YearMonth: Comparable, Hashable {
    let year: Int
    let month: Int
    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        return lhs.month < rhs.month
    }
}

// MARK: - 纯决策函数

enum TimelineLogic {

    // ─── 日期格式化（内部用，保证跨 locale 可复现）───

    /// 将 Date 格式化为 "YYYY-MM-DD" 字符串（对应源端条目里的 ISO date 字段）。
    static func isoDateString(from date: Date?, calendar: Calendar = PetDateCalendar.gregorian) -> String {
        guard let date else { return "" }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 将 "YYYY-MM" 格式化为分组键。
    private static func yearMonthKey(_ ym: YearMonth) -> String {
        String(format: "%04d-%02d", ym.year, ym.month)
    }

    // ─── 条目构建 ───

    /// 查找事件关联照片的原图 URI（对应 SchemaV2 relatedPhotoID 回链）。
    /// 无关联或找不到时返回空串（与照片事件回退语义一致）。
    private static func relatedPhotoURI(
        for event: TimelinePetEvent, in photos: [TimelinePhoto]
    ) -> String {
        guard let photoID = event.relatedPhotoID,
              let photo = photos.first(where: { $0.id == photoID }) else { return "" }
        return photo.uri
    }

    /// 查找事件关联照片的缩略图路径（用于卡片预览加载）。
    private static func relatedPhotoThumbnail(
        for event: TimelinePetEvent, in photos: [TimelinePhoto]
    ) -> String {
        guard let photoID = event.relatedPhotoID,
              let photo = photos.first(where: { $0.id == photoID }) else { return "" }
        return photo.thumbnailPath
    }

    /// 构建全部时间线条目（对应源端 buildTimelineEntries）。
    /// 依次纳入：纪念事件 → 历年生日 → 幼宠参考照片提醒 → 照片事件，最后按日期升序排序。
    static func buildTimelineEntries(
        _ input: TimelineInput,
        calendar: Calendar = PetDateCalendar.gregorian,
        locale: Locale = .current
    ) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []

        // 1. 纪念事件（生日/领养日）+ 用户文本记忆（SchemaV2：sourceType="user"）
        for ev in input.petEvents {
            let pet = input.pets.first { $0.id == ev.petID }
            let petName = pet?.name ?? ""

            // SchemaV2：sourceType="user" 且 body 非空 → 构建为文本记忆条目
            if ev.sourceType == "user" && !ev.body.isEmpty {
                let title = ev.title.isEmpty
                    ? String(localized: "timeline.memoryType.text", locale: locale)
                    : ev.title
                entries.append(TimelineEntry(
                    id: "pet_\(ev.id.uuidString)",
                    type: .textNote,
                    date: ev.eventDate,
                    title: title,
                    subtitle: isoDateString(from: ev.eventDate, calendar: calendar),
                    petID: ev.petID,
                    petName: petName,
                    photoID: ev.relatedPhotoID,
                    photoURI: relatedPhotoURI(for: ev, in: input.photoEvents),
                    thumbnailPath: relatedPhotoThumbnail(for: ev, in: input.photoEvents),
                    bodyText: ev.body,
                    sourceType: ev.sourceType
                ))
                continue
            }

            // SchemaV2：sourceType="work" → 作品记录条目（拼豆图纸/伙伴卡片/编辑产物等）。
            // 来源照片通过 relatedPhotoID 回链（Life-Archive-Design.md §3.2）；
            // 拼豆像素级预览属后续功能，此处先以来源照片缩略图承载视觉。
            if ev.sourceType == "work" {
                let title = ev.title.isEmpty
                    ? String(localized: "timeline.memoryType.work", locale: locale)
                    : ev.title
                entries.append(TimelineEntry(
                    id: "pet_\(ev.id.uuidString)",
                    type: .workRecord,
                    date: ev.eventDate,
                    title: title,
                    subtitle: isoDateString(from: ev.eventDate, calendar: calendar),
                    petID: ev.petID,
                    petName: petName,
                    photoID: ev.relatedPhotoID,
                    photoURI: relatedPhotoURI(for: ev, in: input.photoEvents),
                    thumbnailPath: relatedPhotoThumbnail(for: ev, in: input.photoEvents),
                    bodyText: ev.body,
                    sourceType: ev.sourceType
                ))
                continue
            }

            // 系统推导的纪念事件（生日/领养日）
            let title: String
            if !ev.title.isEmpty {
                title = ev.title
            } else if ev.eventType == "birthday" {
                title = String(localized: "timeline.event.birthday \(petName)", locale: locale)
            } else {
                title = String(localized: "timeline.event.adoption \(petName)", locale: locale)
            }
            entries.append(TimelineEntry(
                id: "pet_\(ev.id.uuidString)",
                type: ev.eventType == "birthday" ? .birthday : .adoption,
                date: ev.eventDate,
                title: title,
                subtitle: isoDateString(from: ev.eventDate, calendar: calendar),
                petID: ev.petID,
                petName: petName,
                photoID: nil,
                photoURI: "",
                thumbnailPath: "",
                sourceType: ev.sourceType
            ))
        }

        // 2. 历年生日
        for pet in input.pets {
            guard let birthday = pet.birthday else { continue }
            let bc = calendar.dateComponents([.year, .month, .day], from: birthday)
            let birthYear = bc.year ?? 0
            let birthMonth = bc.month ?? 0
            let birthDay = bc.day ?? 0
            var age = 1
            while true {
                var dc = DateComponents()
                dc.year = birthYear + age
                dc.month = birthMonth
                dc.day = birthDay
                guard let birthdayDate = calendar.date(from: dc), birthdayDate <= input.now else { break }
                entries.append(TimelineEntry(
                    id: "birthday_\(pet.id.uuidString)_age\(age)",
                    type: .birthday,
                    date: birthdayDate,
                    title: String(localized: "timeline.birthday.title \(pet.name) \(age)", locale: locale),
                    subtitle: String(localized: "timeline.birthday.subtitle \(age)", locale: locale),
                    petID: pet.id,
                    petName: pet.name,
                    photoID: nil,
                    photoURI: "",
                    thumbnailPath: ""
                ))
                age += 1
            }
        }

        // 3. 幼宠参考照片提醒（仅已注册特征的宠物，年龄 < 12 个月）
        for pet in input.pets {
            guard let birthday = pet.birthday, pet.hasFeatureData else { continue }
            let bc = calendar.dateComponents([.year, .month], from: birthday)
            let nc = calendar.dateComponents([.year, .month], from: input.now)
            let ageMonths = ((nc.year ?? 0) - (bc.year ?? 0)) * 12 + ((nc.month ?? 0) - (bc.month ?? 0))
            if ageMonths >= 12 { continue }
            let reminderInterval = ageMonths < 6 ? 1 : 2
            let dayComps = calendar.dateComponents([.day], from: birthday)
            let birthYear = bc.year ?? 0
            let birthMonth = bc.month ?? 0
            let birthDay = dayComps.day ?? 1
            var m = reminderInterval
            while m <= ageMonths {
                var dc = DateComponents()
                dc.year = birthYear
                dc.month = birthMonth + m
                dc.day = birthDay
                guard let reminderDate = calendar.date(from: dc), reminderDate <= input.now else { break }
                entries.append(TimelineEntry(
                    id: "retrain_\(pet.id.uuidString)_m\(m)",
                    type: .photoNote,
                    date: reminderDate,
                    title: String(localized: "timeline.reference.update.title \(pet.name)", locale: locale),
                    subtitle: String(localized: "timeline.reference.update.subtitle \(pet.name)", locale: locale),
                    petID: pet.id,
                    petName: pet.name,
                    photoID: nil,
                    photoURI: "",
                    thumbnailPath: ""
                ))
                m += reminderInterval
            }
        }

        // 4. 照片事件
        for photo in input.photoEvents {
            let pet = photo.petID.flatMap { id in input.pets.first { $0.id == id } }
            let petName = pet?.name ?? ""
            let title = photo.note.isEmpty
                ? (petName.isEmpty ? "照片" : "\(petName)的照片")
                : photo.note
            entries.append(TimelineEntry(
                id: "photo_\(photo.id.uuidString)",
                type: .photoNote,
                date: photo.takenAt,
                title: title,
                subtitle: isoDateString(from: photo.takenAt, calendar: calendar),
                petID: photo.petID,
                petName: petName,
                photoID: photo.id,
                photoURI: photo.uri,
                thumbnailPath: photo.thumbnailPath
            ))
        }

        // 按日期升序排序（nil 日期按 epoch 0 处理，对应源端 dateA ? getTime() : 0）
        entries.sort { a, b in
            let ta = a.date?.timeIntervalSince1970 ?? 0
            let tb = b.date?.timeIntervalSince1970 ?? 0
            return ta < tb
        }

        return entries
    }

    // ─── 过滤 ───

    /// 按选中宠物过滤条目（对应源端 filterTimelineEntries）。
    /// selectedPetID 为 nil 时返回全部（对应源端 selectedPetId < 0）。
    static func filterTimelineEntries(
        _ entries: [TimelineEntry], selectedPetID: UUID?
    ) -> [TimelineEntry] {
        guard let selectedPetID else { return entries }
        return entries.filter { $0.petID == selectedPetID }
    }

    // ─── 分组 ───

    /// 按年月分组条目并标记每年首月（对应源端 buildMonths）。
    static func buildMonths(
        _ entries: [TimelineEntry],
        selectedPetID: UUID?,
        calendar: Calendar = PetDateCalendar.gregorian
    ) -> [TimelineMonth] {
        let filtered = filterTimelineEntries(entries, selectedPetID: selectedPetID)
        var monthMap: [YearMonth: [TimelineEntry]] = [:]
        for entry in filtered {
            guard let date = entry.date else { continue }
            let c = calendar.dateComponents([.year, .month], from: date)
            guard let y = c.year, let mo = c.month else { continue }
            let ym = YearMonth(year: y, month: mo)
            monthMap[ym, default: []].append(entry)
        }
        let sortedKeys = monthMap.keys.sorted()
        var months = sortedKeys.map { ym -> TimelineMonth in
            TimelineMonth(
                year: ym.year, month: ym.month,
                yearMonth: yearMonthKey(ym), isYearStart: false,
                entries: monthMap[ym] ?? []
            )
        }
        // 标记每年首月（与源端一致：该年之前无任何月份组则视为首月）
        for i in 0..<months.count {
            var isFirstOfYear = true
            for j in 0..<i {
                if months[j].year == months[i].year { isFirstOfYear = false; break }
            }
            months[i].isYearStart = isFirstOfYear
        }
        return months
    }
}

// MARK: - 生命档案增强纯决策逻辑（Life-Archive-Design.md P3.6）

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

extension TimelineLogic {

    // ─── 索引查找 ───

    /// 查找包含指定条目 id 的月份索引（对应源端 findMonthIndexByEntry）。未找到返回 nil。
    static func findMonthIndex(containing entryID: String, in months: [TimelineMonth]) -> Int? {
        for (i, month) in months.enumerated() {
            if month.entries.contains(where: { $0.id == entryID }) { return i }
        }
        return nil
    }
}
