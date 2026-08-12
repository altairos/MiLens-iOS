import XCTest
@testable import MiLens

/// AnniversaryLogic + TimeMachineLogic 纯决策测试。
///
/// 覆盖：
/// - formatAnniversaryMonthDay（翻译源端 PhotoQueryLogic.test 5 用例）
/// - computeYearsAgo（翻译源端 NotifyScheduler.getYearsAgo 行为）
/// - isHistoricalPhoto（翻译源端 TimeMachineService 过滤逻辑）
/// - buildAnniversaryNotificationText / buildTimeMachineText（文案 parity）
/// - timeMachineNotificationID（源端 NOTIFY_CONSTANTS 公式 parity）
/// - selectTimeMachinePhoto（源端 random select 行为参数化）
/// - buildTimeMachineResult（端到端结果构建）
/// - buildAnniversaryNotifications（批量纪念日通知构建）
final class AnniversaryTimeMachineLogicTests: XCTestCase {

    // 固定 UTC Calendar 用于构造测试日期
    private var calendar: Calendar { utcCalendar }

    /// 构造固定日期：UTC 时区下的 year-month-day。
    private func makeDate(_ year: Int, _ month: Int, _ day: Int,
                          _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.timeZone = TimeZone(identifier: "UTC")
        return calendar.date(from: comps)!
    }

    // MARK: - formatAnniversaryMonthDay

    func testFormatPadsSingleDigitMonthAndDay() {
        XCTAssertEqual(formatAnniversaryMonthDay(3, 5), "03-05")
    }

    func testFormatPreservesDoubleDigitMonthAndDay() {
        XCTAssertEqual(formatAnniversaryMonthDay(12, 25), "12-25")
    }

    func testFormatHandlesOctoberFirst() {
        XCTAssertEqual(formatAnniversaryMonthDay(10, 1), "10-01")
    }

    func testFormatHandlesJanuaryFirst() {
        XCTAssertEqual(formatAnniversaryMonthDay(1, 1), "01-01")
    }

    func testFormatHandlesDecember31st() {
        XCTAssertEqual(formatAnniversaryMonthDay(12, 31), "12-31")
    }

    // MARK: - computeYearsAgo

    func testYearsAgoCalculatesCorrectDifference() {
        let now = makeDate(2026, 6, 15)
        XCTAssertEqual(computeYearsAgo(fromDateString: "2024-06-15T10:00:00", now: now), 2)
    }

    func testYearsAgoReturnsZeroForSameYear() {
        let now = makeDate(2026, 6, 15)
        XCTAssertEqual(computeYearsAgo(fromDateString: "2026-01-01T00:00:00", now: now), 0)
    }

    func testYearsAgoReturnsZeroForEmptyString() {
        let now = makeDate(2026, 6, 15)
        XCTAssertEqual(computeYearsAgo(fromDateString: "", now: now), 0)
    }

    func testYearsAgoAcceptsDateOnlyFormat() {
        let now = makeDate(2026, 6, 15)
        // "2024-06-15" 纯日期格式也应解析
        XCTAssertEqual(computeYearsAgo(fromDateString: "2024-06-15", now: now), 2)
    }

    func testYearsAgoHandlesCrossYearBoundary() {
        let now = makeDate(2026, 1, 1)
        XCTAssertEqual(computeYearsAgo(fromDateString: "2025-12-31T23:59:59", now: now), 1)
    }

    // MARK: - isHistoricalPhoto

    func testIsHistoricalReturnsTrueForPastYear() {
        let now = makeDate(2026, 6, 15)
        let takenAt = makeDate(2024, 6, 15)
        XCTAssertTrue(isHistoricalPhoto(takenAt: takenAt, now: now))
    }

    func testIsHistoricalReturnsFalseForSameYear() {
        let now = makeDate(2026, 6, 15)
        let takenAt = makeDate(2026, 1, 1)
        XCTAssertFalse(isHistoricalPhoto(takenAt: takenAt, now: now))
    }

    func testIsHistoricalReturnsFalseForNil() {
        let now = makeDate(2026, 6, 15)
        XCTAssertFalse(isHistoricalPhoto(takenAt: nil, now: now))
    }

    func testIsHistoricalReturnsFalseForFutureYear() {
        let now = makeDate(2026, 6, 15)
        let takenAt = makeDate(2027, 6, 15)
        XCTAssertFalse(isHistoricalPhoto(takenAt: takenAt, now: now))
    }

    // MARK: - buildAnniversaryNotificationText

    func testAnniversaryTextWithYearsAgo() {
        let text = buildAnniversaryNotificationText(yearsAgo: 3, note: "在公园玩耍")
        XCTAssertEqual(text, "3年前的今天：在公园玩耍")
    }

    func testAnniversaryTextWithZeroYearsAgo() {
        let text = buildAnniversaryNotificationText(yearsAgo: 0, note: "今天的照片")
        XCTAssertEqual(text, "往年今日的回忆：今天的照片")
    }

    func testAnniversaryTextWithEmptyNote() {
        let text = buildAnniversaryNotificationText(yearsAgo: 2, note: "")
        XCTAssertEqual(text, "2年前的今天：")
    }

    // MARK: - buildTimeMachineText

    func testTimeMachineTextTemplate0() {
        let text = buildTimeMachineText(petName: "咪咪", yearsAgo: 2, note: "", index: 0)
        XCTAssertEqual(text, "2年前的今天，咪咪在做什么呢？")
    }

    func testTimeMachineTextTemplate1() {
        let text = buildTimeMachineText(petName: "咪咪", yearsAgo: 2, note: "", index: 1)
        XCTAssertEqual(text, "2年前的今天，咪咪这样陪伴着你")
    }

    func testTimeMachineTextTemplate2WithNote() {
        let text = buildTimeMachineText(petName: "咪咪", yearsAgo: 2, note: "在晒太阳", index: 2)
        XCTAssertEqual(text, "2年前的今天，在晒太阳")
    }

    func testTimeMachineTextTemplate2WithoutNote() {
        let text = buildTimeMachineText(petName: "咪咪", yearsAgo: 2, note: "", index: 2)
        XCTAssertEqual(text, "时光飞逝，2年前的今天")
    }

    func testTimeMachineTextIndexWrapsAroundWithModulo() {
        // index 3 应等于 index 0（三个模板）
        let text0 = buildTimeMachineText(petName: "咪咪", yearsAgo: 2, note: "", index: 0)
        let text3 = buildTimeMachineText(petName: "咪咪", yearsAgo: 2, note: "", index: 3)
        XCTAssertEqual(text0, text3)
    }

    func testTimeMachineTextNegativeIndexWrapsCorrectly() {
        // index -1 应等于 index 2（三个模板，-1 % 3 = -1 → 2）
        let textNeg1 = buildTimeMachineText(petName: "咪咪", yearsAgo: 2, note: "", index: -1)
        let text2 = buildTimeMachineText(petName: "咪咪", yearsAgo: 2, note: "", index: 2)
        XCTAssertEqual(textNeg1, text2)
    }

    // MARK: - timeMachineNotificationID

    func testNotificationIDFormula() {
        // 源端：8000 + month * 100 + day
        XCTAssertEqual(timeMachineNotificationID(month: 6, day: 15), 8615)
        XCTAssertEqual(timeMachineNotificationID(month: 1, day: 1), 8101)
        XCTAssertEqual(timeMachineNotificationID(month: 12, day: 31), 9231)
    }

    func testNotificationIDIsUniquePerMonthDay() {
        var ids = Set<Int>()
        for month in 1...12 {
            for day in 1...31 {
                let id = timeMachineNotificationID(month: month, day: day)
                XCTAssertFalse(ids.contains(id), "Duplicate ID for \(month)/\(day)")
                ids.insert(id)
            }
        }
    }

    // MARK: - selectTimeMachinePhoto

    func testSelectReturnsNilForEmptyList() {
        XCTAssertNil(selectTimeMachinePhoto([], randomIndex: 0))
    }

    func testSelectReturnsOnlyElementForSingleItemList() {
        let photo = TimeMachinePhoto(id: UUID(), takenAt: nil, note: "test", petID: nil)
        let result = selectTimeMachinePhoto([photo], randomIndex: 0)
        XCTAssertEqual(result?.id, photo.id)
    }

    func testSelectReturnsFirstElementForIndexZero() {
        let p1 = TimeMachinePhoto(id: UUID(), takenAt: nil, note: "1", petID: nil)
        let p2 = TimeMachinePhoto(id: UUID(), takenAt: nil, note: "2", petID: nil)
        let p3 = TimeMachinePhoto(id: UUID(), takenAt: nil, note: "3", petID: nil)
        let result = selectTimeMachinePhoto([p1, p2, p3], randomIndex: 0)
        XCTAssertEqual(result?.id, p1.id)
    }

    func testSelectWrapsIndexWithModulo() {
        let p1 = TimeMachinePhoto(id: UUID(), takenAt: nil, note: "1", petID: nil)
        let p2 = TimeMachinePhoto(id: UUID(), takenAt: nil, note: "2", petID: nil)
        let p3 = TimeMachinePhoto(id: UUID(), takenAt: nil, note: "3", petID: nil)
        // index 3 → 3 % 3 = 0 → p1
        XCTAssertEqual(selectTimeMachinePhoto([p1, p2, p3], randomIndex: 3)?.id, p1.id)
        // index 4 → 4 % 3 = 1 → p2
        XCTAssertEqual(selectTimeMachinePhoto([p1, p2, p3], randomIndex: 4)?.id, p2.id)
    }

    // MARK: - buildTimeMachineResult

    func testBuildResultWithKnownPetAndPhoto() {
        let petID = UUID()
        let photoID = UUID()
        let photo = TimeMachinePhoto(
            id: photoID, takenAt: makeDate(2024, 6, 15), note: "在公园", petID: petID)
        let pets = [TimeMachinePet(id: petID, name: "咪咪")]
        let now = makeDate(2026, 6, 15)

        let result = buildTimeMachineResult(
            photo: photo, pets: pets, now: now, templateIndex: 0)

        XCTAssertEqual(result.title, "2年前的今天")
        XCTAssertEqual(result.photoID, photoID)
        XCTAssertTrue(result.body.contains("咪咪"))
        XCTAssertEqual(result.identifier, timeMachineNotificationID(month: 6, day: 15))
    }

    func testBuildResultUsesDefaultPetNameWhenPetNotFound() {
        let photo = TimeMachinePhoto(
            id: UUID(), takenAt: makeDate(2024, 6, 15), note: "", petID: UUID())
        let now = makeDate(2026, 6, 15)

        let result = buildTimeMachineResult(
            photo: photo, pets: [], now: now, templateIndex: 0)

        XCTAssertTrue(result.body.contains("小宝贝"))
    }

    func testBuildResultUsesDefaultPetNameWhenPetIDIsNil() {
        let photo = TimeMachinePhoto(
            id: UUID(), takenAt: makeDate(2024, 6, 15), note: "", petID: nil)
        let now = makeDate(2026, 6, 15)

        let result = buildTimeMachineResult(
            photo: photo, pets: [], now: now, templateIndex: 0)

        XCTAssertTrue(result.body.contains("小宝贝"))
    }

    func testBuildResultWithCustomDefaultName() {
        let photo = TimeMachinePhoto(
            id: UUID(), takenAt: makeDate(2024, 6, 15), note: "", petID: nil)
        let now = makeDate(2026, 6, 15)

        let result = buildTimeMachineResult(
            photo: photo, pets: [], now: now, templateIndex: 0, defaultPetName: "毛孩子")

        XCTAssertTrue(result.body.contains("毛孩子"))
    }

    func testBuildResultYearZeroWhenTakenAtIsNil() {
        // takenAt 为 nil → photoYear = nowYear → yearsAgo = 0
        let photo = TimeMachinePhoto(
            id: UUID(), takenAt: nil, note: "", petID: nil)
        let now = makeDate(2026, 6, 15)

        let result = buildTimeMachineResult(
            photo: photo, pets: [], now: now, templateIndex: 0)

        XCTAssertEqual(result.title, "0年前的今天")
    }

    // MARK: - buildAnniversaryNotifications

    func testAnniversaryNotificationsEmptyForEmptyPhotos() {
        let now = makeDate(2026, 6, 15)
        let result = buildAnniversaryNotifications(photos: [], now: now)
        XCTAssertTrue(result.isEmpty)
    }

    func testAnniversaryNotificationsOnePerPhoto() {
        let now = makeDate(2026, 6, 15)
        let photos = [
            TimeMachinePhoto(id: UUID(), takenAt: makeDate(2024, 6, 15), note: "A", petID: nil),
            TimeMachinePhoto(id: UUID(), takenAt: makeDate(2023, 6, 15), note: "B", petID: nil),
        ]
        let result = buildAnniversaryNotifications(photos: photos, now: now)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].title, "往日回忆")
        XCTAssertEqual(result[0].body, "2年前的今天：A")
        XCTAssertEqual(result[1].body, "3年前的今天：B")
    }

    func testAnniversaryNotificationWithZeroYearsAgo() {
        let now = makeDate(2026, 6, 15)
        let photos = [
            TimeMachinePhoto(id: UUID(), takenAt: makeDate(2026, 6, 15), note: "today", petID: nil),
        ]
        let result = buildAnniversaryNotifications(photos: photos, now: now)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].body, "往年今日的回忆：today")
    }

    func testAnniversaryNotificationPreservesPhotoID() {
        let photoID = UUID()
        let now = makeDate(2026, 6, 15)
        let photos = [
            TimeMachinePhoto(id: photoID, takenAt: makeDate(2024, 6, 15), note: "", petID: nil),
        ]
        let result = buildAnniversaryNotifications(photos: photos, now: now)
        XCTAssertEqual(result[0].photoID, photoID)
    }
}
