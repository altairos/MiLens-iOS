import XCTest
@testable import MiLensKit
// 显式绑定 RGBColor：macOS 上 Quickdraw（经 XCTest→AppKit 传递导入）有同名 C struct，
// 不限定会报 ambiguous；Linux/WSL2 无此冲突。
import struct MiLensKit.RGBColor

/// BeadFlowLogic 测试。翻译自源端 entry/.../pages/BeadPatternPage.ets 与
/// components/BeadSettingsPanel.ets / BeadPatternResult.ets 的决策分支；
/// 供 App 层 BeadViewModel 使用的流程编排纯逻辑。
final class BeadFlowLogicTests: XCTestCase {

    // MARK: - 辅助构造

    private func makePattern(colorCounts: [BeadColorCount] = [], totalBeads: Int = 841,
                             width: Int = 29, height: Int = 29) -> BeadPattern {
        return BeadPattern(
            width: width, height: height,
            paletteUsed: [],
            colorCounts: colorCounts,
            score: BeadScore(colorError: 0, detailScore: 0, estimatedDifficulty: 0,
                             level: "medium", totalBeads: totalBeads,
                             colorCount: colorCounts.count, estimatedMinutes: "120"))
    }

    private func makeColorCount(symbol: String, name: String, count: Int,
                                suggestedBuy: Int = 0, rgb: RGBColor = RGBColor(120, 80, 40)) -> BeadColorCount {
        return BeadColorCount(colorId: symbol, name: name, symbol: symbol, rgb: rgb,
                              count: count, suggestedBuyCount: suggestedBuy)
    }

    // MARK: - 生成阶段状态机

    func testCanStartGenerationRejectsGeneratingPhase() {
        XCTAssertTrue(canStartBeadGeneration(.idle))
        XCTAssertFalse(canStartBeadGeneration(.generating(cutoutInProgress: false)))
        XCTAssertFalse(canStartBeadGeneration(.generating(cutoutInProgress: true)))
        XCTAssertTrue(canStartBeadGeneration(.success))
        XCTAssertTrue(canStartBeadGeneration(.failure))
    }

    func testPhaseTitleDistinguishesCutoutAndGenerate() {
        XCTAssertEqual(beadPhaseTitle(.generating(cutoutInProgress: true)), "正在智能抠图...")
        XCTAssertEqual(beadPhaseTitle(.generating(cutoutInProgress: false)), "正在生成拼豆图纸...")
        XCTAssertEqual(beadPhaseTitle(.idle), "")
        XCTAssertEqual(beadPhaseTitle(.success), "")
    }

    func testPhaseSubtitleDistinguishesCutoutAndGenerate() {
        XCTAssertEqual(beadPhaseSubtitle(.generating(cutoutInProgress: true)), "识别宠物轮廓并去除背景")
        XCTAssertEqual(beadPhaseSubtitle(.generating(cutoutInProgress: false)), "分析颜色并匹配拼豆色卡")
        XCTAssertEqual(beadPhaseSubtitle(.idle), "")
    }

    // MARK: - 生成参数装配（resolveBeadGeneration）

    func testResolveDefaultSettingsMatchesIllustrationPreset() {
        let resolved = resolveBeadGeneration(settings: defaultBeadSettings())
        let options = resolved.options
        // standard 尺寸 → 29×29；illustration_v1 + standard 颜色
        XCTAssertEqual(options.targetWidth, 29)
        XCTAssertEqual(options.targetHeight, 29)
        XCTAssertEqual(options.paletteId, "MARD_120")
        XCTAssertEqual(options.mode, "free")
        XCTAssertEqual(options.backgroundMode, "transparent")
        XCTAssertFalse(resolved.isAuto)
        // 29×29 网格约束：maxColors = min(24, 14)
        XCTAssertEqual(options.maxColors, 14)
        // 小尺寸强制无抖动 + 去噪
        XCTAssertEqual(options.dithering, "none")
        XCTAssertTrue(options.denoise)
        XCTAssertTrue(options.outline)
        XCTAssertEqual(resolved.recipe.presetId, "illustration_v1")
    }

    func testResolveSizeKeyChangesGridSize() {
        let settings = BeadSettings(styleKey: "illustration_v1", sizeKey: "large",
                                    colorKey: "standard", ditherKey: "none",
                                    outline: true, denoise: true, cutout: true, abstractLevel: 0.5)
        let options = resolveBeadGeneration(settings: settings).options
        XCTAssertEqual(options.targetWidth, 52)
        // 52×52 网格约束：min(24, 40) = 24
        XCTAssertEqual(options.maxColors, 24)
    }

    func testResolveJumboSizeAllowsMoreColors() {
        let settings = BeadSettings(styleKey: "faithful_v1", sizeKey: "jumbo",
                                    colorKey: "realistic", ditherKey: "none",
                                    outline: true, denoise: true, cutout: true, abstractLevel: 0.5)
        let resolved = resolveBeadGeneration(settings: settings)
        XCTAssertEqual(resolved.options.targetWidth, 78)
        // faithful 60 色 + realistic 60 色 → 78×78 上限 60
        XCTAssertEqual(resolved.options.maxColors, 60)
        XCTAssertEqual(resolved.options.paletteId, "MARD_221")
        XCTAssertEqual(resolved.options.mode, "free")
    }

    func testResolveColorKeyChangesPalette() {
        let settings = BeadSettings(styleKey: "illustration_v1", sizeKey: "standard",
                                    colorKey: "simple", ditherKey: "none",
                                    outline: true, denoise: true, cutout: true, abstractLevel: 0.5)
        let options = resolveBeadGeneration(settings: settings).options
        XCTAssertEqual(options.paletteId, "MARD_72")
        // simple 12 色 → 29×29 上限 14，取 12
        XCTAssertEqual(options.maxColors, 12)
    }

    func testResolveUnknownStyleKeyFallsBackToIllustration() {
        var settings = defaultBeadSettings()
        settings.styleKey = "no_such_style"
        let resolved = resolveBeadGeneration(settings: settings)
        XCTAssertEqual(resolved.recipe.presetId, "illustration_v1")
    }

    func testResolveAutoColorKeyMarksAuto() {
        let settings = BeadSettings(styleKey: "illustration_v1", sizeKey: "standard",
                                    colorKey: "auto", ditherKey: "none",
                                    outline: true, denoise: true, cutout: true, abstractLevel: 0.5)
        let resolved = resolveBeadGeneration(settings: settings)
        XCTAssertTrue(resolved.isAuto)
    }

    func testResolveBadgeStyleKeepsCircularCropMode() {
        let settings = BeadSettings(styleKey: "badge_v1", sizeKey: "standard",
                                    colorKey: "simple", ditherKey: "none",
                                    outline: true, denoise: true, cutout: true, abstractLevel: 0.5)
        let options = resolveBeadGeneration(settings: settings).options
        XCTAssertEqual(options.mode, "badge")
        // badge 16 色 + simple 12 色 → 12
        XCTAssertEqual(options.maxColors, 12)
    }

    func testResolveWithNilStylizedDraftDoesNotCrash() {
        // 内置预设均无 stylizedDraft；注入分支应跳过（与源端 `if (options.stylizedDraft)` 一致）
        let resolved = resolveBeadGeneration(settings: defaultBeadSettings())
        XCTAssertNil(resolved.options.stylizedDraft)
    }

    // MARK: - 结果展示决策

    func testClampCanvasScaleBounds() {
        XCTAssertEqual(clampBeadCanvasScale(0.1), 0.5)
        XCTAssertEqual(clampBeadCanvasScale(5.5), 5.0)
        XCTAssertEqual(clampBeadCanvasScale(2.0), 2.0)
        XCTAssertEqual(clampBeadCanvasScale(0.5), 0.5)
        XCTAssertEqual(clampBeadCanvasScale(5.0), 5.0)
    }

    func testStepCanvasScaleStepsByQuarter() {
        XCTAssertEqual(stepBeadCanvasScale(1.0, delta: 0.25), 1.25)
        XCTAssertEqual(stepBeadCanvasScale(1.0, delta: -0.25), 0.75)
        // 边界钳制
        XCTAssertEqual(stepBeadCanvasScale(0.4, delta: -0.25), 0.5)
        XCTAssertEqual(stepBeadCanvasScale(4.9, delta: 0.25), 5.0)
    }

    func testNormalizeViewModeKeepsKnownModes() {
        XCTAssertEqual(normalizeBeadViewMode("color"), "color")
        XCTAssertEqual(normalizeBeadViewMode("letter"), "letter")
        XCTAssertEqual(normalizeBeadViewMode("mard"), "mard")
    }

    func testNormalizeViewModeFallsBackToColor() {
        XCTAssertEqual(normalizeBeadViewMode("bogus"), "color")
        XCTAssertEqual(normalizeBeadViewMode(""), "color")
    }

    func testBadgeDrawOptionsOnlyForBadgeStyle() {
        let pattern = makePattern()
        XCTAssertNotNil(beadDrawOptions(styleKey: "badge_v1", pattern: pattern))
        XCTAssertNil(beadDrawOptions(styleKey: "illustration_v1", pattern: pattern))
        XCTAssertNil(beadDrawOptions(styleKey: "badge_v1", pattern: nil))
    }

    func testBadgeDrawOptionsUseCircularCropAndDerivedBorder() {
        let pattern = makePattern(colorCounts: [
            makeColorCount(symbol: "A1", name: "黑", count: 500, rgb: RGBColor(40, 40, 40)),
        ])
        let opts = beadDrawOptions(styleKey: "badge_v1", pattern: pattern)
        XCTAssertEqual(opts?.circularCrop, true)
        // deriveBadgeBorderColor：主导色加深 0.55
        XCTAssertEqual(opts?.borderColor, "rgb(22,22,22)")
    }

    func testBadgeExportOptionsOnlyForBadgeStyle() {
        let pattern = makePattern()
        XCTAssertNotNil(beadExportOptions(styleKey: "badge_v1", pattern: pattern))
        XCTAssertNil(beadExportOptions(styleKey: "cute_v1", pattern: pattern))
        XCTAssertNil(beadExportOptions(styleKey: "badge_v1", pattern: nil))
    }

    func testStatsLineFormatsSummary() {
        let pattern = makePattern(totalBeads: 841)
        XCTAssertEqual(beadStatsLine(pattern), "29x29 | 841 颗 | 0 色 | 预计 120 分钟")
    }

    // MARK: - 材料清单

    func testMaterialRowsLetterFromA() {
        let pattern = makePattern(colorCounts: [
            makeColorCount(symbol: "C1", name: "米白", count: 300, suggestedBuy: 2),
            makeColorCount(symbol: "D2", name: "橘", count: 120, suggestedBuy: 1),
            makeColorCount(symbol: "E3", name: "深棕", count: 60, suggestedBuy: 1),
        ])
        let rows = beadMaterialRows(pattern)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map(\.letter), ["A", "B", "C"])
        XCTAssertEqual(rows.map(\.symbol), ["C1", "D2", "E3"])
        XCTAssertEqual(rows.map(\.name), ["米白", "橘", "深棕"])
        XCTAssertEqual(rows.map(\.count), [300, 120, 60])
        XCTAssertEqual(rows.map(\.suggestedBuyCount), [2, 1, 1])
        XCTAssertEqual(rows[0].id, "AC1")
    }

    func testMaterialRowsEmptyPattern() {
        XCTAssertEqual(beadMaterialRows(makePattern()), [])
    }

    // MARK: - 概括度文案

    func testAbstractionLevelLabelBoundaries() {
        XCTAssertEqual(abstractionLevelLabel(0.0), "精细")
        XCTAssertEqual(abstractionLevelLabel(0.2), "精细")
        XCTAssertEqual(abstractionLevelLabel(0.3), "适中")
        XCTAssertEqual(abstractionLevelLabel(0.5), "适中")
        XCTAssertEqual(abstractionLevelLabel(0.6), "概括")
        XCTAssertEqual(abstractionLevelLabel(0.8), "概括")
        XCTAssertEqual(abstractionLevelLabel(0.9), "极简")
        XCTAssertEqual(abstractionLevelLabel(1.0), "极简")
    }

    // MARK: - 导出决策与文案

    func testCanStartExportGuards() {
        XCTAssertTrue(canStartBeadExport(isExporting: false, hasPattern: true))
        XCTAssertFalse(canStartBeadExport(isExporting: true, hasPattern: true))
        XCTAssertFalse(canStartBeadExport(isExporting: false, hasPattern: false))
        XCTAssertFalse(canStartBeadExport(isExporting: true, hasPattern: false))
    }

    func testToastTexts() {
        XCTAssertEqual(beadToastText(.missingSource), "未找到来源照片，请返回后重新进入")
        XCTAssertEqual(beadToastText(.generationLimitReached), "今日免费生成次数已用完，升级 MiLens Pro 可不限次数生成")
        XCTAssertEqual(beadToastText(.generationFailed), "生成失败，请重试或关闭智能抠图")
        XCTAssertEqual(beadToastText(.exportSuccess), "✅ 高清图纸已保存到相册")
        XCTAssertEqual(beadToastText(.exportFailed), "❌ 导出失败，请重试")
    }

    // MARK: - 与既有 BeadSettingsLogic 的组合行为

    func testApplyStylePresetThenResolveKeepsConsistency() {
        let settings = applyStylePreset("badge_v1")
        XCTAssertEqual(settings.sizeKey, "large") // recommendedSizes [40] → large
        XCTAssertEqual(settings.colorKey, "standard") // badge 16 色 → standard（12 < 16 ≤ 24）
        XCTAssertTrue(settings.cutout)
        let resolved = resolveBeadGeneration(settings: settings)
        XCTAssertEqual(resolved.options.targetWidth, 52)
        XCTAssertEqual(resolved.options.mode, "badge")
    }

    func testBuildSummaryAfterApplyStylePreset() {
        let settings = applyStylePreset("faithful_v1")
        // faithful recommendedSizes [80] → jumbo；60 色 → realistic
        XCTAssertEqual(settings.sizeKey, "jumbo")
        XCTAssertEqual(settings.colorKey, "realistic")
        XCTAssertEqual(buildSummary(settings), "78x78 | 高还原 | subject_only")
    }
}
