import XCTest
@testable import MiLens

/// TimelineChapterLogic 测试（audit-6 P1-4：从 TimelineView 下沉的章节/年份筛选决策）。
/// 覆盖年份提取/过滤/分组/未筛选回退/相处年数推导（含作用域修复）/筛选标题回退。
final class TimelineChapterLogicTests: XCTestCase {

    private func month(_ y: Int, _ m: Int) -> TimelineMonth {
        TimelineMonth(
            year: y, month: m,
            yearMonth: String(format: "%04d-%02d", y, m),
            isYearStart: false, entries: []
        )
    }

    // MARK: - availableYears

    func testAvailableYearsDeduplicatesAndSortsAscending() {
        let months = [month(2025, 3), month(2024, 1), month(2024, 6), month(2025, 3)]
        XCTAssertEqual(TimelineChapterLogic.availableYears(months), [2024, 2025])
    }

    func testAvailableYearsEmptyInput() {
        XCTAssertTrue(TimelineChapterLogic.availableYears([]).isEmpty)
    }

    // MARK: - filteredByYear

    func testFilteredByYearNilSelectionReturnsAll() {
        let months = [month(2024, 1), month(2025, 3)]
        XCTAssertEqual(TimelineChapterLogic.filteredByYear(months, selectedYear: nil), months)
    }

    func testFilteredByYearKeepsOnlySelectedYear() {
        let months = [month(2024, 1), month(2024, 6), month(2025, 3)]
        let filtered = TimelineChapterLogic.filteredByYear(months, selectedYear: 2024)
        XCTAssertEqual(filtered.map { $0.yearMonth }, ["2024-01", "2024-06"])
    }

    // MARK: - groupByYear

    func testGroupByYearGroupsAscendingAndKeepsInputOrderInsideGroup() {
        let months = [month(2025, 3), month(2024, 6), month(2024, 1)]
        let groups = TimelineChapterLogic.groupByYear(months)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].year, 2024)
        XCTAssertEqual(groups[0].months.map { $0.yearMonth }, ["2024-06", "2024-01"])
        XCTAssertEqual(groups[1].year, 2025)
        XCTAssertEqual(groups[1].months.map { $0.yearMonth }, ["2025-03"])
    }

    // MARK: - effectiveSelectedYear

    func testEffectiveSelectedYearKeepsExplicitSelection() {
        XCTAssertEqual(
            TimelineChapterLogic.effectiveSelectedYear(selectedYear: 2024, years: [2023, 2024, 2025]),
            2024
        )
    }

    func testEffectiveSelectedYearNilFallsBackToLatest() {
        XCTAssertEqual(
            TimelineChapterLogic.effectiveSelectedYear(selectedYear: nil, years: [2023, 2024, 2025]),
            2025
        )
    }

    func testEffectiveSelectedYearNilWithEmptyYearsStaysNil() {
        XCTAssertNil(TimelineChapterLogic.effectiveSelectedYear(selectedYear: nil, years: []))
    }

    // MARK: - chapterTogetherYears

    func testChapterTogetherYearsCountsFromTimelineStart() {
        XCTAssertEqual(TimelineChapterLogic.chapterTogetherYears(year: 2024, firstYear: 2024), 1)
        XCTAssertEqual(TimelineChapterLogic.chapterTogetherYears(year: 2026, firstYear: 2024), 3)
    }

    /// 回归守护：修复前 View 误传分组内首年，筛选非首年时每章恒为「第1年」。
    func testChapterTogetherYearsIgnoresYearFilterScope() {
        // 时间线 2024-2026；即使筛选只看 2026 章节，相处年数仍按全时间线推导为 3。
        let firstYear = TimelineChapterLogic.availableYears([
            month(2024, 1), month(2025, 5), month(2026, 8)
        ]).first
        XCTAssertEqual(TimelineChapterLogic.chapterTogetherYears(year: 2026, firstYear: firstYear), 3)
    }

    func testChapterTogetherYearsClampsToOneWhenYearBeforeStart() {
        XCTAssertEqual(TimelineChapterLogic.chapterTogetherYears(year: 2023, firstYear: 2024), 1)
    }

    func testChapterTogetherYearsNilFirstYearFallsBackToOne() {
        XCTAssertEqual(TimelineChapterLogic.chapterTogetherYears(year: 2026, firstYear: nil), 1)
    }

    // MARK: - filterTitle

    func testFilterTitleSelectedPetReturnsDisplayName() {
        let id = UUID()
        let title = TimelineChapterLogic.filterTitle(
            selectedPetID: id,
            pets: [(id: UUID(), displayName: "🐱 甲"), (id: id, displayName: "🐶 乙")]
        )
        XCTAssertEqual(title, "🐶 乙")
    }

    func testFilterTitleUnknownPetFallsBackToAllPets() {
        let title = TimelineChapterLogic.filterTitle(
            selectedPetID: UUID(),
            pets: [(id: UUID(), displayName: "🐱 甲")]
        )
        XCTAssertEqual(title, String(localized: "timeline.allPets"))
    }

    func testFilterTitleNilSelectionFallsBackToAllPets() {
        let title = TimelineChapterLogic.filterTitle(
            selectedPetID: nil,
            pets: [(id: UUID(), displayName: "🐱 甲")]
        )
        XCTAssertEqual(title, String(localized: "timeline.allPets"))
    }
}
