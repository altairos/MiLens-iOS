//  ImageAnalyzer —— 图像分析协议（对应源端 ImageUtils.computeSharpness + PHash.compute）。
//  把 Core Graphics / Core Image 的直接调用隔离在此协议后面，
//  使 QualityScorer 可通过 mock 覆盖清晰度/哈希计算路径。
//  DESIGN.md §9 平台适配层。

import Foundation
import CoreGraphics
import ImageIO

/// 图像分析协议。
protocol ImageAnalyzer {
    /// 计算 Laplacian 方差清晰度（对应源端 `ImageUtils.computeSharpness`）。
    /// - Parameter imageData: 编码图片数据（JPEG/PNG）
    /// - Returns: 方差值（越大越清晰）；解码失败返回 0
    func computeSharpness(imageData: Data) -> Double

    /// 计算 64 位感知哈希（16 hex，对应源端 `PHash.compute`）。
    /// - Parameter imageData: 编码图片数据（JPEG/PNG）
    /// - Returns: 16 位十六进制哈希；解码失败返回 nil
    func computePHash(imageData: Data) -> String?
}

// MARK: - Core Graphics 实现

/// 基于 Core Graphics 的图像分析实现。
/// - sharpness：缩放到 256px → 灰度 → 3×3 Laplacian 四邻域卷积 → 方差（对应源端 `computeSharpnessInline`）。
/// - pHash：缩放到 8×8 → 灰度 → 均值二值化 → hex（对应源端 `PHash.compute`）。
final class CoreImageAnalyzer: ImageAnalyzer {

    /// 清晰度计算的目标最大边长（对应源端 `loadPixelMap(uri, 256)`）。
    private let sharpnessTargetSize = 256

    func computeSharpness(imageData: Data) -> Double {
        guard let cgImage = decode(imageData),
              let scaled = render(cgImage, maxDimension: sharpnessTargetSize),
              let gray = extractGrayscale(scaled) else { return 0 }
        return laplacianVariance(gray,
                                 width: scaled.width, height: scaled.height)
    }

    func computePHash(imageData: Data) -> String? {
        guard let cgImage = decode(imageData),
              let scaled = render(cgImage, exactWidth: 8, exactHeight: 8),
              let gray = extractGrayscale(scaled) else { return nil }
        return averageHash(gray)
    }

    // MARK: - 解码与缩放

    private func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// 缩放到指定最大边长（保持宽高比，对应源端 `scalePixelMap`）。
    private func render(_ image: CGImage, maxDimension: Int) -> CGImage? {
        let scale = CGFloat(maxDimension) / CGFloat(max(image.width, image.height))
        let newWidth = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let newHeight = max(1, Int((CGFloat(image.height) * scale).rounded()))
        return renderToSize(image, width: newWidth, height: newHeight)
    }

    /// 缩放到精确尺寸（拉伸，pHash 用以确保 64 像素）。
    private func render(_ image: CGImage, exactWidth: Int, exactHeight: Int) -> CGImage? {
        renderToSize(image, width: exactWidth, height: exactHeight)
    }

    private func renderToSize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - 灰度提取

    private func extractGrayscale(_ image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        var gray = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &gray, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return gray
    }

    // MARK: - Laplacian 方差（对应源端 `computeSharpnessInline`）

    private func laplacianVariance(_ gray: [UInt8], width: Int, height: Int) -> Double {
        guard width > 2, height > 2 else { return 0 }
        var sum: Double = 0
        var count = 0
        // 第一遍：求 Laplacian 均值
        // 为避免存储大数组，先收集再算方差（与源端一致）
        var laplacians: [Double] = []
        laplacians.reserveCapacity((width - 2) * (height - 2))
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = Double(gray[y * width + x])
                let up = Double(gray[(y - 1) * width + x])
                let down = Double(gray[(y + 1) * width + x])
                let left = Double(gray[y * width + (x - 1)])
                let right = Double(gray[y * width + (x + 1)])
                let lap = -4 * center + up + down + left + right
                laplacians.append(lap)
                sum += lap
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        let mean = sum / Double(count)
        // 第二遍：方差
        var variance: Double = 0
        for lap in laplacians {
            variance += (lap - mean) * (lap - mean)
        }
        return variance / Double(count)
    }

    // MARK: - 均值哈希（对应源端 `PHash.compute` 的 aHash 实现）

    private func averageHash(_ gray: [UInt8]) -> String {
        let sum = gray.reduce(0) { $0 + Int($1) }
        let avg = sum / max(gray.count, 1)
        var binary = ""
        for i in 0..<64 {
            binary += (i < gray.count && Int(gray[i]) >= avg) ? "1" : "0"
        }
        return PerceptualHashLogic.binaryToHex(binary)
    }
}

// MARK: - Mock（测试用）

/// 预设返回值的 mock，用于 QualityScorer 单元测试。
final class MockImageAnalyzer: ImageAnalyzer {
    var sharpnessResult: Double = 0
    var phashResult: String? = ""
    /// 记录被分析的 imageData，便于断言调用次数/内容。
    private(set) var sharpnessCalls: [Data] = []
    private(set) var phashCalls: [Data] = []

    func computeSharpness(imageData: Data) -> Double {
        sharpnessCalls.append(imageData)
        return sharpnessResult
    }

    func computePHash(imageData: Data) -> String? {
        phashCalls.append(imageData)
        return phashResult
    }
}
