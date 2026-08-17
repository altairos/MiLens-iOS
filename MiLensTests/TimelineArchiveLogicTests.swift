//  TimelineArchiveLogicTests —— 生命档案增强纯决策逻辑测试（Life-Archive-Design.md P3.6）。
//  覆盖：档案统计快照 / 置顶记忆选择 / 相处章节分组 / 年度回看 / 删除边界五组纯函数。
//  全部使用固定 UTC Calendar（PetDateCalendar.gregorian），与 AnniversaryTimeMachineLogicTests 同纪律。

import XCTest
@testable import MiLens

final class TimelineArchiveLogicTests: XCTestCase {

    // MARK: - 辅助

    private let cal = PetDateCalendar.gregorian

    private func utcDate(_ year: Int, _ month: Int, _ day: Int,
                         hour: Int = 0, minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day,
                                      hour: hour, minute: minute))!
    }

    private func makeEvent(_ id: UUID = UUID(), type: String = "anniversary",
                           source: String = "system", date: Date,
                           title: String = "事件", body: String = "",
                           relatedPhotoID: UUID? = nil) -> TimelinePetEvent {
        TimelinePetEvent(id: id, petID: nil, eventType: type, eventDate: date,
                         title: title, body: body, sourceType: source,
                         relatedPhotoID: relatedPhotoID)
    }

    private func makePhoto(takenAt: Date?, uri: String = "/documents/MiPhotos/a.jpg") -> TimelinePhoto {
        TimelinePhoto(id: UUID(), petID: nil, takenAt: takenAt, note: "",
                      uri: uri, thumbnailPath: "")
    }

    private func makeEntry(_ id: String, date: Date?,
                           type: TimelineEntryType = .photoNote) -> TimelineEntry {
        TimelineEntry(id: id, type: type, date: date, title: id, subtitle: "",
                      petID: nil, petName: "", photoID: nil,
                      photoURI: "", thumbnailPath: "")
    }

    // MARK: - computeArchiveStats 档案统计

    /// photoCount 为显式入参透传（非 photos.count），memoryCount = 事件数。
    func testArchiveStatsCountsPassThrough() {
        let stats = TimelineLogic.computeArchiveStats(
            photoCount: 12,
            events: [makeEvent(date: utcDate(2025, 3, 1)),
                     makeEvent(date: utcDate(2025, 5, 2))],
            photos: [makePhoto(takenAt: utcDate(2025, 4, 1))],
            adoptionDay: nil, now: utcDate(2026, 8, 17), calendar: cal)

        XCTAssertEqual(stats.photoCount, 12)
        XCTAssertEqual(stats.memoryCount, 2)
    }

    /// 作品计数：仅 uri 含 /Edits/ 的照片计为作品。
    func testArchiveStatsWorkCountFiltersEditURIs() {
        let photos = [
            makePhoto(takenAt: utcDate(2025, 4, 1), uri: "/documents/MiPhotos/a.jpg"),
            makePhoto(takenAt: utcDate(2025, 4, 2), uri: "/documents/Edits/b.png"),
            makePhoto(takenAt: utcDate(2025, 4, 3), uri: "/documents/Edits/c.png"),
            makePhoto(takenAt: utcDate(2025, 4, 4), uri: "/documents/Edits-mock/d.png")
        ]
        let stats = TimelineLogic.computeArchiveStats(
            photoCount: 4, events: [], photos: photos,
            adoptionDay: nil, now: utcDate(2026, 8, 17), calendar: cal)

        XCTAssertEqual(stats.workCount, 2, "仅路径含 /Edits/ 的计数（前缀相近不算）")
    }

    /// 重要日子：user 事件 + birthday + adoption 计入，system 其他类型不计。
    func testArchiveStatsImportantDayCountFiltersBySourceAndType() {
        let events = [
            makeEvent(type: "anniversary", source: "system", date: utcDate(2025, 1, 1)), // 不计
            makeEvent(type: "anniversary", source: "user", date: utcDate(2025, 2, 1)),   // 计
            makeEvent(type: "birthday", source: "system", date: utcDate(2025, 3, 1)),    // 计
            makeEvent(type: "adoption", source: "system", date: utcDate(2025, 4, 1)),    // 计
            makeEvent(type: "vaccination", source: "user", date: utcDate(2025, 5, 1))    // 计（user 优先）
        ]
        let stats = TimelineLogic.computeArchiveStats(
            photoCount: 0, events: events, photos: [],
            adoptionDay: nil, now: utcDate(2026, 8, 17), calendar: cal)

        XCTAssertEqual(stats.importantDayCount, 4)
    }

    /// 档案起点：事件与照片日期取最早。
    func testArchiveStatsOriginDateIsEarliestAcrossEventsAndPhotos() {
        let stats = TimelineLogic.computeArchiveStats(
            photoCount: 1,
            events: [makeEvent(date: utcDate(2025, 6, 1))],
            photos: [makePhoto(takenAt: utcDate(2024, 12, 31)),
                     makePhoto(takenAt: nil)],
            adoptionDay: nil, now: utcDate(2026, 8, 17), calendar: cal)

        XCTAssertEqual(stats.archiveOriginDate, utcDate(2024, 12, 31))
    }

    /// 相伴天数：adoptionDay 优先于 archiveOriginDate。
    func testArchiveStatsDaysTogetherPrefersAdoptionDay() {
        let stats = TimelineLogic.computeArchiveStats(
            photoCount: 1,
            events: [makeEvent(date: utcDate(2024, 1, 1))],
            photos: [makePhoto(takenAt: utcDate(2024, 2, 1))],
            adoptionDay: utcDate(2026, 1, 1),
            now: utcDate(2026, 1, 31), calendar: cal)

        XCTAssertEqual(stats.daysTogether, 30, "领养日 2026-01-01 至 2026-01-31 为 30 天，不取更早的照片日期")
    }

    /// 无领养日回退档案起点；两者皆无时为 0。
    func testArchiveStatsDaysTogetherFallsBackToOriginThenZero() {
        let withOrigin = TimelineLogic.computeArchiveStats(
            photoCount: 1, events: [], photos: [makePhoto(takenAt: utcDate(2026, 1, 1))],
            adoptionDay: nil, now: utcDate(2026, 1, 11), calendar: cal)
        XCTAssertEqual(withOrigin.daysTogether, 10, "无领养日时回退最早照片日期")

        let empty = TimelineLogic.computeArchiveStats(
            photoCount: 0, events: [], photos: [],
            adoptionDay: nil, now: utcDate(2026, 1, 11), calendar: cal)
        XCTAssertEqual(empty.daysTogether, 0, "无任何记录时相伴天数为 0")
    }

    /// 领养日在未来（数据异常）：天数钳 0 不出负数。
    func testArchiveStatsDaysTogetherClampsFutureAdoptionToZero() {
        let stats = TimelineLogic.computeArchiveStats(
            photoCount: 0, events: [], photos: [],
            adoptionDay: utcDate(2026, 12, 1),
            now: utcDate(2026, 8, 17), calendar: cal)

        XCTAssertEqual(stats.daysTogether, 0)
    }

    // MARK: - selectPinnedMemory 置顶记忆

    /// pinned 事件优先，多个 pinned 取最近日期。
    func testPinnedMemoryPrefersPinnedEventsAndLatestDate() {
        let older = UUID(), newer = UUID()
        let events = [
            makeEvent(older, type: "anniversary", source: "user",
                      date: utcDate(2025, 1, 1), title: "旧置顶", body: "旧正文"),
            makeEvent(newer, type: "anniversary", source: "user",
                      date: utcDate(2026, 1, 1), title: "新置顶", body: "新正文")
        ]
        let result = TimelineLogic.selectPinnedMemory(
            events: events, pinnedEventIDs: [older, newer], calendar: cal)

        XCTAssertEqual(result?.entryID, newer.uuidString, "多个置顶取最近日期")
        XCTAssertEqual(result?.title, "新置顶")
    }

    /// 无 pinned 时回退用户文本记忆（sourceType=user 且 body 非空）。
    func testPinnedMemoryFallsBackToUserTextMemories() {
        let events = [
            makeEvent(type: "anniversary", source: "user",
                      date: utcDate(2025, 1, 1), title: "有正文", body: "正文内容"),
            makeEvent(type: "anniversary", source: "user",
                      date: utcDate(2026, 1, 1), title: "空正文", body: ""),
            makeEvent(type: "birthday", source: "system",
                      date: utcDate(2026, 6, 1), title: "系统事件", body: "系统正文")
        ]
        let result = TimelineLogic.selectPinnedMemory(events: events, pinnedEventIDs: [], calendar: cal)

        XCTAssertEqual(result?.title, "有正文", "仅 sourceType=user 且 body 非空的候选（取最近的可候选者）")
    }

    /// 无任何候选返回 nil。
    func testPinnedMemoryReturnsNilWithoutCandidates() {
        let events = [
            makeEvent(type: "birthday", source: "system", date: utcDate(2026, 1, 1)),
            makeEvent(type: "anniversary", source: "user", date: utcDate(2026, 2, 1), body: "")
        ]
        XCTAssertNil(TimelineLogic.selectPinnedMemory(
            events: events, pinnedEventIDs: [], calendar: cal))
        XCTAssertNil(TimelineLogic.selectPinnedMemory(
            events: [], pinnedEventIDs: [UUID()], calendar: cal))
    }

    /// 字段映射：entryID/photoID/sourceType 透传，title 空时用兜底文案。
    func testPinnedMemoryMapsFieldsAndFallsBackTitle() {
        let id = UUID(), photoID = UUID()
        let events = [
            makeEvent(id, type: "anniversary", source: "user",
                      date: utcDate(2026, 3, 1), title: "", body: "正文",
                      relatedPhotoID: photoID)
        ]
        let result = TimelineLogic.selectPinnedMemory(
            events: events, pinnedEventIDs: [id], calendar: cal)

        XCTAssertEqual(result?.entryID, id.uuidString)
        XCTAssertEqual(result?.bodyText, "正文")
        XCTAssertEqual(result?.date, utcDate(2026, 3, 1))
        XCTAssertEqual(result?.photoID, photoID)
        XCTAssertEqual(result?.sourceType, "user")
        XCTAssertFalse(result?.title.isEmpty ?? true, "title 空时使用本地化兜底文案（非空）")
    }

    // MARK: - buildDateRangeChapters 相处章节

    /// 按年分组、时间正序、末章标记、自定义名优先。
    func testDateRangeChaptersGroupByYearAscendingWithLastFlag() {
        let entries = [
            makeEntry("e2026", date: utcDate(2026, 5, 1)),
            makeEntry("e2024a", date: utcDate(2024, 1, 10)),
            makeEntry("e2024b", date: utcDate(2024, 9, 20)),
            makeEntry("e2025", date: utcDate(2025, 7, 1))
        ]
        let chapters = TimelineLogic.buildDateRangeChapters(
            entries: entries, customNames: [2025: "自定义章名"],
            now: utcDate(2026, 8, 17), calendar: cal)

        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters.map { .entries.count }, [2, 1, 1], "章节按年正序排列")
        XCTAssertEqual(chapters.map { .isLastChapter }, [false, false, true])

        XCTAssertEqual(chapters[0].startDate, utcDate(2024, 1, 10))
        XCTAssertEqual(chapters[0].endDate, utcDate(2024, 9, 20))
        XCTAssertEqual(chapters[1].title, "自定义章名", "自定义名优先于公式推导")
        XCTAssertFalse(chapters[0].title.isEmpty, "未命名章节用公式推导标题（非空）")
    }

    /// 无日期条目被跳过，不参与分组。
    func testDateRangeChaptersSkipEntriesWithoutDate() {
        let entries = [
            makeEntry("dated", date: utcDate(2026, 1, 1)),
            makeEntry("undated", date: nil)
        ]
        let chapters = TimelineLogic.buildDateRangeChapters(
            entries: entries, now: utcDate(2026, 8, 17), calendar: cal)

        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].entries.map { .id }, ["dated"])
    }

    /// 空输入返回空章节列表。
    func testDateRangeChaptersEmptyInput() {
        let chapters = TimelineLogic.buildDateRangeChapters(
            entries: [], now: utcDate(2026, 8, 17), calendar: cal)
        XCTAssertTrue(chapters.isEmpty)
    }

    // MARK: - buildYearlyRecap 年度回看

    /// 过滤目标年份并统计总数。
    func testYearlyRecapFiltersByYearAndCountsTotal() {
        let entries = [
            makeEntry("y2025a", date: utcDate(2025, 2, 1)),
            makeEntry("y2025b", date: utcDate(2025, 8, 15)),
            makeEntry("y2026", date: utcDate(2026, 1, 1)),
            makeEntry("nodate", date: nil)
        ]
        let recap = TimelineLogic.buildYearlyRecap(entries: entries, year: 2025, calendar: cal)

        XCTAssertEqual(recap.year, 2025)
        XCTAssertEqual(recap.totalCount, 2, "仅统计目标年份条目")
    }

    /// 月度代表取每月第一条（输入已按日期排序），精选按日期升序。
    func testYearlyRecapMonthlyPicksFirstPerMonthAndSortedHighlights() {
        let entries = [
            makeEntry("jan1", date: utcDate(2025, 1, 2)),
            makeEntry("jan2", date: utcDate(2025, 1, 20)),
            makeEntry("mar1", date: utcDate(2025, 3, 5)),
            makeEntry("mar2", date: utcDate(2025, 3, 18))
        ]
        let recap = TimelineLogic.buildYearlyRecap(entries: entries, year: 2025, calendar: cal)

        XCTAssertEqual(recap.monthlyPicks[1]?.id, "jan1", "每月取第一条")
        XCTAssertEqual(recap.monthlyPicks[3]?.id, "mar1")
        XCTAssertEqual(recap.highlights.map { .id }, ["jan1", "mar1"], "精选按日期升序、每月至多一条")
    }

    /// 无该年记录返回空快照。
    func testYearlyRecapEmptyForYearWithoutEntries() {
        let recap = TimelineLogic.buildYearlyRecap(
            entries: [makeEntry("only2025", date: utcDate(2025, 6, 1))],
            year: 2024, calendar: cal)

        XCTAssertEqual(recap.totalCount, 0)
        XCTAssertTrue(recap.highlights.isEmpty)
        XCTAssertTrue(recap.monthlyPicks.isEmpty)
    }

    // MARK: - importantDayCountAfterRemoval 删除边界

    /// 删除置顶/用户事件后剩余重要日子数；移除不存在的事件等于原计数。
    func testImportantDayCountAfterRemoval() {
        let keep = UUID(), removed = UUID()
        let events = [
            makeEvent(keep, type: "user", source: "user", date: utcDate(2026, 1, 1)),
            makeEvent(removed, type: "anniversary", source: "user", date: utcDate(2026, 2, 1)),
            makeEvent(type: "anniversary", source: "system", date: utcDate(2026, 3, 1))
        ]
        XCTAssertEqual(TimelineLogic.importantDayCountAfterRemoval(
            events: events, removedEventID: removed), 1, "删除 user 事件后仅剩 1 个")
        XCTAssertEqual(TimelineLogic.importantDayCountAfterRemoval(
            events: events, removedEventID: UUID()), 2, "移除不存在的事件不影响计数")
    }
}