import XCTest
@testable import MiLensKit

/// BeadScoring 测试。翻译自源端 shared/.../test/BeadScoring.test.ets。
final class BeadScoringTests: XCTestCase {

    private func diagnostics(_ avg: Double, _ max: Double, _ colors: Int, _ tiny: Int, _ isolated: Double) -> PatternDiagnostics {
        return PatternDiagnostics(averageDeltaE: avg, maxDeltaE: max, usedColorCount: colors,
                                  tinyColorCount: tiny, isolatedPixelRatio: isolated)
    }

    private func pattern(_ diag: PatternDiagnostics? = nil, difficulty: Double = 20, totalBeads: Int = 64) -> BeadPatternRef {
        let score = BeadScore(colorError: 0, detailScore: 0, estimatedDifficulty: difficulty,
                              level: "", totalBeads: totalBeads, colorCount: 8, estimatedMinutes: "")
        return BeadPatternRef(width: 8, height: 8,
                              indices: [UInt16](repeating: 0, count: 64),
                              empty: [UInt8](repeating: 0, count: 64),
                              paletteUsed: [], score: score, diagnostics: diag)
    }

    func testUsesNeutralDefaultsWhenDiagnosticsUnavailable() {
        let result = computeTriScore(pattern())
        XCTAssertEqual(result.identityScore, 50)
        XCTAssertEqual(result.aestheticScore, 50)
        XCTAssertEqual(result.beadabilityScore, 50)
        XCTAssertEqual(result.overall, 50)
    }

    func testRanksCleanLowErrorAboveNoisyHighError() {
        let clean = computeTriScore(pattern(diagnostics(2, 8, 12, 0, 0.01), difficulty: 10))
        let noisy = computeTriScore(pattern(diagnostics(28, 70, 50, 8, 0.3), difficulty: 70))
        XCTAssertGreaterThan(clean.overall, noisy.overall)
        XCTAssertGreaterThan(clean.identityScore, noisy.identityScore)
        XCTAssertGreaterThan(clean.aestheticScore, noisy.aestheticScore)
    }

    func testKeepsEveryScoreBoundedAndExposesOverallHelper() {
        let p = pattern(diagnostics(15, 40, 24, 3, 0.1), difficulty: 35)
        let result = computeTriScore(p)
        XCTAssertGreaterThanOrEqual(result.identityScore, 0)
        XCTAssertLessThanOrEqual(result.identityScore, 100)
        XCTAssertGreaterThanOrEqual(result.aestheticScore, 0)
        XCTAssertLessThanOrEqual(result.aestheticScore, 100)
        XCTAssertGreaterThanOrEqual(result.beadabilityScore, 0)
        XCTAssertLessThanOrEqual(result.beadabilityScore, 100)
        XCTAssertEqual(triScoreOverall(p), result.overall)
    }

    func testMapsAverageDeltaE15NearMidpoint() {
        let result = computeTriScore(pattern(diagnostics(15, 20, 12, 0, 0), difficulty: 10))
        XCTAssertGreaterThanOrEqual(result.identityScore, 45)
        XCTAssertLessThanOrEqual(result.identityScore, 55)
    }

    func testDoesNotRewardFilledBackgroundsOverTransparentPatterns() {
        let filled = pattern(diagnostics(5, 12, 12, 0, 0.01), difficulty: 10)
        var transparentScore = filled.score
        transparentScore.totalBeads = 24
        let transparent = BeadPatternRef(width: filled.width, height: filled.height,
                                         indices: filled.indices, empty: filled.empty,
                                         paletteUsed: filled.paletteUsed, score: transparentScore,
                                         diagnostics: filled.diagnostics)
        let filledResult = computeTriScore(filled)
        let transparentResult = computeTriScore(transparent)
        XCTAssertEqual(filledResult.identityScore, transparentResult.identityScore, accuracy: 0.01)
    }
}
