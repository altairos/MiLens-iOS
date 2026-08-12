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
