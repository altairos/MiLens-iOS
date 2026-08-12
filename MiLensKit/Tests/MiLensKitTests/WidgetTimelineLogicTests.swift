import XCTest
@testable import MiLensKit

//  WidgetTimelineLogic 时间线刷新策略纯决策逻辑测试。
//
//  覆盖 WidgetKit-Design.md §6.2 的时间线契约。
//  全部日期用固定 UTC Calendar（miLensUTCCalendar）构造，任意时区可复现。

private enum TimelineTestSupport {
    static func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return miLensUTCCalendar.date(from: comps)!
    }
}

final class WidgetTimelineLogicTests: XCTestCase {

    // MARK: - 相片回声

    func testPhotoEchoNextRefresh_returnsTomorrowStart() {
        // 2026-08-12 14:30 → 明天 00:01
        let now = TimelineTestSupport.makeDate(2026, 8, 12, 14, 30)
        let refresh = WidgetTimelineLogic.photoEchoNextRefresh(after: now)
        let expected = TimelineTestSupport.makeDate(2026, 8, 13, 0, 1)
        XCTAssertEqual(refresh, expected, "相片回声应在明天 00:01 刷新")
    }

    func testPhotoEchoNextRefresh_crossMonthBoundary() {
        let now = TimelineTestSupport.makeDate(2026, 8, 31, 23, 50)
        let refresh = WidgetTimelineLogic.photoEchoNextRefresh(after: now)
        let expected = TimelineTestSupport.makeDate(2026, 9, 1, 0, 1)
        XCTAssertEqual(refresh, expected, "跨月时应正确算到下月 1 号 00:01")
    }

    func testPhotoEchoNextRefresh_crossYearBoundary() {
        let now = TimelineTestSupport.makeDate(2026, 12, 31, 23, 50)
        let refresh = WidgetTimelineLogic.photoEchoNextRefresh(after: now)
        let expected = TimelineTestSupport.makeDate(2027, 1, 1, 0, 1)
        XCTAssertEqual(refresh, expected, "跨年时应正确算到次年 1 月 1 日 00:01")
    }

    // MARK: - 纪念日

    func testUpcomingDayEntries_returnsTwoEntriesBeforeMidnight() {
        // 8-12 14:30 → 今天 23:59 + 明天 00:01
        let now = TimelineTestSupport.makeDate(2026, 8, 12, 14, 30)
        let entries = WidgetTimelineLogic.upcomingDayEntries(now: now)
        XCTAssertEqual(entries.count, 2, "午夜前应返回 2 个 entry")
        XCTAssertEqual(entries[0], TimelineTestSupport.makeDate(2026, 8, 12, 23, 59))
        XCTAssertEqual(entries[1], TimelineTestSupport.makeDate(2026, 8, 13, 0, 1))
    }

    func testUpcomingDayEntries_returnsOneEntryAfter2359() {
        // 8-12 23:59:30 → 今天 23:59 已过，只返回明天 00:01
        let now = TimelineTestSupport.makeDate(2026, 8, 12, 23, 59) + 30
        let entries = WidgetTimelineLogic.upcomingDayEntries(now: now)
        XCTAssertEqual(entries.count, 1, "午夜后应只返回 1 个 entry")
        XCTAssertEqual(entries[0], TimelineTestSupport.makeDate(2026, 8, 13, 0, 1))
    }

    // MARK: - 档案年轮

    func testArchiveNextRefresh_returns4HoursLater() {
        let now = TimelineTestSupport.makeDate(2026, 8, 12, 10)
        let refresh = WidgetTimelineLogic.archiveNextRefresh(after: now)
        XCTAssertEqual(refresh, TimelineTestSupport.makeDate(2026, 8, 12, 14), "档案年轮应在 4 小时后刷新")
    }

    // MARK: - 锁屏

    func testLockScreenNextRefresh_followsPhotoEcho() {
        let now = TimelineTestSupport.makeDate(2026, 8, 12, 10)
        let refresh = WidgetTimelineLogic.lockScreenNextRefresh(after: now)
        XCTAssertEqual(refresh, WidgetTimelineLogic.photoEchoNextRefresh(after: now), "锁屏应跟随相片回声的刷新策略")
    }

    // MARK: - 内部工具

    func testNextDayStart() {
        let now = TimelineTestSupport.makeDate(2026, 8, 12, 14, 30)
        let nextStart = WidgetTimelineLogic.nextDayStart(after: now)
        XCTAssertEqual(nextStart, TimelineTestSupport.makeDate(2026, 8, 13, 0, 0))
    }
}
