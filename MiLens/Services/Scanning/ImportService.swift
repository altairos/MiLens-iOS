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
    /// 因免费版配额上限被拦截的数量（ADR-0010）。
    /// > 0 表示有照片因配额未导入，调用方应引导付费墙。
    let quotaBlocked: Int
    /// 本次实际导入入库的照片 ID（精确归属用，避免按「未分配照片/列表前 N 条」推断）。
    /// 调用方应据此对精确记录执行批量归属，而非按数量猜测。
    let importedPhotoIDs: [UUID]
    /// 用户是否在导入过程中取消（部分照片可能已入库）。
    /// true 时调用方应区分提示「已取消」，不要当普通成功完成处理。
    let cancelled: Bool

    init(imported: Int, matched: Int, failed: Int, quotaBlocked: Int = 0,
        importedPhotoIDs: [UUID] = [], cancelled: Bool = false) {
        self.imported = imported
        self.matched = matched
        self.failed = failed
        self.quotaBlocked = quotaBlocked
        self.importedPhotoIDs = importedPhotoIDs
        self.cancelled = cancelled
    }

    /// 是否因配额被拦截（需调用方引导付费）。
    var hitQuota: Bool { quotaBlocked > 0 }
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
    /// Pro 权益状态（ADR-0010 照片配额检查）。
    private var isPro: Bool

    /// 当前是否正在导入
    private(set) var isImporting = false

    init(photoLibrary: any PhotoLibraryAccess,
         fileStorage: any FileStorage,
         photoRepo: any PhotoRepositoryProtocol,
         mediaLifecycle: MediaLifecycleService,
         sandboxDir: String,
         petRepo: any PetRepositoryProtocol,
         clipService: (any ClipInference)? = nil,
         executor: AnalysisExecutor = AnalysisExecutor(),
         isPro: Bool = false) {
        self.photoLibrary = photoLibrary
        self.fileStorage = fileStorage
        self.photoRepo = photoRepo
        self.petRepo = petRepo
        self.mediaLifecycle = mediaLifecycle
        self.sandboxDir = sandboxDir
        self.executor = executor
        self.isPro = isPro
        self.matcher = clipService.map {
            PetMatcher(petRepo: petRepo, clipService: $0, executor: executor)
        }
    }

    /// 更新 Pro 权益状态（设置页/购买回调后同步）。
    func updateProStatus(_ isPro: Bool) {
        self.isPro = isPro
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
        // 候选列表：有序去重（保留输入顺序）→ 排除已导入 → 限制批量上限。
        // 先确定"真正会处理的 identifier"再计算配额，避免重复 identifier 或
        // 已有项被误算为配额超额（修复缺陷：免费用户已有 49 张时传入两次同一个
        // 新 ID 会被算成请求 2 张、拦截 1 张，但实际只有一张唯一照片）。
        var candidates: [String] = []
        var seenInBatch: Set<String> = []
        for identifier in identifiers {
            guard seenInBatch.insert(identifier).inserted else { continue }
            guard !existingOriginalURIs.contains(identifier) else { continue }
            candidates.append(identifier)
        }
        let batchCandidates = Array(candidates.prefix(ScanConfig.maxImportBatch))

        // ADR-0010 照片配额检查：免费版上限 50 张。
        // 基于候选列表（已去重/排除已有/限制批量）计算，而非完整输入——
        // 批次截断不会错误归因为配额拦截。
        let currentCount = (try? photoRepo.countAllPhotos()) ?? 0
        let allowed = CommercialRules.allowedImportCount(
            currentCount: currentCount, requestCount: batchCandidates.count, isPro: isPro)
        let quotaBlocked = batchCandidates.count - allowed
        if quotaBlocked > 0 {
            logger.info("importPhotos: 配额拦截——已存 \(currentCount)，候选 \(batchCandidates.count)，允许 \(allowed)，拦截 \(quotaBlocked)")
        }

        var imported = 0
        var matched = 0
        var failed = 0
        var importedPhotoIDs: [UUID] = []
        let total = batchCandidates.count

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
                importedPhotoIDs.append(contentsOf: photos.map(\.id))
                // quotaRemaining 已在加入 pending 时即时递减，此处不再扣减（避免双重扣减）
                // 自动归属（对应源端 importPhotos 中 matchFromEmbedding → assignPhotoToPet）：
                // 仅对成功入库的照片执行；提取/匹配失败不影响导入。
                // 先按目标宠物分组收集匹配结果，再用 batchAssignPhotos 原子提交
                // （与手动归属/引导归属统一：单次事务内关系 + 计数原子写入，
                //   避免逐张 assignPhoto + refreshPhotoCount 部分失败导致计数不一致）。
                if let matcher {
                    var matchesByPet: [UUID: [Photo]] = [:]
                    for (index, photo) in photos.enumerated() {
                        guard let match = await resolveAutoMatch(
                            matcher: matcher, imageData: batch[index].data) else { continue }
                        matchesByPet[match.petID, default: []].append(photo)
                    }
                    for (petID, photosForPet) in matchesByPet {
                        guard let pet = try? petRepo.getPet(id: petID) else { continue }
                        do {
                            try photoRepo.batchAssignPhotos(photosForPet, to: pet)
                            matched += photosForPet.count
                        } catch {
                            logger.warning("importPhotos: 自动归属批量写入失败（\(error.localizedDescription)）")
                        }
                    }
                }
            } catch {
                failed += photos.count
                logger.error("importPhotos: 批量入库失败（\(error.localizedDescription)），本批 \(photos.count) 张文件已回滚")
            }
        }

        // 配额计数器：达到允许上限后停止入库（仅免费版生效，Pro 时 allowed == batchCandidates.count）。
        var quotaRemaining = allowed

        // candidates 已有序去重、排除已导入、限制批量上限，循环内只需配额检查。
        for (index, identifier) in batchCandidates.enumerated() {
            if Task.isCancelled { break }

            // ADR-0010 配额耗尽：后续不再入库，但仍更新进度。
            if quotaRemaining <= 0 {
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
                // ADR-0010：配额即时扣减（在加入 pending 时递减，而非 flush 时），
                // 避免 32 张攒批窗口内配额检查形同虚设。
                quotaRemaining -= 1
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

        let wasCancelled = Task.isCancelled
        taskOutcome = wasCancelled ? .canceled : .success
        taskSummary = "requested=\(identifiers.count) imported=\(imported) failed=\(failed) matched=\(matched) quotaBlocked=\(quotaBlocked) cancelled=\(wasCancelled)"
        logger.info("importPhotos: imported=\(imported), failed=\(failed), matched=\(matched), quotaBlocked=\(quotaBlocked), cancelled=\(wasCancelled)")
        return ImportResult(imported: imported, matched: matched, failed: failed,
                            quotaBlocked: quotaBlocked, importedPhotoIDs: importedPhotoIDs,
                            cancelled: wasCancelled)
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
