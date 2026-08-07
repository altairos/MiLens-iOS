import XCTest
@testable import MiLensKit

/// BeadPatternStructure 测试。翻译自源端 shared/.../test/BeadPatternStructure.test.ets。
/// finalizeNativePattern 依赖 drawOutline（未迁移），其 2 个用例暂跳过。
final class BeadPatternStructureTests: XCTestCase {

    private func color(_ id: String, _ value: Int) -> BeadColor {
        return BeadColor(id: id, name: id, rgb: RGBColor(value, value, value), symbol: id, brand: "")
    }

    private func patternRef(_ indices: [UInt16], _ width: Int, _ height: Int, _ palette: [BeadColor]) -> BeadPatternRef {
        return BeadPatternRef(width: width, height: height, indices: indices,
                              empty: [UInt8](repeating: 0, count: indices.count),
                              paletteUsed: palette,
                              score: BeadScore(colorError: 0, detailScore: 0, estimatedDifficulty: 0, level: "", totalBeads: indices.count, colorCount: 0, estimatedMinutes: ""))
    }

    func testReturnsDominantIndicesByUsageWhileExcludingEmptyCells() {
        let indices: [UInt16] = [2, 1, 2, 0, 1, 2, 0]
        let result = computeTopDominantIndices(indices: indices, empty: [0, 0, 0, 1, 0, 0, 0], topN: 2)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], 2)  // 色 2 出现 3 次（排除 empty 后）
        XCTAssertEqual(result[1], 1)  // 色 1 出现 2 次
    }

    func testRestoresBrightEyeHighlightSurroundedByDarkCells() {
        let palette = [color("dark", 10), color("white", 250)]
        var indices = [UInt16](repeating: 0, count: 9)
        // 3×3 全暗色 grid，原图中心格为亮白
        var original = [UInt8](repeating: 0, count: 36)
        for i in 0..<9 { original[i * 4 + 3] = 255 }  // alpha
        original[16] = 255; original[17] = 255; original[18] = 255  // 中心 RGB=白

        applyEyeHighlight(&indices, w: 3, h: 3, palette: palette, originalPixels: original,
                          empty: [UInt8](repeating: 0, count: 9), faceRoi: CropArea(x: 0, y: 0, w: 3, h: 3))
        // 中心格 idx=4（原图高光）应被替换为最亮色（index 1 = white）
        XCTAssertEqual(indices[4], 1)
    }

    func testDoesNotAlterEyeCandidatesWithoutFaceRoiOrWhenEmpty() {
        let palette = [color("dark", 10), color("white", 250)]
        var original = [UInt8](repeating: 0, count: 36)
        original[16] = 255; original[17] = 255; original[18] = 255

        // 无 ROI → 不修改
        var noRoi = [UInt16](repeating: 0, count: 9)
        applyEyeHighlight(&noRoi, w: 3, h: 3, palette: palette, originalPixels: original,
                          empty: [UInt8](repeating: 0, count: 9))
        XCTAssertEqual(noRoi[4], 0)

        // 中心格 empty → 跳过
        var emptyMask = [UInt8](repeating: 0, count: 9)
        emptyMask[4] = 1
        var skipped = [UInt16](repeating: 0, count: 9)
        applyEyeHighlight(&skipped, w: 3, h: 3, palette: palette, originalPixels: original,
                          empty: emptyMask, faceRoi: CropArea(x: 0, y: 0, w: 3, h: 3))
        XCTAssertEqual(skipped[4], 0)
    }

    func testRefreshesStructuralDiagnosticsWhilePreservingColorErrorMetrics() {
        var value = patternRef([0, 0, 1], 3, 1, [color("fur_dark", 5), color("white", 250)])
        value.diagnostics = PatternDiagnostics(
            averageDeltaE: 3.2, maxDeltaE: 7, usedColorCount: 0, tinyColorCount: 0,
            isolatedPixelRatio: 0, neutralHueShiftRatio: 0.25, whiteToCoolRatio: 0.5
        )
        refreshStructuralDiagnostics(&value)
        // 保留之前的色差和 hue 指标
        XCTAssertEqual(value.diagnostics?.averageDeltaE, 3.2)
        XCTAssertEqual(value.diagnostics?.usedColorCount, 2)
        XCTAssertEqual(value.diagnostics?.outlineCoverageRatio, 0.667)  // fur_dark 占 2/3
        XCTAssertEqual(value.diagnostics?.blackCoverageRatio, 0.667)   // L(5)<20 占 2/3
    }
}
