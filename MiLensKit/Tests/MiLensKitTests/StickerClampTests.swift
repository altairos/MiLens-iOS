import XCTest
@testable import MiLensKit

// StickerClampTests — 贴纸视觉尺寸钳制（8%–70% 画布短边）与数量上限（20）测试。
// 视觉尺寸定义：素材宽高较大者 × scale（规格 §4.3）。

final class StickerClampTests: XCTestCase {

    // MARK: - clampStickerVisualScale

    func testWithinRangeUnchanged() {
        // 画布短边 100，素材 22：scale 1 → 显示 22（22%），区间内原样返回
        XCTAssertEqual(
            clampStickerVisualScale(nativeW: 22, nativeH: 22, scale: 1, canvasW: 100, canvasH: 300),
            1, accuracy: 1e-9)
        XCTAssertEqual(
            clampStickerVisualScale(nativeW: 22, nativeH: 22, scale: 3, canvasW: 300, canvasH: 100),
            3, accuracy: 1e-9, "短边取 min(宽,高)")
    }

    func testLowerBoundClamp() {
        // 显示 2.2 < 8（8%）→ 钳到 8 → scale = 8/22
        let clamped = clampStickerVisualScale(
            nativeW: 22, nativeH: 22, scale: 0.1, canvasW: 100, canvasH: 100)
        XCTAssertEqual(clamped, 8.0 / 22.0, accuracy: 1e-9)
    }

    func testUpperBoundClamp() {
        // 显示 220 > 70（70%）→ 钳到 70 → scale = 70/22
        let clamped = clampStickerVisualScale(
            nativeW: 22, nativeH: 22, scale: 10, canvasW: 100, canvasH: 100)
        XCTAssertEqual(clamped, 70.0 / 22.0, accuracy: 1e-9)
    }

    func testExactBoundsUnchanged() {
        // 恰好 8% / 70%：不变
        XCTAssertEqual(
            clampStickerVisualScale(nativeW: 100, nativeH: 100, scale: 0.08, canvasW: 100, canvasH: 100),
            0.08, accuracy: 1e-9)
        XCTAssertEqual(
            clampStickerVisualScale(nativeW: 100, nativeH: 100, scale: 0.7, canvasW: 100, canvasH: 100),
            0.7, accuracy: 1e-9)
    }

    func testClampUsesLargerSide() {
        // 非方形素材：取 max(40, 10) = 40 为基准。scale 1 → 显示 40（40%）区间内
        XCTAssertEqual(
            clampStickerVisualScale(nativeW: 40, nativeH: 10, scale: 1, canvasW: 100, canvasH: 100),
            1, accuracy: 1e-9)
        // scale 2.5 → 显示 100 > 70 → 钳到 70 → scale = 1.75
        XCTAssertEqual(
            clampStickerVisualScale(nativeW: 40, nativeH: 10, scale: 2.5, canvasW: 100, canvasH: 100),
            1.75, accuracy: 1e-9)
    }

    func testInvalidCanvasOrAssetReturnsUnchanged() {
        // 画布非法 / 素材非法：原样返回（无有效基准）
        XCTAssertEqual(
            clampStickerVisualScale(nativeW: 22, nativeH: 22, scale: 2, canvasW: 0, canvasH: 100),
            2, accuracy: 1e-9)
        XCTAssertEqual(
            clampStickerVisualScale(nativeW: 0, nativeH: 0, scale: 2, canvasW: 100, canvasH: 100),
            2, accuracy: 1e-9)
    }

    // MARK: - isStickerLimitReached

    private func stickers(_ count: Int) -> [EditorLayer] {
        (0..<count).map { i in
            EditorLayer(id: "s\(i)", type: .sticker, width: 44, height: 44)
        }
    }

    func testBelowLimitNotReached() {
        XCTAssertFalse(isStickerLimitReached(stickers(19)))
        XCTAssertFalse(isStickerLimitReached([]))
    }

    func testAtLimitReached() {
        XCTAssertTrue(isStickerLimitReached(stickers(20)))
        XCTAssertTrue(isStickerLimitReached(stickers(25)))
    }

    func testOnlyStickersCounted() {
        // text/frame/photo 不占贴纸名额
        var layers = stickers(19)
        layers.append(EditorLayer(id: "t", type: .text))
        layers.append(EditorLayer(id: "f", type: .frame, width: 100, height: 100))
        XCTAssertFalse(isStickerLimitReached(layers))
    }

    func testCustomLimit() {
        XCTAssertTrue(isStickerLimitReached(stickers(5), limit: 5))
        XCTAssertFalse(isStickerLimitReached(stickers(4), limit: 5))
    }
}
