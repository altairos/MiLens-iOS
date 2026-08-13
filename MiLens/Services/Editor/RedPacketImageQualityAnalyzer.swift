import CoreGraphics
import Foundation
import ImageIO
import MiLensKit
import UniformTypeIdentifiers

struct RedPacketImageMetrics: Equatable, Sendable {
    var pixelWidth: Int
    var pixelHeight: Int
    var sharpness: Double
    var averageBrightness: Double
    var shadowClippingRatio: Double
    var highlightClippingRatio: Double
    var sampledPixelCount: Int
}

struct RedPacketCutoutProcessingResult: Equatable, Sendable {
    var pngData: Data
    var pixelWidth: Int
    var pixelHeight: Int
    var imageMetrics: RedPacketImageMetrics
    var maskMetrics: RedPacketMaskMetrics
}

/// 红包图片指标提取与蒙版合成协议。输入输出均为 Sendable 值，供后台任务执行。
protocol RedPacketImageQualityAnalyzing: Sendable {
    func analyze(imageData: Data) -> RedPacketImageMetrics?
    func makeCutout(
        imageData: Data,
        segmentation: SegmentationResult
    ) -> RedPacketCutoutProcessingResult?
}

/// 基于 Core Graphics/ImageIO 的本地图像质量分析器。
final class CoreGraphicsRedPacketImageQualityAnalyzer:
    RedPacketImageQualityAnalyzing, @unchecked Sendable
{
    private let sharpnessAnalyzer: any ImageAnalyzer
    private let sampleMaxDimension = 256

    init(sharpnessAnalyzer: any ImageAnalyzer = CoreImageAnalyzer()) {
        self.sharpnessAnalyzer = sharpnessAnalyzer
    }

    func analyze(imageData: Data) -> RedPacketImageMetrics? {
        guard let image = decode(imageData),
              let sample = renderRGBA(image, maxDimension: sampleMaxDimension)
        else { return nil }

        var luminanceSum = 0.0
        var shadowCount = 0
        var highlightCount = 0
        var sampleCount = 0

        sample.pixels.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            for index in stride(from: 0, to: bytes.count, by: 4) {
                guard bytes[index + 3] >= 16 else { continue }
                let red = Double(bytes[index]) / 255
                let green = Double(bytes[index + 1]) / 255
                let blue = Double(bytes[index + 2]) / 255
                let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                luminanceSum += luminance
                sampleCount += 1
                if luminance <= 0.08 { shadowCount += 1 }
                if luminance >= 0.95 { highlightCount += 1 }
            }
        }

        guard sampleCount > 0 else { return nil }
        return RedPacketImageMetrics(
            pixelWidth: image.width,
            pixelHeight: image.height,
            sharpness: sharpnessAnalyzer.computeSharpness(imageData: imageData),
            averageBrightness: luminanceSum / Double(sampleCount),
            shadowClippingRatio: Double(shadowCount) / Double(sampleCount),
            highlightClippingRatio: Double(highlightCount) / Double(sampleCount),
            sampledPixelCount: sampleCount
        )
    }

    func makeCutout(
        imageData: Data,
        segmentation: SegmentationResult
    ) -> RedPacketCutoutProcessingResult? {
        guard let image = decode(imageData),
              segmentation.bboxWidth > 0,
              segmentation.bboxHeight > 0,
              segmentation.mask.count >= segmentation.bboxWidth * segmentation.bboxHeight,
              var rgba = renderRGBA(image, exactWidth: image.width, exactHeight: image.height)?.pixels,
              let maskMetrics = RedPacketMaskQualityLogic.analyze(
                mask: segmentation.mask,
                width: segmentation.bboxWidth,
                height: segmentation.bboxHeight
              )
        else { return nil }

        let bboxX = Int(segmentation.bboxX.rounded())
        let bboxY = Int(segmentation.bboxY.rounded())
        let width = image.width
        let height = image.height
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        rgba.withUnsafeMutableBytes { rgbaBuffer in
            segmentation.mask.withUnsafeBytes { maskBuffer in
                let pixels = rgbaBuffer.bindMemory(to: UInt8.self)
                let mask = maskBuffer.bindMemory(to: UInt8.self)

                for y in 0..<height {
                    for x in 0..<width {
                        let localX = x - bboxX
                        let localY = y - bboxY
                        let alphaMask: UInt8
                        if localX >= 0, localX < segmentation.bboxWidth,
                           localY >= 0, localY < segmentation.bboxHeight {
                            alphaMask = mask[localY * segmentation.bboxWidth + localX]
                        } else {
                            alphaMask = 0
                        }

                        let pixelIndex = (y * width + x) * 4
                        let factor = Int(alphaMask)
                        pixels[pixelIndex] = UInt8(Int(pixels[pixelIndex]) * factor / 255)
                        pixels[pixelIndex + 1] = UInt8(Int(pixels[pixelIndex + 1]) * factor / 255)
                        pixels[pixelIndex + 2] = UInt8(Int(pixels[pixelIndex + 2]) * factor / 255)
                        pixels[pixelIndex + 3] = UInt8(Int(pixels[pixelIndex + 3]) * factor / 255)

                        if pixels[pixelIndex + 3] >= 8 {
                            minX = min(minX, x)
                            minY = min(minY, y)
                            maxX = max(maxX, x)
                            maxY = max(maxY, y)
                        }
                    }
                }
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        let padding = 2
        minX = max(0, minX - padding)
        minY = max(0, minY - padding)
        maxX = min(width - 1, maxX + padding)
        maxY = min(height - 1, maxY + padding)
        let croppedWidth = maxX - minX + 1
        let croppedHeight = maxY - minY + 1
        var cropped = Data(count: croppedWidth * croppedHeight * 4)

        cropped.withUnsafeMutableBytes { destinationBuffer in
            rgba.withUnsafeBytes { sourceBuffer in
                guard let destination = destinationBuffer.baseAddress,
                      let source = sourceBuffer.baseAddress else { return }
                let sourceRowBytes = width * 4
                let destinationRowBytes = croppedWidth * 4
                for row in 0..<croppedHeight {
                    let sourceOffset = (minY + row) * sourceRowBytes + minX * 4
                    destination.advanced(by: row * destinationRowBytes).copyMemory(
                        from: source.advanced(by: sourceOffset),
                        byteCount: destinationRowBytes
                    )
                }
            }
        }

        guard let croppedImage = makeImage(
            rgba: cropped, width: croppedWidth, height: croppedHeight
        ), let pngData = encodePNG(croppedImage),
        let imageMetrics = analyze(imageData: pngData) else { return nil }

        return RedPacketCutoutProcessingResult(
            pngData: pngData,
            pixelWidth: croppedWidth,
            pixelHeight: croppedHeight,
            imageMetrics: imageMetrics,
            maskMetrics: maskMetrics
        )
    }

    private func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func renderRGBA(
        _ image: CGImage, maxDimension: Int
    ) -> (pixels: Data, width: Int, height: Int)? {
        let scale = min(1, CGFloat(maxDimension) / CGFloat(max(image.width, image.height)))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let pixels = renderRGBA(image, exactWidth: width, exactHeight: height)?.pixels else {
            return nil
        }
        return (pixels, width, height)
    }

    private func renderRGBA(
        _ image: CGImage, exactWidth width: Int, exactHeight height: Int
    ) -> (pixels: Data, width: Int, height: Int)? {
        var pixels = Data(count: width * height * 4)
        let succeeded = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return succeeded ? (pixels, width, height) : nil
    }

    private func makeImage(rgba: Data, width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: rgba as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private func encodePNG(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
