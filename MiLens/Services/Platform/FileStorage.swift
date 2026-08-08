//  FileStorage —— 沙盒文件操作协议（对应源端 IFileService）。
//  把 FileManager 的直接调用隔离在此协议后面，
//  使 ImportService / ExportService 可以通过 mock 覆盖文件 I/O 路径。
//  DESIGN.md §9 平台适配层。

import Foundation

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
    func createDirectory(at path: String) async throws
    func removeItem(at path: String) async throws
    /// 列出目录下的文件路径（不含子目录递归，仅直接子项）。孤儿审计用。
    func listFiles(in directory: String) -> [String]
}

// MARK: - Mock（对应源端 FakeFileService）

/// 内存文件系统的 mock，用于单元测试。
/// 维护 `[path: Data]` 模拟文件内容，`Set<path>` 模拟目录。
final class MockFileStorage: FileStorage, @unchecked Sendable {
    private var files: [String: Data] = [:]
    private var directories: Set<String> = ["/tmp", "/documents", "/cache"]

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

    func createDirectory(at path: String) async throws {
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
}
