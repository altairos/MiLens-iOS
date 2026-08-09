import XCTest
@testable import MiLens
@testable import MiLensKit

/// PoseInferenceService 编排测试：两阶段 coarse-to-fine、按名绑定输出、降级路径。
/// 注入 mock 引擎（不加载真实 Core ML 模型），与 ClipInferenceService 的测试纪律一致。
final class PoseInferenceServiceTests: XCTestCase {

    private let simccLength = 384
    private let numKeypoints = 5
    private let inputSize = 192
    /// 峰值 6.0 → one-vs-rest softmax 置信度 ≈ 0.51（> 0.2 阈值，可计数）。
    private let peakValue: Float = 6.0

    // MARK: - Helpers

    /// 按调用次数返回预设输出的 mock 引擎（记录输入字节数以便断言预处理契约）。
    private final class PoseMockEngine: InferenceEngine {
        var isLoaded = true
        /// 每次 predict 按序弹出一个输出组。
        var outputsQueue: [[Data]] = []
        private(set) var recordedInputs: [Data] = []
        private let inputInfoList: [TensorInfo]
        private let outputInfoList: [TensorInfo]

        init(inputInfos: [TensorInfo], outputInfos: [TensorInfo]) {
            self.inputInfoList = inputInfos
            self.outputInfoList = outputInfos
        }

        func load(from path: String) async throws { isLoaded = true }

        func predict(_ inputs: [Data]) async throws -> [Data] {
            recordedInputs.append(contentsOf: inputs)
            guard !outputsQueue.isEmpty else { return [] }
            return outputsQueue.removeFirst()
        }

        func inputInfos() -> [TensorInfo] { inputInfoList }
        func outputInfos() -> [TensorInfo] { outputInfoList }

        func release() { isLoaded = false }
    }

    private func simccInfos() -> [TensorInfo] {
        [
            TensorInfo(name: "simcc_x", shape: [1, numKeypoints, simccLength], dataType: .float32),
            TensorInfo(name: "simcc_y", shape: [1, numKeypoints, simccLength], dataType: .float32)
        ]
    }

    private func imagesInputInfo() -> [TensorInfo] {
        [TensorInfo(name: "images", shape: [1, 3, inputSize, inputSize], dataType: .float32)]
    }

    private func floatData(_ values: [Float]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// 5 个关键点的 SimCC 输出对：第 index 个关键点在 (peakX, peakY) 处有峰值。
    private func outputs(peaks: [(x: Int, y: Int)]) -> [Data] {
        var xValues = [Float](repeating: -3, count: numKeypoints * simccLength)
        var yValues = [Float](repeating: -3, count: numKeypoints * simccLength)
        for (index, peak) in peaks.enumerated() {
            xValues[index * simccLength + peak.x] = peakValue
            yValues[index * simccLength + peak.y] = peakValue
        }
        return [floatData(xValues), floatData(yValues)]
    }

    /// 全部关键点无峰值的输出对（解码后 confidence=0，visibleCount=0）。
    private func blankOutputs() -> [Data] {
        let blank = [Float](repeating: -3, count: numKeypoints * simccLength)
        return [floatData(blank), floatData(blank)]
    }

    /// 构造 192×192 全零 RGBA 像素缓冲。
    private func pixelBuffer() -> [UInt8] {
        [UInt8](repeating: 0, count: inputSize * inputSize * 4)
    }

    /// 主体框内的稳定粗锚点峰值（脸大致在中心区域，保证 faceBox 推导有效）。
    private var stableCoarsePeaks: [(x: Int, y: Int)] {
        [
            (x: 96, y: 88), (x: 128, y: 88), (x: 112, y: 112),  // 左眼、右眼、鼻子
            (x: 80, y: 72), (x: 144, y: 72)                    // 左耳尖、右耳尖
        ]
    }

    /// 粗推理关键点 0 的归一化 x 坐标（峰值 96，整图 bbox → cropSize=240 居中）：
    /// sourceX = -24 + 48·240/192 = 36 → 36/192 = 0.1875。
    private let coarseKeypoint0X = 0.1875

    // MARK: - 契约与降级

    func testThrowsWhenModelNotLoaded() async {
        let engine = PoseMockEngine(inputInfos: imagesInputInfo(), outputInfos: simccInfos())
        engine.isLoaded = false
        let service = PoseInferenceService(engine: engine)
        do {
            _ = try await service.detectPose(pixels: pixelBuffer(), width: inputSize, height: inputSize, bbox: nil)
            XCTFail("模型未加载时应抛出 engineNotLoaded")
        } catch let e as PoseInferenceError {
            if case .engineNotLoaded = e {} else {
                XCTFail("错误类型不匹配：\(e)")
            }
        } catch {
            XCTFail("错误类型不匹配：\(error)")
        }
    }

    func testReturnsNilForInvalidPixelBuffer() async throws {
        let engine = PoseMockEngine(inputInfos: imagesInputInfo(), outputInfos: simccInfos())
        let service = PoseInferenceService(engine: engine)
        // 像素数与宽高不匹配（192×192 需要 4 字节/像素，给 5 字节）
        let result = try await service.detectPose(
            pixels: [UInt8](repeating: 0, count: 5), width: inputSize, height: inputSize, bbox: nil)
        XCTAssertNil(result)
    }

    func testThrowsOnInputContractMismatch() async {
        let engine = PoseMockEngine(
            inputInfos: [TensorInfo(name: "images", shape: [1, 224, 224, 3], dataType: .float32)],
            outputInfos: simccInfos())
        let service = PoseInferenceService(engine: engine)
        do {
            _ = try await service.detectPose(pixels: pixelBuffer(), width: inputSize, height: inputSize, bbox: nil)
            XCTFail("输入契约不匹配时应抛错")
        } catch let e as PoseInferenceError {
            if case .inputContractMismatch = e {} else {
                XCTFail("错误类型不匹配：\(e)")
            }
        } catch {
            XCTFail("错误类型不匹配：\(error)")
        }
    }

    // MARK: - 两阶段编排

    /// 粗推理无可信关键点（全 -3）→ 返回 nil，不进入细化。
    func testReturnsNilWhenCoarsePassFindsNothing() async throws {
        let engine = PoseMockEngine(inputInfos: imagesInputInfo(), outputInfos: simccInfos())
        engine.outputsQueue = [blankOutputs()]
        let service = PoseInferenceService(engine: engine)
        let result = try await service.detectPose(pixels: pixelBuffer(), width: inputSize, height: inputSize, bbox: nil)
        XCTAssertNil(result)
        XCTAssertEqual(engine.recordedInputs.count, 1, "粗推理失败不应触发细化推理")
    }

    /// 粗推理输出稳定锚点（双眼+鼻子）→ 细化通过脸框二次推理，返回细化结果。
    func testRefinesWithFaceBoxWhenAnchorsStable() async throws {
        let engine = PoseMockEngine(inputInfos: imagesInputInfo(), outputInfos: simccInfos())
        let coarse = outputs(peaks: stableCoarsePeaks)
        // 细化推理：关键点 0 峰值右移（96 → 160），验证返回的是细化而非粗推理结果。
        var refinedPeaks = stableCoarsePeaks
        refinedPeaks[0] = (x: 160, y: 96)
        engine.outputsQueue = [coarse, outputs(peaks: refinedPeaks)]
        let service = PoseInferenceService(engine: engine)
        let result = try await service.detectPose(pixels: pixelBuffer(), width: inputSize, height: inputSize, bbox: nil)
        XCTAssertNotNil(result)
        XCTAssertEqual(engine.recordedInputs.count, 2, "稳定锚点应触发两次推理（粗 + 细化）")
        // 细化 keypoint0：faceBox(16,12,60) → cropSize=75、cropX=8.5
        // sourceX = 8.5 + 80·75/192 = 39.75 → 39.75/192 ≈ 0.207
        XCTAssertEqual(result!.keypoints[0].x, 0.20703125, accuracy: 0.001, "应返回细化结果")
        // 两次推理输入均为 192×192×3 float32（NCHW 预处理契约）
        for input in engine.recordedInputs {
            XCTAssertEqual(input.count, inputSize * inputSize * 3 * 4)
        }
    }

    /// 细化结果无稳定锚点（全部无峰值）→ 回退粗推理结果。
    func testFallsBackToCoarseWhenRefinementUnstable() async throws {
        let engine = PoseMockEngine(inputInfos: imagesInputInfo(), outputInfos: simccInfos())
        engine.outputsQueue = [outputs(peaks: stableCoarsePeaks), blankOutputs()]
        let service = PoseInferenceService(engine: engine)
        let result = try await service.detectPose(pixels: pixelBuffer(), width: inputSize, height: inputSize, bbox: nil)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.keypoints[0].x, coarseKeypoint0X, accuracy: 0.001, "应回退粗推理结果")
    }

    // MARK: - 输出绑定

    /// 输出按张量名绑定而非数组顺序：info 列表乱序（simcc_y 在前）时，
    /// 数据仍按引擎契约与 info 位置对齐返回，实现须按名字归类（不依赖 x 在第 0 位）。
    func testBindsOutputsByNameRegardlessOfOrder() async throws {
        let engine = PoseMockEngine(
            inputInfos: imagesInputInfo(),
            outputInfos: [
                TensorInfo(name: "simcc_y", shape: [1, numKeypoints, simccLength], dataType: .float32),
                TensorInfo(name: "simcc_x", shape: [1, numKeypoints, simccLength], dataType: .float32)
            ])
        let coarse = outputs(peaks: stableCoarsePeaks)
        // 数据与 info 位置对齐（引擎契约 outputs[i] ↔ outputInfos[i]），但 simcc_x 不在第 0 位
        engine.outputsQueue = [[coarse[1], coarse[0]]]
        let service = PoseInferenceService(engine: engine)
        let result = try await service.detectPose(pixels: pixelBuffer(), width: inputSize, height: inputSize, bbox: nil)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.keypoints[0].x, coarseKeypoint0X, accuracy: 0.001)
    }

    /// 输出缺少 simcc_y 时抛绑定错误（不静默返回错误坐标）。
    func testThrowsWhenOutputMissing() async {
        let engine = PoseMockEngine(
            inputInfos: imagesInputInfo(),
            outputInfos: [TensorInfo(name: "simcc_x", shape: [1, numKeypoints, simccLength], dataType: .float32)])
        engine.outputsQueue = [blankOutputs()]
        let service = PoseInferenceService(engine: engine)
        do {
            _ = try await service.detectPose(pixels: pixelBuffer(), width: inputSize, height: inputSize, bbox: nil)
            XCTFail("缺少输出时应抛绑定错误")
        } catch let e as PoseInferenceError {
            if case .outputBindingFailed = e {} else {
                XCTFail("错误类型不匹配：\(e)")
            }
        } catch {
            XCTFail("错误类型不匹配：\(error)")
        }
    }
}
