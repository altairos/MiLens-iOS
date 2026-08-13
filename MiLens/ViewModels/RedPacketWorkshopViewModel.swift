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
    private let imageQualityAnalyzer: any RedPacketImageQualityAnalyzing

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
    /// 原图编码数据，Vision 与像素分析共用，避免反复 JPEG 压缩损失。
    private var sourceImageData: Data?
    /// 抠图后的图像。
    var cutoutImage: UIImage?
    /// 原图/抠图真实像素指标。
    private var sourceImageMetrics: RedPacketImageMetrics?
    private var cutoutImageMetrics: RedPacketImageMetrics?
    /// 抠图蒙版真实结构指标。
    private var cutoutMaskMetrics: RedPacketMaskMetrics?
    /// 抠图阶段。
    var cutoutPhase: RedPacketCutoutPhase = .idle
    /// 宠物名。
    var petName = ""
    /// 撤销/重做历史状态。
    var history: RedPacketHistoryState = RedPacketHistoryState()
    /// 质量报告（最近一次检测结果）。
    var qualityReport: RedPacketQualityReport?
    /// 是否正在执行智能优化。
    var isOptimizing = false
    /// 智能优化摘要（供 UI 反馈）。
    var optimizationSummary: [String] = []

    // MARK: - 初始化

    init(
        templateID: String,
        photoID: UUID,
        petID: UUID?,
        isPro: Bool,
        photoRepo: any PhotoRepositoryProtocol,
        vision: any VisionService,
        draftStore: RedPacketDraftStore,
        imageQualityAnalyzer: any RedPacketImageQualityAnalyzing
    ) {
        self.templateID = templateID
        self.photoID = photoID
        self.petID = petID
        self.isPro = isPro
        self.photoRepo = photoRepo
        self.vision = vision
        self.draftStore = draftStore
        self.imageQualityAnalyzer = imageQualityAnalyzer
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
    /// 是否有质量问题。
    var hasQualityIssues: Bool { qualityReport?.hasIssues ?? false }
    /// 总体质量级别。
    var overallQualityLevel: RedPacketQualityLevel {
        qualityReport?.overallLevel ?? .pass
    }

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

            // 优先读取原图，原图不可用时才回退缩略图；质量检查会如实使用实际读取的数据。
            let candidatePaths = [photo.uri, photo.thumbnailPath]
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { paths, path in
                    if !paths.contains(path) { paths.append(path) }
                }
            let loadedData = await Task.detached(priority: .utility) {
                for path in candidatePaths {
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
                       !data.isEmpty {
                        return data
                    }
                }
                return nil
            }.value
            guard let loadedData, let loaded = UIImage(data: loadedData) else {
                logger.error("load: 照片解码失败")
                return
            }
            sourceImage = loaded
            sourceImageData = loadedData

            let analyzer = imageQualityAnalyzer
            sourceImageMetrics = await Task.detached(priority: .utility) {
                analyzer.analyze(imageData: loadedData)
            }.value

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
        guard let data = sourceImageData else { return }
        cutoutPhase = .processing

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
            cutoutImageMetrics = nil
            cutoutMaskMetrics = nil
            evaluateQuality()
            return
        }

        // 蒙版合成、裁边与指标提取均在后台完成，避免阻塞编辑手势。
        let analyzer = imageQualityAnalyzer
        let processed = await Task.detached(priority: .utility) {
            analyzer.makeCutout(imageData: data, segmentation: seg)
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

        // 更新 pet 图层
        updatePetLayerWithCutout(
            pixelWidth: processed.pixelWidth,
            pixelHeight: processed.pixelHeight
        )
        evaluateQuality()
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
        refreshQualityIfNeeded()
    }

    func scaleActive(by factor: Double) {
        guard let id = activeLayerID else { return }
        draft.layers = rpUpdateLayer(draft.layers, id: id) { layer in
            layer.scale = rpClampScale(layer.scale * factor)
        }
        refreshQualityIfNeeded()
    }

    func rotateActive(by degrees: Double) {
        guard let id = activeLayerID else { return }
        draft.layers = rpUpdateLayer(draft.layers, id: id) { layer in
            layer.rotation += degrees
        }
        refreshQualityIfNeeded()
    }

    func deleteActive() {
        guard let id = activeLayerID else { return }
        pushSnapshot()
        draft.layers = rpDeleteLayer(draft.layers, id: id)
        activeLayerID = nil
        refreshQualityIfNeeded()
    }

    func centerActive() {
        guard let id = activeLayerID else { return }
        pushSnapshot()
        draft.layers = rpUpdateLayer(draft.layers, id: id) { layer in
            let centered = rpCenterLayer(layer)
            layer.x = centered.x
            layer.y = centered.y
        }
        refreshQualityIfNeeded()
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
        refreshQualityIfNeeded()
    }

    func updateText(_ text: String) {
        guard let textLayer = draft.layers.first(where: { $0.kind == .text }) else { return }
        pushSnapshot()
        let truncated = String(text.prefix(WeChatRedPacketSpec.coverTitleMaxLength))
        draft.layers = rpUpdateLayer(draft.layers, id: textLayer.id) { $0.text = truncated }
        draft.coverTitle = truncated
        refreshQualityIfNeeded()
    }

    /// 切换活动文本层的预置风格。
    func applyTextStyle(_ preset: RedPacketTextStylePreset) {
        guard let id = activeLayerID, activeLayer?.kind == .text else { return }
        pushSnapshot()
        draft.layers = rpUpdateLayer(draft.layers, id: id) { $0.styleID = preset.rawValue }
        refreshQualityIfNeeded()
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
        refreshQualityIfNeeded()
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
        refreshQualityIfNeeded()
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

    // MARK: - 质量检测与智能优化

    /// 从当前图层状态提取质量检测输入。
    func evaluateQuality() {
        let input = buildQualityInput()
        qualityReport = RedPacketQualityLogic.evaluate(input)
    }

    /// 一键智能优化（根据质量报告生成并应用优化方案，可撤销）。
    func applySmartOptimization() {
        if qualityReport == nil { evaluateQuality() }
        guard qualityReport != nil else { return }
        isOptimizing = true
        defer { isOptimizing = false }

        let report = qualityReport ?? RedPacketQualityReport(items: [])
        let petLayer = draft.layers.first { $0.kind == .pet }
        let textLayer = draft.layers.first { $0.kind == .text }

        let optimization: RedPacketOptimizationResult
        if report.hasIssues {
            optimization = RedPacketOptimizationLogic.generateOptimization(
                report: report,
                template: template,
                petLayer: petLayer,
                textLayer: textLayer
            )
        } else {
            optimization = RedPacketOptimizationLogic.defaultGentleOptimization(
                template: template,
                petLayer: petLayer,
                textLayer: textLayer
            )
        }

        guard optimization.hasOptimizations else {
            optimizationSummary = ["redpacket.optimize.noChanges"]
            return
        }

        // 记录历史（可撤销）
        pushSnapshot()

        // 应用优化到图层
        draft.layers = RedPacketOptimizationLogic.applyOptimization(
            optimization, layers: draft.layers
        )

        optimizationSummary = optimization.summaryKeys

        // 重新检测质量
        evaluateQuality()
    }

    /// 构建质量检测输入（从当前图层和图像状态提取）。
    private func buildQualityInput() -> RedPacketQualityInput {
        let petLayer = draft.layers.first { $0.kind == .pet }
        let textLayer = draft.layers.first { $0.kind == .text }

        // 清晰度/分辨率使用原图，避免透明轮廓抬高 Laplacian；亮度优先检查抠出的主体。
        let clarityMetrics = sourceImageMetrics
        let toneMetrics = cutoutImageMetrics ?? sourceImageMetrics

        // 宠物面积比例
        let petCoverage: Double
        if let pet = petLayer, pet.visible {
            let petArea = pet.width * pet.scale * pet.height * pet.scale
            let canvasArea = rpCanvasWidth * rpCanvasHeight
            petCoverage = min(1, petArea / canvasArea)
        } else {
            petCoverage = 0
        }

        // 宠物是否在安全区
        let petInZone: Bool
        let petSafeZoneCoverage: Double
        let petCanvasVisible: Double
        if let pet = petLayer {
            petSafeZoneCoverage = rpLayerSafeZoneCoverageRatio(pet, template: template)
            petCanvasVisible = rpLayerCanvasVisibleRatio(pet)
            petInZone = petSafeZoneCoverage >= 0.65
        } else {
            petInZone = false
            petSafeZoneCoverage = 0
            petCanvasVisible = 0
        }

        // 文本是否在安全区
        let textInZone: Bool
        if let text = textLayer {
            textInZone = rpIsLayerInSafeZone(text, template: template)
        } else {
            textInZone = true
        }

        return RedPacketQualityInput(
            imageWidth: clarityMetrics?.pixelWidth ?? 0,
            imageHeight: clarityMetrics?.pixelHeight ?? 0,
            sharpness: clarityMetrics?.sharpness ?? 0,
            averageBrightness: toneMetrics?.averageBrightness ?? 0,
            petCoverageRatio: petCoverage,
            cutoutEdgeRoughness: cutoutMaskMetrics?.edgeRoughness ?? 0,
            petInSafeZone: petInZone,
            textContent: textLayer?.text ?? "",
            textInSafeZone: textInZone,
            textContrast: 0.6,
            imageMetricsAvailable: clarityMetrics != nil && toneMetrics != nil,
            shadowClippingRatio: toneMetrics?.shadowClippingRatio ?? 0,
            highlightClippingRatio: toneMetrics?.highlightClippingRatio ?? 0,
            petCanvasVisibleRatio: petCanvasVisible,
            petSafeZoneCoverageRatio: petSafeZoneCoverage,
            cutoutMetricsAvailable: cutoutPhase == .applied && cutoutMaskMetrics != nil,
            cutoutForegroundRatio: cutoutMaskMetrics?.foregroundRatio ?? 0,
            cutoutFragmentationRatio: cutoutMaskMetrics?.fragmentationRatio ?? 0,
            cutoutBoundaryTouchRatio: cutoutMaskMetrics?.boundaryTouchRatio ?? 0
        )
    }

    private func refreshQualityIfNeeded() {
        guard qualityReport != nil else { return }
        evaluateQuality()
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

    /// 用抠图结果更新 pet 图层。
    private func updatePetLayerWithCutout(pixelWidth: Int, pixelHeight: Int) {
        guard let petLayer = draft.layers.first(where: { $0.kind == .pet }) else { return }
        guard pixelWidth > 0, pixelHeight > 0 else { return }
        let zone = template.safeZone
        let maxWidth = zone.width * rpCanvasWidth * 0.82
        let maxHeight = zone.height * rpCanvasHeight * 0.82
        let fitScale = min(
            maxWidth / Double(pixelWidth),
            maxHeight / Double(pixelHeight)
        )
        let logicalWidth = Double(pixelWidth) * fitScale
        let logicalHeight = Double(pixelHeight) * fitScale
        draft.layers = rpUpdateLayer(draft.layers, id: petLayer.id) { layer in
            layer.visible = true
            layer.width = logicalWidth
            layer.height = logicalHeight
            layer.scale = template.defaultPetTransform.scale
            layer.x = template.defaultPetTransform.x
            layer.y = template.defaultPetTransform.y
        }
        activeLayerID = petLayer.id
    }
}
