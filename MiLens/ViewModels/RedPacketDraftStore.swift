//  RedPacketDraftStore —— 红包封面草稿本地持久化（对应红包封面开发计划 §5）。
//
//  草稿保存为可恢复的 JSON，目录 Documents/RedPacketDrafts/<uuid>.json。
//  先使用本地草稿目录 + JSON 验证编辑闭环；需要跨启动、多个草稿和删除联动后，
//  再增加 SwiftData @Model。

import Foundation
import MiLensKit

/// 红包草稿本地存储。
@MainActor
final class RedPacketDraftStore {

    private let draftsDir: URL

    init(draftsDir: URL) {
        self.draftsDir = draftsDir
    }

    /// 便捷构造：默认目录 Documents/RedPacketDrafts。
    static var defaultDir: URL {
        URL.documentsDirectory.appendingPathComponent("RedPacketDrafts", isDirectory: true)
    }

    convenience init() {
        self.init(draftsDir: RedPacketDraftStore.defaultDir)
    }

    // MARK: - 目录

    /// 确保草稿目录存在。
    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: draftsDir, withIntermediateDirectories: true)
    }

    /// 草稿文件 URL。
    private func fileURL(for id: UUID) -> URL {
        draftsDir.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - 保存

    /// 保存草稿（覆盖式）。
    func save(_ draft: RedPacketCoverDraft) throws {
        try ensureDirectory()
        let data = try draft.encodeJSON()
        try data.write(to: fileURL(for: draft.id), options: .atomic)
    }

    // MARK: - 加载

    /// 加载指定草稿。
    func load(id: UUID) throws -> RedPacketCoverDraft? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try RedPacketCoverDraft.decodeJSON(data)
    }

    /// 列出全部草稿（按更新时间降序）。
    func listAll() throws -> [RedPacketCoverDraft] {
        try ensureDirectory()
        let urls = try FileManager.default.contentsOfDirectory(at: draftsDir, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" }

        var drafts: [RedPacketCoverDraft] = []
        for url in urls {
            if let data = try? Data(contentsOf: url),
               let draft = try? RedPacketCoverDraft.decodeJSON(data) {
                drafts.append(draft)
            }
        }
        return drafts.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - 删除

    /// 删除草稿。
    func delete(id: UUID) throws {
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
