import XCTest
@testable import MiLensKit

//  NewPhotoReminderLogic 纯决策逻辑测试。
//  覆盖：距上次添加天数计算、新照片/久未添加触发条件边界、ReminderKind 矩阵。
//  全部日期用固定 UTC Calendar 构造，任意时区可复现。

private enum NewPhotoTestSupport {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        // TimeZone.gmt 是 Swift 6 Foundation 成员，CI Swift 5.10 无此 API；
        // "UTC" 是各平台保留标识符必存在，测试代码直接解包（同下方 date(from:)! 风格）。
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    static func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return calendar.date(from: comps)!
    }
}

final class NewPhotoReminderLogicTests: XCTestCase {

    // MARK: - 常量

    func testStaleDaysIsFourteen() {
        XCTAssertEqual(NewPhotoReminderLogic.staleDays, 14)
    }

    // MARK: - daysSinceLastAdded

    func testDaysSinceLastAddedNilWhenNever() {
        XCTAssertNil(NewPhotoReminderLogic.daysSinceLastAdded(
            lastAddedDate: nil,
            now: NewPhotoTestSupport.makeDate(2026, 8, 13),
            calendar: NewPhotoTestSupport.calendar))
    }

    func testDaysSinceLastAddedSameDay() {
        let now = NewPhotoTestSupport.makeDate(2026, 8, 13)
        XCTAssertEqual(NewPhotoReminderLogic.daysSinceLastAdded(
            lastAddedDate: now, now: now,
            calendar: NewPhotoTestSupport.calendar), 0)
    }

    func testDaysSinceLastAddedUsesCalendarDaysNotHours() {
        // 23:00 添加，次日 01:00 检查 → 跨自然日 = 1 天（非 0）
        let last = NewPhotoTestSupport.makeDate(2026, 8, 12)
        var lateComps = DateComponents()
        lateComps.year = 2026; lateComps.month = 8; lateComps.day = 13; lateComps.hour = 1
        let next = NewPhotoTestSupport.calendar.date(from: lateComps)!
        XCTAssertEqual(NewPhotoReminderLogic.daysSinceLastAdded(
            lastAddedDate: last, now: next,
            calendar: NewPhotoTestSupport.calendar), 1)
    }

    func testDaysSinceLastAddedAcrossMonth() {
        let last = NewPhotoTestSupport.makeDate(2026, 7, 14)
        let now = NewPhotoTestSupport.makeDate(2026, 8, 13)
        XCTAssertEqual(NewPhotoReminderLogic.daysSinceLastAdded(
            lastAddedDate: last, now: now,
            calendar: NewPhotoTestSupport.calendar), 30)
    }

    // MARK: - shouldRemindForStaleInput

    func testStaleInputRemindsWhenNeverAdded() {
        XCTAssertTrue(NewPhotoReminderLogic.shouldRemindForStaleInput(
            lastAddedDate: nil,
            now: NewPhotoTestSupport.makeDate(2026, 8, 13),
            calendar: NewPhotoTestSupport.calendar))
    }

    func testStaleInputDoesNotRemindAt13Days() {
        let now = NewPhotoTestSupport.makeDate(2026, 8, 13)
        let last = NewPhotoTestSupport.makeDate(2026, 7, 31)  // 13 天前
        XCTAssertFalse(NewPhotoReminderLogic.shouldRemindForStaleInput(
            lastAddedDate: last, now: now,
            calendar: NewPhotoTestSupport.calendar))
    }

    func testStaleInputRemindsAt14Days() {
        let now = NewPhotoTestSupport.makeDate(2026, 8, 13)
        let last = NewPhotoTestSupport.makeDate(2026, 7, 30)  // 14 天前
        XCTAssertTrue(NewPhotoReminderLogic.shouldRemindForStaleInput(
            lastAddedDate: last, now: now,
            calendar: NewPhotoTestSupport.calendar))
    }

    // MARK: - shouldRemindForNewPhotos

    func testNewPhotosDoesNotRemindAtZero() {
        XCTAssertFalse(NewPhotoReminderLogic.shouldRemindForNewPhotos(newPhotoCount: 0))
    }

    func testNewPhotosRemindsAtOne() {
        XCTAssertTrue(NewPhotoReminderLogic.shouldRemindForNewPhotos(newPhotoCount: 1))
    }

    func testNewPhotosRemindsAtMany() {
        XCTAssertTrue(NewPhotoReminderLogic.shouldRemindForNewPhotos(newPhotoCount: 50))
    }

    // MARK: - shouldRemind（综合）

    func testShouldRemindFalseWhenBothConditionsUnmet() {
        let now = NewPhotoTestSupport.makeDate(2026, 8, 13)
        let last = NewPhotoTestSupport.makeDate(2026, 8, 10)  // 3 天前
        XCTAssertFalse(NewPhotoReminderLogic.shouldRemind(
            newPhotoCount: 0, lastAddedDate: last, now: now,
            calendar: NewPhotoTestSupport.calendar))
    }

    func testShouldRemindTrueWhenNewPhotosOnly() {
        let now = NewPhotoTestSupport.makeDate(2026, 8, 13)
        let last = NewPhotoTestSupport.makeDate(2026, 8, 10)  // 3 天前
        XCTAssertTrue(NewPhotoReminderLogic.shouldRemind(
            newPhotoCount: 5, lastAddedDate: last, now: now,
            calendar: NewPhotoTestSupport.calendar))
    }

    func testShouldRemindTrueWhenStaleOnly() {
        let now = NewPhotoTestSupport.makeDate(2026, 8, 13)
        XCTAssertTrue(NewPhotoReminderLogic.shouldRemind(
            newPhotoCount: 0, lastAddedDate: nil, now: now,
            calendar: NewPhotoTestSupport.calendar))
    }

    // MARK: - resolveKind（矩阵）

    func testResolveKindNoneWhenNoConditions() {
        let now = NewPhotoTestSupport.makeDate(2026, 8, 13)
        let last = NewPhotoTestSupport.makeDate(2026, 8, 10)
        XCTAssertEqual(NewPhotoReminderLogic.resolveKind(
            newPhotoCount: 0, lastAddedDate: last, now: now,
            calendar: NewPhotoTestSupport.calendar), .none)
    }

    func testResolveKindNewPhotosWhenOnlyNew() {
        let now = NewPhotoTestSupport.makeDate(2026, 8, 13)
        let last = NewPhotoTestSupport.makeDate(2026, 8, 10)  // 3 天前
        XCTAssertEqual(NewPhotoReminderLogic.resolveKind(
            newPhotoCount: 3, lastAddedDate: last, now: now,
            calendar: NewPhotoTestSupport.calendar), .newPhotos)
    }

    func testResolveKindStaleWhenOnlyStale() {
        let now = NewPhotoTestSupport.makeDate(2026, 8, 13)
        let last = NewPhotoTestSupport.makeDate(2026, 7, 1)  // 43 天前
        XCTAssertEqual(NewPhotoReminderLogic.resolveKind(
            newPhotoCount: 0, lastAddedDate: last, now: now,
            calendar: NewPhotoTestSupport.calendar), .staleInput)
    }

    func testResolveKindBothWhenBothConditions() {
        let now = NewPhotoTestSupport.makeDate(2026, 8, 13)
        let last = NewPhotoTestSupport.makeDate(2026, 7, 1)  // 43 天前
        XCTAssertEqual(NewPhotoReminderLogic.resolveKind(
            newPhotoCount: 10, lastAddedDate: last, now: now,
            calendar: NewPhotoTestSupport.calendar), .both)
    }

    func testResolveKindStaleWhenNeverAdded() {
        let now = NewPhotoTestSupport.makeDate(2026, 8, 13)
        XCTAssertEqual(NewPhotoReminderLogic.resolveKind(
            newPhotoCount: 0, lastAddedDate: nil, now: now,
            calendar: NewPhotoTestSupport.calendar), .staleInput)
    }

    func testResolveKindBothWhenNewAndNeverAdded() {
        let now = NewPhotoTestSupport.makeDate(2026, 8, 13)
        XCTAssertEqual(NewPhotoReminderLogic.resolveKind(
            newPhotoCount: 5, lastAddedDate: nil, now: now,
            calendar: NewPhotoTestSupport.calendar), .both)
    }
}
