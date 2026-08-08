//  EditorViewModel —— 图片编辑器页面状态机（@Observable，对应源端 EditorPage.ets 编排层）。
//  全部决策走 MiLensKit 纯逻辑（EditorToolLogic/EditorCropOverlay/EditorCropMath/
//  EditorAdjustLogic/EditorCutoutLogic/EditorSaveLogic/EditorTextToolLogic/EditorLayerGeometry），
//  本 VM 只做 IO 编排：加载照片、图像处理（EditorImageProcessing 协议）、保存回写（EditorSaveService）。
//
//  撤销/重做：快照 = EditorDocument.serialize() JSON（EditorHistory<String, Void>），
//  手势合并由 EditorHistory.beginGesture/endGesture 提供（滑块/拖动合并为一条历史）。
//
//  与源端的已知差异（iOS 无 PixelMap 备份机制，V1.0 简化）：
//  - 像素级操作（裁剪确认/旋转 90°/抠图应用）后重置历史，不可撤销；
//    源端可撤销（pushUndo 备份 PixelMap）。
//  - 翻转/调色/文字为属性级操作，可撤销（与源端一致）。
//  - 锐化：基于未锐化底图卷积后叠加调色渲染（对齐源端 releaseSharpenBase 语义），
//    撤销恢复 sharpness=0 后自动回到未锐化图。

import CoreGraphics
import Foundation
import ImageIO
import MiLensKit
import Observation
import os

/// 调色面板字段（Slider 绑定用）。
enum EditorAdjustField: Sendable {
    case brightness
    case contrast
    case saturation
    case temperature
    case sharpness
}

@MainActor
@Observable
final class EditorViewModel {

    // MARK: - 依赖

    private let logger = Logger(subsystem: "com.milens.app", category: "EditorVM")
    private let photoRepo: any PhotoRepositoryProtocol
    private let visionService: any VisionService
    private let imageProcessor: any EditorImageProcessing
    private let saveService: EditorSaveService

    // MARK: - 照片状态

    let photoID: UUID
    /// 当前编辑的照片记录（保存时就地更新）。
    private var photo: Photo?
    /// 像素级底图（裁剪/旋转/抠图后更新；锐化/调色不替换它）。
    private var baseImage: CGImage?
    /// 当前显示图（底图 + 锐化 + 调色）。
    private(set) var photoImage: CGImage?
    private(set) var isPhotoLoading = true
    private(set) var photoLoaded = false
    private(set) var photoAspectRatio: Double = 1
    /// 画布尺寸（图片 fit 显示区域，View 报告）。
    private(set) var canvasSize: CGSize = .zero
    private(set) var photoFlipX = false
    private(set) var photoFlipY = false

    // MARK: - 文档与历史

    private let document = EditorDocument()
    private let history = EditorHistory<String, Int>(maxDepth: 30)
    private(set) var layers: [EditorLayer] = []
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var activeLayerID: String?

    // MARK: - 工具

    private(set) var tool: EditorToolMode = .none
    private(set) var group: EditorToolGroup = .none

    // MARK: - 裁剪

    private(set) var cropRect: EditorCropRect?
    private(set) var cropRatioIndex = 0

    // MARK: - 调色

    private(set) var adjustState = EditorAdjustPanelState()
    /// 上次成功卷积后记录的锐化强度（resolveSharpnessApply 的 prev 基准；
    /// 对齐源端 releaseSharpenBase：撤销/重置后回到 0，不重复卷积）。
    private var renderedSharpness = 0.0

    // MARK: - 文字

    var textInput = ""
    var textFontSize: Double = DEFAULT_TEXT_FONT_SIZE
    var textColor: String = DEFAULT_TEXT_COLOR
    var textStrokeEnabled: Bool = DEFAULT_TEXT_STROKE_ENABLED
    private(set) var selectedTextFontSize: Double = DEFAULT_TEXT_FONT_SIZE
    private(set) var selectedTextColor: String = DEFAULT_TEXT_COLOR

    // MARK: - 抠图

    private(set) var cutoutPhase: EditorCutoutPhase = .idle
    private(set) var cutoutStatus = ""
    private(set) var cutoutIsFallback = false
    private var photoGeneration = 0
    private var cutoutGeneration = 0

    // MARK: - 保存/返回

    private(set) var isSaving = false
    private(set) var showSaveChoice = false
    private(set) var showBackConfirm = false
    /// 编辑会话结束信号（View 监听后 dismiss）。
    private(set) var shouldDismiss = false
    private(set) var errorMessage: String?
    private(set) var saveFormat: EditorSaveFormatDecision = resolveSaveFormat(hasAlpha: false)

    var hasUnsavedChanges: Bool { history.canUndo }

    // MARK: - 初始化

    init(photoID: UUID,
         photoRepo: any PhotoRepositoryProtocol,
         visionService: any VisionService,
         imageProcessor: any EditorImageProcessing,
         saveService: EditorSaveService) {
        self.photoID = photoID
        self.photoRepo = photoRepo
        self.visionService = visionService
        self.imageProcessor = imageProcessor
        self.saveService = saveService
    }

    // MARK: - 加载

    /// 加载照片：读记录 → 沙盒文件解码 → 建立底图图层 + 历史基线。
    func load() async {
        guard !photoLoaded else { return }
        do {
            photo = try photoRepo.getPhoto(id: photoID)
        } catch {
            photo = nil
            logger.error("load: 读取照片记录失败（\(self.photoID)，\(error.localizedDescription)）")
        }
        guard let photo else {
            isPhotoLoading = false
            errorMessage = "照片不存在"
            return
        }
        let path = photo.uri
        let decoded = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
                return nil
            }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }.value
        guard let decoded else {
            isPhotoLoading = false
            errorMessage = "照片加载失败"
            return
        }

        baseImage = decoded
        photoImage = decoded
        photoAspectRatio = clampAspectRatio(Double(decoded.width) / Double(decoded.height))
        var photoLayer = createImageLayer(
            type: .photo, width: CGFloat(decoded.width), height: CGFloat(decoded.height)
        )
        document.addPassive(&photoLayer)
        history.initialize(document.serialize() ?? "[]")
        isPhotoLoading = false
        photoLoaded = true
        syncLayers()
    }

    /// View 报告画布尺寸（fit 后的图片显示区域；静默更新底图图层，不入历史）。
    func setCanvasSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != canvasSize else { return }
        canvasSize = size
        if let layer = photoLayer() {
            document.updateLayer(layer.id) { l in
                l.x = size.width / 2
                l.y = size.height / 2
                l.width = size.width
                l.height = size.height
            }
        }
        syncLayers()
    }

    // MARK: - 工具切换

    func selectTool(_ target: EditorToolMode) {
        let decision = resolveToolToggle(currentTool: tool, targetTool: target)
        tool = decision.newTool
        if decision.shouldInitCrop {
            beginCrop()
        }
        syncLayers()
    }

    func selectGroup(_ target: EditorToolGroup) {
        let decision = resolveGroupToggle(currentGroup: group, targetGroup: target)
        group = decision.newGroup
        tool = decision.newTool
        syncLayers()
    }

    /// 工具组是否高亮（组内任何工具激活时）。
    func isGroupActive(_ g: EditorToolGroup) -> Bool {
        isGroupTabActive(currentTool: tool, group: g)
    }

    // MARK: - 裁剪

    func beginCrop() {
        let region = computeCropInitRegion(
            canvasW: canvasSize.width, canvasH: canvasSize.height,
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
            canvasW: canvasSize.width, canvasH: canvasSize.height, rect: rect
        )
    }

    func cancelCrop() {
        cropRect = nil
        tool = .none
        syncLayers()
    }

    /// 确认裁剪：画布坐标 → 照片像素空间（computeCropRegion）→ 像素裁切。
    /// 像素级操作：更新底图、重置历史（iOS 差异，见文件头注释）。
    func confirmCrop() {
        guard let cropRect, let baseImage else { return }
        let input = EditorCropInput(
            photoX: canvasSize.width / 2, photoY: canvasSize.height / 2,
            photoW: canvasSize.width, photoH: canvasSize.height,
            cropX: cropRect.x, cropY: cropRect.y, cropW: cropRect.w, cropH: cropRect.h
        )
        let region = computeCropRegion(input: input)
        guard isCropRegionValid(region),
              let cropped = imageProcessor.cropping(baseImage, region: region) else { return }

        self.baseImage = cropped
        photoAspectRatio = clampAspectRatio(Double(region.regionW) / Double(region.regionH))
        if let layer = photoLayer() {
            // 源端裁剪后锐化重置（基准内容与新图区域不匹配）。
            document.updateLayer(layer.id) { l in
                l.adjustments.sharpness = 0
            }
        }
        adjustState.sharpness = 0
        photoGeneration += 1
        self.cropRect = nil
        tool = .none
        resetHistory()
        refreshPhotoImage()
    }

    // MARK: - 旋转 / 翻转

    func rotate(_ direction: RotationDirection) {
        guard let baseImage else { return }
        let degrees = direction == .cw ? 90.0 : 270.0
        let rotated = imageProcessor.rotating(baseImage, degrees: degrees)
        self.baseImage = rotated
        if let layer = photoLayer() {
            document.updateLayer(layer.id) { l in
                let w = l.width
                l.width = l.height
                l.height = w
                l.adjustments.sharpness = 0
            }
        }
        adjustState.sharpness = 0
        photoAspectRatio = clampAspectRatio(Double(rotated.width) / Double(rotated.height))
        photoGeneration += 1
        resetHistory()
        refreshPhotoImage()
    }

    func flip(_ axis: FlipAxis) {
        guard let layer = photoLayer() else { return }
        document.updateLayer(layer.id) { l in
            if axis == .horizontal { l.flipX.toggle() } else { l.flipY.toggle() }
        }
        pushHistory()
        syncLayers()
    }

    // MARK: - 调色

    func onAdjustSliderChange(_ field: EditorAdjustField, value: Double, phase: EditorSliderGesturePhase) {
        let gesture = resolveSliderGesture(phase)
        if gesture.shouldBeginGesture { history.beginGesture() }

        switch field {
        case .brightness: adjustState.brightness = value
        case .contrast: adjustState.contrast = value
        case .saturation: adjustState.saturation = value
        case .temperature: adjustState.temperature = value
        case .sharpness: adjustState.sharpness = value
        }

        guard let layer = photoLayer() else { return }
        if field == .sharpness {
            // 锐化需要卷积：写回图层值，仅 end/click 且强度变化时渲染（源端异步卷积语义）。
            // prev 基准是「上次渲染的强度」而非图层值，否则 begin/moving 已写回后 end 永不触发。
            let decision = resolveSharpnessApply(
                prevStrength: renderedSharpness, nextStrength: value, phase: phase
            )
            document.updateLayer(layer.id) { $0.adjustments.sharpness = value }
            pushHistory()
            if decision.shouldApply {
                renderedSharpness = decision.strength
                refreshPhotoImage()
            }
        } else {
            applyAdjustments()
        }
        syncLayers()

        if gesture.shouldEndGesture { history.endGesture() }
    }

    func resetAdjustments() {
        guard !isAdjustNeutral(adjustState) else { return }
        adjustState = defaultAdjustPanelState()
        if let layer = photoLayer() {
            document.updateLayer(layer.id) { $0.adjustments = NEUTRAL_EDITOR_ADJUSTMENTS }
        }
        pushHistory()
        refreshPhotoImage()
        syncLayers()
    }

    /// 把面板状态写回照片图层并渲染（实时预览；手势内 push 自动合并）。
    private func applyAdjustments() {
        guard let layer = photoLayer() else { return }
        let adj = buildAdjustments(adjustState)
        document.updateLayer(layer.id) { $0.adjustments = adj }
        pushHistory()
        refreshPhotoImage()
    }

    // MARK: - 文字

    func addText() {
        guard canAddTextLayer(textInput), canvasSize.width > 0 else { return }
        var layer = createTextLayer(
            text: textInput, x: canvasSize.width / 2, y: canvasSize.height / 2,
            fontSize: textFontSize
        )
        layer.fontColor = textColor
        layer.strokeWidth = resolveStrokeWidth(textStrokeEnabled)
        document.add(&layer)
        pushHistory()
        textInput = ""
        syncLayers()
    }

    func updateActiveText(fontSize: Double, color: String) {
        guard let layer = document.activeLayer,
              isTextLayerEditable(layer.type.rawValue) else { return }
        document.updateLayer(layer.id) { l in
            l.fontSize = fontSize
            l.fontColor = color
        }
        selectedTextFontSize = fontSize
        selectedTextColor = color
        pushHistory()
        syncLayers()
    }

    /// 选中文字图层的编辑面板是否可见。
    var showTextLayerEditPanel: Bool {
        shouldShowTextLayerEditPanel(
            activeLayerType: document.activeLayer?.type.rawValue ?? "",
            currentTool: tool
        )
    }

    func deleteActiveLayer() {
        guard let layer = document.activeLayer, layer.type != .photo else { return }
        document.remove(layer.id)
        pushHistory()
        syncLayers()
    }

    // MARK: - 图层手势

    /// 点选：顶层优先 hitTest（LayerGeometry.isPointInLayer），底图不可选中。
    func selectLayer(at point: CGPoint) {
        let hit = document.getLayers().reversed().first { layer in
            layer.type != .photo && isPointInLayer(layer, tapX: point.x, tapY: point.y)
        }
        document.select(hit?.id)
        syncLayers()
    }

    func beginLayerGesture() { history.beginGesture() }
    func endLayerGesture() { history.endGesture() }

    func moveActiveLayer(dx: Double, dy: Double) {
        guard let layer = document.activeLayer else { return }
        document.updateLayer(layer.id) { l in
            l.x += dx
            l.y += dy
        }
        pushHistory()
        syncLayers()
    }

    func scaleActiveLayer(by factor: Double) {
        guard let layer = document.activeLayer else { return }
        let newScale = clampLayerScale(layer.scale * factor)
        document.updateLayer(layer.id) { $0.scale = newScale }
        pushHistory()
        syncLayers()
    }

    func rotateActiveLayer(by degrees: Double) {
        guard let layer = document.activeLayer else { return }
        document.updateLayer(layer.id) { $0.rotation += degrees }
        pushHistory()
        syncLayers()
    }

    // MARK: - 抠图

    func startCutout() async {
        let decision = canStartCutout(cutoutPhase)
        guard decision.canStart else {
            cutoutStatus = decision.rejectReason
            return
        }
        guard let image = photoImage, let layer = photoLayer() else { return }

        cutoutPhase = .processing
        cutoutStatus = cutoutStatusText(.processing)
        cutoutGeneration += 1
        let generation = cutoutGeneration

        // 分割输入：当前显示图（含调色，对齐源端基于显示图分割）。
        guard let data = imageProcessor.encode(
            image, format: resolveSaveFormat(hasAlpha: false)
        ) else {
            cutoutPhase = .error
            cutoutStatus = "识别失败，可重试"
            return
        }

        let result: SegmentationResult?
        do {
            result = try await visionService.segmentSubject(in: data)
        } catch {
            logger.error("startCutout: 主体分割失败（\(error.localizedDescription)）")
            result = nil
        }
        let guardSnapshot = EditorCutoutGuard(
            pageActive: true,
            photoGeneration: photoGeneration,
            cutoutGeneration: generation,
            targetLayerId: layer.id,
            layerExists: photoLayer() != nil
        )
        let valid = isCutoutResultValid(
            guardSnapshot,
            expectedPhotoGeneration: photoGeneration,
            expectedCutoutGeneration: generation
        )
        // iOS 无近似降级（诚实标注：失败即 error，不用中心裁切冒充 AI 分割）。
        let resolved = resolveCutoutResult(isValid: valid, resultNull: result == nil, isFallback: false)
        cutoutIsFallback = resolved.isFallback
        cutoutStatus = resolved.statusText
        cutoutPhase = resolved.nextPhase

        if resolved.nextPhase == .applied, let seg = result, let baseImage,
           let applied = imageProcessor.applyingCutoutMask(
               to: baseImage, mask: seg.mask, width: seg.bboxWidth, height: seg.bboxHeight
           ) {
            self.baseImage = applied
            photoGeneration += 1
            document.updateLayer(layer.id) { $0.hasAlpha = true }
            saveFormat = resolveSaveFormat(hasAlpha: true)
            resetHistory()
            refreshPhotoImage()
        }
    }

    // MARK: - 保存 / 返回

    private func saveSnapshot() -> EditorSaveSnapshot {
        EditorSaveSnapshot(
            isSaving: isSaving,
            isPhotoLoading: isPhotoLoading,
            photoLoaded: photoLoaded,
            hasUnsavedChanges: hasUnsavedChanges
        )
    }

    /// 打开保存选择（源端 onSave → showSaveChoiceDialog）。
    func requestSave() {
        guard canStartSave(saveSnapshot()) else { return }
        showSaveChoice = true
    }

    func dismissSaveChoice() {
        showSaveChoice = false
    }

    /// 保存编辑产物并回写（不关闭编辑器，等待 saveAndBack/用户返回）。
    func save() async {
        guard canStartSave(saveSnapshot()), let baseImage, let photo else { return }
        isSaving = true
        defer { isSaving = false }

        let format = saveFormat
        guard let data = imageProcessor.renderExport(
            baseImage: baseImage,
            layers: document.getLayers(),
            canvasSize: canvasSize,
            format: format
        ) else {
            errorMessage = "导出失败，请重试"
            return
        }
        do {
            try await saveService.saveEditedPhoto(
                photo, data: data, decision: format,
                width: baseImage.width, height: baseImage.height
            )
        } catch {
            errorMessage = "保存失败，请重试"
        }
    }

    /// 保存并退出编辑器（源端 saveAndBack）。
    func saveAndBack() async {
        showBackConfirm = false
        await save()
        if errorMessage == nil { shouldDismiss = true }
    }

    /// 放弃修改并退出（源端 discardAndBack）。
    func discardAndBack() {
        showBackConfirm = false
        shouldDismiss = true
    }

    /// 返回动作决策（源端 handleBack）：未保存 → 确认；保存中 → 拦截；否则直接退出。
    func back() {
        let action = resolveBackAction(saveSnapshot())
        switch action {
        case .immediateBack:
            shouldDismiss = true
        case .confirmSaveFirst:
            showBackConfirm = true
        case .blockWhileSaving:
            break
        }
    }

    /// 取消返回确认（留在编辑器）。
    func dismissBackConfirm() {
        showBackConfirm = false
    }

    /// 关闭错误提示（View alert 收尾）。
    func dismissError() {
        errorMessage = nil
    }

    // MARK: - 撤销 / 重做

    func undo() {
        history.undo()
        syncFromHistory()
    }

    func redo() {
        history.redo()
        syncFromHistory()
    }

    // MARK: - 内部

    /// 照片底图图层（文档内 zIndex 最低的 photo 图层）。
    private func photoLayer() -> EditorLayer? {
        document.getLayers().first { $0.type == .photo }
    }

    /// 当前快照（JSON）入历史；手势内自动合并。
    private func pushHistory() {
        history.push(document.serialize() ?? "[]")
    }

    /// 像素级操作后：历史基线重置（iOS 差异，见文件头注释）。
    private func resetHistory() {
        history.initialize(document.serialize() ?? "[]")
        syncLayers()
    }

    private func syncFromHistory() {
        if let json = history.current { document.restore(json) }
        syncLayers()
        // 撤销/重做后显示图必须重算（undo 恢复 sharpness=0 → 回到未锐化底图）。
        refreshPhotoImage()
    }

    /// 同步观察状态（不含显示图重算，避免滑块手势中每帧触发锐化卷积）。
    private func syncLayers() {
        layers = document.getLayers()
        canUndo = history.canUndo
        canRedo = history.canRedo
        activeLayerID = document.activeLayer?.id
        if let photoLayer = photoLayer() {
            photoFlipX = photoLayer.flipX
            photoFlipY = photoLayer.flipY
        }
        if tool == .adjust {
            // 面板与照片图层保持同步（源端 syncAdjustmentsFromPhoto：
            // 进入调色工具 / undo / redo 后从图层回读面板）。
            adjustState = syncAdjustPanelState(photoLayer()?.adjustments ?? NEUTRAL_EDITOR_ADJUSTMENTS)
        }
    }

    /// 显示图 = 底图 + 锐化卷积（若 >0）+ 调色（若非中性）。
    /// 锐化不替换底图（对齐源端 releaseSharpenBase：撤销恢复 sharpness=0 回到未锐化）。
    private func refreshPhotoImage() {
        guard let baseImage, let layer = photoLayer() else { return }
        let adj = layer.adjustments
        var rendered = baseImage
        if adj.sharpness > 0 {
            rendered = imageProcessor.applyingSharpen(to: rendered, strength: adj.sharpness)
        }
        if !isNeutral(adj) {
            rendered = imageProcessor.applyingAdjustments(to: rendered, adjustments: adj)
        }
        // 记录本次渲染对应的锐化强度（0 = 未锐化），供下次 end/click 判断。
        renderedSharpness = adj.sharpness > 0 ? adj.sharpness : 0
        photoImage = rendered
    }
}

/// 旋转方向（对应源端 onRotate('cw' | 'ccw')）。
enum RotationDirection {
    case cw
    case ccw
}

/// 翻转轴（对应源端 onFlip('h' | 'v')）。
enum FlipAxis {
    case horizontal
    case vertical
}
