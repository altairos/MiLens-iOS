import XCTest
@testable import MiLensKit

//  BackupReminderLogic 纯决策逻辑测试。
//  覆盖：距上次备份天数计算、首页横幅触发条件、定期通知触发条件的边界。
//  全部日期用固定 UTC Calendar 构造，任意时区可复现。

private enum BackupTestSupport {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
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

final class BackupReminderLogicTests: XCTestCase {

    // MARK: - 常量

    func testThresholdConstantsAreSensible() {
        XCTAssertGreaterThan(BackupReminderLogic.reminderStaleDays,
                             BackupReminderLogic.bannerStaleDays,
                             "通知阈值应大于横幅阈值（横幅先于通知触达）")
        XCTAssertGreaterThan(BackupReminderLogic.bannerMinPhotos, 0)
    }

    // MARK: - daysSinceLastBackup

    func testDaysSinceLastBackupNilWhenNever() {
        XCTAssertNil(BackupReminderLogic.daysSinceLastBackup(
            lastBackupDate: nil,
            now: BackupTestSupport.makeDate(2026, 8, 13),
            calendar: BackupTestSupport.calendar))
    }

    func testDaysSinceLastBackupSameDay() {
        let now = BackupTestSupport.makeDate(2026, 8, 13)
        XCTAssertEqual(BackupReminderLogic.daysSinceLastBackup(
            lastBackupDate: now, now: now, calendar: BackupTestSupport.calendar), 0)
    }

    func testDaysSinceLastBackupUsesCalendarDaysNotHours() {
        // 23:00 备份，次日 01:00 检查 → 跨自然日 = 1 天（非 0）
        let last = BackupTestSupport.makeDate(2026, 8, 12)
        var lateComps = DateComponents()
        lateComps.year = 2026; lateComps.month = 8; lateComps.day = 13; lateComps.hour = 1
        let next = BackupTestSupport.calendar.date(from: lateComps)!
        XCTAssertEqual(BackupReminderLogic.daysSinceLastBackup(
            lastBackupDate: last, now: next, calendar: BackupTestSupport.calendar), 1)
    }

    func testDaysSinceLastBackupThirtyDays() {
        let last = BackupTestSupport.makeDate(2026, 7, 14)
        let now = BackupTestSupport.makeDate(2026, 8, 13)
        XCTAssertEqual(BackupReminderLogic.daysSinceLastBackup(
            lastBackupDate: last, now: now, calendar: BackupTestSupport.calendar), 30)
    }

    // MARK: - shouldShowHomeBanner

    func testBannerHiddenWhenTooFewPhotos() {
        XCTAssertFalse(BackupReminderLogic.shouldShowHomeBanner(
            lastBackupDate: nil, photoCount: BackupReminderLogic.bannerMinPhotos - 1,
            now: BackupTestSupport.makeDate(2026, 8, 13), calendar: BackupTestSupport.calendar))
    }

    func testBannerShownWhenNeverBackupAndEnoughPhotos() {
        XCTAssertTrue(BackupReminderLogic.shouldShowHomeBanner(
            lastBackupDate: nil, photoCount: BackupReminderLogic.bannerMinPhotos,
            now: BackupTestSupport.makeDate(2026, 8, 13), calendar: BackupTestSupport.calendar))
    }

    func testBannerHiddenWhenRecentlyBackup() {
        let now = BackupTestSupport.makeDate(2026, 8, 13)
        let last = BackupTestSupport.makeDate(2026, 8, 1)  // 12 天前
        XCTAssertFalse(BackupReminderLogic.shouldShowHomeBanner(
            lastBackupDate: last, photoCount: 100, now: now, calendar: BackupTestSupport.calendar))
    }

    func testBannerHiddenAt29DaysBoundary() {
        let now = BackupTestSupport.makeDate(2026, 8, 13)
        let last = BackupTestSupport.makeDate(2026, 7, 15)  // 29 天前
        XCTAssertFalse(BackupReminderLogic.shouldShowHomeBanner(
            lastBackupDate: last, photoCount: 100, now: now, calendar: BackupTestSupport.calendar))
    }

    func testBannerShownAt30DaysBoundary() {
        let now = BackupTestSupport.makeDate(2026, 8, 13)
        let last = BackupTestSupport.makeDate(2026, 7, 14)  // 30 天前
        XCTAssertTrue(BackupReminderLogic.shouldShowHomeBanner(
            lastBackupDate: last, photoCount: 100, now: now, calendar: BackupTestSupport.calendar))
    }

    func testBannerShownWhenStaleAndLotsOfPhotos() {
        let now = BackupTestSupport.makeDate(2026, 8, 13)
        let last = BackupTestSupport.makeDate(2026, 1, 1)  // 半年前
        XCTAssertTrue(BackupReminderLogic.shouldShowHomeBanner(
            lastBackupDate: last, photoCount: 500, now: now, calendar: BackupTestSupport.calendar))
    }

    // MARK: - shouldScheduleBackupReminder

    func testReminderScheduledWhenNeverBackup() {
        XCTAssertTrue(BackupReminderLogic.shouldScheduleBackupReminder(
            lastBackupDate: nil,
            now: BackupTestSupport.makeDate(2026, 8, 13),
            calendar: BackupTestSupport.calendar))
    }

    func testReminderNotScheduledRecently() {
        let now = BackupTestSupport.makeDate(2026, 8, 13)
        let last = BackupTestSupport.makeDate(2026, 8, 1)  // 12 天前
        XCTAssertFalse(BackupReminderLogic.shouldScheduleBackupReminder(
            lastBackupDate: last, now: now, calendar: BackupTestSupport.calendar))
    }

    func testReminderNotScheduledAt59DaysBoundary() {
        let now = BackupTestSupport.makeDate(2026, 8, 13)
        let last = BackupTestSupport.makeDate(2026, 6, 15)  // 59 天前
        XCTAssertFalse(BackupReminderLogic.shouldScheduleBackupReminder(
            lastBackupDate: last, now: now, calendar: BackupTestSupport.calendar))
    }

    func testReminderScheduledAt60DaysBoundary() {
        let now = BackupTestSupport.makeDate(2026, 8, 13)
        let last = BackupTestSupport.makeDate(2026, 6, 14)  // 60 天前
        XCTAssertTrue(BackupReminderLogic.shouldScheduleBackupReminder(
            lastBackupDate: last, now: now, calendar: BackupTestSupport.calendar))
    }
}
