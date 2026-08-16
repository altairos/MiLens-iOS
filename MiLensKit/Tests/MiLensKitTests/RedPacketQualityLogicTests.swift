import XCTest
@testable import MiLensKit

// RedPacketQualityLogicTests — 质量检测纯逻辑测试（对应红包封面开发计划 §4）。
final class RedPacketQualityLogicTests: XCTestCase {

    // MARK: - 清晰度

    func testClarityPass() {
        let input = makeInput(sharpness: 3000, imageWidth: 1920, imageHeight: 1080)
        let item = RedPacketQualityLogic.evaluateClarity(input)
        XCTAssertEqual(item.level, .pass)
        XCTAssertEqual(item.detailKey, "redpacket.quality.clarity.pass.detail")
        XCTAssertTrue(item.detailArgs.isEmpty)
    }

    func testClaritySoftWarning() {
        let input = makeInput(sharpness: 1000, imageWidth: 1920, imageHeight: 1080)
        let item = RedPacketQualityLogic.evaluateClarity(input)
        XCTAssertEqual(item.level, .warning)
        XCTAssertEqual(item.detailKey, "redpacket.quality.clarity.soft.detail")
        XCTAssertEqual(item.detailArgs, [1000])
    }

    func testClarityBlurError() {
        let input = makeInput(sharpness: 100, imageWidth: 1920, imageHeight: 1080)
        let item = RedPacketQualityLogic.evaluateClarity(input)
        XCTAssertEqual(item.level, .error)
        XCTAssertEqual(item.detailKey, "redpacket.quality.clarity.blur.detail")
        XCTAssertEqual(item.detailArgs, [100])
    }

    func testClarityLowResolutionWarning() {
        let input = makeInput(sharpness: 3000, imageWidth: 200, imageHeight: 200)
        let item = RedPacketQualityLogic.evaluateClarity(input)
        XCTAssertEqual(item.level, .warning)
        XCTAssertEqual(item.detailKey, "redpacket.quality.clarity.resolution.detail")
        XCTAssertEqual(item.detailArgs, [200, 200, 40_000])
    }

    // MARK: - 亮度

    func testBrightnessPass() {
        let input = makeInput(brightness: 0.5)
        let item = RedPacketQualityLogic.evaluateBrightness(input)
        XCTAssertEqual(item.level, .pass)
        XCTAssertEqual(item.detailKey, "redpacket.quality.brightness.pass.detail")
        XCTAssertTrue(item.detailArgs.isEmpty)
    }

    func testBrightnessDarkWarning() {
        let input = makeInput(brightness: 0.1)
        let item = RedPacketQualityLogic.evaluateBrightness(input)
        XCTAssertEqual(item.level, .warning)
        XCTAssertEqual(item.detailKey, "redpacket.quality.brightness.dark.detail")
        XCTAssertEqual(item.detailArgs, [10])
    }

    func testBrightnessOverexposedWarning() {
        let input = makeInput(brightness: 0.9)
        let item = RedPacketQualityLogic.evaluateBrightness(input)
        XCTAssertEqual(item.level, .warning)
        XCTAssertEqual(item.detailKey, "redpacket.quality.brightness.bright.detail")
        XCTAssertEqual(item.detailArgs, [90])
    }

    func testBrightnessClippingWarning() {
        let input = makeInput(brightness: 0.5, shadowClipping: 0.4)
        let item = RedPacketQualityLogic.evaluateBrightness(input)
        XCTAssertEqual(item.level, .warning)
        XCTAssertEqual(item.detailKey, "redpacket.quality.brightness.shadowClipping.detail")
        XCTAssertEqual(item.detailArgs, [40])
    }

    func testBrightnessHighlightClippingWarning() {
        let input = makeInput(brightness: 0.5, highlightClipping: 0.4)
        let item = RedPacketQualityLogic.evaluateBrightness(input)
        XCTAssertEqual(item.level, .warning)
        XCTAssertEqual(item.detailKey, "redpacket.quality.brightness.highlightClipping.detail")
        XCTAssertEqual(item.detailArgs, [40])
    }

    func testImageMetricsUnavailableIsDiagnosable() {
        let input = makeInput(imageMetricsAvailable: false)
        let clarity = RedPacketQualityLogic.evaluateClarity(input)
        XCTAssertEqual(clarity.level, .error)
        XCTAssertEqual(clarity.detailKey, "redpacket.quality.clarity.unavailable.detail")
        let brightness = RedPacketQualityLogic.evaluateBrightness(input)
        XCTAssertEqual(brightness.level, .error)
        XCTAssertEqual(brightness.detailKey, "redpacket.quality.brightness.unavailable.detail")
    }

    // MARK: - 构图

    func testCompositionPass() {
        let input = makeInput(petCoverage: 0.5, petInSafeZone: true)
        let item = RedPacketQualityLogic.evaluateComposition(input)
        XCTAssertEqual(item.level, .pass)
        XCTAssertEqual(item.detailKey, "redpacket.quality.composition.pass.detail")
        XCTAssertTrue(item.detailArgs.isEmpty)
    }

    func testCompositionSmallSubject() {
        let input = makeInput(petCoverage: 0.05, petInSafeZone: true)
        let item = RedPacketQualityLogic.evaluateComposition(input)
        XCTAssertEqual(item.level, .warning)
        XCTAssertEqual(item.detailKey, "redpacket.quality.composition.small.detail")
        XCTAssertEqual(item.detailArgs, [5])
    }

    func testCompositionOutOfSafeZone() {
        let input = makeInput(petCoverage: 0.5, petInSafeZone: false)
        let item = RedPacketQualityLogic.evaluateComposition(input)
        XCTAssertEqual(item.level, .error)
        XCTAssertEqual(item.detailKey, "redpacket.quality.composition.safezone.detail")
        XCTAssertEqual(item.detailArgs, [100]) // petSafeZoneCoverageRatio 默认 1.0
    }

    func testCompositionClippedSubjectIsError() {
        let input = makeInput(petCanvasVisible: 0.7)
        let item = RedPacketQualityLogic.evaluateComposition(input)
        XCTAssertEqual(item.level, .error)
        XCTAssertEqual(item.detailKey, "redpacket.quality.composition.clipped.detail")
        XCTAssertEqual(item.detailArgs, [30])
    }

    // MARK: - 抠图

    func testCutoutPass() {
        let input = makeInput(cutoutRoughness: 0.1)
        let item = RedPacketQualityLogic.evaluateCutout(input)
        XCTAssertEqual(item.level, .pass)
        XCTAssertEqual(item.detailKey, "redpacket.quality.cutout.pass.detail")
        XCTAssertTrue(item.detailArgs.isEmpty)
    }

    func testCutoutRoughWarning() {
        let input = makeInput(cutoutRoughness: 0.5)
        let item = RedPacketQualityLogic.evaluateCutout(input)
        XCTAssertEqual(item.level, .warning)
        XCTAssertEqual(item.detailKey, "redpacket.quality.cutout.rough.detail")
        XCTAssertEqual(item.detailArgs, [50])
    }

    func testCutoutUnavailableIsError() {
        let input = makeInput(cutoutMetricsAvailable: false)
        let item = RedPacketQualityLogic.evaluateCutout(input)
        XCTAssertEqual(item.level, .error)
        XCTAssertEqual(item.detailKey, "redpacket.quality.cutout.unavailable.detail")
        XCTAssertTrue(item.detailArgs.isEmpty)
    }

    func testCutoutTooLittleForegroundIsError() {
        let input = makeInput(cutoutForeground: 0.01)
        let item = RedPacketQualityLogic.evaluateCutout(input)
        XCTAssertEqual(item.level, .error)
        XCTAssertEqual(item.detailKey, "redpacket.quality.cutout.retry.detail")
        XCTAssertEqual(item.detailArgs, [1])
    }

    func testCutoutTooMuchForegroundIsWarning() {
        let input = makeInput(cutoutForeground: 0.95)
        let item = RedPacketQualityLogic.evaluateCutout(input)
        XCTAssertEqual(item.level, .warning)
        XCTAssertEqual(item.detailKey, "redpacket.quality.cutout.background.detail")
        XCTAssertEqual(item.detailArgs, [95])
    }

    func testCutoutFragmentedIsWarning() {
        let input = makeInput(cutoutFragmentation: 0.3)
        let item = RedPacketQualityLogic.evaluateCutout(input)
        XCTAssertEqual(item.level, .warning)
        XCTAssertEqual(item.detailKey, "redpacket.quality.cutout.fragmented.detail")
        XCTAssertEqual(item.detailArgs, [30])
    }

    func testCutoutBoundaryContactIsWarning() {
        let input = makeInput(cutoutBoundaryTouch: 0.3)
        let item = RedPacketQualityLogic.evaluateCutout(input)
        XCTAssertEqual(item.level, .warning)
        XCTAssertEqual(item.detailKey, "redpacket.quality.cutout.incomplete.detail")
        XCTAssertEqual(item.detailArgs, [30])
    }

    // MARK: - 可读性

    func testReadabilityPassWithNoText() {
        let input = makeInput(textContent: "")
        let item = RedPacketQualityLogic.evaluateReadability(input)
        XCTAssertEqual(item.level, .pass)
        XCTAssertEqual(item.detailKey, "redpacket.quality.readability.noText.detail")
        XCTAssertTrue(item.detailArgs.isEmpty)
    }

    func testReadabilityPassWithGoodContrast() {
        let input = makeInput(textContent: "恭喜", textInSafeZone: true, textContrast: 0.8)
        let item = RedPacketQualityLogic.evaluateReadability(input)
        XCTAssertEqual(item.level, .pass)
        XCTAssertEqual(item.detailKey, "redpacket.quality.readability.pass.detail")
        XCTAssertTrue(item.detailArgs.isEmpty)
    }

    func testReadabilityContrastWarning() {
        let input = makeInput(textContent: "恭喜", textInSafeZone: true, textContrast: 0.2)
        let item = RedPacketQualityLogic.evaluateReadability(input)
        XCTAssertEqual(item.level, .warning)
        XCTAssertEqual(item.detailKey, "redpacket.quality.readability.contrast.detail")
        XCTAssertTrue(item.detailArgs.isEmpty)
    }

    func testReadabilityOutOfSafeZoneError() {
        let input = makeInput(textContent: "恭喜", textInSafeZone: false, textContrast: 0.8)
        let item = RedPacketQualityLogic.evaluateReadability(input)
        XCTAssertEqual(item.level, .error)
        XCTAssertEqual(item.detailKey, "redpacket.quality.readability.zone.detail")
        XCTAssertTrue(item.detailArgs.isEmpty)
    }

    // MARK: - 完整评估

    func testEvaluateAllPass() {
        let input = makeInput(
            sharpness: 3000, brightness: 0.5,
            petCoverage: 0.5, cutoutRoughness: 0.1,
            petInSafeZone: true,
            textContent: "恭喜", textInSafeZone: true, textContrast: 0.8
        )
        let report = RedPacketQualityLogic.evaluate(input)
        XCTAssertFalse(report.hasIssues)
        XCTAssertEqual(report.overallLevel, .pass)
    }

    func testEvaluateHasIssues() {
        let input = makeInput(
            sharpness: 100, brightness: 0.1,
            petCoverage: 0.05, cutoutRoughness: 0.5,
            petInSafeZone: false,
            textContent: "恭喜", textInSafeZone: false, textContrast: 0.1
        )
        let report = RedPacketQualityLogic.evaluate(input)
        XCTAssertTrue(report.hasIssues)
        XCTAssertGreaterThan(report.errorCount, 0)
        XCTAssertEqual(report.overallLevel, .error)
        XCTAssertEqual(report.items.count, 5)
    }

    func testReportCounts() {
        let input = makeInput(
            sharpness: 3000, brightness: 0.5,
            petCoverage: 0.05, cutoutRoughness: 0.1,
            petInSafeZone: true,
            textContent: "", textInSafeZone: true, textContrast: 0.6
        )
        let report = RedPacketQualityLogic.evaluate(input)
        XCTAssertEqual(report.warningCount, 1) // 构图 warning（主体过小）
        XCTAssertEqual(report.errorCount, 0)
    }

    // MARK: - 文字对比度计算（WCAG）

    func testRelativeLuminanceBlackAndWhite() {
        XCTAssertEqual(RedPacketQualityLogic.relativeLuminance(hex: "#000000") ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(RedPacketQualityLogic.relativeLuminance(hex: "#FFFFFF") ?? -1, 1, accuracy: 0.001)
    }

    func testContrastRatioBlackOnWhiteIs21() {
        let ratio = RedPacketQualityLogic.contrastRatio(textHex: "#000000", backgroundHex: "#FFFFFF")
        XCTAssertEqual(ratio ?? 0, 21, accuracy: 0.01)
    }

    func testTextContrastFestiveOnNewYearRedPassesThreshold() {
        let value = RedPacketQualityLogic.textContrast(
            textHex: RedPacketTextStylePreset.festive.style.colorHex,
            background: RedPacketTemplateCatalog.newYearRed.background
        )
        XCTAssertNotNil(value)
        XCTAssertGreaterThanOrEqual(value ?? 0, RedPacketQualityLogic.textContrastMin)
    }

    func testTextContrastGoldOnFortuneGoldBelowThreshold() {
        let value = RedPacketQualityLogic.textContrast(
            textHex: RedPacketTextStylePreset.goldBlessing.style.colorHex,
            background: RedPacketTemplateCatalog.fortuneGold.background
        )
        XCTAssertNotNil(value)
        // 金字落在金底渐变的深色端，对比度低于阈值 → 可读性 warning（审计 P2-4 的真实场景）
        XCTAssertLessThan(value ?? 1, RedPacketQualityLogic.textContrastMin)
    }

    func testTextContrastResourceBackgroundReturnsNil() {
        let value = RedPacketQualityLogic.textContrast(
            textHex: "#FFFFFF",
            background: .resource(resourceRef: "bg_custom")
        )
        XCTAssertNil(value)
    }

    func testRelativeLuminanceInvalidHexReturnsNil() {
        XCTAssertNil(RedPacketQualityLogic.relativeLuminance(hex: "#12345"))
        XCTAssertNil(RedPacketQualityLogic.relativeLuminance(hex: "zzzzzz"))
        XCTAssertNil(RedPacketQualityLogic.contrastRatio(textHex: "#GGGGGG", backgroundHex: "#FFFFFF"))
    }

    // MARK: - 辅助

    private func makeInput(
        sharpness: Double = 3000,
        brightness: Double = 0.5,
        petCoverage: Double = 0.5,
        cutoutRoughness: Double = 0.1,
        petInSafeZone: Bool = true,
        imageWidth: Int = 1920,
        imageHeight: Int = 1080,
        textContent: String = "",
        textInSafeZone: Bool = true,
        textContrast: Double = 0.6,
        imageMetricsAvailable: Bool = true,
        shadowClipping: Double = 0,
        highlightClipping: Double = 0,
        petCanvasVisible: Double = 1,
        cutoutMetricsAvailable: Bool = true,
        cutoutForeground: Double = 0.4,
        cutoutFragmentation: Double = 0,
        cutoutBoundaryTouch: Double = 0
    ) -> RedPacketQualityInput {
        RedPacketQualityInput(
            imageWidth: imageWidth, imageHeight: imageHeight,
            sharpness: sharpness, averageBrightness: brightness,
            petCoverageRatio: petCoverage, cutoutEdgeRoughness: cutoutRoughness,
            petInSafeZone: petInSafeZone,
            textContent: textContent, textInSafeZone: textInSafeZone,
            textContrast: textContrast,
            imageMetricsAvailable: imageMetricsAvailable,
            shadowClippingRatio: shadowClipping,
            highlightClippingRatio: highlightClipping,
            petCanvasVisibleRatio: petCanvasVisible,
            cutoutMetricsAvailable: cutoutMetricsAvailable,
            cutoutForegroundRatio: cutoutForeground,
            cutoutFragmentationRatio: cutoutFragmentation,
            cutoutBoundaryTouchRatio: cutoutBoundaryTouch
        )
    }
}
