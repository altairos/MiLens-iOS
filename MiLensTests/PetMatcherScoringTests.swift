import XCTest
@testable import MiLens

/// PetMatcherScoring 纯逻辑测试（对应源端 PetMatcherScoring 相关用例）。
/// 覆盖 embedding 有效性、评分决策、代表性样本选择、颜色距离与诊断截断。
final class PetMatcherScoringTests: XCTestCase {

    // MARK: - isValidEmbedding

    func testIsValidEmbeddingAcceptsNormalVector() {
        let valid = [Float](repeating: 0.1, count: 512)
        XCTAssertTrue(PetMatcherScoring.isValidEmbedding(valid))
    }

    func testIsValidEmbeddingRejectsZeroVector() {
        XCTAssertFalse(PetMatcherScoring.isValidEmbedding([Float](repeating: 0, count: 512)))
        // 极小值也视为无效（范式平方 < 1e-10）
        XCTAssertFalse(PetMatcherScoring.isValidEmbedding([Float](repeating: 1e-7, count: 512)))
    }

    func testIsValidEmbeddingRejectsNaNAndInfinity() {
        var nan = [Float](repeating: 0.1, count: 512)
        nan[0] = .nan
        XCTAssertFalse(PetMatcherScoring.isValidEmbedding(nan))

        var inf = [Float](repeating: 0.1, count: 512)
        inf[5] = .infinity
        XCTAssertFalse(PetMatcherScoring.isValidEmbedding(inf))
    }

    // MARK: - scoreFeatureRecord

    func testScoreFeatureRecordUsesAggregateWhenNoSamples() {
        let embedding = normalized([Float](repeating: 0.5, count: 8))
        let feature = PetFeatureRecord(
            version: 1, kind: .clip, aggregate: embedding,
            colorSignature: nil, samples: [], legacy: false)

        let evidence = PetMatcherScoring.scoreFeatureRecord(embedding: embedding, feature: feature)
        XCTAssertEqual(evidence?.source, "aggregate")
        XCTAssertEqual(evidence?.score ?? 0, 1.0, accuracy: 0.0001)
    }

    func testScoreFeatureRecordPrefersBlendWhenPrototypeWins() {
        let aggregate = normalized([Float](repeating: 0.5, count: 8))
        // sample 与 embedding 完全一致（cosine=1），blend = 0.85*1 + 0.15*aggregateScore
        let sample = aggregate
        let feature = PetFeatureRecord(
            version: 1, kind: .clip, aggregate: aggregate,
            colorSignature: nil, samples: [sample], legacy: false)

        let evidence = PetMatcherScoring.scoreFeatureRecord(embedding: aggregate, feature: feature)
        // blend = 1.0，aggregate = 1.0；blend > aggregate 不成立 → 仍用 aggregate
        XCTAssertEqual(evidence?.source, "aggregate")
        XCTAssertEqual(evidence?.score ?? 0, 1.0, accuracy: 0.0001)
    }

    func testScoreFeatureRecordBlendExceedsAggregate() {
        // aggregate 与 embedding 略偏离（cosine 0.9），samples 与 embedding 完全一致（1.0）
        // blend = 0.85*1 + 0.15*0.9 = 0.985 > 0.9 → 采用 blend（prototypeMean）
        let embedding = normalized([Float](repeating: 0.5, count: 8))
        var shifted = [Float](repeating: 0.5, count: 8)
        shifted[0] = -0.5
        let aggregate = normalized(shifted) // 与 embedding 的 cosine < 1
        let sample = embedding
        let feature = PetFeatureRecord(
            version: 1, kind: .clip, aggregate: aggregate,
            colorSignature: nil, samples: [sample], legacy: false)

        let evidence = PetMatcherScoring.scoreFeatureRecord(embedding: embedding, feature: feature)
        XCTAssertEqual(evidence?.source, "prototypeMean[1]")
        let aggregateScore = AiInferenceLogic.cosineSimilarity(embedding, aggregate)
        let expected = 1.0 * PetMatcherScoring.prototypeWeight + aggregateScore * PetMatcherScoring.aggregateWeight
        XCTAssertEqual(evidence?.score ?? 0, expected, accuracy: 0.0001)
    }

    func testScoreFeatureRecordTakesTopKOfSamples() {
        let embedding = normalized([Float](repeating: 0.5, count: 8))
        let feature = PetFeatureRecord(
            version: 1, kind: .clip, aggregate: embedding,
            colorSignature: nil,
            samples: [embedding, embedding, embedding, embedding], // 4 个一致样本，取 top3
            legacy: false)

        let evidence = PetMatcherScoring.scoreFeatureRecord(embedding: embedding, feature: feature)
        XCTAssertEqual(evidence?.source, "prototypeMean[3]")
        XCTAssertEqual(evidence?.score ?? 0, 1.0, accuracy: 0.0001)
    }

    func testScoreFeatureRecordRejectsNonFiniteAggregate() {
        let embedding = normalized([Float](repeating: 0.5, count: 8))
        var nan = embedding
        nan[0] = .nan
        let feature = PetFeatureRecord(
            version: 1, kind: .clip, aggregate: nan,
            colorSignature: nil, samples: [], legacy: false)

        XCTAssertNil(PetMatcherScoring.scoreFeatureRecord(embedding: embedding, feature: feature))
    }

    // MARK: - selectRepresentativeSamples

    func testSelectRepresentativeSamplesKeepsAllWhenBelowMax() {
        let embeddings = (0..<5).map { _ in normalized([Float](repeating: 0.1, count: 8)) }
        let selected = PetMatcherScoring.selectRepresentativeSamples(
            embeddings, maxCount: 24, centroid: embeddings[0])
        XCTAssertEqual(selected.count, 5)
    }

    func testSelectRepresentativeSamplesFarthestPointSampling() {
        // 8 个样本选 3 个：首帧为离 centroid 最近的，其余为最远点采样
        var embeddings = [[Float]]()
        for i in 0..<8 {
            var v = [Float](repeating: 0, count: 8)
            v[i % 8] = 1 // 每个样本沿不同轴（互相正交）
            embeddings.append(normalized(v))
        }
        let centroid = normalized([Float](repeating: 0.5, count: 8))

        let selected = PetMatcherScoring.selectRepresentativeSamples(
            embeddings, maxCount: 3, centroid: centroid)
        XCTAssertEqual(selected.count, 3)
        // 首帧 = 离 centroid 最近的（cosine 最大）
        let firstScore = AiInferenceLogic.cosineSimilarity(selected[0], centroid)
        let allScores = embeddings.map { AiInferenceLogic.cosineSimilarity($0, centroid) }
        XCTAssertEqual(firstScore, allScores.max() ?? -1, accuracy: 0.0001)
        // 无重复样本
        XCTAssertEqual(Set(selected.map { $0 }).count, 3)
    }

    func testSelectRepresentativeSamplesEmptyInput() {
        let selected = PetMatcherScoring.selectRepresentativeSamples(
            [], maxCount: 3, centroid: [])
        XCTAssertTrue(selected.isEmpty)
    }

    // MARK: - averageColorSignatures

    func testAverageColorSignaturesAveragesValidMembers() {
        let a = [Float](repeating: 0.2, count: 14)
        let b = [Float](repeating: 0.4, count: 14)
        let avg = PetMatcherScoring.averageColorSignatures([a, b], dim: 14)
        XCTAssertEqual(avg?.count, 14)
        XCTAssertEqual(avg?[0] ?? 0, 0.3, accuracy: 0.0001)
    }

    func testAverageColorSignaturesIgnoresWrongDim() {
        let a = [Float](repeating: 0.2, count: 14)
        let wrong = [Float](repeating: 0.5, count: 4)
        let avg = PetMatcherScoring.averageColorSignatures([a, wrong], dim: 14)
        XCTAssertEqual(avg?[0] ?? 0, 0.2, accuracy: 0.0001)
    }

    func testAverageColorSignaturesAllInvalidReturnsNil() {
        XCTAssertNil(PetMatcherScoring.averageColorSignatures([], dim: 14))
        XCTAssertNil(PetMatcherScoring.averageColorSignatures([[0.5, 0.5]], dim: 14))
    }

    // MARK: - colorDistance

    func testColorDistanceIdenticalSignaturesIsZero() {
        let a = [Float](repeating: 0.3, count: 14)
        XCTAssertEqual(PetMatcherScoring.colorDistance(a, a), 0, accuracy: 0.0001)
    }

    func testColorDistanceDifferentSignatures() {
        let a = [Float](repeating: 0, count: 14)
        let b = [Float](repeating: 0.5, count: 14)
        // RMS = sqrt(sum(0.25)/14) = sqrt(0.25) = 0.5
        XCTAssertEqual(PetMatcherScoring.colorDistance(a, b), 0.5, accuracy: 0.0001)
    }

    func testColorDistanceEmptyReturnsMax() {
        XCTAssertEqual(PetMatcherScoring.colorDistance([], []), 1)
    }

    func testColorDistanceAlignsShorterLength() {
        let a = [Float](repeating: 0, count: 14)
        let b = [Float](repeating: 1, count: 4)
        // 按较短长度（4）对齐：RMS = sqrt(sum(1)/4) = 0.5
        XCTAssertEqual(PetMatcherScoring.colorDistance(a, b), 0.5, accuracy: 0.0001)
    }

    // MARK: - compactDiagnostics

    func testCompactDiagnosticsTruncatesLongText() {
        let long = String(repeating: "a", count: 1000)
        let compact = PetMatcherScoring.compactDiagnostics(long)
        XCTAssertEqual(compact.count, PetMatcherScoring.diagnosticsMaxLength + 3) // + "..."
        XCTAssertTrue(compact.hasSuffix("..."))
    }

    func testCompactDiagnosticsKeepsShortText() {
        XCTAssertEqual(PetMatcherScoring.compactDiagnostics("ok"), "ok")
    }

    // MARK: - 辅助

    private func normalized(_ values: [Float]) -> [Float] {
        AiInferenceLogic.normalized(values)
    }
}
