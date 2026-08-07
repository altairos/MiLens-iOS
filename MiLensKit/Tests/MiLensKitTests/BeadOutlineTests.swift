import XCTest
@testable import MiLensKit

/// BeadOutline 测试。翻译自源端 shared/.../test/BeadOutline.test.ets。
final class BeadOutlineTests: XCTestCase {

    private func color(_ id: String, _ r: Int, _ g: Int, _ b: Int) -> BeadColor {
        return BeadColor(id: id, name: id, rgb: RGBColor(r, g, b), symbol: id, brand: "")
    }

    func testModeNoneReturnsPaletteUnchangedAndLeavesIndicesUntouched() {
        let palette = [color("white", 255, 255, 255), color("red", 200, 50, 50)]
        var indices: [UInt16] = [0, 1, 0]
        let result = drawOutline(&indices, w: 3, h: 1, palette: palette, mode: "none")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(indices, [0, 1, 0])
    }

    func testModeBlackReplacesEveryBorderCellWithDarkestExistingColor() {
        let palette = [color("white", 255, 255, 255), color("black", 0, 0, 0)]
        var indices: [UInt16] = [0, 1, 0]
        let result = drawOutline(&indices, w: 3, h: 1, palette: palette, mode: "black")
        // black L* ≤ 15 → palette 不扩展
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(indices, [1, 1, 1])
    }

    func testModeBlackAppendsNearBlackWhenPaletteHasNothingDarkEnough() {
        let palette = [color("white", 255, 255, 255), color("red", 200, 50, 50)]
        var indices: [UInt16] = [0, 1, 0]
        let result = drawOutline(&indices, w: 3, h: 1, palette: palette, mode: "black")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[2].id, "_outline_black")
        XCTAssertEqual(indices, [2, 2, 2])
    }

    func testModeDarkDarkensEachBorderCellByGroupingOnOriginalColor() {
        let palette = [color("white", 255, 255, 255), color("red", 200, 50, 50)]
        var indices: [UInt16] = [0, 1, 0]
        let result = drawOutline(&indices, w: 3, h: 1, palette: palette, mode: "dark")
        // pos 0,2 原色 white → 同一暗化索引；pos 1 原色 red → 另一暗化索引
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[2].id, "white_dark")
        XCTAssertEqual(result[3].id, "red_dark")
        XCTAssertEqual(indices, [2, 3, 2])
    }

    func testModeOuterBlackOnlyTouchesCellsAdjacentToEmptyCell() {
        let palette = [color("white", 255, 255, 255), color("red", 200, 50, 50)]
        var indices: [UInt16] = [0, 1, 0]
        let empty: [UInt8] = [0, 0, 1]
        let result = drawOutline(&indices, w: 3, h: 1, palette: palette, mode: "outer_black", empty: empty)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[2].id, "_outline_black")
        // 只有 pos 1 是外轮廓（邻空格），pos 0 是内部边界不处理
        XCTAssertEqual(indices, [0, 2, 0])
    }

    func testModeOuterDarkDarkensOnlyOuterBorders() {
        let palette = [color("white", 255, 255, 255), color("red", 200, 50, 50)]
        var indices: [UInt16] = [0, 1, 0]
        let empty: [UInt8] = [0, 0, 1]
        let result = drawOutline(&indices, w: 3, h: 1, palette: palette, mode: "outer_dark", empty: empty)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[2].id, "red_dark")
        XCTAssertEqual(indices, [0, 2, 0])
    }

    func testModeInnerDarkAppliesSoftDarkOnlyToInnerBordersWithoutPose() {
        let palette = [color("white", 255, 255, 255), color("red", 200, 50, 50)]
        var indices: [UInt16] = [0, 1, 0]
        let empty: [UInt8] = [0, 0, 1]
        let result = drawOutline(&indices, w: 3, h: 1, palette: palette, mode: "inner_dark", empty: empty)
        // pos 0 内部边界 → white_dark(idx 2)；pos 1 外轮廓但 innerStyle 只管内部 → 不变
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[2].id, "white_dark")
        XCTAssertEqual(indices, [2, 1, 0])
    }

    func testModeMixedDarkensOuterStronglyAndInnerSoftly() {
        let palette = [color("white", 255, 255, 255), color("red", 200, 50, 50)]
        var indices: [UInt16] = [0, 1, 0]
        let empty: [UInt8] = [0, 0, 1]
        let result = drawOutline(&indices, w: 3, h: 1, palette: palette, mode: "mixed", empty: empty)
        // dark 先跑：red pos 1 → palette[2]='red_dark', indices[1]=2
        // soft_dark 后跑：white pos 0 → palette[3]='white_dark', indices[0]=3
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[2].id, "red_dark")
        XCTAssertEqual(result[3].id, "white_dark")
        XCTAssertEqual(indices, [3, 2, 0])
    }

    func testProtectsMaskedCellsFromAnyOutlineModification() {
        let palette = [color("white", 255, 255, 255), color("red", 200, 50, 50)]
        var indices: [UInt16] = [0, 0, 1, 0, 0]
        let protectMask: [UInt8] = [0, 0, 1, 0, 0]
        let result = drawOutline(&indices, w: 5, h: 1, palette: palette, mode: "black", protectMask: protectMask)
        // pos 2 受保护 → 保持 idx 1；pos 1,3 被暗化为 black
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[2].id, "_outline_black")
        XCTAssertEqual(indices, [0, 2, 1, 2, 0])
    }

    func testReturnsPaletteUnchangedWhenNoBordersDetected() {
        let palette = [color("white", 255, 255, 255)]
        var indices: [UInt16] = [0, 0, 0]
        let result = drawOutline(&indices, w: 3, h: 1, palette: palette, mode: "black")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(indices, [0, 0, 0])
    }

    func testFallsThroughAsNoOpForUnknownMode() {
        let palette = [color("white", 255, 255, 255)]
        var indices: [UInt16] = [0, 1, 0]
        let result = drawOutline(&indices, w: 3, h: 1, palette: palette, mode: "unknown_mode")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(indices, [0, 1, 0])
    }

    func testTreatsEmptyCellsAsTransparentAndSkipsDuringBorderDetection() {
        let palette = [color("white", 255, 255, 255), color("black", 0, 0, 0)]
        var indices: [UInt16] = [0, 0]
        let empty: [UInt8] = [0, 1]
        _ = drawOutline(&indices, w: 2, h: 1, palette: palette, mode: "black", empty: empty)
        // pos 1 空（跳过）；pos 0 外轮廓（邻空格）→ 替换为最暗色 black idx 1
        XCTAssertEqual(indices, [1, 0])
    }
}
