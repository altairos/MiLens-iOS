//  ClipInferenceServiceTests —— CLIP 推理编排服务测试（对应源端 AiService 编排路径）。
//  覆盖 decodeToRGBA 缩放与容错、floatArrayToData 字节布局、
//  detect 端到端（MockInferenceEngine 注入输出张量）与错误映射、手工特征降级、工厂降级。
//  AiInferenceLogic 的纯决策分支由 AiInferenceLogicTests 覆盖。

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MiLens

final class ClipInferenceServiceTests: XCTestCase {

    // MARK: - 测试辅助

    /// 构造 one-hot 方向的 512 维向量（index 位为 1）。
    private func oneHot(_ index: Int) -> [Float] {
        var v = [Float](repeating: 0, count: ClipConstants.embeddingDim)
        v[index] = 1
        return v
    }

    /// 合成纯色 JPEG（decodeToRGBA 走真实 CGImageSource 解码路径）。
    private func makeImageData(
        width: Int, height: Int, rgb: (UInt8, UInt8, UInt8) = (255, 0, 0)
    ) -> Data {
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        for _ in 0..<(width * height) {
            pixels.append(rgb.0)
            pixels.append(rgb.1)
            pixels.append(rgb.2)
            pixels.append(255)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast,
                provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)
        else { return Data() }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return Data() }
        return out as Data
    }

    /// 预设引擎输出张量字节（float32 小端）。
    private func makeEmbeddingOutput(_ vector: [Float]) -> Data {
        ClipInferenceService.floatArrayToData(vector)
    }

    /// 标准输出张量元信息（shape [1, 512]，名称含 image_features）。
    private func makeOutputInfo() -> TensorInfo {
        TensorInfo(
            name: "image_features", shape: [1, ClipConstants.embeddingDim],
            dataType: .float32)
    }

    /// 已加载的 mock 引擎（predict 返回预设输出）。
    private func makeLoadedEngine(
        outputs: [Data], outputInfos: [TensorInfo]
    ) async throws -> MockInferenceEngine {
        let engine = MockInferenceEngine(outputs: outputs, outputInfos: outputInfos)
        try await engine.load(from: "/mock/clip")
        return engine
    }

    /// 文本集：cat/dog 与 person/car 用正交 one-hot 方向，夹角可控。
    private func makeTextSet() -> PetTextEmbeddingSet {
        PetTextEmbeddingSet(
            pet: ["cat": oneHot(0), "dog": oneHot(1)],
            nonPet: ["person": oneHot(10), "car": oneHot(11)])
    }

    /// predict 必抛错的引擎（覆盖 inferenceFailed 错误映射）。
    private final class FailingPredictEngine: InferenceEngine {
        var isLoaded = true
        func load(from path: String) async throws {}
        func predict(_ inputs: [Data]) async throws -> [Data] {
            throw NSError(domain: "ClipInferenceServiceTests", code: 42)
        }
        func inputInfos() -> [TensorInfo] { [] }
        func outputInfos() -> [TensorInfo] { [] }
        func release() {}
    }
    // MARK: - decodeToRGBA / floatArrayToData

    func testDecodeToRGBAScalesLandscapeToMaxDimension() throws {
        let data = makeImageData(width: 640, height: 480)
        XCTAssertFalse(data.isEmpty)

        let decoded = ClipInferenceService.decodeToRGBA(
            data, maxDimension: ClipConstants.detectInputSize)
        let output = try XCTUnwrap(decoded)
        XCTAssertEqual(output.width, 256)
        XCTAssertEqual(output.height, 192)
        XCTAssertEqual(output.pixels.count, 256 * 192 * 4)
    }

    func testDecodeToRGBAScalesPortraitToMaxDimension() throws {
        let data = makeImageData(width: 480, height: 640)

        let output = try XCTUnwrap(
            ClipInferenceService.decodeToRGBA(
                data, maxDimension: ClipConstants.detectInputSize))
        XCTAssertEqual(output.width, 192)
        XCTAssertEqual(output.height, 256)
    }

    func testDecodeToRGBAUpscalesSmallImageToMaxDimension() throws {
        // scale = 256/100 = 2.56；高 80×2.56 = 204.8 → rounded 205（无上限钳制，与源端一致）。
        let data = makeImageData(width: 100, height: 80)

        let output = try XCTUnwrap(
            ClipInferenceService.decodeToRGBA(data, maxDimension: 256))
        XCTAssertEqual(output.width, 256)
        XCTAssertEqual(output.height, 205)
    }

    func testDecodeToRGBAPreservesDominantColor() throws {
        let data = makeImageData(width: 64, height: 64, rgb: (255, 0, 0))

        let output = try XCTUnwrap(ClipInferenceService.decodeToRGBA(data, maxDimension: 256))
        // JPEG 有压缩损失，用宽松阈值验证主色未被翻转。
        let r = output.pixels[0]
        let g = output.pixels[1]
        let b = output.pixels[2]
        XCTAssertGreaterThan(r, 200)
        XCTAssertLessThan(g, 60)
        XCTAssertLessThan(b, 60)
    }

    func testDecodeToRGBAInvalidDataReturnsNil() {
        let decoded = ClipInferenceService.decodeToRGBA(
            Data("not an image".utf8), maxDimension: 256)
        XCTAssertNil(decoded)
    }

    func testFloatArrayToDataEncodesLittleEndianFloat32() {
        let data = ClipInferenceService.floatArrayToData([1.0, -0.5])
        XCTAssertEqual(data.count, 8)
        let bytes = [UInt8](data)
        // Float(1.0) = 0x3F800000 → 小端 00 00 80 3F
        XCTAssertEqual(bytes[0], 0x00)
        XCTAssertEqual(bytes[1], 0x00)
        XCTAssertEqual(bytes[2], 0x80)
        XCTAssertEqual(bytes[3], 0x3F)
        // Float(-0.5) = 0xBF000000 → 小端 00 00 00 BF
        XCTAssertEqual(bytes[7], 0xBF)
    }
    // MARK: - detect 端到端（MockInferenceEngine 注入输出张量）

    func testDetectClassifiesPetEndToEnd() async throws {
        // 图像 embedding = 2×oneHot(0)（范数 2，验证结果被 L2 归一化）；
        // 与 pet "cat"（oneHot(0)）cos=1 > 0.2，与非宠物全部正交 cos=0 → gap=1 → isPet。
        let outputVector = oneHot(0).map { $0 * 2 }
        let engine = try await makeLoadedEngine(
            outputs: [makeEmbeddingOutput(outputVector)],
            outputInfos: [makeOutputInfo()])
        let service = ClipInferenceService(engine: engine, textEmbeddings: makeTextSet())

        let result = try await service.detect(imageData: makeImageData(width: 320, height: 240))

        XCTAssertTrue(result.isPet)
        XCTAssertEqual(result.species, "cat")
        XCTAssertEqual(result.topLabel, "猫")
        XCTAssertEqual(result.topConfidence, 1, accuracy: 0.001)
        XCTAssertTrue(result.usedClipModel)
        XCTAssertFalse(result.diagnostics.isEmpty)
        XCTAssertEqual(result.embedding.count, ClipConstants.embeddingDim)
        var sumSq: Float = 0
        for v in result.embedding { sumSq += v * v }
        XCTAssertEqual(sumSq, 1, accuracy: 0.001)
    }

    func testDetectRejectsWhenNonPetDominates() async throws {
        // 图像方向 = 0.5×oneHot(0) + 1×oneHot(10)：cat cos≈0.447（过阈值 0.2），
        // person cos≈0.894 → gap≈-0.447 < -0.03 → 判非宠物（gap 双条件守护）。
        var outputVector = oneHot(0).map { $0 * 0.5 }
        for (i, v) in oneHot(10).enumerated() where v != 0 { outputVector[i] += v }
        let engine = try await makeLoadedEngine(
            outputs: [makeEmbeddingOutput(outputVector)],
            outputInfos: [makeOutputInfo()])
        let service = ClipInferenceService(engine: engine, textEmbeddings: makeTextSet())

        let result = try await service.detect(imageData: makeImageData(width: 320, height: 240))

        XCTAssertFalse(result.isPet)
        XCTAssertNil(result.species)
        // topLabel/topConfidence 仍携带 bestPet 信息（降级展示用）。
        XCTAssertEqual(result.topLabel, "猫")
        XCTAssertEqual(result.topConfidence, 0.447, accuracy: 0.01)
    }

    func testDetectRejectsBelowThresholdWithoutNonPet() async throws {
        // 非宠物集合为空 → maxNonPetSim=-1，gap 恒通过；
        // cat cos≈0.0995 < 阈值 0.2 → 单独验证阈值条件。
        var outputVector = oneHot(0).map { $0 * 0.1 }
        for (i, v) in oneHot(10).enumerated() where v != 0 { outputVector[i] += v }
        let engine = try await makeLoadedEngine(
            outputs: [makeEmbeddingOutput(outputVector)],
            outputInfos: [makeOutputInfo()])
        let textSet = PetTextEmbeddingSet(pet: ["cat": oneHot(0)], nonPet: [:])
        let service = ClipInferenceService(engine: engine, textEmbeddings: textSet)

        let result = try await service.detect(imageData: makeImageData(width: 320, height: 240))

        XCTAssertFalse(result.isPet)
        XCTAssertNil(result.species)
        XCTAssertEqual(result.topConfidence, 0.0995, accuracy: 0.01)
    }
    // MARK: - detect 错误映射

    func testDetectThrowsEngineNotLoadedWhenEngineMissing() async {
        let engine = MockInferenceEngine(
            outputs: [makeEmbeddingOutput(oneHot(0))],
            outputInfos: [makeOutputInfo()])
        let service = ClipInferenceService(engine: engine, textEmbeddings: makeTextSet())

        do {
            _ = try await service.detect(imageData: makeImageData(width: 320, height: 240))
            XCTFail("应当抛出 engineNotLoaded")
        } catch let error as ClipInferenceError {
            guard case .engineNotLoaded = error else {
                return XCTFail("期望 engineNotLoaded，实际 \(error)")
            }
        } catch {
            XCTFail("期望 ClipInferenceError，实际 \(error)")
        }
    }

    func testDetectThrowsDecodeFailedOnGarbageData() async throws {
        let engine = try await makeLoadedEngine(
            outputs: [makeEmbeddingOutput(oneHot(0))],
            outputInfos: [makeOutputInfo()])
        let service = ClipInferenceService(engine: engine, textEmbeddings: makeTextSet())

        do {
            _ = try await service.detect(imageData: Data("not an image".utf8))
            XCTFail("应当抛出 decodeFailed")
        } catch let error as ClipInferenceError {
            guard case .decodeFailed = error else {
                return XCTFail("期望 decodeFailed，实际 \(error)")
            }
        } catch {
            XCTFail("期望 ClipInferenceError，实际 \(error)")
        }
    }

    func testDetectThrowsInferenceFailedWhenPredictFails() async {
        let service = ClipInferenceService(
            engine: FailingPredictEngine(), textEmbeddings: makeTextSet())

        do {
            _ = try await service.detect(imageData: makeImageData(width: 320, height: 240))
            XCTFail("应当抛出 inferenceFailed")
        } catch let error as ClipInferenceError {
            guard case .inferenceFailed = error else {
                return XCTFail("期望 inferenceFailed，实际 \(error)")
            }
        } catch {
            XCTFail("期望 ClipInferenceError，实际 \(error)")
        }
    }

    func testDetectThrowsMetadataMismatchWhenCountsDiffer() async throws {
        // outputs 1 个 vs outputInfos 2 个 → selectionFailed(metadataMismatch)。
        let engine = try await makeLoadedEngine(
            outputs: [makeEmbeddingOutput(oneHot(0))],
            outputInfos: [makeOutputInfo(), makeOutputInfo()])
        let service = ClipInferenceService(engine: engine, textEmbeddings: makeTextSet())

        do {
            _ = try await service.detect(imageData: makeImageData(width: 320, height: 240))
            XCTFail("应当抛出 selectionFailed")
        } catch let error as ClipInferenceError {
            guard case .selectionFailed(.metadataMismatch(let outputs, let infos)) = error else {
                return XCTFail("期望 metadataMismatch，实际 \(error)")
            }
            XCTAssertEqual(outputs, 1)
            XCTAssertEqual(infos, 2)
        } catch {
            XCTFail("期望 ClipInferenceError，实际 \(error)")
        }
    }

    func testDetectThrowsNoValidEmbeddingWhenShapeMismatch() async throws {
        // 唯一输出 shape [1, 256]（维度不符）→ 全部跳过 → noValidEmbedding。
        let shortInfo = TensorInfo(name: "image_features", shape: [1, 256], dataType: .float32)
        let shortVector = [Float](repeating: 0.5, count: 256)
        let engine = try await makeLoadedEngine(
            outputs: [ClipInferenceService.floatArrayToData(shortVector)],
            outputInfos: [shortInfo])
        let service = ClipInferenceService(engine: engine, textEmbeddings: makeTextSet())

        do {
            _ = try await service.detect(imageData: makeImageData(width: 320, height: 240))
            XCTFail("应当抛出 selectionFailed")
        } catch let error as ClipInferenceError {
            guard case .selectionFailed(.noValidEmbedding) = error else {
                return XCTFail("期望 noValidEmbedding，实际 \(error)")
            }
        } catch {
            XCTFail("期望 ClipInferenceError，实际 \(error)")
        }
    }
    // MARK: - 手工特征降级 / 工厂

    func testExtractFallbackEmbeddingReturnsNormalizedVector() async throws {
        let engine = MockInferenceEngine()
        let service = ClipInferenceService(engine: engine, textEmbeddings: makeTextSet())

        let embedding = try await service.extractFallbackEmbedding(
            imageData: makeImageData(width: 320, height: 240))

        XCTAssertEqual(embedding.count, ClipConstants.embeddingDim)
        XCTAssertTrue(embedding.allSatisfy { $0.isFinite })
        var sumSq: Float = 0
        for v in embedding { sumSq += v * v }
        XCTAssertEqual(sumSq, 1, accuracy: 0.001)
    }

    func testExtractFallbackEmbeddingThrowsDecodeFailedOnGarbageData() async {
        let service = ClipInferenceService(
            engine: MockInferenceEngine(), textEmbeddings: makeTextSet())

        do {
            _ = try await service.extractFallbackEmbedding(imageData: Data("junk".utf8))
            XCTFail("应当抛出 decodeFailed")
        } catch let error as ClipInferenceError {
            guard case .decodeFailed = error else {
                return XCTFail("期望 decodeFailed，实际 \(error)")
            }
        } catch {
            XCTFail("期望 ClipInferenceError，实际 \(error)")
        }
    }

    func testCreateReturnsNilWhenModelMissing() {
        // app bundle 中不存在该模型 → 工厂返回 nil，调用方降级到 Vision 预筛。
        let service = ClipInferenceService.create(
            modelName: "NoSuchModelForTests", bundle: .main)
        XCTAssertNil(service)
    }
}