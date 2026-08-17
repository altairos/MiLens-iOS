//  RedPacketQualityInputBuilderTests —— 质量检测输入组装纯逻辑测试。
//  覆盖：清晰度用原图 / 亮度优先抠图主体 / 宠物面积比例与钳制 / 安全区判定 /
//  文本层回退与对比度 / cutoutMetricsAvailable 组合语义。

import XCTest
import MiLensKit
@testable import MiLens

final class RedPacketQualityInputBuilderTests: XCTestCase {

    // MARK: - 辅助

    private let template = RedPacketTemplateCatalog.firstFreeTemplate

    private func makeMetrics(
        w: Int = 957, h: Int = 1278,
        sharpness: Double = 3000, brightness: Double = 0.5,
        shadow: Double = 0, highlight: Double = 0
    ) -> RedPacketImageMetrics {
        RedPacketImageMetrics(pixelWidth: w, pixelHeight: h, sharpness: sharpness,
                              averageBrightness: brightness,
                              shadowClippingRatio: shadow,
                              highlightClippingRatio: highlight,
                              sampledPixelCount: 65536)
    }

    /// 居中宠物层（默认可见，指定逻辑宽高与缩放）。
    private func makePetLayer(width: Double = 400, height: Double = 400,
                              scale: Double = 1, visible: Bool = true) -> RedPacketLayer {
        RedPacketLayer(id: "pet", kind: .pet, x: rpCanvasWidth / 2, y: rpCanvasHeight / 2,
                       scale: scale, visible: visible,
                       width: width, height: height, resourceRef: "pet.png")
    }

    private func makeTextLayer(text: String = "新年快乐",
                               styleID: String = RedPacketTextStylePreset.festive.rawValue) -> RedPacketLayer {
        RedPacketLayer(id: "text", kind: .text, x: rpCanvasWidth / 2, y: 200,
                       width: 300, height: 60, text: text, styleID: styleID)
    }

    // MARK: - 指标来源优先级

    /// 清晰度/分辨率用原图，亮度优先抠图主体。
    func testClarityFromSourceAndBrightnessPrefersCutout() {
        let input = RedPacketQualityInputBuilder.make(
            layers: [makePetLayer(), makeTextLayer()],
            template: template,
            sourceMetrics: makeMetrics(sharpness: 2500, brightness: 0.5),
            cutoutMetrics: makeMetrics(w: 800, h: 900, sharpness: 999, brightness: 0.2),
            maskMetrics: nil, cutoutApplied: true)

        XCTAssertEqual(input.imageWidth, 957, "分辨率取原图")
        XCTAssertEqual(input.imageHeight, 1278)
        XCTAssertEqual(input.sharpness, 2500, "清晰度取原图（透明轮廓会抬高 Laplacian）")
        XCTAssertEqual(input.averageBrightness, 0.2, accuracy: 0.0001, "亮度优先抠图主体")
    }

    /// 抠图主体指标缺失时亮度回退原图，且 imageMetricsAvailable 仍为 true。
    func testBrightnessFallsBackToSourceWhenCutoutMissing() {
        let input = RedPacketQualityInputBuilder.make(
            layers: [makePetLayer()],
            template: template,
            sourceMetrics: makeMetrics(brightness: 0.6),
            cutoutMetrics: nil, maskMetrics: nil, cutoutApplied: false)

        XCTAssertEqual(input.averageBrightness, 0.6, accuracy: 0.0001)
        XCTAssertTrue(input.imageMetricsAvailable, "source 与 tone（回退 source）均存在")
    }

    /// 原图指标缺失：宽高/清晰度归零且 imageMetricsAvailable=false（不得伪装通过）。
    func testSourceMissingDisablesImageMetrics() {
        let input = RedPacketQualityInputBuilder.make(
            layers: [makePetLayer()],
            template: template,
            sourceMetrics: nil,
            cutoutMetrics: makeMetrics(brightness: 0.4),
            maskMetrics: nil, cutoutApplied: false)

        XCTAssertEqual(input.imageWidth, 0)
        XCTAssertEqual(input.sharpness, 0)
        XCTAssertEqual(input.averageBrightness, 0.4, accuracy: 0.0001, "亮度仍可用抠图主体")
        XCTAssertFalse(input.imageMetricsAvailable, "clarity 缺失即 false")
    }

    // MARK: - 宠物层

    /// 宠物面积比例 = width*scale*height*scale / 画布面积。
    func testPetCoverageRatioFormula() {
        let input = RedPacketQualityInputBuilder.make(
            layers: [makePetLayer(width: 400, height: 400, scale: 1)],
            template: template,
            sourceMetrics: makeMetrics(), cutoutMetrics: nil,
            maskMetrics: nil, cutoutApplied: false)

        let expected = (400 * 1 * 400 * 1) / (rpCanvasWidth * rpCanvasHeight)
        XCTAssertEqual(input.petCoverageRatio, expected, accuracy: 0.0001)
    }

    /// 超出画布的宠物层面积钳制为 1。
    func testPetCoverageRatioClampedToOne() {
        let input = RedPacketQualityInputBuilder.make(
            layers: [makePetLayer(scale: 10)],
            template: template,
            sourceMetrics: makeMetrics(), cutoutMetrics: nil,
            maskMetrics: nil, cutoutApplied: false)

        XCTAssertEqual(input.petCoverageRatio, 1, accuracy: 0.0001)
    }

    /// 宠物层隐藏：面积比例为 0。
    func testHiddenPetLayerZeroCoverage() {
        let input = RedPacketQualityInputBuilder.make(
            layers: [makePetLayer(visible: false)],
            template: template,
            sourceMetrics: makeMetrics(), cutoutMetrics: nil,
            maskMetrics: nil, cutoutApplied: false)

        XCTAssertEqual(input.petCoverageRatio, 0, accuracy: 0.0001)
    }

    /// 无宠物层：安全区判定为假，面积与可见比例归零。
    func testMissingPetLayerZeroesSafeZoneFields() {
        let input = RedPacketQualityInputBuilder.make(
            layers: [makeTextLayer()],
            template: template,
            sourceMetrics: makeMetrics(), cutoutMetrics: nil,
            maskMetrics: nil, cutoutApplied: false)

        XCTAssertFalse(input.petInSafeZone)
        XCTAssertEqual(input.petCoverageRatio, 0, accuracy: 0.0001)
        XCTAssertEqual(input.petSafeZoneCoverageRatio, 0, accuracy: 0.0001)
        XCTAssertEqual(input.petCanvasVisibleRatio, 0, accuracy: 0.0001)
    }

    // MARK: - 文本层

    /// 无文本层：不构成可读性问题（安全区默认通过、对比度满分）。
    func testMissingTextLayerPassesReadabilityDefaults() {
        let input = RedPacketQualityInputBuilder.make(
            layers: [makePetLayer()],
            template: template,
            sourceMetrics: makeMetrics(), cutoutMetrics: nil,
            maskMetrics: nil, cutoutApplied: false)

        XCTAssertTrue(input.textInSafeZone)
        XCTAssertEqual(input.textContent, "")
        XCTAssertEqual(input.textContrast, 1, accuracy: 0.0001)
    }

    /// 文本层存在且样式可解析：对比度走 WCAG 真实计算（非满分）。
    func testTextLayerUsesWCAGContrast() {
        let input = RedPacketQualityInputBuilder.make(
            layers: [makePetLayer(), makeTextLayer()],
            template: template,
            sourceMetrics: makeMetrics(), cutoutMetrics: nil,
            maskMetrics: nil, cutoutApplied: false)

        XCTAssertEqual(input.textContent, "新年快乐")
        XCTAssertGreaterThan(input.textContrast, 0, "可解析样式计算真实对比度")
    }

    /// 文本层样式 ID 无效（不在预置表）：不构成可读性问题，对比度取满分。
    func testInvalidTextStyleFallsBackToFullContrast() {
        let input = RedPacketQualityInputBuilder.make(
            layers: [makePetLayer(), makeTextLayer(styleID: "no-such-style")],
            template: template,
            sourceMetrics: makeMetrics(), cutoutMetrics: nil,
            maskMetrics: nil, cutoutApplied: false)

        XCTAssertEqual(input.textContrast, 1, accuracy: 0.0001)
    }

    // MARK: - 蒙版指标

    /// cutoutMetricsAvailable = cutoutApplied && maskMetrics 存在（四象限）。
    func testCutoutMetricsAvailableRequiresBothAppliedAndMask() {
        let mask = RedPacketMaskMetrics(foregroundRatio: 0.4, edgeRoughness: 0.1,
                                        fragmentationRatio: 0.05, boundaryTouchRatio: 0.2)
        func make(_ applied: Bool, _ mask: RedPacketMaskMetrics?) -> RedPacketQualityInput {
            RedPacketQualityInputBuilder.make(
                layers: [makePetLayer()], template: template,
                sourceMetrics: makeMetrics(), cutoutMetrics: nil,
                maskMetrics: mask, cutoutApplied: applied)
        }
        XCTAssertTrue(make(true, mask).cutoutMetricsAvailable)
        XCTAssertFalse(make(true, nil).cutoutMetricsAvailable)
        XCTAssertFalse(make(false, mask).cutoutMetricsAvailable)
        XCTAssertFalse(make(false, nil).cutoutMetricsAvailable)
    }

    /// 蒙版指标缺失时全部归零，不残留默认值。
    func testMissingMaskMetricsZeroesCutoutFields() {
        let input = RedPacketQualityInputBuilder.make(
            layers: [makePetLayer()],
            template: template,
            sourceMetrics: makeMetrics(), cutoutMetrics: nil,
            maskMetrics: nil, cutoutApplied: false)

        XCTAssertEqual(input.cutoutEdgeRoughness, 0, accuracy: 0.0001)
        XCTAssertEqual(input.cutoutForegroundRatio, 0, accuracy: 0.0001)
        XCTAssertEqual(input.cutoutFragmentationRatio, 0, accuracy: 0.0001)
        XCTAssertEqual(input.cutoutBoundaryTouchRatio, 0, accuracy: 0.0001)
    }
}
