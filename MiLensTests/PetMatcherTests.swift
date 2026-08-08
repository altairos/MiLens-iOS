import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import MiLens

/// PetMatcher 服务测试（对应源端 PetMatcher 相关用例）。
/// 覆盖特征注册（成功/降级/无图）、自动归属匹配（命中/未命中/kind 隔离/颜色拒绝/margin）。
/// 使用内存宠物仓储 + MockClipInference + 合成 PNG 图片。
@MainActor
final class PetMatcherTests: XCTestCase {

    private func makeMatcher(
        petRepo: InMemoryPetRepository,
        clip: MockClipInference
    ) -> PetMatcher {
        // 串行执行器：保证提取顺序与进度回调确定性
        PetMatcher(petRepo: petRepo, clipService: clip, executor: AnalysisExecutor(maxConcurrent: 1))
    }

    // MARK: - 特征注册

    func testRegisterPetFeaturesWritesFeatureData() async throws {
        let petRepo = InMemoryPetRepository()
        let pet = Pet(name: "小橘")
        try petRepo.insertPet(pet)
        let clip = MockClipInference()
        let matcher = makeMatcher(petRepo: petRepo, clip: clip)

        let images = (0..<8).map { _ in makeSolidPNG(width: 64, height: 64, r: 255, g: 120, b: 60) }
        let ok = await matcher.registerPetFeatures(petID: pet.id, imageDatas: images)

        XCTAssertTrue(ok)
        let stored = try petRepo.getPet(id: pet.id)
        XCTAssertNotNil(stored?.featureData, "注册成功应写入 featureData")
        let feature = PetFeatureCodec.decode(stored!.featureData!)
        XCTAssertEqual(feature?.kind, .clip)
        XCTAssertEqual(feature?.aggregate.count, ClipConstants.embeddingDim)
        XCTAssertEqual(feature?.colorSignature?.count, PetMatchThreshold.colorSignatureDim)
        // 8 张图全部有效 → 样本数 8
        XCTAssertEqual(feature?.samples.count, 8)
    }

    func testRegisterPetFeaturesReportsProgress() async throws {
        let petRepo = InMemoryPetRepository()
        let pet = Pet(name: "小橘")
        try petRepo.insertPet(pet)
        let matcher = makeMatcher(petRepo: petRepo, clip: MockClipInference())

        var progress: [Int] = []
        let images = (0..<8).map { _ in makeSolidPNG(width: 64, height: 64, r: 10, g: 200, b: 30) }
        _ = await matcher.registerPetFeatures(petID: pet.id, imageDatas: images) { p in
            progress.append(p)
        }
        XCTAssertEqual(progress, [1, 2, 3, 4, 5, 6, 7, 8])
    }

    func testRegisterPetFeaturesFailsWithoutImages() async throws {
        let petRepo = InMemoryPetRepository()
        let pet = Pet(name: "小橘")
        try petRepo.insertPet(pet)
        let matcher = makeMatcher(petRepo: petRepo, clip: MockClipInference())

        let ok = await matcher.registerPetFeatures(petID: pet.id, imageDatas: [])
        XCTAssertFalse(ok)
        XCTAssertNil(try petRepo.getPet(id: pet.id)?.featureData)
    }

    func testRegisterPetFeaturesFallsBackWhenClipFails() async throws {
        let petRepo = InMemoryPetRepository()
        let pet = Pet(name: "小橘")
        try petRepo.insertPet(pet)
        let fallback = MockClipInference.randomEmbedding()
        let clip = MockClipInference(fallbackEmbedding: fallback, detectError: MockClipError.inferenceFailed)
        let matcher = makeMatcher(petRepo: petRepo, clip: clip)

        let images = (0..<8).map { _ in makeSolidPNG(width: 64, height: 64, r: 200, g: 100, b: 200) }
        let ok = await matcher.registerPetFeatures(petID: pet.id, imageDatas: images)

        XCTAssertTrue(ok)
        let feature = try petRepo.getPet(id: pet.id).flatMap { $0.featureData }
            .flatMap { PetFeatureCodec.decode($0) }
        XCTAssertEqual(feature?.kind, .fallback, "CLIP 全部失败时应降级为手工特征")
        // averageEmbeddings 求和存在 ~1e-8 级 Float 舍入，逐元素精度比较
        XCTAssertEqual(feature?.aggregate.count, fallback.count)
        if let aggregate = feature?.aggregate {
            for (i, value) in aggregate.enumerated() {
                XCTAssertEqual(value, fallback[i], accuracy: 1e-6)
            }
        }
    }

    // MARK: - 自动归属匹配

    func testMatchFromEmbeddingMatchesRegisteredPet() async throws {
        let (matcher, pet, clipEmbedding) = try await makeRegisteredPet()
        // 用与注册聚合完全一致的 embedding 匹配 → 必然命中
        let result = await matcher.matchFromEmbedding(embedding: clipEmbedding)
        XCTAssertEqual(result?.petID, pet.id)
        XCTAssertGreaterThanOrEqual(result?.score ?? 0, PetMatchThreshold.strict)
    }

    func testMatchFromEmbeddingReturnsNilWhenNoMatch() async throws {
        let (matcher, _, _) = try await makeRegisteredPet()
        let unrelated = MockClipInference.randomEmbedding()
        let result = await matcher.matchFromEmbedding(embedding: unrelated)
        XCTAssertNil(result, "无关 embedding 不应命中")
    }

    func testMatchFromEmbeddingRejectsDifferentKind() async throws {
        let (matcher, _, clipEmbedding) = try await makeRegisteredPet()
        // 已注册 clip 特征；用 fallback 特征空间的 embedding 匹配 → kind 隔离不比较
        let result = await matcher.matchFromEmbedding(
            embedding: clipEmbedding, kind: .fallback)
        XCTAssertNil(result, "不同特征空间的 embedding 不应互相比较")
    }

    func testMatchFromEmbeddingRejectsColorMismatch() async throws {
        let (matcher, _, clipEmbedding) = try await makeRegisteredPet()
        // 注册特征来自红色系图片；匹配用蓝色签名 → 颜色距离超限拒绝
        let blueSignature = ColorSignatureMath.computeColorSignature(
            pixelBytes: makePixels(width: 64, height: 64, r: 0, g: 0, b: 255),
            width: 64, height: 64, dim: PetMatchThreshold.colorSignatureDim)
        let result = await matcher.matchFromEmbedding(
            embedding: clipEmbedding, colorSignature: blueSignature)
        XCTAssertNil(result, "颜色签名冲突时应拒绝匹配")
    }

    func testMatchFromEmbeddingAcceptsMatchingColor() async throws {
        let (matcher, pet, clipEmbedding) = try await makeRegisteredPet()
        // 注册特征来自红色系图片；匹配用同色签名 → 颜色约束通过
        let redSignature = ColorSignatureMath.computeColorSignature(
            pixelBytes: makePixels(width: 64, height: 64, r: 255, g: 80, b: 40),
            width: 64, height: 64, dim: PetMatchThreshold.colorSignatureDim)
        let result = await matcher.matchFromEmbedding(
            embedding: clipEmbedding, colorSignature: redSignature)
        XCTAssertEqual(result?.petID, pet.id)
    }

    func testMatchFromEmbeddingRequiresMarginBetweenPets() async throws {
        let petRepo = InMemoryPetRepository()
        let petA = Pet(name: "A")
        let petB = Pet(name: "B")
        try petRepo.insertPet(petA)
        try petRepo.insertPet(petB)

        // 两只宠物特征接近（A 与 B 的差异很小：仅在第 0 维偏移 0.02）
        let embeddingA = MockClipInference.randomEmbedding()
        var shifted = embeddingA
        shifted[0] += 0.02
        let embeddingB = AiInferenceLogic.normalized(shifted)
        let images = (0..<8).map { _ in makeSolidPNG(width: 64, height: 64, r: 120, g: 120, b: 120) }

        // A 用 embeddingA 注册，B 用 embeddingB 注册（必须显式传入，否则默认随机 embedding 与 A 无关）
        let matcher = makeMatcher(petRepo: petRepo, clip: MockClipInference(embedding: embeddingA))
        _ = await matcher.registerPetFeatures(petID: petA.id, imageDatas: images, onProgress: nil)
        let matcherB = makeMatcher(petRepo: petRepo, clip: MockClipInference(embedding: embeddingB))
        _ = await matcherB.registerPetFeatures(petID: petB.id, imageDatas: images, onProgress: nil)

        // 匹配向量与 A、B 都接近（cosine 几乎相同）→ margin 不足 → 拒绝
        let midpoint = AiInferenceLogic.normalized(
            zip(embeddingA, embeddingB).map { ($0 + $1) / 2 })
        let result = await matcher.matchFromEmbedding(embedding: midpoint)
        XCTAssertNil(result, "top1/top2 分数差距不足时应拒绝（避免误归属）")
    }

    func testMatchFromEmbeddingSkipsPetsWithoutFeatureData() async throws {
        let petRepo = InMemoryPetRepository()
        let petA = Pet(name: "A")          // 未注册特征
        let petB = Pet(name: "B")
        try petRepo.insertPet(petA)
        try petRepo.insertPet(petB)

        let embedding = MockClipInference.randomEmbedding()
        let matcher = makeMatcher(petRepo: petRepo, clip: MockClipInference(embedding: embedding))
        let images = (0..<8).map { _ in makeSolidPNG(width: 64, height: 64, r: 30, g: 200, b: 90) }
        _ = await matcher.registerPetFeatures(petID: petB.id, imageDatas: images)

        let result = await matcher.matchFromEmbedding(embedding: embedding)
        XCTAssertEqual(result?.petID, petB.id, "未注册特征的宠物应被跳过")
    }

    func testMatchFromEmbeddingFallbackThreshold() async throws {
        let petRepo = InMemoryPetRepository()
        let pet = Pet(name: "小灰")
        try petRepo.insertPet(pet)
        let fallback = MockClipInference.randomEmbedding()
        let matcher = makeMatcher(
            petRepo: petRepo,
            clip: MockClipInference(fallbackEmbedding: fallback, detectError: MockClipError.inferenceFailed))

        let images = (0..<8).map { _ in makeSolidPNG(width: 64, height: 64, r: 100, g: 100, b: 100) }
        _ = await matcher.registerPetFeatures(petID: pet.id, imageDatas: images)

        // fallback 特征用放宽阈值（0.85，与 ScanControlMath.resolveMatchThreshold 一致）
        let result = await matcher.matchFromEmbedding(
            embedding: fallback, threshold: 0.85, kind: .fallback)
        XCTAssertEqual(result?.petID, pet.id)
    }

    // MARK: - 颜色签名提取

    func testExtractMatchColorSignatureReturns14Dim() async {
        let matcher = makeMatcher(petRepo: InMemoryPetRepository(), clip: MockClipInference())
        let image = makeSolidPNG(width: 96, height: 96, r: 10, g: 180, b: 250)
        let signature = await matcher.extractMatchColorSignature(imageData: image)
        XCTAssertEqual(signature?.count, PetMatchThreshold.colorSignatureDim)
    }

    func testExtractMatchColorSignatureFailsOnGarbageData() async {
        let matcher = makeMatcher(petRepo: InMemoryPetRepository(), clip: MockClipInference())
        let signature = await matcher.extractMatchColorSignature(imageData: Data([0x00, 0x01, 0x02]))
        XCTAssertNil(signature, "无法解码的数据应返回 nil")
    }

    // MARK: - 辅助

    /// 注册一只红色系宠物（clip 特征），返回 (matcher, pet, 注册用 embedding)。
    private func makeRegisteredPet() async throws -> (PetMatcher, Pet, [Float]) {
        let petRepo = InMemoryPetRepository()
        let pet = Pet(name: "小橘")
        try petRepo.insertPet(pet)
        let clip = MockClipInference()
        let matcher = makeMatcher(petRepo: petRepo, clip: clip)
        let images = (0..<8).map { _ in makeSolidPNG(width: 64, height: 64, r: 255, g: 80, b: 40) }
        let ok = await matcher.registerPetFeatures(petID: pet.id, imageDatas: images)
        XCTAssertTrue(ok)
        return (matcher, pet, clip.embedding)
    }

    /// 生成纯色 PNG 图片数据（供 decodeToRGBA 解码）。
    private func makeSolidPNG(width: Int, height: Int, r: Int, g: Int, b: Int) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(
            red: CGFloat(r) / 255, green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// 生成纯色 RGBA 像素缓冲区（computeColorSignature 直接输入）。
    private func makePixels(width: Int, height: Int, r: Int, g: Int, b: Int) -> [UInt8] {
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        for _ in 0..<(width * height) {
            pixels.append(UInt8(r))
            pixels.append(UInt8(g))
            pixels.append(UInt8(b))
            pixels.append(255)
        }
        return pixels
    }
}

/// CLIP mock：可预设 embedding / fallback / 错误（@MainActor，与 ScanServiceTests 一致）。
/// internal——供 ImportServiceTests 自动归属用例复用。
@MainActor
final class MockClipInference: ClipInference {
    let embedding: [Float]
    private let fallbackEmbedding: [Float]
    private let detectError: Error?
    private(set) var detectCallCount = 0

    init(embedding: [Float]? = nil,
         fallbackEmbedding: [Float]? = nil,
         detectError: Error? = nil) {
        self.embedding = embedding ?? Self.randomEmbedding()
        self.fallbackEmbedding = fallbackEmbedding ?? Self.randomEmbedding()
        self.detectError = detectError
    }

    func detect(imageData: Data) async throws -> ClipDetectionResult {
        detectCallCount += 1
        if let detectError { throw detectError }
        return ClipDetectionResult(
            isPet: true, labels: [], species: "cat", embedding: embedding,
            topLabel: "cat", topConfidence: 0.9, usedClipModel: true, diagnostics: "")
    }

    func extractFallbackEmbedding(imageData: Data) async throws -> [Float] {
        fallbackEmbedding
    }

    static func randomEmbedding() -> [Float] {
        var values = [Float]()
        for _ in 0..<ClipConstants.embeddingDim {
            values.append(Float.random(in: -1...1))
        }
        return AiInferenceLogic.normalized(values)
    }
}

private enum MockClipError: Error {
    case inferenceFailed
}

