import XCTest
@testable import MiLensKit

// RedPacketQualityLogicTests — 质量检测纯逻辑测试（对应红包封面开发计划 §4）。
final class RedPacketQualityLogicTests: XCTestCase {

    // MARK: - 清晰度

    func testClarityPass() {
        let input = makeInput(sharpness: 3000, imageWidth: 1920, imageHeight: 1080)
        let item = RedPacketQualityLogic.evaluateClarity(input)
        XCTAssertEqual(item.level, .pass)
    }

    func testClaritySoftWarning() {
        let input = makeInput(sharpness: 1000, imageWidth: 1920, imageHeight: 1080)
        let item = RedPacketQualityLogic.evaluateClarity(input)
        XCTAssertEqual(item.level, .warning)
    }

    func testClarityBlurError() {
        let input = makeInput(sharpness: 100, imageWidth: 1920, imageHeight: 1080)
        let item = RedPacketQualityLogic.evaluateClarity(input)
        XCTAssertEqual(item.level, .error)
    }

    func testClarityLowResolutionWarning() {
        let input = makeInput(sharpness: 3000, imageWidth: 200, imageHeight: 200)
        let item = RedPacketQualityLogic.evaluateClarity(input)
        XCTAssertEqual(item.level, .warning)
    }

    // MARK: - 亮度

    func testBrightnessPass() {
        let input = makeInput(brightness: 0.5)
        let item = RedPacketQualityLogic.evaluateBrightness(input)
        XCTAssertEqual(item.level, .pass)
    }

    func testBrightnessDarkWarning() {
        let input = makeInput(brightness: 0.1)
        let item = RedPacketQualityLogic.evaluateBrightness(input)
        XCTAssertEqual(item.level, .warning)
    }

    func testBrightnessOverexposedWarning() {
        let input = makeInput(brightness: 0.9)
        let item = RedPacketQualityLogic.evaluateBrightness(input)
        XCTAssertEqual(item.level, .warning)
    }

    func testBrightnessClippingWarning() {
        let input = makeInput(brightness: 0.5, shadowClipping: 0.4)
        XCTAssertEqual(RedPacketQualityLogic.evaluateBrightness(input).level, .warning)
    }

    func testImageMetricsUnavailableIsDiagnosable() {
        let input = makeInput(imageMetricsAvailable: false)
        XCTAssertEqual(RedPacketQualityLogic.evaluateClarity(input).level, .error)
        XCTAssertEqual(RedPacketQualityLogic.evaluateBrightness(input).level, .error)
    }

    // MARK: - 构图

    func testCompositionPass() {
        let input = makeInput(petCoverage: 0.5, petInSafeZone: true)
        let item = RedPacketQualityLogic.evaluateComposition(input)
        XCTAssertEqual(item.level, .pass)
    }

    func testCompositionSmallSubject() {
        let input = makeInput(petCoverage: 0.05, petInSafeZone: true)
        let item = RedPacketQualityLogic.evaluateComposition(input)
        XCTAssertEqual(item.level, .warning)
    }

    func testCompositionOutOfSafeZone() {
        let input = makeInput(petCoverage: 0.5, petInSafeZone: false)
        let item = RedPacketQualityLogic.evaluateComposition(input)
        XCTAssertEqual(item.level, .error)
    }

    func testCompositionClippedSubjectIsError() {
        let input = makeInput(petCanvasVisible: 0.7)
        XCTAssertEqual(RedPacketQualityLogic.evaluateComposition(input).level, .error)
    }

    // MARK: - 抠图

    func testCutoutPass() {
        let input = makeInput(cutoutRoughness: 0.1)
        let item = RedPacketQualityLogic.evaluateCutout(input)
        XCTAssertEqual(item.level, .pass)
    }

    func testCutoutRoughWarning() {
        let input = makeInput(cutoutRoughness: 0.5)
        let item = RedPacketQualityLogic.evaluateCutout(input)
        XCTAssertEqual(item.level, .warning)
    }

    func testCutoutUnavailableIsError() {
        let input = makeInput(cutoutMetricsAvailable: false)
        XCTAssertEqual(RedPacketQualityLogic.evaluateCutout(input).level, .error)
    }

    func testCutoutFragmentedIsWarning() {
        let input = makeInput(cutoutFragmentation: 0.3)
        XCTAssertEqual(RedPacketQualityLogic.evaluateCutout(input).level, .warning)
    }

    func testCutoutBoundaryContactIsWarning() {
        let input = makeInput(cutoutBoundaryTouch: 0.3)
        XCTAssertEqual(RedPacketQualityLogic.evaluateCutout(input).level, .warning)
    }

    // MARK: - 可读性

    func testReadabilityPassWithNoText() {
        let input = makeInput(textContent: "")
        let item = RedPacketQualityLogic.evaluateReadability(input)
        XCTAssertEqual(item.level, .pass)
    }

    func testReadabilityPassWithGoodContrast() {
        let input = makeInput(textContent: "恭喜", textInSafeZone: true, textContrast: 0.8)
        let item = RedPacketQualityLogic.evaluateReadability(input)
        XCTAssertEqual(item.level, .pass)
    }

    func testReadabilityContrastWarning() {
        let input = makeInput(textContent: "恭喜", textInSafeZone: true, textContrast: 0.2)
        let item = RedPacketQualityLogic.evaluateReadability(input)
        XCTAssertEqual(item.level, .warning)
    }

    func testReadabilityOutOfSafeZoneError() {
        let input = makeInput(textContent: "恭喜", textInSafeZone: false, textContrast: 0.8)
        let item = RedPacketQualityLogic.evaluateReadability(input)
        XCTAssertEqual(item.level, .error)
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
        petCanvasVisible: Double = 1,
        cutoutMetricsAvailable: Bool = true,
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
            petCanvasVisibleRatio: petCanvasVisible,
            cutoutMetricsAvailable: cutoutMetricsAvailable,
            cutoutFragmentationRatio: cutoutFragmentation,
            cutoutBoundaryTouchRatio: cutoutBoundaryTouch
        )
    }
}
