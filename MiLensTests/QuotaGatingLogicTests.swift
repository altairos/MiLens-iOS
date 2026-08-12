import XCTest
@testable import MiLens

/// 配额降级门控纯函数测试（ADR-0010 §10.1 扩展）。
/// 覆盖 overLimitCount / lockedPhotoIDs / shouldPromptDowngrade / promptShouldReset 全分支。
final class QuotaGatingLogicTests: XCTestCase {

    // MARK: - overLimitCount

    func testOverLimitCountFreeUserUnderLimit() {
        XCTAssertEqual(QuotaGatingLogic.overLimitCount(photoCount: 30, isPro: false), 0)
    }

    func testOverLimitCountFreeUserAtLimit() {
        XCTAssertEqual(QuotaGatingLogic.overLimitCount(photoCount: 50, isPro: false), 0)
    }

    func testOverLimitCountFreeUserOverLimit() {
        XCTAssertEqual(QuotaGatingLogic.overLimitCount(photoCount: 80, isPro: false), 30)
    }

    func testOverLimitCountProUserAlwaysZero() {
        XCTAssertEqual(QuotaGatingLogic.overLimitCount(photoCount: 0, isPro: true), 0)
        XCTAssertEqual(QuotaGatingLogic.overLimitCount(photoCount: 50, isPro: true), 0)
        XCTAssertEqual(QuotaGatingLogic.overLimitCount(photoCount: 500, isPro: true), 0)
    }

    // MARK: - lockedPhotoIDs

    /// 辅助：构造按 takenAt 倒序的照片列表（模拟 Repository 返回顺序）。
    private func makePhotos(_ count: Int) -> [Photo] {
        let base = Date(timeIntervalSince1970: 1000)
        return (0..<count).map { i in
            // 倒序：index 0 最新（时间最大）
            Photo(uri: "p\(i)", takenAt: base.addingTimeInterval(Double(count - i) * 100))
        }
    }

    func testLockedPhotoIDsFreeUserUnderLimit() {
        let photos = makePhotos(30)
        XCTAssertTrue(QuotaGatingLogic.lockedPhotoIDs(photos: photos, isPro: false).isEmpty)
    }

    func testLockedPhotoIDsFreeUserAtLimit() {
        let photos = makePhotos(50)
        XCTAssertTrue(QuotaGatingLogic.lockedPhotoIDs(photos: photos, isPro: false).isEmpty)
    }

    func testLockedPhotoIDsFreeUserOverLimit() {
        let photos = makePhotos(53)
        let locked = QuotaGatingLogic.lockedPhotoIDs(photos: photos, isPro: false)
        XCTAssertEqual(locked.count, 3)
        // 锁定的应是第 50 张之后的照片（index 50, 51, 52）
        let expectedIDs = Set(photos[50...].map(\.id))
        XCTAssertEqual(locked, expectedIDs)
    }

    func testLockedPhotoIDsProUserAlwaysEmpty() {
        let photos = makePhotos(200)
        XCTAssertTrue(QuotaGatingLogic.lockedPhotoIDs(photos: photos, isPro: true).isEmpty)
    }

    func testLockedPhotoIDsKeepsLatestFifty() {
        let photos = makePhotos(55)
        let locked = QuotaGatingLogic.lockedPhotoIDs(photos: photos, isPro: false)
        // 最新 50 张（index 0..<50）不在锁定集合
        for photo in photos.prefix(50) {
            XCTAssertFalse(locked.contains(photo.id), "最新 50 张不应被锁定")
        }
        // 第 51 张起被锁定
        for photo in photos.dropFirst(50) {
            XCTAssertTrue(locked.contains(photo.id), "超额照片应被锁定")
        }
    }

    // MARK: - shouldPromptDowngrade

    func testShouldPromptWhenDowngradedAndOverLimitAndNotPrompted() {
        XCTAssertTrue(QuotaGatingLogic.shouldPromptDowngrade(
            lastKnownIsPro: true, currentIsPro: false,
            photoCount: 80, promptPending: false))
    }

    func testShouldNotPromptWhenNeverPro() {
        XCTAssertFalse(QuotaGatingLogic.shouldPromptDowngrade(
            lastKnownIsPro: false, currentIsPro: false,
            photoCount: 80, promptPending: false))
    }

    func testShouldNotPromptWhenStillPro() {
        XCTAssertFalse(QuotaGatingLogic.shouldPromptDowngrade(
            lastKnownIsPro: true, currentIsPro: true,
            photoCount: 80, promptPending: false))
    }

    func testShouldNotPromptWhenUnderLimit() {
        XCTAssertFalse(QuotaGatingLogic.shouldPromptDowngrade(
            lastKnownIsPro: true, currentIsPro: false,
            photoCount: 50, promptPending: false))
    }

    func testShouldNotPromptWhenAlreadyPrompted() {
        XCTAssertFalse(QuotaGatingLogic.shouldPromptDowngrade(
            lastKnownIsPro: true, currentIsPro: false,
            photoCount: 80, promptPending: true))
    }

    func testShouldNotPromptAtExactLimit() {
        // 恰好 50 张不超额，不需要提示
        XCTAssertFalse(QuotaGatingLogic.shouldPromptDowngrade(
            lastKnownIsPro: true, currentIsPro: false,
            photoCount: 50, promptPending: false))
    }

    // MARK: - promptShouldReset

    func testPromptShouldResetWhenPro() {
        XCTAssertTrue(QuotaGatingLogic.promptShouldReset(isPro: true))
    }

    func testPromptShouldNotResetWhenFree() {
        XCTAssertFalse(QuotaGatingLogic.promptShouldReset(isPro: false))
    }
}
