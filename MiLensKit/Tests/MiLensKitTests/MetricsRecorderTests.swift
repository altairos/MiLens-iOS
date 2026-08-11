import XCTest
@testable import MiLensKit

//  MetricsRecorder 测试（ADR-0010 §3.4 本地匿名指标）。

final class MetricsRecorderTests: XCTestCase {

    /// 每个测试用独立 UserDefaults suite，避免互相污染。
    private func makeRecorder() -> MetricsRecorder {
        let suiteName = "metrics-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return MetricsRecorder(defaults: defaults)
    }

    func testRecordIncrementsCount() {
        let recorder = makeRecorder()
        XCTAssertEqual(recorder.count(for: .memoryCardPreviewed), 0)
        recorder.record(.memoryCardPreviewed)
        XCTAssertEqual(recorder.count(for: .memoryCardPreviewed), 1)
        recorder.record(.memoryCardPreviewed)
        recorder.record(.memoryCardPreviewed)
        XCTAssertEqual(recorder.count(for: .memoryCardPreviewed), 3)
    }

    func testEventsAreIndependent() {
        let recorder = makeRecorder()
        recorder.record(.exportStarted)
        recorder.record(.exportStarted)
        recorder.record(.paywallShown)
        XCTAssertEqual(recorder.count(for: .exportStarted), 2)
        XCTAssertEqual(recorder.count(for: .paywallShown), 1)
        XCTAssertEqual(recorder.count(for: .purchaseStarted), 0)
    }

    func testSnapshotOnlyIncludesNonZero() {
        let recorder = makeRecorder()
        recorder.record(.scanCompleted)
        recorder.record(.shareSheetOpened)
        recorder.record(.shareSheetOpened)
        let snap = recorder.snapshot()
        XCTAssertEqual(snap["scan_completed"], 1)
        XCTAssertEqual(snap["share_sheet_opened"], 2)
        XCTAssertNil(snap["export_started"])
    }

    func testResetClearsAll() {
        let recorder = makeRecorder()
        recorder.record(.memoryCardPreviewed)
        recorder.record(.growthComparePreviewed)
        recorder.reset()
        XCTAssertEqual(recorder.count(for: .memoryCardPreviewed), 0)
        XCTAssertEqual(recorder.count(for: .growthComparePreviewed), 0)
        XCTAssertTrue(recorder.snapshot().isEmpty)
    }

    func testAllEventsHaveDistinctKeys() {
        let rawValues = MetricsEvent.allCases.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count, "事件 key 不应重复")
    }
}
