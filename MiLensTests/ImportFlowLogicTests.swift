import XCTest
@testable import MiLens

/// ImportFlowLogic 测试（对应源端 ImportFlowViewModel.test.ets）。
/// 覆盖 resolveModeDecision（三种 ImportMode）+ resolveDefaultClassification。
final class ImportFlowLogicTests: XCTestCase {

    // MARK: - resolveModeDecision

    func testAutoMatchFullPipelineNoSkip() {
        let d = ImportFlowLogic.resolveModeDecision(.autoMatch)
        XCTAssertFalse(d.skipDetection)
        XCTAssertFalse(d.skipAutoMatch)
        XCTAssertEqual(d.modeLabel, "auto-match")
    }

    func testImportAllSkipDetectionButKeepMatching() {
        let d = ImportFlowLogic.resolveModeDecision(.importAll)
        XCTAssertTrue(d.skipDetection)
        XCTAssertFalse(d.skipAutoMatch)
        XCTAssertEqual(d.modeLabel, "all")
    }

    func testImportUnassignedSkipBothDetectionAndMatching() {
        let d = ImportFlowLogic.resolveModeDecision(.importUnassigned)
        XCTAssertTrue(d.skipDetection)
        XCTAssertTrue(d.skipAutoMatch)
        XCTAssertEqual(d.modeLabel, "unassigned")
    }

    // MARK: - resolveDefaultClassification

    func testImportUnassignedReturnsPetPhotoOtherWithLabel() {
        let c = ImportFlowLogic.resolveDefaultClassification(.importUnassigned)
        XCTAssertEqual(c.label, "unassigned_pet_confirmed_by_scan")
        XCTAssertEqual(c.confidence, 1.0, accuracy: 1e-9)
    }

    func testAutoMatchReturnsEmptyClassification() {
        let c = ImportFlowLogic.resolveDefaultClassification(.autoMatch)
        XCTAssertEqual(c.label, "")
    }

    func testImportAllReturnsEmptyClassification() {
        let c = ImportFlowLogic.resolveDefaultClassification(.importAll)
        XCTAssertEqual(c.label, "")
    }
}
