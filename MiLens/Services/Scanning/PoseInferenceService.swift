//  PoseInferenceService —— RTMPose-t 宠物五官关键点推理服务（对应源端 services/PoseInferenceService.ets）。
//
//  加载 RTMPoseTPetFace_fp16.mlmodelc（RTMPose-t 5 关键点，SimCC 输出），
//  从 RGBA 像素缓冲检测宠物面部关键点（左眼、右眼、鼻子、左耳尖、右耳尖）：
//  两阶段 coarse-to-fine（主体框粗推理 → deriveFaceBoxFromPose 构造紧凑脸框 → 细推理）。
//
//  串联管线（ADR-0007 §2.1/§4.3）：
//    pixels(RGBA) → preparePoseInput(ImageNet 归一化 NCHW) → InferenceEngine predict
//    → bindPoseOutputs（按张量名绑定 simcc_x/simcc_y）→ decodePoseOutputs（SimCC 解码）
//
//  纯逻辑在 MiLensKit（PoseSimccDecoder），本服务只做模型 IO 编排与降级。
//  模型不可用时 create() 返回 nil，调用方（BeadViewModel 抠图分支）静默跳过。

import CoreML
import Foundation
import MiLensKit

/// RTMPose 推理常量（对应源端 PoseInferenceService.ets 顶部常量）。
enum PoseConstants {
    /// 模型输入尺寸（对应源端 `INPUT_SIZE`）。
    static let inputSize = 192
    /// 关键点数量（左眼、右眼、鼻子、左耳尖、右耳尖，对应源端 `NUM_KEYPOINTS`）。
    static let numKeypoints = 5
    /// SimCC 上采样因子（对应源端 `UPSCALE_FACTOR`）。
    static let upscaleFactor = 2.0
    /// SimCC 序列长度 = inputSize × upscaleFactor（对应源端 `SIMCC_LENGTH`）。
    static let simccLength = Int(Double(inputSize) * upscaleFactor)  // 384
    /// 关键点置信度阈值（对应源端 `SCORE_THRESHOLD`）。
    static let scoreThreshold = 0.20
    /// 默认模型资源名（FP16 生产模型，随 models-v1 Release 交付）。
    static let defaultModelName = "RTMPoseTPetFace_fp16"
}

/// pose 推理错误。
enum PoseInferenceError: Error, LocalizedError {
    case engineNotLoaded
    case inputContractMismatch(String)
    case outputBindingFailed(String)
    case inferenceFailed(Error)

    var errorDescription: String? {
        switch self {
        case .engineNotLoaded:
            return "RTMPose 模型未加载"
        case .inputContractMismatch(let reason):
            return "RTMPose 输入契约不匹配：\(reason)"
        case .outputBindingFailed(let reason):
            return "RTMPose 输出绑定失败：\(reason)"
        case .inferenceFailed(let e):
            return "RTMPose 推理失败：\(e.localizedDescription)"
        }
    }
}

/// pose 推理协议（BeadViewModel 只依赖协议，测试注入 mock 引擎）。
/// Sendable：实现类不可变（let 存储，MLModel 线程安全）。
protocol PoseInference: Sendable {
    /// 从 RGBA 像素缓冲检测宠物面部关键点（归一化坐标）。
    /// 模型不可用或检测失败返回 nil（调用方降级，不阻塞生成流程）。
    func detectPose(pixels: [UInt8], width: Int, height: Int, bbox: CropRect?) async throws -> BeadPoseData?
}

final class PoseInferenceService: PoseInference, @unchecked Sendable {

    private let engine: InferenceEngine

    init(engine: InferenceEngine) {
        self.engine = engine
    }

    /// 模型是否已加载。
    var isLoaded: Bool { engine.isLoaded }

    /// 从 RGBA 像素缓冲检测宠物面部关键点（两阶段 coarse-to-fine）。
    ///
    /// 第一阶段使用主体框（缺省整图）做粗推理；第二阶段用粗关键点构造的
    /// 紧凑脸框细化，使最终输入更接近训练时的人工脸框。细化失败回退粗推理结果。
    /// - Parameters:
    ///   - pixels: RGBA 像素缓冲（top-left origin）。
    ///   - width/height: 像素缓冲尺寸。
    ///   - bbox: 主体框（像素坐标）；nil 时使用整图。
    /// - Returns: 归一化 [0,1] 关键点数据；检测失败返回 nil。
    func detectPose(pixels: [UInt8], width: Int, height: Int, bbox: CropRect?) async throws -> BeadPoseData? {
        guard engine.isLoaded else { throw PoseInferenceError.engineNotLoaded }
        guard width > 0, height > 0, pixels.count == width * height * 4 else { return nil }

        let subjectBox = bbox ?? CropRect(x: 0, y: 0, width: Double(width), height: Double(height))
        let inputInfo = try validateInputContract()

        // 第一阶段：主体框粗推理，寻找稳定双眼+鼻子锚点。
        guard let coarsePose = try await runPosePass(
            pixels: pixels, sourceWidth: width, sourceHeight: height,
            bbox: subjectBox, inputInfo: inputInfo) else {
            return nil
        }

        // 第二阶段：粗关键点构造紧凑脸框（对应源端 deriveFaceBoxFromPose）。
        guard let faceBox = deriveFaceBoxFromPose(
            pose: coarsePose,
            sourceWidth: width,
            sourceHeight: height,
            subjectBox: subjectBox,
            scoreThreshold: PoseConstants.scoreThreshold) else {
            return coarsePose
        }
        do {
            let refinedPose = try await runPosePass(
                pixels: pixels, sourceWidth: width, sourceHeight: height,
                bbox: faceBox, inputInfo: inputInfo)
            if let refinedPose, hasStableFaceAnchors(refinedPose, scoreThreshold: PoseConstants.scoreThreshold) {
                return refinedPose
            }
            // 细化结果不稳定，回退粗推理结果。
        } catch {
            // 细化失败回退粗推理结果（对应源端 catch 后使用 coarse pose）。
        }
        return coarsePose
    }

    // MARK: - 工厂（模型存在则创建，否则返回 nil 降级）

    /// 尝试创建 pose 推理服务（加载 RTMPose 模型）。
    /// 模型缺失或加载失败时返回 nil，调用方静默跳过（与 ClipInferenceService.create 一致）。
    static func create(
        modelName: String = PoseConstants.defaultModelName,
        bundle: Bundle = .main
    ) -> PoseInferenceService? {
        let engine: CoreMLInferenceEngine
        do {
            engine = try CoreMLInferenceEngine.loadFromBundle(name: modelName, bundle: bundle)
        } catch {
            return nil
        }
        return PoseInferenceService(engine: engine)
    }

    // MARK: - 私有辅助

    /// 校验固定输入契约：单输入 [1,3,192,192] 浮点张量（对应源端 validatePoseInputContract）。
    private func validateInputContract() throws -> TensorInfo {
        let infos = engine.inputInfos()
        guard infos.count == 1 else {
            throw PoseInferenceError.inputContractMismatch("期望 1 个输入，实际 \(infos.count)")
        }
        let info = infos[0]
        guard info.name.lowercased().contains("images") else {
            throw PoseInferenceError.inputContractMismatch("输入名不匹配：\(info.name)")
        }
        let expected = [1, 3, PoseConstants.inputSize, PoseConstants.inputSize]
        guard info.shape == expected else {
            throw PoseInferenceError.inputContractMismatch(
                "输入形状不匹配：\(info.shape)，期望 \(expected)")
        }
        guard info.dataType == .float32 || info.dataType == .float16 else {
            throw PoseInferenceError.inputContractMismatch(
                "输入类型不支持：\(info.dataType.rawValue)")
        }
        return info
    }

    /// 依据张量名绑定输出，禁止依赖数组顺序（对应源端 bindPoseOutputs）。
    private func bindPoseOutputs(
        outputs: [Data], outputInfos: [TensorInfo]
    ) throws -> PoseOutputPair {
        guard outputs.count == outputInfos.count else {
            throw PoseInferenceError.outputBindingFailed(
                "输出数量不匹配：outputs=\(outputs.count)，infos=\(outputInfos.count)")
        }
        let simccLength = PoseConstants.simccLength
        let numKeypoints = PoseConstants.numKeypoints
        let expectedShape = [1, numKeypoints, simccLength]
        let expectedElements = numKeypoints * simccLength
        var simccX: [Float]?
        var simccY: [Float]?
        for (index, info) in outputInfos.enumerated() {
            guard info.dataType == .float32 || info.dataType == .float16 else {
                throw PoseInferenceError.outputBindingFailed(
                    "\(info.name) 类型不支持：\(info.dataType.rawValue)")
            }
            guard info.shape == expectedShape else {
                throw PoseInferenceError.outputBindingFailed(
                    "\(info.name) 形状不匹配：\(info.shape)，期望 \(expectedShape)")
            }
            let buffer = outputs[index]
            guard buffer.count == expectedElements * MemoryLayout<Float>.size else {
                throw PoseInferenceError.outputBindingFailed(
                    "\(info.name) 缓冲大小不匹配：\(buffer.count)")
            }
            let floats = buffer.withUnsafeBytes { raw in
                Array(raw.bindMemory(to: Float.self))
            }
            if info.name.lowercased().contains("simcc_x") {
                guard simccX == nil else {
                    throw PoseInferenceError.outputBindingFailed("重复输出：simcc_x")
                }
                simccX = floats
            } else if info.name.lowercased().contains("simcc_y") {
                guard simccY == nil else {
                    throw PoseInferenceError.outputBindingFailed("重复输出：simcc_y")
                }
                simccY = floats
            }
        }
        guard let simccX, let simccY else {
            throw PoseInferenceError.outputBindingFailed("缺少 simcc_x/simcc_y 输出")
        }
        return PoseOutputPair(simccX: simccX, simccY: simccY)
    }

    /// 单次 pose 推理：预处理 → predict → 绑定输出 → SimCC 解码。
    private func runPosePass(
        pixels: [UInt8],
        sourceWidth: Int,
        sourceHeight: Int,
        bbox: CropRect,
        inputInfo: TensorInfo
    ) async throws -> BeadPoseData? {
        let prepared = try preparePoseInput(
            rgba: pixels, sourceWidth: sourceWidth, sourceHeight: sourceHeight,
            bbox: bbox, inputSize: PoseConstants.inputSize)

        // Core ML 输入统一 float32（源端按 dtype 编码 float16 是为 MindSpore 输入；
        // Core ML MLMultiArray 输入仅支持 float32，无需编码分支）。
        let inputData = ClipInferenceService.floatArrayToData(prepared.data)
        let outputs: [Data]
        do {
            outputs = try await engine.predict([inputData])
        } catch {
            throw PoseInferenceError.inferenceFailed(error)
        }

        let pair = try bindPoseOutputs(outputs: outputs, outputInfos: engine.outputInfos())
        return decodePoseOutputs(
            pair: pair,
            transform: prepared.transform,
            keypointCount: PoseConstants.numKeypoints,
            simccLength: PoseConstants.simccLength,
            splitRatio: PoseConstants.upscaleFactor,
            scoreThreshold: PoseConstants.scoreThreshold)
    }
}
