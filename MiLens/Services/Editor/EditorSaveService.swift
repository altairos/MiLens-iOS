//  EditorSaveService —— 编辑器保存回写编排。
//  流程：写沙盒新文件（MiLens_Edit_<ts>.<ext>）→ 就地更新 Photo 记录
//  （uri/thumbnailPath/fileSize/width/height，DESIGN.md §7：不新增记录，编辑覆盖原照片）。
//  格式决策（PNG/JPEG）来自 EditorSaveLogic.resolveSaveFormat（MiLensKit）。

import Foundation
import MiLensKit

/// 编辑器保存服务（@MainActor——PhotoRepository 为 @MainActor 隔离）。
@MainActor
final class EditorSaveService {

    private let fileStorage: any FileStorage
    private let photoRepo: any PhotoRepositoryProtocol
    /// 沙盒照片目录路径（Documents/MiPhotos，与 ImportService 同目录）
    private let sandboxDir: String

    init(fileStorage: any FileStorage,
         photoRepo: any PhotoRepositoryProtocol,
         sandboxDir: String) {
        self.fileStorage = fileStorage
        self.photoRepo = photoRepo
        self.sandboxDir = sandboxDir
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
        let path = "\(sandboxDir)/\(fileName)"
        try? await fileStorage.createDirectory(at: sandboxDir)
        try await fileStorage.write(data, to: path)

        // 就地更新记录（编辑覆盖原照片；thumbnailPath 置空 → 读取端回退 uri）。
        photo.uri = path
        photo.thumbnailPath = ""
        photo.fileSize = Int64(data.count)
        photo.width = width
        photo.height = height
        try photoRepo.updatePhoto(photo)
        return path
    }
}
