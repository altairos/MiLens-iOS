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
        XCTAssertEqual(entries.first?.title, "和Max成为家人的日子")
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

    // MARK: - SchemaV2：用户文本记忆（textNote）

    func testBuildTimelineEntriesCreatesTextNoteForUserSourceWithBody() {
        let petID = UUID()
        let ev = TimelinePetEvent(
            id: UUID(), petID: petID, eventType: "custom",
            eventDate: date(2026, 5, 16), title: "生日记忆",
            body: "两岁了。愿以后每一年，我们都还能这样看着彼此。",
            sourceType: "user"
        )
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [pet(petID, name: "小满")], petEvents: [ev], now: date(2026, 6, 1)),
            calendar: cal)
        let notes = entries.filter { $0.type == .textNote }
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].bodyText, "两岁了。愿以后每一年，我们都还能这样看着彼此。")
        XCTAssertEqual(notes[0].sourceType, "user")
        XCTAssertEqual(notes[0].title, "生日记忆")
    }

    func testBuildTimelineEntriesSkipsTextNoteWhenBodyEmpty() {
        let petID = UUID()
        // sourceType=user 但 body 为空 → 不应生成 textNote，回落为系统事件
        let ev = TimelinePetEvent(
            id: UUID(), petID: petID, eventType: "birthday",
            eventDate: date(2026, 5, 16), title: "生日",
            body: "", sourceType: "user"
        )
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [pet(petID, name: "小满")], petEvents: [ev], now: date(2026, 6, 1)),
            calendar: cal)
        let notes = entries.filter { $0.type == .textNote }
        XCTAssertEqual(notes.count, 0)
        // 应回落为系统事件（birthday）
        XCTAssertFalse(entries.filter { $0.type == .birthday }.isEmpty)
    }

    func testBuildTimelineEntriesSkipsTextNoteForSystemSource() {
        let petID = UUID()
        // sourceType=system → 不生成 textNote
        let ev = TimelinePetEvent(
            id: UUID(), petID: petID, eventType: "birthday",
            eventDate: date(2026, 5, 16), title: "生日",
            body: "不应出现的正文", sourceType: "system"
        )
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [pet(petID, name: "小满")], petEvents: [ev], now: date(2026, 6, 1)),
            calendar: cal)
        let notes = entries.filter { $0.type == .textNote }
        XCTAssertEqual(notes.count, 0)
    }

    func testTextNoteSortsWithOtherEntriesByDate() {
        let petID = UUID()
        let textEv = TimelinePetEvent(
            id: UUID(), petID: petID, eventType: "custom",
            eventDate: date(2026, 5, 16), title: "生日记忆",
            body: "两岁了。", sourceType: "user"
        )
        let photo = TimelinePhoto(
            id: UUID(), petID: petID, takenAt: date(2026, 6, 18),
            note: "夏天", uri: "", thumbnailPath: ""
        )
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [pet(petID, name: "小满")], petEvents: [textEv],
                  photoEvents: [photo], now: date(2026, 7, 1)),
            calendar: cal)
        // textNote (5月) 应在 photoNote (6月) 之前
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].type, .textNote)
        XCTAssertEqual(entries[1].type, .photoNote)
    }

    func testBuildTimelineEntriesTextNoteUsesDefaultTitleWhenEmpty() {
        let petID = UUID()
        // 空标题回退默认标签（timeline.memoryType.text），正文仍完整保留
        let ev = TimelinePetEvent(
            id: UUID(), petID: petID, eventType: "custom",
            eventDate: date(2026, 5, 16), title: "",
            body: "只有正文没有标题", sourceType: "user"
        )
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [pet(petID, name: "小满")], petEvents: [ev], now: date(2026, 6, 1)),
            calendar: cal)
        let notes = entries.filter { $0.type == .textNote }
        XCTAssertEqual(notes.count, 1)
        XCTAssertFalse(notes[0].title.isEmpty)
        XCTAssertEqual(notes[0].bodyText, "只有正文没有标题")
    }

    func testBuildTimelineEntriesTextNoteLinksRelatedPhoto() {
        let petID = UUID()
        let photoID = UUID()
        // AddMemorySheet 从照片页进入时预填 relatedPhotoID → textNote 回链来源照片
        let ev = TimelinePetEvent(
            id: UUID(), petID: petID, eventType: "custom",
            eventDate: date(2026, 5, 16), title: "照片背后的故事",
            body: "那天它第一次学会握手。", sourceType: "user",
            relatedPhotoID: photoID
        )
        let photo = TimelinePhoto(
            id: photoID, petID: petID, takenAt: date(2026, 5, 10),
            note: "", uri: "file://src.jpg", thumbnailPath: "thumb.jpg"
        )
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [pet(petID, name: "小满")], petEvents: [ev],
                  photoEvents: [photo], now: date(2026, 6, 1)),
            calendar: cal)
        let note = entries.first { $0.type == .textNote }
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.photoID, photoID)
        XCTAssertEqual(note?.photoURI, "file://src.jpg")
        XCTAssertEqual(note?.thumbnailPath, "thumb.jpg")
    }

    // MARK: - SchemaV2：作品记录（workRecord）

    func testBuildTimelineEntriesCreatesWorkRecordForWorkSource() {
        let petID = UUID()
        let ev = TimelinePetEvent(
            id: UUID(), petID: petID, eventType: "custom",
            eventDate: date(2026, 5, 16), title: "拼豆图纸",
            body: "用夏天那张照片做的", sourceType: "work"
        )
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [pet(petID, name: "小满")], petEvents: [ev], now: date(2026, 6, 1)),
            calendar: cal)
        let works = entries.filter { $0.type == .workRecord }
        XCTAssertEqual(works.count, 1)
        XCTAssertEqual(works[0].title, "拼豆图纸")
        XCTAssertEqual(works[0].sourceType, "work")
        XCTAssertEqual(works[0].bodyText, "用夏天那张照片做的")
        XCTAssertEqual(works[0].petID, petID)
    }

    func testBuildTimelineEntriesWorkRecordLinksRelatedPhoto() {
        let petID = UUID()
        let photoID = UUID()
        let ev = TimelinePetEvent(
            id: UUID(), petID: petID, eventType: "custom",
            eventDate: date(2026, 5, 16), title: "拼豆图纸",
            body: "", sourceType: "work", relatedPhotoID: photoID
        )
        let photo = TimelinePhoto(
            id: photoID, petID: petID, takenAt: date(2026, 5, 10),
            note: "", uri: "file://src.jpg", thumbnailPath: "thumb.jpg"
        )
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [pet(petID, name: "小满")], petEvents: [ev],
                  photoEvents: [photo], now: date(2026, 6, 1)),
            calendar: cal)
        let work = entries.first { $0.type == .workRecord }
        XCTAssertNotNil(work)
        XCTAssertEqual(work?.photoID, photoID)
        XCTAssertEqual(work?.photoURI, "file://src.jpg")
        XCTAssertEqual(work?.thumbnailPath, "thumb.jpg")
    }

    func testBuildTimelineEntriesWorkRecordWithoutRelatedPhotoHasNilPhotoID() {
        let petID = UUID()
        let ev = TimelinePetEvent(
            id: UUID(), petID: petID, eventType: "custom",
            eventDate: date(2026, 5, 16), title: "编辑作品",
            body: "", sourceType: "work"
        )
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [pet(petID, name: "小满")], petEvents: [ev], now: date(2026, 6, 1)),
            calendar: cal)
        let work = entries.first { $0.type == .workRecord }
        XCTAssertNotNil(work)
        XCTAssertNil(work?.photoID)
        XCTAssertEqual(work?.photoURI, "")
        XCTAssertEqual(work?.thumbnailPath, "")
    }

    func testBuildTimelineEntriesWorkRecordUsesDefaultTitleWhenEmpty() {
        let petID = UUID()
        let ev = TimelinePetEvent(
            id: UUID(), petID: petID, eventType: "custom",
            eventDate: date(2026, 5, 16), title: "",
            body: "", sourceType: "work"
        )
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [pet(petID, name: "小满")], petEvents: [ev], now: date(2026, 6, 1)),
            calendar: cal)
        let work = entries.first { $0.type == .workRecord }
        XCTAssertNotNil(work)
        // 空标题回退到默认标签（timeline.memoryType.work）
        XCTAssertFalse(work?.title.isEmpty ?? true)
    }

    func testWorkRecordSortsWithOtherEntriesByDate() {
        let petID = UUID()
        let workEv = TimelinePetEvent(
            id: UUID(), petID: petID, eventType: "custom",
            eventDate: date(2026, 5, 16), title: "拼豆",
            body: "", sourceType: "work"
        )
        let photo = TimelinePhoto(
            id: UUID(), petID: petID, takenAt: date(2026, 6, 18),
            note: "夏天", uri: "", thumbnailPath: ""
        )
        let entries = TimelineLogic.buildTimelineEntries(
            input(pets: [pet(petID, name: "小满")], petEvents: [workEv],
                  photoEvents: [photo], now: date(2026, 7, 1)),
            calendar: cal)
        // workRecord (5月) 应在 photoNote (6月) 之前
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].type, .workRecord)
        XCTAssertEqual(entries[1].type, .photoNote)
    }

    // MARK: - 生命档案增强：档案统计（computeArchiveStats）

    func testComputeArchiveStatsCountsAllFields() {
        let petID = UUID()
        let events = [
            TimelinePetEvent(id: UUID(), petID: petID, eventType: "birthday",
                            eventDate: date(2024, 5, 1), title: "生日"),
            TimelinePetEvent(id: UUID(), petID: petID, eventType: "adoption",
                            eventDate: date(2024, 6, 1), title: "领养"),
            TimelinePetEvent(id: UUID(), petID: petID, eventType: "custom",
                            eventDate: date(2025, 1, 1), title: "记录",
                            body: "一段记忆", sourceType: "user"),
        ]
        let photos = [
            TimelinePhoto(id: UUID(), petID: petID, takenAt: date(2024, 5, 10),
                          note: "", uri: "file://test.jpg", thumbnailPath: ""),
        ]
        let stats = TimelineLogic.computeArchiveStats(
            photoCount: 1, events: events, photos: photos,
            adoptionDay: date(2024, 6, 1), now: date(2026, 6, 1), calendar: cal)
        XCTAssertEqual(stats.photoCount, 1)
        XCTAssertEqual(stats.memoryCount, 3)
        XCTAssertEqual(stats.importantDayCount, 3)
        XCTAssertEqual(stats.archiveOriginDate, date(2024, 5, 1))
    }

    func testComputeArchiveStatsDaysTogetherFromAdoptionDay() {
        let stats = TimelineLogic.computeArchiveStats(
            photoCount: 0, events: [], photos: [],
            adoptionDay: date(2026, 1, 1), now: date(2026, 1, 31), calendar: cal)
        XCTAssertEqual(stats.daysTogether, 30)
    }

    func testComputeArchiveStatsDaysTogetherFallsBackToEarliestDate() {
        let photo = TimelinePhoto(id: UUID(), petID: nil, takenAt: date(2026, 1, 1),
                                  note: "", uri: "", thumbnailPath: "")
        let stats = TimelineLogic.computeArchiveStats(
            photoCount: 1, events: [], photos: [photo],
            adoptionDay: nil, now: date(2026, 1, 11), calendar: cal)
        XCTAssertEqual(stats.daysTogether, 10)
    }

    func testComputeArchiveStatsArchiveOriginNilForEmptyInput() {
        let stats = TimelineLogic.computeArchiveStats(
            photoCount: 0, events: [], photos: [],
            adoptionDay: nil, now: date(2026, 1, 1), calendar: cal)
        XCTAssertNil(stats.archiveOriginDate)
        XCTAssertEqual(stats.daysTogether, 0)
    }

    // MARK: - 生命档案增强：置顶记忆选择（selectPinnedMemory）

    func testSelectPinnedMemoryPrefersPinnedEvents() {
        let pinnedID = UUID()
        let pinnedEvent = TimelinePetEvent(
            id: pinnedID, petID: nil, eventType: "custom",
            eventDate: date(2026, 3, 1), title: "置顶记忆",
            body: "重要的一天", sourceType: "user")
        let userEvent = TimelinePetEvent(
            id: UUID(), petID: nil, eventType: "custom",
            eventDate: date(2026, 5, 1), title: "普通记忆",
            body: "日常记录", sourceType: "user")
        let result = TimelineLogic.selectPinnedMemory(
            events: [pinnedEvent, userEvent],
            pinnedEventIDs: [pinnedID], calendar: cal)
        XCTAssertEqual(result?.entryID, pinnedID.uuidString)
        XCTAssertEqual(result?.title, "置顶记忆")
    }

    func testSelectPinnedMemoryFallsBackToUserTextMemory() {
        let userEvent = TimelinePetEvent(
            id: UUID(), petID: nil, eventType: "custom",
            eventDate: date(2026, 5, 1), title: "用户记忆",
            body: "正文", sourceType: "user")
        let result = TimelineLogic.selectPinnedMemory(
            events: [userEvent], pinnedEventIDs: [], calendar: cal)
        XCTAssertEqual(result?.entryID, userEvent.id.uuidString)
        XCTAssertEqual(result?.sourceType, "user")
    }

    func testSelectPinnedMemoryReturnsNilForNoCandidates() {
        let systemEvent = TimelinePetEvent(
            id: UUID(), petID: nil, eventType: "birthday",
            eventDate: date(2026, 1, 1), title: "生日")
        let result = TimelineLogic.selectPinnedMemory(
            events: [systemEvent], pinnedEventIDs: [], calendar: cal)
        XCTAssertNil(result)
    }

    func testSelectPinnedMemoryPicksMostRecentWhenMultipleCandidates() {
        let older = TimelinePetEvent(
            id: UUID(), petID: nil, eventType: "custom",
            eventDate: date(2025, 1, 1), title: "旧的",
            body: "旧记忆", sourceType: "user")
        let newer = TimelinePetEvent(
            id: UUID(), petID: nil, eventType: "custom",
            eventDate: date(2026, 1, 1), title: "新的",
            body: "新记忆", sourceType: "user")
        let result = TimelineLogic.selectPinnedMemory(
            events: [older, newer], pinnedEventIDs: [], calendar: cal)
        XCTAssertEqual(result?.title, "新的")
    }

    // MARK: - 生命档案增强：日期范围章节分组（buildDateRangeChapters）

    func testBuildDateRangeChaptersGroupsByYear() {
        let entries = [
            TimelineEntry(id: "a", type: .photoNote, date: date(2024, 3, 1),
                          title: "A", subtitle: "", petID: nil, petName: "",
                          photoID: nil, photoURI: "", thumbnailPath: ""),
            TimelineEntry(id: "b", type: .photoNote, date: date(2025, 6, 1),
                          title: "B", subtitle: "", petID: nil, petName: "",
                          photoID: nil, photoURI: "", thumbnailPath: ""),
        ]
        let chapters = TimelineLogic.buildDateRangeChapters(
            entries: entries, now: date(2026, 1, 1), calendar: cal)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].entries.count, 1)
        XCTAssertEqual(chapters[1].entries.count, 1)
        XCTAssertTrue(chapters[1].isLastChapter)
        XCTAssertFalse(chapters[0].isLastChapter)
    }

    func testBuildDateRangeChaptersUsesCustomName() {
        let entry = TimelineEntry(id: "a", type: .photoNote, date: date(2024, 3, 1),
                                  title: "A", subtitle: "", petID: nil, petName: "",
                                  photoID: nil, photoURI: "", thumbnailPath: "")
        let chapters = TimelineLogic.buildDateRangeChapters(
            entries: [entry], customNames: [2024: "我们的第一年"],
            now: date(2026, 1, 1), calendar: cal)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].title, "我们的第一年")
    }

    func testBuildDateRangeChaptersAutoDerivesTitleWhenNoCustomName() {
        let entry = TimelineEntry(id: "a", type: .photoNote, date: date(2024, 3, 1),
                                  title: "A", subtitle: "", petID: nil, petName: "",
                                  photoID: nil, photoURI: "", thumbnailPath: "")
        let chapters = TimelineLogic.buildDateRangeChapters(
            entries: [entry], now: date(2026, 1, 1), calendar: cal)
        XCTAssertEqual(chapters.count, 1)
        // 自动推导标题不应为空
        XCTAssertFalse(chapters[0].title.isEmpty)
    }

    func testBuildDateRangeChaptersEmptyEntriesReturnsEmpty() {
        let chapters = TimelineLogic.buildDateRangeChapters(
            entries: [], now: date(2026, 1, 1), calendar: cal)
        XCTAssertTrue(chapters.isEmpty)
    }

    // MARK: - 生命档案增强：年度回看（buildYearlyRecap）

    func testBuildYearlyRecapFiltersByYear() {
        let entries = [
            TimelineEntry(id: "a", type: .photoNote, date: date(2025, 3, 1),
                          title: "2025", subtitle: "", petID: nil, petName: "",
                          photoID: nil, photoURI: "", thumbnailPath: ""),
            TimelineEntry(id: "b", type: .photoNote, date: date(2026, 6, 1),
                          title: "2026", subtitle: "", petID: nil, petName: "",
                          photoID: nil, photoURI: "", thumbnailPath: ""),
        ]
        let recap = TimelineLogic.buildYearlyRecap(entries: entries, year: 2026, calendar: cal)
        XCTAssertEqual(recap.year, 2026)
        XCTAssertEqual(recap.totalCount, 1)
        XCTAssertEqual(recap.highlights.first?.title, "2026")
    }

    func testBuildYearlyRecapMonthlyPicksOnePerMonth() {
        let entries = (1...3).map { m in
            TimelineEntry(id: "m\(m)", type: .photoNote, date: date(2026, m, 15),
                          title: "月\(m)", subtitle: "", petID: nil, petName: "",
                          photoID: nil, photoURI: "", thumbnailPath: "")
        }
        let recap = TimelineLogic.buildYearlyRecap(entries: entries, year: 2026, calendar: cal)
        XCTAssertEqual(recap.monthlyPicks.count, 3)
        XCTAssertEqual(recap.monthlyPicks[1]?.title, "月1")
        XCTAssertEqual(recap.monthlyPicks[2]?.title, "月2")
        XCTAssertEqual(recap.monthlyPicks[3]?.title, "月3")
    }

    func testBuildYearlyRecapEmptyYearReturnsZeroCounts() {
        let recap = TimelineLogic.buildYearlyRecap(entries: [], year: 2026, calendar: cal)
        XCTAssertEqual(recap.totalCount, 0)
        XCTAssertTrue(recap.monthlyPicks.isEmpty)
    }

    // MARK: - 生命档案增强：删除/取消关联边界

    func testImportantDayCountAfterRemovalDecrements() {
        let removedID = UUID()
        let events = [
            TimelinePetEvent(id: removedID, petID: nil, eventType: "custom",
                            eventDate: date(2026, 1, 1), title: "将删除",
                            body: "", sourceType: "user"),
            TimelinePetEvent(id: UUID(), petID: nil, eventType: "birthday",
                            eventDate: date(2026, 5, 1), title: "生日"),
        ]
        let count = TimelineLogic.importantDayCountAfterRemoval(
            events: events, removedEventID: removedID)
        XCTAssertEqual(count, 1)
    }

    func testImportantDayCountAfterRemovalWithNonExistentIDUnchanged() {
        let events = [
            TimelinePetEvent(id: UUID(), petID: nil, eventType: "birthday",
                            eventDate: date(2026, 5, 1), title: "生日"),
            TimelinePetEvent(id: UUID(), petID: nil, eventType: "adoption",
                            eventDate: date(2026, 6, 1), title: "领养"),
        ]
        let count = TimelineLogic.importantDayCountAfterRemoval(
            events: events, removedEventID: UUID())
        XCTAssertEqual(count, 2)
    }
}
