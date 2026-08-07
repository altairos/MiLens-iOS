import Foundation

// BeadDither — Floyd-Steinberg 抖动（含 serpentine 变体）+ 自适应 Bayer 有序抖动。
// 逐行翻译自源端 shared/.../bead/BeadDither.ets。
// 输入/输出均为 RGBA [UInt8] 平坦数组（源端 Uint8ClampedArray；Swift 手动 clamp）。

// MARK: - 通用 clamp 辅助

@inline(__always)
private func clampByte(_ v: Double) -> UInt8 {
    return UInt8(max(0, min(255, v.rounded())))
}

/// 将 RGBColor 的 Int 通道（0–255）安全转为 UInt8（源端 Uint8ClampedArray 自动 clamp）。
@inline(__always)
private func toByte(_ v: Int) -> UInt8 {
    return UInt8(max(0, min(255, v)))
}

// MARK: - Floyd-Steinberg

/// Floyd-Steinberg 误差扩散抖动。对应源端 `applyFloydSteinberg`。
/// 原地修改 pixels（RGBA），误差按 7/16, 3/16, 5/16, 1/16 扩散。
public func applyFloydSteinberg(
    _ pixels: inout [UInt8], w: Int, h: Int,
    paletteLab: [LabColor], strength: Double,
    protectMask: [UInt8]? = nil, empty: [UInt8]? = nil, petFriendlyPenalty: Double = 0
) {
    var errR = [Double](repeating: 0, count: w * h)
    var errG = [Double](repeating: 0, count: w * h)
    var errB = [Double](repeating: 0, count: w * h)

    for y in 0..<h {
        for x in 0..<w {
            let idx = y * w + x
            let pIdx = idx * 4
            if empty != nil && empty![idx] != 0 { continue }

            let oldR = max(0, min(255, Double(pixels[pIdx]) + errR[idx]))
            let oldG = max(0, min(255, Double(pixels[pIdx + 1]) + errG[idx]))
            let oldB = max(0, min(255, Double(pixels[pIdx + 2]) + errB[idx]))

            let lab = rgbToLab(oldR, oldG, oldB)
            let nearest = findNearestBeadColor(lab.L, lab.a, lab.b, paletteLab: paletteLab, petFriendlyPenalty: petFriendlyPenalty)
            let beadIdx = nearest.index
            let nearestLab = paletteLab[beadIdx]
            let newRgb = labToRgb(nearestLab.L, nearestLab.a, nearestLab.b)

            let localStrength = (protectMask != nil && protectMask![idx] != 0) ? 0.0 : strength
            let dR = (oldR - Double(newRgb.r)) * localStrength
            let dG = (oldG - Double(newRgb.g)) * localStrength
            let dB = (oldB - Double(newRgb.b)) * localStrength

            pixels[pIdx] = toByte(newRgb.r)
            pixels[pIdx + 1] = toByte(newRgb.g)
            pixels[pIdx + 2] = toByte(newRgb.b)
            
            if x + 1 < w {
                let ni = idx + 1
                if empty == nil || empty![ni] == 0 {
                    errR[ni] += dR * 7 / 16
                    errG[ni] += dG * 7 / 16
                    errB[ni] += dB * 7 / 16
                }
            }
            if y + 1 < h {
                if x - 1 >= 0 {
                    let ni = (y + 1) * w + x - 1
                    if empty == nil || empty![ni] == 0 {
                        errR[ni] += dR * 3 / 16
                        errG[ni] += dG * 3 / 16
                        errB[ni] += dB * 3 / 16
                    }
                }
                let down = (y + 1) * w + x
                if empty == nil || empty![down] == 0 {
                    errR[down] += dR * 5 / 16
                    errG[down] += dG * 5 / 16
                    errB[down] += dB * 5 / 16
                }
                if x + 1 < w {
                    let ni = (y + 1) * w + x + 1
                    if empty == nil || empty![ni] == 0 {
                        errR[ni] += dR * 1 / 16
                        errG[ni] += dG * 1 / 16
                        errB[ni] += dB * 1 / 16
                    }
                }
            }
        }
    }
}

// MARK: - Floyd-Steinberg Serpentine

/// Floyd-Steinberg 蛇形扫描变体。偶数行左→右，奇数行右→左，减少方向性纹理伪影。
/// 对应源端 `applyFloydSteinbergSerpentine`。
public func applyFloydSteinbergSerpentine(
    _ pixels: inout [UInt8], w: Int, h: Int,
    paletteLab: [LabColor], strength: Double,
    protectMask: [UInt8]? = nil, empty: [UInt8]? = nil, petFriendlyPenalty: Double = 0
) {
    var errR = [Double](repeating: 0, count: w * h)
    var errG = [Double](repeating: 0, count: w * h)
    var errB = [Double](repeating: 0, count: w * h)

    for y in 0..<h {
        let leftToRight = (y % 2 == 0)
        let xStart = leftToRight ? 0 : w - 1
        let xEnd = leftToRight ? w : -1
        let xStep = leftToRight ? 1 : -1

        var x = xStart
        while x != xEnd {
            let idx = y * w + x
            let pIdx = idx * 4
            if empty != nil && empty![idx] != 0 { x += xStep; continue }

            let oldR = max(0, min(255, Double(pixels[pIdx]) + errR[idx]))
            let oldG = max(0, min(255, Double(pixels[pIdx + 1]) + errG[idx]))
            let oldB = max(0, min(255, Double(pixels[pIdx + 2]) + errB[idx]))

            let lab = rgbToLab(oldR, oldG, oldB)
            let nearest = findNearestBeadColor(lab.L, lab.a, lab.b, paletteLab: paletteLab, petFriendlyPenalty: petFriendlyPenalty)
            let beadIdx = nearest.index
            let nearestLab = paletteLab[beadIdx]
            let newRgb = labToRgb(nearestLab.L, nearestLab.a, nearestLab.b)

            let localStrength = (protectMask != nil && protectMask![idx] != 0) ? 0.0 : strength
            let dR = (oldR - Double(newRgb.r)) * localStrength
            let dG = (oldG - Double(newRgb.g)) * localStrength
            let dB = (oldB - Double(newRgb.b)) * localStrength

            pixels[pIdx] = toByte(newRgb.r)
            pixels[pIdx + 1] = toByte(newRgb.g)
            pixels[pIdx + 2] = toByte(newRgb.b)

            // 扩散方向随扫描方向翻转
            let fwd = leftToRight ? 1 : -1
            let bwd = leftToRight ? -1 : 1

            if x + fwd >= 0 && x + fwd < w {
                let ni = idx + fwd
                if empty == nil || empty![ni] == 0 {
                    errR[ni] += dR * 7 / 16
                    errG[ni] += dG * 7 / 16
                    errB[ni] += dB * 7 / 16
                }
            }
            if y + 1 < h {
                if x + bwd >= 0 && x + bwd < w {
                    let ni = (y + 1) * w + x + bwd
                    if empty == nil || empty![ni] == 0 {
                        errR[ni] += dR * 3 / 16
                        errG[ni] += dG * 3 / 16
                        errB[ni] += dB * 3 / 16
                    }
                }
                let down = (y + 1) * w + x
                if empty == nil || empty![down] == 0 {
                    errR[down] += dR * 5 / 16
                    errG[down] += dG * 5 / 16
                    errB[down] += dB * 5 / 16
                }
                if x + fwd >= 0 && x + fwd < w {
                    let ni = (y + 1) * w + x + fwd
                    if empty == nil || empty![ni] == 0 {
                        errR[ni] += dR * 1 / 16
                        errG[ni] += dG * 1 / 16
                        errB[ni] += dB * 1 / 16
                    }
                }
            }
            x += xStep
        }
    }
}

// MARK: - 自适应 Bayer 有序抖动

/// 4×4 Bayer 矩阵（归一化到 0–1）。
private let bayer4x4: [[Double]] = [
    [0.0 / 16, 8.0 / 16, 2.0 / 16, 10.0 / 16],
    [12.0 / 16, 4.0 / 16, 14.0 / 16, 6.0 / 16],
    [3.0 / 16, 11.0 / 16, 1.0 / 16, 9.0 / 16],
    [15.0 / 16, 7.0 / 16, 13.0 / 16, 5.0 / 16],
]

/// 计算 3×3 邻域的局部亮度标准差（sigmaL）。用于分类平坦/渐变/边缘区域。
/// 对应源端 `computeLocalSigmaL`（私有）。
private func computeLocalSigmaL(_ pixels: [UInt8], x: Int, y: Int, w: Int, h: Int, empty: [UInt8]?) -> Double {
    var sum = 0.0
    var sumSq = 0.0
    var count = 0
    for dy in -1...1 {
        for dx in -1...1 {
            let nx = x + dx
            let ny = y + dy
            if nx < 0 || nx >= w || ny < 0 || ny >= h { continue }
            let ni = ny * w + nx
            if empty != nil && empty![ni] != 0 { continue }
            let pi = ni * 4
            let lum = (Double(pixels[pi]) * 0.2126 + Double(pixels[pi + 1]) * 0.7152 + Double(pixels[pi + 2]) * 0.0722) / 255.0
            sum += lum
            sumSq += lum * lum
            count += 1
        }
    }
    if count < 2 { return 0 }
    let mean = sum / Double(count)
    return sqrt(max(0, sumSq / Double(count) - mean * mean)) * 100  // 缩放到 Lab 类范围
}

/// 判断两个 Lab 色是否属于同一亮度桶（暗/中/高光）。对应源端 `sameLightnessBucket`。
private func sameLightnessBucket(_ lab1: LabColor, _ lab2: LabColor) -> Bool {
    func bucket(_ L: Double) -> Int { L < 35 ? 0 : (L < 72 ? 1 : 2) }
    return bucket(lab1.L) == bucket(lab2.L)
}

/// 自适应 Bayer 有序抖动。对应源端 `applyAdaptiveBayerDither`。
/// - ≤29×29 网格：始终禁用。
/// - 平坦区（sigmaL < 3）：不抖动。
/// - 边缘区（sigmaL > 12）：不抖动。
/// - 渐变区（3 ≤ sigmaL ≤ 12）：4×4 Bayer 双近邻选择。
/// - 保护区和 Face ROI：不抖动。
public func applyAdaptiveBayerDither(
    _ pixels: inout [UInt8], w: Int, h: Int,
    paletteLab: [LabColor],
    protectMask: [UInt8]?,
    empty: [UInt8]?,
    faceRoi: CropArea?,
    petFriendlyPenalty: Double,
    indicesOut: inout [UInt16]
) {
    // ≤29×29 始终跳过
    if w <= 29 && h <= 29 { return }
    if paletteLab.count < 2 { return }

    // 根据网格大小决定抖动强度
    let maxDim = max(w, h)
    let ditherAmountL: Double
    if maxDim >= 80 {
        ditherAmountL = 6
    } else if maxDim >= 52 {
        ditherAmountL = 4
    } else {
        ditherAmountL = 3
    }
    _ = ditherAmountL  // 当前仅用于分类阈值，源端未在后续直接使用该值做额外缩放

    for y in 0..<h {
        for x in 0..<w {
            let idx = y * w + x
            if empty != nil && empty![idx] != 0 { continue }
            if protectMask != nil && protectMask![idx] != 0 { continue }

            // 跳过 Face ROI 像素
            if let roi = faceRoi, roi.w > 0, roi.h > 0,
               x >= roi.x, x < roi.x + roi.w,
               y >= roi.y, y < roi.y + roi.h {
                continue
            }

            // 局部梯度强度
            let sigmaL = computeLocalSigmaL(pixels, x: x, y: y, w: w, h: h, empty: empty)
            if sigmaL < 3 || sigmaL > 12 { continue }

            // 源色 Lab
            let pIdx = idx * 4
            let srcLab = rgbToLab(Double(pixels[pIdx]), Double(pixels[pIdx + 1]), Double(pixels[pIdx + 2]))

            // 找两个最近色
            var bestIdx = 0
            var bestDist = 1e18
            var secondIdx = -1
            var secondDist = 1e18
            for i in 0..<paletteLab.count {
                let d = paletteMatchDistance(srcLab, paletteLab[i], petFriendlyPenalty: petFriendlyPenalty)
                if d < bestDist {
                    secondDist = bestDist
                    secondIdx = bestIdx
                    bestDist = d
                    bestIdx = i
                } else if d < secondDist {
                    secondDist = d
                    secondIdx = i
                }
            }

            if secondIdx < 0 { continue }

            // 只在相近色之间抖动（避免大色相跳变）
            let de = deltaE76(paletteLab[bestIdx], paletteLab[secondIdx])
            if de > 18 { continue }
            if !sameLightnessBucket(paletteLab[bestIdx], paletteLab[secondIdx]) { continue }

            // 根据源色在 c1/c2 之间的位置计算混合概率
            let distToC1 = bestDist
            let distToC2 = secondDist
            let totalDist = distToC1 + distToC2
            let mixProb = totalDist > 0.001 ? distToC1 / totalDist : 0.5

            // 应用 Bayer 阈值
            let threshold = bayer4x4[y % 4][x % 4]
            let chosenIdx = threshold < mixProb ? secondIdx : bestIdx
            indicesOut[idx] = UInt16(chosenIdx)

            // 更新像素为选中色以保持一致性
            let chosenRgb = labToRgb(paletteLab[chosenIdx].L, paletteLab[chosenIdx].a, paletteLab[chosenIdx].b)
            pixels[pIdx] = toByte(chosenRgb.r)
            pixels[pIdx + 1] = toByte(chosenRgb.g)
            pixels[pIdx + 2] = toByte(chosenRgb.b)
        }
    }
}
