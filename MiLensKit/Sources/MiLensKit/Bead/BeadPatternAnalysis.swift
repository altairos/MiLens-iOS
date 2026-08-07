import Foundation

// BeadPatternAnalysis — 诊断数据计算 + 色级少用色合并。
// 逐行翻译自源端 shared/.../bead/BeadPatternAnalysis.ets。
// 注意：此模块的 mergeTinyColors 是**色级合并**（全色替换），与 BeadDenoise 的
// mergeTinyColors（区域级合并）不同。Swift 侧命名为 mergeTinyColorsByPalette 避免冲突。

// MARK: - 色级少用色合并

/// 色级少用色合并结果。对应源端 `MergeResult`（BeadPaletteSelection.ets）。
public struct MergeResult: Equatable {
    public var indices: [UInt16]
    public var paletteUsed: [BeadColor]
    public var mergedCount: Int
}

/// 色级少用色合并：将使用量低于 threshold 的颜色**全局**替换为最近非 tiny 色。
/// 对应源端 `BeadPatternAnalysis.mergeTinyColors`（不同于 BeadDenoise 的区域级版本）。
/// 保护色（protectMask 标记的像素所用的颜色）不被合并。
public func mergeTinyColorsByPalette(
    _ indices: [UInt16], w: Int, h: Int,
    paletteUsed: [BeadColor], threshold: Int,
    protectMask: [UInt8]? = nil, empty: [UInt8]? = nil
) -> MergeResult {
    // 统计每色数量
    var counts: [Int: Int] = [:]
    for i in 0..<indices.count {
        if empty != nil && empty![i] != 0 { continue }
        counts[Int(indices[i]), default: 0] += 1
    }

    // 找出需要合并的颜色
    var tinySet = Set<Int>()
    for (idx, count) in counts {
        if count < threshold { tinySet.insert(idx) }
    }
    // 保护色使用的颜色从 tiny 集合中移除
    if let protectMask {
        for i in 0..<indices.count {
            if protectMask[i] != 0 { tinySet.remove(Int(indices[i])) }
        }
    }

    if tinySet.isEmpty {
        return MergeResult(indices: indices, paletteUsed: paletteUsed, mergedCount: 0)
    }

    // 为每个 tiny 色找最近的非 tiny 色
    let paletteLab = precomputePaletteLab(paletteUsed)
    var mergeMap: [Int: Int] = [:]
    for tinyIdx in tinySet {
        var bestIdx = 0
        var bestDist = Double.infinity
        for i in 0..<paletteUsed.count {
            if tinySet.contains(i) { continue }
            let dist = weightedDeltaE(paletteLab[tinyIdx], paletteLab[i])
            if dist < bestDist { bestDist = dist; bestIdx = i }
        }
        mergeMap[tinyIdx] = bestIdx
    }

    // 执行合并
    var newIndices = indices
    for i in 0..<newIndices.count {
        if empty != nil && empty![i] != 0 { continue }
        if let mapped = mergeMap[Int(newIndices[i])] {
            newIndices[i] = UInt16(mapped)
        }
    }

    // 重建 paletteUsed（只保留使用中的颜色）
    var usedSet = Set<Int>()
    for i in 0..<newIndices.count {
        if empty == nil || empty![i] == 0 { usedSet.insert(Int(newIndices[i])) }
    }
    var newPalette: [BeadColor] = []
    var oldToNew: [Int: Int] = [:]
    var newIdx = 0
    for oldIdx in usedSet.sorted() {
        newPalette.append(paletteUsed[oldIdx])
        oldToNew[oldIdx] = newIdx
        newIdx += 1
    }
    for i in 0..<newIndices.count {
        if empty != nil && empty![i] != 0 { continue }
        if let mapped = oldToNew[Int(newIndices[i])] {
            newIndices[i] = UInt16(mapped)
        }
    }

    return MergeResult(indices: newIndices, paletteUsed: newPalette, mergedCount: tinySet.count)
}

// MARK: - 诊断数据计算

/// 计算诊断数据：色差、孤立像素、少用色、中性色偏移、白→冷、黑/轮廓占比。
/// 对应源端 `computeDiagnostics`。需要原图像素（RGBA）作为色差基准。
public func computeDiagnostics(
    indices: [UInt16], w: Int, h: Int,
    paletteUsed: [BeadColor], originalPixels: [UInt8],
    empty: [UInt8]? = nil
) -> PatternDiagnostics {
    var totalPixels = 0
    var totalDeltaE = 0.0
    var maxDeltaE = 0.0
    var isolatedCount = 0
    let paletteLab = precomputePaletteLab(paletteUsed)

    for y in 0..<h {
        for x in 0..<w {
            let i = y * w + x
            if empty != nil && empty![i] != 0 { continue }
            totalPixels += 1
            let pi = i * 4
            let idx = Int(indices[i])

            // 色差计算
            let origLab = rgbToLab(Double(originalPixels[pi]), Double(originalPixels[pi + 1]), Double(originalPixels[pi + 2]))
            if idx < paletteLab.count {
                let dl = origLab.L - paletteLab[idx].L
                let da = origLab.a - paletteLab[idx].a
                let db = origLab.b - paletteLab[idx].b
                let de = sqrt(dl * dl + da * da + db * db)
                totalDeltaE += de
                if de > maxDeltaE { maxDeltaE = de }
            }

            // 孤立像素检测（4 邻域无同色）
            let myColor = idx
            var sameNeighbor = false
            let left = i - 1, right = i + 1, up = i - w, down = i + w
            if x > 0 && (empty == nil || empty![left] == 0) && Int(indices[left]) == myColor { sameNeighbor = true }
            if x < w - 1 && (empty == nil || empty![right] == 0) && Int(indices[right]) == myColor { sameNeighbor = true }
            if y > 0 && (empty == nil || empty![up] == 0) && Int(indices[up]) == myColor { sameNeighbor = true }
            if y < h - 1 && (empty == nil || empty![down] == 0) && Int(indices[down]) == myColor { sameNeighbor = true }
            if !sameNeighbor { isolatedCount += 1 }
        }
    }

    // 少用量颜色统计
    let threshold = minColorUsageThreshold(totalPixels)
    var counts: [Int: Int] = [:]
    for i in 0..<indices.count {
        if empty != nil && empty![i] != 0 { continue }
        counts[Int(indices[i]), default: 0] += 1
    }
    var tinyCount = 0
    for (_, count) in counts { if count < threshold { tinyCount += 1 } }

    var usedSet = Set<Int>()
    for i in 0..<indices.count {
        if empty == nil || empty![i] == 0 { usedSet.insert(Int(indices[i])) }
    }

    // 改进方案2 新增诊断指标
    var neutralHueShiftCount = 0
    var whiteToCoolCount = 0
    var blackCount = 0
    var outlineCount = 0

    for y in 0..<h {
        for x in 0..<w {
            let i = y * w + x
            if empty != nil && empty![i] != 0 { continue }
            let pi = i * 4
            let idx = Int(indices[i])
            if idx >= paletteLab.count { continue }

            let origLab = rgbToLab(Double(originalPixels[pi]), Double(originalPixels[pi + 1]), Double(originalPixels[pi + 2]))
            let origChroma = sqrt(origLab.a * origLab.a + origLab.b * origLab.b)
            let beadLab = paletteLab[idx]
            let beadChroma = sqrt(beadLab.a * beadLab.a + beadLab.b * beadLab.b)

            // 中性色被映射到有色相颜色
            if origChroma < 8 && beadChroma > 14 {
                neutralHueShiftCount += 1
            }
            // 高亮低饱和源色被映射到冷色
            if origLab.L > 75 && origChroma < 12 && beadLab.b < -3 {
                whiteToCoolCount += 1
            }
            // 黑/近黑占比
            if beadLab.L < 20 {
                blackCount += 1
            }
            // 轮廓色（id 含 _dark 或 _outline_）
            let colorId = idx < paletteUsed.count ? paletteUsed[idx].id : ""
            if colorId.contains("_dark") || colorId.contains("_outline_") {
                outlineCount += 1
            }
        }
    }

    func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
    func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    return PatternDiagnostics(
        averageDeltaE: totalPixels > 0 ? round1(totalDeltaE / Double(totalPixels)) : 0,
        maxDeltaE: round1(maxDeltaE),
        usedColorCount: usedSet.count,
        tinyColorCount: tinyCount,
        isolatedPixelRatio: totalPixels > 0 ? round3(Double(isolatedCount) / Double(totalPixels)) : 0,
        neutralHueShiftRatio: totalPixels > 0 ? round3(Double(neutralHueShiftCount) / Double(totalPixels)) : 0,
        whiteToCoolRatio: totalPixels > 0 ? round3(Double(whiteToCoolCount) / Double(totalPixels)) : 0,
        outlineCoverageRatio: totalPixels > 0 ? round3(Double(outlineCount) / Double(totalPixels)) : 0,
        blackCoverageRatio: totalPixels > 0 ? round3(Double(blackCount) / Double(totalPixels)) : 0
    )
}
