import XCTest
@testable import MiLens

/// NotifyCheckLogic 纯函数测试——每日去重判断 + 纪念日日期匹配。
final class NotifyCheckLogicTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - shouldRunDailyCheck

    func testNeverCheckedShouldRun() {
        XCTAssertTrue(NotifyCheckLogic.shouldRunDailyCheck(
            lastCheckDate: nil, now: date(2026, 8, 8), calendar: calendar))
    }

    func testSameDayShouldNotRun() {
        let now = date(2026, 8, 8)
        let sameDay = date(2026, 8, 8)  // 同一天不同时刻
        XCTAssertFalse(NotifyCheckLogic.shouldRunDailyCheck(
            lastCheckDate: sameDay, now: now, calendar: calendar))
    }

    func testNextDayShouldRun() {
        XCTAssertTrue(NotifyCheckLogic.shouldRunDailyCheck(
            lastCheckDate: date(2026, 8, 7), now: date(2026, 8, 8), calendar: calendar))
    }

    func testCrossYearShouldRun() {
        XCTAssertTrue(NotifyCheckLogic.shouldRunDailyCheck(
            lastCheckDate: date(2025, 12, 31), now: date(2026, 1, 1), calendar: calendar))
    }

    // MARK: - dayKey

    func testDayKeyFormat() {
        XCTAssertEqual(NotifyCheckLogic.dayKey(for: date(2026, 8, 8), calendar: calendar), "2026-08-08")
        XCTAssertEqual(NotifyCheckLogic.dayKey(for: date(2026, 1, 1), calendar: calendar), "2026-01-01")
    }

    // MARK: - matchesMonthDay

    func testMatchesMonthDay() {
        XCTAssertTrue(NotifyCheckLogic.matchesMonthDay(
            date(2025, 8, 8), month: 8, day: 8, calendar: calendar))
        XCTAssertTrue(NotifyCheckLogic.matchesMonthDay(
            date(2020, 8, 8), month: 8, day: 8, calendar: calendar))
        XCTAssertFalse(NotifyCheckLogic.matchesMonthDay(
            date(2025, 8, 9), month: 8, day: 8, calendar: calendar))
        XCTAssertFalse(NotifyCheckLogic.matchesMonthDay(
            nil, month: 8, day: 8, calendar: calendar))
    }

    // MARK: - isInYear

    func testIsInYear() {
        XCTAssertTrue(NotifyCheckLogic.isInYear(
            date(2026, 8, 8), year: 2026, calendar: calendar))
        XCTAssertFalse(NotifyCheckLogic.isInYear(
            date(2025, 8, 8), year: 2026, calendar: calendar))
        XCTAssertFalse(NotifyCheckLogic.isInYear(
            nil, year: 2026, calendar: calendar))
    }
}
