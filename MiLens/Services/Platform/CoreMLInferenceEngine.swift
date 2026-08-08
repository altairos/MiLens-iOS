//  CoreMLInferenceEngine —— InferenceEngine 真实实现（对应源端 adapters/impl/ModelRunner.ets）。
//
//  把 Core ML 模型加载/推理隔离在 InferenceEngine 协议后面。
//  Tensor 数据以 Data 传递（float32 小端序），不向业务层暴露 MLMultiArray/MLModel 类型。
//
//  ADR-0007 §2.1：业务层只依赖协议；真实实现与 mock 可互换。
//  模型资产（CLIPVisionEncoder*.mlmodelc / RTMPoseTPetFace.mlmodelc）由 .mlpackage 编译产生，
//  随 App Bundle 分发。加载失败时抛出明确错误，由调用方（ClipInferenceService）降级。

import CoreML
import Foundation

/// Core ML 推理错误。
enum CoreMLInferenceError: Error, LocalizedError {
    case notLoaded
    case modelNotFound(name: String)
    case inputCountMismatch(expected: Int, got: Int)
    case unsupportedInputType(name: String)
    case dataSizeMismatch(expected: Int, got: Int)
    case unsupportedOutputType(name: String)
    case predictionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notLoaded:
            return "CoreMLInferenceEngine: 模型未加载"
        case .modelNotFound(let name):
            return "CoreMLInferenceEngine: 未找到模型 \(name).mlmodelc"
        case .inputCountMismatch(let expected, let got):
            return "CoreMLInferenceEngine: 输入数量不匹配（期望 \(expected)，实际 \(got)）"
        case .unsupportedInputType(let name):
            return "CoreMLInferenceEngine: 不支持的输入类型 \(name)（仅支持 multiArray）"
        case .dataSizeMismatch(let expected, let got):
            return "CoreMLInferenceEngine: 输入数据大小不匹配（期望 \(expected) 字节，实际 \(got) 字节）"
        case .unsupportedOutputType(let name):
            return "CoreMLInferenceEngine: 不支持的输出类型 \(name)"
        case .predictionFailed(let underlying):
            return "CoreMLInferenceEngine: 推理失败 — \(underlying.localizedDescription)"
        }
    }
}

/// InferenceEngine 的 Core ML 真实实现（对应源端 `ModelRunner`）。
///
/// 一个实例加载一个模型（CLIPVisionEncoder 或 RTMPoseTPetFace）。
/// Tensor 数据以 Data 传递，内部转换为 MLMultiArray 调用 `MLModel.prediction`。
/// 计算 units 默认 `.all`（Neural Engine / GPU / CPU 自动选择）。
final class CoreMLInferenceEngine: InferenceEngine {

    private var model: MLModel?
    private(set) var isLoaded = false

    private init() {}

    // MARK: - InferenceEngine

    func load(from path: String) async throws {
        let url = URL(fileURLWithPath: path)
        let config = MLModelConfiguration()
        config.computeUnits = .all
        self.model = try MLModel(contentsOf: url, configuration: config)
        self.isLoaded = true
    }

    func predict(_ inputs: [Data]) async throws -> [Data] {
        guard let model = model, isLoaded else {
            throw CoreMLInferenceError.notLoaded
        }

        let description = model.modelDescription
        // 用 sorted key 保证输入顺序稳定（与 inputInfos() 一致）
        let inputNames = description.inputDescriptionsByName.keys.sorted()
        guard inputs.count == inputNames.count else {
            throw CoreMLInferenceError.inputCountMismatch(
                expected: inputNames.count, got: inputs.count)
        }

        var featureDict: [String: Any] = [:]
        for (idx, name) in inputNames.enumerated() {
            guard let inputDesc = description.inputDescriptionsByName[name] else {
                throw CoreMLInferenceError.unsupportedInputType(name: name)
            }
            guard inputDesc.type == .multiArray,
                  let constraint = inputDesc.multiArrayConstraint else {
                throw CoreMLInferenceError.unsupportedInputType(name: name)
            }
            let shape = constraint.shape.map { $0.intValue }
            let array = try makeMultiArray(
                from: inputs[idx], shape: shape, dataType: constraint.dataType)
            featureDict[name] = array
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
        let result: MLFeatureProvider
        do {
            result = try await model.prediction(from: provider, options: MLPredictionOptions())
        } catch {
            throw CoreMLInferenceError.predictionFailed(underlying: error)
        }

        // 用 sorted key 保证输出顺序稳定（与 outputInfos() 一致）
        let outputNames = description.outputDescriptionsByName.keys.sorted()
        var outputs: [Data] = []
        for name in outputNames {
            guard let value = result.featureValue(for: name),
                  let array = value.multiArrayValue else {
                // 输出缺失时填空 Data，保持位置对齐
                outputs.append(Data())
                continue
            }
            outputs.append(try extractData(from: array, name: name))
        }
        return outputs
    }

    func inputInfos() -> [TensorInfo] {
        guard let model = model else { return [] }
        return tensorInfos(from: model.modelDescription.inputDescriptionsByName)
    }

    func outputInfos() -> [TensorInfo] {
        guard let model = model else { return [] }
        return tensorInfos(from: model.modelDescription.outputDescriptionsByName)
    }

    func release() {
        model = nil
        isLoaded = false
    }

    // MARK: - 便捷构造（从 Bundle 加载编译后的 .mlmodelc）

    /// 从 App Bundle 加载编译后的 `.mlmodelc`（对应源端从 rawfile 复制到沙箱后加载）。
    /// - Parameters:
    ///   - name: 模型资源名（不含扩展名，如 "CLIPVisionEncoder_int8"）。
    ///   - bundle: 资源所在 bundle（默认 .main）。
    ///   - computeUnits: 计算 units（默认 .all，优先 Neural Engine/GPU）。
    static func loadFromBundle(
        name: String,
        bundle: Bundle = .main,
        computeUnits: MLComputeUnits = .all
    ) throws -> CoreMLInferenceEngine {
        guard let url = bundle.url(forResource: name, withExtension: "mlmodelc") else {
            throw CoreMLInferenceError.modelNotFound(name: name)
        }
        let engine = CoreMLInferenceEngine()
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits
        engine.model = try MLModel(contentsOf: url, configuration: config)
        engine.isLoaded = true
        return engine
    }

    // MARK: - 私有辅助

    /// 从模型描述字典提取 TensorInfo（按 name 排序，保证顺序稳定）。
    private func tensorInfos(from descriptionsByName: [String: MLFeatureDescription]) -> [TensorInfo] {
        descriptionsByName.keys.sorted().compactMap { name -> TensorInfo? in
            guard let desc = descriptionsByName[name],
                  desc.type == .multiArray,
                  let constraint = desc.multiArrayConstraint else {
                return nil
            }
            return TensorInfo(
                name: name,
                shape: constraint.shape.map { $0.intValue },
                dataType: mlDataTypeToDataType(constraint.dataType)
            )
        }
    }

    /// 将输入 Data 拷贝到新建的 MLMultiArray。
    private func makeMultiArray(
        from data: Data, shape: [Int], dataType: MLMultiArrayDataType
    ) throws -> MLMultiArray {
        let nsShape = shape.map { NSNumber(value: $0) }
        let array = try MLMultiArray(shape: nsShape, dataType: dataType)
        let totalElements = shape.reduce(1, *)
        let expectedBytes = totalElements * bytesPerElement(dataType)
        guard data.count == expectedBytes else {
            throw CoreMLInferenceError.dataSizeMismatch(
                expected: expectedBytes, got: data.count)
        }
        // contiguous 拷贝：MLMultiArray(shape:dataType:) 创建的数组是 C-order contiguous，
        // 直接用 dataPointer + memcpy 写入输入字节。
        // 空数据（shape 含 0 维度）时 baseAddress 为 nil，无字节可拷贝，直接返回。
        guard let baseAddress = data.withUnsafeBytes({ $0.baseAddress }) else {
            return array
        }
        memcpy(array.dataPointer, baseAddress, data.count)
        return array
    }

    /// 从 MLMultiArray 提取原始字节（float32 小端序）。
    /// 非 contiguous 布局或非 float32 输出时转换为 contiguous float32。
    private func extractData(from array: MLMultiArray, name: String) throws -> Data {
        // 检查是否为 contiguous C-order 布局
        let shape = array.shape.map { $0.intValue }
        let isContiguous = isCOrderContiguous(strides: array.strides.map { $0.intValue }, shape: shape)

        if isContiguous && array.dataType == .float32 {
            // 快速路径：直接拷贝连续 float32 数据
            let byteCount = shape.reduce(1, *) * MemoryLayout<Float>.size
            return Data(bytes: array.dataPointer, count: byteCount)
        }

        // 慢速路径：逐元素拷贝并转 float32
        return try copyAsContiguousFloat32(from: array)
    }

    /// 判断 strides 是否为 C-order contiguous（最后一维 stride=1，向前递增）。
    private func isCOrderContiguous(strides: [Int], shape: [Int]) -> Bool {
        guard strides.count == shape.count, !strides.isEmpty else { return false }
        var expected = 1
        for i in (0..<strides.count).reversed() {
            if strides[i] != expected { return false }
            expected *= shape[i]
        }
        return true
    }

    /// 逐元素遍历 MLMultiArray，按 C-order 输出 float32（处理非 contiguous / float16 输出）。
    private func copyAsContiguousFloat32(from array: MLMultiArray) throws -> Data {
        let totalElements = array.shape.map { $0.intValue }.reduce(1, *)
        var output = Data(count: totalElements * MemoryLayout<Float>.size)
        output.withUnsafeMutableBytes { (rawBuffer: UnsafeMutableRawBufferPointer) in
            let floatPtr = rawBuffer.bindMemory(to: Float.self)
            for linearIndex in 0..<totalElements {
                // 将线性索引转换为多维索引，再用 array[row][col]... 访问
                let multiIndex = linearToMultiIndex(linearIndex, shape: array.shape)
                let nsIndex = multiIndex.map { NSNumber(value: $0) }
                let scalar = array[nsIndex]
                floatPtr[linearIndex] = Float(truncating: scalar)
            }
        }
        return output
    }

    /// 线性索引 → 多维索引（C-order）。
    private func linearToMultiIndex(_ linear: Int, shape: [NSNumber]) -> [Int] {
        var remaining = linear
        var index: [Int] = []
        for dim in shape.reversed() {
            let d = dim.intValue
            index.insert(remaining % d, at: 0)
            remaining /= d
        }
        return index
    }

    private func bytesPerElement(_ dataType: MLMultiArrayDataType) -> Int {
        switch dataType {
        case .float32: return MemoryLayout<Float32>.size
        case .float16: return MemoryLayout<Float16>.size
        case .int32: return MemoryLayout<Int32>.size
        case .float64: return MemoryLayout<Float64>.size
        default: return MemoryLayout<Float32>.size
        }
    }

    private func mlDataTypeToDataType(_ dataType: MLMultiArrayDataType) -> MLDataType {
        switch dataType {
        case .float32: return .float32
        case .float16: return .float16
        case .int32: return .int32
        default: return .float32
        }
    }
}
