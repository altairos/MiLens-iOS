import XCTest
@testable import MiLens

final class CommercialRulesTests: XCTestCase {
    func testPetLimits() {
        XCTAssertEqual(CommercialRules.petLimit(isPro: false), 1)
        XCTAssertEqual(CommercialRules.petLimit(isPro: true), 20)
    }

    // MARK: - ADR-0010 照片配额

    func testPhotoLimits() {
        XCTAssertEqual(CommercialRules.photoLimit(isPro: false), 50)
        XCTAssertEqual(CommercialRules.photoLimit(isPro: true), Int.max)
    }

    func testAllowedImportCountFreeUserUnderLimit() {
        // 已 30 张，请求 15 张，免费剩余 20 → 允许 15
        XCTAssertEqual(CommercialRules.allowedImportCount(currentCount: 30, requestCount: 15, isPro: false), 15)
    }

    func testAllowedImportCountFreeUserAtLimit() {
        // 已 50 张（满），请求 10 张 → 允许 0
        XCTAssertEqual(CommercialRules.allowedImportCount(currentCount: 50, requestCount: 10, isPro: false), 0)
    }

    func testAllowedImportCountFreeUserOverLimit() {
        // 已 45 张，请求 20 张，剩余 5 → 允许 5（拦截 15）
        XCTAssertEqual(CommercialRules.allowedImportCount(currentCount: 45, requestCount: 20, isPro: false), 5)
    }

    func testAllowedImportCountProUserUnlimited() {
        // Pro 不限：请求多少允许多少
        XCTAssertEqual(CommercialRules.allowedImportCount(currentCount: 999, requestCount: 100, isPro: true), 100)
    }

    func testAllowedImportCountEdgeCases() {
        // 空 App：已 0 张，请求 50 → 允许 50（刚好上限）
        XCTAssertEqual(CommercialRules.allowedImportCount(currentCount: 0, requestCount: 50, isPro: false), 50)
        // 已 0 张，请求 51 → 允许 50（拦截 1）
        XCTAssertEqual(CommercialRules.allowedImportCount(currentCount: 0, requestCount: 51, isPro: false), 50)
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
