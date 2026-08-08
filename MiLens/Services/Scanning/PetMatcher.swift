//  PetMatcher —— 宠物视觉特征匹配服务（对应源端 services/PetMatcher.ets）。
//
//  职责：
//  - registerPetFeatures：从多张照片提取 CLIP embedding（失败降级手工特征），
//    聚合为均值向量 + 代表性样本 + 颜色签名，编码为 PMF1 blob 存入 Pet.featureData。
//  - matchFromEmbedding：把单张照片的 embedding 与所有已注册宠物的特征比较，
//    top1 分数 ≥ 阈值 + 与 top2 的 margin 足够 + 颜色距离不冲突才接受（自动归属判定）。
//  - extractMatchColorSignature：14 维颜色签名（匹配 tiebreaker）。
//
//  降级链（对应源端）：CLIP 推理失败 → 手工特征 embedding（仅匹配不作分类），
//  匹配阈值放宽（ScanControlMath.resolveMatchThreshold：fallback 0.85 / clip 0.82）。
//
//  像素计算经 AnalysisExecutor 后台执行，不占 MainActor（DESIGN.md §4 性能纪律）。

import Foundation
import os

/// 自动归属匹配结果（对应源端 MatchResult）。
struct PetMatchResult: Equatable, Sendable {
    let petID: UUID
    let score: Float
}

/// 匹配服务（@MainActor —— PetRepository 为 @MainActor 隔离）。
@MainActor
final class PetMatcher {

    private let logger = Logger(subsystem: "com.milens.app", category: "PetMatcher")

    private let petRepo: any PetRepositoryProtocol
    /// Phase 2 精筛 / embedding 提取（nil = CLIP 模型缺失，仅可手工特征降级匹配）
    private let clipService: (any ClipInference)?
    private let executor: AnalysisExecutor

    /// 上次注册诊断（对应源端 getLastRegisterDiagnostics）。
    private(set) var lastRegisterDiagnostics = "registration has not run yet"
    /// 上次匹配诊断（对应源端 getLastMatchDiagnostics）。
    private(set) var lastMatchDiagnostics = "matching has not run yet"

    init(petRepo: any PetRepositoryProtocol,
         clipService: (any ClipInference)?,
         executor: AnalysisExecutor = AnalysisExecutor()) {
        self.petRepo = petRepo
        self.clipService = clipService
        self.executor = executor
    }

    // MARK: - 特征注册（对应源端 registerPetFeatures）

    /// 为指定宠物注册视觉特征：从多张照片提取 embedding 并聚合，存入 Pet.featureData。
    /// - Parameters:
    ///   - petID: 宠物 ID
    ///   - imageDatas: 照片数据（JPEG/PNG 均可，内部缩放到检测尺寸）
    ///   - onProgress: 每张照片处理完成后的进度回调（已处理张数，main actor 调用）
    /// - Returns: 是否注册成功（至少 1 张有效 embedding 且 DB 写入成功）
    @discardableResult
    func registerPetFeatures(
        petID: UUID,
        imageDatas: [Data],
        onProgress: (@MainActor (Int) -> Void)? = nil
    ) async -> Bool {
        guard !imageDatas.isEmpty else {
            lastRegisterDiagnostics = "no image data provided"
            logger.warning("registerPetFeatures: 无照片数据")
            return false
        }

        var clipEmbeddings: [[Float]] = []
        var fallbackEmbeddings: [[Float]] = []
        var clipColorSignatures: [[Float]] = []
        var fallbackColorSignatures: [[Float]] = []
        var loadFailCount = 0
        var fallbackCount = 0
        var dimMismatchCount = 0
        var colorFailCount = 0
        var lastFailure = ""

        for (index, data) in imageDatas.enumerated() {
            if Task.isCancelled { break }
            // 单张提取（CLIP embedding / 降级手工特征 + 颜色签名）经后台执行器，不占 MainActor
            let extraction: (kind: PetEmbeddingKind, embedding: [Float], colorSignature: [Float]?)
            do {
                extraction = try await executor.run {
                    let clipService = self.clipService
                    var kind: PetEmbeddingKind = .clip
                    var embedding: [Float]
                    do {
                        guard let clipService else {
                            throw PetMatcherError.clipUnavailable
                        }
                        let result = try await clipService.detect(imageData: data)
                        embedding = result.embedding
                    } catch {
                        // CLIP 不可用/失败 → 手工特征降级（仅匹配不作分类，对应源端 fallback）
                        kind = .fallback
                        guard let clipService else {
                            throw PetMatcherError.clipUnavailable
                        }
                        embedding = try await clipService.extractFallbackEmbedding(imageData: data)
                    }
                    guard !embedding.isEmpty else {
                        throw PetMatcherError.emptyEmbedding
                    }
                    let colorSignature = try? await self.extractColorSignature(imageData: data)
                    return (kind, embedding, colorSignature)
                }
            } catch {
                loadFailCount += 1
                lastFailure = "extract[\(index)]: \(error.localizedDescription)"
                logger.warning("registerPetFeatures: [\(index)] 提取失败（\(error.localizedDescription)）")
                continue
            }

            let kind = extraction.kind
            let embedding = extraction.embedding
            let colorSignature = extraction.colorSignature

            if embedding.count != ClipConstants.embeddingDim {
                dimMismatchCount += 1
                lastFailure = "embedding[\(index)]: dim=\(embedding.count), expected=\(ClipConstants.embeddingDim)"
                logger.warning("registerPetFeatures: [\(index)] embedding 维度不符（\(embedding.count)）")
                continue
            }
            if !PetMatcherScoring.isValidEmbedding(embedding) {
                dimMismatchCount += 1
                lastFailure = "embedding[\(index)]: invalid/all-zero"
                logger.warning("registerPetFeatures: [\(index)] embedding 无效或全零")
                continue
            }
            if colorSignature == nil {
                colorFailCount += 1
                logger.warning("registerPetFeatures: [\(index)] 颜色签名提取失败")
            }
            if kind == .clip {
                clipEmbeddings.append(embedding)
                if let colorSignature { clipColorSignatures.append(colorSignature) }
            } else {
                fallbackEmbeddings.append(embedding)
                fallbackCount += 1
                if let colorSignature { fallbackColorSignatures.append(colorSignature) }
            }
            onProgress?(index + 1)
        }

        // 聚合：优先模型特征；模型特征完全不可用时整体降级手工特征（不同特征空间不混用）
        let embeddingKind: PetEmbeddingKind = clipEmbeddings.isEmpty ? .fallback : .clip
        let embeddings = embeddingKind == .clip ? clipEmbeddings : fallbackEmbeddings
        let colorSignatures = embeddingKind == .clip ? clipColorSignatures : fallbackColorSignatures
        let discardedOtherKind = embeddingKind == .clip ? fallbackEmbeddings.count : clipEmbeddings.count

        guard !embeddings.isEmpty else {
            lastRegisterDiagnostics = "0 valid embeddings out of \(imageDatas.count) — all failed: \(lastFailure)"
            logger.warning("registerPetFeatures: 全部照片提取失败（\(imageDatas.count) 张）")
            return false
        }
        if embeddings.count < PetFormConstants.minRegistrationPhotos {
            logger.info("registerPetFeatures: 仅 \(embeddings.count) 张有效 embedding，继续注册")
        }

        // 聚合为均值向量 + 代表性样本 + 颜色签名均值，编码为 PMF1 blob
        let avgVector = AiInferenceLogic.averageEmbeddings(embeddings)
        let colorVector = PetMatcherScoring.averageColorSignatures(colorSignatures, dim: PetMatchThreshold.colorSignatureDim)
        let representativeSamples = PetMatcherScoring.selectRepresentativeSamples(
            embeddings, maxCount: PetMatchThreshold.maxStoredSampleVectors, centroid: avgVector)
        let blob: Data
        do {
            blob = try PetFeatureCodec.encode(
                kind: embeddingKind, aggregate: avgVector,
                colorSignature: colorVector, samples: representativeSamples)
        } catch {
            lastRegisterDiagnostics = "encode failed: \(error.localizedDescription)"
            logger.error("registerPetFeatures: 编码失败（\(error.localizedDescription)）")
            return false
        }

        do {
            guard let pet = try petRepo.getPet(id: petID) else {
                lastRegisterDiagnostics = "pet not found"
                return false
            }
            try petRepo.updateFeatureData(pet, data: blob)
        } catch {
            lastRegisterDiagnostics = "DB save failed: \(error.localizedDescription)"
            logger.error("registerPetFeatures: 写入特征失败（\(error.localizedDescription)）")
            return false
        }

        lastRegisterDiagnostics = PetMatcherScoring.compactDiagnostics(
            "success: valid=\(embeddings.count)/\(imageDatas.count), kind=\(embeddingKind.rawValue), " +
            "fallback=\(fallbackCount), discardedOtherKind=\(discardedOtherKind), " +
            "loadFail=\(loadFailCount), dimMismatch=\(dimMismatchCount), " +
            "colorFail=\(colorFailCount), blob=\(blob.count) bytes")
        logger.info("registerPetFeatures: 注册成功（\(embeddings.count)/\(imageDatas.count)）")
        return true
    }

    // MARK: - 单张 embedding 提取（对应源端 extractEmbedding）

    /// 提取单张照片的 CLIP embedding；CLIP 失败时降级手工特征（fallback，仅匹配不作分类）。
    /// 像素解码与推理经后台执行器执行，不占 MainActor。
    /// - Throws: `PetMatcherError`（模型不可用 / 解码失败 / 空 embedding）
    func extractEmbedding(imageData: Data) async throws -> (kind: PetEmbeddingKind, embedding: [Float]) {
        try await executor.run {
            let clipService = self.clipService
            var kind: PetEmbeddingKind = .clip
            var embedding: [Float]
            do {
                guard let clipService else {
                    throw PetMatcherError.clipUnavailable
                }
                let result = try await clipService.detect(imageData: imageData)
                embedding = result.embedding
            } catch {
                // CLIP 不可用/失败 → 手工特征降级（对应源端 fallback）
                guard let clipService else {
                    throw PetMatcherError.clipUnavailable
                }
                kind = .fallback
                embedding = try await clipService.extractFallbackEmbedding(imageData: imageData)
            }
            guard !embedding.isEmpty else {
                throw PetMatcherError.emptyEmbedding
            }
            return (kind, embedding)
        }
    }

    // MARK: - 自动归属匹配（对应源端 matchFromEmbedding）

    /// 将单张照片的 embedding 与所有已注册宠物的特征比较，返回最佳匹配。
    ///
    /// 判定（对应源端）：
    /// - top1 分数 ≥ threshold（默认 STRICT 0.82；fallback 特征用 0.85 放宽）
    /// - 有第二名时 margin（top1 - top2）≥ 有效最小差距
    ///   （高置信匹配缩小 margin：bestScore ≥ threshold + 0.04 时 0.008，否则 0.025）
    /// - 颜色签名距离 ≤ MAX_COLOR_DISTANCE（0.34，超限直接拒绝该宠物）
    ///
    /// - Parameters:
    ///   - embedding: 已归一化的 CLIP embedding（512 维）
    ///   - threshold: 匹配阈值（默认 STRICT；fallback 场景由调用方放宽）
    ///   - colorSignature: 照片颜色签名（14 维，可 nil——跳过颜色约束）
    ///   - kind: embedding 类型（clip / fallback——不同特征空间不互相比较）
    /// - Returns: 匹配结果；未匹配返回 nil
    func matchFromEmbedding(
        embedding: [Float],
        threshold: Float = PetMatchThreshold.strict,
        colorSignature: [Float]? = nil,
        kind: PetEmbeddingKind = .clip
    ) async -> PetMatchResult? {
        guard !embedding.isEmpty else {
            lastMatchDiagnostics = "empty embedding"
            return nil
        }
        guard embedding.count == ClipConstants.embeddingDim,
              PetMatcherScoring.isValidEmbedding(embedding) else {
            lastMatchDiagnostics = "invalid embedding: dim=\(embedding.count)"
            logger.warning("matchFromEmbedding: embedding 无效（dim=\(embedding.count)）")
            return nil
        }

        let pets: [Pet]
        do {
            pets = try petRepo.getAllPets()
        } catch {
            lastMatchDiagnostics = "error: \(error.localizedDescription)"
            return nil
        }

        var bestPetID: UUID?
        var bestPetName = ""
        var bestScore: Float = -1
        var secondPetID: UUID?
        var secondPetName = ""
        var secondScore: Float = -1
        var bestScoreSource = ""
        var bestSampleCount = 0
        var registeredCount = 0
        var comparableCount = 0
        var dimMismatchCount = 0
        var invalidCount = 0
        var kindMismatchCount = 0
        var colorRejectedCount = 0
        var bestColorDistance: Float = -1
        var rejectedColorDistance: Float = -1

        for pet in pets {
            guard let data = pet.featureData else { continue }
            registeredCount += 1

            guard let feature = PetFeatureCodec.decode(data) else {
                dimMismatchCount += 1
                continue
            }
            if feature.aggregate.count != ClipConstants.embeddingDim {
                dimMismatchCount += 1
                continue
            }
            if feature.kind != kind {
                kindMismatchCount += 1
                continue
            }
            var petColorDist: Float = -1
            if let colorSignature,
               colorSignature.count == PetMatchThreshold.colorSignatureDim,
               let petColor = feature.colorSignature,
               petColor.count == PetMatchThreshold.colorSignatureDim {
                petColorDist = PetMatcherScoring.colorDistance(colorSignature, petColor)
            }
            comparableCount += 1
            if petColorDist >= 0 && petColorDist > PetMatchThreshold.maxColorDistance {
                colorRejectedCount += 1
                if rejectedColorDistance < 0 || petColorDist < rejectedColorDistance {
                    rejectedColorDistance = petColorDist
                }
                continue
            }

            guard let scored = PetMatcherScoring.scoreFeatureRecord(embedding: embedding, feature: feature) else {
                invalidCount += 1
                continue
            }
            let petScore = scored.score
            if petScore > bestScore {
                secondScore = bestScore
                secondPetID = bestPetID
                secondPetName = bestPetName
                bestScore = petScore
                bestPetID = pet.id
                bestPetName = pet.name
                bestColorDistance = petColorDist
                bestScoreSource = scored.source
                bestSampleCount = feature.samples.count
            } else if petScore > secondScore {
                secondScore = petScore
                secondPetID = pet.id
                secondPetName = pet.name
            }
        }

        let margin = bestScore - secondScore
        let hasCompetitor = secondPetID != nil
        // Adaptive margin：高置信匹配使用缩小的 margin 要求
        let highConfidence = bestScore >= threshold + PetMatchThreshold.highConfidenceDelta
        let effectiveMinMargin = highConfidence
            ? PetMatchThreshold.highConfidenceMinMargin
            : PetMatchThreshold.minMargin
        let marginOk = !hasCompetitor || margin >= effectiveMinMargin
        let diagnosticColorDistance = bestColorDistance >= 0 ? bestColorDistance : rejectedColorDistance
        let possibleThreshold = threshold <= PetMatchThreshold.strict ? PetMatchThreshold.normal : threshold
        let uncertain = bestScore >= possibleThreshold && bestScore < threshold

        lastMatchDiagnostics = PetMatcherScoring.compactDiagnostics(
            "registered=\(registeredCount)/\(pets.count), comparable=\(comparableCount), " +
            "kind=\(kind.rawValue), kindMismatch=\(kindMismatchCount), dimMismatch=\(dimMismatchCount), " +
            "invalid=\(invalidCount), colorRejected=\(colorRejectedCount), " +
            "bestPet=\(bestPetID?.uuidString ?? "none"), bestName=\(bestPetName), " +
            "bestScore=\(String(format: "%.4f", bestScore)), source=\(bestScoreSource), samples=\(bestSampleCount), " +
            "secondPet=\(secondPetID?.uuidString ?? "none"), secondName=\(secondPetName), " +
            "secondScore=\(String(format: "%.4f", secondScore)), margin=\(String(format: "%.4f", margin)), " +
            "effectiveMinMargin=\(String(format: "%.4f", effectiveMinMargin)), " +
            "highConfidence=\(highConfidence), colorDistance=\(String(format: "%.4f", diagnosticColorDistance)), " +
            "possibleThreshold=\(String(format: "%.4f", possibleThreshold)), " +
            "threshold=\(String(format: "%.4f", threshold)), uncertain=\(uncertain), marginOk=\(marginOk)")

        guard bestScore >= threshold, let bestPetID, marginOk else {
            logger.info("matchFromEmbedding: 未匹配（\(self.lastMatchDiagnostics)）")
            return nil
        }
        logger.info("matchFromEmbedding: 匹配宠物 \(bestPetName)（score=\(String(format: "%.4f", bestScore))）")
        return PetMatchResult(petID: bestPetID, score: bestScore)
    }

    // MARK: - 颜色签名（对应源端 extractMatchColorSignature）

    /// 提取照片的 14 维颜色签名；失败返回 nil（匹配时跳过颜色约束）。
    func extractMatchColorSignature(imageData: Data) async -> [Float]? {
        do {
            return try await executor.run {
                try await self.extractColorSignature(imageData: imageData)
            }
        } catch {
            return nil
        }
    }

    /// 解码像素并计算颜色签名（CPU 密集，须在后台执行器内调用）。
    private func extractColorSignature(imageData: Data) async throws -> [Float] {
        guard let (pixels, width, height) = ClipInferenceService.decodeToRGBA(
            imageData, maxDimension: ClipConstants.detectInputSize) else {
            throw PetMatcherError.decodeFailed
        }
        return ColorSignatureMath.computeColorSignature(
            pixelBytes: pixels, width: width, height: height,
            dim: PetMatchThreshold.colorSignatureDim)
    }
}

/// 特征提取错误。
enum PetMatcherError: Error {
    case clipUnavailable
    case emptyEmbedding
    case decodeFailed
}
