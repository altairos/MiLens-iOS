import XCTest
@testable import MiLensKit

/// BeadDenoise 测试。翻译自源端 shared/.../test/BeadDenoise.test.ets，
/// 并补充边缘覆盖。
final class BeadDenoiseTests: XCTestCase {

    private func color(_ id: String, _ value: Int) -> BeadColor {
        return BeadColor(id: id, name: id, rgb: RGBColor(value, value, value), symbol: id, brand: "")
    }

    // MARK: - 源端用例翻译

    func testReplacesIsolatedPixelWithFourNeighborMode() {
        var indices: [UInt16] = [1, 1, 1, 1, 2, 1, 1, 1, 1]
        removeIsolatedPixels(&indices, w: 3, h: 3)
        XCTAssertEqual(indices[4], 1)
    }

    func testDoesNotReplaceProtectedOrEmptyIsolatedPixels() {
        var protectedIndices: [UInt16] = [1, 1, 1, 1, 2, 1, 1, 1, 1]
        var protect = [UInt8](repeating: 0, count: 9)
        protect[4] = 1
        removeIsolatedPixels(&protectedIndices, w: 3, h: 3, protectMask: protect)
        XCTAssertEqual(protectedIndices[4], 2)

        var emptyIndices: [UInt16] = [1, 1, 1, 1, 3, 1, 1, 1, 1]
        var empty = [UInt8](repeating: 0, count: 9)
        empty[4] = 1
        removeIsolatedPixels(&emptyIndices, w: 3, h: 3, empty: empty)
        XCTAssertEqual(emptyIndices[4], 3)
    }

    func testMergesSmallUnprotectedRegionIntoSurroundingColor() {
        var indices: [UInt16] = [0, 0, 0, 0, 1, 0, 0, 0, 0]
        mergeSmallRegions(&indices, w: 3, h: 3, minSize: 2,
                          paletteLab: [LabColor(L: 50, a: 0, b: 0), LabColor(L: 52, a: 0, b: 0)])
        XCTAssertEqual(indices[4], 0)
    }

    func testPreservesProtectedSmallRegion() {
        var indices: [UInt16] = [0, 0, 0, 0, 1, 0, 0, 0, 0]
        var protect = [UInt8](repeating: 0, count: 9)
        protect[4] = 1
        mergeSmallRegions(&indices, w: 3, h: 3, minSize: 2, protectMask: protect,
                          paletteLab: [LabColor(L: 50, a: 0, b: 0), LabColor(L: 52, a: 0, b: 0)])
        XCTAssertEqual(indices[4], 1)
    }

    func testReturnsUnchangedPaletteWhenNoColorIsTiny() {
        let palette = [color("a", 0), color("b", 255)]
        var indices: [UInt16] = [0, 0, 1, 1]
        let result = mergeTinyColors(&indices, w: 2, h: 2, paletteUsed: palette, threshold: 2)
        XCTAssertEqual(result.mergedCount, 0)
        XCTAssertEqual(result.paletteUsed.count, 2)
    }

    func testMergesTinyColorAndCompactsPaletteIndices() {
        let palette = [color("a", 0), color("b", 128), color("c", 255)]
        var indices: [UInt16] = [0, 0, 0, 1]
        let result = mergeTinyColors(&indices, w: 2, h: 2, paletteUsed: palette, threshold: 2)
        XCTAssertEqual(result.mergedCount, 1)
        XCTAssertEqual(result.paletteUsed.count, 1)
        XCTAssertEqual(result.indices, [0, 0, 0, 0])
    }

    // MARK: - 补充覆盖

    func testRemoveIsolatedPixelsHandlesAllSameColor() {
        var indices: [UInt16] = [5, 5, 5, 5, 5]
        removeIsolatedPixels(&indices, w: 5, h: 1)
        // 全部同色，无孤立点，不变
        XCTAssertEqual(indices, [5, 5, 5, 5, 5])
    }

    func testMergeSmallRegionsWithLargeMinSizeMergesEverything() {
        // 3×3 网格，中心色 1 被 8 个色 0 包围
        var indices: [UInt16] = [0, 0, 0, 0, 1, 0, 0, 0, 0]
        mergeSmallRegions(&indices, w: 3, h: 3, minSize: 5,
                          paletteLab: [LabColor(L: 50, a: 0, b: 0), LabColor(L: 52, a: 0, b: 0)])
        // minSize=5 → size=1 的 cluster 1 应被合并到色 0
        XCTAssertEqual(indices[4], 0)
    }

    func testMergeTinyColorsWithEmptyCells() {
        let palette = [color("a", 0), color("b", 255)]
        var indices: [UInt16] = [0, 1, 0, 0]
        let empty: [UInt8] = [0, 0, 0, 1]
        let result = mergeTinyColors(&indices, w: 2, h: 2, paletteUsed: palette, threshold: 2, empty: empty)
        // 色 1 只有 1 个像素（< threshold=2），应被合并
        XCTAssertEqual(result.mergedCount, 1)
    }
}
