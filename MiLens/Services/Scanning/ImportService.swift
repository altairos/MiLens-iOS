//  ImportService —— 用户主动导入照片编排
//  （对应源端 services/PhotoScanner.ets importPhotos + PhotoImportMetadata.createPhotoFromUri）。
//
//  DESIGN.md §7 硬约束：insertPhoto() 是唯一入库路径。
//  扫描只筛选不入库；用户手动选择后通过本服务导入。
//
//  流程：加载原图 → 复制到沙盒（缩放 1024px JPEG）→ 创建 Photo 元数据 → 入库。
//  V1.0 不含 pHash/embedding 计算（后置 V1.x）。

import Foundation

/// 导入服务（@MainActor——PhotoRepository 为 @MainActor 隔离）。
@MainActor
final class ImportService {

    private let photoLibrary: any PhotoLibraryAccess
    private let fileStorage: any FileStorage
    private let photoRepo: any PhotoRepositoryProtocol
    /// 沙盒照片目录路径（Documents/MiPhotos）
    private let sandboxDir: String

    /// 当前是否正在导入
    private(set) var isImporting = false

    init(photoLibrary: any PhotoLibraryAccess,
         fileStorage: any FileStorage,
         photoRepo: any PhotoRepositoryProtocol,
         sandboxDir: String) {
        self.photoLibrary = photoLibrary
        self.fileStorage = fileStorage
        self.photoRepo = photoRepo
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

        // 确保沙盒目录存在
        try? await fileStorage.createDirectory(at: sandboxDir)

        // 去重集合
        let existingURIs = (try? photoRepo.getAllPhotoURIs()) ?? []

        var imported = 0
        let total = min(identifiers.count, ScanConfig.maxImportBatch)

        for (index, identifier) in identifiers.prefix(ScanConfig.maxImportBatch).enumerated() {
            if Task.isCancelled { break }

            // 跳过已导入
            if existingURIs.contains(identifier) {
                onProgress?(ImportProgress(current: index + 1, total: total))
                continue
            }

            do {
                // 加载原图数据（缩放到 1024px 用于沙盒副本）
                let imageData = try await photoLibrary.loadImageData(
                    forIdentifier: identifier,
                    maxDimension: ScanConfig.importMaxDimension
                )

                // 复制到沙盒（文件名 = hash(identifier).jpg）
                let sandboxPath = "\(sandboxDir)/\(hashToFilename(identifier)).jpg"
                try await fileStorage.write(imageData, to: sandboxPath)

                // 从照片库获取元数据
                let metadata = try await photoLibrary.metadata(forIdentifier: identifier)

                // 创建 Photo 对象
                let photo = Photo(
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

                // 入库（DESIGN.md §7 唯一入库路径）
                try photoRepo.insertPhoto(photo)
                imported += 1
            } catch {
                // 单张导入失败不阻止后续
                continue
            }

            onProgress?(ImportProgress(current: index + 1, total: total))
        }

        return imported
    }
}
