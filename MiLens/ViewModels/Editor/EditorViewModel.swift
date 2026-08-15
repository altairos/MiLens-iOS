//  EditorViewModel —— 图片编辑器页面状态机（@Observable，对应源端 EditorPage.ets 编排层）。
//  全部决策走 MiLensKit 纯逻辑（EditorToolLogic/EditorCropOverlay/EditorCropMath/
//  EditorAdjustLogic/EditorCutoutLogic/EditorSaveLogic/EditorTextToolLogic/EditorLayerGeometry），
//  本 VM 只做 IO 编排：加载照片、图像处理（EditorImageProcessing 协议）、保存回写（EditorSaveService）。
//
//  M2 拆分（对应源端多 Controller 模式）：文档/历史 → EditorDocumentController；
//  裁剪/调色/文字/抠图工具域 → EditorCropPanelVM / EditorAdjustPanelVM / EditorTextPanelVM /
//  EditorCutoutPanelVM。子 VM 通过 owner 协作接口（internal 成员）访问底图/画布/渲染刷新。
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
import UIKit

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
    /// 图像处理协议（子 VM 协作接口，internal 只读）。
    let visionService: any VisionService
    let imageProcessor: any EditorImageProcessing
    private let saveService: EditorSaveService

    // MARK: - 文档 / 工具域（M2 拆分）

    /// 文档与历史协作对象（子 VM 共享）。
    let document = EditorDocumentController()
    /// 工具子 VM（M2 拆分）。init 阶段 self 尚未完整初始化无法直接传 owner，
    /// 故延迟到首次访问时创建并注入（语义与 init 创建一致）。
    private var cropVMStorage: EditorCropPanelVM?
    private var adjustVMStorage: EditorAdjustPanelVM?
    private var textVMStorage: EditorTextPanelVM?
    private var cutoutVMStorage: EditorCutoutPanelVM?
    private var decorationVMStorage: EditorDecorationPanelVM?
    var cropVM: EditorCropPanelVM {
        if let vm = cropVMStorage { return vm }
        let vm = EditorCropPanelVM(owner: self)
        cropVMStorage = vm
        return vm
    }
    var adjustVM: EditorAdjustPanelVM {
        if let vm = adjustVMStorage { return vm }
        let vm = EditorAdjustPanelVM(owner: self)
        adjustVMStorage = vm
        return vm
    }
    var textVM: EditorTextPanelVM {
        if let vm = textVMStorage { return vm }
        let vm = EditorTextPanelVM(owner: self)
        textVMStorage = vm
        return vm
    }
    var cutoutVM: EditorCutoutPanelVM {
        if let vm = cutoutVMStorage { return vm }
        let vm = EditorCutoutPanelVM(owner: self)
        cutoutVMStorage = vm
        return vm
    }
    var decorationVM: EditorDecorationPanelVM {
        if let vm = decorationVMStorage { return vm }
        let vm = EditorDecorationPanelVM(owner: self)
        decorationVMStorage = vm
        return vm
    }

    // MARK: - 照片状态

    let photoID: UUID
    /// 当前编辑的照片记录（保存时就地更新）。
    private var photo: Photo?
    /// 像素级底图（裁剪/旋转/抠图后更新；锐化/调色不替换它）。
    /// internal 可写：裁剪/抠图等像素级子 VM 更新后触发观察刷新。
    var baseImage: CGImage?
    /// 当前显示图（底图 + 锐化 + 调色）。
    private(set) var photoImage: CGImage?
    private(set) var isPhotoLoading = true
    private(set) var photoLoaded = false
    /// internal 可写：像素级操作后更新宽高比。
    var photoAspectRatio: Double = 1
    /// 画布尺寸（图片 fit 显示区域，View 报告）。
    private(set) var canvasSize: CGSize = .zero
    private(set) var photoFlipX = false
    private(set) var photoFlipY = false

    // MARK: - 文档观察状态（syncState 从 document 刷新）

    private(set) var layers: [EditorLayer] = []
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var activeLayerID: String?

    // MARK: - 工具

    /// internal 可写：工具域（裁剪/调色等）切换与退出时更新。
    var tool: EditorToolMode = .none
    private(set) var group: EditorToolGroup = .none

    // MARK: - 保存/返回

    private(set) var isSaving = false
    private(set) var showSaveChoice = false
    private(set) var showBackConfirm = false
    /// 编辑会话结束信号（View 监听后 dismiss）。
    private(set) var shouldDismiss = false
    private(set) var errorMessage: String?
    /// internal 可写：抠图应用后切换 PNG 格式。
    var saveFormat: EditorSaveFormatDecision = resolveSaveFormat(hasAlpha: false)
    /// 底图代数（像素级操作递增，抠图结果有效性守卫用）。internal 可写。
    var photoGeneration = 0

    var hasUnsavedChanges: Bool { document.canUndo }

    // MARK: - 初始化

    /// 装饰资源目录（相框/贴纸元数据）；V1.0 默认空目录，由 ViewModelFactory 从
    /// Bundle catalog.json 加载注入。导出与预览按 resourcePath 查 item 构造渲染源。
    /// internal 只读：装饰面板子 VM 与工具门禁共用（协作接口，同 imageProcessor）。
    let decorationCatalog: DecorationCatalog

    /// 装饰工具门禁（开发计划 §10）：catalog 对应类别非空才显示工具入口；
    /// 空 catalog 时无假入口（只显示文字工具，现状不变）。
    var hasFrameItems: Bool { !decorationCatalog.items(for: .frame).isEmpty }
    var hasStickerItems: Bool { !decorationCatalog.items(for: .sticker).isEmpty }

    init(photoID: UUID,
         photoRepo: any PhotoRepositoryProtocol,
         visionService: any VisionService,
         imageProcessor: any EditorImageProcessing,
         saveService: EditorSaveService,
         decorationCatalog: DecorationCatalog = .empty) {
        self.photoID = photoID
        self.photoRepo = photoRepo
        self.visionService = visionService
        self.imageProcessor = imageProcessor
        self.saveService = saveService
        self.decorationCatalog = decorationCatalog
        // 工具子 VM 在首次访问时创建（见 cropVM 等注释）
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
        let maxPixels = Self.editorMaxPixelDimension
        let decoded = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            Self.downsampledImage(at: path, maxPixelDimension: maxPixels)
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
        document.resetHistory()
        isPhotoLoading = false
        photoLoaded = true
        syncState()
    }

    /// View 报告画布尺寸（fit 后的图片显示区域；静默重映射图层，不入历史）。
    /// 阻塞项7：photo/frame 铺满新画布，sticker/text 中心按比例迁移并钳制 scale
    /// （MiLensKit.remapLayersForCanvas）；首次报告（旧画布无效）时仅铺满底图。
    func setCanvasSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != canvasSize else { return }
        let previous = canvasSize
        canvasSize = size
        if previous.width > 0, previous.height > 0 {
            for layer in remapLayersForCanvas(document.layers, from: previous, to: size) {
                document.updateLayer(layer.id) { l in l = layer }
            }
        } else if let layer = document.photoLayer() {
            document.updateLayer(layer.id) { l in
                l.x = size.width / 2
                l.y = size.height / 2
                l.width = size.width
                l.height = size.height
            }
        }
        syncState()
    }

    // MARK: - 工具切换

    func selectTool(_ target: EditorToolMode) {
        let decision = resolveToolToggle(currentTool: tool, targetTool: target)
        tool = decision.newTool
        if decision.shouldInitCrop {
            cropVM.beginCrop()
        }
        syncState()
    }

    func selectGroup(_ target: EditorToolGroup) {
        let decision = resolveGroupToggle(currentGroup: group, targetGroup: target)
        group = decision.newGroup
        tool = decision.newTool
        syncState()
    }

    /// 工具组是否高亮（组内任何工具激活时）。
    func isGroupActive(_ g: EditorToolGroup) -> Bool {
        isGroupTabActive(currentTool: tool, group: g)
    }

    // MARK: - 旋转 / 翻转

    func rotate(_ direction: RotationDirection) {
        guard let baseImage else { return }
        let degrees = direction == .cw ? 90.0 : 270.0
        let rotated = imageProcessor.rotating(baseImage, degrees: degrees)
        self.baseImage = rotated
        if let layer = document.photoLayer() {
            document.updateLayer(layer.id) { l in
                let w = l.width
                l.width = l.height
                l.height = w
                l.adjustments.sharpness = 0
            }
        }
        adjustVM.resetSharpness()
        photoAspectRatio = clampAspectRatio(Double(rotated.width) / Double(rotated.height))
        photoGeneration += 1
        document.resetHistory()
        refreshPhotoImage()
        syncState()
    }

    func flip(_ axis: FlipAxis) {
        guard let layer = document.photoLayer() else { return }
        document.updateLayer(layer.id) { l in
            if axis == .horizontal { l.flipX.toggle() } else { l.flipY.toggle() }
        }
        document.pushHistory()
        syncState()
    }

    // MARK: - 图层手势

    /// 拖动吸附参考线显示状态（M2 质量项，规格 §4.3）：瞬态 UI 状态，不入历史；
    /// 拖动中随吸附决策更新，手势结束/无吸附时复位。View 据此绘制中心参考线。
    private(set) var showsSnapGuideX = false
    private(set) var showsSnapGuideY = false

    func selectLayer(at point: CGPoint) {
        document.selectLayer(at: point)
        syncState()
    }

    func beginLayerGesture() { document.beginGesture() }
    func endLayerGesture() {
        document.endGesture()
        // 手势结束隐藏参考线（吸附仅拖动中生效）
        showsSnapGuideX = false
        showsSnapGuideY = false
    }

    func moveActiveLayer(dx: Double, dy: Double) {
        let snap = document.moveActiveLayer(dx: dx, dy: dy, canvasSize: canvasSize)
        showsSnapGuideX = snap?.snapsX ?? false
        showsSnapGuideY = snap?.snapsY ?? false
        document.pushHistory()
        syncState()
    }

    func scaleActiveLayer(by factor: Double) {
        document.scaleActiveLayer(by: factor, canvasSize: canvasSize)
        document.pushHistory()
        syncState()
    }

    func rotateActiveLayer(by degrees: Double) {
        document.rotateActiveLayer(by: degrees)
        document.pushHistory()
        syncState()
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
        // 清理旧错误：saveAndBack 依赖 errorMessage == nil 判断是否退出，
        // 旧错误残留会导致保存成功后仍不退出。
        errorMessage = nil
        defer { isSaving = false }

        let format = saveFormat
        guard let data = imageProcessor.renderExport(
            baseImage: baseImage,
            layers: document.layers,
            canvasSize: canvasSize,
            format: format,
            decorationProvider: makeDecorationProvider()
        ) else {
            errorMessage = "导出失败，请重试"
            return
        }
        do {
            try await saveService.saveEditedPhoto(
                photo, data: data, decision: format,
                width: baseImage.width, height: baseImage.height
            )
            // 保存成功：重置历史基线，使 hasUnsavedChanges（document.canUndo）回到 false。
            // 否则保存后返回仍提示「有未保存修改」。
            document.resetHistory()
            syncState()
        } catch {
            errorMessage = "保存失败，请重试"
        }
    }

    /// 构造装饰图层素材提供闭包（传给 renderExport）。
    ///
    /// 素材名解析统一走 MiLensKit.resolveDecorationResource（预览与导出共用同一
    /// ratioSet 选图规则，阻塞项5 所见即所得）；加载失败返回 nil（renderExport 自动跳过）。
    private func makeDecorationProvider() -> (String) -> DecorationRenderSource? {
        let catalog = decorationCatalog
        let ratio = photoAspectRatio
        return { resourcePath in
            guard let item = catalog.items.first(where: { $0.resourcePath == resourcePath })
                ?? catalog.find(resourcePath) else { return nil }
            let assetName = resolveDecorationResource(item: item, targetRatio: ratio)
            guard let cg = UIImage(named: assetName)?.cgImage else { return nil }
            return DecorationRenderSource(
                image: cg,
                fitMode: item.fitMode,
                ninePatchInsets: item.ninePatchInsets
            )
        }
    }

    /// 预览侧装饰素材解析（阻塞项4：EditorCanvasView 用；与导出共用
    /// resolveDecorationResource 的 ratioSet 选图；素材缺失返回 nil 不渲染）。
    func resolveDecorationSource(for layer: EditorLayer) -> DecorationPreviewSource? {
        guard let item = decorationCatalog.items.first(where: { $0.resourcePath == layer.resourcePath })
            ?? decorationCatalog.find(layer.resourcePath) else { return nil }
        return DecorationPreviewSource(
            assetName: resolveDecorationResource(item: item, targetRatio: photoAspectRatio),
            fitMode: item.fitMode,
            ninePatchInsets: item.ninePatchInsets
        )
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
        document.undoHistory()
        syncState()
        // 撤销/重做后显示图必须重算（undo 恢复 sharpness=0 → 回到未锐化底图）。
        refreshPhotoImage()
    }

    func redo() {
        document.redoHistory()
        syncState()
        refreshPhotoImage()
    }

    // MARK: - 内部（子 VM 协作接口）

    /// 同步观察状态（文档层 + 工具面板；不含显示图重算，避免滑块手势中每帧触发锐化卷积）。
    func syncState() {
        let currentLayers = document.layers
        layers = currentLayers
        canUndo = document.canUndo
        canRedo = document.canRedo
        activeLayerID = document.activeLayer?.id
        if let photoLayer = document.photoLayer() {
            photoFlipX = photoLayer.flipX
            photoFlipY = photoLayer.flipY
        }
        if tool == .adjust {
            adjustVM.syncFromLayer()
        }
    }

    /// 显示图 = 底图 + 锐化卷积（若 >0）+ 调色（若非中性）。
    /// 锐化不替换底图（对齐源端 releaseSharpenBase：撤销恢复 sharpness=0 回到未锐化）。
    func refreshPhotoImage() {
        guard let baseImage, let layer = document.photoLayer() else { return }
        let adj = layer.adjustments
        var rendered = baseImage
        if adj.sharpness > 0 {
            rendered = imageProcessor.applyingSharpen(to: rendered, strength: adj.sharpness)
        }
        if !isNeutral(adj) {
            rendered = imageProcessor.applyingAdjustments(to: rendered, adjustments: adj)
        }
        // 记录本次渲染对应的锐化强度（0 = 未锐化），供下次 end/click 判断。
        adjustVM.renderedSharpness = adj.sharpness > 0 ? adj.sharpness : 0
        photoImage = rendered
    }

    /// 抠图分割失败日志（cutoutVM 协作接口）。
    func logCutoutFailure(_ error: Error) {
        logger.error("startCutout: 主体分割失败（\(error.localizedDescription)）")
    }

    // MARK: - 图像解码

    /// 编辑器解码最大边长（像素）。导入流程通常限制到 1024px，但编辑器面对
    /// 旧数据或外部大图时无防御性约束，可能导致高内存甚至 OOM。
    /// 4096px 允许高质量编辑同时防止超大原图（如 100MP DSLR）撑爆内存。
    private static let editorMaxPixelDimension: CGFloat = 4096

    /// 用 ImageIO 降采样解码图片，最大边长不超过 maxPixelDimension。
    /// 低于上限的图片按原始尺寸解码（不放大）。
    /// 遵循 DESIGN.md §3「解码缓冲有上限」资源生命周期纪律。
    /// 纯 ImageIO 调用、无隔离状态访问，标记 nonisolated 以便在
    /// Task.detached 后台上下文同步执行（否则静态方法继承类的
    /// @MainActor 隔离，解码会 hop 回主线程，违背后台解码初衷）。
    nonisolated static func downsampledImage(at path: String, maxPixelDimension: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
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
