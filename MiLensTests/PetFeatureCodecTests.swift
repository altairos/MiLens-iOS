import XCTest
@testable import MiLens

/// PetFeatureCodec 纯逻辑测试——PMF1 blob 编解码（对应源端 PetFeatureCodec 相关用例）。
/// 覆盖 roundtrip、legacy 兼容、非法输入拒绝。
final class PetFeatureCodecTests: XCTestCase {

    private let dim = ClipConstants.embeddingDim // 512

    // MARK: - 编码/解码 roundtrip

    func testEncodeDecodeRoundTripClipWithColorAndSamples() throws {
        let aggregate = randomEmbedding()
        let color = [Float](repeating: 0.5, count: PetMatchThreshold.colorSignatureDim)
        let samples = [randomEmbedding(), randomEmbedding(), randomEmbedding()]

        let blob = try PetFeatureCodec.encode(
            kind: .clip, aggregate: aggregate,
            colorSignature: color, samples: samples)

        // Header 校验：magic + version + kind + flags
        XCTAssertEqual(blob.count, PetFeatureCodec.headerBytes + (dim + 14 + 3 * dim) * 4)
        XCTAssertEqual(readUInt32(blob, offset: 0), PetFeatureCodec.featureMagic)
        XCTAssertEqual(readUInt16(blob, offset: 4), PetFeatureCodec.featureVersion)
        XCTAssertEqual(blob[6], PetFeatureCodec.kindClip)
        XCTAssertEqual(blob[7], PetFeatureCodec.flagColorValid)
        XCTAssertEqual(Int(readUInt16(blob, offset: 8)), dim)
        XCTAssertEqual(Int(readUInt16(blob, offset: 10)), PetMatchThreshold.colorSignatureDim)
        XCTAssertEqual(Int(readUInt16(blob, offset: 12)), 3)

        let decoded = PetFeatureCodec.decode(blob)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.version, 1)
        XCTAssertEqual(decoded?.kind, .clip)
        XCTAssertEqual(decoded?.aggregate, aggregate)
        XCTAssertEqual(decoded?.colorSignature, color)
        XCTAssertEqual(decoded?.samples, samples)
        XCTAssertFalse(decoded?.legacy ?? true)
    }

    func testEncodeDecodeRoundTripFallbackWithoutColor() throws {
        let aggregate = randomEmbedding()
        let blob = try PetFeatureCodec.encode(
            kind: .fallback, aggregate: aggregate,
            colorSignature: nil, samples: [])

        XCTAssertEqual(blob[6], PetFeatureCodec.kindFallback)
        XCTAssertEqual(blob[7], 0) // 无颜色签名 flags
        XCTAssertEqual(Int(readUInt16(blob, offset: 10)), 0)

        let decoded = PetFeatureCodec.decode(blob)
        XCTAssertEqual(decoded?.kind, .fallback)
        XCTAssertNil(decoded?.colorSignature)
        XCTAssertTrue(decoded?.samples.isEmpty ?? false)
        XCTAssertEqual(decoded?.aggregate, aggregate)
    }

    func testEncodeFiltersInvalidSamples() throws {
        // 维度不符的 sample 应被丢弃，不破坏 blob
        let aggregate = randomEmbedding()
        let badSample = [Float](repeating: 1, count: 8)
        let blob = try PetFeatureCodec.encode(
            kind: .clip, aggregate: aggregate,
            colorSignature: nil, samples: [badSample])

        let decoded = PetFeatureCodec.decode(blob)
        XCTAssertEqual(decoded?.samples.count, 0)
    }

    func testEncodeThrowsOnInvalidDimension() {
        XCTAssertThrowsError(try PetFeatureCodec.encode(
            kind: .clip, aggregate: [], colorSignature: nil, samples: []))
    }

    // MARK: - Legacy 兼容（无 magic 的 float32 数组）

    func testDecodeLegacyBlobWithoutMagic() {
        // 旧版直接写 [aggregate(512)]——无 header
        let aggregate = randomEmbedding()
        let blob = floatArrayToData(aggregate)

        let decoded = PetFeatureCodec.decode(blob)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.legacy, true)
        XCTAssertEqual(decoded?.kind, .clip)
        XCTAssertEqual(decoded?.aggregate, aggregate)
        XCTAssertNil(decoded?.colorSignature)
    }

    func testDecodeLegacyBlobWithColorSignature() {
        // 旧版 [aggregate(512) + color(14)]——能识别可用的颜色签名
        let aggregate = randomEmbedding()
        let color = [Float](repeating: 0.25, count: PetMatchThreshold.colorSignatureDim)
        var floats = aggregate
        floats.append(contentsOf: color)
        let blob = floatArrayToData(floats)

        let decoded = PetFeatureCodec.decode(blob)
        XCTAssertEqual(decoded?.colorSignature, color)
        XCTAssertEqual(decoded?.samples.count, 0)
    }

    func testDecodeLegacyBlobWithSamples() {
        // 旧版 [aggregate(512) + sample(512)]——剩余字节按 sample 解析
        let aggregate = randomEmbedding()
        let sample = randomEmbedding()
        var floats = aggregate
        floats.append(contentsOf: sample)
        let blob = floatArrayToData(floats)

        let decoded = PetFeatureCodec.decode(blob)
        XCTAssertEqual(decoded?.samples.count, 1)
        XCTAssertEqual(decoded?.samples[0], sample)
    }

    // MARK: - 非法输入

    func testDecodeEmptyReturnsNil() {
        XCTAssertNil(PetFeatureCodec.decode(Data()))
    }

    func testDecodeGarbageReturnsNil() {
        // 长度不足 512 维的 legacy blob → nil
        let blob = Data([0x00, 0x01, 0x02])
        XCTAssertNil(PetFeatureCodec.decode(blob))
    }

    func testDecodeTruncatedVersionedBlobReturnsNil() {
        // 只有 16 字节 header（无 payload）→ nil（长度不匹配）
        let aggregate = randomEmbedding()
        let blob = try! PetFeatureCodec.encode(
            kind: .clip, aggregate: aggregate, colorSignature: nil, samples: [])
        let truncated = blob.prefix(PetFeatureCodec.headerBytes + 100)
        XCTAssertNil(PetFeatureCodec.decode(Data(truncated)))
    }

    func testDecodeUnknownKindReturnsNil() {
        let aggregate = randomEmbedding()
        var blob = try! PetFeatureCodec.encode(
            kind: .clip, aggregate: aggregate, colorSignature: nil, samples: [])
        blob[6] = 99 // 非法 kind
        XCTAssertNil(PetFeatureCodec.decode(blob))
    }

    // MARK: - isUsableColorSignature

    func testIsUsableColorSignature() {
        XCTAssertTrue(PetFeatureCodec.isUsableColorSignature(
            [Float](repeating: 0.5, count: PetMatchThreshold.colorSignatureDim)))
        XCTAssertFalse(PetFeatureCodec.isUsableColorSignature(nil))
        XCTAssertFalse(PetFeatureCodec.isUsableColorSignature([]))
        // 维度不符
        XCTAssertFalse(PetFeatureCodec.isUsableColorSignature([0.5, 0.5]))
        // 全零（幅值 < 阈值）
        XCTAssertFalse(PetFeatureCodec.isUsableColorSignature(
            [Float](repeating: 0, count: PetMatchThreshold.colorSignatureDim)))
        // NaN
        var nan = [Float](repeating: 0.5, count: PetMatchThreshold.colorSignatureDim)
        nan[0] = .nan
        XCTAssertFalse(PetFeatureCodec.isUsableColorSignature(nan))
    }

    // MARK: - 辅助

    private func randomEmbedding() -> [Float] {
        var values = [Float]()
        for _ in 0..<dim { values.append(Float.random(in: -1...1)) }
        var normalized = values
        AiInferenceLogic.l2Normalize(&normalized)
        return normalized
    }

    private func floatArrayToData(_ floats: [Float]) -> Data {
        var data = Data()
        for value in floats {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }

    private func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[data.startIndex + offset]) | (UInt16(data[data.startIndex + offset + 1]) << 8)
    }

    private func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[data.startIndex + offset])
            | (UInt32(data[data.startIndex + offset + 1]) << 8)
            | (UInt32(data[data.startIndex + offset + 2]) << 16)
            | (UInt32(data[data.startIndex + offset + 3]) << 24)
    }
}
