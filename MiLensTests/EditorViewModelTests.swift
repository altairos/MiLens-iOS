//  EditorViewModelTests —— 编辑器 ViewModel 决策测试（对应 PLAN.md Phase 3 XCTest）。
//  覆盖：加载/失败、工具与组切换、裁剪（初始化/比例/确认=像素级重置历史）、旋转/翻转、
//  调色滑块手势合并、锐化 end 触发、文字（添加/编辑/删除/撤销重做）、
//  抠图（成功/失败无降级）、保存回写（文件 + Photo 就地更新）、返回动作与保存选择、
//  装饰面板（工具门禁/贴纸添加与上限/相框单选替换/Pro 付费墙意图/画布重映射/分组记忆/
//  素材缺失中止保存与面板不可用门禁——开发计划 §7.2/§7.4）。
//  使用 MockEditorImageProcessing + MockFileStorage + 内存 repo（不碰 SwiftData / Core Image）。
//  注意：装饰区段测试未在本地执行（Windows 环境无法跑 App target XCTest），待 Mac/CI 验证。

import CoreGraphics
import ImageIO
import MiLensKit
import XCTest
@testable import MiLens

@MainActor
final class EditorViewModelTests: XCTestCase {

    private var repo: InMemoryPhotoRepository!
    private var vision: MockVisionService!
    private var processor: MockEditorImageProcessing!
    private var storage: MockFileStorage!
    private var sandboxDir: String!

    override func setUp() {
        super.setUp()
        repo = InMemoryPhotoRepository()
        vision = MockVisionService()
        processor = MockEditorImageProcessing()
        storage = MockFileStorage()
        sandboxDir = NSTemporaryDirectory() + "editor-test-\(UUID().uuidString)"
    }

    // MARK: - 基础设施

    private func makeVM(photoID: UUID, decorationCatalog: DecorationCatalog = .empty) -> EditorViewModel {
        EditorViewModel(
            photoID: photoID,
            photoRepo: repo,
            visionService: vision,
            imageProcessor: processor,
            saveService: EditorSaveService(
                mediaLifecycle: MediaLifecycleService(
                    photoRepo: repo, petRepo: InMemoryPetRepository(),
                    fileStorage: storage, sandboxDir: sandboxDir
                ),
                sandboxDir: sandboxDir
            ),
            decorationCatalog: decorationCatalog
        )
    }

    /// 写一张 width×height 的 JPEG 到临时目录并入库，返回已 load 的 VM。
    private func makeLoadedVM(width: Int = 400, height: Int = 300,
                              catalog: DecorationCatalog = .empty) async -> EditorViewModel {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("editor-\(UUID().uuidString).jpg")
        writeJPEG(url: url, width: width, height: height)
        let photo = Photo(uri: url.path, width: width, height: height)
        try? repo.insertPhoto(photo)
        let vm = makeVM(photoID: photo.id, decorationCatalog: catalog)
        await vm.load()
        vm.setCanvasSize(CGSize(width: CGFloat(width), height: CGFloat(height)))
        return vm
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

    private func fullMask(width: Int, height: Int) -> SegmentationResult {
        SegmentationResult(
            mask: Data(repeating: 255, count: width * height),
            bboxX: 0, bboxY: 0, bboxWidth: width, bboxHeight: height
        )
    }

    // MARK: - 加载

    func testLoadDecodesPhotoAndSetsBaseline() async {
        let vm = await makeLoadedVM(width: 400, height: 300)
        XCTAssertTrue(vm.photoLoaded)
        XCTAssertFalse(vm.isPhotoLoading)
        XCTAssertEqual(vm.photoAspectRatio, 4.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(vm.layers.count, 1)
        XCTAssertEqual(vm.layers.first?.type, .photo)
        XCTAssertFalse(vm.canUndo)
        XCTAssertFalse(vm.canRedo)
    }

    func testLoadMissingFileShowsError() async {
        let photo = Photo(uri: NSTemporaryDirectory() + "missing-\(UUID().uuidString).jpg")
        try? repo.insertPhoto(photo)
        let vm = makeVM(photoID: photo.id)
        await vm.load()
        XCTAssertFalse(vm.photoLoaded)
        XCTAssertEqual(vm.errorMessage, "照片加载失败")
    }

    // MARK: - 工具 / 组切换

    func testSelectToolTogglesAndInitializesCrop() async {
        let vm = await makeLoadedVM()
        vm.selectTool(.crop)
        XCTAssertEqual(vm.tool, .crop)
        XCTAssertNotNil(vm.cropVM.cropRect)
        // 再次点击同一工具 → 关闭
        vm.selectTool(.crop)
        XCTAssertEqual(vm.tool, .none)
    }

    func testGroupToggleAndHighlight() async {
        let vm = await makeLoadedVM()
        vm.selectGroup(.adjust)
        XCTAssertEqual(vm.group, .adjust)
        XCTAssertEqual(vm.tool, .none)
        vm.selectTool(.adjust)
        XCTAssertTrue(vm.isGroupActive(.adjust))
        XCTAssertFalse(vm.isGroupActive(.decorate))
        // 再点当前组 → 折叠
        vm.selectGroup(.adjust)
        XCTAssertEqual(vm.group, .none)
        XCTAssertEqual(vm.tool, .none)
    }

    // MARK: - 裁剪

    func testCropRatioSelectionUpdatesRect() async {
        let vm = await makeLoadedVM()
        vm.selectTool(.crop)
        vm.cropVM.selectCropRatio(1) // 1:1
        XCTAssertEqual(vm.cropVM.cropRect?.w ?? 0, vm.cropVM.cropRect?.h ?? 1, accuracy: 0.001)
    }

    func testConfirmCropIsPixelLevelAndResetsHistory() async {
        let vm = await makeLoadedVM()
        vm.flip(.horizontal) // 先制造可撤销状态
        XCTAssertTrue(vm.canUndo)

        vm.selectTool(.crop)
        vm.cropVM.selectCropRatio(1) // 1:1 → 240×240（画布 400×300 的 80% 内适配）
        vm.cropVM.confirmCrop()

        XCTAssertEqual(processor.cropCalls, 1)
        XCTAssertEqual(vm.photoAspectRatio, 1.0, accuracy: 0.001)
        XCTAssertFalse(vm.canUndo) // 像素级操作重置历史
        XCTAssertNil(vm.cropVM.cropRect)
        XCTAssertEqual(vm.tool, .none)
    }

    func testCancelCropClearsOverlay() async {
        let vm = await makeLoadedVM()
        vm.selectTool(.crop)
        vm.cropVM.cancelCrop()
        XCTAssertNil(vm.cropVM.cropRect)
        XCTAssertEqual(vm.tool, .none)
    }

    // MARK: - 旋转 / 翻转

    func testRotateIsPixelLevelAndResetsHistory() async {
        let vm = await makeLoadedVM()
        // 旋转后尺寸交换：400×300 → 300×400 → 400×300（mock 按调用序列返回）。
        processor.rotateResults = [
            makeTestCGImage(width: 300, height: 400),
            makeTestCGImage(width: 400, height: 300),
        ]
        vm.rotate(.cw)
        XCTAssertEqual(processor.rotateCalls, [90])
        XCTAssertEqual(vm.photoAspectRatio, 3.0 / 4.0, accuracy: 0.001) // 400×300 → 300×400
        XCTAssertFalse(vm.canUndo)
        vm.rotate(.ccw)
        XCTAssertEqual(processor.rotateCalls, [90, 270])
        XCTAssertEqual(vm.photoAspectRatio, 4.0 / 3.0, accuracy: 0.001)
    }

    func testFlipIsPropertyLevelAndUndoable() async {
        let vm = await makeLoadedVM()
        vm.flip(.horizontal)
        XCTAssertTrue(vm.photoFlipX)
        XCTAssertFalse(vm.photoFlipY)
        XCTAssertTrue(vm.canUndo)

        vm.undo()
        XCTAssertFalse(vm.photoFlipX)
        XCTAssertFalse(vm.canUndo)

        vm.redo()
        XCTAssertTrue(vm.photoFlipX)
    }

    // MARK: - 调色

    func testAdjustSliderGestureMergesIntoOneHistory() async {
        let vm = await makeLoadedVM()
        vm.selectTool(.adjust)

        vm.adjustVM.onSliderChange(.brightness, value: 10, phase: .begin)
        vm.adjustVM.onSliderChange(.brightness, value: 15, phase: .moving)
        vm.adjustVM.onSliderChange(.brightness, value: 30, phase: .moving)
        vm.adjustVM.onSliderChange(.brightness, value: 30, phase: .end)

        XCTAssertEqual(vm.adjustVM.state.brightness, 30)
        XCTAssertTrue(vm.canUndo)

        vm.undo()
        XCTAssertEqual(vm.adjustVM.state.brightness, 0) // 手势合并为一条历史
        vm.redo()
        XCTAssertEqual(vm.adjustVM.state.brightness, 30)
    }

    func testSharpnessAppliesOnlyOnGestureEnd() async {
        let vm = await makeLoadedVM()
        vm.selectTool(.adjust)

        vm.adjustVM.onSliderChange(.sharpness, value: 40, phase: .begin)
        vm.adjustVM.onSliderChange(.sharpness, value: 60, phase: .moving)
        XCTAssertTrue(processor.sharpenCalls.isEmpty) // 拖动中不触发卷积

        vm.adjustVM.onSliderChange(.sharpness, value: 60, phase: .end)
        XCTAssertEqual(processor.sharpenCalls, [60])
        XCTAssertTrue(vm.canUndo)

        // 撤销恢复 sharpness=0 → 不再锐化（releaseSharpenBase 语义）
        vm.undo()
        XCTAssertEqual(vm.adjustVM.state.sharpness, 0)
    }

    func testAdjustStateSyncsFromPhotoOnToolEntry() async {
        let vm = await makeLoadedVM()
        vm.selectTool(.adjust)
        vm.adjustVM.onSliderChange(.temperature, value: 25, phase: .click)

        vm.selectGroup(.decorate) // 离开调色
        XCTAssertEqual(vm.adjustVM.state.temperature, 25) // 面板保留
        vm.selectTool(.adjust)
        XCTAssertEqual(vm.adjustVM.state.temperature, 25) // 从图层同步回来
    }

    func testResetAdjustmentsRestoresNeutral() async {
        let vm = await makeLoadedVM()
        vm.selectTool(.adjust)
        vm.adjustVM.onSliderChange(.contrast, value: 50, phase: .click)
        XCTAssertFalse(isAdjustNeutral(vm.adjustVM.state))

        vm.adjustVM.reset()
        XCTAssertTrue(isAdjustNeutral(vm.adjustVM.state))
        XCTAssertTrue(vm.canUndo)
    }

    // MARK: - 预设滤镜（iOS 端新增）

    func testApplyPresetSyncsStateAndLayer() async {
        let vm = await makeLoadedVM()
        vm.selectTool(.adjust)
        let vivid = PRESET_FILTERS.first { $0.id == "vivid" }!
        vm.adjustVM.applyPreset(vivid)
        // state 从图层回读，等于预设值即证明图层已写入
        XCTAssertEqual(vm.adjustVM.state.contrast, 20)
        XCTAssertEqual(vm.adjustVM.state.saturation, 30)
        XCTAssertEqual(vm.adjustVM.state.sharpness, 0)
        XCTAssertEqual(vm.adjustVM.selectedFilterID, "vivid")
        XCTAssertTrue(vm.canUndo)
    }

    func testManualSliderChangeClearsFilterHighlight() async {
        let vm = await makeLoadedVM()
        vm.selectTool(.adjust)
        vm.adjustVM.applyPreset(PRESET_FILTERS.first { $0.id == "vivid" }!)
        XCTAssertEqual(vm.adjustVM.selectedFilterID, "vivid")
        // 手动微调对比度（偏离 vivid 预设的 20）→ 自动取消高亮
        vm.adjustVM.onSliderChange(.contrast, value: 21, phase: .click)
        XCTAssertNil(vm.adjustVM.selectedFilterID)
    }

    func testOriginalPresetEqualsReset() async {
        let vm = await makeLoadedVM()
        vm.selectTool(.adjust)
        vm.adjustVM.applyPreset(PRESET_FILTERS.first { $0.id == "warm" }!)
        XCTAssertEqual(vm.adjustVM.selectedFilterID, "warm")
        // 选原图预设 = 回到中性
        vm.adjustVM.applyPreset(ORIGINAL_PRESET_FILTER)
        XCTAssertTrue(isAdjustNeutral(vm.adjustVM.state))
        XCTAssertEqual(vm.adjustVM.selectedFilterID, "original")
    }

    func testSlidersCollapsedByDefault() async {
        let vm = await makeLoadedVM()
        vm.selectTool(.adjust)
        XCTAssertFalse(vm.adjustVM.isSlidersExpanded)
        vm.adjustVM.toggleSlidersExpanded()
        XCTAssertTrue(vm.adjustVM.isSlidersExpanded)
    }

    func testEnterAdjustHighlightsOriginalWhenNeutral() async {
        let vm = await makeLoadedVM()
        vm.selectTool(.adjust)
        // 进入调色时参数中性 → 高亮原图
        XCTAssertEqual(vm.adjustVM.selectedFilterID, "original")
    }

    // MARK: - 文字

    func testAddTextCreatesActiveLayer() async {
        let vm = await makeLoadedVM()
        vm.textVM.textInput = "你好世界"
        vm.textVM.textColor = "#FF0000"
        vm.textVM.textStrokeEnabled = false
        vm.textVM.add()

        XCTAssertEqual(vm.layers.count, 2)
        let textLayer = vm.layers.last
        XCTAssertEqual(textLayer?.type, .text)
        XCTAssertEqual(textLayer?.text, "你好世界")
        XCTAssertEqual(textLayer?.fontColor, "#FF0000")
        XCTAssertEqual(textLayer?.strokeWidth, 0) // 描边关闭
        XCTAssertEqual(vm.activeLayerID, textLayer?.id)
        XCTAssertTrue(vm.textVM.showEditPanel)
        XCTAssertEqual(vm.textVM.textInput, "") // 添加后清空输入
    }

    func testAddTextRequiresNonEmptyInput() async {
        let vm = await makeLoadedVM()
        vm.textVM.textInput = "   "
        vm.textVM.add()
        XCTAssertEqual(vm.layers.count, 1)
    }

    func testUpdateAndDeleteActiveTextLayer() async {
        let vm = await makeLoadedVM()
        vm.textVM.textInput = "喵"
        vm.textVM.add()
        let deletedID = vm.layers.last?.id

        vm.textVM.updateActiveText(fontSize: 60, color: "#00FF00")
        let updated = vm.layers.last
        XCTAssertEqual(updated?.fontSize, 60)
        XCTAssertEqual(updated?.fontColor, "#00FF00")
        XCTAssertEqual(vm.textVM.selectedTextFontSize, 60)
        XCTAssertEqual(vm.textVM.selectedTextColor, "#00FF00")

        vm.textVM.deleteActiveLayer()
        XCTAssertEqual(vm.layers.count, 1)
        // 删除后选区回退到照片层（源端 removeLayer 后 activeLayer 指向剩余末层）。
        XCTAssertNotNil(vm.activeLayerID)
        XCTAssertNotEqual(vm.activeLayerID, deletedID)
        XCTAssertEqual(vm.activeLayerID, vm.layers.first?.id)
    }

    func testUndoRedoTextLayer() async {
        let vm = await makeLoadedVM()
        vm.textVM.textInput = "喵"
        vm.textVM.add()
        XCTAssertEqual(vm.layers.count, 2)

        vm.undo()
        XCTAssertEqual(vm.layers.count, 1)
        vm.redo()
        XCTAssertEqual(vm.layers.count, 2)
        XCTAssertEqual(vm.layers.last?.text, "喵")
    }

    // MARK: - 抠图

    func testCutoutSuccessAppliesAlphaAndPNGFormat() async {
        let vm = await makeLoadedVM()
        vision.presetSegmentation = fullMask(width: 400, height: 300)

        await vm.cutoutVM.start()

        XCTAssertEqual(vm.cutoutVM.phase, .applied)
        XCTAssertEqual(processor.cutoutCalls, 1)
        XCTAssertEqual(processor.encodeCalls, 1)
        XCTAssertTrue(vm.layers.first(where: { $0.type == .photo })?.hasAlpha ?? false)
        XCTAssertEqual(vm.saveFormat.format, "image/png")
        XCTAssertFalse(vm.canUndo) // 像素级操作重置历史
    }

    func testCutoutFailureIsErrorWithoutFallback() async {
        let vm = await makeLoadedVM()
        vision.presetSegmentation = nil // 模拟识别失败

        await vm.cutoutVM.start()

        XCTAssertEqual(vm.cutoutVM.phase, .error)
        XCTAssertFalse(vm.cutoutVM.isFallback) // 诚实标注：无近似降级
        XCTAssertEqual(processor.cutoutCalls, 0)
    }

    // MARK: - 保存 / 返回

    func testSaveWritesFileAndUpdatesPhotoInPlace() async {
        let vm = await makeLoadedVM()
        let photo = repo.photos[0]
        processor.renderExportResult = Data([0x89, 0x50, 0x4E, 0x47, 0x0D])

        await vm.save()

        XCTAssertEqual(processor.renderExportCalls, 1)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNotNil(repo.updatedPhoto)
        // 编辑产物写入 Edits 子目录（允许备份，与排除备份的导入副本分区）
        XCTAssertTrue(photo.uri.hasPrefix(sandboxDir + "/Edits/MiLens_Edit_"))
        XCTAssertTrue(storage.fileExists(at: photo.uri))
        XCTAssertEqual(photo.category, PhotoCategory.edited.rawValue,
                       "保存产物回写「作品」分类（§9.2 ⑥；Service 级见 MediaLifecycleServiceTests）")
        XCTAssertEqual(photo.thumbnailPath, "") // 缩略图回退 uri
        XCTAssertEqual(photo.width, 400)
        XCTAssertEqual(photo.height, 300)
        XCTAssertEqual(photo.fileSize, 5)
        XCTAssertEqual(photo.uri.hasSuffix(".jpg"), true) // 无 alpha → JPEG
    }

    func testSaveFailureShowsExportError() async {
        let vm = await makeLoadedVM()
        processor.renderExportFails = true

        await vm.save()

        XCTAssertEqual(vm.errorMessage, "导出失败，请重试")
        XCTAssertNil(repo.updatedPhoto)
    }

    func testSaveAndBackDismissesAfterSuccess() async {
        let vm = await makeLoadedVM()
        processor.renderExportResult = Data([1, 2, 3])

        await vm.saveAndBack()

        XCTAssertTrue(vm.shouldDismiss)
        XCTAssertNil(vm.errorMessage)
    }

    func testSaveResetsDirtyBaseline() async {
        let vm = await makeLoadedVM()
        processor.renderExportResult = Data([1, 2, 3])

        vm.flip(.horizontal)
        XCTAssertTrue(vm.canUndo, "编辑后应有可撤销状态")
        XCTAssertTrue(vm.hasUnsavedChanges)

        await vm.save()

        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.canUndo, "保存成功后历史基线应重置")
        XCTAssertFalse(vm.hasUnsavedChanges, "保存后不应再提示未保存修改")
    }

    func testSaveClearsStaleErrorBeforeAttempt() async {
        let vm = await makeLoadedVM()
        processor.renderExportResult = Data([1, 2, 3])

        // 第一次保存失败（导出失败）
        processor.renderExportFails = true
        await vm.save()
        XCTAssertEqual(vm.errorMessage, "导出失败，请重试")

        // 第二次保存成功：旧错误应被清理，不应残留
        processor.renderExportFails = false
        await vm.save()
        XCTAssertNil(vm.errorMessage, "保存开始时应清理旧错误")
    }

    func testSaveAndBackExitsEvenAfterPriorFailure() async {
        let vm = await makeLoadedVM()
        processor.renderExportResult = Data([1, 2, 3])

        // 先制造一个失败的保存
        processor.renderExportFails = true
        await vm.save()
        XCTAssertNotNil(vm.errorMessage)

        // 再成功保存并返回：saveAndBack 应退出
        processor.renderExportFails = false
        await vm.saveAndBack()

        XCTAssertTrue(vm.shouldDismiss, "旧错误清理后 saveAndBack 应正常退出")
        XCTAssertNil(vm.errorMessage)
    }

    func testRequestSaveOnlyWhenPhotoLoaded() async {
        // 用真实 JPEG 文件，保证 load 成功（假文件会使 photoLoaded=false，测不到弹窗）。
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("editor-request-save-\(UUID().uuidString).jpg")
        writeJPEG(url: url, width: 100, height: 100)
        let photo = Photo(uri: url.path, width: 100, height: 100)
        try? repo.insertPhoto(photo)
        let vm = makeVM(photoID: photo.id)

        // 未加载完成 → 不可保存
        vm.requestSave()
        XCTAssertFalse(vm.showSaveChoice)

        await vm.load()
        vm.requestSave()
        XCTAssertTrue(vm.showSaveChoice)
        vm.dismissSaveChoice()
        XCTAssertFalse(vm.showSaveChoice)
    }

    func testBackActionsByUnsavedState() async {
        // 无修改 → 直接退出
        let clean = await makeLoadedVM()
        clean.back()
        XCTAssertTrue(clean.shouldDismiss)

        // 有修改 → 确认弹窗
        let dirty = await makeLoadedVM()
        dirty.flip(.horizontal)
        dirty.back()
        XCTAssertFalse(dirty.shouldDismiss)
        XCTAssertTrue(dirty.showBackConfirm)

        dirty.dismissBackConfirm()
        XCTAssertFalse(dirty.showBackConfirm)

        // 放弃修改退出
        dirty.back()
        dirty.discardAndBack()
        XCTAssertTrue(dirty.shouldDismiss)
    }

    // MARK: - 装饰面板（相框/贴纸）
    // 未执行：Windows 环境无法跑 App target XCTest，待 Mac/CI 验证。

    /// 测试用装饰目录：frame（film 组 a/b + holiday 组 Pro）、sticker（paw 组 + daily 组 Pro）。
    private func makeDecorationCatalog() -> DecorationCatalog {
        DecorationCatalog(items: [
            DecorationItem(id: "frame_a", name: "相框A", category: .frame,
                           resourcePath: "frame_a", previewPath: "frame_a", group: "film"),
            DecorationItem(id: "frame_b", name: "相框B", category: .frame,
                           resourcePath: "frame_b", previewPath: "frame_b", group: "film"),
            DecorationItem(id: "frame_pro", name: "节日Pro相框", category: .frame,
                           resourcePath: "frame_pro", previewPath: "frame_pro",
                           isPremium: true, group: "holiday"),
            DecorationItem(id: "sticker_paw", name: "爪印", category: .sticker,
                           resourcePath: "sticker_paw", previewPath: "sticker_paw", group: "paw"),
            DecorationItem(id: "sticker_pro", name: "日常Pro贴纸", category: .sticker,
                           resourcePath: "sticker_pro", previewPath: "sticker_pro",
                           isPremium: true, group: "daily"),
        ])
    }

    /// 工具入口门禁（§10）：catalog 对应类别非空才显示入口；空 catalog 无假入口。
    func testDecorationToolGatesFollowCatalog() async {
        // 空 catalog（素材后补的现状）→ 双入口隐藏
        let empty = await makeLoadedVM()
        XCTAssertFalse(empty.hasFrameItems)
        XCTAssertFalse(empty.hasStickerItems)

        // 双类别齐全 → 双入口
        let full = await makeLoadedVM(catalog: makeDecorationCatalog())
        XCTAssertTrue(full.hasFrameItems)
        XCTAssertTrue(full.hasStickerItems)

        // 仅 frame → 贴纸入口仍隐藏
        let framesOnly = await makeLoadedVM(catalog: DecorationCatalog(items: [
            DecorationItem(id: "frame_a", name: "相框A", category: .frame,
                           resourcePath: "frame_a", previewPath: "frame_a"),
        ]))
        XCTAssertTrue(framesOnly.hasFrameItems)
        XCTAssertFalse(framesOnly.hasStickerItems)
    }

    /// 添加贴纸：创建图层 + 选中（手势链前提）+ 一次 push 可撤销。
    func testAddStickerCreatesSelectedUndoableLayer() async {
        let vm = await makeLoadedVM(catalog: makeDecorationCatalog())
        vm.selectTool(.sticker)
        let sticker = vm.decorationCatalog.find("sticker_paw")!

        vm.decorationVM.addSticker(sticker, isPro: true)

        XCTAssertEqual(vm.layers.count, 2)
        let added = vm.layers.last
        XCTAssertEqual(added?.type, .sticker)
        XCTAssertEqual(added?.resourcePath, "sticker_paw")
        XCTAssertEqual(vm.activeLayerID, added?.id)
        XCTAssertTrue(vm.decorationVM.hasActiveSticker)
        XCTAssertTrue(vm.canUndo)

        vm.undo()
        XCTAssertEqual(vm.layers.count, 1)
        XCTAssertNil(vm.layers.first { $0.type == .sticker })
    }

    /// 贴纸上限（STICKER_LAYER_LIMIT=20）：第 21 个被拦 + 提示置位，View 复位后可再试。
    func testStickerLimitBlocksAtTwentyAndShowsToast() async {
        let vm = await makeLoadedVM(catalog: makeDecorationCatalog())
        vm.selectTool(.sticker)
        let sticker = vm.decorationCatalog.find("sticker_paw")!

        for _ in 0..<STICKER_LAYER_LIMIT {
            vm.decorationVM.addSticker(sticker, isPro: true)
        }
        XCTAssertEqual(vm.layers.filter { $0.type == .sticker }.count, STICKER_LAYER_LIMIT)

        vm.decorationVM.addSticker(sticker, isPro: true) // 第 21 个
        XCTAssertEqual(vm.layers.filter { $0.type == .sticker }.count, STICKER_LAYER_LIMIT)
        XCTAssertTrue(vm.decorationVM.showsStickerLimitToast)

        vm.decorationVM.clearStickerLimitToast()
        XCTAssertFalse(vm.decorationVM.showsStickerLimitToast)
    }

    /// Pro 判定：锁定项点击不改文档、置付费墙意图；isPro=true 同一素材可直接使用。
    func testPremiumDecorationTriggersPaywallIntentOnlyWhenLocked() async {
        let vm = await makeLoadedVM(catalog: makeDecorationCatalog())

        vm.selectTool(.sticker)
        vm.decorationVM.addSticker(vm.decorationCatalog.find("sticker_pro")!, isPro: false)
        XCTAssertEqual(vm.layers.count, 1) // 文档未改
        XCTAssertEqual(vm.decorationVM.pendingPaywallItem?.id, "sticker_pro")

        vm.decorationVM.clearPaywallIntent()
        vm.decorationVM.addSticker(vm.decorationCatalog.find("sticker_pro")!, isPro: true)
        XCTAssertEqual(vm.layers.count, 2)
        XCTAssertNil(vm.decorationVM.pendingPaywallItem)

        vm.selectTool(.frame)
        vm.decorationVM.applyFrame(vm.decorationCatalog.find("frame_pro")!, isPro: false)
        XCTAssertNil(vm.decorationVM.currentFrameResourcePath)
        XCTAssertEqual(vm.decorationVM.pendingPaywallItem?.id, "frame_pro")
    }

    /// 相框单选替换：唯一 frame + 铺满画布 + 不可选中；同资源短路；替换为整体一条历史。
    func testApplyFrameReplacesSoleFrameWithSingleHistoryStep() async {
        let vm = await makeLoadedVM(catalog: makeDecorationCatalog()) // 画布 400×300
        vm.selectTool(.frame)

        vm.decorationVM.applyFrame(vm.decorationCatalog.find("frame_a")!, isPro: true)
        XCTAssertEqual(vm.layers.filter { $0.type == .frame }.count, 1)
        XCTAssertEqual(vm.decorationVM.currentFrameResourcePath, "frame_a")
        let frame = vm.layers.first { $0.type == .frame }!
        XCTAssertEqual(frame.x, 200, accuracy: 0.5) // 画布中心铺满
        XCTAssertEqual(frame.y, 150, accuracy: 0.5)
        XCTAssertEqual(frame.width, 400, accuracy: 0.5)
        XCTAssertEqual(frame.height, 300, accuracy: 0.5)
        XCTAssertNil(vm.activeLayerID) // 相框不可选中（阻塞项6）

        // 换 B：仍是唯一 frame（单选替换）
        vm.decorationVM.applyFrame(vm.decorationCatalog.find("frame_b")!, isPro: true)
        XCTAssertEqual(vm.layers.filter { $0.type == .frame }.count, 1)
        XCTAssertEqual(vm.decorationVM.currentFrameResourcePath, "frame_b")

        // 点击当前已选相框：保持选中，不重复创建（§4.2）
        vm.decorationVM.applyFrame(vm.decorationCatalog.find("frame_b")!, isPro: true)
        XCTAssertEqual(vm.layers.filter { $0.type == .frame }.count, 1)

        // 撤销链：B → A → 无（替换为整体一条记录）
        vm.undo()
        XCTAssertEqual(vm.decorationVM.currentFrameResourcePath, "frame_a")
        vm.undo()
        XCTAssertNil(vm.decorationVM.currentFrameResourcePath)
    }

    /// 标题行图标动作：移除相框（可撤销恢复）；删除贴纸（非贴纸选中态静默）。
    func testRemoveFrameAndDeleteStickerHeaderActions() async {
        let vm = await makeLoadedVM(catalog: makeDecorationCatalog())
        vm.selectTool(.frame)
        vm.decorationVM.applyFrame(vm.decorationCatalog.find("frame_a")!, isPro: true)

        vm.decorationVM.removeFrame()
        XCTAssertEqual(vm.layers.filter { $0.type == .frame }.count, 0)
        XCTAssertNil(vm.decorationVM.currentFrameResourcePath)
        vm.undo()
        XCTAssertEqual(vm.decorationVM.currentFrameResourcePath, "frame_a")

        // 非贴纸选中态（照片/相框/nil）静默，不误删
        vm.selectTool(.sticker)
        let before = vm.layers.count
        vm.decorationVM.deleteActiveSticker()
        XCTAssertEqual(vm.layers.count, before)

        // 添加后选中的贴纸可被标题行动作删除
        vm.decorationVM.addSticker(vm.decorationCatalog.find("sticker_paw")!, isPro: true)
        XCTAssertTrue(vm.decorationVM.hasActiveSticker)
        vm.decorationVM.deleteActiveSticker()
        XCTAssertEqual(vm.layers.filter { $0.type == .sticker }.count, 0)
    }

    /// 素材错误诊断（开发计划 §7.4）：导出预检发现必需素材缺失 → 中止保存，
    /// errorMessage 含素材名（可诊断）且渲染层不被触碰（无「静默缺层成功品」）。
    func testSaveAbortsWhenDecorationAssetMissing() async {
        let vm = await makeLoadedVM(catalog: makeDecorationCatalog())
        vm.selectTool(.frame)
        vm.decorationVM.applyFrame(vm.decorationCatalog.find("frame_a")!, isPro: true)
        XCTAssertEqual(vm.layers.filter { $0.type == .frame }.count, 1)

        // catalog 有条目但 bundle 内无对应图片（测试环境天然缺失）
        await vm.save()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("frame_a") == true)
        XCTAssertEqual(processor.renderExportCalls, 0, "预检拦截，渲染层不被触碰")
    }

    /// 面板不可用门禁（§7.2）：上报解码失败的素材被拦在文档外（贴纸/相框双路径）。
    func testUnavailableDecorationBlockedFromDocument() async {
        let vm = await makeLoadedVM(catalog: makeDecorationCatalog())

        vm.selectTool(.sticker)
        let sticker = vm.decorationCatalog.find("sticker_paw")!
        vm.decorationVM.markPreviewUnavailable(sticker.previewPath)
        XCTAssertTrue(vm.decorationVM.isAssetUnavailable(sticker))
        vm.decorationVM.addSticker(sticker, isPro: true)
        XCTAssertEqual(vm.layers.count, 1, "不可用贴纸不入文档")

        vm.selectTool(.frame)
        let frame = vm.decorationCatalog.find("frame_a")!
        vm.decorationVM.markPreviewUnavailable(frame.previewPath)
        vm.decorationVM.applyFrame(frame, isPro: true)
        XCTAssertNil(vm.decorationVM.currentFrameResourcePath)
        XCTAssertEqual(vm.layers.filter { $0.type == .frame }.count, 0, "不可用相框不入文档")
    }

    /// 手势合并（§9.2 ④）：装饰层连续拖/缩/旋一次撤销整段回退——View 层 onChanged
    /// 高频调用 move/scale/rotate（每次 pushHistory），begin/endLayerGesture 之间
    /// 只压一条手势前基线（Kit EditorHistory 手势合并）。
    func testDecorationGestureMergesIntoSingleUndoStep() async {
        let vm = await makeLoadedVM(catalog: makeDecorationCatalog())
        vm.selectTool(.sticker)
        vm.decorationVM.addSticker(vm.decorationCatalog.find("sticker_paw")!, isPro: true)
        let base = vm.layers.first { $0.type == .sticker }!
        // 拖 (254,96)→(269,111)：两轴距中心线均远超吸附阈值，断言不受吸附干扰
        vm.beginLayerGesture()
        vm.moveActiveLayer(dx: 5, dy: 5)
        vm.moveActiveLayer(dx: 5, dy: 5)
        vm.moveActiveLayer(dx: 5, dy: 5)
        vm.scaleActiveLayer(by: 1.2)
        vm.scaleActiveLayer(by: 1.1)
        vm.rotateActiveLayer(by: 15)
        vm.rotateActiveLayer(by: 15)
        vm.endLayerGesture()

        let moved = vm.layers.first { $0.type == .sticker }!
        XCTAssertEqual(moved.x, base.x + 15, accuracy: 1e-9)
        XCTAssertEqual(moved.y, base.y + 15, accuracy: 1e-9)
        XCTAssertEqual(moved.scale, base.scale * 1.2 * 1.1, accuracy: 1e-9)
        XCTAssertEqual(moved.rotation, base.rotation + 30, accuracy: 1e-9)

        // 一次撤销整段手势回退到贴纸初始状态（不逐帧回退）
        vm.undo()
        let restored = vm.layers.first { $0.type == .sticker }!
        XCTAssertEqual(restored.x, base.x, accuracy: 1e-9)
        XCTAssertEqual(restored.y, base.y, accuracy: 1e-9)
        XCTAssertEqual(restored.scale, base.scale, accuracy: 1e-9)
        XCTAssertEqual(restored.rotation, base.rotation, accuracy: 1e-9)
    }

    /// 画布变化重映射（阻塞项7）：frame 重新铺满，sticker 中心按比例迁移 + scale 按短边比缩放。
    func testSetCanvasSizeRemapsFrameAndSticker() async {
        let vm = await makeLoadedVM(catalog: makeDecorationCatalog()) // 画布 400×300
        vm.selectTool(.frame)
        vm.decorationVM.applyFrame(vm.decorationCatalog.find("frame_a")!, isPro: true)
        vm.selectTool(.sticker)
        vm.decorationVM.addSticker(vm.decorationCatalog.find("sticker_paw")!, isPro: true)
        let stickerBefore = vm.layers.first { $0.type == .sticker }!

        vm.setCanvasSize(CGSize(width: 800, height: 600))

        let frame = vm.layers.first { $0.type == .frame }!
        XCTAssertEqual(frame.x, 400, accuracy: 0.5)
        XCTAssertEqual(frame.y, 300, accuracy: 0.5)
        XCTAssertEqual(frame.width, 800, accuracy: 0.5)
        XCTAssertEqual(frame.height, 600, accuracy: 0.5)

        let sticker = vm.layers.first { $0.type == .sticker }!
        XCTAssertEqual(sticker.x, stickerBefore.x * 2, accuracy: 1) // 中心归一化迁移
        XCTAssertEqual(sticker.y, stickerBefore.y * 2, accuracy: 1)
        XCTAssertEqual(sticker.scale, stickerBefore.scale * 2, accuracy: 0.01) // 短边比缩放（22%→44% 未触钳制）
    }

    /// 分组稳定序（常量序内仅出现有素材的组）+ 分组索引按类别独立记忆。
    func testDecorationGroupOrderAndPerCategoryMemory() async {
        let vm = await makeLoadedVM(catalog: makeDecorationCatalog())
        vm.selectTool(.frame)
        XCTAssertEqual(vm.decorationVM.groups.map(\.id), ["film", "holiday"])

        vm.decorationVM.selectGroup(1)
        XCTAssertEqual(vm.decorationVM.currentGroup?.id, "holiday")

        // 切到贴纸：分组索引独立记忆（首组 paw，不继承相框的 holiday）
        vm.selectTool(.sticker)
        XCTAssertEqual(vm.decorationVM.groups.map(\.id), ["paw", "daily"])
        XCTAssertEqual(vm.decorationVM.currentGroup?.id, "paw")

        // 切回相框：恢复记忆的 holiday
        vm.selectTool(.frame)
        XCTAssertEqual(vm.decorationVM.currentGroup?.id, "holiday")
    }

    /// 空 catalog（素材后补现状）：分组空、无当前组（View 据此显示空态），无选中态。
    func testEmptyCatalogDecorationPanelShowsEmptyState() async {
        let vm = await makeLoadedVM()
        XCTAssertTrue(vm.decorationVM.groups.isEmpty)
        XCTAssertNil(vm.decorationVM.currentGroup)
        XCTAssertNil(vm.decorationVM.currentFrameResourcePath)
        XCTAssertFalse(vm.decorationVM.hasActiveSticker)
    }

    // MARK: - 拖动吸附 / 中心参考线（M2 质量项，规格 §4.3）
    // 未执行：Windows 环境无法跑 App target XCTest，待 Mac/CI 验证。
    // 首个贴纸落点（画布 400×300）：短边 300×22%=66，偏移 18%×300=54 → 中心 (254, 96)；
    // 画布中心线 (200, 150)。阈值 LAYER_SNAP_THRESHOLD=6。

    /// 增量语义守护：连续两次 dx=10 → 总位移 20（View 层 DragGesture 差值传入的前提）。
    func testMoveActiveLayerUsesIncrementalDeltas() async {
        let vm = await makeLoadedVM(catalog: makeDecorationCatalog())
        vm.selectTool(.sticker)
        vm.decorationVM.addSticker(vm.decorationCatalog.find("sticker_paw")!, isPro: true)

        vm.moveActiveLayer(dx: 10, dy: 5)
        vm.moveActiveLayer(dx: 10, dy: 5)

        let sticker = vm.layers.first { $0.type == .sticker }!
        XCTAssertEqual(sticker.x, 254 + 20, accuracy: 1e-9)
        XCTAssertEqual(sticker.y, 96 + 10, accuracy: 1e-9)
        XCTAssertFalse(vm.showsSnapGuideX) // 两轴距中心均远超阈值，无参考线
        XCTAssertFalse(vm.showsSnapGuideY)
    }

    /// 进入阈值吸附：y 轴先入阈值（吸附 + 水平参考线），再 x 轴入阈值（双参考线）；
    /// 手势结束后参考线隐藏（吸附仅拖动中生效）。
    func testDragWithinThresholdSnapsAndShowsGuides() async {
        let vm = await makeLoadedVM(catalog: makeDecorationCatalog())
        vm.selectTool(.sticker)
        vm.decorationVM.addSticker(vm.decorationCatalog.find("sticker_paw")!, isPro: true)

        vm.beginLayerGesture()
        // (254,96) → (207,148)：x 距中心 7（>6 不吸附），y 距中心 2（≤6 吸附）
        vm.moveActiveLayer(dx: -47, dy: 52)
        var sticker = vm.layers.first { $0.type == .sticker }!
        XCTAssertEqual(sticker.x, 207, accuracy: 1e-9)
        XCTAssertEqual(sticker.y, 150, accuracy: 1e-9)
        XCTAssertFalse(vm.showsSnapGuideX)
        XCTAssertTrue(vm.showsSnapGuideY)

        // (207,148) → (200,148)：x 进入阈值，双轴吸附对齐
        vm.moveActiveLayer(dx: -7, dy: 0)
        sticker = vm.layers.first { $0.type == .sticker }!
        XCTAssertEqual(sticker.x, 200, accuracy: 1e-9)
        XCTAssertEqual(sticker.y, 150, accuracy: 1e-9)
        XCTAssertTrue(vm.showsSnapGuideX)
        XCTAssertTrue(vm.showsSnapGuideY)

        // 手势结束：参考线复位
        vm.endLayerGesture()
        XCTAssertFalse(vm.showsSnapGuideX)
        XCTAssertFalse(vm.showsSnapGuideY)
    }

    /// 离开阈值立即释放（无滞后）：同一手势内从吸附态拖离，位置原样、参考线熄灭。
    func testDragBeyondThresholdReleasesImmediately() async {
        let vm = await makeLoadedVM(catalog: makeDecorationCatalog())
        vm.selectTool(.sticker)
        vm.decorationVM.addSticker(vm.decorationCatalog.find("sticker_paw")!, isPro: true)

        vm.beginLayerGesture()
        vm.moveActiveLayer(dx: -54, dy: 54) // → (200,150) 精确中心，双轴吸附
        XCTAssertTrue(vm.showsSnapGuideX)
        XCTAssertTrue(vm.showsSnapGuideY)

        vm.moveActiveLayer(dx: 20, dy: 0) // → (220,150)：x 离开阈值立即释放，y 保持吸附
        let sticker = vm.layers.first { $0.type == .sticker }!
        XCTAssertEqual(sticker.x, 220, accuracy: 1e-9)
        XCTAssertEqual(sticker.y, 150, accuracy: 1e-9)
        XCTAssertFalse(vm.showsSnapGuideX)
        XCTAssertTrue(vm.showsSnapGuideY)
    }

    /// 中心 clamp：拖出画布时中心钳在 [0, W]×[0, H]（保留半幅可见可拖回）。
    func testDragCenterClampedToCanvasBounds() async {
        let vm = await makeLoadedVM(catalog: makeDecorationCatalog())
        vm.selectTool(.sticker)
        vm.decorationVM.addSticker(vm.decorationCatalog.find("sticker_paw")!, isPro: true)

        vm.beginLayerGesture()
        vm.moveActiveLayer(dx: -300, dy: 300) // → (-46,396)：clamp 到 (0,300)
        let sticker = vm.layers.first { $0.type == .sticker }!
        XCTAssertEqual(sticker.x, 0, accuracy: 1e-9)
        XCTAssertEqual(sticker.y, 300, accuracy: 1e-9)
        XCTAssertFalse(vm.showsSnapGuideX)
        XCTAssertFalse(vm.showsSnapGuideY)
    }

    /// 无活动图层：移动静默（photo 为 passive 不可选），参考线保持隐藏。
    func testMoveWithoutActiveLayerKeepsGuidesHidden() async {
        let vm = await makeLoadedVM()
        XCTAssertNil(vm.activeLayerID)

        vm.moveActiveLayer(dx: 10, dy: 10)

        XCTAssertEqual(vm.layers.count, 1) // 仅底图，位置不变
        XCTAssertEqual(vm.layers[0].x, 200, accuracy: 1e-9)
        XCTAssertEqual(vm.layers[0].y, 150, accuracy: 1e-9)
        XCTAssertFalse(vm.showsSnapGuideX)
        XCTAssertFalse(vm.showsSnapGuideY)
    }
}
