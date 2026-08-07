import Foundation

// BeadPatternStats — 用量统计 / 短符号 / 难度评分。
// 逐行翻译自源端 shared/.../bead/BeadPatternStats.ets，纯逻辑。

/// 统计已用颜色数量（排除空格），并计算建议购买量。对应源端 `computePatternColorCounts`。
public func computePatternColorCounts(
    indices: [UInt16], paletteUsed: [BeadColor], empty: [UInt8]? = nil
) -> [BeadColorCount] {
    var counts: [Int: Int] = [:]
    for i in 0..<indices.count {
        if let empty, empty[i] != 0 { continue }
        let idx = Int(indices[i])
        counts[idx, default: 0] += 1
    }
    var colorCounts: [BeadColorCount] = []
    for (idx, count) in counts {
        let color = paletteUsed[idx]
        colorCounts.append(BeadColorCount(
            colorId: color.id,
            name: color.name,
            symbol: color.symbol,
            rgb: color.rgb,
            count: count,
            suggestedBuyCount: ceilInt(Double(count) * 1.08 / 10) * 10
        ))
    }
    // 源端按 count 降序；Swift 的 map.forEach 顺序不稳定，需显式排序以匹配源端结果顺序。
    colorCounts.sort { $0.count > $1.count }
    return colorCounts
}

/// 按用量降序分配 A-Z，同时保留 palette index 顺序。对应源端 `generatePatternShortSymbols`。
public func generatePatternShortSymbols(
    paletteUsed: [BeadColor], colorCounts: [BeadColorCount]
) -> [String] {
    let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    let lettersArray = Array(letters)
    var colorIdToLetter: [String: String] = [:]
    for i in 0..<min(colorCounts.count, lettersArray.count) {
        colorIdToLetter[colorCounts[i].colorId] = String(lettersArray[i])
    }
    var shortSymbols: [String] = []
    for i in 0..<paletteUsed.count {
        shortSymbols.append(colorIdToLetter[paletteUsed[i].id] ?? "?")
    }
    return shortSymbols
}

/// 根据最终图纸估算制作难度和耗时。对应源端 `computePatternDifficulty`。
public func computePatternDifficulty(
    colorCounts: [BeadColorCount], totalPixels: Int, w: Int, h: Int
) -> BeadScore {
    let colorCount = colorCounts.count
    var difficulty = Double(colorCount) / 48 * 40 + Double(totalPixels) / (80 * 80) * 30
    if w > 58 || h > 58 { difficulty += 20 }
    if colorCount > 24 { difficulty += 10 }
    var level = "normal"
    if difficulty < 25 { level = "easy" }
    else if difficulty < 50 { level = "normal" }
    else if difficulty < 75 { level = "hard" }
    else { level = "expert" }
    let minutes = ceilInt(Double(totalPixels) / 30)
    return BeadScore(
        colorError: 0,
        detailScore: 0,
        estimatedDifficulty: difficulty,
        level: level,
        totalBeads: totalPixels,
        colorCount: colorCount,
        estimatedMinutes: "\(max(1, Int(Double(minutes) * 0.7)))~\(minutes)"
    )
}
