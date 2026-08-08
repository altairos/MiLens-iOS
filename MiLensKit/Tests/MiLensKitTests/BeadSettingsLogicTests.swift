import XCTest
@testable import MiLensKit

/// BeadSettingsLogic 测试。逐条翻译自源端 entry/.../test/BeadSettingsViewModel.test.ets。
final class BeadSettingsLogicTests: XCTestCase {

    func testDefaultBeadSettingsReturnsExpectedDefaults() {
        let s = defaultBeadSettings()
        XCTAssertEqual(s.styleKey, "illustration_v1")
        XCTAssertEqual(s.sizeKey, "standard")
        XCTAssertEqual(s.colorKey, "standard")
        XCTAssertTrue(s.outline)
        XCTAssertTrue(s.denoise)
        XCTAssertTrue(s.cutout)
        XCTAssertEqual(resolveAbstractionLevel(0.5), .high)
    }

    func testApplyStylePresetReturnsValidSettingsForIllustrationV1() {
        let s = applyStylePreset("illustration_v1")
        XCTAssertEqual(s.styleKey, "illustration_v1")
        XCTAssertTrue(!s.sizeKey.isEmpty)
    }

    func testApplyStylePresetReturnsValidSettingsForFaithfulV1() {
        let s = applyStylePreset("faithful_v1")
        XCTAssertEqual(s.styleKey, "faithful_v1")
    }

    func testApplyStylePresetReturnsValidSettingsForBadgeV1() {
        let s = applyStylePreset("badge_v1")
        XCTAssertEqual(s.styleKey, "badge_v1")
    }

    func testApplyStylePresetFallsBackForUnknownPreset() {
        let s = applyStylePreset("unknown_preset")
        XCTAssertEqual(s.styleKey, "unknown_preset")
    }

    func testBuildSummaryProducesNonEmptyString() {
        let s = defaultBeadSettings()
        let summary = buildSummary(s)
        XCTAssertTrue(!summary.isEmpty)
    }

    func testBuildSummaryIncludesSizeDimension() {
        let s = defaultBeadSettings()
        let summary = buildSummary(s)
        XCTAssertTrue(summary.contains("x"))
    }

    func testBuildSummaryReflectsCutoutToggle() {
        let s1 = defaultBeadSettings()
        let summary1 = buildSummary(s1)
        XCTAssertTrue(summary1.contains("subject_only"))

        let s2 = BeadSettings(
            styleKey: s1.styleKey, sizeKey: s1.sizeKey, colorKey: s1.colorKey,
            ditherKey: s1.ditherKey, outline: s1.outline, denoise: s1.denoise,
            cutout: false, abstractLevel: s1.abstractLevel)
        let summary2 = buildSummary(s2)
        XCTAssertTrue(summary2.contains("with_background"))
    }

    func testComputeCellSizeReturnsAtLeast4ForAnyPositiveWidth() {
        XCTAssertGreaterThanOrEqual(computeCellSize(patternWidth: 29), 4)
        XCTAssertGreaterThanOrEqual(computeCellSize(patternWidth: 58), 4)
        XCTAssertGreaterThanOrEqual(computeCellSize(patternWidth: 100), 4)
    }

    func testComputeCellSizeReturnsSmallerCellForLargerPattern() {
        let small = computeCellSize(patternWidth: 29)
        let large = computeCellSize(patternWidth: 100)
        XCTAssertLessThan(large, small)
    }

    func testResolveAbstractionLevelMapsLevelCorrectly() {
        XCTAssertEqual(resolveAbstractionLevel(0.0), .low)
        XCTAssertEqual(resolveAbstractionLevel(0.3), .medium)
        XCTAssertEqual(resolveAbstractionLevel(0.5), .high)
        XCTAssertEqual(resolveAbstractionLevel(0.8), .extreme)
        XCTAssertEqual(resolveAbstractionLevel(1.0), .extreme)
    }

    // MARK: - iOS 边界增强

    func testComputeCellSizeExactValues() {
        // 360 / 29 = 12.41 → floor = 12
        XCTAssertEqual(computeCellSize(patternWidth: 29), 12)
        // 360 / 58 = 6.20 → floor = 6
        XCTAssertEqual(computeCellSize(patternWidth: 58), 6)
        // 360 / 100 = 3.6 → floor = 3, clamp to 4
        XCTAssertEqual(computeCellSize(patternWidth: 100), 4)
    }

    func testBuildSummaryContainsColorLabel() {
        let s = defaultBeadSettings()
        let summary = buildSummary(s)
        // defaultBeadSettings 的 colorKey 是 "standard"，label 是 "标准"
        XCTAssertTrue(summary.contains("标准"))
    }

    func testApplyStylePresetMapsIllustrationSizeToJumbo() {
        // illustration_v1 recommendedSizes = [58]，58 > 52 → "jumbo"
        let s = applyStylePreset("illustration_v1")
        XCTAssertEqual(s.sizeKey, "jumbo")
        // maxColors = 28，28 > 24 且 <= 40 → "detailed"
        XCTAssertEqual(s.colorKey, "detailed")
    }
}
