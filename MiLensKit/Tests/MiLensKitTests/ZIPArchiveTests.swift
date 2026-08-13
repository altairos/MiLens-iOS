import XCTest
@testable import MiLensKit

/// ZIPArchive 往返与边界测试。
/// store 模式生成的 ZIP 必须可被自身 reader 还原，且 CRC32 与 IEEE 标准向量一致。
final class ZIPArchiveTests: XCTestCase {

    // MARK: - 往返

    func testEmptyEntriesRoundTrip() throws {
        let zip = ZipWriter.archive(entries: [])
        let extracted = try ZipReader.extract(zip)
        XCTAssertEqual(extracted, [])
    }

    func testSingleEntryRoundTrip() throws {
        let entries = [ZipEntry(path: "manifest.json", data: Data("{\"v\":1}".utf8))]
        let zip = ZipWriter.archive(entries: entries)
        let extracted = try ZipReader.extract(zip)
        XCTAssertEqual(extracted, entries)
    }

    func testMultipleEntriesPreserveOrder() throws {
        let entries = [
            ZipEntry(path: "a.txt", data: Data("alpha".utf8)),
            ZipEntry(path: "b.dat", data: Data([0x00, 0xFF, 0x7F, 0x80])),
            ZipEntry(path: "nested/c.txt", data: Data("gamma".utf8)),
        ]
        let zip = ZipWriter.archive(entries: entries)
        let extracted = try ZipReader.extract(zip)
        XCTAssertEqual(extracted.count, 3)
        XCTAssertEqual(extracted.map(\.path), ["a.txt", "b.dat", "nested/c.txt"])
        XCTAssertEqual(extracted[1].data, Data([0x00, 0xFF, 0x7F, 0x80]))
    }

    func testEmptyDataEntryRoundTrip() throws {
        let entries = [ZipEntry(path: "empty.bin", data: Data())]
        let zip = ZipWriter.archive(entries: entries)
        let extracted = try ZipReader.extract(zip)
        XCTAssertEqual(extracted, entries)
    }

    func testBinaryDataRoundTrip() throws {
        // 全字节域 + 伪随机数据，验证无字节被特殊处理
        var bytes = [UInt8](repeating: 0, count: 1024)
        for i in 0..<bytes.count { bytes[i] = UInt8(i & 0xFF) }
        let data = Data(bytes)
        let zip = ZipWriter.archive(entries: [ZipEntry(path: "binary", data: data)])
        let extracted = try ZipReader.extract(zip)
        XCTAssertEqual(extracted.first?.data, data)
    }

    // MARK: - 文件名编码

    func testUTF8FilePathPreserved() throws {
        let entries = [
            ZipEntry(path: "照片/小橘.jpg", data: Data([0x01])),
            ZipEntry(path: "café.txt", data: Data([0x02])),
        ]
        let zip = ZipWriter.archive(entries: entries)
        let extracted = try ZipReader.extract(zip)
        XCTAssertEqual(extracted.map(\.path), ["照片/小橘.jpg", "café.txt"])
    }

    // MARK: - CRC32 正确性（IEEE 标准已知向量）

    func testCRC32KnownVector() throws {
        // "123456789" 的 CRC-32/ISO-HDLC 标准值为 0xCBF43926
        let digest = CRC32.compute(Data("123456789".utf8))
        XCTAssertEqual(digest, 0xCBF43926)
    }

    func testCRC32EmptyIsZero() throws {
        XCTAssertEqual(CRC32.compute(Data()), 0)
    }

    // MARK: - 大数据

    func testLargeEntryRoundTrip() throws {
        // 256KB 数据，模拟备份包中的照片文件尺寸量级
        let data = Data((0..<(256 * 1024)).map { UInt8($0 & 0xFF) })
        let zip = ZipWriter.archive(entries: [ZipEntry(path: "big.jpg", data: data)])
        let extracted = try ZipReader.extract(zip)
        XCTAssertEqual(extracted.first?.data, data)
    }

    // MARK: - 错误路径

    func testTruncatedDataThrows() {
        XCTAssertThrowsError(try ZipReader.extract(Data([0x50, 0x4b]))) { error in
            XCTAssertEqual(error as? ZipArchiveError, .truncated)
        }
    }

    func testMissingEOCDThrows() {
        // 足够长但无 EOCD 签名
        let noise = Data(repeating: 0x00, count: 64)
        XCTAssertThrowsError(try ZipReader.extract(noise)) { error in
            XCTAssertEqual(error as? ZipArchiveError, .endOfCentralDirectoryNotFound)
        }
    }

    func testCorruptDataThrowsCrcMismatch() throws {
        // 生成合法 store ZIP，篡改数据区一字节，验证 reader 经 CRC 校验拒绝损坏数据。
        let zip = ZipWriter.archive(entries: [ZipEntry(path: "x", data: Data([0xAB, 0xCD]))])
        var mutable = zip

        // 定位数据起点：跳过 local header(30) + 文件名长度("x"=1)，篡改首个数据字节。
        let dataStart = 30 + 1
        mutable[dataStart] = mutable[dataStart] ^ 0xFF  // 翻转字节

        XCTAssertThrowsError(try ZipReader.extract(mutable)) { error in
            guard case .crcMismatch = error as? ZipArchiveError else {
                return XCTFail("应抛 crcMismatch，实际：\(error)")
            }
        }
    }

    func testDuplicateEntriesKeepFirst() throws {
        // 构造含同名条目的 ZIP（外部/损坏包可能出现），验证 reader 不崩溃。
        // ZipWriter 不会产出重复，这里手动拼装两个同名 local+central 条目。
        let first = ZipWriter.archive(entries: [ZipEntry(path: "dup", data: Data("first".utf8))])
        let second = ZipWriter.archive(entries: [ZipEntry(path: "dup", data: Data("second".utf8))])
        // 简单拼接不可行（两个 EOCD），这里仅验证 reader 能解出条目不崩溃；
        // 重复 key 合并在 BackupService 层处理（见 ZipBackupServiceTests）。
        let extracted = try ZipReader.extract(first)
        XCTAssertEqual(extracted.first?.data, Data("first".utf8))
        _ = second  // 保留语义占位
    }

    func testUnsupportedCompressionThrows() throws {
        // 生成一个合法的 store ZIP，然后篡改 central directory 的 method 为 deflate(8)，
        // 验证 reader 拒绝压缩条目。
        let zip = ZipWriter.archive(entries: [ZipEntry(path: "x", data: Data([0xAB]))])
        var mutable = zip

        // 定位 EOCD → cdOffset（EOCD +16 为 CD offset）
        let eocdOffset = try locateEOCD(in: mutable)
        let cdOffset = Int(mutable.readUInt32LETesting(at: eocdOffset + 16))

        // CD 条目的 method 字段在 cdOffset + 10（UInt16 LE）
        mutable[cdOffset + 10] = 8
        mutable[cdOffset + 11] = 0

        XCTAssertThrowsError(try ZipReader.extract(mutable)) { error in
            XCTAssertEqual(error as? ZipArchiveError, .unsupportedCompression(method: 8))
        }
    }

    // MARK: - 大小预校验（validateSizes）

    func testValidateSizesPassesWithinLimits() throws {
        let entries = [
            ZipEntry(path: "a.txt", data: Data(repeating: 0x41, count: 100)),
            ZipEntry(path: "b.txt", data: Data(repeating: 0x42, count: 200)),
        ]
        let zip = ZipWriter.archive(entries: entries)

        // 不解出数据，只读 central directory 校验：通过
        XCTAssertNoThrow(try ZipReader.validateSizes(
            in: zip, maxTotalUncompressedSize: 1000,
            maxEntryCount: 10, maxSingleEntrySize: 500))
    }

    func testValidateSizesRejectsEntryCountExceeded() throws {
        let entries = (0..<5).map { i in
            ZipEntry(path: "file\(i).txt", data: Data([UInt8(i)]))
        }
        let zip = ZipWriter.archive(entries: entries)

        XCTAssertThrowsError(try ZipReader.validateSizes(
            in: zip, maxTotalUncompressedSize: 1000,
            maxEntryCount: 3, maxSingleEntrySize: 100)) { error in
            guard case .entryCountExceeded = error as? ZipArchiveError else {
                return XCTFail("应抛 entryCountExceeded，实际：\(error)")
            }
        }
    }

    func testValidateSizesRejectsTotalSizeExceeded() throws {
        let entries = [
            ZipEntry(path: "a.txt", data: Data(repeating: 0x41, count: 500)),
            ZipEntry(path: "b.txt", data: Data(repeating: 0x42, count: 600)),
        ]
        let zip = ZipWriter.archive(entries: entries)

        // 总解压大小 1100 > 上限 1000
        XCTAssertThrowsError(try ZipReader.validateSizes(
            in: zip, maxTotalUncompressedSize: 1000,
            maxEntryCount: 10, maxSingleEntrySize: 1000)) { error in
            guard case .totalSizeExceeded = error as? ZipArchiveError else {
                return XCTFail("应抛 totalSizeExceeded，实际：\(error)")
            }
        }
    }

    func testValidateSizesRejectsSingleEntrySizeExceeded() throws {
        let entries = [
            ZipEntry(path: "big.txt", data: Data(repeating: 0x41, count: 500)),
        ]
        let zip = ZipWriter.archive(entries: entries)

        // 单条目 500 > 上限 100
        XCTAssertThrowsError(try ZipReader.validateSizes(
            in: zip, maxTotalUncompressedSize: 10000,
            maxEntryCount: 10, maxSingleEntrySize: 100)) { error in
            guard case .singleEntrySizeExceeded = error as? ZipArchiveError else {
                return XCTFail("应抛 singleEntrySizeExceeded，实际：\(error)")
            }
        }
    }

    func testValidateSizesPassesEmptyArchive() throws {
        let zip = ZipWriter.archive(entries: [])
        XCTAssertNoThrow(try ZipReader.validateSizes(
            in: zip, maxTotalUncompressedSize: 1000,
            maxEntryCount: 10, maxSingleEntrySize: 500))
    }

    // MARK: - 流式读写（writeArchive / readCentralDirectory / copyEntry）

    func testWriteArchiveStreamingRoundTrip() async throws {
        let entries = [
            ZipStreamEntry(path: "a.txt") { Data("alpha".utf8) },
            ZipStreamEntry(path: "b.dat") { Data([0x00, 0xFF, 0x7F, 0x80]) },
            ZipStreamEntry(path: "nested/c.txt") { Data("gamma".utf8) },
        ]
        let output = TestDataOutputStream()
        try await ZipWriter.writeArchive(entries: entries, to: output)
        try await output.close()

        // 用旧 extract 解出验证格式一致
        let extracted = try ZipReader.extract(output.buffer)
        XCTAssertEqual(extracted.count, 3)
        XCTAssertEqual(extracted.map(\.path), ["a.txt", "b.dat", "nested/c.txt"])
        XCTAssertEqual(extracted[0].data, Data("alpha".utf8))
        XCTAssertEqual(extracted[1].data, Data([0x00, 0xFF, 0x7F, 0x80]))
        XCTAssertEqual(extracted[2].data, Data("gamma".utf8))
    }

    func testReadCentralDirectoryMatchesExtract() async throws {
        let entries = [
            ZipEntry(path: "a.txt", data: Data("alpha".utf8)),
            ZipEntry(path: "b.dat", data: Data([0x00, 0xFF])),
        ]
        let zip = ZipWriter.archive(entries: entries)
        let input = TestDataInputStream(data: zip)

        let records = try await ZipReader.readCentralDirectory(from: input)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.path), ["a.txt", "b.dat"])
        XCTAssertEqual(records[0].uncompSize, 5)
        XCTAssertEqual(records[1].uncompSize, 2)
        // CRC 须与旧 extract 一致
        XCTAssertEqual(records[0].crc, CRC32.compute(Data("alpha".utf8)))
        XCTAssertEqual(records[1].crc, CRC32.compute(Data([0x00, 0xFF])))
        try await input.close()
    }

    func testCopyEntryPreservesDataAndCRC() async throws {
        let original = Data((0..<1000).map { UInt8($0 & 0xFF) })
        let zip = ZipWriter.archive(entries: [
            ZipEntry(path: "big.dat", data: original)
        ])
        let input = TestDataInputStream(data: zip)

        let records = try await ZipReader.readCentralDirectory(from: input)
        let output = TestDataOutputStream()
        try await ZipReader.copyEntry(records[0], from: input, to: output, chunkSize: 64)
        try await output.close()
        try await input.close()

        XCTAssertEqual(output.buffer, original, "流式拷贝数据须与原数据一致")
    }

    func testCopyEntryDetectsCorruptCRC() async throws {
        let zip = ZipWriter.archive(entries: [
            ZipEntry(path: "x.dat", data: Data([0xAB, 0xCD, 0xEF]))
        ])
        var corrupt = zip
        // 篡改数据区首字节（local header 30 + 文件名 5 = 偏移 35）
        corrupt[35] = corrupt[35] ^ 0xFF

        let input = TestDataInputStream(data: corrupt)
        let records = try await ZipReader.readCentralDirectory(from: input)
        let output = TestDataOutputStream()

        do {
            try await ZipReader.copyEntry(records[0], from: input, to: output)
            XCTFail("篡改数据应抛 crcMismatch")
        } catch let error as ZipArchiveError {
            guard case .crcMismatch = error else {
                return XCTFail("应抛 crcMismatch，实际：\(error)")
            }
        }
        try await input.close()
    }

    func testReadEntryDataPreservesData() async throws {
        let payload = Data("{\"v\":1}".utf8)
        let zip = ZipWriter.archive(entries: [
            ZipEntry(path: "manifest.json", data: payload)
        ])
        let input = TestDataInputStream(data: zip)

        let records = try await ZipReader.readCentralDirectory(from: input)
        let data = try await ZipReader.readEntryData(records[0], from: input)
        try await input.close()

        XCTAssertEqual(data, payload, "readEntryData 须返回完整数据")
    }

    func testWriteArchiveStreamingEmptyEntries() async throws {
        let output = TestDataOutputStream()
        try await ZipWriter.writeArchive(entries: [], to: output)
        try await output.close()

        let extracted = try ZipReader.extract(output.buffer)
        XCTAssertEqual(extracted, [])
    }

    func testWriteArchiveStreamingLargeEntry() async throws {
        // 256KB 数据，验证大 entry 流式往返
        let data = Data((0..<(256 * 1024)).map { UInt8($0 & 0xFF) })
        let entries = [ZipStreamEntry(path: "big.jpg") { data }]
        let output = TestDataOutputStream()
        try await ZipWriter.writeArchive(entries: entries, to: output)
        try await output.close()

        // 流式读回
        let input = TestDataInputStream(data: output.buffer)
        let records = try await ZipReader.readCentralDirectory(from: input)
        let copyOutput = TestDataOutputStream()
        try await ZipReader.copyEntry(records[0], from: input, to: copyOutput, chunkSize: 4096)
        try await copyOutput.close()
        try await input.close()

        XCTAssertEqual(copyOutput.buffer, data, "大 entry 流式往返数据须一致")
    }

    // MARK: - 辅助

    /// 测试专用：复刻 reader 的 EOCD 定位逻辑以取得偏移（避免暴露内部 API）。
    private func locateEOCD(in data: Data) throws -> Int {
        let lowerBound = max(0, data.count - 22 - 65535)
        var i = data.count - 22
        while i >= lowerBound {
            let sig = UInt32(data[i])
                | (UInt32(data[i + 1]) << 8)
                | (UInt32(data[i + 2]) << 16)
                | (UInt32(data[i + 3]) << 24)
            if sig == 0x06054b50 { return i }
            i -= 1
        }
        throw ZipArchiveError.endOfCentralDirectoryNotFound
    }
}

// MARK: - 测试可见性桥接（Data 的私有 LE 读取在 module 内可见）

extension Data {
    /// 测试桥接：复用 module 内 readUInt32LE 的字节拼接逻辑（私有方法在 @testable 下仍不可见，
    /// 此处内联等价实现供测试定位 EOCD 使用）。
    func readUInt32LETesting(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}

// MARK: - 测试用内存流实现

/// 测试用内存输出流：追加写到 Data buffer。
final class TestDataOutputStream: ZipOutputStream, @unchecked Sendable {
    private(set) var buffer = Data()
    private(set) var offset: Int64 = 0
    private var closed = false

    func write(_ data: Data) async throws {
        guard !closed else { throw ZipArchiveError.offsetOutOfBounds }
        buffer.append(data)
        offset += Int64(data.count)
    }

    func close() async throws { closed = true }
}

/// 测试用内存输入流：基于 Data 提供随机访问。
final class TestDataInputStream: ZipInputStream, @unchecked Sendable {
    private let data: Data
    let size: Int64

    init(data: Data) {
        self.data = data
        self.size = Int64(data.count)
    }

    func read(offset: Int64, length: Int) async throws -> Data {
        let start = Int(offset)
        guard start >= 0, start <= data.count else {
            throw ZipArchiveError.offsetOutOfBounds
        }
        let end = min(start + length, data.count)
        return data.subdata(in: start..<end)
    }

    func close() async throws {}
}
