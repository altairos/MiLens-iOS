//  RedPacketWorkshopViewModel —— 红包工作室状态机（对应红包封面开发计划 §3）。
//
//  @Observable 视图模型，管理草稿/图层/选中状态/抠图状态。
//  几何全部委托 RedPacketLayoutLogic；VM 只做状态机。
//  抠图复用 VisionService.segmentSubject（VNGenerateForegroundInstanceMask），
//  失败设 .error，不降级为中心裁切（诚实标注）。

import SwiftUI
import UIKit
import MiLensKit
import os

private let logger = Logger(subsystem: "com.milens.app", category: "RedPacketWorkshop")

/// 抠图处理阶段。
enum RedPacketCutoutPhase: Equatable {
    case idle
    case processing
    case applied
    case error
}

/// 红包工作室 ViewModel。
@MainActor
@Observable
final class RedPacketWorkshopViewModel {

    // MARK: - 依赖

    private let photoRepo: any PhotoRepositoryProtocol
    private let vision: any VisionService
    private let draftStore: RedPacketDraftStore

    // MARK: - 初始参数

    let templateID: String
    let photoID: UUID
    let petID: UUID?
    let isPro: Bool

    // MARK: - 状态

    /// 是否正在加载。
    var isLoading = true
    /// 当前模板。
    private(set) var template: RedPacketTemplate = .firstFreeTemplate
    /// 当前草稿。
    var draft: RedPacketCoverDraft = RedPacketCoverDraft(templateID: "", templateRevision: 1)
    /// 当前选中图层 ID（nil = 未选中）。
    var activeLayerID: String?
    /// 原始照片图像。
    var sourceImage: UIImage?
    /// 抠图后的图像。
    var cutoutImage: UIImage?
    /// 抠图阶段。
    var cutoutPhase: RedPacketCutoutPhase = .idle
    /// 宠物名。
    var petName = ""
    /// 撤销/重做历史状态。
    var history: RedPacketHistoryState = RedPacketHistoryState()

    // MARK: - 初始化

    init(
        templateID: String,
        photoID: UUID,
        petID: UUID?,
        isPro: Bool,
        photoRepo: any PhotoRepositoryProtocol,
        vision: any VisionService,
        draftStore: RedPacketDraftStore
    ) {
        self.templateID = templateID
        self.photoID = photoID
        self.petID = petID
        self.isPro = isPro
        self.photoRepo = photoRepo
        self.vision = vision
        self.draftStore = draftStore
    }

    // MARK: - 计算属性

    /// 图层列表（来自草稿）。
    var layers: [RedPacketLayer] {
        draft.layers
    }

    /// 当前活动图层。
    var activeLayer: RedPacketLayer? {
        guard let activeLayerID else { return nil }
        return draft.layers.first { $0.id == activeLayerID }
    }

    /// 当前文本内容。
    var textContent: String {
        draft.layers.first { $0.kind == .text }?.text ?? ""
    }

    /// 是否可撤销。
    var canUndo: Bool { history.canUndo }
    /// 是否可重做。
    var canRedo: Bool { history.canRedo }

    // MARK: - 加载

    func load() async {
        defer { isLoading = false }
        guard let foundTemplate = RedPacketTemplateCatalog.find(id: templateID) else {
            logger.error("load: 模板不存在 \(self.templateID)")
            return
        }
        template = foundTemplate

        do {
            guard let photo = try photoRepo.getPhoto(id: photoID) else {
                logger.error("load: 照片不存在 \(self.photoID)")
                return
            }

            // 解码原图
            let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
            let loaded = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: path)
            }.value
            guard let loaded else {
                logger.error("load: 照片解码失败 \(path)")
                return
            }
            sourceImage = loaded

            // 宠物名
            var name = ""
            if let petID, let pet = try photoRepo.getPet(id: petID) {
                name = pet.name
            } else if let pet = photo.pet {
                name = pet.name
            }
            petName = name

            // 创建草稿
            draft = RedPacketCoverDraft.create(
                from: foundTemplate,
                sourcePhotoID: photoID,
                petName: name
            )

            // 自动抠图
            // 初始化历史状态
            history = RedPacketHistoryLogic.initialState(draft: draft)

            await performCutout()

        } catch {
            logger.error("load: 读取照片失败 \(error.localizedDescription)")
        }
    }

    // MARK: - 抠图

    func performCutout() async {
        guard let source = sourceImage else { return }
        cutoutPhase = .processing

        guard let cgImage = source.cgImage else {
            cutoutPhase = .error
            return
        }

        // 编码为 JPEG 供 VisionService
        guard let data = source.jpegData(compressionQuality: 0.9) else {
            cutoutPhase = .error
            return
        }

        let result: SegmentationResult?
        do {
            result = try await vision.segmentSubject(in: data)
        } catch {
            logger.error("performCutout: 分割失败 \(error.localizedDescription)")
            result = nil
        }

        guard let seg = result, seg.bboxWidth > 0, seg.bboxHeight > 0 else {
            // 失败即 error，不用中心裁切伪装（诚实标注）
            cutoutPhase = .error
            return
        }

        // 应用蒙版生成抠图
        guard let cutout = applyCutoutMask(
            cgImage: cgImage, mask: [UInt8](seg.mask),
            bboxX: Int(seg.bboxX), bboxY: Int(seg.bboxY),
            bboxWidth: seg.bboxWidth, bboxHeight: seg.bboxHeight
        ) else {
            cutoutPhase = .error
            return
        }

        cutoutImage = cutout
        cutoutPhase = .applied

        // 更新 pet 图层
        updatePetLayerWithCutout(cutout)
    }

    func retryCutout() async {
        await performCutout()
    }

    // MARK: - 图层操作

    func selectLayer(at canvasPoint: CGPoint) {
        let hitID = rpHitTest(
            layers: draft.layers,
            canvasX: Double(canvasPoint.x), canvasY: Double(canvasPoint.y)
        )
        activeLayerID = hitID
    }

    func deselect() {
        activeLayerID = nil
    }

    func moveActive(dx: Double, dy: Double) {
        guard let id = activeLayerID else { return }
        draft.layers = rpUpdateLayer(draft.layers, id: id) { layer in
            let newX = layer.x + dx
            let newY = layer.y + dy
            let clamped = rpClampPosition(x: newX, y: newY)
            layer.x = clamped.x
            layer.y = clamped.y
        }
    }

    func scaleActive(by factor: Double) {
        guard let id = activeLayerID else { return }
        draft.layers = rpUpdateLayer(draft.layers, id: id) { layer in
            layer.scale = rpClampScale(layer.scale * factor)
        }
    }

    func rotateActive(by degrees: Double) {
        guard let id = activeLayerID else { return }
        draft.layers = rpUpdateLayer(draft.layers, id: id) { layer in
            layer.rotation += degrees
        }
    }

    func deleteActive() {
        guard let id = activeLayerID else { return }
        pushSnapshot()
        draft.layers = rpDeleteLayer(draft.layers, id: id)
        activeLayerID = nil
    }

    func centerActive() {
        guard let id = activeLayerID else { return }
        pushSnapshot()
        draft.layers = rpUpdateLayer(draft.layers, id: id) { layer in
            let centered = rpCenterLayer(layer)
            layer.x = centered.x
            layer.y = centered.y
        }
    }

    func resetActive() {
        guard let id = activeLayerID else { return }
        pushSnapshot()
        draft.layers = rpUpdateLayer(draft.layers, id: id) { layer in
            let reset = rpResetLayerToDefault(layer, template: template)
            layer.x = reset.x
            layer.y = reset.y
            layer.scale = reset.scale
            layer.rotation = reset.rotation
        }
    }

    func updateText(_ text: String) {
        guard let textLayer = draft.layers.first(where: { $0.kind == .text }) else { return }
        pushSnapshot()
        let truncated = String(text.prefix(WeChatRedPacketSpec.coverTitleMaxLength))
        draft.layers = rpUpdateLayer(draft.layers, id: textLayer.id) { $0.text = truncated }
        draft.coverTitle = truncated
    }

    /// 切换活动文本层的预置风格。
    func applyTextStyle(_ preset: RedPacketTextStylePreset) {
        guard let id = activeLayerID, activeLayer?.kind == .text else { return }
        pushSnapshot()
        draft.layers = rpUpdateLayer(draft.layers, id: id) { $0.styleID = preset.rawValue }
    }

    /// 添加配饰图层（Phase 2 基础配饰）。
    func addAccessory(resourceRef: String, x: Double? = nil, y: Double? = nil) {
        pushSnapshot()
        let posX = x ?? (rpCanvasWidth * 0.5)
        let posY = y ?? (rpCanvasHeight * 0.5)
        var accessory = makeRedPacketTextLayer(text: "", x: posX, y: posY, width: 120, height: 120)
        accessory.kind = .accessory
        accessory.resourceRef = resourceRef
        accessory.zIndex = 150
        draft.layers.append(accessory)
        activeLayerID = accessory.id
    }

    // MARK: - 模板切换

    func switchTemplate(to newTemplateID: String) {
        guard let newTemplate = RedPacketTemplateCatalog.find(id: newTemplateID) else { return }
        pushSnapshot()
        template = newTemplate
        draft.layers = rpSwitchTemplate(oldLayers: draft.layers, newTemplate: newTemplate)
        draft.templateID = newTemplate.id
        draft.templateRevision = newTemplate.revision
        draft.updatedAt = Date()
    }

    // MARK: - 撤销 / 重做

    /// 在用户操作前记录快照。
    private func pushSnapshot() {
        history = RedPacketHistoryLogic.push(current: history, draft: draft)
    }

    func undo() {
        let (newState, restored) = RedPacketHistoryLogic.undo(history)
        history = newState
        if let restored {
            draft = restored
            if let t = RedPacketTemplateCatalog.find(id: restored.templateID) {
                template = t
            }
        }
    }

    func redo() {
        let (newState, restored) = RedPacketHistoryLogic.redo(history)
        history = newState
        if let restored {
            draft = restored
            if let t = RedPacketTemplateCatalog.find(id: restored.templateID) {
                template = t
            }
        }
    }

    // MARK: - 草稿持久化

    @discardableResult
    func saveDraft() -> UUID {
        draft.updatedAt = Date()
        do {
            try draftStore.save(draft)
        } catch {
            logger.error("saveDraft: 保存失败 \(error.localizedDescription)")
        }
        return draft.id
    }

    func loadDraft(id: UUID) {
        do {
            if let loaded = try draftStore.load(id: id) {
                draft = loaded
                if let t = RedPacketTemplateCatalog.find(id: loaded.templateID) {
                    template = t
                }
            }
        } catch {
            logger.error("loadDraft: 加载失败 \(error.localizedDescription)")
        }
    }

    // MARK: - 抠图蒙版应用

    /// 把 bbox 局部 mask 平铺到全图，生成透明抠图。
    private func applyCutoutMask(
        cgImage: CGImage, mask: [UInt8],
        bboxX: Int, bboxY: Int, bboxWidth: Int, bboxHeight: Int
    ) -> UIImage? {
        let imgW = cgImage.width
        let imgH = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = imgW * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil, width: imgW, height: imgH,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // 先画原图
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: imgW, height: imgH))

        guard let pixelData = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        // 对 bbox 内的像素应用 mask 到 alpha 通道
        for y in 0..<bboxHeight {
            let dstY = bboxY + y
            guard dstY >= 0, dstY < imgH else { continue }
            for x in 0..<bboxWidth {
                let dstX = bboxX + x
                guard dstX >= 0, dstX < imgW else { continue }
                let maskIdx = y * bboxWidth + x
                guard maskIdx < mask.count else { continue }
                let alpha = mask[maskIdx]
                let pixelIdx = (dstY * imgW + dstX) * bytesPerPixel
                // 把 mask 值（0-255）写入 alpha 通道
                pixelData[pixelIdx + 3] = min(pixelData[pixelIdx + 3], alpha)
            }
        }

        guard let outputCG = context.makeImage() else { return nil }
        return UIImage(cgImage: outputCG)
    }

    /// 用抠图结果更新 pet 图层。
    private func updatePetLayerWithCutout(_ cutout: UIImage) {
        guard let petLayer = draft.layers.first(where: { $0.kind == .pet }) else { return }
        let cw = cutout.size.width
        let ch = cutout.size.height
        draft.layers = rpUpdateLayer(draft.layers, id: petLayer.id) { layer in
            layer.visible = true
            layer.width = Double(cw)
            layer.height = Double(ch)
        }
    }
}
