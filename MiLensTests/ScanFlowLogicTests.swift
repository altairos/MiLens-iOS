import XCTest
@testable import MiLens

/// ScanFlowLogic 测试（对应源端 ScanFlowViewModel.test.ets）。
/// 覆盖 resolveFlow（error/canceled/paused/complete 四分支）+ resolveCompleteMessage 文案。
final class ScanFlowLogicTests: XCTestCase {

    // MARK: - resolveFlow

    func testResolveFlowReturnsShowErrorWhenErrorNonEmpty() {
        let op = ScanOpSnapshot(error: "network failed", canceled: false, result: nil)
        XCTAssertEqual(ScanFlowLogic.resolveFlow(op), .showError)
    }

    func testResolveFlowReturnsShowCanceledWhenCanceledAndNoError() {
        let op = ScanOpSnapshot(error: "", canceled: true, result: nil)
        XCTAssertEqual(ScanFlowLogic.resolveFlow(op), .showCanceled)
    }

    func testResolveFlowReturnsSetPausedWhenResultNilWithoutErrorOrCancel() {
        let op = ScanOpSnapshot(error: "", canceled: false, result: nil)
        XCTAssertEqual(ScanFlowLogic.resolveFlow(op), .setPaused)
    }

    func testResolveFlowReturnsProceedCompleteWhenResultNonNil() {
        let scanResult = ScanResult(matchedCount: 3, unassignedPetUris: [], processedCount: 50)
        let op = ScanOpSnapshot(error: "", canceled: false, result: scanResult)
        XCTAssertEqual(ScanFlowLogic.resolveFlow(op), .proceedComplete)
    }

    func testResolveFlowPrioritizesErrorOverCanceled() {
        let op = ScanOpSnapshot(error: "err", canceled: true, result: nil)
        XCTAssertEqual(ScanFlowLogic.resolveFlow(op), .showError)
    }

    func testResolveFlowPrioritizesCanceledOverNullResult() {
        let op = ScanOpSnapshot(error: "", canceled: true, result: nil)
        XCTAssertEqual(ScanFlowLogic.resolveFlow(op), .showCanceled)
    }

    // MARK: - resolveCompleteMessage

    func testCompleteMessageIncludesCountForNewOnlyScan() {
        let msg = ScanFlowLogic.resolveCompleteMessage(matchedCount: 0, unassignedCount: 0, processedCount: 10, isNewOnly: true)
        XCTAssertTrue(msg.contains("新扫描 10 张照片。"))
    }

    func testCompleteMessageIncludesCountForFullScan() {
        let msg = ScanFlowLogic.resolveCompleteMessage(matchedCount: 0, unassignedCount: 0, processedCount: 50, isNewOnly: false)
        XCTAssertTrue(msg.contains("共扫描 50 张照片。"))
    }

    func testCompleteMessageAppendsMatchedLineWhenMatchedGreaterThanZero() {
        let msg = ScanFlowLogic.resolveCompleteMessage(matchedCount: 5, unassignedCount: 0, processedCount: 50, isNewOnly: false)
        XCTAssertTrue(msg.contains("5 张照片属于已注册的伙伴"))
    }

    func testCompleteMessageAppendsUnassignedLineWhenUnassignedGreaterThanZero() {
        let msg = ScanFlowLogic.resolveCompleteMessage(matchedCount: 0, unassignedCount: 3, processedCount: 50, isNewOnly: false)
        XCTAssertTrue(msg.contains("3 张照片也包含猫或狗"))
    }

    func testCompleteMessageAppendsNoneFoundLineWhenBothZero() {
        let msg = ScanFlowLogic.resolveCompleteMessage(matchedCount: 0, unassignedCount: 0, processedCount: 50, isNewOnly: false)
        XCTAssertTrue(msg.contains("未发现任何包含猫或狗"))
    }
}
