//  BeadViewModelTests —— 拼豆图纸状态机单测。
//  覆盖：load 路由赋值、generate 三层守卫（重入/每日配额/缺源图）、成功/失败/取消路径、
//  CLIP 语义按源图缓存、视图模式规范化与画布缩放钳制（Kit 纯函数在 VM 接线层的透传）、
//  export / prepareShareFile / preparePDFFile 的守卫与 toast 反馈、toast 自动清除。
//  依赖全协议注入：InMemoryPhotoRepository + MockVisionService + MockClipInference +
//  BeadExportService(photoLibrary: MockPhotoLibraryAccess) + QuotaSpy（自写配额记账 spy）。
//  成功路径需要真实可解码图片：setUp 阶段写临时 PNG，tearDown 统一清理。

import XCTest
import UIKit
import MiLensKit
@testable import MiLens

@MainActor
final class BeadViewModelTests: XCTestCase {

    private var tempFilePaths: [String] = []

    override func tearDown() {
        for path in tempFilePaths {
            try? FileManager.default.removeItem(atPath: path)
        }
        tempFilePaths.removeAll()
        super.tearDown()
    }

    // MARK: - 工厂与辅助

    /// 生成一张纯色 PNG（成功路径需要 decodeToRGBA 可解码的真实数据）。
    private func makePNGData(side: Int = 32) throws -> Data {
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(red: 0.75, green: 0.45, blue: 0.25, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = try XCTUnwrap(ctx.makeImage())
        return try XCTUnwrap(UIImage(cgImage: image).pngData())
    }

    /// 写临时 PNG 并返回绝对路径（tearDown 统一清理）。
    @discardableResult
    private func writeSamplePNG(side: Int = 32) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bead-vm-\(UUID().uuidString).png")
        try makePNGData(side: side).write(to: url)
        tempFilePaths.append(url.path)
        return url.path
    }

    private func makeVM(
        photo: Photo? = nil,
        vision: MockVisionService = MockVisionService(),
        clip: (any ClipInference)? = nil,
        library: MockPhotoLibraryAccess = MockPhotoLibraryAccess(),
        isPro: Bool = false,
        quotaUsedToday: Int = 0
    ) -> (vm: BeadViewModel, quota: QuotaSpy, repo: InMemoryPhotoRepository) {
        let repo = InMemoryPhotoRepository(photos: photo.map { [$0] } ?? [])
        let quota = QuotaSpy(usedToday: quotaUsedToday)
        let vm = BeadViewModel(
            photoRepo: repo,
            vision: vision,
            clipService: clip,
            exportService: BeadExportService(photoLibrary: library),
            isPro: isPro,
            quotaStore: quota
        )
        return (vm, quota, repo)
    }

    /// 构造已加载有效源图的 VM（photoURI 为 private(set)，走 load(photoID:) 正式入口）。
    private func makeLoadedVM(
        vision: MockVisionService = MockVisionService(),
        clip: (any ClipInference)? = nil,
        library: MockPhotoLibraryAccess = MockPhotoLibraryAccess(),
        isPro: Bool = false,
        quotaUsedToday: Int = 0
    ) async throws -> (vm: BeadViewModel, quota: QuotaSpy) {
        let photo = Photo(uri: try writeSamplePNG())
        let made = makeVM(photo: photo, vision: vision, clip: clip,
                          library: library, isPro: isPro, quotaUsedToday: quotaUsedToday)
        await made.vm.load(photoID: photo.id)
        return (made.vm, made.quota)
    }

    /// 等待生成 Task 到终态（离开 generating）。
    private func waitForGenerationSettled(_ vm: BeadViewModel, timeoutMs: Int = 10_000) async {
        for _ in 0..<(timeoutMs / 10) {
            guard case .generating = vm.phase else { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// 等待导出 Task 完成（export() 同步置位 isExporting 后才可调用）。
    private func waitForExportSettled(_ vm: BeadViewModel, timeoutMs: Int = 15_000) async {
        for _ in 0..<(timeoutMs / 10) {
            if !vm.isExporting { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// 配额记账 spy：预设 usedToday，记录 recordSuccessfulGeneration 调用次数。
    private final class QuotaSpy: BeadGenerationQuotaStore, @unchecked Sendable {
        var usedToday: Int
        private(set) var recordedCount = 0

        init(usedToday: Int = 0) {
            self.usedToday = usedToday
        }

        func recordSuccessfulGeneration() {
            recordedCount += 1
            usedToday += 1
        }
    }

    // MARK: - 初始状态与设置

    func testInitialStateDefaults() {
        let vm = makeVM().vm
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertNil(vm.pattern)
        XCTAssertEqual(vm.viewMode, "color")
        XCTAssertEqual(vm.cellSize, 8)
        XCTAssertEqual(vm.canvasScale, 1.0)
        XCTAssertFalse(vm.isExporting)
        XCTAssertNil(vm.toastMessage)
        XCTAssertTrue(vm.photoURI.isEmpty)
        XCTAssertTrue(vm.thumbnailPath.isEmpty)
        XCTAssertEqual(vm.settings, defaultBeadSettings())
        XCTAssertFalse(vm.showAdvancedSettings)
    }

    func testApplyPresetMatchesKitResolver() {
        let vm = makeVM().vm
        vm.applyPreset("pixel_art")
        XCTAssertEqual(vm.settings, applyStylePreset("pixel_art"))
        vm.applyPreset("no-such-style")
        XCTAssertEqual(vm.settings, applyStylePreset("no-such-style"), "未知 key 由 Kit 兜底预设回退")
    }

    func testSetViewModeNormalizesInvalidValue() {
        let vm = makeVM().vm
        vm.setViewMode("letter")
        XCTAssertEqual(vm.viewMode, "letter")
        vm.setViewMode("mard")
        XCTAssertEqual(vm.viewMode, "mard")
        vm.setViewMode("bogus")
        XCTAssertEqual(vm.viewMode, "color", "非法模式应规范化回退 color")
    }

    func testStepCanvasScaleClampsToBoundaries() {
        let vm = makeVM().vm
        vm.stepCanvasScale(-100)
        XCTAssertEqual(vm.canvasScale, 0.5, "缩放下界 0.5")
        vm.stepCanvasScale(0.25)
        XCTAssertEqual(vm.canvasScale, 0.75)
        vm.stepCanvasScale(100)
        XCTAssertEqual(vm.canvasScale, 5.0, "缩放上界 5.0")
    }

    // MARK: - 源图加载

    func testLoadPhotoSetsSourcePaths() async {
        let photo = Photo(uri: "/tmp/a.png", thumbnailPath: "/tmp/a_thumb.png")
        let made = makeVM(photo: photo)
        await made.vm.load(photoID: photo.id)
        XCTAssertEqual(made.vm.photoURI, "/tmp/a.png")
        XCTAssertEqual(made.vm.thumbnailPath, "/tmp/a_thumb.png")
    }

    func testLoadMissingPhotoLeavesStateUnchanged() async {
        let made = makeVM()
        await made.vm.load(photoID: UUID())
        XCTAssertTrue(made.vm.photoURI.isEmpty, "照片不存在时静默返回")
        XCTAssertTrue(made.vm.thumbnailPath.isEmpty)
    }

    // MARK: - generate 守卫

    func testGenerateWithoutSourceShowsMissingSourceToast() {
        let made = makeVM()
        made.vm.generate()
        XCTAssertEqual(made.vm.toastMessage, .missingSource)
        XCTAssertEqual(made.vm.phase, .idle, "缺源图不得启动生成任务")
        XCTAssertEqual(made.quota.recordedCount, 0)
    }

    func testGenerateBlockedWhenFreeQuotaExhausted() async throws {
        let made = try await makeLoadedVM(quotaUsedToday: CommercialRules.freeBeadGenerationsPerDay)
        made.vm.generate()
        XCTAssertEqual(made.vm.toastMessage, .generationLimitReached)
        XCTAssertEqual(made.vm.phase, .idle, "配额拦截不得启动生成任务")
        XCTAssertEqual(made.quota.recordedCount, 0)
    }

    func testProEntitlementBypassesQuotaAndSkipsAccounting() async throws {
        // 免费配额已耗尽，但 updateEntitlement 升级 Pro 后应不受限且不记账。
        let made = try await makeLoadedVM(quotaUsedToday: CommercialRules.freeBeadGenerationsPerDay)
        made.vm.updateEntitlement(isPro: true)
        made.vm.generate()
        await waitForGenerationSettled(made.vm)
        XCTAssertEqual(made.vm.phase, .success, "Pro 用户不受每日免费配额限制")
        XCTAssertEqual(made.quota.recordedCount, 0, "Pro 生成不记账")
    }

    func testGenerateRejectedWhileGenerating() async throws {
        let made = try await makeLoadedVM()
        made.vm.generate()
        // MainActor 尚未让出、生成 Task 未启动，phase 停在 generating——
        // 重入守卫先于配额/缺图检查，直接返回且不产生任何 toast。
        made.vm.generate()
        XCTAssertNil(made.vm.toastMessage, "重入拦截不应触发其他守卫的 toast")
        await waitForGenerationSettled(made.vm)
        XCTAssertEqual(made.vm.phase, .success, "首次生成正常完成")
        XCTAssertEqual(made.quota.recordedCount, 1)
    }

    // MARK: - 生成路径

    func testGenerateSuccessProducesPatternPreviewAndAccounting() async throws {
        let vision = MockVisionService(detections: [
            DetectionBox(x: 0.2, y: 0.15, width: 0.5, height: 0.6, label: "cat", confidence: 0.9)
        ])
        let made = try await makeLoadedVM(vision: vision)
        made.vm.generate()
        await waitForGenerationSettled(made.vm)

        XCTAssertEqual(made.vm.phase, .success)
        let pattern = try XCTUnwrap(made.vm.pattern)
        XCTAssertEqual(made.vm.cellSize, computeCellSize(patternWidth: pattern.width))
        XCTAssertEqual(made.vm.canvasScale, 1.0, "新图纸画布缩放复位")
        XCTAssertNotNil(made.vm.previewImage, "成功后应渲染结果预览")
        XCTAssertEqual(made.quota.recordedCount, 1, "非 Pro 成功生成记账一次")
        XCTAssertEqual(made.quota.usedToday, 1)
    }

    func testGenerateWithCutoutDisabledSkipsSegmentation() async throws {
        // settings.cutout = false 应跳过抠图分支（默认 true 走降级路径由成功用例覆盖）。
        let made = try await makeLoadedVM()
        made.vm.settings.cutout = false
        made.vm.generate()
        await waitForGenerationSettled(made.vm)
        XCTAssertEqual(made.vm.phase, .success)
        XCTAssertNotNil(made.vm.pattern)
    }

    func testGenerateDecodeFailureSetsFailurePhase() async throws {
        // 路径有效但内容不是图片 → decodeToRGBA 返回 nil → decodeFailed。
        let badURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bead-vm-bad-\(UUID().uuidString).bin")
        try Data("not-an-image".utf8).write(to: badURL)
        tempFilePaths.append(badURL.path)
        let photo = Photo(uri: badURL.path)
        let made = makeVM(photo: photo)
        await made.vm.load(photoID: photo.id)

        made.vm.generate()
        await waitForGenerationSettled(made.vm)

        XCTAssertEqual(made.vm.phase, .failure)
        XCTAssertEqual(made.vm.toastMessage, .generationFailed)
        XCTAssertNil(made.vm.pattern)
        XCTAssertEqual(made.quota.recordedCount, 0, "失败不消耗配额")
    }

    func testCancelGenerationReturnsToIdle() async throws {
        let made = try await makeLoadedVM()
        made.vm.generate()
        // 同步取消：生成 Task 尚未启动即被标记取消，内部 checkCancellation 抛出后回 idle。
        made.vm.cancelGeneration()
        await waitForGenerationSettled(made.vm)
        XCTAssertEqual(made.vm.phase, .idle, "无已展示结果时取消应回到 idle")
        XCTAssertNil(made.vm.pattern)
        XCTAssertNil(made.vm.toastMessage, "取消不是失败，不弹 toast")
        XCTAssertEqual(made.quota.recordedCount, 0, "取消不记账")
    }

    func testCLIPDetectionRunsOncePerSource() async throws {
        let clip = MockClipInference()
        let made = try await makeLoadedVM(clip: clip)
        made.vm.generate()
        await waitForGenerationSettled(made.vm)
        XCTAssertEqual(made.vm.phase, .success)

        made.vm.generate() // 同一源图再次生成
        await waitForGenerationSettled(made.vm)
        XCTAssertEqual(made.vm.phase, .success)
        XCTAssertEqual(clip.detectCallCount, 1, "同一源图的 CLIP 语义检测应缓存复用")
    }

    // MARK: - 导出 / 分享

    func testExportWithoutPatternIsRejected() {
        let library = MockPhotoLibraryAccess()
        let vm = makeVM(library: library).vm
        vm.export()
        XCTAssertFalse(vm.isExporting, "无图纸时导出守卫直接拦截")
        XCTAssertTrue(library.saveCalls.isEmpty)
    }

    func testPrepareShareAndPDFWithoutPatternReturnNil() async {
        let vm = makeVM().vm
        let shareURL = await vm.prepareShareFile()
        XCTAssertNil(shareURL)
        let pdfURL = await vm.preparePDFFile()
        XCTAssertNil(pdfURL)
        XCTAssertFalse(vm.isExporting, "守卫拦截后 isExporting 不应被置位")
    }

    func testExportSuccessSavesAndShowsToast() async throws {
        let library = MockPhotoLibraryAccess()
        let made = try await makeLoadedVM(library: library)
        made.vm.generate()
        await waitForGenerationSettled(made.vm)
        XCTAssertEqual(made.vm.phase, .success)

        made.vm.export()
        await waitForExportSettled(made.vm)

        XCTAssertEqual(made.vm.toastMessage, .exportSuccess)
        XCTAssertEqual(library.saveCalls.count, 1, "A4 PNG 应保存到系统相册")
        XCTAssertFalse(made.vm.isExporting, "导出完成后复位导出状态")
    }

    func testExportFailureShowsFailedToast() async throws {
        let library = MockPhotoLibraryAccess()
        library.saveError = PhotoLibraryError.saveFailed
        let made = try await makeLoadedVM(library: library)
        made.vm.generate()
        await waitForGenerationSettled(made.vm)

        made.vm.export()
        await waitForExportSettled(made.vm)

        XCTAssertEqual(made.vm.toastMessage, .exportFailed)
        XCTAssertTrue(library.saveCalls.isEmpty, "底层失败不记录成功调用")
        XCTAssertFalse(made.vm.isExporting)
    }

    func testPrepareShareFileWritesCacheAndResetsExporting() async throws {
        let made = try await makeLoadedVM()
        made.vm.generate()
        await waitForGenerationSettled(made.vm)

        let maybeURL = await made.vm.prepareShareFile()
        let url = try XCTUnwrap(maybeURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "分享缓存文件应落盘")
        XCTAssertFalse(made.vm.isExporting, "defer 保证导出状态复位")
    }

    func testPreparePDFFileWritesA4PDFCache() async throws {
        let made = try await makeLoadedVM()
        made.vm.generate()
        await waitForGenerationSettled(made.vm)

        let maybeURL = await made.vm.preparePDFFile()
        let url = try XCTUnwrap(maybeURL)
        XCTAssertEqual(url.pathExtension, "pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "A4 PDF 缓存文件应落盘")
        XCTAssertFalse(made.vm.isExporting)
    }

    // MARK: - Toast

    func testToastAutoDismissesAfterDelay() async {
        let vm = makeVM().vm
        vm.showToast(.missingSource)
        XCTAssertEqual(vm.toastMessage, .missingSource)
        // 2.5s 自动清除（轮询上限 5s，给 CI 慢环境留余量）。
        for _ in 0..<500 {
            if vm.toastMessage == nil { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(vm.toastMessage, "toast 应在 2.5s 后自动清除")
    }
}
