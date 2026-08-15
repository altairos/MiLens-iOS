//  RemindersLogic —— 回忆提醒中心纯决策逻辑。
//
//  计算今日命中的提醒（生日/成为家人的日子/相处里程碑/往日回忆）和
//  全部即将到来的纪念日倒计时。作为系统推送通知（NotifyService）的应用内兜底回看：
//  不依赖通知权限、不丢失、用户随时可回看。
//
//  复用 NotifyCheckLogic.matchesMonthDay（月日匹配）和 MilestoneLogic（里程碑命中）。
//  日期推进逻辑提取自 HomeViewModel.buildUpcoming，统一为纯函数后可跨 ViewModel 复用。
//
//  纯函数：不依赖 Repository / UserNotifications / SwiftData。
//  宿主（MemoryRemindersViewModel）负责 IO：查照片/宠物、投影组装。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation
import MiLensKit

// MARK: - 投影类型

/// 提醒中心用的宠物投影（脱离 SwiftData @Model）。
struct ReminderPet: Equatable, Sendable {
    let id: UUID
    let name: String
    let birthday: Date?
    let adoptionDay: Date?
    let events: [ReminderEvent]

    init(
        id: UUID, name: String,
        birthday: Date? = nil, adoptionDay: Date? = nil,
        events: [ReminderEvent] = []
    ) {
        self.id = id
        self.name = name
        self.birthday = birthday
        self.adoptionDay = adoptionDay
        self.events = events
    }
}

/// 提醒中心用的纪念事件投影。
struct ReminderEvent: Equatable, Sendable {
    let id: UUID
    let title: String
    let eventDate: Date

    init(id: UUID = UUID(), title: String, eventDate: Date) {
        self.id = id
        self.title = title
        self.eventDate = eventDate
    }
}

/// 提醒中心用的照片投影。
struct ReminderPhoto: Equatable, Sendable {
    let id: UUID
    let takenAt: Date?
    let note: String
    let petID: UUID?
    let thumbnailPath: String

    init(
        id: UUID = UUID(), takenAt: Date? = nil, note: String = "",
        petID: UUID? = nil, thumbnailPath: String = ""
    ) {
        self.id = id
        self.takenAt = takenAt
        self.note = note
        self.petID = petID
        self.thumbnailPath = thumbnailPath
    }
}

// MARK: - 输出类型

/// 今日提醒项类型，决定卡片样式与跳转目标。
enum TodayReminderKind: Sendable, Equatable {
    /// 今天是生日。
    case birthday
    /// 今天是成为家人的日子。
    case adoption
    /// 今天是相处里程碑（100/365/730/1000 天）。
    case milestone
    /// 今天有往日回忆（时光机当天命中）。
    case memory
}

/// 今日提醒项。
struct TodayReminder: Identifiable, Equatable, Sendable {
    let kind: TodayReminderKind
    let title: String
    /// 辅助信息：里程碑为天数文案，memory 为备注或宠物名；其余为空。
    let subtitle: String
    let petName: String
    let petID: UUID?
    /// memory 类型携带照片 ID，可跳转大图；其余为 nil。
    let photoID: UUID?

    var id: String {
        switch kind {
        case .birthday:
            return "today-birthday-\(petID?.uuidString ?? "")"
        case .adoption:
            return "today-adoption-\(petID?.uuidString ?? "")"
        case .milestone:
            // title 含天数，保证唯一
            return "today-milestone-\(petID?.uuidString ?? "")-\(title)"
        case .memory:
            return "today-memory-\(photoID?.uuidString ?? "")"
        }
    }
}

/// 即将到来的纪念日项。
struct UpcomingReminder: Identifiable, Equatable, Sendable {
    /// 纪念日来源类型，决定文案语义（与 HomeViewModel.UpcomingDay.Kind 对齐）。
    enum Kind: Sendable, Equatable {
        case birthday
        case adoption
        case memorial
    }

    let title: String
    let petName: String
    let petID: UUID
    let nextDate: Date
    /// 距今天数（≥0）。
    let daysUntil: Int
    /// 从原始日期到现在的天数（语义随 kind 变化）。
    let daysTogether: Int
    let kind: Kind

    var id: String {
        "\(kind)-\(petID.uuidString)-\(Int(nextDate.timeIntervalSince1970))"
    }
}

// MARK: - 决策逻辑

enum RemindersLogic {

    // MARK: - 今日命中

    /// 计算今日命中的提醒：生日/成为家人的日子/相处里程碑 + 往日回忆。
    ///
    /// - Parameters:
    ///   - pets: 全部宠物投影
    ///   - photos: 全部照片投影
    ///   - now: 当前时间（注入保证测试可复现）
    ///   - calendar: 日历（默认 UTC，测试可注入）
    ///   - birthdayTitle: 生日标题构建（petName → 标题）
    ///   - adoptionTitle: 成为家人的日子标题构建
    ///   - milestoneTitle: 里程碑标题构建（petName, days → 标题）
    ///   - memoryTitle: 往日回忆标题构建（yearsAgo → 标题）
    /// - Returns: 今日提醒列表；无命中返回空数组
    static func todayReminders(
        pets: [ReminderPet],
        photos: [ReminderPhoto],
        now: Date,
        calendar: Calendar = utcCalendar,
        birthdayTitle: (String) -> String = { "\($0)的生日" },
        adoptionTitle: (String) -> String = { "和\($0)成为家人的日子" },
        milestoneTitle: (String, Int) -> String = { name, days in "\(name)来到家\(days)天" },
        memoryTitle: (Int) -> String = { "\($0)年前的今天" }
    ) -> [TodayReminder] {
        let nowMonth = calendar.component(.month, from: now)
        let nowDay = calendar.component(.day, from: now)
        var result: [TodayReminder] = []

        for pet in pets {
            // 生日命中（月日匹配）
            if let birthday = pet.birthday,
               NotifyCheckLogic.matchesMonthDay(birthday, month: nowMonth, day: nowDay, calendar: calendar) {
                result.append(TodayReminder(
                    kind: .birthday,
                    title: birthdayTitle(pet.name),
                    subtitle: "",
                    petName: pet.name,
                    petID: pet.id,
                    photoID: nil
                ))
            }
            // 成为家人的日子命中
            if let adoption = pet.adoptionDay,
               NotifyCheckLogic.matchesMonthDay(adoption, month: nowMonth, day: nowDay, calendar: calendar) {
                result.append(TodayReminder(
                    kind: .adoption,
                    title: adoptionTitle(pet.name),
                    subtitle: "",
                    petName: pet.name,
                    petID: pet.id,
                    photoID: nil
                ))
            }
            // 里程碑命中（按 adoptionDay 计算相处天数）
            if let adoption = pet.adoptionDay {
                let elapsed = MilestoneLogic.daysSince(from: adoption, now: now)
                if let milestone = MilestoneLogic.hitMilestone(daysElapsed: elapsed) {
                    result.append(TodayReminder(
                        kind: .milestone,
                        title: milestoneTitle(pet.name, milestone.days),
                        subtitle: "\(milestone.days)",
                        petName: pet.name,
                        petID: pet.id,
                        photoID: nil
                    ))
                }
            }
        }

        // 往日回忆命中（当天月日有历史照片，拍摄年份严格早于今年）
        let nowYear = calendar.component(.year, from: now)
        let memoryPhotos = photos.filter { photo in
            guard let takenAt = photo.takenAt else { return false }
            return calendar.component(.month, from: takenAt) == nowMonth
                && calendar.component(.day, from: takenAt) == nowDay
                && calendar.component(.year, from: takenAt) < nowYear
        }
        for photo in memoryPhotos {
            let photoYear = calendar.component(.year, from: photo.takenAt ?? now)
            let yearsAgo = nowYear - photoYear
            let petName = pets.first(where: { $0.id == photo.petID })?.name ?? ""
            result.append(TodayReminder(
                kind: .memory,
                title: memoryTitle(yearsAgo),
                subtitle: photo.note.isEmpty ? petName : photo.note,
                petName: petName,
                petID: photo.petID,
                photoID: photo.id
            ))
        }

        return result
    }

    // MARK: - 即将到来的纪念日（全部）

    /// 计算全部宠物的即将到来的纪念日倒计时，按 daysUntil 升序。
    /// 包含生日、成为家人的日子、纪念事件；今天命中（daysUntil == 0）也包含。
    ///
    /// - Parameters:
    ///   - pets: 全部宠物投影
    ///   - now: 当前时间
    ///   - calendar: 日历
    ///   - birthdayTitle: 生日标题
    ///   - adoptionTitle: 成为家人的日子标题
    /// - Returns: 倒计时列表；无有效日期返回空数组
    static func upcomingReminders(
        pets: [ReminderPet],
        now: Date,
        calendar: Calendar = utcCalendar,
        birthdayTitle: (String) -> String = { "\($0)的生日" },
        adoptionTitle: (String) -> String = { "和\($0)成为家人的日子" }
    ) -> [UpcomingReminder] {
        var candidates: [UpcomingReminder] = []

        for pet in pets {
            if let birthday = pet.birthday,
               let upcoming = buildUpcoming(
                   originalDate: birthday, title: birthdayTitle(pet.name),
                   petName: pet.name, petID: pet.id, kind: .birthday, now: now, cal: calendar
               ) {
                candidates.append(upcoming)
            }
            if let adoption = pet.adoptionDay,
               let upcoming = buildUpcoming(
                   originalDate: adoption, title: adoptionTitle(pet.name),
                   petName: pet.name, petID: pet.id, kind: .adoption, now: now, cal: calendar
               ) {
                candidates.append(upcoming)
            }
            for ev in pet.events {
                if let upcoming = buildUpcoming(
                    originalDate: ev.eventDate, title: ev.title,
                    petName: pet.name, petID: pet.id, kind: .memorial, now: now, cal: calendar
                ) {
                    candidates.append(upcoming)
                }
            }
        }

        return candidates.sorted { $0.daysUntil < $1.daysUntil }
    }

    // MARK: - 内部：日期推进（提取自 HomeViewModel.buildUpcoming）

    /// 把原始日期推进到今年/明年的下一次月日匹配，构建候选 UpcomingReminder。
    private static func buildUpcoming(
        originalDate: Date, title: String, petName: String, petID: UUID,
        kind: UpcomingReminder.Kind, now: Date, cal: Calendar
    ) -> UpcomingReminder? {
        let comp = cal.dateComponents([.month, .day, .hour, .minute], from: originalDate)
        guard let month = comp.month, let day = comp.day else { return nil }

        let nowYear = cal.component(.year, from: now)
        var dc = DateComponents()
        dc.year = nowYear
        dc.month = month
        dc.day = day
        // 保留原始时刻（周年推进只换年份，不改当天触发时刻）
        dc.hour = comp.hour ?? 0
        dc.minute = comp.minute ?? 0
        guard let thisYear = cal.date(from: dc) else { return nil }

        // 如果今年已过，取明年
        let target: Date
        if thisYear >= cal.startOfDay(for: now) {
            target = thisYear
        } else {
            dc.year = nowYear + 1
            target = cal.date(from: dc) ?? thisYear
        }

        let daysUntil = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: target)).day ?? 0)
        let daysTogether = max(0, cal.dateComponents([.day], from: originalDate, to: now).day ?? 0)

        return UpcomingReminder(
            title: title, petName: petName, petID: petID,
            nextDate: target, daysUntil: daysUntil, daysTogether: daysTogether,
            kind: kind
        )
    }
}
