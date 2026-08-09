//  ImportService —— 用户主动导入照片编排
//  （对应源端 services/PhotoScanner.ets importPhotos + PhotoImportMetadata.createPhotoFromUri）。
//
//  DESIGN.md §7 硬约束：insertPhoto() 是唯一入库路径。
//  扫描只筛选不入库；用户手动选择后通过本服务导入。
//
//  流程：加载原图 → 复制到沙盒（缩放 1024px JPEG）→ 创建 Photo 元数据 → 入库 →
//  自动归属（PetMatcher：CLIP embedding + 颜色签名匹配已注册宠物 → assignPhoto，
//  对应源端 importPhotos 中 matchFromEmbedding → assignPhotoToPet）。
//  文件写入与入库的一致性由 MediaLifecycleService.commitImportBatch 保证（批量入库失败回滚本批文件）。
//  去重：以 originalURI（Photos localIdentifier）为键——uri 是沙盒副本路径不能作比较；
//  同一批次内重复 identifier 只导入一次。
//  文件名：UUID（与 Photo.id 一致）——短哈希可能碰撞覆盖已有文件，且无法确认
//  失败回滚时删除的是本次写入的文件。
//  自动归属失败（模型缺失/提取失败/未达阈值）不阻止导入；
//  embedding 提取与颜色签名经 AnalysisExecutor 后台执行，不占 MainActor。

import Foundation
import os
import MiLensKit

/// 导入结果汇总。
struct ImportResult: Equatable, Sendable {
    /// 实际入库数量。
    let imported: Int
    /// 自动归属到已注册宠物的数量（≤ imported）。
    let matched: Int
    /// 单张导入失败的数量（加载/复制/入库失败；H4 可观测性）。
    let failed: Int
}

/// 导入服务（@MainActor——PhotoRepository/PetRepository 均为 @MainActor 隔离）。
@MainActor
final class ImportService {

    private let logger = Logger(subsystem: "com.milens.app", category: "Import")

    private let photoLibrary: any PhotoLibraryAccess
    private let fileStorage: any FileStorage
    private let photoRepo: any PhotoRepositoryProtocol
    private let petRepo: any PetRepositoryProtocol
    private let mediaLifecycle: MediaLifecycleService
    /// 自动归属匹配服务（clipService 为 nil 时不创建——无模型可提取 embedding）。
    private let matcher: PetMatcher?
    /// 沙盒照片目录路径（Documents/MiPhotos）
    private let sandboxDir: String
    private let executor: AnalysisExecutor

    /// 当前是否正在导入
    private(set) var isImporting = false

    init(photoLibrary: any PhotoLibraryAccess,
         fileStorage: any FileStorage,
         photoRepo: any PhotoRepositoryProtocol,
         mediaLifecycle: MediaLifecycleService,
         sandboxDir: String,
         petRepo: any PetRepositoryProtocol,
         clipService: (any ClipInference)? = nil,
         executor: AnalysisExecutor = AnalysisExecutor()) {
        self.photoLibrary = photoLibrary
        self.fileStorage = fileStorage
        self.photoRepo = photoRepo
        self.petRepo = petRepo
        self.mediaLifecycle = mediaLifecycle
        self.sandboxDir = sandboxDir
        self.executor = executor
        self.matcher = clipService.map {
            PetMatcher(petRepo: petRepo, clipService: $0, executor: executor)
        }
    }

    /// 导入选中的照片到应用沙盒并入库，随后自动归属到已注册宠物（如有匹配）。
    /// - Parameters:
    ///   - identifiers: 照片库 identifier 列表（来自扫描结果或 PHPicker）
    ///   - onProgress: 进度回调
    /// - Returns: 导入结果（imported = 实际入库数，matched = 自动归属数，failed = 单张失败数）
    @discardableResult
    func importPhotos(
        identifiers: [String],
        onProgress: (@MainActor (ImportProgress) -> Void)? = nil
    ) async -> ImportResult {
        guard !isImporting, !identifiers.isEmpty else { return ImportResult(imported: 0, matched: 0, failed: 0) }
        isImporting = true
        defer { isImporting = false }

        // H1 结构化任务日志：导入全过程记录，供 DiagnosticsCollector 汇总与线上诊断
        let taskId = TaskLogger.beginTask(.import_, label: "count=\(identifiers.count)")
        var taskOutcome: TaskOutcome = .success
        var taskSummary: String?
        defer {
            switch taskOutcome {
            case .success: TaskLogger.complete(taskId, summary: taskSummary)
            case .canceled: TaskLogger.cancel(taskId, summary: taskSummary)
            case .failed: TaskLogger.fail(
                taskId, err: ErrorInput(message: taskSummary), summary: taskSummary)
            }
        }
        TaskLogger.stage(taskId, "prepare")

        // 确保沙盒目录存在（目录创建失败是环境级错误，直接终止本次导入）
        do {
            try await fileStorage.createDirectory(at: sandboxDir)
        } catch {
            taskOutcome = .failed
            taskSummary = "创建沙盒目录失败"
            logger.error("importPhotos: 创建沙盒目录失败（\(error.localizedDescription)）")
            return ImportResult(imported: 0, matched: 0, failed: 0)
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
        var matched = 0
        var failed = 0
        let total = min(identifiers.count, ScanConfig.maxImportBatch)

        // L2 分批提交：逐张加载/写文件，攒够一批统一入库（替代逐张 save）。
        // 事务边界：批量入库失败回滚本批已写文件（MediaLifecycleService.commitImportBatch）；
        // 单张加载/写文件失败仅影响该张，不影响其余。
        var pending: [(data: Data, path: String, photo: Photo)] = []

        /// 入库当前攒批并执行自动归属；批量入库失败计数回本批数量（文件已回滚）。
        func flushPending() async {
            guard !pending.isEmpty else { return }
            let batch = pending
            pending = []
            let photos = batch.map { $0.photo }
            let paths = batch.map { $0.path }
            do {
                try await mediaLifecycle.commitImportBatch(photos: photos, paths: paths)
                imported += photos.count
                // 自动归属（对应源端 importPhotos 中 matchFromEmbedding → assignPhotoToPet）：
                // 仅对成功入库的照片执行；提取/匹配失败不影响导入
                for (index, photo) in photos.enumerated() {
                    if let matcher, let match = await resolveAutoMatch(matcher: matcher, imageData: batch[index].data) {
                        do {
                            if let pet = try petRepo.getPet(id: match.petID) {
                                try photoRepo.assignPhoto(photo, to: pet)
                                try petRepo.refreshPhotoCount(for: pet)
                                matched += 1
                            }
                        } catch {
                            logger.warning("importPhotos: 自动归属写入失败（\(error.localizedDescription)）")
                        }
                    }
                }
            } catch {
                failed += photos.count
                logger.error("importPhotos: 批量入库失败（\(error.localizedDescription)），本批 \(photos.count) 张文件已回滚")
            }
        }

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
                    // IOSPhotoLibraryAccess 无公开 fileSize API（恒为 0），
                    // 这里以实际写入数据大小兜底（诚实标注）。
                    fileSize: (metadata?.fileSize ?? 0) > 0 ? (metadata?.fileSize ?? 0) : Int64(imageData.count),
                    category: PhotoCategory.petPhoto.rawValue,
                    subCategory: "other"
                )

                // 写沙盒副本文件；入库延后到攒批 flush（L2 批量事务）
                try await fileStorage.write(imageData, to: sandboxPath)
                pending.append((data: imageData, path: sandboxPath, photo: photo))
                if pending.count >= ScanConfig.importFlushBatchSize {
                    await flushPending()
                }
            } catch {
                // 单张导入失败不阻止后续（批量版：入库失败的整批已在 flush 内回滚文件）；
                // H4：失败计数 + 日志保证可观测，避免静默丢照片
                failed += 1
                logger.error("importPhotos: 单张导入失败（\(AppErrorHandler.redactIdentifier(identifier))，\(error.localizedDescription)）")
                continue
            }

            onProgress?(ImportProgress(current: index + 1, total: total))
            TaskLogger.progress(taskId, current: index + 1, total: total)
        }
        // 尾批入库（含取消中断：已写文件不丢弃，避免孤儿）
        await flushPending()

        taskOutcome = Task.isCancelled ? .canceled : .success
        taskSummary = "requested=\(identifiers.count) imported=\(imported) failed=\(failed) matched=\(matched)"
        logger.info("importPhotos: imported=\(imported), failed=\(failed), matched=\(matched)")
        return ImportResult(imported: imported, matched: matched, failed: failed)
    }

    /// 自动归属判定：提取 embedding + 颜色签名 → PetMatcher 匹配。
    /// 任一步失败返回 nil（不阻止导入，对应源端 importPhotos 失败容错）。
    private func resolveAutoMatch(matcher: PetMatcher, imageData: Data) async -> PetMatchResult? {
        let extraction: (kind: PetEmbeddingKind, embedding: [Float])?
        do {
            extraction = try await matcher.extractEmbedding(imageData: imageData)
        } catch {
            logger.warning("importPhotos: embedding 提取失败，跳过自动归属（\(error.localizedDescription)）")
            return nil
        }
        guard let extraction, extraction.embedding.count == ClipConstants.embeddingDim else {
            return nil
        }
        // 颜色签名失败时跳过颜色约束（匹配仍可进行）
        let colorSignature = await matcher.extractMatchColorSignature(imageData: imageData)
        // 手工特征（fallback）放宽阈值，与源端 ScanControlMath.resolveMatchThreshold 一致
        let threshold = ScanControlMath.resolveMatchThreshold(matchRequired: extraction.kind == .fallback)
        return await matcher.matchFromEmbedding(
            embedding: extraction.embedding,
            threshold: Float(threshold),
            colorSignature: colorSignature,
            kind: extraction.kind)
    }
}
