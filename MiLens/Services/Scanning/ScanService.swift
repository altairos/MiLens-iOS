//  ScanService —— Photos 全库扫描编排（对应源端 services/PhotoScanner.ets scanAlbum）。
//
//  设计要点（DESIGN.md §7 硬约束）：
//  - 扫描只筛选不入库——检测到的宠物照片收集到 unassignedPetUris，
//    由用户手动「导入」才入库（ImportService.insertPhoto 是唯一入库路径）。
//  - 支持取消（Task.cancel → Task.isCancelled 检查点）。
//  - 依赖通过协议注入，mock 可覆盖（ADR-0007 §2.1 分层）。
//
//  V1.0 降级说明：Core ML 模型尚未就绪时，VisionService 使用系统 Vision API
//  做 pet detection（VNClassifyImageRequest / VNRecognizeAnimalsRequest），精度有限。

import Foundation

/// 扫描服务（@MainActor——PhotoRepository/PetRepository 均为 @MainActor 隔离）。
@MainActor
final class ScanService {

    private let photoLibrary: any PhotoLibraryAccess
    private let vision: any VisionService
    private let photoRepo: any PhotoRepositoryProtocol
    private let petRepo: any PetRepositoryProtocol

    /// 当前是否正在扫描（对应源端 isScanning）
    private(set) var isScanning = false

    init(photoLibrary: any PhotoLibraryAccess,
         vision: any VisionService,
         photoRepo: any PhotoRepositoryProtocol,
         petRepo: any PetRepositoryProtocol) {
        self.photoLibrary = photoLibrary
        self.vision = vision
        self.photoRepo = photoRepo
        self.petRepo = petRepo
    }

    /// 扫描系统相册，检测宠物照片。支持取消。
    /// - Parameters:
    ///   - afterTimestamp: 仅扫描此时间之后新增的照片（nil = 全量扫描）
    ///   - onProgress: 进度回调（在 main actor 上调用）
    /// - Returns: 扫描结果（matchedCount 始终为 0——V1.0 扫描不做自动匹配）
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

        let existingURIs: Set<String>
        do {
            existingURIs = try photoRepo.getAllPhotoURIs()
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

                // 跳过已导入的照片（去重）
                if existingURIs.contains(asset.identifier) {
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

                // 加载缩略图数据用于 AI 检测
                if let imageData = try? await photoLibrary.loadImageData(
                    forIdentifier: asset.identifier,
                    maxDimension: ScanConfig.detectInputSize
                ) {
                    // 两阶段检测（VisionService 内部实现 Phase1 prefilter + Phase2 CLIP）
                    let detections = (try? await vision.detectPets(in: imageData)) ?? []
                    if !detections.isEmpty {
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
}
