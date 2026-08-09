import XCTest
@testable import MiLens

/// IOSFileStorage 测试——FileManager 真实实现的沙盒文件操作。
/// 使用系统临时目录（每次测试独立子目录，结束后清理），与 mock 契约测试
/// （PlatformContractTests MockFileStorage）保持同一协议面。
final class IOSFileStorageTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IOSFileStorageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
    }

    private func path(_ name: String) -> String {
        tempDir.appendingPathComponent(name).path
    }

    func testWriteThenReadRoundTrip() async throws {
        let fs = IOSFileStorage()
        let data = Data([0x89, 0x50, 0x4E, 0x47])  // PNG header bytes
        try await fs.write(data, to: path("a.png"))

        let readBack = try await fs.read(at: path("a.png"))
        XCTAssertEqual(readBack, data)
    }

    func testWriteCreatesParentDirectories() async throws {
        let fs = IOSFileStorage()
        try await fs.write(Data("x".utf8), to: path("nested/sub/file.txt"))

        XCTAssertTrue(fs.fileExists(at: path("nested/sub/file.txt")))
        let readBack = try await fs.read(at: path("nested/sub/file.txt"))
        XCTAssertEqual(String(data: readBack, encoding: .utf8), "x")
    }

    func testCopyPreservesContent() async throws {
        let fs = IOSFileStorage()
        try await fs.write(Data("hello".utf8), to: path("src.txt"))
        try await fs.copy(from: path("src.txt"), to: path("dest.txt"))

        let readBack = try await fs.read(at: path("dest.txt"))
        XCTAssertEqual(String(data: readBack, encoding: .utf8), "hello")
    }

    func testCopyMissingSourceThrows() async throws {
        let fs = IOSFileStorage()
        do {
            try await fs.copy(from: path("missing.txt"), to: path("dest.txt"))
            XCTFail("应抛出 fileNotFound")
        } catch let error as FileStorageError {
            XCTAssertEqual(error, .fileNotFound(path("missing.txt")))
        }
    }

    func testReadMissingThrows() async throws {
        let fs = IOSFileStorage()
        do {
            _ = try await fs.read(at: path("missing.txt"))
            XCTFail("应抛出 fileNotFound")
        } catch let error as FileStorageError {
            XCTAssertEqual(error, .fileNotFound(path("missing.txt")))
        }
    }

    func testFileExistsAndRemoveItem() async throws {
        let fs = IOSFileStorage()
        try await fs.write(Data("test".utf8), to: path("f.txt"))
        XCTAssertTrue(fs.fileExists(at: path("f.txt")))

        try await fs.removeItem(at: path("f.txt"))
        XCTAssertFalse(fs.fileExists(at: path("f.txt")))
    }

    func testRemoveMissingThrows() async throws {
        let fs = IOSFileStorage()
        do {
            try await fs.removeItem(at: path("missing"))
            XCTFail("应抛出 fileNotFound")
        } catch let error as FileStorageError {
            XCTAssertEqual(error, .fileNotFound(path("missing")))
        }
    }

    func testCreateDirectoryAndExists() async throws {
        let fs = IOSFileStorage()
        XCTAssertFalse(fs.fileExists(at: path("dir")))

        try await fs.createDirectory(at: path("dir"))
        XCTAssertTrue(fs.fileExists(at: path("dir")))
    }

    // MARK: - 备份排除（Documents 下的媒体副本不进入 iCloud/iTunes 备份）

    /// 写入 Documents 下的文件必须设置 isExcludedFromBackup（评审中优先级）。
    /// 使用测试沙盒的真实 Documents 目录（临时子目录，结束后清理）。
    func testDocumentsWriteExcludedFromBackup() async throws {
        let fs = IOSFileStorage()
        let dir = URL.documentsDirectory
            .appendingPathComponent("IOSFileStorageBackupTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("a.jpg")

        try await fs.write(Data("x".utf8), to: fileURL.path)

        let values = try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true,
                       "Documents 下的媒体副本必须排除备份（照片不离开设备的承诺）")
    }

    /// 非 Documents 路径（如临时目录）不受影响——排除逻辑只作用于媒体副本目录。
    func testNonDocumentsWriteKeepsBackupEligible() async throws {
        let fs = IOSFileStorage()
        let fileURL = tempDir.appendingPathComponent("keep.txt")
        try await fs.write(Data("x".utf8), to: fileURL.path)

        let values = try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertNotEqual(values.isExcludedFromBackup, true,
                          "非 Documents 路径不应被排除备份")
    }
}

/// ScanCursorStore 测试——游标持久化（UserDefaults 隔离 suite）与 mock 行为。
final class ScanCursorStoreTests: XCTestCase {

    func testUserDefaultsRoundTrip() {
        let suite = "ScanCursorStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = UserDefaultsScanCursorStore(defaults: defaults)
        XCTAssertNil(store.lastSuccessfulScan, "初始无游标")

        let date = Date(timeIntervalSince1970: 1234)
        store.saveLastSuccessfulScan(date)
        XCTAssertEqual(store.lastSuccessfulScan, date)
    }

    func testMockStoreRecordsTimestamps() {
        let store = MockScanCursorStore()
        XCTAssertNil(store.lastSuccessfulScan)

        let date = Date(timeIntervalSince1970: 99)
        store.saveLastSuccessfulScan(date)
        XCTAssertEqual(store.lastSuccessfulScan, date)
        XCTAssertEqual(store.savedTimestamps, [date])
    }

    func testMockStoreWithPresetCursor() {
        let date = Date(timeIntervalSince1970: 50)
        let store = MockScanCursorStore(lastSuccessfulScan: date)
        XCTAssertEqual(store.lastSuccessfulScan, date)
    }
}
