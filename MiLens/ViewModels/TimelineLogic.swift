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

    // ─── 索引查找 ───

    /// 查找包含指定条目 id 的月份索引（对应源端 findMonthIndexByEntry）。未找到返回 nil。
    static func findMonthIndex(containing entryID: String, in months: [TimelineMonth]) -> Int? {
        for (i, month) in months.enumerated() {
            if month.entries.contains(where: { $0.id == entryID }) { return i }
        }
        return nil
    }
}
