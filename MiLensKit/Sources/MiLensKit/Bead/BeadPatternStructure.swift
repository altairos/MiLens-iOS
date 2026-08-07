import Foundation

// BeadPatternStructure — 结构诊断 / 眼睛高光 / 主色索引 / finalizeNativePattern。
// 逐行翻译自源端 shared/.../bead/BeadPatternStructure.ets。

// MARK: - 轻量图纸引用（refreshStructuralDiagnostics 操作的可变引用）

/// refreshStructuralDiagnostics 操作的可变图纸引用。
/// 完整 BeadPattern 类型待生成管线主入口迁移时定义。
public struct BeadPatternRef {
    public var width: Int
    public var height: Int
    public var indices: [UInt16]
    public var empty: [UInt8]
    public var paletteUsed: [BeadColor]
    public var score: BeadScore
    public var diagnostics: PatternDiagnostics?
    public var protectMask: [UInt8]?
    public var colorCounts: [BeadColorCount]?
    public var shortSymbols: [String]?

    public init(width: Int, height: Int, indices: [UInt16], empty: [UInt8],
                paletteUsed: [BeadColor], score: BeadScore = BeadScore(colorError: 0, detailScore: 0, estimatedDifficulty: 0, level: "", totalBeads: 0, colorCount: 0, estimatedMinutes: ""),
                diagnostics: PatternDiagnostics? = nil,
                protectMask: [UInt8]? = nil,
                colorCounts: [BeadColorCount]? = nil,
                shortSymbols: [String]? = nil) {
        self.width = width
        self.height = height
        self.indices = indices
        self.empty = empty
        self.paletteUsed = paletteUsed
        self.score = score
        self.diagnostics = diagnostics
        self.protectMask = protectMask
        self.colorCounts = colorCounts
        self.shortSymbols = shortSymbols
    }
}

// MARK: - 结构诊断刷新

/// 刷新结构诊断：孤立像素比、少用色数、轮廓/黑占比。
/// 保留之前的 averageDeltaE/maxDeltaE/neutralHueShiftRatio/whiteToCoolRatio。
/// 对应源端 `refreshStructuralDiagnostics`。原地修改 pattern.diagnostics。
public func refreshStructuralDiagnostics(_ pattern: inout BeadPatternRef) {
    let previous = pattern.diagnostics
    var counts: [Int: Int] = [:]
    let paletteLab = precomputePaletteLab(pattern.paletteUsed)
    var total = 0
    var isolated = 0
    var outline = 0
    var black = 0
    for y in 0..<pattern.height {
        for x in 0..<pattern.width {
            let i = y * pattern.width + x
            if pattern.empty[i] != 0 { continue }
            total += 1
            let idx = Int(pattern.indices[i])
            counts[idx, default: 0] += 1

            var sameNeighbor = false
            if x > 0 && pattern.empty[i - 1] == 0 && Int(pattern.indices[i - 1]) == idx { sameNeighbor = true }
            if x < pattern.width - 1 && pattern.empty[i + 1] == 0 && Int(pattern.indices[i + 1]) == idx { sameNeighbor = true }
            if y > 0 && pattern.empty[i - pattern.width] == 0 && Int(pattern.indices[i - pattern.width]) == idx { sameNeighbor = true }
            if y < pattern.height - 1 && pattern.empty[i + pattern.width] == 0 && Int(pattern.indices[i + pattern.width]) == idx { sameNeighbor = true }
            if !sameNeighbor { isolated += 1 }

            let color = idx < pattern.paletteUsed.count ? pattern.paletteUsed[idx] : nil
            if let color, color.id.contains("_dark") || color.id.contains("_outline_") { outline += 1 }
            if idx < paletteLab.count && paletteLab[idx].L < 20 { black += 1 }
        }
    }

    let tinyThreshold = minColorUsageThreshold(total)
    var tiny = 0
    for (_, count) in counts { if count < tinyThreshold { tiny += 1 } }

    func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

    pattern.diagnostics = PatternDiagnostics(
        averageDeltaE: previous?.averageDeltaE ?? 0,
        maxDeltaE: previous?.maxDeltaE ?? 0,
        usedColorCount: counts.count,
        tinyColorCount: tiny,
        isolatedPixelRatio: total > 0 ? round3(Double(isolated) / Double(total)) : 0,
        neutralHueShiftRatio: previous?.neutralHueShiftRatio,
        whiteToCoolRatio: previous?.whiteToCoolRatio,
        outlineCoverageRatio: total > 0 ? round3(Double(outline) / Double(total)) : 0,
        blackCoverageRatio: total > 0 ? round3(Double(black) / Double(total)) : 0
    )
}

// MARK: - 眼睛高光补偿

/// 在 Face ROI 内检测眼睛高光格，确保它们使用最亮的色卡色。
/// 对应源端 `applyEyeHighlight`。原地修改 indices。
public func applyEyeHighlight(
    _ indices: inout [UInt16], w: Int, h: Int,
    palette: [BeadColor], originalPixels: [UInt8],
    empty: [UInt8], faceRoi: CropArea? = nil
) {
    guard let faceRoi else { return }
    let paletteLab = precomputePaletteLab(palette)
    var brightestIdx = 0
    var brightestL = 0.0
    for i in 0..<paletteLab.count {
        if paletteLab[i].L > brightestL {
            brightestL = paletteLab[i].L
            brightestIdx = i
        }
    }

    for y in faceRoi.y..<(faceRoi.y + faceRoi.h) {
        for x in faceRoi.x..<(faceRoi.x + faceRoi.w) {
            let i = y * w + x
            if empty[i] != 0 { continue }
            // 当前格必须是暗色（可能是眼珠）
            let currentLab = paletteLab[Int(indices[i])]
            if currentLab.L > 35 { continue }

            // 检查邻居中是否有亮色格（可能是高光）
            for dy in -1...1 {
                for dx in -1...1 {
                    if dx == 0 && dy == 0 { continue }
                    let nx = x + dx
                    let ny = y + dy
                    if nx < 0 || nx >= w || ny < 0 || ny >= h { continue }
                    let ni = ny * w + nx
                    if empty[ni] != 0 { continue }

                    // 原图像素亮度
                    let pi = ni * 4
                    let origLum = (Double(originalPixels[pi]) * 0.2126 +
                                   Double(originalPixels[pi + 1]) * 0.7152 +
                                   Double(originalPixels[pi + 2]) * 0.0722) / 255

                    // 如果原图中这个点是亮的（高光），但当前被映射成了暗色
                    if origLum > 0.75 && paletteLab[Int(indices[ni])].L < 60 {
                        // 检查是否被至少 2 个暗色邻居包围
                        var darkNeighborCount = 0
                        for ddy in -1...1 {
                            for ddx in -1...1 {
                                if ddx == 0 && ddy == 0 { continue }
                                let nnx = nx + ddx
                                let nny = ny + ddy
                                if nnx < 0 || nnx >= w || nny < 0 || nny >= h { continue }
                                let nni = nny * w + nnx
                                if paletteLab[Int(indices[nni])].L < 40 { darkNeighborCount += 1 }
                            }
                        }
                        if darkNeighborCount >= 2 {
                            indices[ni] = UInt16(brightestIdx)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 主色索引

/// 计算前 N 大主色的索引数组（按像素数降序）。对应源端 `computeTopDominantIndices`。
public func computeTopDominantIndices(
    indices: [UInt16], empty: [UInt8]?, topN: Int
) -> [Int] {
    var counts: [Int: Int] = [:]
    for i in 0..<indices.count {
        if let empty, empty[i] != 0 { continue }
        counts[Int(indices[i]), default: 0] += 1
    }
    let sorted = counts.sorted { $0.value > $1.value }
    return sorted.prefix(topN).map(\.key)
}

// MARK: - 最终化图纸

/// 最终化图纸：可选轮廓绘制 + 诊断刷新。对应源端 `finalizeNativePattern`。
/// 原地修改 pattern。
public func finalizeNativePattern(
    _ pattern: inout BeadPatternRef,
    options: BeadGenerateOptions,
    referencePixels: [UInt8]? = nil
) {
    if !options.outlineDrawMode.isEmpty && options.outlineDrawMode != "none" {
        pattern.paletteUsed = drawOutline(
            &pattern.indices, w: pattern.width, h: pattern.height,
            palette: pattern.paletteUsed, mode: options.outlineDrawMode,
            protectMask: pattern.protectMask, empty: pattern.empty)
        pattern.colorCounts = computePatternColorCounts(
            indices: pattern.indices, paletteUsed: pattern.paletteUsed, empty: pattern.empty)
        pattern.score = computePatternDifficulty(
            colorCounts: pattern.colorCounts ?? [],
            totalPixels: pattern.score.totalBeads,
            w: pattern.width, h: pattern.height)
        pattern.shortSymbols = generatePatternShortSymbols(
            paletteUsed: pattern.paletteUsed, colorCounts: pattern.colorCounts ?? [])
    }
    if let referencePixels, referencePixels.count == pattern.width * pattern.height * 4 {
        pattern.diagnostics = computeDiagnostics(
            indices: pattern.indices, w: pattern.width, h: pattern.height,
            paletteUsed: pattern.paletteUsed, originalPixels: referencePixels,
            empty: pattern.empty)
    } else {
        refreshStructuralDiagnostics(&pattern)
    }
}
