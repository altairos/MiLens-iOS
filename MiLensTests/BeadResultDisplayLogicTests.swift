import XCTest
@testable import MiLens

/// BeadResultDisplayLogic 测试（audit-6 P1-4：从 BeadPatternResultView 下沉的结果页展示碎片）。
/// 覆盖身份元信息拼接与缩放滑轨进度映射（含超界 clamp）。
final class BeadResultDisplayLogicTests: XCTestCase {

    // MARK: - identityMeta

    func testIdentityMetaJoinsSizeAndColorCount() {
        XCTAssertEqual(BeadResultDisplayLogic.identityMeta(width: 29, height: 29, colorCount: 12), "29×29 · 12 色")
    }

    func testIdentityMetaSupportsRectangularBoard() {
        XCTAssertEqual(BeadResultDisplayLogic.identityMeta(width: 52, height: 26, colorCount: 24), "52×26 · 24 色")
    }

    // MARK: - zoomProgress

    func testZoomProgressMapsMidScaleToHalf() {
        XCTAssertEqual(BeadResultDisplayLogic.zoomProgress(canvasScale: 1.0), 0.5, accuracy: 0.0001)
    }

    func testZoomProgressMapsFullScaleToOne() {
        XCTAssertEqual(BeadResultDisplayLogic.zoomProgress(canvasScale: 2.0), 1.0, accuracy: 0.0001)
    }

    func testZoomProgressClampsAboveRange() {
        XCTAssertEqual(BeadResultDisplayLogic.zoomProgress(canvasScale: 5.0), 1.0, accuracy: 0.0001)
    }

    func testZoomProgressClampsBelowRange() {
        XCTAssertEqual(BeadResultDisplayLogic.zoomProgress(canvasScale: -1.0), 0.0, accuracy: 0.0001)
    }
}
