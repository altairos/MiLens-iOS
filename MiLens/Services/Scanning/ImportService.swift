//  ImportService —— 用户主动导入照片编排
//  （对应源端 services/PhotoScanner.ets importPhotos + PhotoImportMetadata.createPhotoFromUri）。
//
//  DESIGN.md §7 硬约束：insertPhoto() 是唯一入库路径。
//  扫描只筛选不入库；用户手动选择后通过本服务导入。
//
//  流程：加载原图 → 复制到沙盒（缩放 1024px JPEG）→ 创建 Photo 元数据 → 入库。
//  文件写入与入库的一致性由 MediaLifecycleService.commitImport 保证（DB 失败回滚文件）。
//  去重：以 originalURI（Photos localIdentifier）为键——uri 是沙盒副本路径不能作比较；
//  同一批次内重复 identifier 只导入一次。
//  文件名：UUID（与 Photo.id 一致）——短哈希可能碰撞覆盖已有文件，且无法确认
//  失败回滚时删除的是本次写入的文件。
//  V1.0 不含 pHash/embedding 计算（后置 V1.x）。

import Foundation
import os

/// 导入服务（@MainActor——PhotoRepository 为 @MainActor 隔离）。
@MainActor
final class ImportService {

    private let logger = Logger(subsystem: "com.milens.app", category: "Import")

    private let photoLibrary: any PhotoLibraryAccess
    private let fileStorage: any FileStorage
    private let photoRepo: any PhotoRepositoryProtocol
    private let mediaLifecycle: MediaLifecycleService
    /// 沙盒照片目录路径（Documents/MiPhotos）
    private let sandboxDir: String

    /// 当前是否正在导入
    private(set) var isImporting = false

    init(photoLibrary: any PhotoLibraryAccess,
         fileStorage: any FileStorage,
         photoRepo: any PhotoRepositoryProtocol,
         mediaLifecycle: MediaLifecycleService,
         sandboxDir: String) {
        self.photoLibrary = photoLibrary
        self.fileStorage = fileStorage
        self.photoRepo = photoRepo
        self.mediaLifecycle = mediaLifecycle
        self.sandboxDir = sandboxDir
    }

    /// 导入选中的照片到应用沙盒并入库。
    /// - Parameters:
    ///   - identifiers: 照片库 identifier 列表（来自扫描结果或 PHPicker）
    ///   - onProgress: 进度回调
    /// - Returns: 实际导入数量
    @discardableResult
    func importPhotos(
        identifiers: [String],
        onProgress: (@MainActor (ImportProgress) -> Void)? = nil
    ) async -> Int {
        guard !isImporting, !identifiers.isEmpty else { return 0 }
        isImporting = true
        defer { isImporting = false }

        // 确保沙盒目录存在（目录创建失败是环境级错误，直接终止本次导入）
        do {
            try await fileStorage.createDirectory(at: sandboxDir)
        } catch {
            return 0
        }

        // 去重集合：以 originalURI（Photos localIdentifier）为键；
        // 读取失败时按无既有记录处理（可能重复导入，但保证不中断本次导入）
        let existingOriginalURIs: Set<String>
        do {
            existingOriginalURIs = try photoRepo.getAllOriginalURIs()
        } catch {
            logger.error("importPhotos: 读取既有 originalURI 失败（\(error.localizedDescription)），本次去重失效")
            existingOriginalURIs = []
        }
        // 同一批次内已处理的 identifier（输入列表可能含重复）
        var seenInBatch: Set<String> = []

        var imported = 0
        let total = min(identifiers.count, ScanConfig.maxImportBatch)

        for (index, identifier) in identifiers.prefix(ScanConfig.maxImportBatch).enumerated() {
            if Task.isCancelled { break }

            // 同一批次内重复 identifier：跳过
            if seenInBatch.contains(identifier) {
                onProgress?(ImportProgress(current: index + 1, total: total))
                continue
            }
            seenInBatch.insert(identifier)

            // 跳过已导入（originalURI 去重）
            if existingOriginalURIs.contains(identifier) {
                onProgress?(ImportProgress(current: index + 1, total: total))
                continue
            }

            do {
                // 文件名 = UUID（与 Photo.id 一致）——避免短哈希碰撞覆盖已有文件
                let fileID = UUID()
                let sandboxPath = "\(sandboxDir)/\(fileID.uuidString).jpg"

                // 加载原图数据（缩放到 1024px 用于沙盒副本）
                let imageData = try await photoLibrary.loadImageData(
                    forIdentifier: identifier,
                    maxDimension: ScanConfig.importMaxDimension
                )

                // 从照片库获取元数据
                let metadata = try await photoLibrary.metadata(forIdentifier: identifier)

                // 创建 Photo 对象（id 与沙盒文件名一致，便于排查与清理）
                let photo = Photo(
                    id: fileID,
                    uri: sandboxPath,
                    originalURI: identifier,
                    takenAt: metadata?.dateTaken,
                    thumbnailPath: ScanControlMath.resolveThumbnailPath(sandboxPath),
                    width: metadata?.pixelWidth ?? 0,
                    height: metadata?.pixelHeight ?? 0,
                    fileSize: metadata?.fileSize ?? Int64(imageData.count),
                    category: "pet_photo",
                    subCategory: "other"
                )

                // 写文件 + 入库（事务段：DB 失败回滚已写文件）
                try await mediaLifecycle.commitImport(data: imageData, to: sandboxPath, photo: photo)
                imported += 1
            } catch {
                // 单张导入失败不阻止后续（commitImport 已回滚已写文件，不留孤儿）
                continue
            }

            onProgress?(ImportProgress(current: index + 1, total: total))
        }

        return imported
    }
}
