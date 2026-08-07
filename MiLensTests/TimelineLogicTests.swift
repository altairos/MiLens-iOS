import XCTest
@testable import MiLens

/// TimelineLogic 测试（对应源端 TimelineViewModel.test.ets）。
/// 覆盖 buildTimelineEntries（纪念事件/历年生日/幼宠提醒/照片事件/排序/空输入）、
/// buildMonths（分组/年份标记）、filterTimelineEntries、findMonthIndex。
///
/// 架构差异：源端用 new Date(y, month0, d) 构造日期、id 为整数；
/// iOS 用固定 UTC Gregorian + DateComponents 构造、id 为 UUID。
/// 日期断言改用 isoDateString 比较（对应源端 date 字符串断言）。
final class TimelineLogicTests: XCTestCase {

    private let cal = PetDateCalendar.gregorian

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d
        return cal.date(from: dc)!
    }

    private func pet(_ id: UUID, name: String, birthday: Date? = nil, hasFeatureData: Bool = false) -> TimelinePet {
        TimelinePet(id: id, name: name, birthday: birthday, hasFeatureData: hasFeatureData)
    }

    private func input(
        pets: [TimelinePet] = [], petEvents: [TimelinePetEvent] = [],
        photoEvents: [TimelinePhoto] = [], now: Date
    ) -> TimelineInput {
        TimelineInput(pets: pets, petEvents: petEvents, photoEvents: photoEvents, now: now)
    }

    // MARK: - buildTimelineEntries：历年生日

    func testBuildTimelineEntriesGeneratesBirthdayEntriesForPastBirthdays() {
        let petID = UUID()
        let p = pet(petID, name: "Max", birthday: date(2024, 1, 15))
        let entries = TimelineLogic.buildTimelineEntries(input(pets: [p], now: date(2026, 1, 16)), calendar: cal)
        let birthdays = entries.filter { $0.type == .birthday }
        XCTAssertEqual(birthdays.count, 2)
        XCTAssertEqual(TimelineLogic.isoDateString(from: birthdays[0].date, calendar: cal), "2025-01-15")
        XCTAssertEqual(TimelineLogic.isoDateString(from: birthdays[1].date, calendar: cal), "2026-01-15")
    }

    func testBuildTimelineEntriesRespectsNowInjectionForBirthdayLoop() {
        let petID = UUID()
        let p = pet(petID, name: "Max", birthday: date(2024, 1, 15))
        let e1 = TimelineLogic.buildTimelineEntries(input(pets: [p], now: date(2025, 1, 16)), calendar: cal)
        XCTAssertEqual(e1.filter { $0.type == .birthday }.count, 1)

        let e2 = TimelineLogic.buildTimelineEntries(input(pets: [p], now: date(2027, 1, 16)), calendar: cal)
        XCTAssertEqual(e2.filter { $0.type == .birthday }.count, 3)
    }

    func testBuildTimelineEntriesSkipsPetsWithoutBirthday() {
        let p = pet(UUID(), name: "NoBirthday")
        let entries = TimelineLogic.buildTimelineEntries(input(pets: [p], now: date(2026, 1, 1)), calendar: cal)
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - buildTimelineEntries：幼宠参考照片提醒

    func testBuildTimelineEntriesGeneratesMonthlyRemindersForPetsUnder6Months() {
        let petID = UUID()
        let p = pet(petID, name: "Kitty", birthday: date(2024, 11, 1), hasFeatureData: true)
        let entries = TimelineLogic.buildTimelineEntries(input(pets: [p], now: date(2025, 1, 2)), calendar: cal)
        let reminders = entries.filter { $0.id.hasPrefix("retrain_") }
        XCTAssertEqual(reminders.count, 2)
    }

    func testBuildTimelineEntriesUsesInterval2ForPets6To12Months() {
        let petID = UUID()
        let p = pet(petID, name: "Buddy", birthday: date(2024, 3, 1), hasFeatureData: true)
        let entries = TimelineLogic.buildTimelineEntries(input(pets: [p], now: date(2024, 9, 2)), calendar: cal)
        let reminders = entries.filter { $0.id.hasPrefix("retrain_") }
        XCTAssertEqual(reminders.count, 3)
    }

    func testBuildTimelineEntriesSkipsRemindersForPets12PlusMonths() {
        let petID = UUID()
        let p = pet(petID, name: "Old", birthday: date(2023, 1, 1), hasFeatureData: true)
        let entries = TimelineLogic.buildTimelineEntries(input(pets: [p], now: date(2024, 6, 1)), calendar: cal)
        let reminders = entries.filter { $0.id.hasPrefix("retrain_") }
        XCTAssertEqual(reminders.count, 0)
    }

    func testBuildTimelineEntriesSkipsRemindersForPetsWithoutFeatureData() {
        // V1.0 实际场景：featureData 恒为 nil，提醒不应出现
        let p = pet(UUID(), name: "Unregistered", birthday: date(2024, 11, 1), hasFeatureData: false)
        let entries = TimelineLogic.buildTimelineEntries(input(pets: [p], now: date(2025, 1, 2)), calendar: cal)
        XCTAssertTrue(entries.filter { $0.id.hasPrefix("retrain_") }.isEmpty)
    }

    // MARK: - buildTimelineEntries：照片事件

    func testBuildTimelineEntriesIncludesPhotoEvents() {
        let petID = UUID()
        let photoID = UUID()
        let p = pet(petID, name: "Max")
        let photo = TimelinePhoto(id: photoID, petID: petID, takenAt: date(2024, 6, 15),
                                  note: "", uri: "file://test.jpg", thumbnailPath: "")
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [p], photoEvents: [photo], now: date(2026, 1, 1)), calendar: cal)
        let photoEntries = entries.filter { $0.photoID == photoID }
        XCTAssertEqual(photoEntries.count, 1)
        XCTAssertEqual(photoEntries[0].type, .photoNote)
        XCTAssertEqual(photoEntries[0].petID, petID)
    }

    func testBuildTimelineEntriesPhotoWithoutPetShowsGenericTitle() {
        let photoID = UUID()
        let photo = TimelinePhoto(id: photoID, petID: nil, takenAt: date(2024, 6, 15),
                                  note: "", uri: "u", thumbnailPath: "")
        let entries = TimelineLogic.buildTimelineEntries(
            input(photoEvents: [photo], now: date(2026, 1, 1)), calendar: cal)
        XCTAssertEqual(entries.first?.title, "照片")
    }

    func testBuildTimelineEntriesPhotoWithNoteUsesNoteAsTitle() {
        let photoID = UUID()
        let photo = TimelinePhoto(id: photoID, petID: nil, takenAt: date(2024, 6, 15),
                                  note: "第一次洗澡", uri: "u", thumbnailPath: "")
        let entries = TimelineLogic.buildTimelineEntries(
            input(photoEvents: [photo], now: date(2026, 1, 1)), calendar: cal)
        XCTAssertEqual(entries.first?.title, "第一次洗澡")
    }

    // MARK: - buildTimelineEntries：纪念事件 + 排序 + 空输入

    func testBuildTimelineEntriesReturnsEmptyForNoInput() {
        let entries = TimelineLogic.buildTimelineEntries(input(now: date(2026, 1, 1)), calendar: cal)
        XCTAssertTrue(entries.isEmpty)
    }

    func testBuildTimelineEntriesIncludesPetEventsAsEntries() {
        let petID = UUID()
        let eventID = UUID()
        let p = pet(petID, name: "Max")
        let ev = TimelinePetEvent(id: eventID, petID: petID, eventType: "adoption",
                                  eventDate: date(2024, 3, 10), title: "Adoption Day")
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [p], petEvents: [ev], now: date(2026, 1, 1)), calendar: cal)
        let eventEntries = entries.filter { $0.id == "pet_\(eventID.uuidString)" }
        XCTAssertEqual(eventEntries.count, 1)
        XCTAssertEqual(eventEntries[0].title, "Adoption Day")
    }

    func testBuildTimelineEntriesPetEventWithoutTitleUsesPetName() {
        let petID = UUID()
        let eventID = UUID()
        let p = pet(petID, name: "Max")
        let ev = TimelinePetEvent(id: eventID, petID: petID, eventType: "adoption",
                                  eventDate: date(2024, 3, 10), title: "")
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [p], petEvents: [ev], now: date(2026, 1, 1)), calendar: cal)
        XCTAssertEqual(entries.first?.title, "Max的纪念日")
    }

    func testBuildTimelineEntriesSortsEntriesByDateAscending() {
        let p = pet(UUID(), name: "Max")
        let photo1 = TimelinePhoto(id: UUID(), petID: nil, takenAt: date(2024, 6, 15),
                                   note: "", uri: "", thumbnailPath: "")
        let photo2 = TimelinePhoto(id: UUID(), petID: nil, takenAt: date(2024, 1, 15),
                                   note: "", uri: "", thumbnailPath: "")
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [p], photoEvents: [photo1, photo2], now: date(2026, 1, 1)), calendar: cal)
        XCTAssertEqual(TimelineLogic.isoDateString(from: entries[0].date, calendar: cal), "2024-01-15")
        XCTAssertEqual(TimelineLogic.isoDateString(from: entries[1].date, calendar: cal), "2024-06-15")
    }

    // MARK: - buildMonths

    func testBuildMonthsGroupsEntriesByYearMonth() {
        let p = pet(UUID(), name: "Max")
        let photos = [
            TimelinePhoto(id: UUID(), petID: nil, takenAt: date(2024, 3, 10), note: "", uri: "", thumbnailPath: ""),
            TimelinePhoto(id: UUID(), petID: nil, takenAt: date(2024, 3, 20), note: "", uri: "", thumbnailPath: ""),
            TimelinePhoto(id: UUID(), petID: nil, takenAt: date(2024, 5, 1), note: "", uri: "", thumbnailPath: "")
        ]
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [p], photoEvents: photos, now: date(2026, 1, 1)), calendar: cal)
        let months = TimelineLogic.buildMonths(entries, selectedPetID: nil, calendar: cal)
        XCTAssertEqual(months.count, 2)
        XCTAssertEqual(months[0].entries.count, 2)
        XCTAssertEqual(months[1].entries.count, 1)
    }

    func testBuildMonthsMarksFirstMonthOfEachYearAsYearStart() {
        let p = pet(UUID(), name: "Max")
        let photos = [
            TimelinePhoto(id: UUID(), petID: nil, takenAt: date(2024, 1, 10), note: "", uri: "", thumbnailPath: ""),
            TimelinePhoto(id: UUID(), petID: nil, takenAt: date(2025, 2, 10), note: "", uri: "", thumbnailPath: "")
        ]
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [p], photoEvents: photos, now: date(2026, 1, 1)), calendar: cal)
        let months = TimelineLogic.buildMonths(entries, selectedPetID: nil, calendar: cal)
        XCTAssertEqual(months.count, 2)
        XCTAssertTrue(months[0].isYearStart)
        XCTAssertTrue(months[1].isYearStart)
    }

    func testBuildMonthsDoesNotMarkSecondMonthOfSameYearAsYearStart() {
        let p = pet(UUID(), name: "Max")
        let photos = [
            TimelinePhoto(id: UUID(), petID: nil, takenAt: date(2024, 1, 10), note: "", uri: "", thumbnailPath: ""),
            TimelinePhoto(id: UUID(), petID: nil, takenAt: date(2024, 5, 10), note: "", uri: "", thumbnailPath: "")
        ]
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [p], photoEvents: photos, now: date(2026, 1, 1)), calendar: cal)
        let months = TimelineLogic.buildMonths(entries, selectedPetID: nil, calendar: cal)
        XCTAssertEqual(months.count, 2)
        XCTAssertTrue(months[0].isYearStart)
        XCTAssertFalse(months[1].isYearStart)
    }

    // MARK: - filterTimelineEntries

    func testFilterTimelineEntriesFiltersBySelectedPetID() {
        let pet1ID = UUID()
        let pet2ID = UUID()
        let photo1 = TimelinePhoto(id: UUID(), petID: pet1ID, takenAt: date(2024, 6, 15),
                                   note: "", uri: "", thumbnailPath: "")
        let photo2 = TimelinePhoto(id: UUID(), petID: pet2ID, takenAt: date(2024, 6, 16),
                                   note: "", uri: "", thumbnailPath: "")
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [pet(pet1ID, name: "A"), pet(pet2ID, name: "B")],
                  photoEvents: [photo1, photo2], now: date(2026, 1, 1)), calendar: cal)
        let filtered = TimelineLogic.filterTimelineEntries(entries, selectedPetID: pet1ID)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].petID, pet1ID)
    }

    func testFilterTimelineEntriesReturnsAllForNilSelectedPetID() {
        let pet1ID = UUID()
        let photo1 = TimelinePhoto(id: UUID(), petID: pet1ID, takenAt: date(2024, 6, 15),
                                   note: "", uri: "", thumbnailPath: "")
        let photo2 = TimelinePhoto(id: UUID(), petID: nil, takenAt: date(2024, 6, 16),
                                   note: "", uri: "", thumbnailPath: "")
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [pet(pet1ID, name: "A")], photoEvents: [photo1, photo2],
                  now: date(2026, 1, 1)), calendar: cal)
        let filtered = TimelineLogic.filterTimelineEntries(entries, selectedPetID: nil)
        XCTAssertEqual(filtered.count, entries.count)
    }

    // MARK: - findMonthIndex

    func testFindMonthIndexReturnsIndexWhenEntryPresent() {
        let photoID = UUID()
        let photo = TimelinePhoto(id: photoID, petID: nil, takenAt: date(2024, 6, 15),
                                  note: "", uri: "", thumbnailPath: "")
        let entries = TimelineLogic.buildTimelineEntries(
            input(photoEvents: [photo], now: date(2026, 1, 1)), calendar: cal)
        let months = TimelineLogic.buildMonths(entries, selectedPetID: nil, calendar: cal)
        let idx = TimelineLogic.findMonthIndex(containing: "photo_\(photoID.uuidString)", in: months)
        XCTAssertEqual(idx, 0)
    }

    func testFindMonthIndexReturnsNilWhenEntryAbsent() {
        let months = [TimelineMonth(year: 2024, month: 6, yearMonth: "2024-06",
                                    isYearStart: true, entries: [])]
        XCTAssertNil(TimelineLogic.findMonthIndex(containing: "missing", in: months))
    }
}
