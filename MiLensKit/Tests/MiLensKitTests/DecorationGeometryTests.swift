import XCTest
@testable import MiLensKit

// DecorationGeometryTests — 装饰图层默认几何测试（阻塞项2）。
// 覆盖：frame 画布中心/铺满/初始姿态；sticker 视觉尺寸 22% 短边（按素材宽高比分配）、
// 首贴纸右上 18% 偏移、堆叠 +8% 偏移、环形回归落点 clamp 画布内。
// 期望值全部手算（见各用例注释），画布统一 200x400（短边 200）。

final class DecorationGeometryTests: XCTestCase {

    private func makeItem(
        _ category: DecorationCategory, ratio: Double? = nil
    ) -> DecorationItem {
        DecorationItem(
            id: "d_\(category.rawValue)", name: "D", category: category,
            resourcePath: "d", previewPath: "d", nativeAspectRatio: ratio)
    }

    // MARK: - frame 几何

    func testFrameLayerCentersAndFillsCanvas() {
        let layer = createDecorationLayer(
            from: makeItem(.frame), canvasWidth: 200, canvasHeight: 400)
        // 中心 = 画布中心；宽高 = 画布尺寸（铺满）
        XCTAssertEqual(layer.x, 100, accuracy: 1e-9)
        XCTAssertEqual(layer.y, 200, accuracy: 1e-9)
        XCTAssertEqual(layer.width, 200, accuracy: 1e-9)
        XCTAssertEqual(layer.height, 400, accuracy: 1e-9)
    }

    func testFrameLayerInitialPose() {
        // frame 恒 rotation=0 / scale=1 / flip=false / visible=true
        let layer = createDecorationLayer(
            from: makeItem(.frame), canvasWidth: 200, canvasHeight: 400)
        XCTAssertEqual(layer.rotation, 0)
        XCTAssertEqual(layer.scale, 1)
        XCTAssertFalse(layer.flipX)
        XCTAssertFalse(layer.flipY)
        XCTAssertTrue(layer.visible)
    }

    // MARK: - sticker 视觉尺寸（短边 × 22%，较大边 = 视觉尺寸）

    func testStickerSquareVisualSize() {
        // 方形素材（缺 ratio 元数据同样按 1 处理）：44 = 200 × 22%
        let layer = createDecorationLayer(
            from: makeItem(.sticker, ratio: nil), canvasWidth: 200, canvasHeight: 400)
        XCTAssertEqual(layer.width, 44, accuracy: 1e-9)
        XCTAssertEqual(layer.height, 44, accuracy: 1e-9)
    }

    func testStickerWideRatioAssignsLargerSideToWidth() {
        // ratio = 2（宽素材）：宽 = 44（较大边），高 = 22
        let layer = createDecorationLayer(
            from: makeItem(.sticker, ratio: 2), canvasWidth: 200, canvasHeight: 400)
        XCTAssertEqual(layer.width, 44, accuracy: 1e-9)
        XCTAssertEqual(layer.height, 22, accuracy: 1e-9)
    }

    func testStickerTallRatioAssignsLargerSideToHeight() {
        // ratio = 0.5（高素材）：高 = 44（较大边），宽 = 22
        let layer = createDecorationLayer(
            from: makeItem(.sticker, ratio: 0.5), canvasWidth: 200, canvasHeight: 400)
        XCTAssertEqual(layer.width, 22, accuracy: 1e-9)
        XCTAssertEqual(layer.height, 44, accuracy: 1e-9)
    }

    // MARK: - sticker 落点（中心语义）

    func testFirstStickerOffsetsTopRight() {
        // 首贴纸：偏移 18%×200 = 36 → 中心 (100+36, 200-36) = (136, 164)
        let layer = createDecorationLayer(
            from: makeItem(.sticker), canvasWidth: 200, canvasHeight: 400, stickerCount: 0)
        XCTAssertEqual(layer.x, 136, accuracy: 1e-9)
        XCTAssertEqual(layer.y, 164, accuracy: 1e-9)
    }

    func testStackedStickerShiftsFurther() {
        // 第 2 个贴纸：偏移 (18%+8%)×200 = 52 → 中心 (100+52, 200-52) = (152, 148)
        let layer = createDecorationLayer(
            from: makeItem(.sticker), canvasWidth: 200, canvasHeight: 400, stickerCount: 1)
        XCTAssertEqual(layer.x, 152, accuracy: 1e-9)
        XCTAssertEqual(layer.y, 148, accuracy: 1e-9)
    }

    func testManyStacksStayInsideCanvas() {
        // 大 stickerCount 触发环形回归（偏移对可用半径取模），落点仍 clamp 在画布内
        for count in [2, 5, 10, 20, 100] {
            let layer = createDecorationLayer(
                from: makeItem(.sticker), canvasWidth: 200, canvasHeight: 400,
                stickerCount: count)
            XCTAssertGreaterThanOrEqual(layer.x, layer.width / 2 - 1e-9, "count=\(count)")
            XCTAssertLessThanOrEqual(layer.x, 200 - layer.width / 2 + 1e-9, "count=\(count)")
            XCTAssertGreaterThanOrEqual(layer.y, layer.height / 2 - 1e-9, "count=\(count)")
            XCTAssertLessThanOrEqual(layer.y, 400 - layer.height / 2 + 1e-9, "count=\(count)")
        }
    }

    func testStickerRingReturnComputes() {
        // stickerCount=20：偏移 = (18% + 8%×20)×200 = 356；
        // 环形：356 mod 78 = 44 → x = 144；356 mod 178 = 0 → y = 200
        let layer = createDecorationLayer(
            from: makeItem(.sticker), canvasWidth: 200, canvasHeight: 400, stickerCount: 20)
        XCTAssertEqual(layer.x, 144, accuracy: 1e-9)
        XCTAssertEqual(layer.y, 200, accuracy: 1e-9)
    }
}
