import XCTest
@testable import MiLensKit

//  MilestoneLogic 纯决策逻辑测试（ADR-0010 §3.2 / §10.11）。
//
//  无源端黄金规格（里程碑为 iOS 自研情感触点），行为规格由本文件守护：
//  - 整数核心：命中判定 / 下一个 / 上一个 / 非里程碑值回退
//  - 日期计算：daysSince 截断 / milestoneDate 日进位 / daysRemaining 倒计时
//  - 批量调度：upcomingMilestones 窗口过滤
//  - 文案：标题 / 通知正文（含/缺宠物名）
//
//  全部日期用固定 UTC Calendar（miLensUTCCalendar）构造，任意时区可复现。

// MARK: - 测试工具

private enum MilestoneTestSupport {
    /// 固定「现在」：2026-08-11 12:00 UTC。
    static let now = makeDate(2026, 8, 11, 12)

    static func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        return miLensUTCCalendar.date(from: comps)!
    }

    /// 锚点日期（领养日），使 now 距锚点恰好 `days` 整天。
    static func anchor(daysBeforeNow days: Int) -> Date {
        makeDate(2026, 8, 11, 12).addingTimeInterval(TimeInterval(-days * 86_400))
    }
}

// MARK: - 整数核心

final class MilestoneLogicCoreTests: XCTestCase {

    func testMilestoneDaysAreAscending() {
        XCTAssertEqual(MilestoneLogic.milestoneDays, [100, 365, 730, 1000])
    }

    func testMilestoneForKnownDays() {
        XCTAssertEqual(MilestoneLogic.milestone(forDays: 100)?.days, 100)
        XCTAssertEqual(MilestoneLogic.milestone(forDays: 365)?.days, 365)
        XCTAssertEqual(MilestoneLogic.milestone(forDays: 730)?.days, 730)
        XCTAssertEqual(MilestoneLogic.milestone(forDays: 1000)?.days, 1000)
    }

    func testMilestoneForUnknownDaysReturnsNil() {
        XCTAssertNil(MilestoneLogic.milestone(forDays: 0))
        XCTAssertNil(MilestoneLogic.milestone(forDays: 99))
        XCTAssertNil(MilestoneLogic.milestone(forDays: 200))
        XCTAssertNil(MilestoneLogic.milestone(forDays: 1001))
        XCTAssertNil(MilestoneLogic.milestone(forDays: -1))
    }

    // MARK: - hitMilestone

    func testHitMilestoneAtExactDay() {
        XCTAssertEqual(MilestoneLogic.hitMilestone(daysElapsed: 100)?.days, 100)
        XCTAssertEqual(MilestoneLogic.hitMilestone(daysElapsed: 365)?.days, 365)
        XCTAssertEqual(MilestoneLogic.hitMilestone(daysElapsed: 1000)?.days, 1000)
    }

    func testHitMilestoneReturnsNilForNonMilestoneDay() {
        XCTAssertNil(MilestoneLogic.hitMilestone(daysElapsed: 0))
        XCTAssertNil(MilestoneLogic.hitMilestone(daysElapsed: 99))
        XCTAssertNil(MilestoneLogic.hitMilestone(daysElapsed: 366))
        XCTAssertNil(MilestoneLogic.hitMilestone(daysElapsed: 1001))
    }

    func testHitMilestoneReturnsNilForNegative() {
        XCTAssertNil(MilestoneLogic.hitMilestone(daysElapsed: -10))
    }

    // MARK: - nextMilestone

    func testNextMilestoneFromBelow100() {
        XCTAssertEqual(MilestoneLogic.nextMilestone(afterDaysElapsed: 0)?.days, 100)
        XCTAssertEqual(MilestoneLogic.nextMilestone(afterDaysElapsed: 50)?.days, 100)
        XCTAssertEqual(MilestoneLogic.nextMilestone(afterDaysElapsed: 99)?.days, 100)
    }

    func testNextMilestoneBetweenMilestones() {
        XCTAssertEqual(MilestoneLogic.nextMilestone(afterDaysElapsed: 100)?.days, 365)
        XCTAssertEqual(MilestoneLogic.nextMilestone(afterDaysElapsed: 200)?.days, 365)
        XCTAssertEqual(MilestoneLogic.nextMilestone(afterDaysElapsed: 364)?.days, 365)
        XCTAssertEqual(MilestoneLogic.nextMilestone(afterDaysElapsed: 365)?.days, 730)
        XCTAssertEqual(MilestoneLogic.nextMilestone(afterDaysElapsed: 730)?.days, 1000)
    }

    func testNextMilestoneReturnsNilAfterLastMilestone() {
        XCTAssertNil(MilestoneLogic.nextMilestone(afterDaysElapsed: 1000))
        XCTAssertNil(MilestoneLogic.nextMilestone(afterDaysElapsed: 5000))
    }

    // MARK: - previousMilestone

    func testPreviousMilestone() {
        XCTAssertNil(MilestoneLogic.previousMilestone(beforeDaysElapsed: 50))
        XCTAssertNil(MilestoneLogic.previousMilestone(beforeDaysElapsed: 100))
        XCTAssertEqual(MilestoneLogic.previousMilestone(beforeDaysElapsed: 101)?.days, 100)
        XCTAssertEqual(MilestoneLogic.previousMilestone(beforeDaysElapsed: 365)?.days, 100)
        XCTAssertEqual(MilestoneLogic.previousMilestone(beforeDaysElapsed: 500)?.days, 365)
        XCTAssertEqual(MilestoneLogic.previousMilestone(beforeDaysElapsed: 2000)?.days, 1000)
    }
}

// MARK: - 日期计算

final class MilestoneLogicDateTests: XCTestCase {

    func testDaysSinceTruncates() {
        let anchor = MilestoneTestSupport.anchor(daysBeforeNow: 100)
        // 截断除法：100.5 天 → 100
        let anchorHalfDay = anchor.addingTimeInterval(43_200) // +12h → now 距锚点 99.5 天
        XCTAssertEqual(MilestoneLogic.daysSince(from: anchorHalfDay, now: MilestoneTestSupport.now), 99)
    }

    func testDaysSinceExact100Days() {
        let anchor = MilestoneTestSupport.anchor(daysBeforeNow: 100)
        XCTAssertEqual(MilestoneLogic.daysSince(from: anchor, now: MilestoneTestSupport.now), 100)
    }

    func testDaysSinceNegativeForFutureAnchor() {
        let future = MilestoneTestSupport.now.addingTimeInterval(10 * 86_400)
        XCTAssertEqual(MilestoneLogic.daysSince(from: future, now: MilestoneTestSupport.now), -10)
    }

    func testMilestoneDateAddsExactDays() {
        let anchor = MilestoneTestSupport.makeDate(2026, 1, 1, 0)
        let day100 = MilestoneLogic.milestoneDate(anchor: anchor, days: 100)
        // 2026-01-01 + 100 天 = 2026-04-11
        let comps = miLensUTCCalendar.dateComponents([.year, .month, .day], from: day100)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 11)
    }

    func testMilestoneDate365Days() {
        let anchor = MilestoneTestSupport.makeDate(2025, 1, 1, 0)
        let day365 = MilestoneLogic.milestoneDate(anchor: anchor, days: 365)
        // 2025-01-01 + 365 天 = 2026-01-01（2025 非闰年，365 天后恰满一年）
        let comps = miLensUTCCalendar.dateComponents([.year, .month, .day], from: day365)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 1)
    }

    func testDaysRemainingToUpcomingMilestone() {
        let anchor = MilestoneTestSupport.anchor(daysBeforeNow: 90)
        let milestone = PetMilestone(days: 100)
        XCTAssertEqual(MilestoneLogic.daysRemaining(to: milestone, from: anchor, now: MilestoneTestSupport.now), 10)
    }

    func testDaysRemainingToPassedMilestoneIsNegative() {
        let anchor = MilestoneTestSupport.anchor(daysBeforeNow: 200)
        let milestone = PetMilestone(days: 100)
        XCTAssertEqual(MilestoneLogic.daysRemaining(to: milestone, from: anchor, now: MilestoneTestSupport.now), -100)
    }

    func testDaysRemainingAtHitIsZero() {
        let anchor = MilestoneTestSupport.anchor(daysBeforeNow: 100)
        let milestone = PetMilestone(days: 100)
        XCTAssertEqual(MilestoneLogic.daysRemaining(to: milestone, from: anchor, now: MilestoneTestSupport.now), 0)
    }
}

// MARK: - 批量调度

final class MilestoneLogicUpcomingTests: XCTestCase {

    func testUpcomingIncludesHitMilestone() {
        let anchor = MilestoneTestSupport.anchor(daysBeforeNow: 100)
        let upcoming = MilestoneLogic.upcomingMilestones(from: anchor, now: MilestoneTestSupport.now, daysAhead: 30)
        XCTAssertEqual(upcoming.map(\.days), [100])
    }

    func testUpcomingIncludesMultipleInWindow() {
        // 已过 99 天 → 100 在 1 天后，365 在 266 天后
        let anchor = MilestoneTestSupport.anchor(daysBeforeNow: 99)
        let upcoming = MilestoneLogic.upcomingMilestones(from: anchor, now: MilestoneTestSupport.now, daysAhead: 300)
        XCTAssertEqual(upcoming.map(\.days), [100, 365])
    }

    func testUpcomingExcludesBeyondWindow() {
        let anchor = MilestoneTestSupport.anchor(daysBeforeNow: 99)
        let upcoming = MilestoneLogic.upcomingMilestones(from: anchor, now: MilestoneTestSupport.now, daysAhead: 50)
        XCTAssertEqual(upcoming.map(\.days), [100])
    }

    func testUpcomingEmptyWhenAllPassed() {
        let anchor = MilestoneTestSupport.anchor(daysBeforeNow: 2000)
        let upcoming = MilestoneLogic.upcomingMilestones(from: anchor, now: MilestoneTestSupport.now, daysAhead: 30)
        XCTAssertTrue(upcoming.isEmpty)
    }

    func testUpcomingEmptyForNegativeDaysAhead() {
        let anchor = MilestoneTestSupport.anchor(daysBeforeNow: 50)
        let upcoming = MilestoneLogic.upcomingMilestones(from: anchor, now: MilestoneTestSupport.now, daysAhead: -10)
        XCTAssertTrue(upcoming.isEmpty)
    }

    func testUpcomingZeroDaysAheadReturnsOnlyHit() {
        // 已过 100 天，daysAhead=0 只含当天命中的 100
        let anchor = MilestoneTestSupport.anchor(daysBeforeNow: 100)
        let upcoming = MilestoneLogic.upcomingMilestones(from: anchor, now: MilestoneTestSupport.now, daysAhead: 0)
        XCTAssertEqual(upcoming.map(\.days), [100])
    }
}

// MARK: - 文案

final class MilestoneLogicTextTests: XCTestCase {

    func testMilestoneTitle() {
        XCTAssertEqual(MilestoneLogic.milestoneTitle(days: 100), "来到家 100 天")
        XCTAssertEqual(MilestoneLogic.milestoneTitle(days: 365), "来到家 365 天")
        XCTAssertEqual(MilestoneLogic.milestoneTitle(days: 1000), "来到家 1000 天")
    }

    func testMilestoneNotificationTextWithPetName() {
        XCTAssertEqual(
            MilestoneLogic.milestoneNotificationText(petName: "咪咪", days: 365),
            "咪咪来到家 365 天了"
        )
    }

    func testMilestoneNotificationTextWithoutPetName() {
        XCTAssertEqual(
            MilestoneLogic.milestoneNotificationText(petName: "", days: 100),
            "来到家 100 天"
        )
    }
}

// MARK: - MemoryCardKind 元数据

final class MemoryCardKindTests: XCTestCase {

    func testAllKindsPresent() {
        XCTAssertEqual(
            MemoryCardKind.allCases.map(\.rawValue),
            ["birthday", "adoptionDay", "milestone", "growthCompare", "monthlyRecap", "yearlyRecap"]
        )
    }

    func testRequiresSinglePhoto() {
        XCTAssertTrue(MemoryCardKind.birthday.requiresSinglePhoto)
        XCTAssertTrue(MemoryCardKind.adoptionDay.requiresSinglePhoto)
        XCTAssertTrue(MemoryCardKind.milestone.requiresSinglePhoto)
        XCTAssertFalse(MemoryCardKind.growthCompare.requiresSinglePhoto)
        XCTAssertFalse(MemoryCardKind.monthlyRecap.requiresSinglePhoto)
        XCTAssertFalse(MemoryCardKind.yearlyRecap.requiresSinglePhoto)
    }

    func testDefaultTemplateForSinglePhotoKinds() {
        XCTAssertEqual(MemoryCardKind.birthday.defaultTemplate, .classic)
        XCTAssertEqual(MemoryCardKind.milestone.defaultTemplate, .classic)
    }

    func testDefaultTemplateNilForMultiPhotoKinds() {
        XCTAssertNil(MemoryCardKind.growthCompare.defaultTemplate)
        XCTAssertNil(MemoryCardKind.monthlyRecap.defaultTemplate)
        XCTAssertNil(MemoryCardKind.yearlyRecap.defaultTemplate)
    }

    func testIsAnnuallyRecurring() {
        XCTAssertTrue(MemoryCardKind.birthday.isAnnuallyRecurring)
        XCTAssertTrue(MemoryCardKind.adoptionDay.isAnnuallyRecurring)
        XCTAssertFalse(MemoryCardKind.milestone.isAnnuallyRecurring)
        XCTAssertFalse(MemoryCardKind.growthCompare.isAnnuallyRecurring)
    }

    func testLocalizationKey() {
        XCTAssertEqual(MemoryCardKind.birthday.localizationKey, "memory.kind.birthday")
        XCTAssertEqual(MemoryCardKind.growthCompare.localizationKey, "memory.kind.growthCompare")
    }
}
