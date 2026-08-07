import Foundation

// VirtualPaletteBuilder — 加权 Median Cut 虚拟色板提取
// 逐行翻译自源端 shared/.../bead/VirtualPaletteBuilder.ets。
//
// 从像素采样中构建指定数量的虚拟颜色调色板。
// 支持主体 mask 加权，使主体颜色获得更多色板槽位。

// MARK: - 色彩桶

/// Median Cut 的切分单元。
private struct ColorBucket {
    var pixels: [Double]   // Lab 像素 flat array: [L,a,b, L,a,b, ...]
    var weights: [Double]  // 每个像素对应的权重
    var minL: Double, maxL: Double
    var minA: Double, maxA: Double
    var minB: Double, maxB: Double
    var totalWeight: Double
}

private func createBucket(pixels: [Double], weights: [Double]) -> ColorBucket {
    var minL = Double.infinity, maxL = -Double.infinity
    var minA = Double.infinity, maxA = -Double.infinity
    var minB = Double.infinity, maxB = -Double.infinity
    var totalWeight: Double = 0
    let count = pixels.count / 3
    for i in 0..<count {
        let L = pixels[i * 3]
        let a = pixels[i * 3 + 1]
        let b = pixels[i * 3 + 2]
        if L < minL { minL = L }; if L > maxL { maxL = L }
        if a < minA { minA = a }; if a > maxA { maxA = a }
        if b < minB { minB = b }; if b > maxB { maxB = b }
        totalWeight += weights[i]
    }
    return ColorBucket(pixels: pixels, weights: weights,
                       minL: minL, maxL: maxL,
                       minA: minA, maxA: maxA,
                       minB: minB, maxB: maxB,
                       totalWeight: totalWeight)
}

/// 沿 Lab 最长轴对桶做加权中位数切分。
private func splitBucket(_ bucket: ColorBucket) -> [ColorBucket] {
    let rangeL = bucket.maxL - bucket.minL
    let rangeA = bucket.maxA - bucket.minA
    let rangeB = bucket.maxB - bucket.minB

    var sortAxis = 0 // 0=L, 1=a, 2=b
    if rangeA >= rangeL && rangeA >= rangeB { sortAxis = 1 }
    else if rangeB >= rangeL && rangeB >= rangeA { sortAxis = 2 }

    // Build index array for sort
    let count = bucket.pixels.count / 3
    var sortIndices = Array(0..<count)

    sortIndices.sort { a, b in
        bucket.pixels[a * 3 + sortAxis] < bucket.pixels[b * 3 + sortAxis]
    }

    // Find weighted median split point
    let halfWeight = bucket.totalWeight / 2
    var accWeight: Double = 0
    var splitIdx = 0
    for i in 0..<sortIndices.count {
        accWeight += bucket.weights[sortIndices[i]]
        if accWeight >= halfWeight {
            splitIdx = i + 1
            break
        }
    }
    if splitIdx == 0 { splitIdx = 1 }
    if splitIdx >= sortIndices.count { splitIdx = sortIndices.count - 1 }

    var leftPixels: [Double] = []
    var leftWeights: [Double] = []
    var rightPixels: [Double] = []
    var rightWeights: [Double] = []

    for i in 0..<sortIndices.count {
        let idx = sortIndices[i]
        let base = idx * 3
        if i < splitIdx {
            leftPixels.append(bucket.pixels[base])
            leftPixels.append(bucket.pixels[base + 1])
            leftPixels.append(bucket.pixels[base + 2])
            leftWeights.append(bucket.weights[idx])
        } else {
            rightPixels.append(bucket.pixels[base])
            rightPixels.append(bucket.pixels[base + 1])
            rightPixels.append(bucket.pixels[base + 2])
            rightWeights.append(bucket.weights[idx])
        }
    }

    if leftPixels.isEmpty || rightPixels.isEmpty { return [bucket] }
    return [createBucket(pixels: leftPixels, weights: leftWeights),
            createBucket(pixels: rightPixels, weights: rightWeights)]
}

/// 计算桶的加权平均 Lab。
private func bucketAverage(_ bucket: ColorBucket) -> (Double, Double, Double) {
    var sumL: Double = 0, sumA: Double = 0, sumB: Double = 0, totalW: Double = 0
    let count = bucket.pixels.count / 3
    for i in 0..<count {
        let w = bucket.weights[i]
        sumL += bucket.pixels[i * 3] * w
        sumA += bucket.pixels[i * 3 + 1] * w
        sumB += bucket.pixels[i * 3 + 2] * w
        totalW += w
    }
    if totalW == 0 { return (128, 0, 0) }
    return (sumL / totalW, sumA / totalW, sumB / totalW)
}

// MARK: - Mulberry32 PRNG

/// 确定性伪随机数生成器 (Mulberry32)。逐位翻译自源端。
private final class Mulberry32 {
    private var seed: UInt32

    init(_ seed: Int) {
        // JS seed |= 0 → Int32 truncation
        self.seed = UInt32(bitPattern: Int32(truncatingIfNeeded: seed))
    }

    func next() -> Double {
        // seed = seed + 0x6D2B79F5 | 0
        seed = seed &+ 0x6D2B79F5

        // t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
        var t = (seed ^ (seed >> 15)) &* (1 | seed)

        // t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
        let imulResult = (t ^ (t >> 7)) &* (61 | t)
        t = (t &+ imulResult) ^ t

        // ((t ^ (t >>> 14)) >>> 0) / 4294967296
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
}

// MARK: - 辅助

@inline(__always)
private func clamp8(_ v: Double) -> Int {
    max(0, min(255, Int(v.rounded())))
}

// MARK: - 公共 API

/// 从 RGBA 像素数据中提取虚拟色板。
///
/// - Parameters:
///   - rgba: 源 RGBA 像素（每像素 4 字节）
///   - width: 图宽
///   - height: 图高
///   - count: 目标虚拟颜色数 (4–24)
///   - mask: 可选主体 mask（0=非主体，>0=主体）
///   - seed: 采样种子
/// - Returns: 虚拟色板数组
public func buildVirtualPalette(
    rgba: [UInt8],
    width: Int,
    height: Int,
    count: Int,
    mask: [UInt8]? = nil,
    seed: Int = 42
) -> [VirtualColor] {
    let totalPixels = width * height
    let maxSamples = min(totalPixels, 4000)
    let _ = Mulberry32(seed) // 源端声明 rand 但采样为步长驱动，保留以保持对齐

    // 加权采样：主体像素权重 3x，非主体权重 1x
    var sampledLab: [Double] = []
    var sampledWeights: [Double] = []
    let step = max(1, totalPixels / maxSamples)

    var i = 0
    while i < totalPixels {
        let pi = i * 4
        let a = rgba[pi + 3]
        if a < 128 { i += step; continue } // 跳过透明像素

        let lab = rgbToLab(Double(rgba[pi]), Double(rgba[pi + 1]), Double(rgba[pi + 2]))
        let rawMask = mask?[i] ?? 255
        let maskWeight = rawMask > 1 ? Double(rawMask) / 255.0 : Double(rawMask)
        let isSubject = mask == nil || maskWeight > 0
        let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
        // Do not let neutral background clutter consume virtual-palette slots.
        if mask != nil && !isSubject && chroma < 6 && lab.L > 20 && lab.L < 88 {
            i += step; continue
        }
        let weight = mask != nil ? max(0.15, 1 + 2 * maskWeight) : 3
        sampledLab.append(lab.L)
        sampledLab.append(lab.a)
        sampledLab.append(lab.b)
        sampledWeights.append(weight)
        i += step
    }

    if sampledLab.isEmpty {
        // 空图像返回默认灰色
        let rgb = labToRgb(50, 0, 0)
        return [VirtualColor(id: "vc_0", rgb: [rgb.r, rgb.g, rgb.b], lab: [50, 0, 0])]
    }

    // Median Cut
    var buckets: [ColorBucket] = [createBucket(pixels: sampledLab, weights: sampledWeights)]
    let targetCount = max(1, min(count, 24))

    while buckets.count < targetCount {
        // 找到总权重最大的桶进行切分
        var maxIdx = 0
        var maxW: Double = 0
        for i in 0..<buckets.count {
            if buckets[i].totalWeight > maxW && buckets[i].pixels.count >= 6 {
                maxW = buckets[i].totalWeight
                maxIdx = i
            }
        }
        if maxW == 0 { break }
        let split = splitBucket(buckets[maxIdx])
        buckets.replaceSubrange(maxIdx...maxIdx, with: split)
    }

    // 将桶转为虚拟颜色
    var palette: [VirtualColor] = []
    for i in 0..<buckets.count {
        let avg = bucketAverage(buckets[i])
        let rgb = labToRgb(avg.0, avg.1, avg.2)
        palette.append(VirtualColor(
            id: "vc_\(i)",
            rgb: [clamp8(Double(rgb.r)), clamp8(Double(rgb.g)), clamp8(Double(rgb.b))],
            lab: [avg.0, avg.1, avg.2]
        ))
    }

    return palette
}

// MARK: - 灰色合并

/// 灰色合并结果。
public struct MergeGrayResult: Equatable, Sendable {
    public var palette: [VirtualColor]
    public var remap: [UInt8]

    public init(palette: [VirtualColor], remap: [UInt8]) {
        self.palette = palette
        self.remap = remap
    }
}

/// 合并虚拟色板中色度接近的灰色虚拟色 — 减少低饱和度碎片槽位。
public func mergeGrayVirtualColors(
    _ palette: [VirtualColor],
    chromaThreshold: Double = 10,
    maxLabDist: Double = 18
) -> MergeGrayResult {
    let n = palette.count
    var remap = [UInt8](repeating: 0, count: n)
    for i in 0..<n { remap[i] = UInt8(i) }

    // 找出所有低色度虚拟色
    var graySet = Set<Int>()
    for i in 0..<n {
        let ch = (palette[i].lab[1] * palette[i].lab[1] + palette[i].lab[2] * palette[i].lab[2]).squareRoot()
        if ch < chromaThreshold { graySet.insert(i) }
    }
    if graySet.count <= 1 { return MergeGrayResult(palette: palette, remap: remap) }

    // 合并 Lab 距离在 maxLabDist 内的灰色对
    var merged = Set<Int>()
    let graySorted = graySet.sorted()
    for i in graySorted {
        if merged.contains(i) { continue }
        for j in graySorted {
            if j <= i || merged.contains(j) { continue }
            let dL = palette[i].lab[0] - palette[j].lab[0]
            let da = palette[i].lab[1] - palette[j].lab[1]
            let db = palette[i].lab[2] - palette[j].lab[2]
            let dist = (dL * dL + da * da + db * db).squareRoot()
            if dist < maxLabDist {
                remap[j] = UInt8(i)
                merged.insert(j)
            }
        }
    }

    if merged.isEmpty { return MergeGrayResult(palette: palette, remap: remap) }

    // 构建压缩后的色板
    var used = Set<Int>()
    for i in 0..<n { used.insert(Int(remap[i])) }
    var newPalette: [VirtualColor] = []
    var oldToNew: [Int: Int] = [:]
    var newIdx = 0
    for oldIdx in used.sorted() {
        oldToNew[oldIdx] = newIdx
        let src = palette[oldIdx]
        newPalette.append(VirtualColor(id: "vc_\(newIdx)", rgb: src.rgb, lab: src.lab))
        newIdx += 1
    }
    var finalRemap = [UInt8](repeating: 0, count: n)
    for i in 0..<n {
        finalRemap[i] = UInt8(oldToNew[Int(remap[i])] ?? i)
    }

    return MergeGrayResult(palette: newPalette, remap: finalRemap)
}

// MARK: - 像素映射

/// 将虚拟色板中的每个像素映射到最近的虚拟颜色。
public func mapPixelsToVirtualPalette(
    rgba: [UInt8],
    width: Int,
    height: Int,
    palette: [VirtualColor],
    pose: BeadPoseData? = nil
) -> [UInt8] {
    var indices = [UInt8](repeating: 0, count: width * height)
    let count = width * height

    // T2c: 预计算有效关键点像素坐标（眼睛 0,1 + 鼻子 2）
    let activeKpts = activeKeypoints(from: pose, width: width, height: height)
    let kptRadius: Double = 1.2 // 格为单位的刚性锁定半径
    let kptRadiusSq = kptRadius * kptRadius

    for i in 0..<count {
        let pi = i * 4
        if rgba[pi + 3] < 128 {
            indices[i] = 255 // 标记为透明/空
            continue
        }
        let pixelLab = rgbToLab(Double(rgba[pi]), Double(rgba[pi + 1]), Double(rgba[pi + 2]))
        let isDark = pixelLab.L < 35

        // T2c: 判断像素是否在关键点刚性锁定范围内
        var nearKpt = false
        if isDark && !activeKpts.isEmpty {
            let x = i % width
            let y = i / width
            for kpt in activeKpts {
                let dx = Double(x) - kpt.px
                let dy = Double(y) - kpt.py
                if dx * dx + dy * dy < kptRadiusSq {
                    nearKpt = true
                    break
                }
            }
        }

        var bestIdx = 0
        var bestDist = Double.infinity
        for j in 0..<palette.count {
            let virtualLab = LabColor(L: palette[j].lab[0], a: palette[j].lab[1], b: palette[j].lab[2])
            var dist = paletteMatchDistance(pixelLab, virtualLab, petFriendlyPenalty: 0)

            // T2c: 暗色斑块刚性锁定 — 关键点附近的暗色像素拒绝被映射到偏亮候选
            if nearKpt && virtualLab.L > 25 {
                dist += 5.0 * max(0, virtualLab.L - 25) // 刚性惩罚
            }

            if dist < bestDist {
                bestDist = dist
                bestIdx = j
            }
        }
        indices[i] = UInt8(bestIdx)
    }

    return indices
}
