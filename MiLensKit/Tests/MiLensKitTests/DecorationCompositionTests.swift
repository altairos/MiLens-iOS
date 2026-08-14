import XCTest
@testable import MiLensKit

// DecorationCompositionTests — 稳定合成顺序（阻塞项5）与画布重映射（阻塞项7）测试。
// 排序规则：photo → frame → sticker → text，同类型内 zIndex 升序，同 zIndex 保持原序。

final class DecorationCompositionTests: XCTestCase {

    // MARK: - orderedRenderLayers

    func testSortsByTypeOrder() {
        // 乱序输入：类型序优先于 zIndex（photo 层 zIndex 最大仍在最底）
        let layers = [
            EditorLayer(id: "t1", type: .text, zIndex: 1),
            EditorLayer(id: "s1", type: .sticker, zIndex: 2, width: 10, height: 10),
            EditorLayer(id: "f1", type: .frame, zIndex: 3, width: 10, height: 10),
            EditorLayer(id: "p1", type: .photo, zIndex: 4, width: 10, height: 10),
        ]
        let ordered = orderedRenderLayers(layers)
        XCTAssertEqual(ordered.map(\.id), ["p1", "f1", "s1", "t1"])
    }

    func testTypeOrderBeatsZIndex() {
        // frame zIndex 9 仍先于 sticker zIndex 2（类型权重优先，阻塞项5 语义）
        let layers = [
            EditorLayer(id: "s1", type: .sticker, zIndex: 2, width: 10, height: 10),
            EditorLayer(id: "f1", type: .frame, zIndex: 9, width: 10, height: 10),
        ]
        XCTAssertEqual(orderedRenderLayers(layers).map(\.id), ["f1", "s1"])
    }

    func testSameTypeSortsByZIndexAscending() {
        let layers = [
            EditorLayer(id: "s2", type: .sticker, zIndex: 5, width: 10, height: 10),
            EditorLayer(id: "s1", type: .sticker, zIndex: 1, width: 10, height: 10),
            EditorLayer(id: "s3", type: .sticker, zIndex: 3, width: 10, height: 10),
        ]
        XCTAssertEqual(
            orderedRenderLayers(layers).map(\.id), ["s1", "s3", "s2"],
            "同类型内 zIndex 升序")
    }

    func testSameTypeSameZIndexKeepsOriginalOrder() {
        // 同类型同 zIndex：保持原始相对顺序（显式稳定）
        let layers = [
            EditorLayer(id: "a", type: .sticker, zIndex: 2, width: 10, height: 10),
            EditorLayer(id: "b", type: .sticker, zIndex: 2, width: 10, height: 10),
            EditorLayer(id: "c", type: .sticker, zIndex: 2, width: 10, height: 10),
        ]
        XCTAssertEqual(orderedRenderLayers(layers).map(\.id), ["a", "b", "c"])
    }

    // MARK: - remapLayersForCanvas

    func testFrameResetsToFillNewCanvas() {
        // frame 带脏姿态（rotation/scale/flip）：重映射后按新画布重新铺满并重置姿态
        var frame = EditorLayer(id: "f", type: .frame, x: 10, y: 20, width: 100, height: 200)
        frame.rotation = 30
        frame.scale = 2.5
        frame.flipX = true
        let remapped = remapLayersForCanvas([frame], from: CGSize(width: 100, height: 200),
                                            to: CGSize(width: 300, height: 600))
        XCTAssertEqual(remapped[0].x, 150, accuracy: 1e-9)
        XCTAssertEqual(remapped[0].y, 300, accuracy: 1e-9)
        XCTAssertEqual(remapped[0].width, 300, accuracy: 1e-9)
        XCTAssertEqual(remapped[0].height, 600, accuracy: 1e-9)
        XCTAssertEqual(remapped[0].rotation, 0)
        XCTAssertEqual(remapped[0].scale, 1)
        XCTAssertFalse(remapped[0].flipX)
    }

    func testPhotoResetsToNewCanvas() {
        // photo 沿用 setCanvasSize 原有语义：中心与宽高重置为新画布
        let photo = EditorLayer(id: "p", type: .photo, x: 100, y: 200, width: 200, height: 400)
        let remapped = remapLayersForCanvas([photo], from: CGSize(width: 200, height: 400),
                                            to: CGSize(width: 100, height: 200))
        XCTAssertEqual(remapped[0].x, 50, accuracy: 1e-9)
        XCTAssertEqual(remapped[0].y, 100, accuracy: 1e-9)
        XCTAssertEqual(remapped[0].width, 100, accuracy: 1e-9)
        XCTAssertEqual(remapped[0].height, 200, accuracy: 1e-9)
    }

    func testStickerMigratesCenterProportionally() {
        // sticker 中心按新旧画布比例归一化迁移；scale 按短边比例缩放（区间内不钳）
        let sticker = EditorLayer(
            id: "s", type: .sticker, x: 136, y: 164, width: 44, height: 44)
        let remapped = remapLayersForCanvas([sticker], from: CGSize(width: 200, height: 400),
                                            to: CGSize(width: 400, height: 800))
        XCTAssertEqual(remapped[0].x, 272, accuracy: 1e-9)
        XCTAssertEqual(remapped[0].y, 328, accuracy: 1e-9)
        // scale 1×2=2 → 显示 88 = 22% 新短边 400，区间内保持
        XCTAssertEqual(remapped[0].scale, 2, accuracy: 1e-9)
    }

    func testStickerScaleClampedAfterRemap() {
        // 越界 scale 的 sticker 重映射后顺带回钳：显示 ≤ 70% 新短边
        let sticker = EditorLayer(
            id: "s", type: .sticker, x: 200, y: 200, scale: 4, width: 88, height: 88)
        let remapped = remapLayersForCanvas([sticker], from: CGSize(width: 400, height: 400),
                                            to: CGSize(width: 800, height: 800))
        // shortScale=2 → 名义 scale 8 → 显示 704 > 560（70%×800）→ 钳到 560
        XCTAssertEqual(88 * remapped[0].scale, 560, accuracy: 1e-6)
    }

    func testTextMigratesAndScalesByShortSide() {
        let text = EditorLayer(id: "t", type: .text, x: 60, y: 80, scale: 2)
        let remapped = remapLayersForCanvas([text], from: CGSize(width: 200, height: 400),
                                            to: CGSize(width: 100, height: 200))
        XCTAssertEqual(remapped[0].x, 30, accuracy: 1e-9)
        XCTAssertEqual(remapped[0].y, 40, accuracy: 1e-9)
        XCTAssertEqual(remapped[0].scale, 1, accuracy: 1e-9, "text 按短边比例缩放并维持层钳制")
    }

    func testInvalidOrSameSizeReturnsUnchanged() {
        let layers = [
            EditorLayer(id: "p", type: .photo, x: 10, y: 10, width: 100, height: 100),
        ]
        // 尺寸相同：原样返回
        XCTAssertEqual(
            remapLayersForCanvas(layers, from: CGSize(width: 100, height: 100),
                                 to: CGSize(width: 100, height: 100)),
            layers)
        // 旧画布非法：原样返回
        XCTAssertEqual(
            remapLayersForCanvas(layers, from: CGSize(width: 0, height: 100),
                                 to: CGSize(width: 50, height: 50)),
            layers)
    }
}
