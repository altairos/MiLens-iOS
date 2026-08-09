//  BeadViewModel —— 拼豆图纸页面状态机（@Observable）。
//  对应源端 BeadPatternPage：doGenerate 编排（图片解码 → 宠物 bbox → CLIP 语义
//  → 可选抠图 → 参数装配 → 生成）与 exportPattern / sharePattern 的 IO 部分。
//  纯决策逻辑下沉 MiLensKit（BeadFlowLogic / BeadGenerationLogic / BeadSemanticGuide），
//  CPU 密集生成/渲染在 detached Task 执行，避免阻塞主 actor（DESIGN.md §4）。

import SwiftUI
import MiLensKit
import os

@MainActor
@Observable
final class BeadViewModel {

    private let logger = Logger(subsystem: "com.milens.app", category: "Bead")

    // MARK: - 设置（对应源端 selectedStyleKey 等状态）

    var settings: BeadSettings = defaultBeadSettings()
    var showAdvancedSettings = false

    // MARK: - 生成状态（对应源端 isGenerating / isCuttingOut / pattern 组合）

    private(set) var phase: BeadGenerationPhase = .idle
    private(set) var pattern: BeadPattern?
    var viewMode: BeadViewMode = "color"
    var cellSize = 8
    var canvasScale: Double = 1.0
    var isExporting = false
    private(set) var toastMessage: BeadToastMessage?
    /// 结果画布预览（对应源端 BeadPatternResult 的 Canvas 绘制结果）。
    private(set) var previewImage: UIImage?

    // MARK: - 源图

    private(set) var photoURI = ""
    private(set) var thumbnailPath = ""

    // MARK: - 依赖

    private let photoRepo: any PhotoRepositoryProtocol
    private let vision: any VisionService
    private let clipService: (any ClipInference)?
    private let poseService: (any PoseInference)?
    private let exportService: BeadExportService
    private var isPro: Bool
    private let quotaStore: any BeadGenerationQuotaStore

    private var generationTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var semanticDetection: ClipDetectionResult?
    private var semanticSourceURI = ""

    /// 生成用源图解码上限（原图 4K RGBA 约 33MB，加 2048 上限控制峰值内存）。
    private let generationMaxDimension = 2048
    /// 导出原图缩略上限（对应源端 loadPhotoPixels 的 maxThumbDim = 560）。
    private let thumbMaxDimension = 560

    init(photoRepo: any PhotoRepositoryProtocol,
         vision: any VisionService,
         clipService: (any ClipInference)?,
         poseService: (any PoseInference)? = nil,
         exportService: BeadExportService = BeadExportService(),
         isPro: Bool = false,
         quotaStore: any BeadGenerationQuotaStore = UserDefaultsBeadGenerationQuotaStore()) {
        self.photoRepo = photoRepo
        self.vision = vision
        self.clipService = clipService
        self.poseService = poseService
        self.exportService = exportService
        self.isPro = isPro
        self.quotaStore = quotaStore
    }

    func updateEntitlement(isPro: Bool) {
        self.isPro = isPro
    }

    // 无 deinit 取消：generationTask/toastDismissTask 均以 [weak self] 捕获，
    // VM 释放后任务自然结束；长任务内部有 Task.checkCancellation 可取消。
    // （deinit 为 nonisolated，无法引用 @MainActor 隔离的 Task 属性。）

    // MARK: - 源图加载

    /// 按照片 ID 加载源图路径（对应源端 aboutToAppear 的路由参数赋值）。
    func load(photoID: UUID) async {
        let photo: Photo
        do {
            guard let found = try photoRepo.getPhoto(id: photoID) else {
                logger.error("load: 照片不存在（\(photoID)）")
                return
            }
            photo = found
        } catch {
            logger.error("load: 读取照片失败（\(photoID)，\(error.localizedDescription)）")
            return
        }
        photoURI = photo.uri
        thumbnailPath = photo.thumbnailPath
    }

    // MARK: - 生成编排（对应源端 doGenerate）

    func generate() {
        guard canStartBeadGeneration(phase) else { return }
        if !isPro && quotaStore.usedToday >= CommercialRules.freeBeadGenerationsPerDay {
            showToast(.generationLimitReached)
            return
        }
        guard !photoURI.isEmpty else {
            showToast(.missingSource)
            return
        }
        generationTask?.cancel()
        phase = .generating(cutoutInProgress: false)
        generationTask = Task { [weak self] in
            await self?.runGeneration()
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
    }

    private func runGeneration() async {
        do {
            // 1. 解码源图 RGBA（top-left origin，与源端 PixelMap 一致）
            let sourceData = try loadSourceData()
            guard let (pixels, w, h) = ClipInferenceService.decodeToRGBA(
                sourceData, maxDimension: generationMaxDimension) else {
                throw BeadRunError.decodeFailed
            }

            // 2. 宠物主体框（对应源端 VisionClassifier.prefilterPetCandidate）
            var subject: BeadSubjectContext?
            do {
                let boxes = try await vision.detectPets(in: sourceData)
                if let box = boxes.first, box.width > 0, box.height > 0 {
                    // iOS DetectionBox 为归一化坐标，先换算为像素（源端 CoreVision 框为像素坐标）
                    let rect = CropRect(x: box.x * Double(w), y: box.y * Double(h),
                                        width: box.width * Double(w), height: box.height * Double(h))
                    subject = computeSubjectFromBBox(box: rect, w: w, h: h)
                }
            } catch {
                // 降级：无主体框继续生成（对应源端 catch 后跳过）
            }

            // 3. CLIP 语义检测（可选，不可用/失败降级到预设默认）
            let detection = await resolveSemanticDetection()

            // 4. 可选抠图（对应源端 segmentSubject 分支）
            var workingPixels = pixels
            var workingW = w
            var workingH = h
            if settings.cutout {
                phase = .generating(cutoutInProgress: true)
                do {
                    if let seg = try await vision.segmentSubject(in: sourceData),
                       seg.bboxWidth > 0, seg.bboxHeight > 0 {
                        let bbox = CropRect(x: Double(seg.bboxX), y: Double(seg.bboxY),
                                            width: Double(seg.bboxWidth), height: Double(seg.bboxHeight))
                        let cropParams = computeSquareCropParams(bbox: bbox, imgW: w, imgH: h)
                        workingPixels = cropPixelsToSquare(
                            pixels, srcW: w,
                            cropX: cropParams.cropX, cropY: cropParams.cropY,
                            cropSize: cropParams.cropSize)
                        // iOS 蒙版为 bbox 局部坐标，平铺到全图后再裁切（源端蒙版为全图坐标）
                        let fullMask = fullMaskFromSegmentation(seg, imgW: w, imgH: h)
                        let croppedMask = cropMaskToSquare(
                            fullMask, srcW: w,
                            cropX: cropParams.cropX, cropY: cropParams.cropY,
                            cropSize: cropParams.cropSize)
                        var adjusted = adjustSubjectForCrop(
                            originalBbox: bbox,
                            cropX: cropParams.cropX, cropY: cropParams.cropY,
                            cropSize: cropParams.cropSize)
                        adjusted.mask = croppedMask
                        subject = adjusted
                        // RTMPose 五官关键点：随抠图分支检测（对应源端 cutoutResult.pose →
                        // adjustPoseForCrop）；模型缺失/失败时静默跳过，不影响生成。
                        if let poseService {
                            do {
                                if let pose = try await poseService.detectPose(
                                    pixels: pixels, width: w, height: h, bbox: bbox) {
                                    subject?.pose = adjustPoseForCrop(
                                        pose, sourceWidth: w, sourceHeight: h,
                                        cropX: cropParams.cropX, cropY: cropParams.cropY,
                                        cropSize: cropParams.cropSize)
                                }
                            } catch {
                                logger.warning("pose 检测失败，跳过（\(error.localizedDescription)）")
                            }
                        }
                        workingW = cropParams.cropSize
                        workingH = cropParams.cropSize
                    }
                } catch {
                    // 抠图失败降级为原图（对应源端 catch 后继续）
                }
                phase = .generating(cutoutInProgress: false)
            }

            // 5. 参数装配 + 语义色板引导（对应源端 resolved + applySemanticPaletteSteering）
            let resolved = resolveBeadGeneration(settings: settings)
            var options = resolved.options
            if let detection {
                let mutable = BeadGenerateOptionsMutable(petFriendlyPenalty: options.petFriendlyPenalty)
                let shared = DetectionResult(isPet: detection.isPet, species: detection.species,
                                             topConfidence: Double(detection.topConfidence))
                _ = applySemanticPaletteSteering(mutable, detection: shared)
                options.petFriendlyPenalty = mutable.petFriendlyPenalty
            }

            // 6. CPU 密集生成在 detached Task 执行（自动模式内部逐候选检查取消）
            try Task.checkCancellation()
            let isAuto = resolved.isAuto
            let result = try await Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                if isAuto {
                    return try await generateBeadPatternAutoAsync(
                        srcPixels: workingPixels, srcW: workingW, srcH: workingH,
                        baseOptions: options, subject: subject)
                }
                return try await generateBeadPatternAsync(
                    srcPixels: workingPixels, srcW: workingW, srcH: workingH,
                    options: options, subject: subject)
            }.value
            try Task.checkCancellation()

            pattern = result
            if !isPro {
                quotaStore.recordSuccessfulGeneration()
            }
            cellSize = computeCellSize(patternWidth: result.width)
            canvasScale = 1.0
            phase = .success
            refreshPreview()
        } catch is CancellationError {
            if pattern == nil { phase = .idle }
        } catch {
            if !Task.isCancelled {
                phase = .failure
                showToast(.generationFailed)
            }
        }
    }

    // MARK: - 结果展示

    /// 切换视图模式并重绘预览（对应源端 onViewModeChange）。
    func setViewMode(_ mode: BeadViewMode) {
        let normalized = normalizeBeadViewMode(mode)
        guard normalized != viewMode else { return }
        viewMode = normalized
        refreshPreview()
    }

    /// 画布缩放步进（对应源端结果页 − / + 按钮）。
    func stepCanvasScale(_ delta: Double) {
        canvasScale = stepBeadCanvasScale(canvasScale, delta: delta)
    }

    /// 渲染结果画布预览（对应源端 BeadPatternResult.redrawCanvas：
    /// 按 cellSize × canvasScale 重绘，画布尺寸随缩放变化，上限 2560 控制内存）。
    func refreshPreview() {
        guard let pattern else {
            previewImage = nil
            return
        }
        let scaledCell = Swift.max(2, Int((Double(cellSize) * canvasScale).rounded()))
        let totalW = pattern.width * scaledCell
        let totalH = pattern.height * scaledCell
        let canvasSize = Swift.min(2560, Swift.max(720, Swift.max(totalW, totalH)))
        var pixels = [UInt8](repeating: 255, count: canvasSize * canvasSize * 4)
        let offsetX = Swift.max(0, (canvasSize - totalW) / 2)
        let offsetY = Swift.max(0, (canvasSize - totalH) / 2)
        drawBeadPattern(pixels: &pixels, canvasW: canvasSize, canvasH: canvasSize,
                        pattern: pattern, cellSize: scaledCell, viewMode: viewMode,
                        offsetX: offsetX, offsetY: offsetY,
                        drawOpts: beadDrawOptions(styleKey: settings.styleKey, pattern: pattern))
        previewImage = BeadExportService.makeImage(rgba: pixels, width: canvasSize, height: canvasSize)
    }

    // MARK: - 风格预设

    /// 应用风格预设（对应源端 applyStylePreset）。
    /// 注意：方法名避开 MiLensKit 顶层函数 applyStylePreset——实例方法会遮蔽
    /// 模块顶层函数导致递归；且 `MiLensKit.` 限定符被同名 `enum MiLensKit` 抢占。
    func applyPreset(_ key: String) {
        settings = applyStylePreset(key)
    }

    // MARK: - 导出 / 分享（对应源端 exportPattern / sharePattern）

    /// 保存高清 A4 图纸到系统相册。
    func export() {
        guard canStartBeadExport(isExporting: isExporting, hasPattern: pattern != nil) else { return }
        isExporting = true
        Task { [weak self] in
            guard let self, let pattern = self.pattern else {
                self?.isExporting = false
                return
            }
            do {
                let photoData = await self.loadPhotoPixels()
                let opts = beadExportOptions(styleKey: self.settings.styleKey, pattern: pattern)
                let renderer = self.exportService
                let png: Data? = await Task.detached(priority: .userInitiated) {
                    renderer.renderA4PNG(pattern: pattern,
                                         photoPixels: photoData?.pixels,
                                         photoW: photoData?.w ?? 0,
                                         photoH: photoData?.h ?? 0,
                                         exportOpts: opts)
                }.value
                guard let png else { throw BeadRunError.exportRenderFailed }
                try await self.exportService.saveToPhotoLibrary(pngData: png)
                self.showToast(.exportSuccess)
            } catch {
                self.showToast(.exportFailed)
            }
            self.isExporting = false
        }
    }

    /// 渲染分享缓存文件（对应源端 sharePattern 写 cacheDir/bead_pattern_share.png）。
    /// 返回 nil 表示失败（调用方静默处理）。
    func prepareShareFile() async -> URL? {
        guard canStartBeadExport(isExporting: isExporting, hasPattern: pattern != nil) else { return nil }
        isExporting = true
        defer { isExporting = false }
        guard let pattern else { return nil }
        let photoData = await loadPhotoPixels()
        let opts = beadExportOptions(styleKey: settings.styleKey, pattern: pattern)
        let renderer = exportService
        let png: Data? = await Task.detached(priority: .userInitiated) {
            renderer.renderA4PNG(pattern: pattern,
                                 photoPixels: photoData?.pixels,
                                 photoW: photoData?.w ?? 0,
                                 photoH: photoData?.h ?? 0,
                                 exportOpts: opts)
        }.value
        guard let png else { return nil }
        do {
            return try exportService.writeShareCache(data: png)
        } catch {
            logger.error("prepareShareFile: 写入分享缓存失败（\(error.localizedDescription)）")
            return nil
        }
    }

    /// 渲染 A4 PDF 分享文件（与 prepareShareFile 同一渲染路径，封装为单页 A4 PDF，
    /// 经系统分享面板可打印或存储到文件）。返回 nil 表示失败（调用方静默处理）。
    func preparePDFFile() async -> URL? {
        guard canStartBeadExport(isExporting: isExporting, hasPattern: pattern != nil) else { return nil }
        isExporting = true
        defer { isExporting = false }
        guard let pattern else { return nil }
        let photoData = await loadPhotoPixels()
        let opts = beadExportOptions(styleKey: settings.styleKey, pattern: pattern)
        let renderer = exportService
        let pdf: Data? = await Task.detached(priority: .userInitiated) {
            renderer.renderA4PDF(pattern: pattern,
                                 photoPixels: photoData?.pixels,
                                 photoW: photoData?.w ?? 0,
                                 photoH: photoData?.h ?? 0,
                                 exportOpts: opts)
        }.value
        guard let pdf else { return nil }
        do {
            return try exportService.writeShareCache(data: pdf, filename: "bead_pattern_a4.pdf")
        } catch {
            logger.error("preparePDFFile: 写入 PDF 缓存失败（\(error.localizedDescription)）")
            return nil
        }
    }

    // MARK: - Toast

    /// 展示提示并在 2.5s 后自动清除（对应源端 showToast + scheduleTimer）。
    func showToast(_ message: BeadToastMessage) {
        toastMessage = message
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2.5))
            } catch {
                return  // 任务被取消（新的 toast 或 VM 释放）
            }
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    // MARK: - 私有辅助

    private enum BeadRunError: Error {
        case decodeFailed
        case exportRenderFailed
    }

    private func loadSourceData() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: photoURI))
    }

    /// 加载导出用原图缩略像素（对应源端 loadPhotoPixels，最大边 560）。
    private func loadPhotoPixels() async -> (pixels: [UInt8], w: Int, h: Int)? {
        guard !photoURI.isEmpty else { return nil }
        do {
            let data = try loadSourceData()
            guard let rgba = ClipInferenceService.decodeToRGBA(data, maxDimension: thumbMaxDimension) else {
                return nil
            }
            return (pixels: rgba.pixels, w: rgba.width, h: rgba.height)
        } catch {
            return nil
        }
    }

    /// CLIP 语义检测（同一源图只跑一次，对应源端 resolveSemanticDetection）。
    private func resolveSemanticDetection() async -> ClipDetectionResult? {
        guard semanticSourceURI != photoURI else { return semanticDetection }
        semanticSourceURI = photoURI
        semanticDetection = nil
        guard let clipService else { return nil }
        do {
            let data = try loadSourceData()
            semanticDetection = try await clipService.detect(imageData: data)
        } catch {
            semanticDetection = nil
        }
        return semanticDetection
    }

    /// iOS SegmentationResult.mask 是 bbox 局部蒙版；平铺到全图坐标（源端蒙版为全图坐标）再裁切。
    private func fullMaskFromSegmentation(_ seg: SegmentationResult, imgW: Int, imgH: Int) -> [UInt8] {
        var mask = [UInt8](repeating: 0, count: imgW * imgH)
        let bytes = [UInt8](seg.mask)
        for y in 0..<seg.bboxHeight {
            let dstY = Int(seg.bboxY) + y
            guard dstY >= 0, dstY < imgH else { continue }
            for x in 0..<seg.bboxWidth {
                let dstX = Int(seg.bboxX) + x
                guard dstX >= 0, dstX < imgW else { continue }
                mask[dstY * imgW + dstX] = bytes[y * seg.bboxWidth + x]
            }
        }
        return mask
    }
}
