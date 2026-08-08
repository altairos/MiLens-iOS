//  AiInferenceLogicTests —— CLIP 推理纯决策逻辑测试（对应源端 AiInferenceLogic.test.ets）。
//  覆盖 cosineSimilarity / l2Normalize / classifyImageEmbedding / selectOutputEmbedding。

import XCTest
@testable import MiLens

final class AiInferenceLogicTests: XCTestCase {

    // MARK: - cosineSimilarity

    func testCosineSimilarity_identicalVectors_returnsOne() {
        let v: [Float] = [1, 2, 3, 4]
        XCTAssertEqual(AiInferenceLogic.cosineSimilarity(v, v), 1.0, accuracy: 1e-6)
    }

    func testCosineSimilarity_orthogonalVectors_returnsZero() {
        let a: [Float] = [1, 0]
        let b: [Float] = [0, 1]
        XCTAssertEqual(AiInferenceLogic.cosineSimilarity(a, b), 0.0, accuracy: 1e-6)
    }

    func testCosineSimilarity_zeroVector_returnsZero() {
        let a: [Float] = [0, 0, 0]
        let b: [Float] = [1, 2, 3]
        XCTAssertEqual(AiInferenceLogic.cosineSimilarity(a, b), 0.0, accuracy: 1e-6)
    }

    func testCosineSimilarity_emptyVectors_returnsZero() {
        XCTAssertEqual(AiInferenceLogic.cosineSimilarity([], []), 0.0, accuracy: 1e-6)
    }

    func testCosineSimilarity_knownValue() {
        // [1,0,0] vs [1,1,0] → 1 / (1 * sqrt(2)) ≈ 0.7071
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [1, 1, 0]
        XCTAssertEqual(AiInferenceLogic.cosineSimilarity(a, b), Float(1.0 / sqrt(2.0)), accuracy: 1e-5)
    }

    // MARK: - l2Normalize

    func testL2Normalize_unitLength() {
        var v: [Float] = [3, 4]  // L2 = 5
        AiInferenceLogic.l2Normalize(&v)
        XCTAssertEqual(AiInferenceLogic.cosineSimilarity(v, [3, 4]), 1.0, accuracy: 1e-6)
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(norm, 1.0, accuracy: 1e-6)
    }

    func testL2Normalize_zeroVector_unchanged() {
        var v: [Float] = [0, 0, 0]
        AiInferenceLogic.l2Normalize(&v)
        XCTAssertEqual(v, [0, 0, 0])
    }

    func testNormalized_returnsNewVector() {
        let original: [Float] = [3, 4]
        let normalized = AiInferenceLogic.normalized(original)
        XCTAssertEqual(original, [3, 4])  // 原向量不变
        let norm = sqrt(normalized.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(norm, 1.0, accuracy: 1e-6)
    }

    // MARK: - classifyImageEmbedding

    private func makeConfig(threshold: Float = 0.2, tolerance: Float = 0.03) -> ClassificationConfig {
        ClassificationConfig(embeddingDim: 4, petDetectThreshold: threshold, petNonPetTolerance: tolerance)
    }

    func testClassify_highPetSimilarity_isPetTrue() {
        // image 与 "cat" 文本 embedding 几乎相同
        let imageVec: [Float] = [0.9, 0.1, 0.0, 0.0]
        let pet: [String: [Float]] = ["cat": [0.9, 0.1, 0.0, 0.0]]
        let nonPet: [String: [Float]] = ["car": [0.0, 0.0, 0.9, 0.1]]
        let labels: [String: String] = ["cat": "猫"]

        let result = AiInferenceLogic.classifyImageEmbedding(
            imageVec: imageVec, petTextEmbeddings: pet,
            nonPetTextEmbeddings: nonPet, speciesLabels: labels, config: makeConfig())

        XCTAssertTrue(result.isPet)
        XCTAssertEqual(result.species, "cat")
        XCTAssertEqual(result.topLabel, "猫")
        XCTAssertGreaterThan(result.topConfidence, 0.2)
    }

    func testClassify_lowPetSimilarity_isPetFalse() {
        // image 与 pet 正交（cosine≈0），低于阈值 → isPet false
        let imageVec: [Float] = [1, 0, 0, 0]
        let pet: [String: [Float]] = ["cat": [0, 0.9, 0.9, 0.9]]  // 与 imageVec 正交
        let nonPet: [String: [Float]] = [:]

        let result = AiInferenceLogic.classifyImageEmbedding(
            imageVec: imageVec, petTextEmbeddings: pet,
            nonPetTextEmbeddings: nonPet, speciesLabels: [:], config: makeConfig())

        XCTAssertFalse(result.isPet)
        XCTAssertNil(result.species)
    }

    func testClassify_nonPetHigherThanPet_isPetFalse() {
        // nonPet 与 image 同向（cosine=1.0），pet 与 image 正交（cosine≈0）
        // gap = 0 - 1.0 = -1.0 < -tolerance(0.03) → isPet false
        let imageVec: [Float] = [0.9, 0.9, 0.0, 0.0]
        let pet: [String: [Float]] = ["dog": [0, 0, 0.9, 0.9]]      // 正交，cosine=0
        let nonPet: [String: [Float]] = ["car": [0.9, 0.9, 0, 0]]  // 同向，cosine=1.0

        let result = AiInferenceLogic.classifyImageEmbedding(
            imageVec: imageVec, petTextEmbeddings: pet,
            nonPetTextEmbeddings: nonPet, speciesLabels: [:], config: makeConfig())

        XCTAssertFalse(result.isPet)
    }

    func testClassify_allZeroEmbedding_skipped() {
        // 全零的文本 embedding 应被跳过
        let imageVec: [Float] = [1, 0, 0, 0]
        let pet: [String: [Float]] = ["cat": [0, 0, 0, 0]]
        let nonPet: [String: [Float]] = [:]

        let result = AiInferenceLogic.classifyImageEmbedding(
            imageVec: imageVec, petTextEmbeddings: pet,
            nonPetTextEmbeddings: nonPet, speciesLabels: [:], config: makeConfig())

        XCTAssertFalse(result.isPet)
        XCTAssertTrue(result.labels.isEmpty)
    }

    func testClassify_labelsSortedByConfidence() {
        let imageVec: [Float] = [0.8, 0.2, 0.0, 0.0]
        let pet: [String: [Float]] = [
            "dog": [0.8, 0.2, 0.0, 0.0],   // 高
            "cat": [0.2, 0.8, 0.0, 0.0],   // 低
        ]
        let nonPet: [String: [Float]] = [:]

        let result = AiInferenceLogic.classifyImageEmbedding(
            imageVec: imageVec, petTextEmbeddings: pet,
            nonPetTextEmbeddings: nonPet, speciesLabels: [:], config: makeConfig())

        XCTAssertEqual(result.labels.count, 2)
        XCTAssertGreaterThanOrEqual(result.labels[0].confidence, result.labels[1].confidence)
    }

    // MARK: - selectOutputEmbedding

    func testSelectOutput_imageFeaturesNamed_selected() throws {
        let embeddingDim = 4
        let vector: [Float] = [0.1, 0.2, 0.3, 0.4]
        let data = ClipInferenceService.floatArrayToData(vector)
        let infos = [TensorInfo(name: "image_features", shape: [1, embeddingDim], dataType: .float32)]

        let selection = try AiInferenceLogic.selectOutputEmbedding(
            outputs: [data], outputInfos: infos, embeddingDim: embeddingDim)

        XCTAssertEqual(selection.vector.count, embeddingDim)
        // XCTAssertEqual 的 accuracy 变体不支持数组，逐元素比较。
        for i in 0..<embeddingDim {
            XCTAssertEqual(selection.vector[i], vector[i], accuracy: 1e-6)
        }
        XCTAssertTrue(selection.description.contains("output["))
    }

    func testSelectOutput_wrongShape_skipped() {
        let vector: [Float] = [0.1, 0.2, 0.3]
        let data = ClipInferenceService.floatArrayToData(vector)
        let infos = [TensorInfo(name: "image_features", shape: [1, 3], dataType: .float32)]  // shape != 512... 不匹配 embeddingDim=4

        XCTAssertThrowsError(
            try AiInferenceLogic.selectOutputEmbedding(
                outputs: [data], outputInfos: infos, embeddingDim: 4)
        ) { error in
            XCTAssertEqual(error as? InferenceSelectionError, .some(.noValidEmbedding))
        }
    }

    func testSelectOutput_metadataMismatch_throws() {
        let infos = [TensorInfo(name: "image_features", shape: [1, 4], dataType: .float32)]

        XCTAssertThrowsError(
            try AiInferenceLogic.selectOutputEmbedding(
                outputs: [Data(), Data()], outputInfos: infos, embeddingDim: 4)
        ) { error in
            XCTAssertEqual(error as? InferenceSelectionError, .some(.metadataMismatch(outputs: 2, infos: 1)))
        }
    }

    func testSelectOutput_allZeroVector_rejected() {
        let vector: [Float] = [0, 0, 0, 0]
        let data = ClipInferenceService.floatArrayToData(vector)
        let infos = [TensorInfo(name: "image_features", shape: [1, 4], dataType: .float32)]

        XCTAssertThrowsError(
            try AiInferenceLogic.selectOutputEmbedding(
                outputs: [data], outputInfos: infos, embeddingDim: 4)
        ) { error in
            XCTAssertEqual(error as? InferenceSelectionError, .some(.noValidEmbedding))
        }
    }
}
