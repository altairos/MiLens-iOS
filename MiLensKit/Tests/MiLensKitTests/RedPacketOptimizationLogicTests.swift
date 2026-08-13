import XCTest
@testable import MiLensKit

// RedPacketOptimizationLogicTests — 智能优化纯逻辑测试（对应红包封面开发计划 §4）。
final class RedPacketOptimizationLogicTests: XCTestCase {

    private var defaultTemplate: RedPacketTemplate { RedPacketTemplateCatalog.firstFreeTemplate }

    // MARK: - 生成优化方案

    func testNoOptimizationForCleanReport() {
        let report = RedPacketQualityReport(items: [
            RedPacketQualityItem(dimension: .clarity, level: .pass, detail: "", suggestionKey: ""),
            RedPacketQualityItem(dimension: .brightness, level: .pass, detail: "", suggestionKey: ""),
            RedPacketQualityItem(dimension: .composition, level: .pass, detail: "", suggestionKey: ""),
            RedPacketQualityItem(dimension: .cutout, level: .pass, detail: "", suggestionKey: ""),
            RedPacketQualityItem(dimension: .readability, level: .pass, detail: "", suggestionKey: ""),
        ])

        let result = RedPacketOptimizationLogic.generateOptimization(
            report: report, template: defaultTemplate,
            petLayer: nil, textLayer: nil
        )
        // 干净报告不应有额外优化（对比度提升只在 hasIssues 时）
        XCTAssertEqual(result.brightnessAdjust, 0)
        XCTAssertEqual(result.petNewX, nil)
    }

    func testSharpenForClarityIssue() {
        let report = RedPacketQualityReport(items: [
            RedPacketQualityItem(dimension: .clarity, level: .warning, detail: "", suggestionKey: "redpacket.quality.clarity.soft"),
        ])

        let result = RedPacketOptimizationLogic.generateOptimization(
            report: report, template: defaultTemplate,
            petLayer: nil, textLayer: nil
        )
        XCTAssertGreaterThan(result.sharpnessAdjust, 0)
        XCTAssertTrue(result.summaryKeys.contains("redpacket.optimize.sharpened"))
    }

    func testBrightenForDarkPhoto() {
        let report = RedPacketQualityReport(items: [
            RedPacketQualityItem(dimension: .brightness, level: .warning, detail: "", suggestionKey: "redpacket.quality.brightness.dark"),
        ])

        let result = RedPacketOptimizationLogic.generateOptimization(
            report: report, template: defaultTemplate,
            petLayer: nil, textLayer: nil
        )
        XCTAssertGreaterThan(result.brightnessAdjust, 0)
        XCTAssertTrue(result.summaryKeys.contains("redpacket.optimize.brightened"))
    }

    func testRepositionPetOutOfSafeZone() {
        let report = RedPacketQualityReport(items: [
            RedPacketQualityItem(dimension: .composition, level: .error, detail: "", suggestionKey: "redpacket.quality.composition.safezone"),
        ])

        let petLayer = makeRedPacketPetLayer(x: 10, y: 1200) // 偏离安全区
        let result = RedPacketOptimizationLogic.generateOptimization(
            report: report, template: defaultTemplate,
            petLayer: petLayer, textLayer: nil
        )
        XCTAssertNotNil(result.petNewX)
        XCTAssertNotNil(result.petNewY)
        XCTAssertTrue(result.summaryKeys.contains("redpacket.optimize.petRepositioned"))
    }

    func testRepositionTextOutOfSafeZone() {
        let report = RedPacketQualityReport(items: [
            RedPacketQualityItem(dimension: .readability, level: .error, detail: "", suggestionKey: "redpacket.quality.readability.zone"),
        ])

        let textLayer = makeRedPacketTextLayer(text: "恭喜", x: 100, y: 1200)
        let result = RedPacketOptimizationLogic.generateOptimization(
            report: report, template: defaultTemplate,
            petLayer: nil, textLayer: textLayer
        )
        XCTAssertNotNil(result.textNewX)
        XCTAssertNotNil(result.textNewY)
        XCTAssertTrue(result.summaryKeys.contains("redpacket.optimize.textRepositioned"))
    }

    // MARK: - 应用优化

    func testApplyOptimizationMovesPet() {
        let petLayer = makeRedPacketPetLayer(x: 10, y: 10)
        let optimization = RedPacketOptimizationResult(
            petNewX: 500,
            petNewY: 600
        )

        let updated = RedPacketOptimizationLogic.applyOptimization(
            optimization, layers: [petLayer]
        )
        let updatedPet = updated.first { $0.kind == .pet }
        XCTAssertEqual(updatedPet?.x, 500)
        XCTAssertEqual(updatedPet?.y, 600)
    }

    func testApplyOptimizationMovesText() {
        let textLayer = makeRedPacketTextLayer(text: "恭喜", x: 10, y: 10)
        let optimization = RedPacketOptimizationResult(
            textNewX: 400,
            textNewY: 500
        )

        let updated = RedPacketOptimizationLogic.applyOptimization(
            optimization, layers: [textLayer]
        )
        let updatedText = updated.first { $0.kind == .text }
        XCTAssertEqual(updatedText?.x, 400)
        XCTAssertEqual(updatedText?.y, 500)
    }

    func testApplyOptimizationPreservesOtherLayers() {
        let bg = makeRedPacketTemplateBackgroundLayer()
        let petLayer = makeRedPacketPetLayer(x: 100, y: 100)
        let optimization = RedPacketOptimizationResult(petNewX: 500, petNewY: 600)

        let updated = RedPacketOptimizationLogic.applyOptimization(
            optimization, layers: [bg, petLayer]
        )
        let bg2 = updated.first { $0.kind == .templateBackground }
        XCTAssertEqual(bg2?.x, bg.x) // 背景不变
    }

    func testApplyOptimizationBrightnessAdjust() {
        var petLayer = makeRedPacketPetLayer(x: 100, y: 100)
        petLayer.opacity = 0.8
        let optimization = RedPacketOptimizationResult(brightnessAdjust: 0.15)

        let updated = RedPacketOptimizationLogic.applyOptimization(
            optimization, layers: [petLayer]
        )
        let updatedPet = updated.first { $0.kind == .pet }
        XCTAssertGreaterThan(updatedPet?.opacity ?? 0, 0.8) // 提亮后 opacity 增加
    }

    // MARK: - 默认优化

    func testDefaultGentleOptimization() {
        let result = RedPacketOptimizationLogic.defaultGentleOptimization(
            template: defaultTemplate, petLayer: nil, textLayer: nil
        )
        XCTAssertTrue(result.hasOptimizations)
        XCTAssertGreaterThan(result.sharpnessAdjust, 0)
        XCTAssertTrue(result.summaryKeys.contains("redpacket.optimize.gentleApplied"))
    }

    // MARK: - hasOptimizations

    func testHasOptimizationsTrue() {
        let opt = RedPacketOptimizationResult(contrastAdjust: 0.1)
        XCTAssertTrue(opt.hasOptimizations)
    }

    func testHasOptimizationsFalse() {
        let opt = RedPacketOptimizationResult()
        XCTAssertFalse(opt.hasOptimizations)
    }
}
