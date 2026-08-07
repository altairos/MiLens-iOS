import Foundation

// BeadScoring — 三目标评分系统。
// overall = identityScore × 0.45 + aestheticScore × 0.35 + beadabilityScore × 0.20
// 逐行翻译自源端 shared/.../bead/BeadScoring.ets（161 行）。

private func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }

// MARK: - identityScore

/// 识别感：颜色保真度 + 主体覆盖度。对应源端 `computeIdentityScore`（私有）。
private func computeIdentityScore(_ d: PatternDiagnostics, _ s: BeadScore, _ gridW: Int, _ gridH: Int) -> Double {
    // ΔE 0 → 100, ΔE 15 → 50, ΔE 30+ → 0
    let avgDeltaEScore = max(0, 100 - d.averageDeltaE * (100.0 / 30))

    // 最大色差惩罚：maxDeltaE > 40 时开始扣分
    let maxDeltaEPenalty = max(0, (d.maxDeltaE - 40) * 0.5)

    // 有效格占比：只能识别主体小到几乎不可用的异常
    let coverageRatio = gridW * gridH > 0 ? Double(s.totalBeads) / Double(gridW * gridH) : 1.0
    let sparseCoveragePenalty = coverageRatio < 0.2 ? (0.2 - coverageRatio) * 50 : 0

    // 中性色偏移和白→冷惩罚
    let neutralShiftPenalty = (d.neutralHueShiftRatio ?? 0) * 300
    let whiteCoolPenalty = (d.whiteToCoolRatio ?? 0) * 500

    let raw = avgDeltaEScore - maxDeltaEPenalty - sparseCoveragePenalty - neutralShiftPenalty - whiteCoolPenalty
    return clamp01(raw / 100) * 100
}

// MARK: - aestheticScore

/// 美观度：孤点 + 少用量色 + 色数平衡 - 轮廓/黑边惩罚。对应源端 `computeAestheticScore`（私有）。
private func computeAestheticScore(_ d: PatternDiagnostics, _ s: BeadScore) -> Double {
    // 孤点评分：ratio 0 → 满分, ratio 0.15+ → 0
    let isolatedScore = max(0, 100 - d.isolatedPixelRatio * 667)

    // 少用量色评分：0 个 → 满分, 5+ → 0
    let tinyScore = max(0, 100 - Double(d.tinyColorCount) * 20)

    // 色数适度评分：12–24 色最佳
    let colors = d.usedColorCount
    var colorBalanceScore: Double = 100
    if colors < 6 {
        colorBalanceScore = 40 + Double(colors) * 10
    } else if colors <= 24 {
        colorBalanceScore = 100
    } else if colors <= 40 {
        colorBalanceScore = 100 - Double(colors - 24) * 2
    } else {
        colorBalanceScore = max(30, 68 - Double(colors - 40))
    }

    // 轮廓和黑边覆盖率惩罚
    let outlineRatio = d.outlineCoverageRatio ?? 0
    let blackRatio = d.blackCoverageRatio ?? 0
    let outlinePenalty = outlineRatio > 0.18 ? (outlineRatio - 0.18) * 200 : 0
    let blackPenalty = blackRatio > 0.15 ? (blackRatio - 0.15) * 150 : 0

    let raw = isolatedScore * 0.35 + tinyScore * 0.20 + colorBalanceScore * 0.45 - outlinePenalty - blackPenalty
    return clamp01(raw / 100) * 100
}

// MARK: - beadabilityScore

/// 可拼性：颜色数 + 难度 + 孤点 + 少用量色。对应源端 `computeBeadabilityScore`（私有）。
private func computeBeadabilityScore(_ d: PatternDiagnostics, _ s: BeadScore) -> Double {
    // ≤ 12 → 100, 24 → 80, 48 → 40, 60+ → 20
    let colors = d.usedColorCount
    var colorFeasibility: Double = 100
    if colors <= 12 {
        colorFeasibility = 100
    } else if colors <= 24 {
        colorFeasibility = 100 - Double(colors - 12) * (20.0 / 12)
    } else if colors <= 48 {
        colorFeasibility = 80 - Double(colors - 24) * (40.0 / 24)
    } else {
        colorFeasibility = max(10, 40 - Double(colors - 48))
    }

    // 难度评分转换：difficulty 0–25 → 100, 75+ → 20
    let diff = s.estimatedDifficulty
    let diffScore = max(20, 100 - diff * (80.0 / 75))

    let isolatedPenalty = d.isolatedPixelRatio * 200
    let tinyPenalty = Double(d.tinyColorCount) * 8

    let raw = colorFeasibility * 0.35 + diffScore * 0.40 - isolatedPenalty - tinyPenalty + 25
    return clamp01(raw / 100) * 100
}

// MARK: - 公开接口

/// 计算三目标评分。对应源端 `computeTriScore`。
public func computeTriScore(_ pattern: BeadPatternRef) -> TriScore {
    guard let d = pattern.diagnostics else {
        return TriScore(identityScore: 50, aestheticScore: 50, beadabilityScore: 50, overall: 50)
    }
    let s = pattern.score
    let identity = computeIdentityScore(d, s, pattern.width, pattern.height)
    let aesthetic = computeAestheticScore(d, s)
    let beadability = computeBeadabilityScore(d, s)
    let overall = identity * 0.45 + aesthetic * 0.35 + beadability * 0.20
    func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
    return TriScore(
        identityScore: round1(identity),
        aestheticScore: round1(aesthetic),
        beadabilityScore: round1(beadability),
        overall: round1(overall)
    )
}

/// 自动模式候选排序的快捷函数。对应源端 `triScoreOverall`。
public func triScoreOverall(_ pattern: BeadPatternRef) -> Double {
    return computeTriScore(pattern).overall
}
