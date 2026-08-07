import XCTest
@testable import MiLensKit

/// BeadRenderer 测试。翻译自源端 shared/.../test/BeadRenderer.test.ets。
final class BeadRendererTests: XCTestCase {

    private func colorCount(_ id: String, _ r: Int, _ g: Int, _ b: Int, count: Int = 1) -> BeadColorCount {
        return BeadColorCount(colorId: id, name: id, symbol: id,
                              rgb: RGBColor(r, g, b), count: count,
                              suggestedBuyCount: count)
    }

    private func patternWith(_ counts: [BeadColorCount]) -> BeadPattern {
        return BeadPattern(colorCounts: counts)
    }

    // MARK: - deriveBadgeBorderColor

    func testReturnsDefaultWhenColorCountsIsEmpty() {
        XCTAssertEqual(deriveBadgeBorderColor(patternWith([])), "#333333")
    }

    func testDarkensBrightDominantColorByFactor() {
        // 255 * 0.55 = 140.25 -> rounded to 140
        let c = deriveBadgeBorderColor(patternWith([colorCount("white", 255, 255, 255)]))
        XCTAssertEqual(c, "rgb(140,140,140)")
    }

    func testDarkensEachRGBChannelIndependently() {
        // 200*0.55=110, 100*0.55=55, 50*0.55=27.5->28
        let c = deriveBadgeBorderColor(patternWith([colorCount("orange", 200, 100, 50)]))
        XCTAssertEqual(c, "rgb(110,55,28)")
    }

    func testAlwaysPicksFirstDominantColorIgnoringRest() {
        // first color is dark gray; second brighter red must NOT be used
        let c = deriveBadgeBorderColor(patternWith([
            colorCount("gray", 100, 100, 100, count: 100),
            colorCount("red", 255, 0, 0, count: 1)
        ]))
        // 100*0.55=55
        XCTAssertEqual(c, "rgb(55,55,55)")
    }

    func testRoundsHalfValuesUpViaMathRound() {
        // 1*0.55=0.55->1, 3*0.55=1.65->2, 5*0.55=2.75->3
        let c = deriveBadgeBorderColor(patternWith([colorCount("low", 1, 3, 5)]))
        XCTAssertEqual(c, "rgb(1,2,3)")
    }

    // MARK: - calcPatternSize

    func testCalcPatternSizeReturnsCorrectDimensions() {
        let pattern = BeadPattern(width: 29, height: 58)
        let size = calcPatternSize(pattern, cellSize: 8)
        XCTAssertEqual(size.width, 232)
        XCTAssertEqual(size.height, 464)
    }
}
