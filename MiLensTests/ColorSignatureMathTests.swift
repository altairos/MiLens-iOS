import XCTest
@testable import MiLens

/// ColorSignatureMath 纯逻辑测试（对应源端 ColorSignatureMath 相关用例）。
/// 覆盖 hueBin 桶边界与 computeColorSignature 的维度/归一化/降级行为。
final class ColorSignatureMathTests: XCTestCase {

    // MARK: - hueBin

    func testHueBinRedMapsToBucket0() {
        // hue = 0（红）→ 桶 0（hue < 30）
        XCTAssertEqual(ColorSignatureMath.hueBin(r: 1, g: 0, b: 0), 0)
        // 品红（hue = 300）→ 桶 4（255 <= hue < 330）
        XCTAssertEqual(ColorSignatureMath.hueBin(r: 1, g: 0, b: 1), 4)
    }

    func testHueBinOrangeMapsToBucket1() {
        // hue = 30 → 桶 1（30 <= hue < 75）
        XCTAssertEqual(ColorSignatureMath.hueBin(r: 1, g: 0.5, b: 0), 1)
    }

    func testHueBinGreenMapsToBucket2() {
        // hue = 120 → 桶 2（75 <= hue < 165）
        XCTAssertEqual(ColorSignatureMath.hueBin(r: 0, g: 1, b: 0), 2)
    }

    func testHueBinBlueMapsToBucket3() {
        // hue = 240 → 桶 3（165 <= hue < 255）
        XCTAssertEqual(ColorSignatureMath.hueBin(r: 0, g: 0, b: 1), 3)
    }

    func testHueBinPurpleMapsToBucket4() {
        // hue = 300 → 桶 4（255 <= hue < 330）
        XCTAssertEqual(ColorSignatureMath.hueBin(r: 0.5, g: 0, b: 1), 4)
    }

    func testHueBinGrayReturnsBucket0() {
        // r == g == b（无色相）→ 桶 0
        XCTAssertEqual(ColorSignatureMath.hueBin(r: 0.5, g: 0.5, b: 0.5), 0)
        XCTAssertEqual(ColorSignatureMath.hueBin(r: 0.1, g: 0.1, b: 0.1), 0)
    }

    func testHueBinDeepRedAbove330MapsToBucket0() {
        // hue ≈ 354（>= 330）→ 桶 0
        XCTAssertEqual(ColorSignatureMath.hueBin(r: 1, g: 0, b: 0.1), 0)
    }

    // MARK: - computeColorSignature

    func testComputeColorSignaturePureRedImage() {
        // 64x64 全红不透明（RGBA：r=255, g=0, b=0, a=255）
        let pixels = makePixels(width: 64, height: 64) { _, _ in (255, 0, 0, 255) }
        let signature = ColorSignatureMath.computeColorSignature(
            pixelBytes: pixels, width: 64, height: 64, dim: 14)

        XCTAssertEqual(signature.count, 14)
        // [0-2] 加权 RGB 均值：全红 → R≈1, G≈0, B≈0
        XCTAssertEqual(signature[0], 1.0, accuracy: 0.001)
        XCTAssertEqual(signature[1], 0.0, accuracy: 0.001)
        XCTAssertEqual(signature[2], 0.0, accuracy: 0.001)
        // [3] 亮度 ≈ 0.299
        XCTAssertEqual(signature[3], 0.299, accuracy: 0.002)
        // [4] 饱和度 = 1
        XCTAssertEqual(signature[4], 1.0, accuracy: 0.001)
        // [9] 色相桶 0（红）占比 ≈ 1，其余色相桶 ≈ 0
        XCTAssertEqual(signature[9], 1.0, accuracy: 0.001)
        XCTAssertEqual(signature[10], 0.0, accuracy: 0.001)
        XCTAssertEqual(signature[11], 0.0, accuracy: 0.001)
        XCTAssertEqual(signature[12], 0.0, accuracy: 0.001)
        XCTAssertEqual(signature[13], 0.0, accuracy: 0.001)
        // 亮度桶归一化：4 桶之和 ≈ 1
        let lumaSum = signature[5] + signature[6] + signature[7] + signature[8]
        XCTAssertEqual(lumaSum, 1.0, accuracy: 0.001)
    }

    func testComputeColorSignaturePureGrayImageNoHue() {
        // 全灰（饱和度为 0）→ 色相桶全为 0，亮度桶正常
        let pixels = makePixels(width: 32, height: 32) { _, _ in (128, 128, 128, 255) }
        let signature = ColorSignatureMath.computeColorSignature(
            pixelBytes: pixels, width: 32, height: 32, dim: 14)

        XCTAssertEqual(signature[4], 0.0, accuracy: 0.001)   // 饱和度 = 0
        for i in 9..<14 {
            XCTAssertEqual(signature[i], 0.0, accuracy: 0.001, "灰色不应计入色相桶 [\(i)]")
        }
        // RGB 均值 = 128/255 ≈ 0.502
        XCTAssertEqual(signature[0], 128.0 / 255.0, accuracy: 0.002)
    }

    func testComputeColorSignatureInvalidInputsReturnZeros() {
        // 空像素 / 非法尺寸 → 全零签名（不崩溃）
        let empty = ColorSignatureMath.computeColorSignature(
            pixelBytes: [], width: 10, height: 10, dim: 14)
        XCTAssertEqual(empty, [Float](repeating: 0, count: 14))

        let zeroSize = ColorSignatureMath.computeColorSignature(
            pixelBytes: [1, 2, 3, 4], width: 0, height: 0, dim: 14)
        XCTAssertEqual(zeroSize, [Float](repeating: 0, count: 14))
    }

    func testComputeColorSignatureBufferTooSmallReturnsZeros() {
        // 缓冲区不足 width*height*4 → 全零
        let signature = ColorSignatureMath.computeColorSignature(
            pixelBytes: [1, 2, 3, 4], width: 64, height: 64, dim: 14)
        XCTAssertEqual(signature, [Float](repeating: 0, count: 14))
    }

    func testComputeColorSignatureCustomDim() {
        // dim=5 时只输出前 5 维
        let pixels = makePixels(width: 16, height: 16) { _, _ in (0, 255, 0, 255) }
        let signature = ColorSignatureMath.computeColorSignature(
            pixelBytes: pixels, width: 16, height: 16, dim: 5)
        XCTAssertEqual(signature.count, 5)
        XCTAssertEqual(signature[1], 1.0, accuracy: 0.001) // G=1
    }

    // MARK: - 辅助

    /// 生成 width×height 的 RGBA 像素缓冲区（premultiplied 无关——测试直接用不透明色）。
    private func makePixels(
        width: Int, height: Int,
        color: (Int, Int) -> (r: Int, g: Int, b: Int, a: Int)
    ) -> [UInt8] {
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let c = color(x, y)
                pixels.append(UInt8(c.r))
                pixels.append(UInt8(c.g))
                pixels.append(UInt8(c.b))
                pixels.append(UInt8(c.a))
            }
        }
        return pixels
    }
}
