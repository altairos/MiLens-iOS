//  EditorCutoutPanelVM —— 抠图工具子状态（M2 拆分，对应源端 EditorCutoutController）。
//  主体分割状态机（idle/processing/applied/error），决策走 MiLensKit EditorCutoutLogic；
//  失败即 error，无近似降级（诚实标注：不用中心裁切冒充 AI 分割）。

import Foundation
import MiLensKit
import Observation

@MainActor
@Observable
final class EditorCutoutPanelVM {

    private unowned let owner: EditorViewModel
    private let document: EditorDocumentController

    init(owner: EditorViewModel) {
        self.owner = owner
        self.document = owner.document
    }

    private(set) var phase: EditorCutoutPhase = .idle
    private(set) var status = ""
    private(set) var isFallback = false
    /// 抠图代数（startCutout 次数），配合 photoGeneration 做结果有效性守卫。
    private var generation = 0

    func start() async {
        let decision = canStartCutout(phase)
        guard decision.canStart else {
            status = decision.rejectReason
            return
        }
        guard let image = owner.photoImage, let layer = document.photoLayer() else { return }

        phase = .processing
        status = cutoutStatusText(.processing)
        generation += 1
        let currentGeneration = generation

        // 分割输入：当前显示图（含调色，对齐源端基于显示图分割）。
        guard let data = owner.imageProcessor.encode(
            image, format: resolveSaveFormat(hasAlpha: false)
        ) else {
            phase = .error
            status = "识别失败，可重试"
            return
        }

        let result: SegmentationResult?
        do {
            result = try await owner.visionService.segmentSubject(in: data)
        } catch {
            owner.logCutoutFailure(error)
            result = nil
        }
        let guardSnapshot = EditorCutoutGuard(
            pageActive: true,
            photoGeneration: owner.photoGeneration,
            cutoutGeneration: currentGeneration,
            targetLayerId: layer.id,
            layerExists: document.photoLayer() != nil
        )
        let valid = isCutoutResultValid(
            guardSnapshot,
            expectedPhotoGeneration: owner.photoGeneration,
            expectedCutoutGeneration: currentGeneration
        )
        // iOS 无近似降级（诚实标注：失败即 error，不用中心裁切冒充 AI 分割）。
        let resolved = resolveCutoutResult(isValid: valid, resultNull: result == nil, isFallback: false)
        isFallback = resolved.isFallback
        status = resolved.statusText
        phase = resolved.nextPhase

        if resolved.nextPhase == .applied, let seg = result, let baseImage = owner.baseImage,
           let applied = owner.imageProcessor.applyingCutoutMask(
               to: baseImage, mask: seg.mask, width: seg.bboxWidth, height: seg.bboxHeight
           ) {
            owner.baseImage = applied
            owner.photoGeneration += 1
            document.updateLayer(layer.id) { $0.hasAlpha = true }
            owner.saveFormat = resolveSaveFormat(hasAlpha: true)
            document.resetHistory()
            owner.refreshPhotoImage()
            owner.syncState()
        }
    }
}
