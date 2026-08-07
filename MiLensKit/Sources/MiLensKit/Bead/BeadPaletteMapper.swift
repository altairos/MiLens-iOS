import Foundation

// BeadPaletteMapper — 像素→色板映射 + 中性色走廊修正。
// 逐行翻译自源端 shared/.../bead/BeadPaletteMapper.ets（188 行）。
// 含中性色走廊检测、参考图中性像素重映射、最终中性色边缘清理。

private let mapperDirections: [(Int, Int)] = [(-1, 0), (1, 0), (0, -1), (0, 1)]

/// 将 RGBA 像素映射到最近色板色，含中性色走廊抑制。
/// 对应源端 `mapToPalette`。返回颜色索引数组。
public func mapToPalette(
    _ pixels: [UInt8], w: Int, h: Int, paletteLab: [LabColor],
    empty: [UInt8]? = nil, petFriendlyPenalty: Double = 0
) -> [UInt16] {
    var indices = [UInt16](repeating: 0, count: w * h)
    var sourceLab: [LabColor] = []
    for i in 0..<(w * h) {
        let pi = i * 4
        sourceLab.append(rgbToLab(Double(pixels[pi]), Double(pixels[pi + 1]), Double(pixels[pi + 2])))
    }

    for i in 0..<(w * h) {
        if empty != nil && empty![i] != 0 { continue }
        var lab = sourceLab[i]
        let chroma = labChroma(lab)
        if chroma >= 18 && chroma < 90 {
            let x = i % w
            let y = i / w
            for dir in mapperDirections {
                let x1 = x + dir.0, y1 = y + dir.1
                let x2 = x + dir.0 * 2, y2 = y + dir.1 * 2
                if x2 < 0 || x2 >= w || y2 < 0 || y2 >= h || x1 < 0 || x1 >= w || y1 < 0 || y1 >= h { continue }
                let n1 = sourceLab[y1 * w + x1]
                let n2 = sourceLab[y2 * w + x2]
                if labChroma(n1) < 22 && labChroma(n2) < 22 &&
                   abs(lab.L - n1.L) < 50 && abs(lab.L - n2.L) < 50 {
                    lab = LabColor(L: lab.L, a: lab.a * 0.2, b: lab.b * 0.2)
                    break
                }
            }
        }
        let result = findNearestBeadColor(lab.L, lab.a, lab.b, paletteLab: paletteLab, petFriendlyPenalty: petFriendlyPenalty)
        indices[i] = UInt16(result.index)
    }

    // 第二遍：降低彩色像素的饱和度（如果它嵌入在中性走廊中）
    let rawIndices = indices
    for i in 0..<(w * h) {
        if empty != nil && empty![i] != 0 { continue }
        let currentIdx = Int(rawIndices[i])
        if currentIdx >= paletteLab.count { continue }
        let current = paletteLab[currentIdx]
        if labChroma(current) < 35 { continue }
        if labChroma(sourceLab[i]) >= 34 { continue }
        let x = i % w, y = i / w
        for dir in mapperDirections {
            let x1 = x + dir.0, y1 = y + dir.1
            let x2 = x + dir.0 * 2, y2 = y + dir.1 * 2
            if x2 < 0 || x2 >= w || y2 < 0 || y2 >= h || x1 < 0 || x1 >= w || y1 < 0 || y1 >= h { continue }
            let n1Idx = Int(rawIndices[y1 * w + x1])
            let n2Idx = Int(rawIndices[y2 * w + x2])
            if n1Idx >= paletteLab.count || n2Idx >= paletteLab.count { continue }
            let n1 = paletteLab[n1Idx], n2 = paletteLab[n2Idx]
            let currentChroma = labChroma(current)
            if ((labChroma(n1) < 45 && labChroma(n2) < 45) ||
                (labChroma(n1) < currentChroma - 8 && labChroma(n2) < currentChroma - 8)) &&
               abs(current.L - n1.L) < 50 && abs(current.L - n2.L) < 50 {
                indices[i] = UInt16(n1Idx)
                break
            }
        }
    }
    return indices
}

/// 将参考图中的中性像素从中性色调色板条目中重选最近色。
/// 对应源端 `remapReferenceNeutralPixels`。原地修改 indices。
public func remapReferenceNeutralPixels(
    _ indices: inout [UInt16], referencePixels: [UInt8], paletteLab: [LabColor],
    empty: [UInt8]? = nil
) {
    for i in 0..<indices.count {
        if empty != nil && empty![i] != 0 { continue }
        let pi = i * 4
        let source = rgbToLab(Double(referencePixels[pi]), Double(referencePixels[pi + 1]), Double(referencePixels[pi + 2]))
        if labChroma(source) >= 24 || labChroma(paletteLab[Int(indices[i])]) <= 35 { continue }
        var bestIdx = -1
        var bestDist = Double.infinity
        for j in 0..<paletteLab.count {
            if labChroma(paletteLab[j]) > 24 { continue }
            let dist = weightedDeltaE(source, paletteLab[j])
            if dist < bestDist { bestDist = dist; bestIdx = j }
        }
        if bestIdx >= 0 { indices[i] = UInt16(bestIdx) }
    }
}

/// 在色板后处理后强制中性 RGB 选择。对应源端 `enforceReferenceNeutralRgb`。原地修改 indices。
public func enforceReferenceNeutralRgb(
    _ indices: inout [UInt16], w: Int, h: Int, referencePixels: [UInt8],
    palette: [BeadColor], empty: [UInt8]? = nil
) {
    for i in 0..<indices.count {
        if empty != nil && empty![i] != 0 { continue }
        let pi = i * 4
        let r = Int(referencePixels[pi]), g = Int(referencePixels[pi + 1]), b = Int(referencePixels[pi + 2])
        let sourceSpread = max(r, g, b) - min(r, g, b)
        var neutralCorridor = sourceSpread <= 42
        if !neutralCorridor && sourceSpread <= 72 {
            let x = i % w, y = i / w
            for dir in mapperDirections {
                let x1 = x + dir.0, y1 = y + dir.1
                let x2 = x + dir.0 * 2, y2 = y + dir.1 * 2
                if x1 < 0 || x1 >= w || y1 < 0 || y1 >= h || x2 < 0 || x2 >= w || y2 < 0 || y2 >= h { continue }
                let p1 = (y1 * w + x1) * 4, p2 = (y2 * w + x2) * 4
                let spread1 = max(Int(referencePixels[p1]), max(Int(referencePixels[p1 + 1]), Int(referencePixels[p1 + 2]))) -
                              min(Int(referencePixels[p1]), min(Int(referencePixels[p1 + 1]), Int(referencePixels[p1 + 2])))
                let spread2 = max(Int(referencePixels[p2]), max(Int(referencePixels[p2 + 1]), Int(referencePixels[p2 + 2]))) -
                              min(Int(referencePixels[p2]), min(Int(referencePixels[p2 + 1]), Int(referencePixels[p2 + 2])))
                if spread1 <= 42 && spread2 <= 42 { neutralCorridor = true; break }
            }
        }
        if !neutralCorridor { continue }
        let current = palette[Int(indices[i])].rgb
        if max(current.r, max(current.g, current.b)) - min(current.r, min(current.g, current.b)) < 60 { continue }
        let target = (r + g + b) / 3
        var bestIdx = -1
        var bestDist = Int.max
        for j in 0..<palette.count {
            let candidate = palette[j].rgb
            if max(candidate.r, max(candidate.g, candidate.b)) - min(candidate.r, min(candidate.g, candidate.b)) >= 60 { continue }
            let dist = abs((candidate.r + candidate.g + candidate.b) / 3 - target)
            if dist < bestDist { bestDist = dist; bestIdx = j }
        }
        if bestIdx >= 0 { indices[i] = UInt16(bestIdx) }
    }
}

/// 清理最终的彩色边缘：用最近中性色替换。对应源端 `cleanFinalNeutralFringes`。原地修改 indices。
public func cleanFinalNeutralFringes(
    _ indices: inout [UInt16], w: Int, h: Int, paletteLab: [LabColor],
    sourcePixels: [UInt8], empty: [UInt8]? = nil
) {
    let raw = indices
    for i in 0..<(w * h) {
        if empty != nil && empty![i] != 0 { continue }
        let rawIdx = Int(raw[i])
        if rawIdx >= paletteLab.count { continue }
        let current = paletteLab[rawIdx]
        if labChroma(current) < 35 { continue }
        let pi = i * 4
        let source = rgbToLab(Double(sourcePixels[pi]), Double(sourcePixels[pi + 1]), Double(sourcePixels[pi + 2]))
        let sourceChroma = labChroma(source)
        let x = i % w, y = i / w
        var neutralCorridor = sourceChroma < 24
        if !neutralCorridor && sourceChroma < 34 {
            for dir in mapperDirections {
                let x1 = x + dir.0, y1 = y + dir.1
                let x2 = x + dir.0 * 2, y2 = y + dir.1 * 2
                if x1 < 0 || x1 >= w || y1 < 0 || y1 >= h || x2 < 0 || x2 >= w || y2 < 0 || y2 >= h { continue }
                let p1 = (y1 * w + x1) * 4, p2 = (y2 * w + x2) * 4
                let n1 = rgbToLab(Double(sourcePixels[p1]), Double(sourcePixels[p1 + 1]), Double(sourcePixels[p1 + 2]))
                let n2 = rgbToLab(Double(sourcePixels[p2]), Double(sourcePixels[p2 + 1]), Double(sourcePixels[p2 + 2]))
                if labChroma(n1) < 24 && labChroma(n2) < 24 &&
                   abs(source.L - n1.L) < 50 && abs(source.L - n2.L) < 50 {
                    neutralCorridor = true
                    break
                }
            }
        }
        if neutralCorridor && labChroma(current) > 35 {
            var bestIdx = -1
            var bestDist = Double.infinity
            let allowedChroma = sourceChroma < 24 ? max(20, sourceChroma + 7) : 24
            for j in 0..<paletteLab.count {
                if labChroma(paletteLab[j]) > Double(allowedChroma) { continue }
                let dist = weightedDeltaE(source, paletteLab[j])
                if dist < bestDist { bestDist = dist; bestIdx = j }
            }
            if bestIdx >= 0 {
                indices[i] = UInt16(bestIdx)
                continue
            }
        }
        if sourceChroma >= 34 { continue }
        for dir in mapperDirections {
            let x1 = x + dir.0, y1 = y + dir.1
            let x2 = x + dir.0 * 2, y2 = y + dir.1 * 2
            if x1 < 0 || x1 >= w || y1 < 0 || y1 >= h || x2 < 0 || x2 >= w || y2 < 0 || y2 >= h { continue }
            let n1Idx = Int(raw[y1 * w + x1])
            let n2Idx = Int(raw[y2 * w + x2])
            if n1Idx >= paletteLab.count || n2Idx >= paletteLab.count { continue }
            let n1 = paletteLab[n1Idx], n2 = paletteLab[n2Idx]
            if labChroma(n1) < 45 && labChroma(n2) < 45 &&
               abs(current.L - n1.L) < 50 && abs(current.L - n2.L) < 50 {
                indices[i] = UInt16(n1Idx)
                break
            }
        }
    }
}
