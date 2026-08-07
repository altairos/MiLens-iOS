import XCTest
@testable import MiLens

/// ScanControlMath 测试（对应源端 ScanControlMath.test.ets）。
/// 覆盖常量、日期过滤、阈值解析、恢复断点、缩略图路径。
final class ScanControlMathTests: XCTestCase {

    // MARK: - 常量

    func testFallbackVisualMatchThresholdIsPoint85() {
        XCTAssertEqual(ScanControlMath.fallbackVisualMatchThreshold, 0.85, accuracy: 1e-9)
    }

    func testStrictMatchThresholdIsPoint82() {
        XCTAssertEqual(ScanControlMath.strictMatchThreshold, 0.82, accuracy: 1e-9)
    }

    // MARK: - shouldSkipByDateAdded

    func testShouldSkipReturnsFalseWhenAfterTimestampMsLEZero() {
        XCTAssertFalse(ScanControlMath.shouldSkipByDateAdded(dateAdded: 1000, afterTimestampMs: 0))
        XCTAssertFalse(ScanControlMath.shouldSkipByDateAdded(dateAdded: 1000, afterTimestampMs: -1))
    }

    func testShouldSkipReturnsFalseWhenDateAddedLEZero() {
        XCTAssertFalse(ScanControlMath.shouldSkipByDateAdded(dateAdded: 0, afterTimestampMs: 1_000_000))
        XCTAssertFalse(ScanControlMath.shouldSkipByDateAdded(dateAdded: -1, afterTimestampMs: 1_000_000))
    }

    func testShouldSkipReturnsTrueWhenDateAddedOlderThanThreshold() {
        // afterTimestampMs = 2_000_000 → afterTimestampSec = 2000; dateAdded = 1000 < 2000 → skip
        XCTAssertTrue(ScanControlMath.shouldSkipByDateAdded(dateAdded: 1000, afterTimestampMs: 2_000_000))
    }

    func testShouldSkipReturnsFalseWhenDateAddedGEThreshold() {
        XCTAssertFalse(ScanControlMath.shouldSkipByDateAdded(dateAdded: 2000, afterTimestampMs: 2_000_000))
        XCTAssertFalse(ScanControlMath.shouldSkipByDateAdded(dateAdded: 3000, afterTimestampMs: 2_000_000))
    }

    func testShouldSkipHandlesMillisecondToSecondTruncation() {
        // 2_999_999 ms → floor(2999999/1000) = 2999 sec
        XCTAssertTrue(ScanControlMath.shouldSkipByDateAdded(dateAdded: 2998, afterTimestampMs: 2_999_999))
        XCTAssertFalse(ScanControlMath.shouldSkipByDateAdded(dateAdded: 2999, afterTimestampMs: 2_999_999))
        XCTAssertFalse(ScanControlMath.shouldSkipByDateAdded(dateAdded: 3000, afterTimestampMs: 2_999_999))
    }

    // MARK: - resolveMatchThreshold

    func testResolveMatchThresholdReturnsFallbackWhenMatchRequiredTrue() {
        XCTAssertEqual(
            ScanControlMath.resolveMatchThreshold(matchRequired: true),
            ScanControlMath.fallbackVisualMatchThreshold,
            accuracy: 1e-9
        )
    }

    func testResolveMatchThresholdReturnsStrictWhenMatchRequiredFalse() {
        XCTAssertEqual(
            ScanControlMath.resolveMatchThreshold(matchRequired: false),
            ScanControlMath.strictMatchThreshold,
            accuracy: 1e-9
        )
    }

    // MARK: - resolveEmbeddingKind

    func testResolveEmbeddingKindReturnsFallbackWhenMatchRequiredTrue() {
        XCTAssertEqual(ScanControlMath.resolveEmbeddingKind(matchRequired: true), "fallback")
    }

    func testResolveEmbeddingKindReturnsClipWhenMatchRequiredFalse() {
        XCTAssertEqual(ScanControlMath.resolveEmbeddingKind(matchRequired: false), "clip")
    }

    // MARK: - updateResumePoint

    func testUpdateResumePointReturnsTrueWhenAlreadyPastTrue() {
        XCTAssertTrue(ScanControlMath.updateResumePoint(assetUri: "any-uri", lastScannedUri: "break-uri", alreadyPast: true))
        XCTAssertTrue(ScanControlMath.updateResumePoint(assetUri: "", lastScannedUri: "", alreadyPast: true))
    }

    func testUpdateResumePointReturnsTrueWhenCurrentAssetIsBreakPoint() {
        XCTAssertTrue(ScanControlMath.updateResumePoint(assetUri: "break-uri", lastScannedUri: "break-uri", alreadyPast: false))
    }

    func testUpdateResumePointReturnsFalseWhenNotYetAtBreakPoint() {
        XCTAssertFalse(ScanControlMath.updateResumePoint(assetUri: "other-uri", lastScannedUri: "break-uri", alreadyPast: false))
        XCTAssertFalse(ScanControlMath.updateResumePoint(assetUri: "", lastScannedUri: "break-uri", alreadyPast: false))
    }

    func testUpdateResumePointReturnsTrueWhenBreakPointIsEmptyString() {
        XCTAssertTrue(ScanControlMath.updateResumePoint(assetUri: "", lastScannedUri: "", alreadyPast: false))
        XCTAssertFalse(ScanControlMath.updateResumePoint(assetUri: "some-uri", lastScannedUri: "", alreadyPast: false))
    }

    // MARK: - resolveThumbnailPath

    func testResolveThumbnailPathReturnsSandboxURIAsIs() {
        let uri = "file://data/.../MiPhotos/abc.jpg"
        XCTAssertEqual(ScanControlMath.resolveThumbnailPath(uri), uri)
    }

    func testResolveThumbnailPathReturnsEmptyForEmptyInput() {
        XCTAssertEqual(ScanControlMath.resolveThumbnailPath(""), "")
    }
}
