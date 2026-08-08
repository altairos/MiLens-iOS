//  ColorSignatureMath —— 宠物颜色签名纯逻辑（对应源端 services/ColorSignatureMath.ets）。
//
//  从 PetMatcher.extractMatchColorSignature + hueBin 抽出的纯函数：
//  - hueBin：RGB → 色相桶索引（0-4）
//  - computeColorSignature：从原始 RGBA 像素缓冲区计算加权颜色签名
//
//  设计原则（DESIGN.md §4）：零 IO / 零 SwiftUI 依赖，输入为像素缓冲区 + 宽高 + 维度。
//  字节序差异：源端 HarmonyOS PixelMap readPixelsToBuffer 返回 BGRA；
//  iOS ClipInferenceService.decodeToRGBA 输出 RGBA（premultipliedLast），偏移不同。

import Foundation

enum ColorSignatureMath {

    /// iOS decodeToRGBA 输出 RGBA 字节序（源端为 BGRA，RED_OFFSET=2）。
    private static let redOffset = 0
    private static let greenOffset = 1
    private static let blueOffset = 2

    /// 色相阈值（度），用于将连续色相映射到 5 个桶（与源端 HUE_BIN_BOUNDARIES 一致）。
    private static let hueBinBoundaries: [Double] = [30, 75, 165, 255, 330]

    /// 将 RGB 值（0–1）映射到色相桶索引（0-4）。
    ///
    /// 桶定义：
    /// - 0: 红/品红 (hue < 30 || hue >= 330)
    /// - 1: 橙/黄 (30 <= hue < 75)
    /// - 2: 绿 (75 <= hue < 165)
    /// - 3: 青/蓝 (165 <= hue < 255)
    /// - 4: 紫/品红 (255 <= hue < 330)
    ///
    /// 当 r==g==b（无色相，delta ≈ 0）时返回 0。
    static func hueBin(r: Double, g: Double, b: Double) -> Int {
        let maxValue = max(r, max(g, b))
        let minValue = min(r, min(g, b))
        let delta = maxValue - minValue
        if delta <= 0.000001 { return 0 }
        var hue: Double
        if maxValue == r {
            hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxValue == g {
            hue = (b - r) / delta + 2
        } else {
            hue = (r - g) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        if hue < hueBinBoundaries[0] || hue >= hueBinBoundaries[4] { return 0 }
        if hue < hueBinBoundaries[1] { return 1 }
        if hue < hueBinBoundaries[2] { return 2 }
        if hue < hueBinBoundaries[3] { return 3 }
        return 4
    }

    /// 从原始 RGBA 像素缓冲区计算加权颜色签名。
    ///
    /// 签名维度 = dim（通常 14）：
    /// - [0-2] 加权 RGB 均值
    /// - [3]   加权亮度均值
    /// - [4]   加权饱和度均值
    /// - [5-8] 4 个亮度桶的权重归一化占比
    /// - [9-13] 5 个色相桶的饱和度加权占比
    ///
    /// 权重 = 中心距离权重 × (0.65 + 0.35 × 饱和度)，使画面中心和高饱和度区域权重更高。
    /// 饱和度 < 0.12 的像素不计入色相桶。
    ///
    /// 输入 pixelBytes 必须为 width × height × 4 字节的 RGBA 缓冲区；
    /// 宽高 ≤ 0 或缓冲区不足时返回全零签名。
    static func computeColorSignature(
        pixelBytes: [UInt8],
        width: Int,
        height: Int,
        dim: Int
    ) -> [Float] {
        var signature = [Float](repeating: 0, count: max(0, dim))
        if width <= 0 || height <= 0 { return signature }
        if pixelBytes.count < width * height * 4 { return signature }

        let lumaBinCount = 4
        let hueBinCount = 5
        var weightSum: Double = 0
        var rSum: Double = 0
        var gSum: Double = 0
        var bSum: Double = 0
        var lumaSum: Double = 0
        var satSum: Double = 0
        var lumaBins = [Double](repeating: 0, count: lumaBinCount)
        var hueBins = [Double](repeating: 0, count: hueBinCount)
        let cx = Double(width - 1) / 2
        let cy = Double(height - 1) / 2
        let maxDist = (cx * cx + cy * cy).squareRoot()

        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let r = Double(pixelBytes[idx + redOffset]) / 255.0
                let g = Double(pixelBytes[idx + greenOffset]) / 255.0
                let b = Double(pixelBytes[idx + blueOffset]) / 255.0
                let maxValue = max(r, max(g, b))
                let minValue = min(r, min(g, b))
                let luma = 0.299 * r + 0.587 * g + 0.114 * b
                let sat = maxValue > 0 ? (maxValue - minValue) / maxValue : 0
                let dist = maxDist > 0
                    ? (Double(x) - cx) * (Double(x) - cx) + (Double(y) - cy) * (Double(y) - cy)
                    : 0
                let centerWeight = 1.0 - 0.55 * min(1.0, dist.squareRoot() / maxDist)
                let weight = centerWeight * (0.65 + 0.35 * sat)

                weightSum += weight
                rSum += r * weight
                gSum += g * weight
                bSum += b * weight
                lumaSum += luma * weight
                satSum += sat * weight
                lumaBins[min(lumaBinCount - 1, Int(luma * Double(lumaBinCount)))] += weight
                if sat > 0.12 {
                    hueBins[hueBin(r: r, g: g, b: b)] += weight * sat
                }
            }
        }

        let safeWeight = weightSum > 0 ? weightSum : 1
        if dim > 0 { signature[0] = Float(rSum / safeWeight) }
        if dim > 1 { signature[1] = Float(gSum / safeWeight) }
        if dim > 2 { signature[2] = Float(bSum / safeWeight) }
        if dim > 3 { signature[3] = Float(lumaSum / safeWeight) }
        if dim > 4 { signature[4] = Float(satSum / safeWeight) }
        for i in 0..<lumaBinCount where 5 + i < dim {
            signature[5 + i] = Float(lumaBins[i] / safeWeight)
        }

        let hueWeight = hueBins.reduce(0, +)
        let safeHueWeight = hueWeight > 0 ? hueWeight : 1
        for i in 0..<hueBinCount where 9 + i < dim {
            signature[9 + i] = Float(hueBins[i] / safeHueWeight)
        }
        return signature
    }
}
