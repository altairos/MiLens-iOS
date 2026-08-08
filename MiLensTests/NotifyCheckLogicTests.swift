import XCTest
@testable import MiLens

/// NotifyCheckLogic 纯函数测试——纪念日日期匹配。
/// P1 重构：每日去重判断（shouldRunDailyCheck/dayKey）随前台检查语义一并移除。
final class NotifyCheckLogicTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
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
