import XCTest
@testable import MiLens

/// RemindersLogic 纯决策逻辑测试。
///
/// 覆盖：
/// - todayReminders：生日/成为家人的日子/相处里程碑/往日回忆命中与空数据
/// - upcomingReminders：倒计时排序、跨年推进、多宠物、纪念事件
/// 全部用固定 UTC Calendar，与 AnniversaryTimeMachineLogicTests 同风格。
final class RemindersLogicTests: XCTestCase {

    private var calendar: Calendar {
        utcCalendar
    }

    /// 构造固定 UTC 日期。
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        comps.timeZone = TimeZone(identifier: "UTC")
        return calendar.date(from: comps)!
    }

    // MARK: - todayReminders

    func testTodayBirthdayHit() {
        let pet = ReminderPet(
            id: UUID(), name: "小橘",
            birthday: date(2020, 8, 13)
        )
        let now = date(2026, 8, 13)

        let result = RemindersLogic.todayReminders(pets: [pet], photos: [], now: now)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.kind, .birthday)
        XCTAssertEqual(result.first?.petName, "小橘")
    }

    func testTodayAdoptionHit() {
        let pet = ReminderPet(
            id: UUID(), name: "小橘",
            adoptionDay: date(2021, 8, 13)
        )
        let now = date(2026, 8, 13)

        let result = RemindersLogic.todayReminders(pets: [pet], photos: [], now: now)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.kind, .adoption)
    }

    func testTodayMilestoneHit() {
        // 2024-05-06 + 100 天 = 2024-08-14 → 2026-08-14 不是里程碑
        // 用 365 天里程碑：2025-08-14 + 365 天 = 2026-08-14
        let adoptionDay = date(2025, 8, 14)
        let pet = ReminderPet(
            id: UUID(), name: "小橘",
            adoptionDay: adoptionDay
        )
        let now = date(2026, 8, 14)

        let result = RemindersLogic.todayReminders(pets: [pet], photos: [], now: now)

        let milestone = result.first { $0.kind == .milestone }
        XCTAssertNotNil(milestone)
        XCTAssertEqual(milestone?.subtitle, "365")
    }

    func testTodayMilestoneNotHit() {
        // 99 天不是里程碑
        let adoptionDay = date(2026, 5, 7) // ~99 天前
        let pet = ReminderPet(
            id: UUID(), name: "小橘",
            adoptionDay: adoptionDay
        )
        let now = date(2026, 8, 14)

        let result = RemindersLogic.todayReminders(pets: [pet], photos: [], now: now)

        XCTAssertFalse(result.contains { $0.kind == .milestone })
    }

    func testTodayMemoryHit() {
        let petID = UUID()
        let photo = ReminderPhoto(
            id: UUID(), takenAt: date(2024, 8, 13),
            note: "在公园散步", petID: petID
        )
        let pet = ReminderPet(id: petID, name: "小橘")
        let now = date(2026, 8, 13)

        let result = RemindersLogic.todayReminders(pets: [pet], photos: [photo], now: now)

        let memory = result.first { $0.kind == .memory }
        XCTAssertNotNil(memory)
        XCTAssertEqual(memory?.photoID, photo.id)
        XCTAssertEqual(memory?.petName, "小橘")
    }

    func testTodayMemoryExcludesCurrentYear() {
        // 当年照片不作为往日回忆
        let photo = ReminderPhoto(
            id: UUID(), takenAt: date(2026, 8, 13)
        )
        let now = date(2026, 8, 13)

        let result = RemindersLogic.todayReminders(pets: [], photos: [photo], now: now)

        XCTAssertFalse(result.contains { $0.kind == .memory })
    }

    func testTodayNoHitsReturnsEmpty() {
        let pet = ReminderPet(id: UUID(), name: "小橘", birthday: date(2020, 1, 1))
        let now = date(2026, 8, 13)

        let result = RemindersLogic.todayReminders(pets: [pet], photos: [], now: now)

        XCTAssertTrue(result.isEmpty)
    }

    func testTodayMultipleHits() {
        // 同一天既是生日又是领养日 + 有往日回忆
        let petID = UUID()
        let pet = ReminderPet(
            id: petID, name: "小橘",
            birthday: date(2020, 8, 13),
            adoptionDay: date(2021, 8, 13)
        )
        let photo = ReminderPhoto(id: UUID(), takenAt: date(2024, 8, 13), petID: petID)
        let now = date(2026, 8, 13)

        let result = RemindersLogic.todayReminders(pets: [pet], photos: [photo], now: now)

        XCTAssertEqual(result.count, 3)
        let kinds = Set(result.map(\.kind))
        XCTAssertTrue(kinds.contains(.birthday))
        XCTAssertTrue(kinds.contains(.adoption))
        XCTAssertTrue(kinds.contains(.memory))
    }

    // MARK: - upcomingReminders

    func testUpcomingSortedByDaysUntil() {
        let pet1 = ReminderPet(id: UUID(), name: "A", birthday: date(2020, 9, 1))
        let pet2 = ReminderPet(id: UUID(), name: "B", birthday: date(2020, 8, 20))
        let now = date(2026, 8, 13)

        let result = RemindersLogic.upcomingReminders(pets: [pet1, pet2], now: now)

        XCTAssertEqual(result.count, 2)
        // 8/20 比 9/1 更近
        XCTAssertEqual(result[0].petName, "B")
        XCTAssertEqual(result[1].petName, "A")
        XCTAssertEqual(result[0].daysUntil, 7)
        XCTAssertEqual(result[1].daysUntil, 19)
    }

    func testUpcomingCrossYearAdvancement() {
        // 生日已过（今年 1 月），应推进到明年
        let pet = ReminderPet(id: UUID(), name: "小橘", birthday: date(2020, 1, 1))
        let now = date(2026, 8, 13)

        let result = RemindersLogic.upcomingReminders(pets: [pet], now: now)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].nextDate, date(2027, 1, 1))
    }

    func testUpcomingTodayDaysUntilZero() {
        let pet = ReminderPet(id: UUID(), name: "小橘", birthday: date(2020, 8, 13))
        let now = date(2026, 8, 13)

        let result = RemindersLogic.upcomingReminders(pets: [pet], now: now)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].daysUntil, 0)
    }

    func testUpcomingIncludesEvents() {
        let eventDate = date(2023, 10, 1)
        let event = ReminderEvent(title: "第一次体检", eventDate: eventDate)
        let pet = ReminderPet(id: UUID(), name: "小橘", events: [event])
        let now = date(2026, 8, 13)

        let result = RemindersLogic.upcomingReminders(pets: [pet], now: now)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].kind, .memorial)
        XCTAssertEqual(result[0].title, "第一次体检")
    }

    func testUpcomingMultipleKindsForSamePet() {
        let petID = UUID()
        let pet = ReminderPet(
            id: petID, name: "小橘",
            birthday: date(2020, 9, 1),
            adoptionDay: date(2021, 10, 1)
        )
        let now = date(2026, 8, 13)

        let result = RemindersLogic.upcomingReminders(pets: [pet], now: now)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.kind)), [.birthday, .adoption])
    }

    func testUpcomingNoDatesReturnsEmpty() {
        let pet = ReminderPet(id: UUID(), name: "无日期")
        let now = date(2026, 8, 13)

        let result = RemindersLogic.upcomingReminders(pets: [pet], now: now)

        XCTAssertTrue(result.isEmpty)
    }

    func testUpcomingEmptyPetsReturnsEmpty() {
        let now = date(2026, 8, 13)

        let result = RemindersLogic.upcomingReminders(pets: [], now: now)

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - 自定义文案注入

    func testTodayCustomTitles() {
        let pet = ReminderPet(id: UUID(), name: "小橘", birthday: date(2020, 8, 13))
        let now = date(2026, 8, 13)

        let result = RemindersLogic.todayReminders(
            pets: [pet], photos: [], now: now,
            birthdayTitle: { name in "Happy Birthday \(name)" }
        )

        XCTAssertEqual(result.first?.title, "Happy Birthday 小橘")
    }
}
