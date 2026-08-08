//  ClipPreprocessTests —— CLIP 图像预处理纯逻辑测试（对应源端 ClipPreprocess.test.ets）。
//  覆盖 bilinearResizeAndNormalize / computeHandcraftedFeatures。

import XCTest
@testable import MiLens

final class ClipPreprocessTests: XCTestCase {

    // CLIP 标准归一化参数（与 ClipConstants 一致）
    private let clipMean: [Double] = [0.48145466, 0.4578275, 0.40821073]
    private let clipStd: [Double] = [0.26862954, 0.26130258, 0.27577711]

    // MARK: - bilinearResizeAndNormalize

    func testBilinearResize_outputLength_nchw() throws {
        // 2×2 纯色图像 → targetSize=2，NCHW 输出 3*4=12
        let pixels = [UInt8](repeating: 0, count: 2 * 2 * 4)
        let result = try ClipPreprocess.bilinearResizeAndNormalize(
            pixelBytes: pixels, origWidth: 2, origHeight: 2,
            targetSize: 2, mean: clipMean, std: clipStd, layout: .nchw)
        XCTAssertEqual(result.count, 3 * 2 * 2)
    }

    func testBilinearResize_outputLength_nhwc() throws {
        let pixels = [UInt8](repeating: 0, count: 2 * 2 * 4)
        let result = try ClipPreprocess.bilinearResizeAndNormalize(
            pixelBytes: pixels, origWidth: 2, origHeight: 2,
            targetSize: 4, mean: clipMean, std: clipStd, layout: .nhwc)
        XCTAssertEqual(result.count, 3 * 4 * 4)
    }

    func testBilinearResize_solidColor_normalizedCorrectly_nchw() throws {
        // 2×2 纯色 RGBA [128, 64, 255, 255]（纯色图像插值无误差）
        let pixel: [UInt8] = [128, 64, 255, 255]
        let pixels = [UInt8](repeating: 0, count: 16).enumerated().map { i, _ in pixel[i % 4] }

        let result = try ClipPreprocess.bilinearResizeAndNormalize(
            pixelBytes: pixels, origWidth: 2, origHeight: 2,
            targetSize: 2, mean: clipMean, std: clipStd, layout: .nchw)

        // 期望值
        let r = 128.0 / 255.0, g = 64.0 / 255.0, b = 255.0 / 255.0
        let expectedR = Float((r - clipMean[0]) / clipStd[0])
        let expectedG = Float((g - clipMean[1]) / clipStd[1])
        let expectedB = Float((b - clipMean[2]) / clipStd[2])

        // NCHW：channelSize=4
        // [0..3]=R, [4..7]=G, [8..11]=B
        for i in 0..<4 {
            XCTAssertEqual(result[i], expectedR, accuracy: 0.01, "R channel at \(i)")
            XCTAssertEqual(result[4 + i], expectedG, accuracy: 0.01, "G channel at \(i)")
            XCTAssertEqual(result[8 + i], expectedB, accuracy: 0.01, "B channel at \(i)")
        }
    }

    func testBilinearResize_solidColor_normalizedCorrectly_nhwc() throws {
        let pixel: [UInt8] = [128, 64, 255, 255]
        let pixels = [UInt8](repeating: 0, count: 16).enumerated().map { i, _ in pixel[i % 4] }

        let result = try ClipPreprocess.bilinearResizeAndNormalize(
            pixelBytes: pixels, origWidth: 2, origHeight: 2,
            targetSize: 2, mean: clipMean, std: clipStd, layout: .nhwc)

        let r = 128.0 / 255.0, g = 64.0 / 255.0, b = 255.0 / 255.0
        let expectedR = Float((r - clipMean[0]) / clipStd[0])
        let expectedG = Float((g - clipMean[1]) / clipStd[1])
        let expectedB = Float((b - clipMean[2]) / clipStd[2])

        // NHWC：每像素 [R, G, B] 交错
        for i in 0..<4 {
            let base = i * 3
            XCTAssertEqual(result[base], expectedR, accuracy: 0.01, "R at pixel \(i)")
            XCTAssertEqual(result[base + 1], expectedG, accuracy: 0.01, "G at pixel \(i)")
            XCTAssertEqual(result[base + 2], expectedB, accuracy: 0.01, "B at pixel \(i)")
        }
    }

    func testBilinearResize_invalidSize_throws() {
        let pixels = [UInt8](repeating: 0, count: 16)
        XCTAssertThrowsError(
            try ClipPreprocess.bilinearResizeAndNormalize(
                pixelBytes: pixels, origWidth: 0, origHeight: 2,
                targetSize: 2, mean: clipMean, std: clipStd, layout: .nchw)
        ) { error in
            guard case ClipPreprocessError.invalidInputSize = error else {
                XCTFail("Expected invalidInputSize, got \(error)")
                return
            }
        }
    }

    func testBilinearResize_bufferTooSmall_throws() {
        // 声称 4×4 但只给 2×2 的缓冲区
        let pixels = [UInt8](repeating: 0, count: 16)
        XCTAssertThrowsError(
            try ClipPreprocess.bilinearResizeAndNormalize(
                pixelBytes: pixels, origWidth: 4, origHeight: 4,
                targetSize: 2, mean: clipMean, std: clipStd, layout: .nchw)
        ) { error in
            guard case ClipPreprocessError.bufferTooSmall = error else {
                XCTFail("Expected bufferTooSmall, got \(error)")
                return
            }
        }
    }

    func testBilinearResize_centerCrop_usesShortSide() throws {
        // 4×2 矩形图像，中心裁剪 cropSize=min(4,2)=2，cropX=1
        // 验证输出尺寸正确（不崩溃，输出长度正确）
        let pixels = [UInt8](repeating: 128, count: 4 * 2 * 4)
        let result = try ClipPreprocess.bilinearResizeAndNormalize(
            pixelBytes: pixels, origWidth: 4, origHeight: 2,
            targetSize: 2, mean: clipMean, std: clipStd, layout: .nchw)
        XCTAssertEqual(result.count, 3 * 2 * 2)
    }

    // MARK: - computeHandcraftedFeatures

    func testHandcraftedFeatures_outputLength() throws {
        let pixels = [UInt8](repeating: 128, count: 16 * 16 * 4)
        let result = try ClipPreprocess.computeHandcraftedFeatures(
            pixelBytes: pixels, width: 16, height: 16)
        XCTAssertEqual(result.count, handcraftedDim)  // 512
    }

    func testHandcraftedFeatures_solidColor_luminanceAndSaturation() throws {
        // 16×16 纯色 [128, 64, 255] (RGB)
        let pixel: [UInt8] = [128, 64, 255, 255]
        let pixels = [UInt8](repeating: 0, count: 16 * 16 * 4).enumerated().map { i, _ in pixel[i % 4] }

        let result = try ClipPreprocess.computeHandcraftedFeatures(
            pixelBytes: pixels, width: 16, height: 16)

        let r = 128.0 / 255.0, g = 64.0 / 255.0, b = 255.0 / 255.0
        let expectedLuminance = Float(0.299 * r + 0.587 * g + 0.114 * b - 0.5)
        let expectedSaturation = Float(max(r, max(g, b)) - min(r, min(g, b)))

        // [0..255] 亮度（居中），[256..511] 饱和度
        for i in 0..<256 {
            XCTAssertEqual(result[i], expectedLuminance, accuracy: 0.01, "luminance cell \(i)")
            XCTAssertEqual(result[256 + i], expectedSaturation, accuracy: 0.01, "saturation cell \(i)")
        }
    }

    func testHandcraftedFeatures_invalidSize_throws() {
        let pixels = [UInt8](repeating: 0, count: 16)
        XCTAssertThrowsError(
            try ClipPreprocess.computeHandcraftedFeatures(
                pixelBytes: pixels, width: 0, height: 4)
        ) { error in
            guard case ClipPreprocessError.invalidInputSize = error else {
                XCTFail("Expected invalidInputSize, got \(error)")
                return
            }
        }
    }

    func testHandcraftedFeatures_bufferTooSmall_throws() {
        let pixels = [UInt8](repeating: 0, count: 16)
        XCTAssertThrowsError(
            try ClipPreprocess.computeHandcraftedFeatures(
                pixelBytes: pixels, width: 8, height: 8)
        ) { error in
            guard case ClipPreprocessError.bufferTooSmall = error else {
                XCTFail("Expected bufferTooSmall, got \(error)")
                return
            }
        }
    }
}
