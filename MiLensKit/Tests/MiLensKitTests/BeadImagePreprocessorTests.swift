import XCTest
@testable import MiLensKit

/// BeadImagePreprocessor 测试。翻译自源端 shared/.../test/BeadImagePreprocessor.test.ets。
final class BeadImagePreprocessorTests: XCTestCase {

    func testPreservesRgbaPixelsWhenResizingToSameDimensions() {
        let source: [UInt8] = [10, 20, 30, 40, 50, 60, 70, 80]
        let result = areaResizeRgba(source, srcW: 2, srcH: 1, dstW: 2, dstH: 1)
        XCTAssertEqual(result[0], 10)
        XCTAssertEqual(result[3], 40)
        XCTAssertEqual(result[4], 50)
        XCTAssertEqual(result[7], 80)
        // Swift 值类型：返回新数组（拷贝），非同引用
    }

    func testAveragesColorAndAlphaChannelsWhenReducing() {
        let source: [UInt8] = [
            0, 20, 40, 0, 100, 40, 60, 100,
            200, 60, 80, 200, 255, 80, 100, 255,
        ]
        let result = areaResizeRgba(source, srcW: 2, srcH: 2, dstW: 1, dstH: 1)
        XCTAssertEqual(result[0], 139)  // (0+100+200+255)/4 = 138.75 → 139
        XCTAssertEqual(result[1], 50)
        XCTAssertEqual(result[2], 70)
        XCTAssertEqual(result[3], 139)
    }

    func testSharpensContrastInPlaceWithoutChangingAlpha() {
        var pixels: [UInt8] = [0, 0, 0, 10, 100, 100, 100, 20, 255, 255, 255, 30]
        applyUnsharpMask(&pixels, w: 3, h: 1, amount: 1)
        XCTAssertEqual(pixels[0], 0)
        XCTAssertEqual(pixels[4], 82)   // 100 + (100 - round((0+100+255)/3)) = 100 + (100-118) = 82
        XCTAssertEqual(pixels[8], 255)
        XCTAssertEqual(pixels[3], 10)   // alpha 不变
        XCTAssertEqual(pixels[7], 20)
        XCTAssertEqual(pixels[11], 30)
    }

    func testLeavesPixelsUnchangedWithNeutralEnhancementSettings() {
        var pixels: [UInt8] = [80, 120, 160, 255, 20, 30, 40, 127]
        // 源端：enhancePetColors(pixels, 2, 1, 1, 0, 0, 1, 1, 0, 0)
        // saturationBoost=1, contrastBoost=1, shadowLift=0, wbStrength=0,
        // vibrance=1, brightness=1, neutralGuard=0, highlightProtect=0
        enhancePetColors(&pixels, pixelCount: 2,
                         saturationBoost: 1, contrastBoost: 1, shadowLiftAmount: 0,
                         autoWhiteBalanceStrength: 0, vibranceBoost: 1, brightnessBoost: 1,
                         neutralGuardStrength: 0, highlightProtectStrength: 0)
        XCTAssertEqual(pixels[0], 80)
        XCTAssertEqual(pixels[1], 120)
        XCTAssertEqual(pixels[2], 160)
        // alpha < 128 的像素跳过
        XCTAssertEqual(pixels[4], 20)
        XCTAssertEqual(pixels[5], 30)
        XCTAssertEqual(pixels[6], 40)
    }

    func testReducesStrongColorCastWhileSkippingTransparentPixels() {
        var pixels: [UInt8] = [200, 100, 100, 255, 220, 20, 20, 0]
        enhancePetColors(&pixels, pixelCount: 2,
                         saturationBoost: 1, contrastBoost: 0, shadowLiftAmount: 1,
                         autoWhiteBalanceStrength: 1, vibranceBoost: 1, brightnessBoost: 1,
                         neutralGuardStrength: 0, highlightProtectStrength: 0)
        XCTAssertLessThan(pixels[0], 200)   // 红通道被白平衡压低
        XCTAssertGreaterThan(pixels[1], 100) // 绿通道提升
        XCTAssertGreaterThan(pixels[2], 100) // 蓝通道提升
        // 透明像素不变
        XCTAssertEqual(pixels[4], 220)
        XCTAssertEqual(pixels[5], 20)
        XCTAssertEqual(pixels[6], 20)
        XCTAssertEqual(pixels[7], 0)
    }
}
