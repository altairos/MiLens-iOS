//  PetMatcherScoring —— 宠物特征匹配纯逻辑评分模块（对应源端 services/PetMatcherScoring.ets）。
//
//  从 PetMatcher 抽出的纯逻辑（DESIGN.md §4：零 IO / 零 SwiftUI 依赖，可单测）：
//  - isValidEmbedding：embedding 有效性（范式 > 阈值，无 NaN/Infinity）
//  - scoreFeatureRecord：聚合 + prototype 混合评分决策
//  - selectRepresentativeSamples：基于最远点采样的代表性样本选择
//  - averageColorSignatures：颜色签名均值聚合
//  - colorDistance：颜色签名欧氏距离（RMS）
//  - compactDiagnostics：诊断字符串安全截断
//
//  匹配阈值常量集中于此（对应源端 MatchThresholdConstants）。

import Foundation

/// 匹配阈值（对应源端 constants/AppConstants.ets MatchThresholdConstants）。
enum PetMatchThreshold {
    /// 严格模式（自动归属默认阈值）。
    static let strict: Float = 0.82
    /// 正常模式（uncertain 区间下界）。
    static let normal: Float = 0.78
    /// 宽松模式。
    static let loose: Float = 0.70
    /// top1 与 top2 分数的最小差距（自动归属）。
    static let minMargin: Float = 0.025
    /// bestScore >= threshold + 此值时视为高置信匹配。
    static let highConfidenceDelta: Float = 0.04
    /// 高置信匹配可用的缩小 margin。
    static let highConfidenceMinMargin: Float = 0.008
    /// feature blob 中追加的颜色签名维度。
    static let colorSignatureDim = 14
    /// 自动归属允许的最大颜色距离。
    static let maxColorDistance: Float = 0.34
    /// 聚合向量之后最多存储的注册样本向量数。
    static let maxStoredSampleVectors = 24
    /// 照片多样性检查的最小平均 embedding 分散度。
    static let minDiversityScore: Float = 0.10
}

/// 单只宠物的评分结果（含分数来源标识，便于诊断；对应源端 MatchEvidence）。
struct MatchEvidence: Equatable, Sendable {
    let score: Float
    let source: String
}

enum PetMatcherScoring {

    /// 截断后诊断字符串的最大长度（与原 PetMatcher.compact 保持一致）。
    static let diagnosticsMaxLength = 360
    /// scoreFeatureRecord 中 prototype 平均时考虑的最大样本数。
    static let prototypeTopK = 3
    /// prototype 与 aggregate 的混合权重。
    static let prototypeWeight: Float = 0.85
    static let aggregateWeight: Float = 0.15
    /// embedding 有效性的最小范式平方阈值（避免全零向量误判）。
    static let validEmbeddingNormSqEps: Float = 1e-10

    /// 判断 embedding 是否为有效的非零向量。
    ///
    /// 规则：
    /// - 任何元素为 NaN/Infinity → false
    /// - 所有元素平方和小于 1e-10 → false（视为全零）
    /// - 否则 true
    static func isValidEmbedding(_ embedding: [Float]) -> Bool {
        var normSq: Float = 0
        for value in embedding {
            if !value.isFinite { return false }
            normSq += value * value
        }
        return normSq > validEmbeddingNormSqEps
    }

    /// 对单个宠物的特征记录评分：取 aggregate cosine，并尝试用 prototype top-K 均值增强。
    ///
    /// 决策：
    /// - 若 aggregate cosine 非 finite → nil（不可比较）
    /// - 若无可用 sample → 直接返回 aggregate 分数
    /// - 否则计算 top-K sample 均值，按 0.85/0.15 与 aggregate 混合；
    ///   混合分数严格高于 aggregate 时采用混合分（prototype 在样本充足且一致时更鲁棒）。
    static func scoreFeatureRecord(embedding: [Float], feature: PetFeatureRecord) -> MatchEvidence? {
        let aggregateScore = AiInferenceLogic.cosineSimilarity(embedding, feature.aggregate)
        guard aggregateScore.isFinite else { return nil }
        var sampleScores: [Float] = []
        for sample in feature.samples {
            guard sample.count == embedding.count else { continue }
            let score = AiInferenceLogic.cosineSimilarity(embedding, sample)
            if score.isFinite { sampleScores.append(score) }
        }
        if sampleScores.isEmpty {
            return MatchEvidence(score: aggregateScore, source: "aggregate")
        }
        sampleScores.sort(by: >)
        let evidenceCount = min(prototypeTopK, sampleScores.count)
        var evidenceSum: Float = 0
        for i in 0..<evidenceCount { evidenceSum += sampleScores[i] }
        let prototypeMean = evidenceSum / Float(evidenceCount)
        let blended = prototypeMean * prototypeWeight + aggregateScore * aggregateWeight
        if blended > aggregateScore {
            return MatchEvidence(score: blended, source: "prototypeMean[\(evidenceCount)]")
        }
        return MatchEvidence(score: aggregateScore, source: "aggregate")
    }

    /// 从 embeddings 中选出最多 maxCount 个代表性样本。
    ///
    /// 算法（贪心最远点采样）：
    /// 1. 选离 centroid 最近的一个作为首帧；
    /// 2. 反复选取「与已选集合最大相似度」最小的样本（即离已选最远的），
    ///    直到选满 maxCount 或剩余为空。
    ///
    /// 用途：注册宠物时保存 K 张代表性视角供 prototype 评分使用。
    static func selectRepresentativeSamples(
        _ embeddings: [[Float]], maxCount: Int, centroid: [Float]
    ) -> [[Float]] {
        if embeddings.count <= maxCount { return embeddings }
        var selected: [[Float]] = []
        var selectedIndices = Set<Int>()
        var firstIndex = 0
        var firstScore: Float = -.infinity
        for (i, embedding) in embeddings.enumerated() {
            let score = AiInferenceLogic.cosineSimilarity(embedding, centroid)
            if score > firstScore {
                firstScore = score
                firstIndex = i
            }
        }
        selected.append(embeddings[firstIndex])
        selectedIndices.insert(firstIndex)
        while selected.count < maxCount {
            var bestIndex = -1
            var bestDistance: Float = -1
            for (i, embedding) in embeddings.enumerated() where !selectedIndices.contains(i) {
                var nearestSimilarity: Float = -1
                for chosen in selected {
                    nearestSimilarity = max(nearestSimilarity, AiInferenceLogic.cosineSimilarity(embedding, chosen))
                }
                let distance = 1 - nearestSimilarity
                if distance > bestDistance {
                    bestDistance = distance
                    bestIndex = i
                }
            }
            if bestIndex < 0 { break }
            selected.append(embeddings[bestIndex])
            selectedIndices.insert(bestIndex)
        }
        return selected
    }

    /// 计算颜色签名集合的均值。
    ///
    /// - 忽略长度不等于 dim 的成员；
    /// - 若全部成员无效 → nil；
    /// - 否则返回长度等于 dim 的均值向量。
    static func averageColorSignatures(_ signatures: [[Float]], dim: Int) -> [Float]? {
        var avg = [Float](repeating: 0, count: dim)
        var validCount = 0
        for sig in signatures {
            guard sig.count == dim else { continue }
            for i in 0..<dim { avg[i] += sig[i] }
            validCount += 1
        }
        guard validCount > 0 else { return nil }
        let count = Float(validCount)
        for i in 0..<dim { avg[i] /= count }
        return avg
    }

    /// 计算两个颜色签名之间的 RMS 欧氏距离。
    ///
    /// - 维度不一致时按较短长度对齐；空输入返回 1（最大距离）。
    /// - 返回 sqrt(sum((a-b)^2)/len)（RMS 而非原始平方和，便于跨维度可比）。
    static func colorDistance(_ a: [Float], _ b: [Float]) -> Float {
        let len = min(a.count, b.count)
        if len == 0 { return 1 }
        var sum: Float = 0
        for i in 0..<len {
            let d = a[i] - b[i]
            sum += d * d
        }
        return (sum / Float(len)).squareRoot()
    }

    /// 把诊断字符串截断到 maxLen；超过则在尾部加 "..."。
    static func compactDiagnostics(_ text: String, maxLen: Int = diagnosticsMaxLength) -> String {
        if text.count <= maxLen { return text }
        return String(text.prefix(maxLen)) + "..."
    }
}
