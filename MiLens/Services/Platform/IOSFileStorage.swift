//  IOSFileStorage —— FileStorage 的 FileManager 真实实现（对应源端 FileService）。
//  路径语义：沙盒绝对路径（如 Documents/MiPhotos/xxx.jpg）。
//  与 MockFileStorage 保持同一协议面；由 MiLensApp 组合根构造并通过
//  .environment(\.fileStorage) 注入（DESIGN.md §9 平台适配层）。
//  写文件前自动创建父目录，保证 ImportService / EditorSaveService 不依赖调用方建目录。

import Foundation

/// FileManager 沙盒文件操作实现。
final class IOSFileStorage: FileStorage {

    func copy(from source: String, to destination: String) async throws {
        guard fileExists(at: source) else {
            throw FileStorageError.fileNotFound(source)
        }
        try ensureParentDirectory(of: destination)
        try FileManager.default.copyItem(atPath: source, toPath: destination)
    }

    func read(at path: String) async throws -> Data {
        guard fileExists(at: path) else {
            throw FileStorageError.fileNotFound(path)
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    func write(_ data: Data, to path: String) async throws {
        try ensureParentDirectory(of: path)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func createDirectory(at path: String) async throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path),
            withIntermediateDirectories: true
        )
    }

    func removeItem(at path: String) async throws {
        guard fileExists(at: path) else {
            throw FileStorageError.fileNotFound(path)
        }
        try FileManager.default.removeItem(atPath: path)
    }

    // MARK: - 私有

    private func ensureParentDirectory(of path: String) throws {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
    }
}
