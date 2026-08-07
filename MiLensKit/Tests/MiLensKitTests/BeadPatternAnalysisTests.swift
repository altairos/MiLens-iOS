import XCTest
@testable import MiLensKit

/// BeadPatternAnalysis 测试。翻译自源端 shared/.../test/BeadPatternAnalysis.test.ets。
final class BeadPatternAnalysisTests: XCTestCase {

    private func color(_ id: String, _ r: Int, _ g: Int, _ b: Int) -> BeadColor {
        return BeadColor(id: id, name: id, rgb: RGBColor(r, g, b), symbol: id, brand: "")
    }

    private func solidPixels(_ count: Int, _ r: Int, _ g: Int, _ b: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: count * 4)
        for i in 0..<count {
            result[i * 4] = UInt8(r)
            result[i * 4 + 1] = UInt8(g)
            result[i * 4 + 2] = UInt8(b)
            result[i * 4 + 3] = 255
        }
        return result
    }

    func testMergesTinyColorIntoNearestMainColorAndCompactsPalette() {
        let palette = [color("gray", 100, 100, 100), color("nearGray", 110, 110, 110)]
        let result = mergeTinyColorsByPalette([0, 0, 0, 0, 1], w: 5, h: 1, paletteUsed: palette, threshold: 2)
        XCTAssertEqual(result.mergedCount, 1)
        XCTAssertEqual(result.paletteUsed.count, 1)
        XCTAssertEqual(result.paletteUsed[0].id, "gray")
        XCTAssertEqual(result.indices[4], 0)
    }

    func testDoesNotMergeTinyColorUsedByProtectedCell() {
        let palette = [color("gray", 100, 100, 100), color("detail", 110, 110, 110)]
        let protect: [UInt8] = [0, 0, 0, 0, 1]
        let result = mergeTinyColorsByPalette([0, 0, 0, 0, 1], w: 5, h: 1, paletteUsed: palette, threshold: 2, protectMask: protect)
        XCTAssertEqual(result.mergedCount, 0)
        XCTAssertEqual(result.paletteUsed.count, 2)
        XCTAssertEqual(result.indices[4], 1)
    }

    func testExcludesEmptyCellsFromMergeCountsAndIndexRewriting() {
        let palette = [color("gray", 100, 100, 100), color("unused", 200, 0, 0)]
        let indices: [UInt16] = [0, 0, 1]
        let result = mergeTinyColorsByPalette(indices, w: 3, h: 1, paletteUsed: palette, threshold: 2, empty: [0, 0, 1])
        // 色 1 在 empty=1 格，不计入统计 → mergedCount=0
        XCTAssertEqual(result.mergedCount, 0)
        XCTAssertEqual(result.indices[2], 1)
    }

    func testReportsZeroErrorForUniformExactMatchWithoutIsolatedPixels() {
        let palette = [color("gray", 120, 120, 120)]
        let diagnostics = computeDiagnostics(indices: [0, 0, 0, 0], w: 2, h: 2, paletteUsed: palette, originalPixels: solidPixels(4, 120, 120, 120))
        XCTAssertEqual(diagnostics.averageDeltaE, 0)
        XCTAssertEqual(diagnostics.maxDeltaE, 0)
        XCTAssertEqual(diagnostics.usedColorCount, 1)
        XCTAssertEqual(diagnostics.isolatedPixelRatio, 0)
    }

    func testDetectsIsolatedColorsNeutralHueShiftAndWhiteToCoolMapping() {
        let palette = [color("gray", 128, 128, 128), color("blue", 30, 90, 230)]
        let reference: [UInt8] = [
            128, 128, 128, 255, 245, 245, 245, 255, 128, 128, 128, 255,
        ]
        let diagnostics = computeDiagnostics(indices: [0, 1, 0], w: 3, h: 1, paletteUsed: palette, originalPixels: reference)
        // 3 个格全是孤立（无同色邻居）
        XCTAssertEqual(diagnostics.isolatedPixelRatio, 1)
        XCTAssertNotNil(diagnostics.neutralHueShiftRatio)
        XCTAssertGreaterThan(diagnostics.neutralHueShiftRatio ?? 0, 0)
        XCTAssertNotNil(diagnostics.whiteToCoolRatio)
        XCTAssertGreaterThan(diagnostics.whiteToCoolRatio ?? 0, 0)
    }

    func testCountsOutlineAndBlackCoverageWhileIgnoringEmptyCells() {
        let palette = [color("fur_dark", 5, 5, 5), color("white", 255, 255, 255)]
        let diagnostics = computeDiagnostics(indices: [0, 0, 1], w: 3, h: 1, paletteUsed: palette,
                                             originalPixels: solidPixels(3, 5, 5, 5), empty: [0, 1, 0])
        // empty[1]=1 → 只有 2 个有效格（色 0 和色 1）
        XCTAssertEqual(diagnostics.usedColorCount, 2)
        XCTAssertEqual(diagnostics.outlineCoverageRatio, 0.5)
        XCTAssertEqual(diagnostics.blackCoverageRatio, 0.5)
    }

    func testDoesNotLetEmptyNeighborHideAnIsolatedBead() {
        let palette = [color("gray", 120, 120, 120), color("white", 255, 255, 255)]
        let diagnostics = computeDiagnostics(indices: [0, 0, 1], w: 3, h: 1, paletteUsed: palette,
                                             originalPixels: solidPixels(3, 120, 120, 120), empty: [0, 1, 0])
        // 格 0 和格 2 有效但非相邻（中间 empty），都是孤立的
        XCTAssertEqual(diagnostics.isolatedPixelRatio, 1)
    }
}
