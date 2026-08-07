//  QualityScorer —— 质量评分 + 重复分组编排
//  （对应源端 services/QualityScorer.ets）。
//
//  DESIGN.md §4 分层：Service 编排 IO + 异常处理。
//  - computeAllQualityScores：分页读 pending → 解码 → sharpness + pHash → 质量公式 → 入库。
//  - findDuplicates：加载候选 → DuplicateGroupingLogic 纯逻辑 → 原子替换标记。
//
//  源端在 ScanController 扫描完成后 fire-and-forget 调用本服务。

import Foundation

/// 质量评分 + 重复分组服务（@MainActor——PhotoRepository 为 @MainActor 隔离）。
@MainActor
final class QualityScorer {

    private let photoRepo: any PhotoRepositoryProtocol
    private let imageAnalyzer: any ImageAnalyzer
    private let fileStorage: any FileStorage

    /// 单次评分批量的上限（对应源端 `pageSize = 100`）。
    private let batchSize = 500

    init(photoRepo: any PhotoRepositoryProtocol,
         imageAnalyzer: any ImageAnalyzer,
         fileStorage: any FileStorage) {
        self.photoRepo = photoRepo
        self.imageAnalyzer = imageAnalyzer
        self.fileStorage = fileStorage
    }

    /// 计算所有待评分照片的质量评分（含 pHash 补算）。
    /// 对应源端 `QualityScorer.computeAllQualityScores`。
    /// - Returns: 实际计算成功的数量
    @discardableResult
    func computeAllQualityScores() async -> Int {
        var computed = 0
        let pending = (try? photoRepo.getPendingQualityScorePhotos(limit: batchSize)) ?? []
        for photo in pending {
            if Task.isCancelled { break }
            guard !photo.uri.isEmpty else { continue }
            do {
                let data = try await fileStorage.read(at: photo.uri)
                let sharpness = imageAnalyzer.computeSharpness(imageData: data)
                // pHash 补算：仅当尚未计算时（对应源端导入时计算，此处覆盖 pending 缺口）
                let phash = photo.phash.isEmpty
                    ? (imageAnalyzer.computePHash(imageData: data) ?? "")
                    : photo.phash
                let hasPet = photo.pet != nil
                let score = QualityScoringLogic.computeQualityScore(
                    sharpness: sharpness, hasPet: hasPet,
                    width: photo.width, height: photo.height)
                try photoRepo.updateQualityData(
                    photo, sharpness: sharpness, qualityScore: score, phash: phash)
                computed += 1
            } catch {
                // 单张失败不阻止后续（对应源端 AppErrorHandler.warn + continue）
                continue
            }
        }
        return computed
    }

    /// 重新计算并原子替换所有重复标记。
    /// 对应源端 `QualityScorer.findDuplicates`。
    /// - Returns: 重复组数量
    @discardableResult
    func findDuplicates() async -> Int {
        let candidates = (try? photoRepo.getDuplicateCandidates()) ?? []
        let projected = candidates.map { photo in
            DuplicateCandidate(
                id: photo.id, phash: photo.phash, qualityScore: photo.qualityScore,
                sharpness: photo.sharpness, width: photo.width, height: photo.height,
                fileSize: photo.fileSize)
        }
        let groups = DuplicateGroupingLogic.buildDuplicateGroups(projected)
        let marks = groups.map { group in
            DuplicateMarkGroup(bestID: group[0].id, duplicateIDs: group.dropFirst().map(\.id))
        }
        try? photoRepo.replaceDuplicateMarks(marks)
        return groups.count
    }

    /// 扫描后分析：先算质量评分，再找重复（对应源端 ScanController fire-and-forget 链）。
    func runPostScanAnalysis() async {
        _ = await computeAllQualityScores()
        _ = await findDuplicates()
    }
}
