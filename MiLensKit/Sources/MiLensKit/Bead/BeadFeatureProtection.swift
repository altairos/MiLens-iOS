import Foundation

// BeadFeatureProtection — 特征保护掩码构建（边缘/暗部/花纹边界/注意力热图）。
// 逐行翻译自源端 shared/.../bead/BeadFeatureProtection.ets（99 行）。

private func insideFaceRoi(_ x: Int, _ y: Int, _ faceRoi: CropArea?) -> Bool {
    guard let roi = faceRoi else { return false }
    return x >= roi.x && x < roi.x + roi.w && y >= roi.y && y < roi.y + roi.h
}

/// 构建保护掩码：标记边缘像素、暗部特征、亮邻暗格、花纹边界、语义注意力区域。
/// 对应源端 `buildProtectMask`。
public func buildProtectMask(
    _ pixels: [UInt8], w: Int, h: Int, empty: [UInt8],
    protectionStrength: Double = 0.6, faceRoi: CropArea? = nil,
    attentionHeatmap: [Float]? = nil
) -> [UInt8] {
    var mask = [UInt8](repeating: 0, count: w * h)
    var luminance = [Double](repeating: 0, count: w * h)
    for i in 0..<(w * h) {
        let pi = i * 4
        luminance[i] = (Double(pixels[pi]) * 0.2126 + Double(pixels[pi + 1]) * 0.7152 + Double(pixels[pi + 2]) * 0.0722) / 255
    }

    let strength = max(0, min(1, protectionStrength))
    let globalEdgeThreshold = 0.32 - strength * 0.15
    let headEdgeThreshold = 0.15 - strength * 0.05
    let globalDarkThreshold = 0.24 + strength * 0.11

    for y in 0..<h {
        for x in 0..<w {
            let i = y * w + x
            if empty[i] != 0 { continue }
            let lum = luminance[i]
            let left = luminance[y * w + max(0, x - 1)]
            let right = luminance[y * w + min(w - 1, x + 1)]
            let top = luminance[max(0, y - 1) * w + x]
            let bottom = luminance[min(h - 1, y + 1) * w + x]
            let edge = abs(right - left) + abs(bottom - top)

            let inHeadRegion = protectionStrength > 0 && insideFaceRoi(x, y, faceRoi)
            let attentionX = min(6, Int((Double(x) + 0.5) / Double(w) * 7))
            let attentionY = min(6, Int((Double(y) + 0.5) / Double(h) * 7))
            let attention: Double = (attentionHeatmap != nil && attentionHeatmap!.count == 49)
                ? Double(attentionHeatmap![attentionY * 7 + attentionX]) : 0
            let inSemanticRegion = attention >= 0.58
            let edgeThreshold = inHeadRegion ? headEdgeThreshold : globalEdgeThreshold
            let darkThreshold = inHeadRegion ? globalDarkThreshold : 0.24

            // 源端：y < Math.floor(h * 0.82)。注意 floor 使 h=3 时阈值为 2 → y=2 不保护。
            let darkFeature = lum < darkThreshold && y < floorInt(Double(h) * 0.82)
            var nearDark = false
            if lum > 0.78 {
                let searchRadius = inHeadRegion ? 2 : 1
                outer: for dy in -searchRadius...searchRadius {
                    for dx in -searchRadius...searchRadius {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0 && nx < w && ny >= 0 && ny < h && luminance[ny * w + nx] < darkThreshold {
                            nearDark = true
                            break outer
                        }
                    }
                }
            }
            if edge > edgeThreshold || darkFeature || nearDark || inSemanticRegion { mask[i] = 1 }
        }
    }

    // 花纹边界保护：只保护 run 的左右边界 ±1 格
    if strength > 0.3 {
        let runThreshold = max(3, Int(Double(min(w, h)) * 0.08))
        for y in 1..<(h - 1) {
            var runStart = 0
            var runColor = luminance[y * w] > 0.5 ? 1 : 0
            for x in 1...w {
                let c = x < w ? (luminance[y * w + x] > 0.5 ? 1 : 0) : -1
                if c != runColor || x == w {
                    if x - runStart >= runThreshold && y > 0 && y < h - 1 {
                        let protectPositions = [runStart, runStart + 1, x - 2, x - 1]
                        for bx in protectPositions {
                            if bx >= 0 && bx < w {
                                if empty[y * w + bx] == 0 { mask[y * w + bx] = 1 }
                                if y > 0 && empty[(y - 1) * w + bx] == 0 { mask[(y - 1) * w + bx] = 1 }
                                if y < h - 1 && empty[(y + 1) * w + bx] == 0 { mask[(y + 1) * w + bx] = 1 }
                            }
                        }
                    }
                    runStart = x
                    runColor = c
                }
            }
        }
    }

    return mask
}
