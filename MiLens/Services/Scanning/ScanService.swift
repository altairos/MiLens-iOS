//  ScanService —— Photos 全库扫描编排（对应源端 services/PhotoScanner.ets scanAlbum）。
//
//  设计要点（DESIGN.md §7 硬约束）：
//  - 扫描只筛选不入库——检测到的宠物照片收集到 unassignedPetUris，
//    由用户手动「导入」才入库（ImportService.insertPhoto 是唯一入库路径）。
//  - 支持取消（Task.cancel → Task.isCancelled 检查点）。
//  - 依赖通过协议注入，mock 可覆盖（ADR-0007 §2.1 分层）。
//
//  两阶段执行（P1 性能重构，像素计算不占 MainActor）：
//  - 阶段 1（MainActor 轻量）：streamPhotos consumer 只做已导入/过旧判断 +
//    收集候选 identifiers + 跳过路径的进度回调（O(1) 操作）。
//  - 阶段 2：候选分批（每批 maxConcurrent 个）经 AnalysisExecutor 受限并发
//    后台执行 loadImageData → detectPets → CLIP detect；结果回 MainActor 汇总
//    unassignedURIs + 进度 + 冷却。进度回调次数仍按照片数（跳过/候选各一次）。
//
//  两阶段检测（诚实标注）：
//  - Phase 1：VisionService 预筛（VNClassifyImageRequest 宠物标签匹配，宽松）；
//  - Phase 2：ClipInferenceService 精筛（模型缺失/失败时降级为 Phase 1 结论）。
//  自动归属（PetMatcher）：扫描阶段做只读预匹配——复用 CLIP 同一次推理的 512 维
//  embedding + 14 维颜色签名，匹配已注册宠物的照片计入 matchedCount/matchedUris，
//  未匹配的宠物照片收集到 unassignedPetUris 由用户手动导入；真正归属写入
//  （assignPhoto）仍在导入阶段（ImportService → matchFromEmbedding，唯一入库路径）。

import Foundation
import os
import MiLensKit

/// 扫描服务（@MainActor——PhotoRepository/PetRepository 均为 @MainActor 隔离）。
@MainActor
final class ScanService {

    private let logger = Logger(subsystem: "com.milens.app", category: "Scan")

    private let photoLibrary: any PhotoLibraryAccess
    private let vision: any VisionService
    private let photoRepo: any PhotoRepositoryProtocol
    private let petRepo: any PetRepositoryProtocol
    /// Phase 2 精筛（nil = CLIP 模型缺失，仅 Phase 1 预筛结果生效）
    private let clipService: (any ClipInference)?
    /// 自动归属预匹配（clipService 为 nil 时不创建——无模型可提取 embedding）。
    /// 扫描阶段只读匹配不写库；真正归属写入在 ImportService 导入时完成。
    private let matcher: PetMatcher?
    /// 受限并发后台执行器（阶段 2 的读文件 + 解码 + 检测在此执行，不占 MainActor）
    private let executor: AnalysisExecutor

    /// 当前是否正在扫描（对应源端 isScanning）
    private(set) var isScanning = false

    init(photoLibrary: any PhotoLibraryAccess,
         vision: any VisionService,
         photoRepo: any PhotoRepositoryProtocol,
         petRepo: any PetRepositoryProtocol,
         clipService: (any ClipInference)? = nil,
         executor: AnalysisExecutor = AnalysisExecutor()) {
        self.photoLibrary = photoLibrary
        self.vision = vision
        self.photoRepo = photoRepo
        self.petRepo = petRepo
        self.clipService = clipService
        self.executor = executor
        self.matcher = clipService.map {
            PetMatcher(petRepo: petRepo, clipService: $0, executor: executor)
        }
    }

    /// 扫描系统相册，检测宠物照片。支持取消。
    /// - Parameters:
    ///   - afterTimestamp: 增量扫描游标——仅处理 dateAdded >= 此时间的照片
    ///     （nil = 全量扫描；iOS 上 dateAdded 以 creationDate 近似，见 ScanCursorStore）。
    ///   - onProgress: 进度回调（在 main actor 上调用）
    /// - Returns: 扫描结果（matchedCount = 预匹配到已注册宠物的照片数，matchedUris 为对应
    ///   identifier 列表——只读预判，照片尚未入库；unassignedPetUris 为未匹配的宠物照片）。
    ///   注意：失败路径（error != nil）不代表完整遍历——上层不得保存增量游标。
    @discardableResult
    func scanAlbum(
        afterTimestamp: Date? = nil,
        onProgress: (@MainActor (ScanProgress) -> Void)? = nil
    ) async -> ScanResult {
        guard !isScanning else {
            return ScanResult(error: "已有扫描在进行")
        }
        isScanning = true
        defer { isScanning = false }

        // H1 结构化任务日志：扫描全过程记录，供 DiagnosticsCollector 汇总与线上诊断
        let taskId = TaskLogger.beginTask(.scan, label: afterTimestamp == nil ? "full" : "incremental")
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
        TaskLogger.stage(taskId, "collect-candidates")

        let existingOriginalURIs: Set<String>
        do {
            existingOriginalURIs = try photoRepo.getAllOriginalURIs()
        } catch {
            taskOutcome = .failed
            taskSummary = "读取已导入照片失败"
            return ScanResult(error: "读取已导入照片失败")
        }

        let totalCount: Int
        do {
            totalCount = try await photoLibrary.photoCount()
        } catch {
            taskOutcome = .failed
            taskSummary = "读取照片数量失败"
            return ScanResult(error: "读取照片数量失败")
        }

        var scanned = 0
        var processedCount = 0
        var petPhotosFound = 0
        var matchedCount = 0
        var unassignedURIs: [String] = []
        var matchedURIs: [String] = []
        // 阶段 2 待分析的候选 identifiers（已通过已导入/过旧过滤）
        var candidates: [String] = []

        // 阶段 1（MainActor，轻量）：只做过滤 + 收集候选 + 跳过路径的进度回调。
        // consumer 闭包继承 MainActor，但只执行 O(1) 操作，不再触碰像素数据。
        do {
            _ = try await photoLibrary.streamPhotos { asset in
                // 取消检查点（对应源端 shouldCancel）
                if Task.isCancelled { return false }

                scanned += 1

                // 跳过已导入的照片（按 originalURI 去重——uri 是沙盒副本路径，不能与 identifier 比较）
                if existingOriginalURIs.contains(asset.identifier) {
                    onProgress?(ScanProgress(
                        scanned: scanned, total: totalCount,
                        petPhotosFound: petPhotosFound, matchedCount: matchedCount,
                        currentIdentifier: asset.identifier))
                    return true
                }

                // 仅扫描新增模式：跳过过旧的照片
                if let after = afterTimestamp {
                    if let added = asset.dateAdded, added < after {
                        onProgress?(ScanProgress(
                            scanned: scanned, total: totalCount,
                            petPhotosFound: petPhotosFound, matchedCount: matchedCount,
                            currentIdentifier: asset.identifier))
                        return true
                    }
                }

                // 候选进入阶段 2 统一分析（进度回调延后到分析完成时发出，petPhotosFound 实时准确）
                candidates.append(asset.identifier)
                return true
            }
        } catch {
            // streamPhotos 抛错：保留已收集结果，但标记失败——
            // 未完整遍历全部照片，上层不得保存增量游标。
            // 用户取消（CancellationError）优先记为 canceled（error 为 nil）。
            taskOutcome = Task.isCancelled ? .canceled : .failed
            taskSummary = "阶段1收集中断"
            return ScanResult(
                matchedCount: matchedCount,
                unassignedPetUris: unassignedURIs,
                matchedUris: matchedURIs,
                processedCount: processedCount,
                canceled: Task.isCancelled,
                error: Task.isCancelled ? nil : "扫描中断"
            )
        }

        // 阶段 2：候选分批（每批 maxConcurrent 个）经后台执行器分析，结果回 MainActor 汇总。
        TaskLogger.stage(taskId, "analyze")
        let batchSize = executor.maxConcurrent
        var batchStart = 0
        while batchStart < candidates.count {
            if Task.isCancelled { break }
            let batchEnd = min(batchStart + batchSize, candidates.count)
            let batch = Array(candidates[batchStart..<batchEnd])
            batchStart = batchEnd

            let results = await analyzeBatch(batch)
            for identifier in batch {
                guard let analysis = results[identifier] else { continue }
                if analysis.isPet {
                    petPhotosFound += 1
                    if analysis.matchedPetID != nil {
                        matchedCount += 1
                        matchedURIs.append(identifier)
                    } else {
                        unassignedURIs.append(identifier)
                    }
                }
                processedCount += 1
                onProgress?(ScanProgress(
                    scanned: scanned, total: totalCount,
                    petPhotosFound: petPhotosFound, matchedCount: matchedCount,
                    currentIdentifier: identifier))
            }
            TaskLogger.progress(taskId, current: processedCount, total: candidates.count)

            // 冷却（防止 CPU 过热，对应源端 COOLDOWN）；sleep 失败即任务被取消，结束扫描
            if processedCount % ScanConfig.cooldownBatchSize == 0 {
                do {
                    try await Task.sleep(for: ScanConfig.cooldownInterval)
                } catch {
                    break
                }
            }
        }

        taskOutcome = Task.isCancelled ? .canceled : .success
        taskSummary = "candidates=\(candidates.count) processed=\(processedCount) "
            + "petPhotos=\(petPhotosFound) matched=\(matchedCount)"
        return ScanResult(
            matchedCount: matchedCount,
            unassignedPetUris: unassignedURIs,
            matchedUris: matchedURIs,
            processedCount: processedCount,
            canceled: Task.isCancelled
        )
    }

    /// 并发分析一批候选（每批提交 maxConcurrent 个任务，内部排队由执行器保证）。
    /// - Returns: identifier → 分析结果（是否为宠物 + 预匹配宠物 ID）。
    private func analyzeBatch(_ batch: [String]) async -> [String: ScanAnalysisResult] {
        await withTaskGroup(of: (String, ScanAnalysisResult).self) { group in
            for identifier in batch {
                group.addTask {
                    let analysis = await self.analyzeOne(identifier)
                    return (identifier, analysis)
                }
            }
            var results: [String: ScanAnalysisResult] = [:]
            for await (identifier, analysis) in group {
                results[identifier] = analysis
            }
            return results
        }
    }

    /// 分析单张照片：读数据 → Phase 1 Vision 预筛 → Phase 2 CLIP 精筛（可选，失败降级）
    /// → 自动归属预匹配（只读，不写库；真正归属在导入时写入）。
    /// 像素段（解码/预筛/CLIP/颜色签名）经 AnalysisExecutor 后台执行；
    /// PetMatcher 匹配回 MainActor（PetMatcher 为 @MainActor 隔离）。
    private func analyzeOne(_ identifier: String) async -> ScanAnalysisResult {
        let photoLibrary = self.photoLibrary
        let vision = self.vision
        let clipService = self.clipService
        let executor = self.executor
        // 执行器异常视为单张失败（不收录，不中断扫描），记录错误便于诊断
        let extraction: (isPet: Bool, embedding: [Float], colorSignature: [Float]?)?
        do {
            extraction = try await executor.run {
                let imageData: Data
                do {
                    imageData = try await photoLibrary.loadImageData(
                        forIdentifier: identifier,
                        maxDimension: ScanConfig.detectInputSize
                    )
                } catch {
                    self.logger.error("analyzeOne: 读取照片失败（\(AppErrorHandler.redactIdentifier(identifier))，\(error.localizedDescription)）")
                    return (false, [], nil)
                }
                let detections: [DetectionBox]
                do {
                    detections = try await vision.detectPets(in: imageData)
                } catch {
                    self.logger.error("analyzeOne: 宠物预筛失败（\(AppErrorHandler.redactIdentifier(identifier))，\(error.localizedDescription)）")
                    detections = []
                }
                guard !detections.isEmpty else { return (false, [], nil) }
                // CLIP 不可用或推理失败时降级为 Phase 1 预筛结论（不中断扫描，对应源端多级降级）
                guard let clipService else { return (true, [], nil) }
                let result: ClipDetectionResult
                do {
                    result = try await clipService.detect(imageData: imageData)
                } catch {
                    self.logger.error("analyzeOne: CLIP 精筛失败（\(AppErrorHandler.redactIdentifier(identifier))，\(error.localizedDescription)），降级为 Phase 1 结论")
                    return (true, [], nil)
                }
                guard result.isPet else { return (false, [], nil) }
                // 宠物照片：复用本次推理的 embedding 预匹配（embedding 为空 = 不可匹配）
                var colorSignature: [Float]?
                if !result.embedding.isEmpty {
                    colorSignature = extractColorSignature(imageData: imageData)
                }
                return (true, result.embedding, colorSignature)
            }
        } catch {
            self.logger.error("analyzeOne: 执行器异常（\(AppErrorHandler.redactIdentifier(identifier))，\(error.localizedDescription)）")
            return ScanAnalysisResult(isPet: false, matchedPetID: nil)
        }
        guard let extraction, extraction.isPet else {
            return ScanAnalysisResult(isPet: false, matchedPetID: nil)
        }
        // 自动归属预匹配（只读）：仅对有效 embedding 执行；未注册宠物/未达阈值返回 nil，
        // 照片仍进 unassigned 由用户决定是否导入（与 ImportService 判定一致）。
        var matchedPetID: UUID?
        if let matcher, !extraction.embedding.isEmpty {
            if let match = await matcher.matchFromEmbedding(
                embedding: extraction.embedding,
                colorSignature: extraction.colorSignature,
                kind: .clip
            ) {
                matchedPetID = match.petID
                logger.info("analyzeOne: 预匹配宠物（\(AppErrorHandler.redactIdentifier(identifier))，score=\(String(format: "%.4f", match.score))）")
            }
        }
        return ScanAnalysisResult(isPet: true, matchedPetID: matchedPetID)
    }
}

/// 单张照片分析结果（阶段 2 汇总用）。
private struct ScanAnalysisResult: Sendable {
    let isPet: Bool
    /// 自动归属预匹配的宠物 ID（nil = 未匹配或不可匹配）
    let matchedPetID: UUID?
}

/// 从照片数据提取 14 维颜色签名（CPU 密集，仅在后台执行器闭包内调用）；
/// 失败返回 nil（匹配时跳过颜色约束，与 PetMatcher.extractMatchColorSignature 一致）。
/// 文件级函数（非 MainActor 隔离），供后台闭包调用。
private func extractColorSignature(imageData: Data) -> [Float]? {
    guard let (pixels, width, height) = ClipInferenceService.decodeToRGBA(
        imageData, maxDimension: ClipConstants.detectInputSize) else {
        return nil
    }
    return ColorSignatureMath.computeColorSignature(
        pixelBytes: pixels, width: width, height: height,
        dim: PetMatchThreshold.colorSignatureDim)
}
