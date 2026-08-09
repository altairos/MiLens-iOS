//  EditorSaveService —— 编辑器保存回写编排。
//  流程：写沙盒新文件（MiLens_Edit_<ts>.<ext>）→ 就地更新 Photo 记录
//  （uri/thumbnailPath/fileSize/width/height，DESIGN.md §7：不新增记录，编辑覆盖原照片）。
//  格式决策（PNG/JPEG）来自 EditorSaveLogic.resolveSaveFormat（MiLensKit）。
//  文件写入与记录更新的一致性由 MediaLifecycleService.saveEditedPhoto 保证
//  （失败回滚新文件，成功清理旧版本文件）。

import Foundation
import MiLensKit

/// 编辑器保存服务（@MainActor——PhotoRepository 为 @MainActor 隔离）。
@MainActor
final class EditorSaveService {

    private let mediaLifecycle: MediaLifecycleService
    /// 编辑产物目录路径（Documents/MiPhotos/Edits）——编辑成品不可从系统相册重建，
    /// 允许备份；与排除备份的导入副本分区（DESIGN.md §7）。
    private let editsDir: String

    init(mediaLifecycle: MediaLifecycleService,
         sandboxDir: String,
         editsDir: String? = nil) {
        self.mediaLifecycle = mediaLifecycle
        // sandboxDir 仅用于派生默认 editsDir（与导入副本分区存储）
        self.editsDir = editsDir ?? sandboxDir + "/" + ScanConfig.editsDirName
    }

    /// 保存编辑产物并更新照片记录。
    /// - Parameters:
    ///   - photo: 目标照片记录（就地更新属性）
    ///   - data: 已编码的导出数据（JPEG/PNG，由 imageProcessor.renderExport 生成）
    ///   - decision: 格式决策（决定扩展名与编码质量）
    ///   - width/height: 导出图尺寸（像素）
    ///   - timestamp: 文件时间戳（注入保证测试可复现）
    /// - Returns: 新文件路径
    @discardableResult
    func saveEditedPhoto(
        _ photo: Photo,
        data: Data,
        decision: EditorSaveFormatDecision,
        width: Int,
        height: Int,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) async throws -> String {
        let fileName = resolveSaveFileNameHint(timestamp: timestamp, decision: decision)
        let path = "\(editsDir)/\(fileName)"
        // 事务段：写新文件 → 更新记录 → 清理旧版本文件（失败回滚）
        return try await mediaLifecycle.saveEditedPhoto(
            photo, data: data, to: path, width: width, height: height)
    }
}
