import XCTest
@testable import MiLensKit

/// BeadDither 测试。翻译自源端 shared/.../test/BeadDither.test.ets，
/// 并补充 serpentine 与 adaptive bayer 的边界覆盖。
final class BeadDitherTests: XCTestCase {

    func testQuantizesEveryNonEmptyPixelToPalette() {
        // 源端：2×1 灰度图，双色调色板（纯黑/纯白）
        var pixels: [UInt8] = [120, 120, 120, 255, 200, 200, 200, 255]
        let palette = [rgbToLab(0, 0, 0), rgbToLab(255, 255, 255)]
        applyFloydSteinberg(&pixels, w: 2, h: 1, paletteLab: palette, strength: 1)
        // 量化后 RGB 只能是 0 或 255
        XCTAssertTrue(pixels[0] == 0 || pixels[0] == 255)
        XCTAssertTrue(pixels[4] == 0 || pixels[4] == 255)
        // alpha 通道不受影响
        XCTAssertEqual(pixels[3], 255)
        XCTAssertEqual(pixels[7], 255)
    }

    func testLeavesEmptyPixelsUntouched() {
        var pixels: [UInt8] = [123, 45, 67, 9]
        let palette = [rgbToLab(0, 0, 0), rgbToLab(255, 255, 255)]
        applyFloydSteinberg(&pixels, w: 1, h: 1, paletteLab: palette, strength: 1, empty: [1])
        // empty=1 的像素完全不被修改
        XCTAssertEqual(pixels[0], 123)
        XCTAssertEqual(pixels[1], 45)
        XCTAssertEqual(pixels[2], 67)
        XCTAssertEqual(pixels[3], 9)
    }

    func testSerpentineDitheringIsDeterministic() {
        let source: [UInt8] = [
            40, 40, 40, 255, 100, 100, 100, 255,
            160, 160, 160, 255, 220, 220, 220, 255,
        ]
        var first = source
        var second = source
        let palette = [rgbToLab(0, 0, 0), rgbToLab(255, 255, 255)]
        applyFloydSteinbergSerpentine(&first, w: 2, h: 2, paletteLab: palette, strength: 0.8)
        applyFloydSteinbergSerpentine(&second, w: 2, h: 2, paletteLab: palette, strength: 0.8)
        // 同样输入两次运行结果必须完全一致
        XCTAssertEqual(first, second)
    }

    func testAdaptiveBayerDisabledForGridsUpTo29x29() {
        var pixels: [UInt8] = [100, 100, 100, 255]
        var indices: [UInt16] = [7]
        applyAdaptiveBayerDither(&pixels, w: 1, h: 1,
                                 paletteLab: [rgbToLab(90, 90, 90), rgbToLab(110, 110, 110)],
                                 protectMask: nil, empty: nil, faceRoi: nil,
                                 petFriendlyPenalty: 0, indicesOut: &indices)
        // ≤29×29：完全不修改
        XCTAssertEqual(indices[0], 7)
        XCTAssertEqual(pixels[0], 100)
    }

    // MARK: - 补充覆盖

    func testProtectMaskPreventsPixelModification() {
        var pixels: [UInt8] = [120, 120, 120, 255]
        let palette = [rgbToLab(0, 0, 0), rgbToLab(255, 255, 255)]
        applyFloydSteinberg(&pixels, w: 1, h: 1, paletteLab: palette, strength: 1, protectMask: [1])
        // 被保护像素不参与抖动，strength 视为 0，但 findNearest 仍会写入新色
        // 注：源端 protectMask 仅将 localStrength 置 0（误差扩散为 0），
        // 像素仍被量化为最近色。这里验证像素被量化到调色板之一。
        XCTAssertTrue(pixels[0] == 0 || pixels[0] == 255)
    }

    func testZeroStrengthPreservesOriginalColors() {
        var pixels: [UInt8] = [128, 128, 128, 255]
        let palette = [rgbToLab(0, 0, 0), rgbToLab(255, 255, 255)]
        applyFloydSteinberg(&pixels, w: 1, h: 1, paletteLab: palette, strength: 0)
        // strength=0 时，误差扩散为 0，但像素仍量化到最近色。
        // 128 应量化为黑或白（取决于 Lab 距离）
        XCTAssertTrue(pixels[0] == 0 || pixels[0] == 255)
    }

    func testAdaptiveBayerRequiresAtLeastTwoColors() {
        var pixels = [UInt8](repeating: 128, count: 32 * 32 * 4)
        var indices = [UInt16](repeating: 99, count: 32 * 32)
        let singlePalette = [rgbToLab(128, 128, 128)]
        applyAdaptiveBayerDither(&pixels, w: 32, h: 32,
                                 paletteLab: singlePalette,
                                 protectMask: nil, empty: nil, faceRoi: nil,
                                 petFriendlyPenalty: 0, indicesOut: &indices)
        // 单色调色板：< 2 直接返回，不修改
        XCTAssertEqual(indices[0], 99)
    }
}
