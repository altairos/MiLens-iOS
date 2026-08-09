//  IOSFileStorage —— FileStorage 的 FileManager 真实实现（对应源端 FileService）。
//  路径语义：沙盒绝对路径（如 Documents/MiPhotos/xxx.jpg）。
//  与 MockFileStorage 保持同一协议面；由 MiLensApp 组合根构造并通过
//  .environment(\.fileStorage) 注入（DESIGN.md §9 平台适配层）。
//  写文件前自动创建父目录，保证 ImportService / EditorSaveService 不依赖调用方建目录。
//
//  备份策略（V1.0）：按目录区分可重建性——
//  - Documents/MiPhotos/ 下的导入副本（原图在系统相册可重新导入）按 Apple 指引
//    排除 iCloud/iTunes 备份，避免「照片不会离开设备」承诺与默认备份冲突；
//  - Documents/MiPhotos/Edits/ 下的编辑成品（系统相册中没有编辑后版本，
//    删除后不可重建）允许备份，保证设备恢复后编辑产物不丢失（DESIGN.md §7）。

import Foundation
import os

/// FileManager 沙盒文件操作实现。
final class IOSFileStorage: FileStorage, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.milens.app", category: "FileStorage")

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
        applyBackupExclusionIfNeeded(at: path)
    }

    func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func createDirectory(at path: String) async throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path),
            withIntermediateDirectories: true
        )
        applyBackupExclusionIfNeeded(at: path)
    }

    func removeItem(at path: String) async throws {
        guard fileExists(at: path) else {
            throw FileStorageError.fileNotFound(path)
        }
        try FileManager.default.removeItem(atPath: path)
    }

    func listFiles(in directory: String) -> [String] {
        let fm = FileManager.default
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(
                at: URL(fileURLWithPath: directory),
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        } catch {
            logger.error("listFiles: 读取目录失败（\(directory)，\(error.localizedDescription)）")
            return []
        }
        return urls.filter { url in
            do {
                return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile ?? false
            } catch {
                logger.error("listFiles: 文件属性读取失败（\(url.path)），按非常规文件跳过")
                return false
            }
        }.map(\.path)
    }

    // MARK: - 私有

    private func ensureParentDirectory(of path: String) throws {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
    }

    /// 对沙盒「可重建的导入副本」设置排除备份（isExcludedFromBackup）。
    /// 仅作用于 Documents/MiPhotos/ 下、非 Edits 子目录的媒体（编辑成品允许备份）；
    /// 目录属性不向新建文件传播，因此写入时逐文件设置；失败仅记日志不阻断写入
    /// （备份排除是优化项，不应让文件操作失败）。
    private func applyBackupExclusionIfNeeded(at path: String) {
        guard path.contains("/Documents/\(ScanConfig.sandboxDirName)/"),
              !path.contains("/\(ScanConfig.sandboxDirName)/\(ScanConfig.editsDirName)/") else {
            return
        }
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try url.setResourceValues(values)
        } catch {
            logger.error("applyBackupExclusion: 设置排除备份失败（\(path)，\(error.localizedDescription)）")
        }
    }
}
