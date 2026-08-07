//  InferenceEngine —— Core ML 推理协议（对应源端 IModelRunner）。
//  把 Core ML 模型加载/推理隔离在此协议后面。
//  真实实现待 P1.5 AI 路线 ADR 定案后补；此处先定义协议骨架 + mock。
//  DESIGN.md §9 平台适配层。

import Foundation

/// 模型张量数据类型（对应源端 ModelDataType，不引入 CoreML 枚举）。
enum MLDataType: String, Sendable, Equatable {
    case float32
    case float16
    case int32
    case uint8
}

/// 模型张量信息（对应源端 ModelTensorInfo）。
struct TensorInfo: Equatable, Sendable {
    let name: String
    let shape: [Int]
    let dataType: MLDataType
}

/// AI 模型推理协议。
/// Tensor 数据以 Data 传递，不直接暴露 CoreML 类型。
protocol InferenceEngine {
    /// 从沙盒路径加载模型（对应源端 loadFromFile）。
    func load(from path: String) async throws

    /// 运行推理（对应源端 predict）。
    /// - Parameter inputs: 按模型输入端口顺序的 Data 数组。
    /// - Returns: 按模型输出端口顺序的 Data 数组。
    func predict(_ inputs: [Data]) async throws -> [Data]

    /// 模型输入张量信息（对应源端 getInputInfos）。
    func inputInfos() -> [TensorInfo]

    /// 模型输出张量信息（对应源端 getOutputInfos）。
    func outputInfos() -> [TensorInfo]

    /// 模型是否已加载（对应源端 isLoaded）。
    var isLoaded: Bool { get }

    /// 释放模型资源（对应源端 release）。
    func release()
}

// MARK: - Mock（对应源端 FakeModelRunner）

/// 预设推理结果的 mock，用于单元测试。
final class MockInferenceEngine: InferenceEngine {
    private(set) var isLoaded = false
    /// 预设的推理输出（predict 返回此值）。
    var presetOutputs: [Data]
    /// 预设的输入张量信息。
    var presetInputInfos: [TensorInfo]
    /// 预设的输出张量信息。
    var presetOutputInfos: [TensorInfo]

    init(
        outputs: [Data] = [],
        inputInfos: [TensorInfo] = [],
        outputInfos: [TensorInfo] = []
    ) {
        self.presetOutputs = outputs
        self.presetInputInfos = inputInfos
        self.presetOutputInfos = outputInfos
    }

    func load(from path: String) async throws {
        isLoaded = true
    }

    func predict(_ inputs: [Data]) async throws -> [Data] {
        guard isLoaded else { throw NSError(domain: "MockInferenceEngine", code: 1) }
        return presetOutputs
    }

    func inputInfos() -> [TensorInfo] { presetInputInfos }
    func outputInfos() -> [TensorInfo] { presetOutputInfos }

    func release() {
        isLoaded = false
    }
}
