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
//  自动匹配已注册宠物（PetMatcher）V1.0 未实现，matchedCount 恒为 0。

import Foundation
import os

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
    }

    /// 扫描系统相册，检测宠物照片。支持取消。
    /// - Parameters:
    ///   - afterTimestamp: 增量扫描游标——仅处理 dateAdded >= 此时间的照片
    ///     （nil = 全量扫描；iOS 上 dateAdded 以 creationDate 近似，见 ScanCursorStore）。
    ///   - onProgress: 进度回调（在 main actor 上调用）
    /// - Returns: 扫描结果（matchedCount 始终为 0——V1.0 未实现 PetMatcher 自动匹配）。
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

        let existingOriginalURIs: Set<String>
        do {
            existingOriginalURIs = try photoRepo.getAllOriginalURIs()
        } catch {
            return ScanResult(error: "读取已导入照片失败")
        }

        let totalCount: Int
        do {
            totalCount = try await photoLibrary.photoCount()
        } catch {
            return ScanResult(error: "读取照片数量失败")
        }

        var scanned = 0
        var processedCount = 0
        var petPhotosFound = 0
        var unassignedURIs: [String] = []
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
                        petPhotosFound: petPhotosFound, matchedCount: 0,
                        currentIdentifier: asset.identifier))
                    return true
                }

                // 仅扫描新增模式：跳过过旧的照片
                if let after = afterTimestamp {
                    if let added = asset.dateAdded, added < after {
                        onProgress?(ScanProgress(
                            scanned: scanned, total: totalCount,
                            petPhotosFound: petPhotosFound, matchedCount: 0,
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
            return ScanResult(
                matchedCount: 0,
                unassignedPetUris: unassignedURIs,
                processedCount: processedCount,
                canceled: Task.isCancelled,
                error: Task.isCancelled ? nil : "扫描中断"
            )
        }

        // 阶段 2：候选分批（每批 maxConcurrent 个）经后台执行器分析，结果回 MainActor 汇总。
        let batchSize = executor.maxConcurrent
        var batchStart = 0
        while batchStart < candidates.count {
            if Task.isCancelled { break }
            let batchEnd = min(batchStart + batchSize, candidates.count)
            let batch = Array(candidates[batchStart..<batchEnd])
            batchStart = batchEnd

            let results = await analyzeBatch(batch)
            for identifier in batch {
                if results[identifier] == true {
                    petPhotosFound += 1
                    unassignedURIs.append(identifier)
                }
                processedCount += 1
                onProgress?(ScanProgress(
                    scanned: scanned, total: totalCount,
                    petPhotosFound: petPhotosFound, matchedCount: 0,
                    currentIdentifier: identifier))
            }

            // 冷却（防止 CPU 过热，对应源端 COOLDOWN）；sleep 失败即任务被取消，结束扫描
            if processedCount % ScanConfig.cooldownBatchSize == 0 {
                do {
                    try await Task.sleep(for: ScanConfig.cooldownInterval)
                } catch {
                    break
                }
            }
        }

        return ScanResult(
            matchedCount: 0,
            unassignedPetUris: unassignedURIs,
            processedCount: processedCount,
            canceled: Task.isCancelled
        )
    }

    /// 并发分析一批候选（每批提交 maxConcurrent 个任务，内部排队由执行器保证）。
    /// - Returns: identifier → 是否为宠物照片。
    private func analyzeBatch(_ batch: [String]) async -> [String: Bool] {
        await withTaskGroup(of: (String, Bool).self) { group in
            for identifier in batch {
                group.addTask {
                    let isPet = await self.analyzeOne(identifier)
                    return (identifier, isPet)
                }
            }
            var results: [String: Bool] = [:]
            for await (identifier, isPet) in group {
                results[identifier] = isPet
            }
            return results
        }
    }

    /// 分析单张照片：读数据 → Phase 1 Vision 预筛 → Phase 2 CLIP 精筛（可选，失败降级）。
    /// 整段经 AnalysisExecutor 在后台执行（像素解码/推理不占 MainActor）。
    private func analyzeOne(_ identifier: String) async -> Bool {
        let photoLibrary = self.photoLibrary
        let vision = self.vision
        let clipService = self.clipService
        let executor = self.executor
        // 执行器异常视为单张失败（不收录，不中断扫描），记录错误便于诊断
        do {
            return try await executor.run {
                let imageData: Data
                do {
                    imageData = try await photoLibrary.loadImageData(
                        forIdentifier: identifier,
                        maxDimension: ScanConfig.detectInputSize
                    )
                } catch {
                    self.logger.error("analyzeOne: 读取照片失败（\(identifier)，\(error.localizedDescription)）")
                    return false
                }
                let detections: [DetectionBox]
                do {
                    detections = try await vision.detectPets(in: imageData)
                } catch {
                    self.logger.error("analyzeOne: 宠物预筛失败（\(identifier)，\(error.localizedDescription)）")
                    detections = []
                }
                guard !detections.isEmpty else { return false }
                // CLIP 不可用或推理失败时降级为 Phase 1 预筛结论（不中断扫描，对应源端多级降级）
                guard let clipService else { return true }
                let result: ClipDetectionResult
                do {
                    result = try await clipService.detect(imageData: imageData)
                } catch {
                    self.logger.error("analyzeOne: CLIP 精筛失败（\(identifier)，\(error.localizedDescription)），降级为 Phase 1 结论")
                    return true
                }
                return result.isPet
            }
        } catch {
            self.logger.error("analyzeOne: 执行器异常（\(identifier)，\(error.localizedDescription)）")
            return false
        }
    }
}
