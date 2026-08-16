//  FileStorage —— 沙盒文件操作协议（对应源端 IFileService）。
//  把 FileManager 的直接调用隔离在此协议后面，
//  使 ImportService / ExportService 可以通过 mock 覆盖文件 I/O 路径。
//  DESIGN.md §9 平台适配层。

import Foundation
import MiLensKit

/// 文件存储错误。
enum FileStorageError: Error, Equatable {
    case fileNotFound(String)
    case directoryNotFound(String)
}

/// 沙盒文件操作协议。V1.0 含导入复制/缩略图缓存/导出所需方法。
/// Sendable：实现类无共享可变状态（或单线程测试 mock），供后台执行器捕获。
protocol FileStorage: Sendable {
    func copy(from source: String, to destination: String) async throws
    func read(at path: String) async throws -> Data
    func write(_ data: Data, to path: String) async throws
    func fileExists(at path: String) -> Bool
    /// 读取文件大小（字节），文件不存在返回 nil。备份分卷预估用，避免依赖可能过期的 DB fileSize。
    func fileSize(at path: String) -> Int64?
    func createDirectory(at path: String) async throws
    func removeItem(at path: String) async throws
    /// 列出目录下的文件路径（不含子目录递归，仅直接子项）。孤儿审计用。
    func listFiles(in directory: String) -> [String]
    /// 构造流式输出流（追加写，大备份导出用）。
    func makeOutputStream(at path: String) async throws -> any ZipOutputStream
    /// 构造随机访问输入流（大备份恢复用）。
    func makeInputStream(at path: String) async throws -> any ZipInputStream
}

// MARK: - Mock（对应源端 FakeFileService）

/// 内存文件系统的 mock，用于单元测试。
/// 维护 `[path: Data]` 模拟文件内容，`Set<path>` 模拟目录。
final class MockFileStorage: FileStorage, @unchecked Sendable {
    private var files: [String: Data] = [:]
    private var directories: Set<String> = ["/tmp", "/documents", "/cache"]

    /// 失败注入：createDirectory 抛错（导入沙盒目录创建失败路径）。
    var failCreateDirectory = false

    /// 预设文件内容（测试辅助方法，对应源端 presetFile）。
    func preset(_ data: Data, at path: String) {
        files[path] = data
    }

    func copy(from source: String, to destination: String) async throws {
        guard let data = files[source] else {
            throw FileStorageError.fileNotFound(source)
        }
        files[destination] = data
    }

    func read(at path: String) async throws -> Data {
        guard let data = files[path] else {
            throw FileStorageError.fileNotFound(path)
        }
        return data
    }

    func write(_ data: Data, to path: String) async throws {
        files[path] = data
    }

    func fileExists(at path: String) -> Bool {
        files[path] != nil || directories.contains(path)
    }

    func fileSize(at path: String) -> Int64? {
        files[path].map { Int64($0.count) }
    }

    func createDirectory(at path: String) async throws {
        guard !failCreateDirectory else {
            throw FileStorageError.directoryNotFound(path)
        }
        directories.insert(path)
    }

    func removeItem(at path: String) async throws {
        files[path] = nil
        directories.remove(path)
    }

    func listFiles(in directory: String) -> [String] {
        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        return files.keys.filter { path in
            guard path.hasPrefix(prefix) else { return false }
            // 仅直接子项（不含更深层路径）
            return path.dropFirst(prefix.count).firstIndex(of: "/") == nil
        }
    }

    func makeOutputStream(at path: String) async throws -> any ZipOutputStream {
        MockOutputStream(parent: self, path: path)
    }

    func makeInputStream(at path: String) async throws -> any ZipInputStream {
        guard let data = files[path] else {
            throw FileStorageError.fileNotFound(path)
        }
        return MockInputStream(data: data)
    }
}

// MARK: - 内存流式实现（测试用）

/// 内存输出流：write 追加到内部 Data，close 时写回 MockFileStorage.files。
final class MockOutputStream: ZipOutputStream, @unchecked Sendable {
    private let parent: MockFileStorage
    private let path: String
    private var buffer = Data()
    private(set) var offset: Int64 = 0
    private var closed = false

    init(parent: MockFileStorage, path: String) {
        self.parent = parent
        self.path = path
    }

    func write(_ data: Data) async throws {
        guard !closed else { throw FileStorageError.fileNotFound(path) }
        buffer.append(data)
        offset += Int64(data.count)
    }

    func close() async throws {
        guard !closed else { return }
        closed = true
        parent.preset(buffer, at: path)
    }
}

/// 内存输入流：基于 Data 切片提供随机访问读取。
final class MockInputStream: ZipInputStream, @unchecked Sendable {
    private let data: Data
    let size: Int64

    init(data: Data) {
        self.data = data
        self.size = Int64(data.count)
    }

    func read(offset: Int64, length: Int) async throws -> Data {
        let start = Int(offset)
        let end = min(start + length, data.count)
        guard start >= 0, start <= data.count else {
            throw ZipArchiveError.offsetOutOfBounds
        }
        return data.subdata(in: start..<end)
    }

    func close() async throws {}
}
