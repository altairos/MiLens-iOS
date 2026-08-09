import XCTest
@testable import MiLens

final class CommercialRulesTests: XCTestCase {
    func testPetLimits() {
        XCTAssertEqual(CommercialRules.petLimit(isPro: false), 1)
        XCTAssertEqual(CommercialRules.petLimit(isPro: true), 20)
    }

    func testFreeTimelineKeepsOnlyLastYearAndReportsLockedHistory() {
        let now = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 UTC
        let recent = TimelineEntry(id: "recent", type: .photoNote, date: now.addingTimeInterval(-30 * 86_400), title: "", subtitle: "", petID: nil, petName: "", photoID: nil, photoURI: "", thumbnailPath: "")
        let old = TimelineEntry(id: "old", type: .photoNote, date: now.addingTimeInterval(-400 * 86_400), title: "", subtitle: "", petID: nil, petName: "", photoID: nil, photoURI: "", thumbnailPath: "")

        XCTAssertEqual(TimelineAccessLogic.visibleEntries([old, recent], now: now, isPro: false).map(\.id), ["recent"])
        XCTAssertTrue(TimelineAccessLogic.hasLockedHistory([old, recent], now: now, isPro: false))
        XCTAssertEqual(TimelineAccessLogic.visibleEntries([old, recent], now: now, isPro: true).count, 2)
    }

    func testTimelinePreviewShowsAllHistoryForFourteenDays() {
        let now = Date(timeIntervalSince1970: 1_735_689_600)
        let firstAccess = now.addingTimeInterval(-13 * 86_400)
        let old = TimelineEntry(id: "old", type: .photoNote, date: now.addingTimeInterval(-400 * 86_400), title: "", subtitle: "", petID: nil, petName: "", photoID: nil, photoURI: "", thumbnailPath: "")

        XCTAssertTrue(TimelineAccessLogic.isInFullHistoryPreview(now: now, firstAccessDate: firstAccess))
        XCTAssertEqual(TimelineAccessLogic.visibleEntries([old], now: now, isPro: false, firstAccessDate: firstAccess).count, 1)
        XCTAssertEqual(TimelineAccessLogic.previewDaysRemaining(now: now, firstAccessDate: firstAccess), 1)
    }

    func testTimelinePreviewExpiresOnDayFourteen() {
        let now = Date(timeIntervalSince1970: 1_735_689_600)
        let firstAccess = now.addingTimeInterval(-14 * 86_400)
        XCTAssertFalse(TimelineAccessLogic.isInFullHistoryPreview(now: now, firstAccessDate: firstAccess))
        XCTAssertEqual(TimelineAccessLogic.previewDaysRemaining(now: now, firstAccessDate: firstAccess), 0)
    }
}
