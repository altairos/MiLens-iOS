import XCTest
@testable import MiLensKit
// 显式绑定 RGBColor：macOS 上 Quickdraw（经 XCTest→AppKit 传递导入）有同名 C struct，
// 不限定会报 ambiguous；Linux/WSL2 无此冲突。
import struct MiLensKit.RGBColor

/// BeadPaletteMapper 测试。翻译自源端 shared/.../test/BeadPaletteMapper.test.ets。
final class BeadPaletteMapperTests: XCTestCase {

    private func color(_ id: String, _ r: Int, _ g: Int, _ b: Int) -> BeadColor {
        return BeadColor(id: id, name: id, rgb: RGBColor(r, g, b), symbol: id, brand: "")
    }

    func testMapsPixelsToNearestPaletteColorsAndSkipsEmpty() {
        let palette = [color("black", 0, 0, 0), color("white", 255, 255, 255)]
        let pixels: [UInt8] = [5, 5, 5, 255, 250, 250, 250, 255, 250, 250, 250, 255]
        let empty: [UInt8] = [0, 0, 1]
        let indices = mapToPalette(pixels, w: 3, h: 1, paletteLab: precomputePaletteLab(palette), empty: empty)
        XCTAssertEqual(indices[0], 0)  // 近黑
        XCTAssertEqual(indices[1], 1)  // 近白
        XCTAssertEqual(indices[2], 0)  // empty 保持初始 0
    }

    func testSuppressesColoredPixelInNeutralCorridor() {
        let palette = [color("gray", 120, 120, 120), color("red", 180, 60, 60)]
        let pixels: [UInt8] = [
            120, 120, 120, 255, 150, 100, 100, 255, 120, 120, 120, 255,
            120, 120, 120, 255, 120, 120, 120, 255,
        ]
        let indices = mapToPalette(pixels, w: 5, h: 1, paletteLab: precomputePaletteLab(palette))
        // 中间的偏色像素（150,100,100）被中性走廊抑制 → 映射到 gray(0) 而非 red(1)
        XCTAssertEqual(indices[1], 0)
    }

    func testRemapsNeutralReferencePixelsAwayFromChromaticEntry() {
        let palette = [color("gray", 128, 128, 128), color("red", 220, 40, 40)]
        let paletteLab = precomputePaletteLab(palette)
        var indices: [UInt16] = [1, 1]
        let reference: [UInt8] = [130, 130, 130, 255, 130, 130, 130, 255]
        remapReferenceNeutralPixels(&indices, referencePixels: reference, paletteLab: paletteLab, empty: [0, 1])
        // 格 0 是中性参考 → 重映射到 gray(0)；格 1 是 empty → 不变
        XCTAssertEqual(indices[0], 0)
        XCTAssertEqual(indices[1], 1)
    }

    func testEnforcesNeutralRgbAfterPalettePostProcessing() {
        let palette = [color("gray", 140, 140, 140), color("orange", 230, 100, 20)]
        var indices: [UInt16] = [1]
        let reference: [UInt8] = [145, 140, 135, 255]
        enforceReferenceNeutralRgb(&indices, w: 1, h: 1, referencePixels: reference, palette: palette)
        // 参考是中性（spread=10），当前映射是 orange（spread=210）→ 强制选 gray
        XCTAssertEqual(indices[0], 0)
    }

    func testCleansFinalChromaticFringeUsingClosestNeutral() {
        let palette = [color("gray", 125, 125, 125), color("blue", 30, 90, 230)]
        var indices: [UInt16] = [1]
        let reference: [UInt8] = [128, 126, 124, 255]
        cleanFinalNeutralFringes(&indices, w: 1, h: 1, paletteLab: precomputePaletteLab(palette), sourcePixels: reference)
        // 参考是中性 → blue 被清理为 gray
        XCTAssertEqual(indices[0], 0)
    }
}
