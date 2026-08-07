import Foundation

// BeadImagePreprocessor — 面积平均缩放 / USM 锐化 / 宠物色彩增强。
// 逐行翻译自源端 shared/.../bead/BeadImagePreprocessor.ets（127 行）。
// 操作 RGBA [UInt8] 平坦数组。

/// 面积平均缩放 RGBA 像素。对应源端 `areaResizeRgba`。
public func areaResizeRgba(
    _ src: [UInt8], srcW: Int, srcH: Int, dstW: Int, dstH: Int
) -> [UInt8] {
    var dst = [UInt8](repeating: 0, count: dstW * dstH * 4)
    let scaleX = Double(srcW) / Double(dstW)
    let scaleY = Double(srcH) / Double(dstH)
    for dy in 0..<dstH {
        for dx in 0..<dstW {
            let sx0 = floorInt(Double(dx) * scaleX)
            let sy0 = floorInt(Double(dy) * scaleY)
            let sx1 = min(ceilInt(Double(dx + 1) * scaleX), srcW)
            let sy1 = min(ceilInt(Double(dy + 1) * scaleY), srcH)
            var r = 0, g = 0, b = 0, a = 0, count = 0
            for sy in sy0..<sy1 {
                for sx in sx0..<sx1 {
                    let si = (sy * srcW + sx) * 4
                    r += Int(src[si]); g += Int(src[si + 1]); b += Int(src[si + 2]); a += Int(src[si + 3]); count += 1
                }
            }
            if count > 0 {
                let di = (dy * dstW + dx) * 4
                dst[di] = UInt8(Double(r) / Double(count) + 0.5)
                dst[di + 1] = UInt8(Double(g) / Double(count) + 0.5)
                dst[di + 2] = UInt8(Double(b) / Double(count) + 0.5)
                dst[di + 3] = UInt8(Double(a) / Double(count) + 0.5)
            }
        }
    }
    return dst
}

/// 3×3 USM 锐化（原地修改，保留 alpha）。对应源端 `applyUnsharpMask`。
public func applyUnsharpMask(_ pixels: inout [UInt8], w: Int, h: Int, amount: Double) {
    var blurred = [UInt8](repeating: 0, count: pixels.count)
    for y in 0..<h {
        for x in 0..<w {
            var r = 0, g = 0, b = 0, count = 0
            for dy in -1...1 {
                for dx in -1...1 {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0 && nx < w && ny >= 0 && ny < h {
                        let ni = (ny * w + nx) * 4
                        r += Int(pixels[ni]); g += Int(pixels[ni + 1]); b += Int(pixels[ni + 2]); count += 1
                    }
                }
            }
            let idx = (y * w + x) * 4
            blurred[idx] = UInt8((Double(r) / Double(count)).rounded())
            blurred[idx + 1] = UInt8((Double(g) / Double(count)).rounded())
            blurred[idx + 2] = UInt8((Double(b) / Double(count)).rounded())
        }
    }
    for i in 0..<(w * h) {
        let pi = i * 4
        pixels[pi] = clampByte(Double(pixels[pi]) + (Double(pixels[pi]) - Double(blurred[pi])) * amount)
        pixels[pi + 1] = clampByte(Double(pixels[pi + 1]) + (Double(pixels[pi + 1]) - Double(blurred[pi + 1])) * amount)
        pixels[pi + 2] = clampByte(Double(pixels[pi + 2]) + (Double(pixels[pi + 2]) - Double(blurred[pi + 2])) * amount)
    }
}

@inline(__always)
private func clampByte(_ v: Double) -> UInt8 {
    UInt8(max(0, min(255, v.rounded())))
}

/// 宠物色彩增强：白平衡 / 饱和度 / 对比度 / 阴影提升 / 自然色保护。
/// 对应源端 `enhancePetColors`。原地修改 pixels。
public func enhancePetColors(
    _ pixels: inout [UInt8], pixelCount: Int,
    saturationBoost: Double, contrastBoost: Double,
    shadowLiftAmount: Double, autoWhiteBalanceStrength: Double,
    vibranceBoost: Double, brightnessBoost: Double,
    neutralGuardStrength: Double, highlightProtectStrength: Double
) {
    var sumR = 0.0, sumG = 0.0, sumB = 0.0
    var validCount = 0
    for i in 0..<pixelCount {
        let pi = i * 4
        if pixels[pi + 3] < 128 { continue }
        sumR += Double(pixels[pi]); sumG += Double(pixels[pi + 1]); sumB += Double(pixels[pi + 2]); validCount += 1
    }
    let avgR = validCount > 0 ? sumR / Double(validCount) : 128
    let avgG = validCount > 0 ? sumG / Double(validCount) : 128
    let avgB = validCount > 0 ? sumB / Double(validCount) : 128
    let target = (avgR + avgG + avgB) / 3
    let wbStrength = max(0, min(1, autoWhiteBalanceStrength))
    let gainR = 1 + (max(0.9, min(1.1, target / max(1, avgR))) - 1) * wbStrength
    let gainG = 1 + (max(0.9, min(1.1, target / max(1, avgG))) - 1) * wbStrength
    let gainB = 1 + (max(0.9, min(1.1, target / max(1, avgB))) - 1) * wbStrength

    for i in 0..<pixelCount {
        let pi = i * 4
        if pixels[pi + 3] < 128 { continue }
        let originalR = Double(pixels[pi]) / 255
        let originalG = Double(pixels[pi + 1]) / 255
        let originalB = Double(pixels[pi + 2]) / 255
        let originalMax = max(originalR, max(originalG, originalB))
        let originalMin = min(originalR, min(originalG, originalB))
        let originalSaturation = originalMax - originalMin
        let neutralBase = max(0, min(1, (0.14 - originalSaturation) / 0.14))
        let guardStrength = max(0, min(1, neutralGuardStrength))
        let neutralProtection = neutralBase * (guardStrength + (1 - guardStrength) * neutralBase)
        let r = max(0, min(1, originalR * (1 + (gainR - 1) * (1 - neutralProtection))))
        let g = max(0, min(1, originalG * (1 + (gainG - 1) * (1 - neutralProtection))))
        let b = max(0, min(1, originalB * (1 + (gainB - 1) * (1 - neutralProtection))))
        let gray = r * 0.2126 + g * 0.7152 + b * 0.0722
        let shadowLift = gray < 0.35 ? (0.35 - gray) * shadowLiftAmount : 0
        let contrast = gray > 0.9 ? 1 + (contrastBoost - 1) * 0.4 : contrastBoost
        let vibrance = 1 + (vibranceBoost - 1) * (1 - min(1, originalSaturation * 2))
        var chromaScale = saturationBoost * vibrance
        if originalSaturation < 0.10 { chromaScale = 1 + (chromaScale - 1) * (1 - guardStrength) }
        let highlightBlend = gray > 0.75
            ? max(0, min(1, (gray - 0.75) / 0.25)) * max(0, min(1, highlightProtectStrength))
            : 0
        pixels[pi] = clampByte(enhanceChannel(r, originalR, gray, chromaScale, contrast, shadowLift, brightnessBoost, highlightBlend) * 255)
        pixels[pi + 1] = clampByte(enhanceChannel(g, originalG, gray, chromaScale, contrast, shadowLift, brightnessBoost, highlightBlend) * 255)
        pixels[pi + 2] = clampByte(enhanceChannel(b, originalB, gray, chromaScale, contrast, shadowLift, brightnessBoost, highlightBlend) * 255)
    }
}

private func enhanceChannel(
    _ channel: Double, _ original: Double, _ gray: Double,
    _ chromaScale: Double, _ contrast: Double,
    _ shadowLift: Double, _ brightnessBoost: Double, _ highlightBlend: Double
) -> Double {
    let saturated = gray + (channel - gray) * chromaScale
    let value = (saturated - 0.5) * contrast + 0.5 + shadowLift + (brightnessBoost - 1)
    return max(0, min(1, value * (1 - highlightBlend) + original * highlightBlend))
}
