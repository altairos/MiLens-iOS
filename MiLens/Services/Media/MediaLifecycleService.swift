//  MediaLifecycleService —— 媒体文件与数据库记录的事务一致性编排（P1 可靠性）。
//  （对应源端无直接等价物；统一治理导入/编辑/删除的文件-记录不一致窗口。）
//
//  职责：
//  - commitImport：写文件 → 入库；入库失败回滚已写文件（不留孤儿文件）。
//  - saveEditedPhoto：写新文件 → 更新记录；失败删新文件，成功删旧版本文件。
//  - deletePhoto：数据库删除 + 联动删除沙盒媒体文件（文件失败不阻断记录删除）。
//  - auditOrphans：启动时扫描沙盒目录，清理 DB 无记录的孤儿文件；
//    DB 有记录但文件缺失仅记日志（不删 DB——文件可经系统相册原图恢复）。
//  - refreshPetPhotoCounts：删除联动后刷新宠物照片计数缓存。
//
//  DESIGN.md §4：Service 编排 IO + 异常处理；DB 是事实源，媒体文件是派生资源。

import Foundation
import os

@MainActor
final class MediaLifecycleService {

    private let photoRepo: any PhotoRepositoryProtocol
    private let petRepo: any PetRepositoryProtocol
    private let fileStorage: any FileStorage
    /// 沙盒照片目录路径（Documents/MiPhotos，与 ImportService 同目录）
    private let sandboxDir: String
    private let logger = Logger(subsystem: "com.milens.app", category: "MediaLifecycle")

    init(photoRepo: any PhotoRepositoryProtocol,
         petRepo: any PetRepositoryProtocol,
         fileStorage: any FileStorage,
         sandboxDir: String) {
        self.photoRepo = photoRepo
        self.petRepo = petRepo
        self.fileStorage = fileStorage
        self.sandboxDir = sandboxDir
    }

    // MARK: - 导入事务段

    /// 导入事务段：写文件 → 入库。任一步失败回滚已写文件。
    /// - Parameters:
    ///   - data: 已编码的图像数据
    ///   - path: 目标沙盒路径
    ///   - photo: 已构建的 Photo 记录（uri 应为 path）
    func commitImport(data: Data, to path: String, photo: Photo) async throws {
        try await fileStorage.write(data, to: path)
        do {
            try photoRepo.insertPhoto(photo)
        } catch {
            // DB 失败 → 回滚已写文件，不留孤儿文件；回滚失败仅记日志（文件可手工清理）
            do {
                try await fileStorage.removeItem(at: path)
            } catch {
                logger.error("commitImport: 回滚删除失败（\(path)，\(error.localizedDescription)）")
            }
            throw error
        }
    }

    // MARK: - 编辑保存事务段

    /// 编辑保存事务段：写新文件 → 就地更新记录（uri/thumbnail/fileSize/尺寸）。
    /// - 更新失败：恢复记录旧属性 + 删除新文件后抛出（记录保持指向旧文件）。
    /// - 更新成功：清理旧版本文件（uri 变化且不再被任何记录引用时）。
    /// - Returns: 新文件路径
    @discardableResult
    func saveEditedPhoto(
        _ photo: Photo, data: Data, to newPath: String, width: Int, height: Int
    ) async throws -> String {
        let oldURI = photo.uri
        let oldThumbnailPath = photo.thumbnailPath
        let oldFileSize = photo.fileSize
        let oldWidth = photo.width
        let oldHeight = photo.height
        try await fileStorage.write(data, to: newPath)
        do {
            // 就地更新记录（编辑覆盖原照片；thumbnailPath 置空 → 读取端回退 uri）
            photo.uri = newPath
            photo.thumbnailPath = ""
            photo.fileSize = Int64(data.count)
            photo.width = width
            photo.height = height
            // 作品标记：档案「作品」分类的唯一可靠来源（UI-DESIGN.md §6.4）
            photo.category = PhotoCategory.edited.rawValue
            try photoRepo.updatePhoto(photo)
        } catch {
            // 记录更新失败 → 恢复内存旧值 + 回滚新文件，记录保持指向旧文件
            photo.uri = oldURI
            photo.thumbnailPath = oldThumbnailPath
            photo.fileSize = oldFileSize
            photo.width = oldWidth
            photo.height = oldHeight
            do {
                try await fileStorage.removeItem(at: newPath)
            } catch {
                logger.error("saveEditedPhoto: 回滚删除新文件失败（\(newPath)，\(error.localizedDescription)）")
            }
            throw error
        }
        // 成功：清理旧版本文件（路径唯一由 hash/时间戳生成；仍防御性检查引用）
        if oldURI != newPath, fileStorage.fileExists(at: oldURI) {
            // 引用查询失败时保守保留旧文件（不删）——避免误删仍被引用的媒体
            let stillReferenced: Bool
            do {
                stillReferenced = try photoRepo.getPhotoByURI(oldURI) != nil
            } catch {
                logger.error("saveEditedPhoto: 旧文件引用查询失败（\(oldURI)），保守保留")
                stillReferenced = true
            }
            if !stillReferenced {
                do {
                    try await fileStorage.removeItem(at: oldURI)
                } catch {
                    logger.error("saveEditedPhoto: 清理旧版本文件失败（\(oldURI)，\(error.localizedDescription)）")
                }
            }
        }
        return newPath
    }

    // MARK: - 删除联动

    /// 删除照片：数据库删除 + 联动删除沙盒媒体文件（thumbnailPath 与 uri 相同时只删一次）。
    /// 文件删除失败不阻断记录删除（媒体文件是派生资源，可经系统相册重新导入）。
    /// 删除后刷新归属宠物的照片计数缓存。
    func deletePhoto(_ photo: Photo) async throws {
        let pet = photo.pet
        let uri = photo.uri
        let thumbnail = photo.thumbnailPath

        try photoRepo.deletePhoto(photo)

        // 文件删除失败不阻断记录删除（媒体文件是派生资源，可经系统相册重新导入），仅记日志
        if !uri.isEmpty {
            do {
                try await fileStorage.removeItem(at: uri)
            } catch {
                logger.error("deletePhoto: 删除媒体文件失败（\(uri)，\(error.localizedDescription)）")
            }
        }
        if !thumbnail.isEmpty, thumbnail != uri {
            do {
                try await fileStorage.removeItem(at: thumbnail)
            } catch {
                logger.error("deletePhoto: 删除缩略图失败（\(thumbnail)，\(error.localizedDescription)）")
            }
        }
        if let pet {
            do {
                try petRepo.refreshPhotoCount(for: pet)
            } catch {
                logger.error("deletePhoto: 刷新宠物照片计数失败（\(error.localizedDescription)）")
            }
        }
    }

    /// 删除多张照片（多选删除入口用，逐张联动）。
    func deletePhotos(_ photos: [Photo]) async throws {
        for photo in photos {
            try await deletePhoto(photo)
        }
    }

    // MARK: - 启动孤儿审计

    /// 启动时审计：扫描沙盒目录与 DB 对照。
    /// - 文件存在但 DB 无记录 → 删除（孤儿文件，上一次崩溃/回滚残留）。
    /// - DB 记录存在但文件缺失 → 记日志（不删 DB——记录是事实源，文件可恢复）。
    func auditOrphans() async {
        let knownPaths: Set<String>
        do {
            knownPaths = try photoRepo.getAllPhotoURIs()
        } catch {
            logger.error("auditOrphans: 无法读取 DB 记录，跳过审计")
            return
        }
        let files = fileStorage.listFiles(in: sandboxDir)
        var orphanCount = 0
        for path in files where !knownPaths.contains(path) {
            do {
                try await fileStorage.removeItem(at: path)
            } catch {
                logger.error("auditOrphans: 删除孤儿文件失败（\(path)，\(error.localizedDescription)）")
            }
            orphanCount += 1
        }
        if orphanCount > 0 {
            logger.warning("auditOrphans: 清理 \(orphanCount) 个孤儿文件")
        }
    }

    // MARK: - 照片计数刷新

    /// 刷新指定宠物的照片计数缓存（补上生产链路缺口——PetsView/PetProfileView 直接读缓存）。
    func refreshPetPhotoCounts(for pets: [Pet]) throws {
        for pet in pets {
            try petRepo.refreshPhotoCount(for: pet)
        }
    }
}
