//  ClipInferenceService —— CLIP 推理编排（对应源端 services/AiService.ets fullClipInference）。
//
//  串联 CLIP 推理管线（ADR-0007 §2.1）：
//    imageData → 解码 RGBA → ClipPreprocess 归一化 → InferenceEngine predict
//    → AiInferenceLogic.selectOutputEmbedding → l2Normalize → classifyImageEmbedding
//
//  降级（对应源端 extractFallbackVisualEmbedding）：CLIP 模型不可用时，
//  用 computeHandcraftedFeatures 生成 512 维手工特征 embedding（仅用于已注册宠物视觉匹配，不作分类）。
//
//  DESIGN.md §4：Service 编排 IO + 异常处理 + 文案决策。纯决策逻辑下沉到 AiInferenceLogic。

import CoreGraphics
import Foundation
import ImageIO

/// CLIP 推理常量（对应源端 constants/AppConstants.ets AI_CONSTANTS）。
enum ClipConstants {
    /// CLIP 输入尺寸（ViT-B/32，对应源端 `CLIP_INPUT_SIZE`）。
    static let inputSize = 224
    /// CLIP embedding 维度（对应源端 `CLIP_EMBEDDING_DIM`）。
    static let embeddingDim = 512
    /// 宠物检测输入缩放边长（对应源端 `DETECT_INPUT_SIZE`，预处理前缩放）。
    static let detectInputSize = 256
    /// CLIP 归一化均值（R/G/B，对应源端 `NORMALIZE_MEAN`）。
    static let normalizeMean: [Double] = [0.48145466, 0.4578275, 0.40821073]
    /// CLIP 归一化标准差（R/G/B，对应源端 `NORMALIZE_STD`）。
    static let normalizeStd: [Double] = [0.26862954, 0.26130258, 0.27577711]
    /// 宠物检测阈值（embedding 余弦相似度，对应源端 `PET_DETECT_THRESHOLD`）。
    static let petDetectThreshold: Float = 0.20
    /// 宠物与非宠物相似度容差（对应源端 `PET_NON_PET_TOLERANCE`）。
    static let petNonPetTolerance: Float = 0.03
    /// 默认 CLIP 模型资源名（INT8 版本，体积更小）。
    static let defaultModelName = "CLIPVisionEncoder_int8"
}

/// CLIP 推理结果（对应源端 `DetectionResult`）。
struct ClipDetectionResult: Equatable {
    let isPet: Bool
    let labels: [DetectionLabel]
    let species: String?
    let embedding: [Float]
    let topLabel: String
    let topConfidence: Float
    /// CLIP 模型是否实际执行（false = 手工特征降级，仅可匹配不可分类）。
    let usedClipModel: Bool
    /// 诊断信息（对应源端 `AiService.lastDiagnostics`）。
    let diagnostics: String
}

/// CLIP 推理错误。
enum ClipInferenceError: Error, LocalizedError {
    case engineNotLoaded
    case decodeFailed
    case preprocessFailed(ClipPreprocessError)
    case selectionFailed(InferenceSelectionError)
    case inferenceFailed(Error)
    case unusableOutput

    var errorDescription: String? {
        switch self {
        case .engineNotLoaded:
            return "CLIP 模型未加载"
        case .decodeFailed:
            return "图像解码失败"
        case .preprocessFailed(let e):
            return "CLIP 预处理失败：\(e)"
        case .selectionFailed(let e):
            return "CLIP 输出选择失败：\(e)"
        case .inferenceFailed(let e):
            return "CLIP 推理失败：\(e.localizedDescription)"
        case .unusableOutput:
            return "CLIP 输出向量不可用（空/非有限/全零）"
        }
    }
}

/// CLIP 推理编排服务（对应源端 `AiService`）。
///
/// 一个实例绑定一个已加载的 `InferenceEngine`（CLIPVisionEncoder）和一组文本 embedding。
/// 构造后可直接调用 `detect` / `extractEmbedding`；模型不可用时用 `extractFallbackEmbedding` 降级。
///
/// ScanService 只依赖 `ClipInference` 协议（Phase 2 精筛），测试注入 mock。
protocol ClipInference {
    /// 完整 CLIP 推理：分类 + 提取 embedding。
    func detect(imageData: Data) async throws -> ClipDetectionResult
    /// 手工特征降级 embedding（CLIP 模型不可用时，仅用于已注册宠物视觉匹配）。
    func extractFallbackEmbedding(imageData: Data) async throws -> [Float]
}

final class ClipInferenceService: ClipInference {

    private let engine: InferenceEngine
    private let textEmbeddings: PetTextEmbeddingSet

    init(engine: InferenceEngine, textEmbeddings: PetTextEmbeddingSet) {
        self.engine = engine
        self.textEmbeddings = textEmbeddings
    }

    // MARK: - 完整推理（对应源端 fullClipInference）

    /// 完整 CLIP 推理：分类 + 提取 embedding（对应源端 `fullClipInference`）。
    ///
    /// 流程：解码 → 预处理（NCHW float32）→ predict → selectOutputEmbedding
    ///       → l2Normalize → classifyImageEmbedding。
    func detect(imageData: Data) async throws -> ClipDetectionResult {
        guard engine.isLoaded else { throw ClipInferenceError.engineNotLoaded }

        // 1. 解码为 RGBA 像素（top-left origin，与源端 PixelMap 一致）
        guard let (pixels, width, height) = Self.decodeToRGBA(
            imageData, maxDimension: ClipConstants.detectInputSize) else {
            throw ClipInferenceError.decodeFailed
        }

        // 2. 预处理：中心裁剪 + 双线性 + CLIP 归一化 → NCHW float32
        let inputFloat: [Float]
        do {
            inputFloat = try ClipPreprocess.bilinearResizeAndNormalize(
                pixelBytes: pixels,
                origWidth: width, origHeight: height,
                targetSize: ClipConstants.inputSize,
                mean: ClipConstants.normalizeMean,
                std: ClipConstants.normalizeStd,
                layout: .nchw)
        } catch let e as ClipPreprocessError {
            throw ClipInferenceError.preprocessFailed(e)
        }

        // 3. [Float] → Data（float32 小端序）
        let inputData = Self.floatArrayToData(inputFloat)

        // 4. 推理
        let outputs: [Data]
        do {
            outputs = try await engine.predict([inputData])
        } catch {
            throw ClipInferenceError.inferenceFailed(error)
        }

        // 5. 选择最佳 embedding 张量
        let outputInfos = engine.outputInfos()
        let selection: OutputEmbeddingSelection
        do {
            selection = try AiInferenceLogic.selectOutputEmbedding(
                outputs: outputs, outputInfos: outputInfos,
                embeddingDim: ClipConstants.embeddingDim)
        } catch let e as InferenceSelectionError {
            throw ClipInferenceError.selectionFailed(e)
        }

        // 6. 可用性检查 + L2 归一化
        guard isUsableVector(selection.vector) else {
            throw ClipInferenceError.unusableOutput
        }
        var embedding = selection.vector
        AiInferenceLogic.l2Normalize(&embedding)

        // 7. 宠物/非宠物分类
        let config = ClassificationConfig(
            embeddingDim: ClipConstants.embeddingDim,
            petDetectThreshold: ClipConstants.petDetectThreshold,
            petNonPetTolerance: ClipConstants.petNonPetTolerance)
        let classification = AiInferenceLogic.classifyImageEmbedding(
            imageVec: embedding,
            petTextEmbeddings: textEmbeddings.pet,
            nonPetTextEmbeddings: textEmbeddings.nonPet,
            speciesLabels: petSpeciesLabels,
            config: config)

        return ClipDetectionResult(
            isPet: classification.isPet,
            labels: classification.labels,
            species: classification.species,
            embedding: embedding,
            topLabel: classification.topLabel,
            topConfidence: classification.topConfidence,
            usedClipModel: true,
            diagnostics: "\(selection.description); \(classification.diagnostics)")
    }

    // MARK: - 降级 embedding（对应源端 extractFallbackVisualEmbedding）

    /// 生成手工特征降级 embedding（CLIP 模型不可用时，仅用于已注册宠物视觉匹配）。
    /// 16×16 网格亮度+饱和度 → 512 维 → L2 归一化。
    func extractFallbackEmbedding(imageData: Data) async throws -> [Float] {
        guard let (pixels, width, height) = Self.decodeToRGBA(
            imageData, maxDimension: ClipConstants.detectInputSize) else {
            throw ClipInferenceError.decodeFailed
        }
        let features: [Float]
        do {
            features = try ClipPreprocess.computeHandcraftedFeatures(
                pixelBytes: pixels, width: width, height: height)
        } catch let e as ClipPreprocessError {
            throw ClipInferenceError.preprocessFailed(e)
        }
        return AiInferenceLogic.normalized(features)
    }

    // MARK: - 工厂（模型存在则创建，否则返回 nil 降级）

    /// 尝试创建 CLIP 推理服务（加载模型 + 文本 embedding）。
    /// 模型缺失或文本 embedding 缺失时返回 nil，调用方降级到 VisionService 预筛。
    static func create(
        modelName: String = ClipConstants.defaultModelName,
        bundle: Bundle = .main
    ) -> ClipInferenceService? {
        let engine: CoreMLInferenceEngine
        do {
            engine = try CoreMLInferenceEngine.loadFromBundle(name: modelName, bundle: bundle)
        } catch {
            return nil
        }
        let textEmbeddings: PetTextEmbeddingSet
        do {
            textEmbeddings = try PetTextEmbeddings.load(from: bundle)
        } catch {
            engine.release()
            return nil
        }
        return ClipInferenceService(engine: engine, textEmbeddings: textEmbeddings)
    }

    // MARK: - 私有辅助

    /// 判断向量是否可用（非空、有限、非全零）。
    private func isUsableVector(_ vector: [Float]) -> Bool {
        guard !vector.isEmpty else { return false }
        var hasNonZero = false
        for v in vector {
            if !v.isFinite { return false }
            if v != 0 { hasNonZero = true }
        }
        return hasNonZero
    }

    /// [Float] → Data（float32 小端序）。
    static func floatArrayToData(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    /// 解码图片数据为 RGBA 像素缓冲区（top-left origin，与源端 PixelMap 一致）。
    /// 先缩放到 maxDimension（保持宽高比），再提取 RGBA。
    /// - Returns: (pixels: [UInt8] RGBA, width, height)；解码失败返回 nil。
    static func decodeToRGBA(
        _ data: Data, maxDimension: Int
    ) -> (pixels: [UInt8], width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let origW = cgImage.width
        let origH = cgImage.height
        let scale = CGFloat(maxDimension) / CGFloat(max(origW, origH))
        let newWidth = max(1, Int((CGFloat(origW) * scale).rounded()))
        let newHeight = max(1, Int((CGFloat(origH) * scale).rounded()))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = newWidth * 4
        var pixels = [UInt8](repeating: 0, count: newWidth * newHeight * 4)

        guard let context = CGContext(
            data: &pixels, width: newWidth, height: newHeight,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        // CGContext 原点在左下，翻转 CTM 使输出为 top-left origin（与源端 PixelMap 一致）
        context.translateBy(x: 0, y: CGFloat(newHeight))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        // premultipliedLast 的 RGB 已预乘 alpha；CLIP 预处理按非预乘处理。
        // 对于扫描场景的 JPEG（alpha=255），预乘无影响；此处不做 unpremultiply（与源端一致）。
        return (pixels, newWidth, newHeight)
    }
}
