//  ScanService —— Photos 全库扫描编排（对应源端 services/PhotoScanner.ets scanAlbum）。
//
//  设计要点（DESIGN.md §7 硬约束）：
//  - 扫描只筛选不入库——检测到的宠物照片收集到 unassignedPetUris，
//    由用户手动「导入」才入库（ImportService.insertPhoto 是唯一入库路径）。
//  - 支持取消（Task.cancel → Task.isCancelled 检查点）。
//  - 依赖通过协议注入，mock 可覆盖（ADR-0007 §2.1 分层）。
//
//  两阶段检测（诚实标注）：
//  - Phase 1：VisionService 预筛（VNClassifyImageRequest 宠物标签匹配，宽松）；
//  - Phase 2：ClipInferenceService 精筛（模型缺失/失败时降级为 Phase 1 结论）。
//  自动匹配已注册宠物（PetMatcher）V1.0 未实现，matchedCount 恒为 0。

import Foundation

/// 扫描服务（@MainActor——PhotoRepository/PetRepository 均为 @MainActor 隔离）。
@MainActor
final class ScanService {

    private let photoLibrary: any PhotoLibraryAccess
    private let vision: any VisionService
    private let photoRepo: any PhotoRepositoryProtocol
    private let petRepo: any PetRepositoryProtocol
    /// Phase 2 精筛（nil = CLIP 模型缺失，仅 Phase 1 预筛结果生效）
    private let clipService: (any ClipInference)?

    /// 当前是否正在扫描（对应源端 isScanning）
    private(set) var isScanning = false

    init(photoLibrary: any PhotoLibraryAccess,
         vision: any VisionService,
         photoRepo: any PhotoRepositoryProtocol,
         petRepo: any PetRepositoryProtocol,
         clipService: (any ClipInference)? = nil) {
        self.photoLibrary = photoLibrary
        self.vision = vision
        self.photoRepo = photoRepo
        self.petRepo = petRepo
        self.clipService = clipService
    }

    /// 扫描系统相册，检测宠物照片。支持取消。
    /// - Parameters:
    ///   - afterTimestamp: 增量扫描游标——仅处理 dateAdded >= 此时间的照片
    ///     （nil = 全量扫描；iOS 上 dateAdded 以 creationDate 近似，见 ScanCursorStore）。
    ///   - onProgress: 进度回调（在 main actor 上调用）
    /// - Returns: 扫描结果（matchedCount 始终为 0——V1.0 未实现 PetMatcher 自动匹配）
    @discardableResult
    func scanAlbum(
        afterTimestamp: Date? = nil,
        onProgress: (@MainActor (ScanProgress) -> Void)? = nil
    ) async -> ScanResult {
        guard !isScanning else {
            return ScanResult()
        }
        isScanning = true
        defer { isScanning = false }

        let existingOriginalURIs: Set<String>
        do {
            existingOriginalURIs = try photoRepo.getAllOriginalURIs()
        } catch {
            return ScanResult()
        }

        let totalCount: Int
        do {
            totalCount = try await photoLibrary.photoCount()
        } catch {
            return ScanResult()
        }

        var scanned = 0
        var processedCount = 0
        var petPhotosFound = 0
        var unassignedURIs: [String] = []

        do {
            _ = try await photoLibrary.streamPhotos { [self] asset in
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

                processedCount += 1

                // 两阶段检测：Phase 1 VisionService 预筛（宽松）→ Phase 2 CLIP 精筛（可选，失败降级）
                if let imageData = try? await photoLibrary.loadImageData(
                    forIdentifier: asset.identifier,
                    maxDimension: ScanConfig.detectInputSize
                ) {
                    let detections = (try? await vision.detectPets(in: imageData)) ?? []
                    if !detections.isEmpty,
                       await confirmPetWithClipIfAvailable(imageData) {
                        petPhotosFound += 1
                        unassignedURIs.append(asset.identifier)
                    }
                }

                // 冷却（防止 CPU 过热，对应源端 COOLDOWN）
                if processedCount % ScanConfig.cooldownBatchSize == 0 {
                    try? await Task.sleep(for: ScanConfig.cooldownInterval)
                }

                onProgress?(ScanProgress(
                    scanned: scanned, total: totalCount,
                    petPhotosFound: petPhotosFound, matchedCount: 0,
                    currentIdentifier: asset.identifier))
                return true
            }
        } catch {
            // streamPhotos 抛错时仍返回已收集的结果
        }

        return ScanResult(
            matchedCount: 0,
            unassignedPetUris: unassignedURIs,
            processedCount: processedCount,
            canceled: Task.isCancelled
        )
    }

    /// Phase 2 CLIP 精筛：预筛命中后进一步确认是否为宠物。
    /// CLIP 不可用或推理失败时降级为 Phase 1 预筛结论（不中断扫描，对应源端多级降级）。
    private func confirmPetWithClipIfAvailable(_ imageData: Data) async -> Bool {
        guard let clipService else { return true }
        guard let result = try? await clipService.detect(imageData: imageData) else {
            return true
        }
        return result.isPet
    }
}
