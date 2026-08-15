import XCTest
import MiLensKit
@testable import MiLens

final class ArchiveSharePaginationTests: XCTestCase {
    private let calendar = PetDateCalendar.gregorian

    func testTimelinePaginationKeepsEveryEntryAndUsesFixedCoverBudget() {
        let entries = (0..<7).map { index in
            timelineEntry(index: index, type: .photoNote)
        }
        let month = TimelineMonth(
            year: 2026,
            month: 5,
            yearMonth: "2026-05",
            isYearStart: true,
            entries: entries
        )

        let pages = ArchiveSharePagination.timelinePages(from: [month])

        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(pages[0].isCover)
        XCTAssertFalse(pages[1].isCover)
        XCTAssertEqual(pages[0].months.flatMap(\.entries).count, 2)
        XCTAssertEqual(pages[1].months.flatMap(\.entries).count, 5)
        XCTAssertEqual(
            pages.flatMap(\.months).flatMap(\.entries).map(\.id),
            entries.map(\.id)
        )
    }

    func testTimelinePaginationRepeatsMonthHeaderWhenMonthContinuesOnNextPage() {
        let month = TimelineMonth(
            year: 2026,
            month: 6,
            yearMonth: "2026-06",
            isYearStart: true,
            entries: (0..<4).map { timelineEntry(index: $0, type: .photoNote) }
        )

        let pages = ArchiveSharePagination.timelinePages(from: [month])

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].months.first?.yearMonth, "2026-06")
        XCTAssertEqual(pages[1].months.first?.yearMonth, "2026-06")
    }

    func testTimelinePaginationReturnsEmptyForNoEntries() {
        let emptyMonth = TimelineMonth(
            year: 2026,
            month: 7,
            yearMonth: "2026-07",
            isYearStart: true,
            entries: []
        )

        XCTAssertTrue(ArchiveSharePagination.timelinePages(from: [emptyMonth]).isEmpty)
    }

    func testAnnualPaginationUsesTwoMonthsOnCoverAndThreeOnContentPages() {
        let photos = (1...8).map { month in
            RecapPhoto(
                takenAt: date(year: 2026, month: month),
                qualityScore: 0.8
            )
        }
        let recap = MemoryRecapLogic.yearlyRecap(photos: photos, year: 2026)

        let pages = ArchiveSharePagination.annualPages(from: recap.months)

        XCTAssertEqual(pages.map { $0.months.count }, [2, 3, 3])
        XCTAssertEqual(pages.map(\.isCover), [true, false, false])
        XCTAssertEqual(pages.flatMap(\.months).map(\.month), Array(1...8))
    }

    func testPreferredImagePathUsesThumbnailThenOriginal() {
        XCTAssertEqual(
            ArchiveSharePagination.preferredImagePath(
                thumbnailPath: " /cache/thumb.jpg ",
                photoURI: "/photos/original.jpg"
            ),
            "/cache/thumb.jpg"
        )
        XCTAssertEqual(
            ArchiveSharePagination.preferredImagePath(
                thumbnailPath: " ",
                photoURI: " /photos/original.jpg "
            ),
            "/photos/original.jpg"
        )
        XCTAssertNil(ArchiveSharePagination.preferredImagePath(
            thumbnailPath: "",
            photoURI: ""
        ))
    }

    private func timelineEntry(index: Int, type: TimelineEntryType) -> TimelineEntry {
        TimelineEntry(
            id: "entry_\(index)",
            type: type,
            date: date(year: 2026, month: 5, day: index + 1),
            title: "记录 \(index)",
            subtitle: "说明",
            petID: nil,
            petName: "小满",
            photoID: UUID(),
            photoURI: "/photos/\(index).jpg",
            thumbnailPath: "/cache/\(index).jpg"
        )
    }

    private func date(year: Int, month: Int, day: Int = 15) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)!
    }
}
