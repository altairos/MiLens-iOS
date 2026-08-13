import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MiLens

final class RedPacketImageQualityAnalyzerTests: XCTestCase {
    func testAnalyzeExtractsDimensionsAndBrightness() throws {
        let data = try makeSolidPNG(width: 80, height: 60, gray: 128)
        let metrics = try XCTUnwrap(
            CoreGraphicsRedPacketImageQualityAnalyzer().analyze(imageData: data)
        )

        XCTAssertEqual(metrics.pixelWidth, 80)
        XCTAssertEqual(metrics.pixelHeight, 60)
        XCTAssertEqual(metrics.averageBrightness, 0.502, accuracy: 0.02)
        XCTAssertEqual(metrics.shadowClippingRatio, 0, accuracy: 0.001)
        XCTAssertEqual(metrics.highlightClippingRatio, 0, accuracy: 0.001)
    }

    func testMakeCutoutCropsTransparentMarginsAndReturnsMaskMetrics() throws {
        let width = 40
        let height = 40
        let data = try makeSolidPNG(width: width, height: height, gray: 160)
        var mask = Data(repeating: 0, count: width * height)
        mask.withUnsafeMutableBytes { rawBuffer in
            let values = rawBuffer.bindMemory(to: UInt8.self)
            for y in 10..<30 {
                for x in 10..<30 {
                    values[y * width + x] = 255
                }
            }
        }
        let segmentation = SegmentationResult(
            mask: mask, bboxX: 0, bboxY: 0,
            bboxWidth: width, bboxHeight: height
        )

        let result = try XCTUnwrap(
            CoreGraphicsRedPacketImageQualityAnalyzer().makeCutout(
                imageData: data, segmentation: segmentation
            )
        )
        XCTAssertEqual(result.pixelWidth, 24)
        XCTAssertEqual(result.pixelHeight, 24)
        XCTAssertEqual(result.maskMetrics.foregroundRatio, 0.25, accuracy: 0.001)
        XCTAssertEqual(result.maskMetrics.fragmentationRatio, 0, accuracy: 0.001)
    }

    private func makeSolidPNG(width: Int, height: Int, gray: UInt8) throws -> Data {
        let pixel = [gray, gray, gray, UInt8.max]
        let rgba = Data((0..<(width * height)).flatMap { _ in pixel })
        let provider = try XCTUnwrap(CGDataProvider(data: rgba as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
