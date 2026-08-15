import XCTest
@testable import MiLensKit

// StickerSnapGuideTests — 拖动中心吸附与边界 clamp 纯函数测试（M2 质量项，规格 §4.3）。
// 语义：|中心 − 画布中心线| ≤ 6pt 吸附对齐；离开阈值立即释放（无滞后）；
// 中心 clamp 在画布 [0, W]×[0, H]；画布非法原样返回。

final class StickerSnapGuideTests: XCTestCase {

    private let canvasW = 400.0
    private let canvasH = 300.0

    // MARK: - 吸附

    func testExactCenterSnapsBothAxes() {
        let r = snapAndClampLayerCenter(x: 200, y: 150, canvasW: canvasW, canvasH: canvasH)
        XCTAssertEqual(r.x, 200, accuracy: 1e-9)
        XCTAssertEqual(r.y, 150, accuracy: 1e-9)
        XCTAssertTrue(r.snapsX)
        XCTAssertTrue(r.snapsY)
    }

    func testWithinThresholdSnapsToCenterLine() {
        // 阈值边界（±6 恰好命中）：吸附到中心线
        let r1 = snapAndClampLayerCenter(x: 206, y: 144, canvasW: canvasW, canvasH: canvasH)
        XCTAssertEqual(r1.x, 200, accuracy: 1e-9)
        XCTAssertEqual(r1.y, 150, accuracy: 1e-9)
        XCTAssertTrue(r1.snapsX)
        XCTAssertTrue(r1.snapsY)

        // 阈值内（4pt）：吸附
        let r2 = snapAndClampLayerCenter(x: 196, y: 154, canvasW: canvasW, canvasH: canvasH)
        XCTAssertEqual(r2.x, 200, accuracy: 1e-9)
        XCTAssertEqual(r2.y, 150, accuracy: 1e-9)
        XCTAssertTrue(r2.snapsX)
        XCTAssertTrue(r2.snapsY)
    }

    func testBeyondThresholdNoSnap() {
        // 阈值外（6.1pt）：原样，不吸附
        let r = snapAndClampLayerCenter(x: 206.1, y: 143.9, canvasW: canvasW, canvasH: canvasH)
        XCTAssertEqual(r.x, 206.1, accuracy: 1e-9)
        XCTAssertEqual(r.y, 143.9, accuracy: 1e-9)
        XCTAssertFalse(r.snapsX)
        XCTAssertFalse(r.snapsY)
    }

    func testLeaveThresholdReleasesImmediately() {
        // 离开立即释放（无滞后）：同一手势内先阈值内、再阈值外的两次独立调用
        let inside = snapAndClampLayerCenter(x: 198, y: 150, canvasW: canvasW, canvasH: canvasH)
        XCTAssertTrue(inside.snapsX)
        XCTAssertEqual(inside.x, 200, accuracy: 1e-9)

        let outside = snapAndClampLayerCenter(x: 210, y: 150, canvasW: canvasW, canvasH: canvasH)
        XCTAssertFalse(outside.snapsX)
        XCTAssertEqual(outside.x, 210, accuracy: 1e-9)
    }

    func testAxesSnapIndependently() {
        // 仅 x 轴在阈值内：只吸附 x、只显示垂直参考线
        let rxOnly = snapAndClampLayerCenter(x: 197, y: 40, canvasW: canvasW, canvasH: canvasH)
        XCTAssertEqual(rxOnly.x, 200, accuracy: 1e-9)
        XCTAssertEqual(rxOnly.y, 40, accuracy: 1e-9)
        XCTAssertTrue(rxOnly.snapsX)
        XCTAssertFalse(rxOnly.snapsY)

        // 仅 y 轴在阈值内
        let ryOnly = snapAndClampLayerCenter(x: 40, y: 147, canvasW: canvasW, canvasH: canvasH)
        XCTAssertEqual(ryOnly.x, 40, accuracy: 1e-9)
        XCTAssertEqual(ryOnly.y, 150, accuracy: 1e-9)
        XCTAssertFalse(ryOnly.snapsX)
        XCTAssertTrue(ryOnly.snapsY)
    }

    // MARK: - 边界 clamp

    func testCenterClampedInsideCanvas() {
        // 拖出画布：中心 clamp 在 [0, W]/[0, H]（保留可拖回的半幅可见）
        let r = snapAndClampLayerCenter(x: -50, y: 400, canvasW: canvasW, canvasH: canvasH)
        XCTAssertEqual(r.x, 0, accuracy: 1e-9)
        XCTAssertEqual(r.y, 300, accuracy: 1e-9)
        XCTAssertFalse(r.snapsX)
        XCTAssertFalse(r.snapsY)
    }

    func testSnapWinsOverCanvasEdge() {
        // 吸附中心线优先（吸附值必在画布内，clamp 不改变吸附结果）
        let r = snapAndClampLayerCenter(x: -200, y: 148, canvasW: canvasW, canvasH: canvasH)
        XCTAssertEqual(r.x, 0, accuracy: 1e-9)
        XCTAssertEqual(r.y, 150, accuracy: 1e-9)
        XCTAssertTrue(r.snapsY)
    }

    // MARK: - 非法输入与自定义阈值

    func testInvalidCanvasReturnsUnchanged() {
        let r = snapAndClampLayerCenter(x: 37, y: -4, canvasW: 0, canvasH: 300)
        XCTAssertEqual(r.x, 37, accuracy: 1e-9)
        XCTAssertEqual(r.y, -4, accuracy: 1e-9)
        XCTAssertFalse(r.snapsX)
        XCTAssertFalse(r.snapsY)

        let r2 = snapAndClampLayerCenter(x: 37, y: -4, canvasW: 400, canvasH: -1)
        XCTAssertEqual(r2.x, 37, accuracy: 1e-9)
        XCTAssertFalse(r2.snapsX)
    }

    func testCustomThreshold() {
        // 自定义阈值 20：14pt 也吸附
        let r = snapAndClampLayerCenter(
            x: 214, y: 150, canvasW: canvasW, canvasH: canvasH, threshold: 20)
        XCTAssertEqual(r.x, 200, accuracy: 1e-9)
        XCTAssertTrue(r.snapsX)

        // 默认阈值 6：14pt 不吸附
        let r2 = snapAndClampLayerCenter(x: 214, y: 150, canvasW: canvasW, canvasH: canvasH)
        XCTAssertEqual(r2.x, 214, accuracy: 1e-9)
        XCTAssertFalse(r2.snapsX)
    }
}
