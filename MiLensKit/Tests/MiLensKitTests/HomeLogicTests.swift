import XCTest
@testable import MiLensKit

//  Home 纯决策逻辑测试（首页 hero，UI-Rework计划 Phase 3.1 数据层）。
//
//  无源端黄金规格（首页为 iOS 设计稿新增概念，源端无 HomePage），
//  行为规格由 UI-DESIGN.md §5.1 + 设计稿 Tab 1 定义，本文件守护：
//  - HomeGreetingLogic：时段问候（5-11 早上好 / 12-17 下午好 / 18-4 晚上好）
//  - HomeHeroLogic：hero 选片（今日最新 → 回退最近一张）+ 「今天 · 小橘」标注
//  - HomeMemoryLogic：「一年前的今天」回忆筛选（同月同日 → 回退最近历史）+ 标题/副标题
//
//  全部日期用固定 UTC Calendar（homeUTCCalendar）构造，任意时区可复现。

// MARK: - 测试工具

private enum HomeTestSupport {
    /// 固定「现在」：2026-08-08 12:00 UTC（与部署日一致，便于理解用例）。
    static let now = makeDate(2026, 8, 8, 12)

    static func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        return homeUTCCalendar.date(from: comps)!
    }
}

// MARK: - HomeGreetingLogic

final class HomeGreetingLogicTests: XCTestCase {

    func testMorningHours() {
        XCTAssertEqual(HomeGreetingLogic.greeting(forHour: 5), "早上好")
        XCTAssertEqual(HomeGreetingLogic.greeting(forHour: 8), "早上好")
        XCTAssertEqual(HomeGreetingLogic.greeting(forHour: 11), "早上好")
    }

    func testAfternoonHours() {
        XCTAssertEqual(HomeGreetingLogic.greeting(forHour: 12), "下午好")
        XCTAssertEqual(HomeGreetingLogic.greeting(forHour: 15), "下午好")
        XCTAssertEqual(HomeGreetingLogic.greeting(forHour: 17), "下午好")
    }

    func testEveningHours() {
        XCTAssertEqual(HomeGreetingLogic.greeting(forHour: 18), "晚上好")
        XCTAssertEqual(HomeGreetingLogic.greeting(forHour: 22), "晚上好")
        XCTAssertEqual(HomeGreetingLogic.greeting(forHour: 23), "晚上好")
        XCTAssertEqual(HomeGreetingLogic.greeting(forHour: 0), "晚上好")
        XCTAssertEqual(HomeGreetingLogic.greeting(forHour: 4), "晚上好")
    }

    func testOutOfRangeHoursNormalizedByModulo() {
        // -1 → 23 时（晚上好）；24 → 0 时（晚上好）；-7 → 17 时（下午好）
        XCTAssertEqual(HomeGreetingLogic.greeting(forHour: -1), "晚上好")
        XCTAssertEqual(HomeGreetingLogic.greeting(forHour: 24), "晚上好")
        XCTAssertEqual(HomeGreetingLogic.greeting(forHour: -7), "下午好")
    }
}

// MARK: - HomeHeroLogic

final class HomeHeroLogicTests: XCTestCase {

    private var now: Date { HomeTestSupport.now }

    // MARK: isToday

    func testIsTodayTrueForSameDay() {
        let taken = HomeTestSupport.makeDate(2026, 8, 8, 9)
        XCTAssertTrue(HomeHeroLogic.isToday(takenAt: taken, now: now))
    }

    func testIsTodayFalseForYesterday() {
        let taken = HomeTestSupport.makeDate(2026, 8, 7, 23)
        XCTAssertFalse(HomeHeroLogic.isToday(takenAt: taken, now: now))
    }

    func testIsTodayFalseForSameMonthDayOtherYear() {
        let taken = HomeTestSupport.makeDate(2025, 8, 8, 9)
        XCTAssertFalse(HomeHeroLogic.isToday(takenAt: taken, now: now))
    }

    func testIsTodayFalseForNil() {
        XCTAssertFalse(HomeHeroLogic.isToday(takenAt: nil, now: now))
    }

    // MARK: selectHeroPhoto

    func testSelectHeroPrefersLatestTodayPhoto() {
        let todayMorning = HomeHeroPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2026, 8, 8, 9))
        let todayEvening = HomeHeroPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2026, 8, 8, 20))
        let yesterday = HomeHeroPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2026, 8, 7, 12))
        let selected = HomeHeroLogic.selectHeroPhoto([todayMorning, yesterday, todayEvening], now: now)
        XCTAssertEqual(selected?.id, todayEvening.id)
    }

    func testSelectHeroFallsBackToLatestPhotoWhenNoTodayPhoto() {
        let older = HomeHeroPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2025, 3, 1, 10))
        let newest = HomeHeroPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2026, 7, 30, 18))
        let selected = HomeHeroLogic.selectHeroPhoto([older, newest], now: now)
        XCTAssertEqual(selected?.id, newest.id)
    }

    func testSelectHeroIgnoresPhotosWithoutTakenAt() {
        let noDate = HomeHeroPhoto(id: UUID(), takenAt: nil)
        let withDate = HomeHeroPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2026, 7, 30, 18))
        let selected = HomeHeroLogic.selectHeroPhoto([noDate, withDate], now: now)
        XCTAssertEqual(selected?.id, withDate.id)
    }

    func testSelectHeroReturnsNilForEmptyList() {
        XCTAssertNil(HomeHeroLogic.selectHeroPhoto([], now: now))
    }

    func testSelectHeroReturnsNilWhenNoPhotoHasTakenAt() {
        let noDate = HomeHeroPhoto(id: UUID(), takenAt: nil)
        XCTAssertNil(HomeHeroLogic.selectHeroPhoto([noDate], now: now))
    }

    // MARK: buildHeroCaption

    func testHeroCaptionTodayWithPetName() {
        XCTAssertEqual(HomeHeroLogic.buildHeroCaption(petName: "小橘", isToday: true), "今天 · 小橘")
    }

    func testHeroCaptionFallbackWithPetName() {
        XCTAssertEqual(HomeHeroLogic.buildHeroCaption(petName: "小橘", isToday: false), "最近 · 小橘")
    }

    func testHeroCaptionWithoutPetName() {
        XCTAssertEqual(HomeHeroLogic.buildHeroCaption(petName: nil, isToday: true), "今天")
        XCTAssertEqual(HomeHeroLogic.buildHeroCaption(petName: nil, isToday: false), "最近")
    }

    func testHeroCaptionIgnoresEmptyPetName() {
        XCTAssertEqual(HomeHeroLogic.buildHeroCaption(petName: "", isToday: true), "今天")
    }
}

// MARK: - HomeMemoryLogic

final class HomeMemoryLogicTests: XCTestCase {

    private var now: Date { HomeTestSupport.now }

    // MARK: 主筛（往年的今天）

    func testSelectsSameMonthDayHistoricalPhotosNewestYearFirst() {
        let lastYear = HomeMemoryPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2025, 8, 8, 10))
        let twoYearsAgo = HomeMemoryPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2024, 8, 8, 10))
        let entries = HomeMemoryLogic.selectMemoryPhotos([twoYearsAgo, lastYear], now: now)
        XCTAssertEqual(entries.map(\.photoID), [lastYear.id, twoYearsAgo.id])
    }

    func testExcludesTodayPhotoFromMemory() {
        let today = HomeMemoryPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2026, 8, 8, 10))
        let entries = HomeMemoryLogic.selectMemoryPhotos([today], now: now)
        XCTAssertTrue(entries.isEmpty)
    }

    func testExcludesOtherDatesFromSameYear() {
        let thisYearOtherDay = HomeMemoryPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2026, 3, 5, 10))
        let entries = HomeMemoryLogic.selectMemoryPhotos([thisYearOtherDay], now: now)
        XCTAssertTrue(entries.isEmpty)
    }

    func testMemoryTitleShowsYearsAgo() {
        let oneYear = HomeMemoryPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2025, 8, 8, 10))
        let threeYears = HomeMemoryPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2023, 8, 8, 10))
        let entries = HomeMemoryLogic.selectMemoryPhotos([threeYears, oneYear], now: now)
        XCTAssertEqual(entries[0].title, "1年前的今天")
        XCTAssertEqual(entries[1].title, "3年前的今天")
    }

    func testMemorySubtitleUsesPetName() {
        let petID = UUID()
        let photo = HomeMemoryPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2025, 8, 8, 10), petID: petID)
        let pets = [HomeMemoryPet(id: petID, name: "小橘")]
        let entries = HomeMemoryLogic.selectMemoryPhotos([photo], now: now, pets: pets)
        XCTAssertEqual(entries[0].subtitle, "小橘")
    }

    func testMemorySubtitleEmptyWhenPetUnknown() {
        let photo = HomeMemoryPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2025, 8, 8, 10))
        let entries = HomeMemoryLogic.selectMemoryPhotos([photo], now: now)
        XCTAssertEqual(entries[0].subtitle, "")
    }

    // MARK: 回退（最近历史照片）

    func testFallsBackToRecentHistoricalPhotos() {
        let july = HomeMemoryPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2025, 7, 30, 10))
        let march = HomeMemoryPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2025, 3, 1, 10))
        let entries = HomeMemoryLogic.selectMemoryPhotos([march, july], now: now)
        XCTAssertEqual(entries.map(\.photoID), [july.id, march.id])
        XCTAssertEqual(entries[0].title, "最近回忆")
    }

    func testFallbackSubtitleContainsDateAndPetName() {
        let petID = UUID()
        let photo = HomeMemoryPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2025, 7, 30, 10), petID: petID)
        let pets = [HomeMemoryPet(id: petID, name: "旺财")]
        let entries = HomeMemoryLogic.selectMemoryPhotos([photo], now: now, pets: pets)
        XCTAssertEqual(entries[0].subtitle, "2025年7月30日 · 旺财")
    }

    func testFallbackSubtitleDateOnlyWithoutPet() {
        let photo = HomeMemoryPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2025, 7, 30, 10))
        let entries = HomeMemoryLogic.selectMemoryPhotos([photo], now: now)
        XCTAssertEqual(entries[0].subtitle, "2025年7月30日")
    }

    func testFallbackRespectsLimit() {
        let photos = (1...10).map { i in
            HomeMemoryPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2025, 6, i, 10))
        }
        let entries = HomeMemoryLogic.selectMemoryPhotos(photos, now: now, limit: 3)
        XCTAssertEqual(entries.count, 3)
    }

    func testDefaultLimitIsSix() {
        XCTAssertEqual(HomeMemoryLogic.defaultLimit, 6)
        let photos = (1...10).map { i in
            HomeMemoryPhoto(id: UUID(), takenAt: HomeTestSupport.makeDate(2025, 6, i, 10))
        }
        let entries = HomeMemoryLogic.selectMemoryPhotos(photos, now: now)
        XCTAssertEqual(entries.count, 6)
    }

    func testEmptyListReturnsEmpty() {
        XCTAssertTrue(HomeMemoryLogic.selectMemoryPhotos([], now: now).isEmpty)
    }

    func testIgnoresPhotosWithoutTakenAt() {
        let noDate = HomeMemoryPhoto(id: UUID(), takenAt: nil)
        XCTAssertTrue(HomeMemoryLogic.selectMemoryPhotos([noDate], now: now).isEmpty)
    }

    // MARK: isHistoricalPhoto / formatMemoryDate

    func testIsHistoricalPhotoYearBoundary() {
        XCTAssertTrue(HomeMemoryLogic.isHistoricalPhoto(
            takenAt: HomeTestSupport.makeDate(2025, 12, 31, 23), now: now))
        XCTAssertFalse(HomeMemoryLogic.isHistoricalPhoto(
            takenAt: HomeTestSupport.makeDate(2026, 1, 1, 0), now: now))
        XCTAssertFalse(HomeMemoryLogic.isHistoricalPhoto(takenAt: nil, now: now))
    }

    func testFormatMemoryDate() {
        XCTAssertEqual(HomeMemoryLogic.formatMemoryDate(HomeTestSupport.makeDate(2024, 8, 8, 10)), "2024年8月8日")
        XCTAssertEqual(HomeMemoryLogic.formatMemoryDate(HomeTestSupport.makeDate(2021, 12, 31, 23)), "2021年12月31日")
    }
}
