//  EditorCropPanelVM —— 裁剪工具子状态（M2 拆分，对应源端 EditorCropController）。
//  裁剪区域 / 比例选择 / 确认（像素级，重置历史）/ 取消；决策走 MiLensKit EditorCropMath。

import CoreGraphics
import Foundation
import MiLensKit
import Observation

@MainActor
@Observable
final class EditorCropPanelVM {

    private unowned let owner: EditorViewModel
    private let document: EditorDocumentController

    init(owner: EditorViewModel) {
        self.owner = owner
        self.document = owner.document
    }

    private(set) var cropRect: EditorCropRect?
    private(set) var cropRatioIndex = 0

    func beginCrop() {
        let region = computeCropInitRegion(
            canvasW: owner.canvasSize.width, canvasH: owner.canvasSize.height,
            ratio: resolveCropRatioByIndex(cropRatioIndex)
        )
        cropRect = EditorCropRect(x: region.x, y: region.y, w: region.w, h: region.h)
    }

    func selectCropRatio(_ index: Int) {
        cropRatioIndex = index
        beginCrop()
    }

    func updateCropRect(_ rect: EditorCropRect) {
        cropRect = clampCropRect(
            canvasW: owner.canvasSize.width, canvasH: owner.canvasSize.height, rect: rect
        )
    }

    func cancelCrop() {
        cropRect = nil
        owner.tool = .none
        owner.syncState()
    }

    /// 确认裁剪：画布坐标 → 照片像素空间（computeCropRegion）→ 像素裁切。
    /// 像素级操作：更新底图、重置历史（iOS 差异，见 EditorViewModel 文件头注释）。
    func confirmCrop() {
        guard let cropRect, let baseImage = owner.baseImage else { return }
        let input = EditorCropInput(
            photoX: owner.canvasSize.width / 2, photoY: owner.canvasSize.height / 2,
            photoW: owner.canvasSize.width, photoH: owner.canvasSize.height,
            cropX: cropRect.x, cropY: cropRect.y, cropW: cropRect.w, cropH: cropRect.h
        )
        let region = computeCropRegion(input: input)
        guard isCropRegionValid(region),
              let cropped = owner.imageProcessor.cropping(baseImage, region: region) else { return }

        owner.baseImage = cropped
        owner.photoAspectRatio = clampAspectRatio(Double(region.regionW) / Double(region.regionH))
        if let layer = document.photoLayer() {
            // 源端裁剪后锐化重置（基准内容与新图区域不匹配）。
            document.updateLayer(layer.id) { l in
                l.adjustments.sharpness = 0
            }
        }
        owner.adjustVM.resetSharpness()
        owner.photoGeneration += 1
        self.cropRect = nil
        owner.tool = .none
        document.resetHistory()
        owner.refreshPhotoImage()
        owner.syncState()
    }
}
