//  IOSFileStorage —— FileStorage 的 FileManager 真实实现（对应源端 FileService）。
//  路径语义：沙盒绝对路径（如 Documents/MiPhotos/xxx.jpg）。
//  与 MockFileStorage 保持同一协议面；由 MiLensApp 组合根构造并通过
//  .environment(\.fileStorage) 注入（DESIGN.md §9 平台适配层）。
//  写文件前自动创建父目录，保证 ImportService / EditorSaveService 不依赖调用方建目录。
//
//  备份策略（V1.0）：按目录区分可重建性 + 用户可控（任务 3）——
//  - Documents/MiPhotos/Edits/ 下的编辑成品始终允许备份（不可重建）；
//  - Documents/MiPhotos/ 下的导入副本默认排除 iCloud/iTunes 备份（节省云空间）；
//    用户可在设置页切换为 dataSafe 模式，将导入副本也纳入系统备份。
//    切换后调用 reapplyBackupExclusion 立即重标记已有文件。

import Foundation
import os

/// FileManager 沙盒文件操作实现。
final class IOSFileStorage: FileStorage, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.milens.app", category: "FileStorage")
    /// 导入副本是否排除系统备份（用户可配置，闭包延迟求值以响应用户切换）。
    private let excludePhotosFromBackup: @Sendable () -> Bool

    init(excludePhotosFromBackup: @Sendable @escaping () -> Bool = { true }) {
        self.excludePhotosFromBackup = excludePhotosFromBackup
    }

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
    /// 仅作用于 Documents/MiPhotos/ 下、非 Edits 子目录的媒体（编辑成品始终允许备份）；
    /// 目录属性不向新建文件传播，因此写入时逐文件设置；失败仅记日志不阻断写入
    /// （备份排除是优化项，不应让文件操作失败）。
    /// 用户可在设置页切换为 dataSafe 模式——此时不排除导入副本（纳入系统备份）。
    private func applyBackupExclusionIfNeeded(at path: String) {
        guard excludePhotosFromBackup(),
              path.contains("/Documents/\(ScanConfig.sandboxDirName)/"),
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

    /// 用户切换备份模式后，重新标记已有文件的 isExcludedFromBackup 属性。
    /// 遍历沙盒目录，对导入副本（非 Edits 子目录）设置或清除排除标记。
    /// Edits 子目录始终不排除（编辑成品不可重建，始终允许备份）。
    /// - Parameters:
    ///   - sandboxDir: 沙盒媒体根目录（Documents/MiPhotos）
    ///   - exclude: 导入副本是否排除系统备份
    func reapplyBackupExclusion(in sandboxDir: String, exclude: Bool) async {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: sandboxDir)
        let editsMarker = "/\(ScanConfig.sandboxDirName)/\(ScanConfig.editsDirName)/"

        guard let enumerator = fm.enumerator(
            at: dirURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.warning("reapplyBackupExclusion: 目录不存在或无法枚举（\(sandboxDir)）")
            return
        }

        var reapplied = 0
        for case let url as URL in enumerator {
            // 仅处理常规文件（跳过子目录本身）
            guard let isRegular = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                  isRegular == true else { continue }
            // Edits 子目录始终不排除
            if url.path.contains(editsMarker) { continue }
            // 仅处理 MiPhotos 下的导入副本
            guard url.path.contains("/\(ScanConfig.sandboxDirName)/") else { continue }

            var mutableURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = exclude
            do {
                try mutableURL.setResourceValues(values)
                reapplied += 1
            } catch {
                logger.error("reapplyBackupExclusion: 设置 \(url.path) 失败（\(error.localizedDescription)）")
            }
        }
        logger.info("reapplyBackupExclusion: 已重新标记 \(reapplied) 个文件（exclude=\(exclude)）")
    }
}
