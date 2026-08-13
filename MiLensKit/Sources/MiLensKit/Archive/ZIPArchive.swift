//  ZIPArchive —— 纯 Swift ZIP 归档（store 模式，无第三方依赖）。
//
//  用途：离线备份服务（ADR-0010 §8）将照片 + 元数据打包为 .milensbackup。
//  决策不引入 ZIPFoundation 等三方库，保持项目完整 Swift 重写原则；
//  store 模式（method=0，不压缩）对已压缩的 JPEG 几乎无体积惩罚且实现极简，
//  产出的 .milensbackup 是合法 ZIP，macOS Archive Utility / iOS Files 均可解压。
//
//  格式遵循 PKWARE APPNOTE 6.3.x：local file header + data + central directory +
//  end of central directory record。文件名以 UTF-8 编码并置 flag bit 11（0x0800）。
//  CRC32 使用 IEEE 802.3 反射多项式 0xEDB88320，与 zlib/InfoZIP 兼容。
//  Reader 从 central directory 读取权威 size/crc（兼容 data descriptor 写法），
//  仅支持 store；遇到压缩条目抛 unsupportedCompression（本项目不产出，也不消费外部压缩包）。

import Foundation

// MARK: - 条目与错误

/// ZIP 归档中的一个条目（文件路径 + 原始数据，store 模式不压缩）。
public struct ZipEntry: Sendable, Equatable {
    /// 归档内相对路径（正斜杠分隔，如 `manifest.json`、`photos/{uuid}.jpg`）。
    public let path: String
    /// 文件原始数据。
    public let data: Data

    public init(path: String, data: Data) {
        self.path = path
        self.data = data
    }
}

/// ZIP 归档读写错误。
public enum ZipArchiveError: Error, Equatable, Sendable {
    /// 数据过短，不是有效 ZIP。
    case truncated
    /// 找不到 End Of Central Directory 记录。
    case endOfCentralDirectoryNotFound
    /// central / local file header 签名不匹配。
    case invalidSignature
    /// 仅支持 store（method 0），遇到压缩条目。
    case unsupportedCompression(method: UInt16)
    /// 读取偏移超出数据边界（文件损坏）。
    case offsetOutOfBounds
    /// 解压数据 CRC 与 central directory 记录不符（文件损坏/被篡改）。
    case crcMismatch(expected: UInt32, actual: UInt32)
    /// 条目数超过上限（防御性限制，避免大备份 OOM）。
    case entryCountExceeded(max: Int)
    /// 解压后总大小超过上限（防御性限制，避免大备份 OOM）。
    case totalSizeExceeded(max: Int)
    /// 单个条目解压后大小超过上限（防御性限制，避免大文件 OOM）。
    case singleEntrySizeExceeded(max: Int)
}

// MARK: - Writer

/// ZIP 归档写入器（store 模式）。
public enum ZipWriter {

    /// 将条目打包为 ZIP 数据。
    /// - Parameters:
    ///   - entries: 条目列表（顺序保留）。
    ///   - modificationDate: 所有条目统一使用的修改时间（默认当前时间）。
    /// - Returns: 完整的 ZIP 文件数据。
    public static func archive(entries: [ZipEntry], modificationDate: Date = Date()) -> Data {
        var out = Data()
        let dosTime = DOSTime.modification(for: modificationDate)
        // 记录每个条目的 CRC + local header 偏移，供 central directory 使用
        var localOffsets: [Int] = []
        var crcs: [UInt32] = []

        for entry in entries {
            let nameBytes = Array(entry.path.utf8)
            let crc = CRC32.compute(entry.data)
            crcs.append(crc)
            localOffsets.append(out.count)

            // Local file header（30 字节固定 + 文件名）
            out.appendLE(Self.localFileHeaderSignature)
            out.appendLE(UInt16(20))                 // version needed to extract: 2.0
            out.appendLE(UInt16(0x0800))              // flags: bit 11 = UTF-8 文件名
            out.appendLE(UInt16(0))                   // method: store
            out.appendLE(dosTime.time)
            out.appendLE(dosTime.date)
            out.appendLE(crc)
            out.appendLE(UInt32(entry.data.count))    // compressed size = uncompressed (store)
            out.appendLE(UInt32(entry.data.count))    // uncompressed size
            out.appendLE(UInt16(nameBytes.count))     // file name length
            out.appendLE(UInt16(0))                   // extra field length
            out.append(contentsOf: nameBytes)
            // 数据（store：原样追加）
            out.append(entry.data)
        }

        // Central directory
        let cdStart = out.count
        for (index, entry) in entries.enumerated() {
            let nameBytes = Array(entry.path.utf8)
            out.appendLE(Self.centralDirectoryHeaderSignature)
            out.appendLE(UInt16(20))                 // version made by
            out.appendLE(UInt16(20))                 // version needed
            out.appendLE(UInt16(0x0800))             // flags: UTF-8 文件名
            out.appendLE(UInt16(0))                  // method: store
            out.appendLE(dosTime.time)
            out.appendLE(dosTime.date)
            out.appendLE(crcs[index])
            out.appendLE(UInt32(entry.data.count))   // compressed size
            out.appendLE(UInt32(entry.data.count))   // uncompressed size
            out.appendLE(UInt16(nameBytes.count))    // file name length
            out.appendLE(UInt16(0))                  // extra field length
            out.appendLE(UInt16(0))                  // comment length
            out.appendLE(UInt16(0))                  // disk number start
            out.appendLE(UInt16(0))                  // internal file attributes
            out.appendLE(UInt32(0))                  // external file attributes
            out.appendLE(UInt32(localOffsets[index]))// relative offset of local header
            out.append(contentsOf: nameBytes)
        }
        let cdSize = out.count - cdStart

        // End of central directory record（22 字节）
        out.appendLE(Self.endOfCentralDirectorySignature)
        out.appendLE(UInt16(0))                       // number of this disk
        out.appendLE(UInt16(0))                       // disk where CD starts
        out.appendLE(UInt16(entries.count))           // entries on this disk
        out.appendLE(UInt16(entries.count))           // total entries
        out.appendLE(UInt32(cdSize))                  // size of central directory
        out.appendLE(UInt32(cdStart))                 // offset of start of CD
        out.appendLE(UInt16(0))                       // comment length

        return out
    }

    private static let localFileHeaderSignature: UInt32 = 0x04034b50
    private static let centralDirectoryHeaderSignature: UInt32 = 0x02014b50
    private static let endOfCentralDirectorySignature: UInt32 = 0x06054b50
}

// MARK: - Reader

/// ZIP 归档读取器（仅支持 store）。
public enum ZipReader {

    /// 从 ZIP 数据解包全部条目。
    /// - Parameter data: 完整 ZIP 文件数据。
    /// - Returns: 条目列表（按 central directory 顺序）。
    /// - Note: 从 central directory 读取权威 size/crc，再跳转到 local header 定位数据；
    ///   仅消费 store 条目（method 0）。
    public static func extract(_ data: Data) throws -> [ZipEntry] {
        guard data.count >= 22 else { throw ZipArchiveError.truncated }

        let eocdOffset = try findEndOfCentralDirectory(in: data)
        // EOCD 布局：+8 entries on disk(UInt16)、+10 total entries(UInt16)、
        // +12 size of CD(UInt32)、+16 offset of CD(UInt32)。
        let totalEntries = Int(data.readUInt16LE(at: eocdOffset + 10))
        let cdOffset = Int(data.readUInt32LE(at: eocdOffset + 16))

        var entries: [ZipEntry] = []
        entries.reserveCapacity(totalEntries)

        var cursor = cdOffset
        for _ in 0..<totalEntries {
            guard cursor + 46 <= data.count else { throw ZipArchiveError.offsetOutOfBounds }
            let signature = data.readUInt32LE(at: cursor)
            guard signature == 0x02014b50 else { throw ZipArchiveError.invalidSignature }

            let method = data.readUInt16LE(at: cursor + 10)
            guard method == 0 else { throw ZipArchiveError.unsupportedCompression(method: method) }

            // central directory 记录的权威 CRC-32（+16 偏移）。
            let expectedCRC = data.readUInt32LE(at: cursor + 16)
            let uncompSize = Int(data.readUInt32LE(at: cursor + 24))
            let nameLen = Int(data.readUInt16LE(at: cursor + 28))
            let extraLen = Int(data.readUInt16LE(at: cursor + 30))
            let commentLen = Int(data.readUInt16LE(at: cursor + 32))
            let localOffset = Int(data.readUInt32LE(at: cursor + 42))

            let nameStart = cursor + 46
            guard nameStart + nameLen <= data.count else { throw ZipArchiveError.offsetOutOfBounds }
            let name = String(decoding: data.subdata(in: nameStart..<(nameStart + nameLen)), as: UTF8.self)

            // 推进到下一个 CD 条目
            cursor = nameStart + nameLen + extraLen + commentLen

            // 跳转到 local header 计算数据起点（local header 的 extra 可能与 CD 不同）
            guard localOffset + 30 <= data.count else { throw ZipArchiveError.offsetOutOfBounds }
            let localSig = data.readUInt32LE(at: localOffset)
            guard localSig == 0x04034b50 else { throw ZipArchiveError.invalidSignature }
            let localNameLen = Int(data.readUInt16LE(at: localOffset + 26))
            let localExtraLen = Int(data.readUInt16LE(at: localOffset + 28))
            let dataStart = localOffset + 30 + localNameLen + localExtraLen
            guard dataStart + uncompSize <= data.count else { throw ZipArchiveError.offsetOutOfBounds }

            let entryData = data.subdata(in: dataStart..<(dataStart + uncompSize))
            // 完整性校验：解压数据 CRC 必须与 central directory 记录一致，
            // 否则文件损坏或被篡改——拒绝静默吞下错误数据。
            let actualCRC = CRC32.compute(entryData)
            guard actualCRC == expectedCRC else {
                throw ZipArchiveError.crcMismatch(expected: expectedCRC, actual: actualCRC)
            }
            entries.append(ZipEntry(path: name, data: entryData))
        }

        return entries
    }

    /// 预校验 ZIP 归档大小，不解出数据。
    ///
    /// 只读 central directory 统计条目数与各条目解压后大小，提前拒绝超限归档，
    /// 避免一次性解出全部条目造成内存峰值甚至 OOM。
    ///
    /// - Parameters:
    ///   - data: 完整 ZIP 文件数据。
    ///   - maxTotalUncompressedSize: 全部条目解压后总字节数上限。
    ///   - maxEntryCount: 条目数上限。
    ///   - maxSingleEntrySize: 单个条目解压后字节数上限。
    public static func validateSizes(
        in data: Data,
        maxTotalUncompressedSize: Int,
        maxEntryCount: Int,
        maxSingleEntrySize: Int
    ) throws {
        guard data.count >= 22 else { throw ZipArchiveError.truncated }
        let eocdOffset = try findEndOfCentralDirectory(in: data)
        let totalEntries = Int(data.readUInt16LE(at: eocdOffset + 10))
        let cdOffset = Int(data.readUInt32LE(at: eocdOffset + 16))

        guard totalEntries <= maxEntryCount else {
            throw ZipArchiveError.entryCountExceeded(max: maxEntryCount)
        }

        var cursor = cdOffset
        var totalUncompressed = 0
        for _ in 0..<totalEntries {
            guard cursor + 46 <= data.count else { throw ZipArchiveError.offsetOutOfBounds }
            guard data.readUInt32LE(at: cursor) == 0x02014b50 else {
                throw ZipArchiveError.invalidSignature
            }
            let uncompSize = Int(data.readUInt32LE(at: cursor + 24))
            let nameLen = Int(data.readUInt16LE(at: cursor + 28))
            let extraLen = Int(data.readUInt16LE(at: cursor + 30))
            let commentLen = Int(data.readUInt16LE(at: cursor + 32))

            guard uncompSize <= maxSingleEntrySize else {
                throw ZipArchiveError.singleEntrySizeExceeded(max: maxSingleEntrySize)
            }
            totalUncompressed += uncompSize
            guard totalUncompressed <= maxTotalUncompressedSize else {
                throw ZipArchiveError.totalSizeExceeded(max: maxTotalUncompressedSize)
            }
            cursor = cursor + 46 + nameLen + extraLen + commentLen
        }
    }

    /// 从尾部向前扫描 End Of Central Directory 签名（兼容尾部带注释的 ZIP）。
    private static func findEndOfCentralDirectory(in data: Data) throws -> Int {
        // EOCD 最小 22 字节，注释最多 65535。
        let lowerBound = max(0, data.count - 22 - 65535)
        var i = data.count - 22
        while i >= lowerBound {
            if data.readUInt32LE(at: i) == 0x06054b50 {
                return i
            }
            i -= 1
        }
        throw ZipArchiveError.endOfCentralDirectoryNotFound
    }
}

// MARK: - CRC32（IEEE 802.3，反射多项式 0xEDB88320）

enum CRC32 {
    static let table: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for n in 0..<256 {
            var c = UInt32(n)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            table[n] = c
        }
        return table
    }()

    static func compute(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xff)
            crc = (crc >> 8) ^ table[idx]
        }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - DOS 时间编码

struct DOSTime {
    let time: UInt16
    let date: UInt16

    static func modification(for date: Date) -> DOSTime {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        // DOS 日期起始于 1980；更早的日期统一钳制到 1980-01-01。
        let year = max(1980, comps.year ?? 1980)
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let second = (comps.second ?? 0) / 2
        let dateValue = ((year - 1980) << 9) | (month << 5) | day
        let timeValue = (hour << 11) | (minute << 5) | second
        return DOSTime(time: UInt16(timeValue), date: UInt16(dateValue))
    }
}

// MARK: - Little-endian 读写

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }
    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }

    /// 从指定偏移读取小端 UInt16（调用方保证不越界）。
    func readUInt16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
    /// 从指定偏移读取小端 UInt32（调用方保证不越界）。
    func readUInt32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
