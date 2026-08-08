//  AiInferenceLogic —— CLIP 推理纯决策逻辑（对应源端 services/AiInferenceLogic.ets）。
//
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 CoreML / 无 SwiftUI 依赖。
//  覆盖 CLIP 推理管线中的决策/计算逻辑：
//  - cosineSimilarity / l2Normalize（对应源端 utils/MathUtils.ets）
//  - classifyImageEmbedding：宠物/非宠物分类决策（cosine + 阈值 + gap）
//  - selectOutputEmbedding：从多输出张量中选择最佳 CLIP embedding（评分逻辑）
//
//  ADR-0007 §2.1：业务层只依赖纯函数，CoreML/Vision 真实实现可注入 mock 测试。
//  行为一致性由 XCTest 守护（对应源端 Hypium 用例）。

import Foundation

/// 单个分类标签得分（对应源端 DetectionLabel）。
struct DetectionLabel: Equatable, Sendable {
    let name: String
    let confidence: Float
    let key: String?
}

/// 分类决策配置（对应源端 ClassificationConfig）。
struct ClassificationConfig: Equatable, Sendable {
    /// CLIP embedding 维度（512）。
    let embeddingDim: Int
    /// 宠物检测阈值，bestPet.confidence 必须大于此值。
    let petDetectThreshold: Float
    /// 宠物与非宠物相似度差值的容差（bestPet.confidence - maxNonPetSim >= -tolerance）。
    let petNonPetTolerance: Float
}

/// 分类决策结果（对应源端 ClipClassificationResult）。
struct ClipClassificationResult: Equatable, Sendable {
    let isPet: Bool
    let labels: [DetectionLabel]
    /// 物种 key（如 "cat"/"dog"/"bird"）；非宠物为 nil。
    let species: String?
    let topLabel: String
    let topConfidence: Float
    /// 诊断信息（对应源端 AiService.lastDiagnostics）。
    let diagnostics: String
}

/// 输出 embedding 选择结果（对应源端 OutputEmbeddingSelection）。
struct OutputEmbeddingSelection: Equatable {
    /// 选中的 CLIP embedding 向量（已解码为 Float32）。
    let vector: [Float]
    /// 选中理由描述（对应源端 AiService.lastSelectedOutput）。
    let description: String
}

/// CLIP 推理纯决策逻辑（对应源端 `AiInferenceLogic`）。
enum AiInferenceLogic {

    // MARK: - 向量数学（对应源端 utils/MathUtils.ets）

    /// 计算两个向量的余弦相似度（对应源端 `cosineSimilarity`）。
    /// 长度不一致时取较短长度对齐；零向量返回 0。
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let len = min(a.count, b.count)
        if len == 0 { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<len {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }

    /// L2 归一化向量（原地修改，对应源端 `l2Normalize`）。
    /// 零向量不修改。
    static func l2Normalize(_ vector: inout [Float]) {
        var sumSq: Float = 0
        for v in vector { sumSq += v * v }
        let norm = sqrt(sumSq)
        if norm > 0 {
            for i in vector.indices { vector[i] /= norm }
        }
    }

    /// 返回归一化后的新向量（非原地版本，便于链式调用）。
    static func normalized(_ vector: [Float]) -> [Float] {
        var copy = vector
        l2Normalize(&copy)
        return copy
    }

    /// 计算一组向量的逐元素均值（对应源端 `averageEmbeddings`）。
    /// 空输入返回空数组；输入向量长度不一致时按最短长度对齐。
    static func averageEmbeddings(_ embeddings: [[Float]]) -> [Float] {
        guard let first = embeddings.first, !first.isEmpty else { return [] }
        let dim = embeddings.map(\.count).min() ?? first.count
        var sum = [Float](repeating: 0, count: dim)
        for embedding in embeddings {
            for i in 0..<dim { sum[i] += embedding[i] }
        }
        let count = Float(embeddings.count)
        for i in 0..<dim { sum[i] /= count }
        return sum
    }

    // MARK: - 输出 embedding 选择（对应源端 selectOutputEmbedding）

    /// 从模型多输出张量中选择最佳 CLIP embedding（对应源端 `selectOutputEmbedding`）。
    ///
    /// 评分规则（优先级从高到低）：
    /// 1. 名称含 "image_features"（+10000）
    /// 2. 长度精确等于 embeddingDim 且 shape=[1, embeddingDim]（+1000）
    /// 3. 向量有限非 NaN（+100）
    /// 4. L2 范数（有限时才计入）
    ///
    /// 仅接受 shape 为 [1, embeddingDim] 且 dtype 为 float32/float16 的输出。
    /// 找不到有效输出时抛出 `InferenceSelectionError.noValidEmbedding`。
    ///
    /// - Parameters:
    ///   - outputs: 模型输出的原始字节（每个对应一个输出张量，float32 小端序）。
    ///   - outputInfos: 模型输出张量元数据（与 outputs 一一对应）。
    ///   - embeddingDim: CLIP embedding 维度（512）。
    static func selectOutputEmbedding(
        outputs: [Data],
        outputInfos: [TensorInfo],
        embeddingDim: Int
    ) throws -> OutputEmbeddingSelection {
        guard outputs.count == outputInfos.count else {
            throw InferenceSelectionError.metadataMismatch(
                outputs: outputs.count, infos: outputInfos.count)
        }

        var bestVector: [Float]? = nil
        var bestIndex = -1
        var bestScore: Float = -1.0

        for (i, info) in outputInfos.enumerated() {
            let exactShape = info.shape.count == 2
                && info.shape[0] == 1
                && info.shape[1] == embeddingDim

            // shape 不符直接跳过
            guard exactShape else { continue }

            // 从 Data 解码 float32（CoreML mlprogram 输出接口为 float32）
            guard let candidate = decodeFloat32(outputs[i]), candidate.count == embeddingDim else {
                continue
            }

            let norm = l2Norm(candidate)
            let finite = candidate.allSatisfy { $0.isFinite }
            let namedEmbedding = info.name.contains("image_features")
            let score: Float = (namedEmbedding ? 10000.0 : 0.0)
                + 1000.0
                + (finite ? 100.0 : 0.0)
                + (finite ? norm : 0.0)

            if finite && norm > 0.000001 && score > bestScore {
                bestVector = candidate
                bestIndex = i
                bestScore = score
            }
        }

        guard let bestVector = bestVector else {
            throw InferenceSelectionError.noValidEmbedding
        }

        return OutputEmbeddingSelection(
            vector: bestVector,
            description: "output[\(bestIndex)], score=\(String(format: "%.4f", bestScore))"
        )
    }

    // MARK: - 宠物/非宠物分类（对应源端 classifyImageEmbedding）

    /// 从 CLIP image embedding 做宠物/非宠物分类决策（对应源端 `classifyImageEmbedding`）。
    ///
    /// 决策逻辑：
    /// 1. 计算 imageVec 与所有 petTextEmbeddings 的 cosine 相似度，收集 petScores
    /// 2. 计算 imageVec 与所有 nonPetTextEmbeddings 的 cosine 相似度，取最高分 maxNonPetSim
    /// 3. petScores 按 confidence 降序，取 bestPet
    /// 4. isPet = bestPet.confidence > threshold && (bestPet.confidence - maxNonPetSim) >= -tolerance
    ///
    /// speciesLabels 将 key 映射为可读名称（如 "cat" → "猫"）。
    static func classifyImageEmbedding(
        imageVec: [Float],
        petTextEmbeddings: [String: [Float]],
        nonPetTextEmbeddings: [String: [Float]],
        speciesLabels: [String: String],
        config: ClassificationConfig
    ) -> ClipClassificationResult {
        var petScores: [DetectionLabel] = []
        for (key, textVec) in petTextEmbeddings {
            guard textVec.count == config.embeddingDim, !isAllZero(textVec) else { continue }
            let sim = cosineSimilarity(imageVec, textVec)
            let label = speciesLabels[key] ?? key
            petScores.append(DetectionLabel(name: label, confidence: sim, key: key))
        }

        var maxNonPetSim: Float = -1
        var bestNonPetName = ""
        for (key, textVec) in nonPetTextEmbeddings {
            guard textVec.count == config.embeddingDim, !isAllZero(textVec) else { continue }
            let sim = cosineSimilarity(imageVec, textVec)
            if sim > maxNonPetSim {
                maxNonPetSim = sim
                bestNonPetName = key
            }
        }

        petScores.sort { $0.confidence > $1.confidence }
        guard let bestPet = petScores.first else {
            // 无可用宠物标签：非宠物，且不携带 topLabel（对应源端无 bestPet 分支）。
            return ClipClassificationResult(
                isPet: false,
                labels: petScores,
                species: nil,
                topLabel: "",
                topConfidence: 0,
                diagnostics: "classify: no pet labels matched (petScores=\(petScores.count))"
            )
        }

        let gap = bestPet.confidence - maxNonPetSim
        let isPet = bestPet.confidence > config.petDetectThreshold
            && gap >= -config.petNonPetTolerance

        let diagnostics = String(
            format: "classify: isPet=%@, bestPet=%@/%@ conf=%.4f, bestNonPet=%@ conf=%.4f, gap=%.4f, threshold=%@, tolerance=%@",
            isPet ? "true" : "false",
            bestPet.name, bestPet.key ?? "",
            bestPet.confidence,
            bestNonPetName,
            maxNonPetSim,
            gap,
            String(format: "%g", config.petDetectThreshold as CVarArg) as String,
            String(format: "%g", config.petNonPetTolerance as CVarArg) as String
        )

        let species = isPet ? (bestPet.key ?? bestPet.name) : nil

        return ClipClassificationResult(
            isPet: isPet,
            labels: petScores,
            species: species,
            topLabel: bestPet.name,
            topConfidence: bestPet.confidence,
            diagnostics: diagnostics
        )
    }

    // MARK: - 私有辅助

    /// 计算 L2 范数。
    private static func l2Norm(_ vector: [Float]) -> Float {
        var sumSq: Float = 0
        for v in vector { sumSq += v * v }
        return sqrt(sumSq)
    }

    /// 判断向量是否全零（对应源端 `textVec.every(v => v === 0)`）。
    private static func isAllZero(_ vector: [Float]) -> Bool {
        vector.allSatisfy { $0 == 0 }
    }

    /// 将 Data 解码为 [Float]（float32 小端序，CoreML 输出约定）。
    private static func decodeFloat32(_ data: Data) -> [Float]? {
        guard data.count % MemoryLayout<Float>.size == 0 else { return nil }
        return data.withUnsafeBytes { rawBuffer -> [Float] in
            let floatPtr = rawBuffer.bindMemory(to: Float.self)
            return Array(floatPtr)
        }
    }
}

/// embedding 选择错误（对应源端 selectOutputEmbedding 抛出的 Error）。
enum InferenceSelectionError: Error, Equatable {
    case metadataMismatch(outputs: Int, infos: Int)
    case noValidEmbedding
}
