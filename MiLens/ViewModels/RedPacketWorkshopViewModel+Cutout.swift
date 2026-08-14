//  RedPacketWorkshopViewModel+Cutout —— 抠图管线（VM 状态机的抠图部分）。
//
//  performCutout：Vision 分割 → applySegmentation 合成；
//  applySegmentation：蒙版合成、裁边、指标提取、PNG 持久化、更新 pet 层，
//  与 performCutout 分离，供复用 CutoutConfirm 已确认的分割结果（P2-1）。
//  存储属性仍留在主文件（@Observable 宏要求），此处只放行为。

import UIKit
import MiLensKit
import os

private let cutoutLogger = Logger(subsystem: "com.milens.app", category: "RedPacketWorkshop.Cutout")

extension RedPacketWorkshopViewModel {

    func performCutout() async {
        guard let data = sourceImageData else { return }
        cutoutPhase = .processing

        let result: SegmentationResult?
        do {
            result = try await vision.segmentSubject(in: data)
        } catch {
            cutoutLogger.error("performCutout: 分割失败 \(error.localizedDescription)")
            result = nil
        }

        guard let seg = result, seg.bboxWidth > 0, seg.bboxHeight > 0 else {
            // 失败即 error，不用中心裁切伪装（诚实标注）
            cutoutPhase = .error
            cutoutImageMetrics = nil
            cutoutMaskMetrics = nil
            evaluateQuality()
            return
        }

        await applySegmentation(seg, sourceData: data)
    }

    /// 用分割结果合成抠图：蒙版合成、裁边、指标提取、持久化、更新 pet 层。
    /// 与 performCutout 分离，供复用 CutoutConfirm 已确认的分割结果。
    func applySegmentation(_ segmentation: SegmentationResult, sourceData: Data) async {
        cutoutPhase = .processing

        // 蒙版合成、裁边与指标提取均在后台完成，避免阻塞编辑手势。
        let analyzer = imageQualityAnalyzer
        let processed = await Task.detached(priority: .utility) {
            analyzer.makeCutout(imageData: sourceData, segmentation: segmentation)
        }.value
        guard let processed, let cutout = UIImage(data: processed.pngData) else {
            cutoutPhase = .error
            cutoutImageMetrics = nil
            cutoutMaskMetrics = nil
            evaluateQuality()
            return
        }

        cutoutImage = cutout
        cutoutImageMetrics = processed.imageMetrics
        cutoutMaskMetrics = processed.maskMetrics
        cutoutPhase = .applied

        // 持久化抠图 PNG；导出页不持有本 VM，靠 pet 层 mattePath 回灌。
        // 写入失败不阻断编辑，但不写入 mattePath，避免草稿引用悬空文件。
        var matteFileName: String?
        do {
            let fileName = "\(draft.id.uuidString).png"
            try draftStore.saveCutoutPNG(processed.pngData, for: draft.id)
            matteFileName = fileName
        } catch {
            cutoutLogger.error("applySegmentation: 抠图持久化失败 \(error.localizedDescription)")
        }

        // 更新 pet 图层
        updatePetLayerWithCutout(
            pixelWidth: processed.pixelWidth,
            pixelHeight: processed.pixelHeight,
            mattePath: matteFileName
        )
        evaluateQuality()
    }

    func retryCutout() async {
        await performCutout()
    }

    /// 用抠图结果更新 pet 图层。
    private func updatePetLayerWithCutout(
        pixelWidth: Int,
        pixelHeight: Int,
        mattePath: String?
    ) {
        guard let petLayer = draft.layers.first(where: { $0.kind == .pet }) else { return }
        guard let fitted = rpFitCutoutLayerSize(
            pixelWidth: pixelWidth, pixelHeight: pixelHeight, template: template
        ) else { return }
        draft.layers = rpUpdateLayer(draft.layers, id: petLayer.id) { layer in
            layer.visible = true
            layer.width = fitted.width
            layer.height = fitted.height
            layer.mattePath = mattePath
            layer.scale = template.defaultPetTransform.scale
            layer.x = template.defaultPetTransform.x
            layer.y = template.defaultPetTransform.y
        }
        activeLayerID = petLayer.id
    }
}
