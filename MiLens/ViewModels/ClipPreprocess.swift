//  ClipPreprocess —— CLIP 图像预处理纯逻辑（对应源端 services/ClipPreprocess.ets）。
//
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 CoreML / 无 SwiftUI 依赖。
//  从 AiService.preprocessForClip + extractHandcraftedEmbedding 抽出的纯函数：
//  - bilinearResizeAndNormalize：中心裁剪 + 双线性插值 + RGBA→RGB 归一化
//  - computeHandcraftedFeatures：16×16 网格手工特征提取（降级 embedding）
//
//  与源端差异（ADR-0007 §4.1）：
//  - 源端 PixelMap 字节序为 BGRA，iOS Core Graphics 为 RGBA（通道偏移调整）。
//  - 源端模型 NHWC，iOS CoreML 固定 NCHW（layout 参数保留但 iOS 仅用 .nchw）。
//  - 源端双线性，iOS 沿用双线性（保持 parity；ADR 文案中的 "bicubic" 为未来选项）。
//
//  输入为 [UInt8] 像素缓冲区 + 尺寸参数，不依赖 CGImage/PixelMap，可在 XCTest 完整覆盖。

import Foundation

/// 手工特征网格边长（对应源端 `HANDCRAFTED_GRID`）。
private let handcraftedGrid = 16

/// 手工特征向量维度（2 × grid² = 512，对应源端 `HANDCRAFTED_DIM`）。
let handcraftedDim = 512

/// CLIP 输入张量布局（对应源端 `ClipInputLayout`）。
/// iOS CoreML 固定使用 `.nchw`（[1, 3, H, W]）；保留 `.nhwc` 用于 parity 测试。
enum ClipInputLayout {
    case nchw  // [1, 3, H, W] — iOS CoreML 约定
    case nhwc  // [1, H, W, 3] — 源端 MindSpore 约定
}

/// CLIP 图像预处理纯逻辑（对应源端 `ClipPreprocess`）。
enum ClipPreprocess {

    /// 中心裁剪 + 双线性插值缩放 + CLIP 归一化（对应源端 `bilinearResizeAndNormalize`）。
    ///
    /// 步骤：
    /// 1. 以短边为中心裁剪正方形区域（cropSize = min(origW, origH)）；
    /// 2. 双线性插值缩放到 targetSize × targetSize（半像素偏移采样，与源端一致）；
    /// 3. RGBA → RGB 通道分离 + (x - mean) / std 归一化；
    /// 4. 按 layout 排列为 NCHW 或 NHWC。
    ///
    /// - Parameters:
    ///   - pixelBytes: RGBA 像素缓冲区（每像素 4 字节，长度 >= origWidth × origHeight × 4）。
    ///   - origWidth/origHeight: 原始图像尺寸。
    ///   - targetSize: 目标边长（CLIP 为 224）。
    ///   - mean/std: CLIP 归一化参数（R/G/B 顺序）。
    ///   - layout: 输出张量布局（iOS 固定 `.nchw`）。
    /// - Returns: Float 数组，长度 = 3 × targetSize²。
    ///
    /// 当 origW/origH ≤ 0 或缓冲区不足时抛出 `ClipPreprocessError.invalidInputSize`。
    static func bilinearResizeAndNormalize(
        pixelBytes: [UInt8],
        origWidth: Int,
        origHeight: Int,
        targetSize: Int,
        mean: [Double],
        std: [Double],
        layout: ClipInputLayout
    ) throws -> [Float] {
        guard origWidth > 0, origHeight > 0 else {
            throw ClipPreprocessError.invalidInputSize(width: origWidth, height: origHeight)
        }
        guard pixelBytes.count >= origWidth * origHeight * 4 else {
            throw ClipPreprocessError.bufferTooSmall(
                bytes: pixelBytes.count,
                expected: origWidth * origHeight * 4)
        }

        let channelSize = targetSize * targetSize
        var floatData = [Float](repeating: 0, count: 3 * channelSize)

        let cropSize = min(origWidth, origHeight)
        let cropX = (origWidth - cropSize) / 2
        let cropY = (origHeight - cropSize) / 2

        for ty in 0..<targetSize {
            // 半像素偏移采样（源端：cropY + (ty + 0.5) * cropSize / targetSize - 0.5）
            let origY = Double(cropY) + (Double(ty) + 0.5) * Double(cropSize) / Double(targetSize) - 0.5
            let y0 = max(0, Int(floor(origY)))
            let y1 = min(origHeight - 1, y0 + 1)
            let dy = origY - Double(y0)

            for tx in 0..<targetSize {
                let origX = Double(cropX) + (Double(tx) + 0.5) * Double(cropSize) / Double(targetSize) - 0.5
                let x0 = max(0, Int(floor(origX)))
                let x1 = min(origWidth - 1, x0 + 1)
                let dx = origX - Double(x0)

                let idx00 = y0 * origWidth + x0
                let idx01 = y0 * origWidth + x1
                let idx10 = y1 * origWidth + x0
                let idx11 = y1 * origWidth + x1

                // RGBA 字节序（iOS Core Graphics）：R=+0, G=+1, B=+2
                let r00 = Double(pixelBytes[idx00 * 4 + 0]) / 255.0
                let g00 = Double(pixelBytes[idx00 * 4 + 1]) / 255.0
                let b00 = Double(pixelBytes[idx00 * 4 + 2]) / 255.0

                let r01 = Double(pixelBytes[idx01 * 4 + 0]) / 255.0
                let g01 = Double(pixelBytes[idx01 * 4 + 1]) / 255.0
                let b01 = Double(pixelBytes[idx01 * 4 + 2]) / 255.0

                let r10 = Double(pixelBytes[idx10 * 4 + 0]) / 255.0
                let g10 = Double(pixelBytes[idx10 * 4 + 1]) / 255.0
                let b10 = Double(pixelBytes[idx10 * 4 + 2]) / 255.0

                let r11 = Double(pixelBytes[idx11 * 4 + 0]) / 255.0
                let g11 = Double(pixelBytes[idx11 * 4 + 1]) / 255.0
                let b11 = Double(pixelBytes[idx11 * 4 + 2]) / 255.0

                let ti = ty * targetSize + tx
                let r = (r00 * (1 - dx) + r01 * dx) * (1 - dy) + (r10 * (1 - dx) + r11 * dx) * dy
                let g = (g00 * (1 - dx) + g01 * dx) * (1 - dy) + (g10 * (1 - dx) + g11 * dx) * dy
                let b = (b00 * (1 - dx) + b01 * dx) * (1 - dy) + (b10 * (1 - dx) + b11 * dx) * dy

                let rn = Float((r - mean[0]) / std[0])
                let gn = Float((g - mean[1]) / std[1])
                let bn = Float((b - mean[2]) / std[2])

                switch layout {
                case .nhwc:
                    let base = ti * 3
                    floatData[base] = rn
                    floatData[base + 1] = gn
                    floatData[base + 2] = bn
                case .nchw:
                    floatData[ti] = rn
                    floatData[channelSize + ti] = gn
                    floatData[2 * channelSize + ti] = bn
                }
            }
        }

        return floatData
    }

    /// 从原始 RGBA 像素缓冲区提取 16×16 网格手工特征（对应源端 `computeHandcraftedFeatures`）。
    ///
    /// 输出 [Float]（512 维）：
    /// - [0..255]：每格亮度（0.299r + 0.587g + 0.114b - 0.5，居中）
    /// - [256..511]：每格饱和度（max - min）
    ///
    /// 用于 CLIP 模型不可用时的降级 embedding（仅用于已注册宠物的视觉匹配，不作分类）。
    static func computeHandcraftedFeatures(
        pixelBytes: [UInt8],
        width: Int,
        height: Int
    ) throws -> [Float] {
        guard width > 0, height > 0 else {
            throw ClipPreprocessError.invalidInputSize(width: width, height: height)
        }
        guard pixelBytes.count >= width * height * 4 else {
            throw ClipPreprocessError.bufferTooSmall(
                bytes: pixelBytes.count, expected: width * height * 4)
        }

        let grid = handcraftedGrid
        let cellCount = grid * grid
        var vector = [Float](repeating: 0, count: handcraftedDim)
        var rSum = [Double](repeating: 0, count: cellCount)
        var gSum = [Double](repeating: 0, count: cellCount)
        var bSum = [Double](repeating: 0, count: cellCount)
        var counts = [Double](repeating: 0, count: cellCount)

        for y in 0..<height {
            let gy = min(grid - 1, y * grid / height)
            for x in 0..<width {
                let gx = min(grid - 1, x * grid / width)
                let cell = gy * grid + gx
                let idx = (y * width + x) * 4
                // RGBA 字节序
                bSum[cell] += Double(pixelBytes[idx + 2]) / 255.0
                gSum[cell] += Double(pixelBytes[idx + 1]) / 255.0
                rSum[cell] += Double(pixelBytes[idx + 0]) / 255.0
                counts[cell] += 1.0
            }
        }

        for i in 0..<cellCount {
            let count = counts[i] > 0 ? counts[i] : 1.0
            let r = rSum[i] / count
            let g = gSum[i] / count
            let b = bSum[i] / count
            let maxValue = max(r, max(g, b))
            let minValue = min(r, min(g, b))
            vector[i] = Float(0.299 * r + 0.587 * g + 0.114 * b - 0.5)
            vector[cellCount + i] = Float(maxValue - minValue)
        }

        return vector
    }
}

/// CLIP 预处理错误（对应源端 ClipPreprocess 抛出的 Error）。
enum ClipPreprocessError: Error, Equatable {
    case invalidInputSize(width: Int, height: Int)
    case bufferTooSmall(bytes: Int, expected: Int)
}
