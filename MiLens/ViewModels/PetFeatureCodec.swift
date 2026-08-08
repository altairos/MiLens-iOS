//  PetFeatureCodec —— 宠物视觉特征 blob 二进制编解码（对应源端 services/PetFeatureCodec.ets）。
//
//  格式（PMF1，与源端完全一致，保证跨端 blob 可互读）：
//  - Header 16 字节（little-endian）：magic u32（0x31464D50 = "PMF1"）、
//    version u16、kind u8（1=clip / 2=fallback）、flags u8（bit0=颜色签名有效）、
//    embeddingDim u16、colorDim u16、sampleCount u16、reserved u16
//  - Payload：float32 小端序 [aggregate(embeddingDim) + color(colorDim) + samples(sampleCount × embeddingDim)]
//
//  decode 兼容无 magic 的 legacy blob（源端旧版直接写 float32 数组）。
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 SwiftUI 依赖。

import Foundation

/// 特征 embedding 类型（对应源端 PetEmbeddingKind）。
enum PetEmbeddingKind: String, Equatable, Sendable {
    case clip
    case fallback
}

/// 解码后的特征记录（对应源端 PetFeatureRecord）。
struct PetFeatureRecord: Equatable, Sendable {
    var version: Int
    var kind: PetEmbeddingKind
    var aggregate: [Float]
    var colorSignature: [Float]?
    var samples: [[Float]]
    var legacy: Bool
}

enum PetFeatureCodec {

    static let featureMagic: UInt32 = 0x31464D50
    static let featureVersion: UInt16 = 1
    static let headerBytes = 16
    static let kindClip: UInt8 = 1
    static let kindFallback: UInt8 = 2
    static let flagColorValid: UInt8 = 1

    // MARK: - 编码

    /// 编码特征 blob（对应源端 encodePetFeatureBlob）。
    /// - Throws: embeddingDim 非法时抛出（0 或 > 65535）。
    static func encode(
        kind: PetEmbeddingKind,
        aggregate: [Float],
        colorSignature: [Float]?,
        samples: [[Float]]
    ) throws -> Data {
        let embeddingDim = aggregate.count
        guard embeddingDim > 0, embeddingDim <= 65535 else {
            throw PetFeatureCodecError.invalidDimension
        }
        let colorValid = isUsableColorSignature(colorSignature)
        let colorDim = colorValid ? colorSignature?.count ?? 0 : 0
        var validSamples: [[Float]] = []
        for sample in samples where sample.count == embeddingDim && validSamples.count < 65535 {
            validSamples.append(sample)
        }

        // Payload：aggregate + color + samples（float32 LE）
        let floatCount = embeddingDim + colorDim + validSamples.count * embeddingDim
        var payload = Data(capacity: floatCount * 4)
        payload.append(contentsOf: floatArrayToBytes(aggregate))
        if colorValid, let colorSignature {
            payload.append(contentsOf: floatArrayToBytes(colorSignature))
        }
        for sample in validSamples {
            payload.append(contentsOf: floatArrayToBytes(sample))
        }

        // Header（16 字节，little-endian）
        var header = Data(capacity: headerBytes)
        header.append(contentsOf: withUnsafeBytes(of: featureMagic.littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: featureVersion.littleEndian) { Data($0) })
        header.append(kind == .fallback ? kindFallback : kindClip)
        header.append(colorValid ? flagColorValid : 0)
        header.append(contentsOf: withUnsafeBytes(of: UInt16(embeddingDim).littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(colorDim).littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(validSamples.count).littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian) { Data($0) })

        var blob = Data(capacity: headerBytes + payload.count)
        blob.append(header)
        blob.append(payload)
        return blob
    }

    // MARK: - 解码

    /// 解码特征 blob；格式非法返回 nil（对应源端 decodePetFeatureBlob）。
    static func decode(_ blob: Data) -> PetFeatureRecord? {
        guard !blob.isEmpty else { return nil }
        if blob.count >= headerBytes {
            let magic = readUInt32LE(blob, offset: 0)
            if magic == featureMagic { return decodeVersionedBlob(blob) }
        }
        return decodeLegacyBlob(blob)
    }

    /// 校验颜色签名是否可用（长度匹配 + 全有限 + 幅值 > 阈值）。
    static func isUsableColorSignature(_ value: [Float]?) -> Bool {
        guard let value, value.count == PetMatchThreshold.colorSignatureDim else { return false }
        var magnitude: Float = 0
        for component in value {
            if !component.isFinite { return false }
            magnitude += abs(component)
        }
        return magnitude > 0.000001
    }

    // MARK: - 私有

    private static func decodeVersionedBlob(_ blob: Data) -> PetFeatureRecord? {
        guard blob.count >= headerBytes else { return nil }
        let version = readUInt16LE(blob, offset: 4)
        guard version == featureVersion else { return nil }
        guard let kind = embeddingKind(from: blob[blob.startIndex + 6]) else { return nil }
        let flags = blob[blob.startIndex + 7]
        let embeddingDim = Int(readUInt16LE(blob, offset: 8))
        let colorDim = Int(readUInt16LE(blob, offset: 10))
        let sampleCount = Int(readUInt16LE(blob, offset: 12))
        let colorValid = (flags & flagColorValid) != 0
        guard embeddingDim > 0 else { return nil }
        guard (colorValid && colorDim == PetMatchThreshold.colorSignatureDim) || (!colorValid && colorDim == 0) else {
            return nil
        }
        let floatCount = embeddingDim + colorDim + sampleCount * embeddingDim
        guard blob.count == headerBytes + floatCount * 4 else { return nil }

        let floats = bytesToFloatArray(blob.subdata(in: headerBytes..<blob.count))
        let aggregate = Array(floats[0..<embeddingDim])
        let colorSignature: [Float]? = colorValid
            ? Array(floats[embeddingDim..<(embeddingDim + colorDim)])
            : nil
        var samples: [[Float]] = []
        let sampleOffset = embeddingDim + colorDim
        for i in 0..<sampleCount {
            let start = sampleOffset + i * embeddingDim
            samples.append(Array(floats[start..<(start + embeddingDim)]))
        }
        return PetFeatureRecord(
            version: Int(version), kind: kind,
            aggregate: aggregate, colorSignature: colorSignature,
            samples: samples, legacy: false)
    }

    private static func decodeLegacyBlob(_ blob: Data) -> PetFeatureRecord? {
        guard blob.count % 4 == 0 else { return nil }
        let floats = bytesToFloatArray(blob)
        let embeddingDim = ClipConstants.embeddingDim
        guard floats.count >= embeddingDim else { return nil }
        let aggregate = Array(floats[0..<embeddingDim])
        var colorSignature: [Float]? = nil
        var sampleOffset = embeddingDim
        if floats.count >= embeddingDim + PetMatchThreshold.colorSignatureDim {
            let candidate = Array(floats[embeddingDim..<(embeddingDim + PetMatchThreshold.colorSignatureDim)])
            colorSignature = isUsableColorSignature(candidate) ? candidate : nil
            sampleOffset += PetMatchThreshold.colorSignatureDim
        }
        let availableSamples = max(0, (floats.count - sampleOffset) / embeddingDim)
        var samples: [[Float]] = []
        for i in 0..<availableSamples {
            let start = sampleOffset + i * embeddingDim
            samples.append(Array(floats[start..<(start + embeddingDim)]))
        }
        return PetFeatureRecord(
            version: 0, kind: .clip,
            aggregate: aggregate, colorSignature: colorSignature,
            samples: samples, legacy: true)
    }

    private static func embeddingKind(from code: UInt8) -> PetEmbeddingKind? {
        if code == kindClip { return .clip }
        if code == kindFallback { return .fallback }
        return nil
    }

    // MARK: - 字节读写

    private static func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        data.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: UInt8.self).baseAddress! + offset
            return UInt32(base[0]) | (UInt32(base[1]) << 8) | (UInt32(base[2]) << 16) | (UInt32(base[3]) << 24)
        }
    }

    private static func readUInt16LE(_ data: Data, offset: Int) -> UInt16 {
        data.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: UInt8.self).baseAddress! + offset
            return UInt16(base[0]) | (UInt16(base[1]) << 8)
        }
    }

    private static func floatArrayToBytes(_ floats: [Float]) -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(floats.count * 4)
        for value in floats {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { bytes.append(contentsOf: $0) }
        }
        return bytes
    }

    private static func bytesToFloatArray(_ data: Data) -> [Float] {
        var floats = [Float]()
        let count = data.count / 4
        floats.reserveCapacity(count)
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for i in 0..<count {
                let offset = i * 4
                let bits = UInt32(base[offset])
                    | (UInt32(base[offset + 1]) << 8)
                    | (UInt32(base[offset + 2]) << 16)
                    | (UInt32(base[offset + 3]) << 24)
                floats.append(Float(bitPattern: bits))
            }
        }
        return floats
    }
}

/// 特征编码错误。
enum PetFeatureCodecError: Error {
    case invalidDimension
}
