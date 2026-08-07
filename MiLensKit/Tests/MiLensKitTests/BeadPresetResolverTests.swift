import XCTest
@testable import MiLensKit

/// BeadPresetResolver 测试。翻译自源端 shared/.../test/BeadPresetResolver.test.ets。
/// 注意：BEAD_EFFECT_PRESETS 是模块级全局注册表，loadFromJsonText 会替换它，
/// 因此每个相关 test 末尾必须调用 resetToBuiltIns() 还原。
final class BeadPresetResolverTests: XCTestCase {

    /// 抓取当前注册表里 illustration_v1 的 maxColors，作为基准值。
    private func builtinIllustrationMaxColors() -> Int {
        for preset in BEAD_EFFECT_PRESETS {
            if preset.id == "illustration_v1" { return preset.generation.maxColors }
        }
        return -1
    }

    /// 把单个 generation 序列化为 JSON 片段。
    private func genJson(_ g: BeadGenerationPreset) -> String {
        let fields: [String] = [
            "\"paletteId\":\"\(g.paletteId)\"",
            "\"maxColors\":\(g.maxColors)",
            "\"mode\":\"\(g.mode)\"",
            "\"backgroundMode\":\"\(g.backgroundMode)\"",
            "\"outline\":\(g.outline)",
            "\"dithering\":\"\(g.dithering)\"",
            "\"denoise\":\(g.denoise)",
            "\"preserveBrightness\":\(g.preserveBrightness)",
            "\"useSubjectCutout\":\(g.useSubjectCutout)",
            "\"outlineStrength\":\(g.outlineStrength)",
            "\"saturationBoost\":\(g.saturationBoost)",
            "\"contrastBoost\":\(g.contrastBoost)",
            "\"shadowLift\":\(g.shadowLift)",
            "\"cleanupSmallRegionMinSize\":\(g.cleanupSmallRegionMinSize)",
            "\"tinyColorUsageRatio\":\(g.tinyColorUsageRatio)",
            "\"lightnessBucketCoverage\":\(g.lightnessBucketCoverage)",
            "\"petFriendlyPenalty\":\(g.petFriendlyPenalty)",
            "\"outlineDrawMode\":\"\(g.outlineDrawMode)\"",
            "\"featureProtectionStrength\":\(g.featureProtectionStrength)",
            "\"autoWhiteBalanceStrength\":\(g.autoWhiteBalanceStrength)",
            "\"vibranceBoost\":\(g.vibranceBoost)",
            "\"brightnessBoost\":\(g.brightnessBoost)",
            "\"neutralGuardStrength\":\(g.neutralGuardStrength)",
            "\"highlightProtectStrength\":\(g.highlightProtectStrength)",
            "\"subjectLocalContrast\":\(g.subjectLocalContrast)",
            "\"backgroundDesaturation\":\(g.backgroundDesaturation)",
            "\"backgroundBlurStrength\":\(g.backgroundBlurStrength)",
        ]
        return "{\(fields.joined(separator: ","))}"
    }

    /// 构造一个预设的 JSON 文本。
    private func presetJson(_ id: String, _ generation: BeadGenerationPreset) -> String {
        return "{" +
            "\"id\":\"\(id)\"," +
            "\"version\":1," +
            "\"name\":\"n\"," +
            "\"description\":\"d\"," +
            "\"recommended\":true," +
            "\"recommendedSizes\":[58]," +
            "\"generation\":\(genJson(generation))" +
        "}"
    }

    override func tearDown() {
        // 确保 BEAD_EFFECT_PRESETS 在每个 test 后恢复内置状态
        BeadPresetResolver.resetToBuiltIns()
        super.tearDown()
    }

    // MARK: - getEffect / normalizePresetId

    func testGetEffectReturnsMatchedPresetByExactId() {
        let preset = BeadPresetResolver.getEffect("faithful_v1")
        XCTAssertEqual(preset.id, "faithful_v1")
        XCTAssertGreaterThan(preset.name.count, 0)
    }

    func testGetEffectFallsBackToIllustrationForUnknownId() {
        let preset = BeadPresetResolver.getEffect("does_not_exist")
        XCTAssertEqual(preset.id, "illustration_v1")
    }

    // MARK: - resolve: gridSize 边界

    func testResolveClampsGridSizeBelowMinimumTo16() {
        let resolved = BeadPresetResolver.resolve("illustration_v1", gridSize: 5)
        XCTAssertEqual(resolved.options.targetWidth, 16)
        XCTAssertEqual(resolved.options.targetHeight, 16)
    }

    func testResolveClampsGridSizeAboveMaximumTo80() {
        let resolved = BeadPresetResolver.resolve("illustration_v1", gridSize: 9999)
        XCTAssertEqual(resolved.options.targetWidth, 80)
    }

    // MARK: - applyGridConstraints 强制降级

    func testResolveCapsMaxColorsTo14ForSmallGrid() {
        let resolved = BeadPresetResolver.resolve("illustration_v1", gridSize: 29)
        XCTAssertLessThanOrEqual(resolved.options.maxColors, 14)
        XCTAssertEqual(resolved.options.dithering, "none")
        XCTAssertTrue(resolved.options.denoise)
        XCTAssertLessThanOrEqual(resolved.options.subjectLocalContrast, 0.10)
        XCTAssertLessThanOrEqual(resolved.options.outlineStrength, 0.55)
    }

    func testResolveDowngradesOutlineDrawModeBlackToDarkAtSmallGridSizes() {
        var overrides = BeadGenerationOverrides()
        overrides.outlineDrawMode = "black"
        let resolved = BeadPresetResolver.resolve("cute_v1", gridSize: 29, overrides: overrides)
        XCTAssertEqual(resolved.options.outlineDrawMode, "dark")
    }

    func testResolveDowngradesOuterBlackToOuterDarkAtSmallGridSizes() {
        var overrides = BeadGenerationOverrides()
        overrides.outlineDrawMode = "outer_black"
        let resolved = BeadPresetResolver.resolve("badge_v1", gridSize: 29, overrides: overrides)
        XCTAssertEqual(resolved.options.outlineDrawMode, "outer_dark")
    }

    func testResolveCapsMaxColorsTo20ForGrid30To40() {
        let resolved = BeadPresetResolver.resolve("illustration_v1", gridSize: 40)
        XCTAssertLessThanOrEqual(resolved.options.maxColors, 20)
        XCTAssertEqual(resolved.options.dithering, "none")
    }

    func testResolveCapsMaxColorsTo40ForGrid41To58() {
        let resolved = BeadPresetResolver.resolve("illustration_v1", gridSize: 58)
        XCTAssertLessThanOrEqual(resolved.options.maxColors, 40)
    }

    func testResolveCapsMaxColorsTo60ForGridAbove58() {
        let resolved = BeadPresetResolver.resolve("illustration_v1", gridSize: 80)
        XCTAssertLessThanOrEqual(resolved.options.maxColors, 60)
    }

    // MARK: - resolve: options / recipe 返回值结构

    func testResolveReturnsEyeEnhanceAndPreservesPresetId() {
        let resolved = BeadPresetResolver.resolve("faithful_v1", gridSize: 58)
        XCTAssertTrue(resolved.options.eyeEnhance)
        XCTAssertEqual(resolved.recipe.presetId, "faithful_v1")
        XCTAssertGreaterThan(resolved.recipe.algorithmVersion.count, 0)
    }

    func testResolveFlagsIsAutoOnlyWhenPaletteIdIsMard291() {
        var autoOverrides = BeadGenerationOverrides()
        autoOverrides.paletteId = "MARD_291"
        let auto = BeadPresetResolver.resolve("illustration_v1", gridSize: 58, overrides: autoOverrides)
        XCTAssertTrue(auto.isAuto)

        var notAutoOverrides = BeadGenerationOverrides()
        notAutoOverrides.paletteId = "MARD_120"
        let notAuto = BeadPresetResolver.resolve("illustration_v1", gridSize: 58, overrides: notAutoOverrides)
        XCTAssertFalse(notAuto.isAuto)
    }

    // MARK: - overridesFromControls

    func testOverridesFromControlsMapsValidColorKey() {
        let overrides = BeadPresetResolver.overridesFromControls(
            colorKey: "realistic", dithering: "none", outline: true, denoise: false, useSubjectCutout: true)
        let expected = BEAD_COLOR_PRESETS["realistic"]!
        XCTAssertEqual(overrides.paletteId, expected.paletteId)
        XCTAssertEqual(overrides.maxColors, expected.count)
        XCTAssertEqual(overrides.dithering, "none")
        XCTAssertEqual(overrides.outline, true)
        XCTAssertEqual(overrides.denoise, false)
        XCTAssertEqual(overrides.useSubjectCutout, true)
    }

    func testOverridesFromControlsFallsBackToStandardForUnknownKey() {
        let overrides = BeadPresetResolver.overridesFromControls(
            colorKey: "unknown_key", dithering: "adaptive", outline: false, denoise: true, useSubjectCutout: false)
        let fallback = BEAD_COLOR_PRESETS["standard"]!
        XCTAssertEqual(overrides.paletteId, fallback.paletteId)
        XCTAssertEqual(overrides.maxColors, fallback.count)
        XCTAssertEqual(overrides.dithering, "adaptive")
    }

    // MARK: - overrides clamp

    func testResolveClampsOverridesMaxColorsOutOfRange() {
        var tooHigh = BeadGenerationOverrides()
        tooHigh.maxColors = 9999
        let r1 = BeadPresetResolver.resolve("illustration_v1", gridSize: 80, overrides: tooHigh)
        XCTAssertLessThanOrEqual(r1.options.maxColors, 60)

        var tooLow = BeadGenerationOverrides()
        tooLow.maxColors = -5
        let r2 = BeadPresetResolver.resolve("illustration_v1", gridSize: 80, overrides: tooLow)
        XCTAssertGreaterThanOrEqual(r2.options.maxColors, 2)
    }

    func testResolveClampsOverridesOutlineStrengthTo01() {
        var over = BeadGenerationOverrides()
        over.outlineStrength = 5
        let r = BeadPresetResolver.resolve("illustration_v1", gridSize: 80, overrides: over)
        XCTAssertLessThanOrEqual(r.options.outlineStrength, 1)
    }

    func testResolveIgnoresUnsupportedPaletteIdInOverrides() {
        var over = BeadGenerationOverrides()
        over.paletteId = "NOT_A_REAL_PALETTE"
        let r = BeadPresetResolver.resolve("illustration_v1", gridSize: 80, overrides: over)
        XCTAssertEqual(r.options.paletteId, "MARD_120")
    }

    // MARK: - loadFromJsonText / 注册表完整性

    func testResetToBuiltInsRestores5BuiltinPresets() {
        BeadPresetResolver.resetToBuiltIns()
        XCTAssertEqual(BEAD_EFFECT_PRESETS.count, 5)
        let ids = Set(BEAD_EFFECT_PRESETS.map { $0.id })
        XCTAssertTrue(ids.contains("illustration_v1"))
        XCTAssertTrue(ids.contains("faithful_v1"))
        XCTAssertTrue(ids.contains("badge_v1"))
        XCTAssertTrue(ids.contains("full_photo_v1"))
        XCTAssertTrue(ids.contains("cute_v1"))
    }

    func testLoadFromJsonTextRejectsMalformedJson() {
        let before = builtinIllustrationMaxColors()
        XCTAssertFalse(BeadPresetResolver.loadFromJsonText("not a json"))
        XCTAssertFalse(BeadPresetResolver.loadFromJsonText(""))
        XCTAssertEqual(builtinIllustrationMaxColors(), before)
    }

    func testLoadFromJsonTextRejectsWrongSchemaVersion() {
        let before = builtinIllustrationMaxColors()
        let json = "{\"schemaVersion\":99,\"presets\":[]}"
        XCTAssertFalse(BeadPresetResolver.loadFromJsonText(json))
        XCTAssertEqual(builtinIllustrationMaxColors(), before)
    }

    func testLoadFromJsonTextRejectsFewerThan5Presets() {
        let before = builtinIllustrationMaxColors()
        let single = presetJson("illustration_v1", BEAD_EFFECT_PRESETS[0].generation)
        let json = "{\"schemaVersion\":1,\"presets\":[\(single)]}"
        XCTAssertFalse(BeadPresetResolver.loadFromJsonText(json))
        XCTAssertEqual(builtinIllustrationMaxColors(), before)
    }

    func testLoadFromJsonTextRejectsDuplicatePresetIds() {
        let before = builtinIllustrationMaxColors()
        let single = presetJson("illustration_v1", BEAD_EFFECT_PRESETS[0].generation)
        let json = "{\"schemaVersion\":1,\"presets\":[\(single),\(single),\(single),\(single),\(single)]}"
        XCTAssertFalse(BeadPresetResolver.loadFromJsonText(json))
        XCTAssertEqual(builtinIllustrationMaxColors(), before)
    }

    func testLoadFromJsonTextAcceptsValid5PresetConfig() {
        let presets = BEAD_EFFECT_PRESETS.map { presetJson($0.id, $0.generation) }
        let json = "{\"schemaVersion\":1,\"presets\":[\(presets.joined(separator: ","))]}"
        XCTAssertTrue(BeadPresetResolver.loadFromJsonText(json))
        // 成功加载后还原
        BeadPresetResolver.resetToBuiltIns()
        XCTAssertEqual(BEAD_EFFECT_PRESETS.count, 5)
    }
}
