import Foundation

// BeadPaletteSelection — Median Cut 主色提取 + 色卡选色。
// 逐行翻译自源端 shared/.../bead/BeadPaletteSelection.ets。

// MARK: - 内部辅助类型

/// 中位切割的颜色箱。对应源端 `ColorBox`。
private struct ColorBox {
    var colors: [LabColor] = []
    var weights: [Double] = []
}

/// 候选条目。对应源端 `CandidateEntry`。
private struct CandidateEntry {
    var idx: Int
    var minDist: Double
}

// MARK: - 标签距离

/// 带标签的色板匹配距离：在 paletteMatchDistance 基础上叠加宠物毛色偏好。
/// 对应源端 `taggedPaletteDistance`。
public func taggedPaletteDistance(
    _ source: LabColor, _ candidate: LabColor,
    color: BeadColor, petFriendlyPenalty: Double
) -> Double {
    var distance = paletteMatchDistance(source, candidate, petFriendlyPenalty: petFriendlyPenalty)
    if petFriendlyPenalty <= 0 || color.tags == nil { return distance }
    let tags = color.tags!
    if tags.contains(.avoidForFur) { distance += petFriendlyPenalty * 0.75 }
    let warmSource = source.a > 1 && source.b > 2
    if (warmSource && (tags.contains(.orangeFur) || tags.contains(.brownFur))) ||
        tags.contains(.warmWhite) || tags.contains(.cream) {
        distance = max(0, distance - petFriendlyPenalty * 0.2)
    }
    return distance
}

// MARK: - Median Cut 主色提取

/// 从照片像素中提取 dominant colors（中位切割减色）。
/// 对应源端 `medianCutExtract`。
public func medianCutExtract(
    pixels: [UInt8], pixelCount: Int, targetColors: Int,
    empty: [UInt8]? = nil, protectMask: [UInt8]? = nil
) -> [LabColor] {
    // 采样（大量像素时只取部分加速）
    let sampleStep = max(1, floorInt(Double(pixelCount) / 5000))
    var sampled: [LabColor] = []
    var sampledWeights: [Double] = []
    var i = 0
    while i < pixelCount {
        let pi = i * 4
        if pixels[pi + 3] < 128 { i += sampleStep; continue }  // 跳过透明
        if let empty, empty[i] != 0 { i += sampleStep; continue }
        sampled.append(rgbToLab(Double(pixels[pi]), Double(pixels[pi + 1]), Double(pixels[pi + 2])))
        let weight = (protectMask != nil && protectMask![i] != 0) ? 3.0 : 1.0
        sampledWeights.append(weight)
        i += sampleStep
    }
    if sampled.isEmpty { return [rgbToLab(128, 128, 128)] }

    var boxes: [ColorBox] = [ColorBox(colors: sampled, weights: sampledWeights)]

    while boxes.count < targetColors {
        // 找最大范围的 box
        var maxRange: Double = -1
        var maxIdx = 0
        for bi in 0..<boxes.count {
            if boxes[bi].colors.count < 2 { continue }
            var lMin = Double.infinity, lMax = -Double.infinity
            var aMin = Double.infinity, aMax = -Double.infinity
            var bMin = Double.infinity, bMax = -Double.infinity
            for c in boxes[bi].colors {
                if c.L < lMin { lMin = c.L }; if c.L > lMax { lMax = c.L }
                if c.a < aMin { aMin = c.a }; if c.a > aMax { aMax = c.a }
                if c.b < bMin { bMin = c.b }; if c.b > bMax { bMax = c.b }
            }
            var totalWeight: Double = 0
            for weight in boxes[bi].weights { totalWeight += weight }
            let range = max(lMax - lMin, aMax - aMin, bMax - bMin) * totalWeight
            if range > maxRange { maxRange = range; maxIdx = bi }
        }
        if maxRange <= 0 { break }

        let box = boxes[maxIdx]
        // 找最宽通道
        var lMin = Double.infinity, lMax = -Double.infinity
        var aMin = Double.infinity, aMax = -Double.infinity
        var bMin = Double.infinity, bMax = -Double.infinity
        for c in box.colors {
            if c.L < lMin { lMin = c.L }; if c.L > lMax { lMax = c.L }
            if c.a < aMin { aMin = c.a }; if c.a > aMax { aMax = c.a }
            if c.b < bMin { bMin = c.b }; if c.b > bMax { bMax = c.b }
        }
        let lRange = lMax - lMin, aRange = aMax - aMin, bRange = bMax - bMin
        var ch = 0
        if aRange >= lRange && aRange >= bRange { ch = 1 }
        else if bRange >= lRange && bRange >= aRange { ch = 2 }

        var order = Array(0..<box.colors.count)
        order.sort { (left, right) -> Bool in
            if ch == 0 { return box.colors[left].L < box.colors[right].L }
            if ch == 1 { return box.colors[left].a < box.colors[right].a }
            return box.colors[left].b < box.colors[right].b
        }
        var totalWeight: Double = 0
        for weight in box.weights { totalWeight += weight }
        var splitWeight: Double = 0
        var mid = 1
        while mid < order.count {
            splitWeight += box.weights[order[mid - 1]]
            if splitWeight >= totalWeight / 2 { break }
            mid += 1
        }
        var leftColors: [LabColor] = [], leftWeights: [Double] = []
        var rightColors: [LabColor] = [], rightWeights: [Double] = []
        for k in 0..<order.count {
            let idx = order[k]
            if k < mid { leftColors.append(box.colors[idx]); leftWeights.append(box.weights[idx]) }
            else { rightColors.append(box.colors[idx]); rightWeights.append(box.weights[idx]) }
        }

        boxes.remove(at: maxIdx)
        if !leftColors.isEmpty { boxes.append(ColorBox(colors: leftColors, weights: leftWeights)) }
        if !rightColors.isEmpty { boxes.append(ColorBox(colors: rightColors, weights: rightWeights)) }
    }

    // 每个 box 取平均色
    var result: [LabColor] = []
    for box in boxes {
        var l: Double = 0, a: Double = 0, b: Double = 0, weightSum: Double = 0
        for k in 0..<box.colors.count {
            let weight = box.weights[k]
            l += box.colors[k].L * weight
            a += box.colors[k].a * weight
            b += box.colors[k].b * weight
            weightSum += weight
        }
        result.append(LabColor(L: l / weightSum, a: a / weightSum, b: b / weightSum))
    }
    return result
}

// MARK: - 色卡选色

/// 从色卡池中选出最适合照片的 N 色。对应源端 `selectBestPaletteColors`。
public func selectBestPaletteColors(
    dominantColors: [LabColor],
    allPaletteColors: [BeadColor],
    maxColors: Int,
    lightnessBucketCoverage: Double,
    petFriendlyPenalty: Double,
    sourcePixels: [UInt8]? = nil,
    empty: [UInt8]? = nil
) -> [BeadColor] {
    let paletteLab = precomputePaletteLab(allPaletteColors)
    var selected = Set<Int>()

    // Reserve neutral representatives before chromatic dominant colors fill a
    // reduced palette. This keeps gray-white highlights and shadows mappable.
    if let sourcePixels {
        let bounds = [0, 35, 72, 101]
        for bucket in 0..<3 where selected.count < maxColors {
            var sumL: Double = 0
            var count = 0
            let pixelTotal = sourcePixels.count / 4
            for i in 0..<pixelTotal {
                if let empty, empty[i] != 0 { continue }
                let pi = i * 4
                let lab = rgbToLab(Double(sourcePixels[pi]), Double(sourcePixels[pi + 1]), Double(sourcePixels[pi + 2]))
                if lab.L >= Double(bounds[bucket]) && lab.L < Double(bounds[bucket + 1]) && labChroma(lab) < 24 {
                    sumL += lab.L
                    count += 1
                }
            }
            if count == 0 { continue }
            let target = LabColor(L: sumL / Double(count), a: 0, b: 0)
            var bestIdx = -1
            var bestDist = Double.infinity
            for i in 0..<paletteLab.count {
                if labChroma(paletteLab[i]) > 24 { continue }
                let dist = weightedDeltaE(target, paletteLab[i])
                if dist < bestDist { bestDist = dist; bestIdx = i }
            }
            if bestIdx >= 0 { selected.insert(bestIdx) }
        }
    }

    // 为照片中实际出现的暗部/中间调/高光预留代表色。
    if lightnessBucketCoverage > 0 {
        let bucketBounds = [0, 35, 72, 101]
        for bucket in 0..<3 {
            let inBucket = dominantColors.filter { color in
                color.L >= Double(bucketBounds[bucket]) && color.L < Double(bucketBounds[bucket + 1])
            }
            if inBucket.isEmpty { continue }
            var meanL: Double = 0, meanA: Double = 0, meanB: Double = 0
            for color in inBucket {
                meanL += color.L; meanA += color.a; meanB += color.b
            }
            let n = Double(inBucket.count)
            let mean = LabColor(L: meanL / n, a: meanA / n, b: meanB / n)
            var bestIdx = -1
            var bestDist = Double.infinity
            let margin = (1 - lightnessBucketCoverage) * 20
            let lower = max(0, Double(bucketBounds[bucket]) - margin)
            let upper = min(101, Double(bucketBounds[bucket + 1]) + margin)
            // 高光桶选色：如果 dominant chroma 低，优先选低 chroma 候选，避免白色被蓝化
            let dominantChroma = labChroma(mean)
            for i in 0..<paletteLab.count {
                if paletteLab[i].L < lower || paletteLab[i].L >= upper { continue }
                // 高光桶 + 低 chroma dominant 时，跳过高 chroma 候选
                if bucket == 2 && dominantChroma < 12 {
                    let cChroma = labChroma(paletteLab[i])
                    if cChroma > 16 && paletteLab[i].b < -5 { continue }
                }
                let dist = taggedPaletteDistance(mean, paletteLab[i], color: allPaletteColors[i], petFriendlyPenalty: petFriendlyPenalty)
                if dist < bestDist { bestDist = dist; bestIdx = i }
            }
            if bestIdx >= 0 && selected.count < maxColors { selected.insert(bestIdx) }
        }
    }

    // 对每个 dominant color 找最近的色卡色
    for dc in dominantColors {
        var bestIdx = 0
        var bestDist = Double.infinity
        for i in 0..<paletteLab.count {
            let dist = taggedPaletteDistance(dc, paletteLab[i], color: allPaletteColors[i], petFriendlyPenalty: petFriendlyPenalty)
            if dist < bestDist { bestDist = dist; bestIdx = i }
        }
        if selected.count < maxColors { selected.insert(bestIdx) }
    }

    // 如果还不够，加入尚未选中的色卡色中与 dominant 色最近的
    if selected.count < maxColors {
        var candidates: [CandidateEntry] = []
        for i in 0..<allPaletteColors.count {
            if selected.contains(i) { continue }
            var minDist = Double.infinity
            for dc in dominantColors {
                let dist = taggedPaletteDistance(dc, paletteLab[i], color: allPaletteColors[i], petFriendlyPenalty: petFriendlyPenalty)
                if dist < minDist { minDist = dist }
            }
            candidates.append(CandidateEntry(idx: i, minDist: minDist))
        }
        candidates.sort { $0.minDist < $1.minDist }
        for c in candidates {
            if selected.count >= maxColors { break }
            selected.insert(c.idx)
        }
    }

    return selected.sorted().map { allPaletteColors[$0] }
}
