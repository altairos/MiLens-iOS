//  RedPacketWorkshopViewModel —— 红包工作室状态机（对应红包封面开发计划 §3）。
//
//  @Observable 视图模型，管理草稿/图层/选中状态/抠图状态。
//  几何全部委托 RedPacketLayoutLogic；VM 只做状态机。
//  抠图管线（分割/合成/持久化）在 +Cutout.swift；质量输入组装在
//  RedPacketQualityInputBuilder；本文件只保留加载/图层操作/撤销/优化/草稿持久化。

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

/// 工作室加载失败原因（模板/照片不可用时阻止编辑，UI 显示失败态）。
enum RedPacketLoadError: Equatable {
    case templateNotFound
    case photoNotFound
    case photoUnreadable
}

/// 红包工作室 ViewModel。
@MainActor
@Observable
final class RedPacketWorkshopViewModel {

    // MARK: - 依赖

    private let photoRepo: any PhotoRepositoryProtocol
    // 以下三个成员供 +Cutout.swift 访问（同模块内可见），其余仍 private。
    let vision: any VisionService
    let draftStore: RedPacketDraftStore
    let imageQualityAnalyzer: any RedPacketImageQualityAnalyzing

    // MARK: - 初始参数

    let templateID: String
    let photoID: UUID
    let petID: UUID?
    let isPro: Bool
    /// 是否跳过自动抠图（从 CutoutConfirm 进入时为 true）。
    var skipAutoCutout = false
    /// CutoutConfirm 页已确认的分割结果（复用以跳过重复 Vision 分割）。
    var confirmedSegmentation: SegmentationResult?

    // MARK: - 状态

    /// 是否正在加载。
    var isLoading = true
    /// 加载失败原因（nil = 加载成功或进行中）。
    var loadError: RedPacketLoadError?
    /// 当前模板。
    private(set) var template: RedPacketTemplate = .firstFreeTemplate
    /// 当前草稿。
    var draft: RedPacketCoverDraft = RedPacketCoverDraft(templateID: "", templateRevision: 1)
    /// 当前选中图层 ID（nil = 未选中）。
    var activeLayerID: String?
    /// 原始照片图像。
    var sourceImage: UIImage?
    /// 原图编码数据，Vision 与像素分析共用，避免反复 JPEG 压缩损失。
    var sourceImageData: Data?
    /// 抠图后的图像。
    var cutoutImage: UIImage?
    /// 原图/抠图真实像素指标（抠图指标供 +Cutout.swift 写入）。
    private var sourceImageMetrics: RedPacketImageMetrics?
    var cutoutImageMetrics: RedPacketImageMetrics?
    /// 抠图蒙版真实结构指标。
    var cutoutMaskMetrics: RedPacketMaskMetrics?
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
    /// 优化前图层快照（优化后可通过切换预览“优化前”状态）。
    /// 仅在最近一次智能优化执行后存在；用户修改图层后清除。
    var preOptimizationLayers: [RedPacketLayer]?
    /// 当前预览是否显示优化前状态（false = 优化后/正常状态）。
    var isPreviewingBeforeOptimization = false
    /// 最近一次优化是否已应用（用于判断“优化前/优化后”切换和“撤销本次调整”的可见性）。
    var hasAppliedOptimization = false

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
            loadError = .templateNotFound
            return
        }
        template = foundTemplate

        do {
            guard let photo = try photoRepo.getPhoto(id: photoID) else {
                logger.error("load: 照片不存在 \(self.photoID)")
                loadError = .photoNotFound
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
                loadError = .photoUnreadable
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

            // 初始化历史状态
            history = RedPacketHistoryLogic.initialState(draft: draft)

            // 抠图：从 CutoutConfirm 进入时复用其已确认的分割结果，避免重复 Vision 分割；
            // 其余入口自行分割。
            if skipAutoCutout, let seg = confirmedSegmentation,
               seg.bboxWidth > 0, seg.bboxHeight > 0 {
                await applySegmentation(seg, sourceData: loadedData)
            } else {
                await performCutout()
            }

        } catch {
            logger.error("load: 读取照片失败 \(error.localizedDescription)")
            loadError = .photoUnreadable
        }
    }

    // MARK: - 图层操作（抠图管线见 +Cutout.swift）

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

    /// 手势编辑会话：会话首帧推快照（幂等），手势结束调 endGestureEdit。
    /// 连续手势（拖/缩/旋）在 onChanged 首帧进入，整段手势只占一条撤销记录。
    private var isGestureEditing = false

    /// 文本输入会话：会话首帧自动推快照，连续键入只占一条撤销记录。
    /// 任何离散操作（pushSnapshot）、撤销/重做或失焦（endTextEdit）都会重置。
    private var isTextEditing = false

    func beginGestureEdit() {
        guard !isGestureEditing, activeLayerID != nil else { return }
        isGestureEditing = true
        pushSnapshot()
        clearOptimizationPreview()
    }

    func endGestureEdit() {
        isGestureEditing = false
    }

    /// 离散变换（检查器按钮等单次操作）：推快照后执行。
    func transformActive(scaleBy factor: Double = 1.0, rotateBy degrees: Double = 0.0) {
        guard activeLayerID != nil else { return }
        pushSnapshot()
        clearOptimizationPreview()
        if factor != 1.0 { scaleActive(by: factor) }
        if degrees != 0 { rotateActive(by: degrees) }
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
        clearOptimizationPreview()
        draft.layers = rpDeleteLayer(draft.layers, id: id)
        activeLayerID = nil
        refreshQualityIfNeeded()
    }

    func centerActive() {
        guard let id = activeLayerID else { return }
        pushSnapshot()
        clearOptimizationPreview()
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
        clearOptimizationPreview()
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
        if !isTextEditing {
            // 会话首帧：记录编辑前状态；后续键入不再逐字推快照
            isTextEditing = true
            history = RedPacketHistoryLogic.push(current: history, draft: draft)
            clearOptimizationPreview()
        }
        let truncated = String(text.prefix(WeChatRedPacketSpec.coverTitleMaxLength))
        draft.layers = rpUpdateLayer(draft.layers, id: textLayer.id) { $0.text = truncated }
        draft.coverTitle = truncated
        refreshQualityIfNeeded()
    }

    /// 结束文本输入会话（输入框失焦时调用；下一次键入开启新撤销记录）。
    func endTextEdit() {
        isTextEditing = false
    }

    /// 切换活动文本层的预置风格。
    func applyTextStyle(_ preset: RedPacketTextStylePreset) {
        guard let id = activeLayerID, activeLayer?.kind == .text else { return }
        pushSnapshot()
        clearOptimizationPreview()
        draft.layers = rpUpdateLayer(draft.layers, id: id) { $0.styleID = preset.rawValue }
        refreshQualityIfNeeded()
    }

    /// 添加配饰图层（Phase 2 基础配饰）。
    func addAccessory(resourceRef: String, x: Double? = nil, y: Double? = nil) {
        pushSnapshot()
        clearOptimizationPreview()
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
        // VM 层兜底：View 层 isLocked 已拦截，但直接调用（测试/未来入口）不可越权切到 Pro 模板。
        guard newTemplate.isFree || isPro else { return }
        pushSnapshot()
        clearOptimizationPreview()
        template = newTemplate
        draft.layers = rpSwitchTemplate(oldLayers: draft.layers, newTemplate: newTemplate)
        draft.templateID = newTemplate.id
        draft.templateRevision = newTemplate.revision
        draft.updatedAt = Date()
        refreshQualityIfNeeded()
    }

    // MARK: - 撤销 / 重做

    /// 在用户操作前记录快照。离散操作同时打断文本输入会话，
    /// 避免跨操作合并撤销记录。
    private func pushSnapshot() {
        isTextEditing = false
        history = RedPacketHistoryLogic.push(current: history, draft: draft)
    }

    /// 用户手动修改图层后，清除优化前/后预览状态。
    private func clearOptimizationPreview() {
        if preOptimizationLayers != nil {
            preOptimizationLayers = nil
            isPreviewingBeforeOptimization = false
            hasAppliedOptimization = false
        }
    }

    func undo() {
        isTextEditing = false
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
        isTextEditing = false
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

    /// 从当前图层状态评估质量（输入组装见 RedPacketQualityInputBuilder）。
    func evaluateQuality() {
        let input = RedPacketQualityInputBuilder.make(
            layers: draft.layers,
            template: template,
            sourceMetrics: sourceImageMetrics,
            cutoutMetrics: cutoutImageMetrics,
            maskMetrics: cutoutMaskMetrics,
            cutoutApplied: cutoutPhase == .applied
        )
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
            // 无质量问题：没有可真实落地的调整，交由 noChanges 摘要告知用户。
            optimization = RedPacketOptimizationResult()
        }

        guard optimization.hasOptimizations else {
            optimizationSummary = ["redpacket.optimize.noChanges"]
            return
        }

        // 保存优化前快照（供“优化前/优化后”预览切换）
        preOptimizationLayers = draft.layers
        isPreviewingBeforeOptimization = false
        hasAppliedOptimization = true

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

    /// 切换“优化前/优化后”预览。
    /// 优化后状态为正常草稿（draft.layers）；优化前状态使用 preOptimizationLayers 快照。
    func toggleOptimizationPreview() {
        guard preOptimizationLayers != nil else { return }
        isPreviewingBeforeOptimization.toggle()
    }

    /// 撤销最近一次优化（恢复优化前图层，清除快照）。
    func undoOptimization() {
        guard let before = preOptimizationLayers else { return }
        pushSnapshot()
        draft.layers = before
        preOptimizationLayers = nil
        isPreviewingBeforeOptimization = false
        hasAppliedOptimization = false
        optimizationSummary = []
        evaluateQuality()
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
}
