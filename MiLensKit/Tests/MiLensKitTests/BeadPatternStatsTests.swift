import XCTest
@testable import MiLensKit
// 显式绑定 RGBColor：macOS 上 Quickdraw（经 XCTest→AppKit 传递导入）有同名 C struct，
// 不限定会报 ambiguous；Linux/WSL2 无此冲突。
import struct MiLensKit.RGBColor

/// BeadPatternStats 测试。翻译自源端 shared/.../test/BeadPatternStats.test.ets。
final class BeadPatternStatsTests: XCTestCase {

    private func color(_ id: String, _ value: Int) -> BeadColor {
        return BeadColor(id: id, name: id, rgb: RGBColor(value, value, value), symbol: id, brand: "test")
    }

    private func makeCounts(_ amount: Int) -> [BeadColorCount] {
        return (0..<amount).map { i in
            BeadColorCount(colorId: "C\(i)", name: "C\(i)", symbol: "C\(i)",
                           rgb: RGBColor(0, 0, 0), count: 1, suggestedBuyCount: 10)
        }
    }

    func testCountsNonEmptyCellsSortsUsageAndRoundsPurchaseQuantities() {
        let palette = [color("red", 255), color("gray", 128), color("black", 0)]
        let indices: [UInt16] = [0, 1, 0, 2, 0, 1, 1, 1, 1, 1]
        var empty = [UInt8](repeating: 0, count: indices.count)
        empty[3] = 1
        let result = computePatternColorCounts(indices: indices, paletteUsed: palette, empty: empty)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].colorId, "gray")
        XCTAssertEqual(result[0].count, 6)
        XCTAssertEqual(result[0].suggestedBuyCount, 10)
        XCTAssertEqual(result[1].colorId, "red")
        XCTAssertEqual(result[1].count, 3)
    }

    func testRoundsLargerPurchaseQuantitiesUpToPacksOfTen() {
        let indices = [UInt16](repeating: 0, count: 19)
        let result = computePatternColorCounts(indices: indices, paletteUsed: [color("white", 255)])
        XCTAssertEqual(result[0].suggestedBuyCount, 30)
    }

    func testAssignsShortSymbolsByUsageWhilePreservingPaletteOrder() {
        let palette = [color("red", 255), color("gray", 128), color("black", 0)]
        let usage = [
            BeadColorCount(colorId: "black", name: "black", symbol: "black", rgb: RGBColor(0, 0, 0), count: 8, suggestedBuyCount: 10),
            BeadColorCount(colorId: "red", name: "red", symbol: "red", rgb: RGBColor(255, 255, 255), count: 4, suggestedBuyCount: 10),
        ]
        let symbols = generatePatternShortSymbols(paletteUsed: palette, colorCounts: usage)
        XCTAssertEqual(symbols[0], "B")
        XCTAssertEqual(symbols[1], "?")
        XCTAssertEqual(symbols[2], "A")
    }

    func testClassifiesSimpleAndExpertPatternsWithStableTimeEstimates() {
        let easy = computePatternDifficulty(colorCounts: [], totalPixels: 0, w: 20, h: 20)
        XCTAssertEqual(easy.level, "easy")
        XCTAssertEqual(easy.estimatedMinutes, "1~0")
        let expert = computePatternDifficulty(colorCounts: makeCounts(30), totalPixels: 6400, w: 80, h: 80)
        XCTAssertEqual(expert.level, "expert")
        XCTAssertEqual(expert.colorCount, 30)
        XCTAssertEqual(expert.totalBeads, 6400)
        XCTAssertEqual(expert.estimatedMinutes, "149~214")
    }

    func testAppliesLargeGridAndHighColorDifficultySurcharges() {
        let base = computePatternDifficulty(colorCounts: makeCounts(24), totalPixels: 1200, w: 58, h: 58)
        let surcharged = computePatternDifficulty(colorCounts: makeCounts(25), totalPixels: 1200, w: 59, h: 58)
        XCTAssertGreaterThan(surcharged.estimatedDifficulty, base.estimatedDifficulty + 29)
    }
}
