//  EditorPanelVMTests —— 编辑器 5 个面板 VM / 文档控制器的未覆盖编排分支测试。
//  与 EditorViewModelTests 互补：主流程已测，这里覆盖缝隙分支——
//  调色（reset 中性 no-op / 滤镜缩略图缓存与代际失效 / resetSharpness 基准语义）、
//  裁剪（updateCropRect clamp）、文字（编辑面板可见性联动 / photo 层保护）、
//  文档（点选顶层优先且底图不可选 / 贴纸视觉钳制 / 层级钳制 / 旋转累计 / addPassive 不抢占选中）、
//  抠图（processing 中重入拒绝——GatedVisionService 可控挂起）。
//  基建复用 EditorViewModelTests 模式：MockEditorImageProcessing + 内存 repo + 临时 JPEG。

import CoreGraphics
import ImageIO
import MiLensKit
import XCTest
@testable import MiLens

@MainActor
final class EditorPanelVMTests: XCTestCase {

    private var repo: InMemoryPhotoRepository!
    private var processor: MockEditorImageProcessing!
    private var storage: MockFileStorage!
    private var sandboxDir: String!

    override func setUp() {
        super.setUp()
        repo = InMemoryPhotoRepository()
        processor = MockEditorImageProcessing()
        storage = MockFileStorage()
        sandboxDir = NSTemporaryDirectory() + "editor-panel-test-" + UUID().uuidString
    }

    // MARK: - 基础设施

    private func makeVM(photoID: UUID, vision: (any VisionService)? = nil) -> EditorViewModel {
        EditorViewModel(
            photoID: photoID,
            photoRepo: repo,
            visionService: vision ?? MockVisionService(),
            imageProcessor: processor,
            saveService: EditorSaveService(
                mediaLifecycle: MediaLifecycleService(
                    photoRepo: repo, petRepo: InMemoryPetRepository(),
                    fileStorage: storage, sandboxDir: sandboxDir
                ),
                sandboxDir: sandboxDir
            ),
            decorationCatalog: .empty
        )
    }

    private func writeJPEG(url: URL, width: Int, height: Int) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let image = ctx?.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    private func makeLoadedVM(width: Int = 400, height: Int = 300,
                              vision: (any VisionService)? = nil) async -> EditorViewModel {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("editor-panel-" + UUID().uuidString + ".jpg")
        writeJPEG(url: url, width: width, height: height)
        let photo = Photo(uri: url.path, width: width, height: height)
        try? repo.insertPhoto(photo)
        let vm = makeVM(photoID: photo.id, vision: vision)
        await vm.load()
        vm.setCanvasSize(CGSize(width: CGFloat(width), height: CGFloat(height)))
        return vm
    }

    // MARK: - EditorAdjustPanelVM

    /// 中性状态下 reset 为 no-op：不入历史、不触发渲染。
    func testResetNoOpWhenAlreadyNeutral() async {
        let vm = await makeLoadedVM()
        XCTAssertFalse(vm.canUndo)
        XCTAssertEqual(processor.adjustmentCalls, 0, "加载后中性态不应有调色渲染")

        vm.adjustVM.reset()

        XCTAssertFalse(vm.canUndo, "中性 no-op 不得入历史")
        XCTAssertEqual(processor.adjustmentCalls, 0, "中性 no-op 不触发渲染")
        XCTAssertTrue(isAdjustNeutral(vm.adjustVM.state))
    }

    /// 滤镜缩略图按 photoGeneration 缓存：同代命中缓存，代际变化后失效重算。
    func testFilterThumbnailCachedUntilPhotoGenerationChanges() async {
        let vm = await makeLoadedVM()
        let preset = PRESET_FILTERS[1] // vivid
        let base = processor.adjustmentCalls

        XCTAssertNotNil(vm.adjustVM.filterThumbnail(for: preset))
        XCTAssertEqual(processor.adjustmentCalls, base + 1, "首次生成走一次调色渲染")

        XCTAssertNotNil(vm.adjustVM.filterThumbnail(for: preset))
        XCTAssertEqual(processor.adjustmentCalls, base + 1, "同代同预设命中缓存不再渲染")

        vm.photoGeneration += 1 // 像素级操作后底图变化
        XCTAssertNotNil(vm.adjustVM.filterThumbnail(for: preset))
        XCTAssertEqual(processor.adjustmentCalls, base + 2, "代际变化后缓存失效重算")

        XCTAssertNotNil(vm.adjustVM.filterThumbnail(for: preset))
        XCTAssertEqual(processor.adjustmentCalls, base + 2, "新代际内再次命中缓存")
    }

    /// resetSharpness 只复位滑块状态：图层值与渲染基准（renderedSharpness）不动。
    func testResetSharpnessZeroesStateButKeepsRenderedBase() async {
        let vm = await makeLoadedVM()
        vm.adjustVM.onSliderChange(.sharpness, value: 50, phase: .click)
        XCTAssertEqual(vm.adjustVM.state.sharpness, 50)
        XCTAssertEqual(vm.adjustVM.renderedSharpness, 50, "click 且强度变化已触发渲染")

        vm.adjustVM.resetSharpness()

        XCTAssertEqual(vm.adjustVM.state.sharpness, 0, "滑块状态复位")
        XCTAssertEqual(vm.adjustVM.renderedSharpness, 50, "渲染基准保留（不重复卷积的 prev 基准）")
        let photoLayer = vm.document.photoLayer()
        XCTAssertEqual(photoLayer?.adjustments.sharpness ?? -1, 50, "图层值由像素级操作负责复位")
    }

    // MARK: - EditorCropPanelVM

    /// updateCropRect 透传 clampCropRect：负偏移归零、超画布截断、右下角不越界。
    func testUpdateCropRectClampsToCanvasBounds() async {
        let vm = await makeLoadedVM() // 画布 400x300
        vm.selectTool(.crop)

        vm.cropVM.updateCropRect(EditorCropRect(x: -50, y: -40, w: 500, h: 400))

        let rect = vm.cropVM.cropRect
        XCTAssertEqual(rect?.x ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(rect?.y ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(rect?.w ?? -1, 400, accuracy: 0.001, "宽截断到画布宽")
        XCTAssertEqual(rect?.h ?? -1, 300, accuracy: 0.001, "高截断到画布高")
    }

    // MARK: - EditorTextPanelVM

    /// 编辑面板可见性三态：text 层选中且 text 工具 / 工具关闭 / photo 层选中（工具开启）。
    func testShowEditPanelOnlyForActiveTextLayerWithTextTool() async {
        let vm = await makeLoadedVM()
        vm.textVM.textInput = "hello"
        vm.textVM.add()
        XCTAssertEqual(vm.document.activeLayer?.type, .text)

        vm.selectTool(.text)
        XCTAssertTrue(vm.textVM.showEditPanel, "text 层 + text 工具 = 可编辑")

        vm.selectTool(.none)
        XCTAssertFalse(vm.textVM.showEditPanel, "工具关闭后隐藏（选中层保留）")

        vm.selectTool(.text)
        let photoID = vm.document.photoLayer()?.id
        vm.document.select(photoID)
        XCTAssertFalse(vm.textVM.showEditPanel, "photo 层选中时不可编辑文字")
    }

    /// photo 层选中时 updateActiveText 为 no-op：面板值与历史均不变。
    func testUpdateActiveTextIgnoredWhenPhotoLayerSelected() async {
        let vm = await makeLoadedVM()
        vm.textVM.textInput = "hello"
        vm.textVM.add()
        vm.textVM.updateActiveText(fontSize: 40, color: "#FF0000")
        XCTAssertEqual(vm.textVM.selectedTextFontSize, 40)

        let photoID = vm.document.photoLayer()?.id
        vm.document.select(photoID)
        let undoBefore = vm.canUndo

        vm.textVM.updateActiveText(fontSize: 99, color: "#00FF00")

        XCTAssertEqual(vm.textVM.selectedTextFontSize, 40, "非 text 层 no-op 不改面板值")
        XCTAssertEqual(vm.canUndo, undoBefore, "no-op 不入历史")
    }

    /// photo 层受 deleteActiveLayer 保护：底图不可删除。
    func testDeleteActiveLayerProtectsPhotoLayer() async {
        let vm = await makeLoadedVM()
        XCTAssertEqual(vm.document.layers.count, 1)

        let photoID = vm.document.photoLayer()?.id
        vm.document.select(photoID)
        vm.textVM.deleteActiveLayer()

        XCTAssertEqual(vm.document.layers.count, 1, "photo 层删除被 guard 拦截")
    }

    // MARK: - EditorDocumentController

    /// 点选命中：顶层（后添加）优先；photo 底图区域不可选中。
    func testSelectLayerPrefersTopmostAndSkipsPhotoBase() async {
        let vm = await makeLoadedVM() // 画布 400x300
        var sticker = EditorLayer(id: "s1", type: .sticker, x: 200, y: 150, width: 100, height: 80)
        vm.document.add(&sticker)
        var text = createTextLayer(text: "hi", x: 200, y: 150)
        vm.document.add(&text)

        vm.document.selectLayer(at: CGPoint(x: 200, y: 150))
        XCTAssertEqual(vm.document.activeLayer?.type, .text, "重叠区顶层（后添加）优先命中")

        vm.document.selectLayer(at: CGPoint(x: 5, y: 5))
        XCTAssertNil(vm.document.activeLayer, "photo 底图区域不可选中（清空选中）")
    }

    /// 贴纸缩放走视觉尺寸钳制（8%-70% 短边），与 Kit clampStickerVisualScale 输出一致。
    func testScaleActiveLayerClampsStickerVisualRange() async {
        let vm = await makeLoadedVM() // 画布 400x300
        var sticker = EditorLayer(id: "s2", type: .sticker, x: 200, y: 150, width: 100, height: 80)
        vm.document.add(&sticker)
        vm.document.select(sticker.id)

        vm.document.scaleActiveLayer(by: 50, canvasSize: CGSize(width: 400, height: 300))

        let expected = clampStickerVisualScale(
            nativeW: 100, nativeH: 80, scale: 50, canvasW: 400, canvasH: 300)
        XCTAssertEqual(vm.document.activeLayer?.scale ?? -1, expected, accuracy: 0.0001,
                       "贴纸按视觉尺寸钳制而非 MAX_LAYER_SCALE")
        XCTAssertLessThan(vm.document.activeLayer?.scale ?? 6, MAX_LAYER_SCALE)
    }

    /// 非贴纸图层缩放钳制到 [MIN, MAX]_LAYER_SCALE。
    func testScaleActiveLayerClampsTextToLayerScaleRange() async {
        let vm = await makeLoadedVM()
        var text = createTextLayer(text: "clamp", x: 200, y: 150)
        vm.document.add(&text)
        vm.document.select(text.id)

        vm.document.scaleActiveLayer(by: 0.01, canvasSize: CGSize(width: 400, height: 300))
        XCTAssertEqual(vm.document.activeLayer?.scale ?? -1, MIN_LAYER_SCALE, accuracy: 0.0001)

        vm.document.scaleActiveLayer(by: 1000, canvasSize: CGSize(width: 400, height: 300))
        XCTAssertEqual(vm.document.activeLayer?.scale ?? -1, MAX_LAYER_SCALE, accuracy: 0.0001)
    }

    /// 旋转累计入角度；addPassive 添加图层不抢占当前选中。
    func testRotateAccumulatesAndAddPassiveKeepsSelection() async {
        let vm = await makeLoadedVM()
        var text = createTextLayer(text: "rot", x: 200, y: 150)
        vm.document.add(&text)
        vm.document.select(text.id)

        vm.document.rotateActiveLayer(by: 15)
        vm.document.rotateActiveLayer(by: 30)
        XCTAssertEqual(vm.document.activeLayer?.rotation ?? -1, 45, accuracy: 0.0001)

        var extra = EditorLayer(id: "passive1", type: .sticker, x: 30, y: 30, width: 40, height: 40)
        vm.document.addPassive(&extra)
        XCTAssertEqual(vm.document.activeLayer?.type, .text, "addPassive 不改变选中层")
        XCTAssertEqual(vm.document.layers.count, 3)
    }

    // MARK: - EditorCutoutPanelVM（重入守卫）

    /// processing 中二次 start 被拒绝：状态提示 + 不重复 encode；放行后走结果判定。
    func testStartWhileProcessingRejectedByReentryGuard() async {
        let gated = GatedVisionService()
        let vm = await makeLoadedVM(vision: gated)

        let task = Task { await vm.cutoutVM.start() }
        await gated.waitForSegmentEntered() // 此刻 phase == .processing 且已 encode 一次
        XCTAssertEqual(vm.cutoutVM.phase, .processing)
        let encodeAfterFirst = processor.encodeCalls

        await vm.cutoutVM.start() // 重入：被 canStartCutout 拒绝
        XCTAssertEqual(vm.cutoutVM.status, "正在识别主体，请稍候")
        XCTAssertEqual(vm.cutoutVM.phase, .processing, "拒绝不改阶段")
        XCTAssertEqual(processor.encodeCalls, encodeAfterFirst, "重入被拦截不重复编码")

        gated.release()
        await task.value

        XCTAssertEqual(vm.cutoutVM.phase, .error, "挂起放行后 result nil -> error 无降级")
        XCTAssertEqual(vm.cutoutVM.status, "未能识别主体，请重试或更换照片")
    }
}

/// 可控挂起的 VisionService：首次 segmentSubject 挂起直至 release（重入/竞态测试用）。
/// 检测路径始终返回空（编辑器面板测试不涉及）。
private final class GatedVisionService: VisionService, @unchecked Sendable {
    private let lock = NSLock()
    private var entered = false
    private let enteredSignal = AsyncStream<Void>.makeStream()
    private let releaseGate = AsyncStream<Void>.makeStream()

    /// 预设分割结果（默认 nil 模拟识别失败）。
    var segmentationResult: SegmentationResult?

    /// 等待首次 segmentSubject 进入挂起。
    func waitForSegmentEntered() async {
        for await _ in enteredSignal.stream { break }
    }

    /// 放行挂起中的 segmentSubject。
    func release() {
        releaseGate.continuation.yield()
    }

    func detectPets(in imageData: Data) async throws -> [DetectionBox] { [] }

    func segmentSubject(in imageData: Data) async throws -> SegmentationResult? {
        lock.lock()
        let first = !entered
        entered = true
        lock.unlock()
        if first {
            enteredSignal.continuation.yield()
            for await _ in releaseGate.stream { break }
        }
        return segmentationResult
    }
}