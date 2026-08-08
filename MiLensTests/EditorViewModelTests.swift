//  EditorViewModelTests —— 编辑器 ViewModel 决策测试（对应 PLAN.md Phase 3 XCTest）。
//  覆盖：加载/失败、工具与组切换、裁剪（初始化/比例/确认=像素级重置历史）、旋转/翻转、
//  调色滑块手势合并、锐化 end 触发、文字（添加/编辑/删除/撤销重做）、
//  抠图（成功/失败无降级）、保存回写（文件 + Photo 就地更新）、返回动作与保存选择。
//  使用 MockEditorImageProcessing + MockFileStorage + 内存 repo（不碰 SwiftData / Core Image）。

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

    private func makeVM(photoID: UUID) -> EditorViewModel {
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
            )
        )
    }

    /// 写一张 width×height 的 JPEG 到临时目录并入库，返回已 load 的 VM。
    private func makeLoadedVM(width: Int = 400, height: Int = 300) async -> EditorViewModel {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("editor-\(UUID().uuidString).jpg")
        writeJPEG(url: url, width: width, height: height)
        let photo = Photo(uri: url.path, width: width, height: height)
        try? repo.insertPhoto(photo)
        let vm = makeVM(photoID: photo.id)
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
        XCTAssertNotNil(vm.cropRect)
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
        vm.selectCropRatio(1) // 1:1
        XCTAssertEqual(vm.cropRect?.w ?? 0, vm.cropRect?.h ?? 1, accuracy: 0.001)
    }

    func testConfirmCropIsPixelLevelAndResetsHistory() async {
        let vm = await makeLoadedVM()
        vm.flip(.horizontal) // 先制造可撤销状态
        XCTAssertTrue(vm.canUndo)

        vm.selectTool(.crop)
        vm.selectCropRatio(1) // 1:1 → 240×240（画布 400×300 的 80% 内适配）
        vm.confirmCrop()

        XCTAssertEqual(processor.cropCalls, 1)
        XCTAssertEqual(vm.photoAspectRatio, 1.0, accuracy: 0.001)
        XCTAssertFalse(vm.canUndo) // 像素级操作重置历史
        XCTAssertNil(vm.cropRect)
        XCTAssertEqual(vm.tool, .none)
    }

    func testCancelCropClearsOverlay() async {
        let vm = await makeLoadedVM()
        vm.selectTool(.crop)
        vm.cancelCrop()
        XCTAssertNil(vm.cropRect)
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

        vm.onAdjustSliderChange(.brightness, value: 10, phase: .begin)
        vm.onAdjustSliderChange(.brightness, value: 15, phase: .moving)
        vm.onAdjustSliderChange(.brightness, value: 30, phase: .moving)
        vm.onAdjustSliderChange(.brightness, value: 30, phase: .end)

        XCTAssertEqual(vm.adjustState.brightness, 30)
        XCTAssertTrue(vm.canUndo)

        vm.undo()
        XCTAssertEqual(vm.adjustState.brightness, 0) // 手势合并为一条历史
        vm.redo()
        XCTAssertEqual(vm.adjustState.brightness, 30)
    }

    func testSharpnessAppliesOnlyOnGestureEnd() async {
        let vm = await makeLoadedVM()
        vm.selectTool(.adjust)

        vm.onAdjustSliderChange(.sharpness, value: 40, phase: .begin)
        vm.onAdjustSliderChange(.sharpness, value: 60, phase: .moving)
        XCTAssertTrue(processor.sharpenCalls.isEmpty) // 拖动中不触发卷积

        vm.onAdjustSliderChange(.sharpness, value: 60, phase: .end)
        XCTAssertEqual(processor.sharpenCalls, [60])
        XCTAssertTrue(vm.canUndo)

        // 撤销恢复 sharpness=0 → 不再锐化（releaseSharpenBase 语义）
        vm.undo()
        XCTAssertEqual(vm.adjustState.sharpness, 0)
    }

    func testAdjustStateSyncsFromPhotoOnToolEntry() async {
        let vm = await makeLoadedVM()
        vm.selectTool(.adjust)
        vm.onAdjustSliderChange(.temperature, value: 25, phase: .click)

        vm.selectGroup(.decorate) // 离开调色
        XCTAssertEqual(vm.adjustState.temperature, 25) // 面板保留
        vm.selectTool(.adjust)
        XCTAssertEqual(vm.adjustState.temperature, 25) // 从图层同步回来
    }

    func testResetAdjustmentsRestoresNeutral() async {
        let vm = await makeLoadedVM()
        vm.selectTool(.adjust)
        vm.onAdjustSliderChange(.contrast, value: 50, phase: .click)
        XCTAssertFalse(isAdjustNeutral(vm.adjustState))

        vm.resetAdjustments()
        XCTAssertTrue(isAdjustNeutral(vm.adjustState))
        XCTAssertTrue(vm.canUndo)
    }

    // MARK: - 文字

    func testAddTextCreatesActiveLayer() async {
        let vm = await makeLoadedVM()
        vm.textInput = "你好世界"
        vm.textColor = "#FF0000"
        vm.textStrokeEnabled = false
        vm.addText()

        XCTAssertEqual(vm.layers.count, 2)
        let textLayer = vm.layers.last
        XCTAssertEqual(textLayer?.type, .text)
        XCTAssertEqual(textLayer?.text, "你好世界")
        XCTAssertEqual(textLayer?.fontColor, "#FF0000")
        XCTAssertEqual(textLayer?.strokeWidth, 0) // 描边关闭
        XCTAssertEqual(vm.activeLayerID, textLayer?.id)
        XCTAssertTrue(vm.showTextLayerEditPanel)
        XCTAssertEqual(vm.textInput, "") // 添加后清空输入
    }

    func testAddTextRequiresNonEmptyInput() async {
        let vm = await makeLoadedVM()
        vm.textInput = "   "
        vm.addText()
        XCTAssertEqual(vm.layers.count, 1)
    }

    func testUpdateAndDeleteActiveTextLayer() async {
        let vm = await makeLoadedVM()
        vm.textInput = "喵"
        vm.addText()
        let deletedID = vm.layers.last?.id

        vm.updateActiveText(fontSize: 60, color: "#00FF00")
        let updated = vm.layers.last
        XCTAssertEqual(updated?.fontSize, 60)
        XCTAssertEqual(updated?.fontColor, "#00FF00")
        XCTAssertEqual(vm.selectedTextFontSize, 60)
        XCTAssertEqual(vm.selectedTextColor, "#00FF00")

        vm.deleteActiveLayer()
        XCTAssertEqual(vm.layers.count, 1)
        // 删除后选区回退到照片层（源端 removeLayer 后 activeLayer 指向剩余末层）。
        XCTAssertNotNil(vm.activeLayerID)
        XCTAssertNotEqual(vm.activeLayerID, deletedID)
        XCTAssertEqual(vm.activeLayerID, vm.layers.first?.id)
    }

    func testUndoRedoTextLayer() async {
        let vm = await makeLoadedVM()
        vm.textInput = "喵"
        vm.addText()
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

        await vm.startCutout()

        XCTAssertEqual(vm.cutoutPhase, .applied)
        XCTAssertEqual(processor.cutoutCalls, 1)
        XCTAssertEqual(processor.encodeCalls, 1)
        XCTAssertTrue(vm.layers.first(where: { $0.type == .photo })?.hasAlpha ?? false)
        XCTAssertEqual(vm.saveFormat.format, "image/png")
        XCTAssertFalse(vm.canUndo) // 像素级操作重置历史
    }

    func testCutoutFailureIsErrorWithoutFallback() async {
        let vm = await makeLoadedVM()
        vision.presetSegmentation = nil // 模拟识别失败

        await vm.startCutout()

        XCTAssertEqual(vm.cutoutPhase, .error)
        XCTAssertFalse(vm.cutoutIsFallback) // 诚实标注：无近似降级
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
        XCTAssertTrue(photo.uri.hasPrefix(sandboxDir + "/MiLens_Edit_"))
        XCTAssertTrue(storage.fileExists(at: photo.uri))
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
}

// MARK: - 纯内存 mock

/// 内存照片仓储：记录就地更新（EditorSaveService 回写断言用）。
@MainActor
private final class InMemoryPhotoRepository: PhotoRepositoryProtocol {
    private(set) var photos: [Photo]
    private(set) var updatedPhoto: Photo?

    init(photos: [Photo] = []) {
        self.photos = photos
    }

    func insertPhoto(_ photo: Photo) throws { photos.append(photo) }
    func getPhoto(id: UUID) throws -> Photo? { photos.first { $0.id == id } }
    func getPhotoByURI(_ uri: String) throws -> Photo? { photos.first { $0.uri == uri } }
    func getPhotoByOriginalURI(_ originalURI: String) throws -> Photo? { photos.first { $0.originalURI == originalURI } }
    func getAllOriginalURIs() throws -> Set<String> { Set(photos.map(\.originalURI)) }
    func getAllPhotoURIs() throws -> Set<String> { Set(photos.map(\.uri)) }
    func getPhotosPage(offset: Int, limit: Int) throws -> [Photo] {
        Array(photos.sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }.dropFirst(offset).prefix(limit))
    }
    func getPhotosByPet(_ pet: Pet) throws -> [Photo] {
        photos.filter { $0.pet?.id == pet.id }
    }
    func getAnniversaryPhotos(month: Int, day: Int, excludeYear: Int?) throws -> [Photo] { [] }
    func deletePhoto(_ photo: Photo) throws { photos.removeAll { $0.id == photo.id } }
    func updatePhoto(_ photo: Photo) throws { updatedPhoto = photo }
    func assignPhoto(_ photo: Photo, to pet: Pet?) throws { photo.pet = pet }
    func setFavorite(_ photo: Photo, favorite: Bool) throws { photo.isFavorite = favorite }
    func updateNote(_ photo: Photo, note: String) throws { photo.note = note }
    func getPendingQualityScorePhotos(limit: Int) throws -> [Photo] { [] }
    func getDuplicateCandidates() throws -> [Photo] { [] }
    func updateQualityData(_ photo: Photo, sharpness: Double, qualityScore: Double, phash: String) throws {}
    func replaceDuplicateMarks(_ groups: [DuplicateMarkGroup]) throws {}
}

/// 内存宠物仓储（编辑保存链路不触碰宠物，最简实现即可）。
@MainActor
private final class InMemoryPetRepository: PetRepositoryProtocol {
    private var pets: [Pet] = []
    func getAllPets() throws -> [Pet] { pets }
    func getPet(id: UUID) throws -> Pet? { pets.first { $0.id == id } }
    func insertPet(_ pet: Pet) throws { pets.append(pet) }
    func updatePet(_ pet: Pet) throws {}
    func deletePet(_ pet: Pet) throws { pets.removeAll { $0.id == pet.id } }
    func refreshPhotoCount(for pet: Pet) throws {}
}
