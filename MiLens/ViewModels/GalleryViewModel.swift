//  GalleryViewModel —— 相册页面状态机（@Observable）。
//  持有分页照片列表、筛选状态、扫描/导入编排。
//  决策通过 GalleryPageState 纯函数 + ScanFlowLogic 纯函数完成（DESIGN.md §4）。
//  对应源端 GalleryStore + GalleryActions。

import SwiftUI
import SwiftData
import os

@MainActor
@Observable
final class GalleryViewModel {

    private let logger = Logger(subsystem: "com.milens.app", category: "Gallery")

    // MARK: - 显示层状态

    var photos: [Photo] = []
    var pets: [Pet] = []
    var isLoading = false
    var hasMorePhotos = true
    private(set) var totalPhotoCount = 0

    // MARK: - 筛选

    var filterEnabled = false
    var favoritesEnabled = false
    var selectedFilter = GalleryFilter.empty

    // MARK: - 扫描

    var isScanning = false
    var scanProgressText = ""
    var showScanCompleteDialog = false
    var scanCompleteMessage = ""
    /// 本次扫描是否失败（未完整遍历）。决定完成弹窗的标题/图标与游标保存。
    var scanFailed = false
    /// 照片权限被拒（denied/restricted/未授权）：完成弹窗显示「去设置」引导。
    var permissionDenied = false
    var unassignedPetUris: [String] = []
    /// 预匹配到已注册宠物的照片 identifier（只读预判，尚未入库；
    /// 与 unassignedPetUris 一并提供导入入口，导入时真正归属写入）。
    var matchedPetUris: [String] = []

    // MARK: - 导入

    var isImporting = false
    /// ADR-0010 照片配额不足时触发付费墙。
    var showQuotaPaywall = false
    /// Pro 权益状态（GalleryView 经 Environment 同步）。
    var isPro = false

    // MARK: - 多选

    var isMultiSelectMode = false
    var selectedPhotoIDs: Set<UUID> = []

    // MARK: - 依赖

    private let photoRepo: any PhotoRepositoryProtocol
    private let petRepo: any PetRepositoryProtocol
    private let photoLibrary: any PhotoLibraryAccess
    private let vision: any VisionService
    private let fileStorage: any FileStorage
    private let imageAnalyzer: any ImageAnalyzer
    private let sandboxDir: String
    /// 媒体生命周期（导入事务段 + 删除联动：写文件/入库一致性、DB 删除连带沙盒文件清理）
    private let mediaLifecycle: MediaLifecycleService
    /// Phase 2 CLIP 精筛（nil = 模型缺失，仅 Vision 预筛）
    private let clipService: (any ClipInference)?
    /// 上次成功扫描游标（「仅扫描新增」过滤基准）
    private let cursorStore: any ScanCursorStore

    private let pageSize = 60
    private var scanTask: Task<Void, Never>?

    init(photoRepo: any PhotoRepositoryProtocol,
         petRepo: any PetRepositoryProtocol,
         photoLibrary: any PhotoLibraryAccess,
         vision: any VisionService,
         fileStorage: any FileStorage,
         sandboxDir: String,
         imageAnalyzer: any ImageAnalyzer = CoreImageAnalyzer(),
         clipService: (any ClipInference)? = nil,
         cursorStore: any ScanCursorStore = UserDefaultsScanCursorStore(),
         mediaLifecycle: MediaLifecycleService? = nil) {
        self.photoRepo = photoRepo
        self.petRepo = petRepo
        self.photoLibrary = photoLibrary
        self.vision = vision
        self.fileStorage = fileStorage
        self.imageAnalyzer = imageAnalyzer
        self.sandboxDir = sandboxDir
        self.clipService = clipService
        self.cursorStore = cursorStore
        self.mediaLifecycle = mediaLifecycle ?? MediaLifecycleService(
            photoRepo: photoRepo, petRepo: petRepo,
            fileStorage: fileStorage, sandboxDir: sandboxDir)
    }

    /// 扫描/导入后后台质量评分 + 重复分组（对应源端 ScanController fire-and-forget 链）。
    private func triggerQualityAnalysis() {
        let scorer = QualityScorer(
            photoRepo: photoRepo, imageAnalyzer: imageAnalyzer, fileStorage: fileStorage)
        Task { await scorer.runPostScanAnalysis() }
    }

    // MARK: - 快照（供 GalleryPageState 纯函数消费）

    var displaySnapshot: GalleryDisplaySnapshot {
        GalleryDisplaySnapshot(
            isLoading: isLoading,
            photoCount: totalPhotoCount,
            visibleCount: filteredPhotos.count,
            hasMorePhotos: hasMorePhotos,
            galleryChromeHidden: false
        )
    }

    var filterSnapshot: GalleryFilterSnapshot {
        GalleryFilterSnapshot(
            filterEnabled: filterEnabled,
            favoritesEnabled: favoritesEnabled,
            selectedFilter: selectedFilter
        )
    }

    /// 当前筛选条件下的显示照片。原始分页数组保持不变，避免切换筛选后分页偏移失效。
    var filteredPhotos: [Photo] {
        var result = photos
        if let petID = selectedFilter.petID {
            result = result.filter { $0.pet?.id == petID }
        }
        if favoritesEnabled {
            result = result.filter(\.isFavorite)
        }
        return result
    }

    var scanSnapshot: GalleryScanSnapshot {
        GalleryScanSnapshot(
            isScanning: isScanning,
            scanPaused: false,
            showScanCompleteDialog: showScanCompleteDialog,
            scanTotal: 0,
            scanFound: 0
        )
    }

    var taskSnapshot: GalleryTaskSnapshot {
        GalleryTaskSnapshot(isImporting: isImporting, isExporting: false)
    }

    // MARK: - 分页加载

    func loadInitial() {
        isLoading = true
        currentLoadedCount = 0
        do {
            totalPhotoCount = try photoRepo.countAllPhotos()
            let page = try photoRepo.getPhotosPage(offset: 0, limit: pageSize)
            photos = page
            hasMorePhotos = page.count == pageSize
            currentLoadedCount = page.count
        } catch {
            photos = []
            hasMorePhotos = false
        }
        // 宠物列表失败不影响照片列表（独立降级，记录错误便于诊断）
        do {
            pets = try petRepo.getAllPets()
        } catch {
            logger.error("loadInitial: 读取宠物列表失败（\(error.localizedDescription)）")
            pets = []
        }
        isLoading = false
    }

    func loadMore() {
        guard GalleryPageState.canLoadMore(displaySnapshot) else { return }
        do {
            let page = try photoRepo.getPhotosPage(offset: currentLoadedCount, limit: pageSize)
            photos.append(contentsOf: page)
            hasMorePhotos = page.count == pageSize
            currentLoadedCount += page.count
        } catch {
            hasMorePhotos = false
        }
    }

    private var currentLoadedCount = 0

    // MARK: - 筛选

    func toggleFavorites() {
        favoritesEnabled.toggle()
    }

    func selectPet(_ petID: UUID?) {
        selectedFilter.petID = petID
        filterEnabled = petID != nil
    }

    func setFavorite(_ photo: Photo) {
        let nextValue = !photo.isFavorite
        do {
            try photoRepo.setFavorite(photo, favorite: nextValue)
            photo.isFavorite = nextValue
        } catch {
            // 仓储失败时保留当前状态，避免 UI 假装完成。
        }
    }

    /// 删除照片：走媒体生命周期服务（DB 删除 + 沙盒文件联动删除 + 宠物照片计数刷新），
    /// 不再直接调 photoRepo.deletePhoto（否则沙盒文件残留、归属宠物计数不刷新）。
    func deletePhoto(id: UUID) {
        guard let photo = photos.first(where: { $0.id == id }) else { return }
        Task {
            do {
                try await mediaLifecycle.deletePhoto(photo)
                photos.removeAll { $0.id == id }
                totalPhotoCount = max(0, totalPhotoCount - 1)
            } catch {
                // 删除失败不从内存移除，等待用户重试。
            }
        }
    }

    // MARK: - 扫描

    func startScan(scanNewOnly: Bool = false) {
        guard !isScanning else { return }
        isScanning = true
        showScanCompleteDialog = false
        scanFailed = false
        permissionDenied = false
        unassignedPetUris = []
        matchedPetUris = []

        let service = ScanService(
            photoLibrary: photoLibrary, vision: vision,
            photoRepo: photoRepo, petRepo: petRepo,
            clipService: clipService
        )
        // 增量扫描基准：上次成功扫描开始时刻（无历史游标 = 全量扫描）
        let afterTimestamp = scanNewOnly ? cursorStore.lastSuccessfulScan : nil
        // 游标 = 本次扫描开始时刻；扫描成功（未取消）后持久化，作为下次增量基准
        let scanStart = Date()

        scanTask = Task { [weak self] in
            guard let self else { return }
            // 权限前置（对应源端 PhotoScanner.checkAndRequestPermission）：
            // notDetermined → 系统弹窗请求；denied/restricted → 弹窗引导去设置；
            // authorized/limited → 继续扫描（limited = 仅限选中的照片，可扫描可见部分）。
            guard await ensurePhotoPermission() else {
                self.isScanning = false
                self.scanProgressText = ""
                self.permissionDenied = true
                self.scanFailed = true
                self.scanCompleteMessage = "需要照片访问权限才能扫描相册。\n可在「设置 → 隐私 → 照片」中开启。"
                self.showScanCompleteDialog = true
                return
            }
            let result = await service.scanAlbum(afterTimestamp: afterTimestamp) { progress in
                self.scanProgressText = GalleryPageState.resolveScanProgressLabel(
                    GalleryScanSnapshot(
                        isScanning: true, scanPaused: false,
                        showScanCompleteDialog: false,
                        scanTotal: progress.total, scanFound: progress.petPhotosFound
                    )
                )
            }
            self.isScanning = false
            self.scanProgressText = ""
            self.unassignedPetUris = result.unassignedPetUris
            self.matchedPetUris = result.matchedUris
            self.scanFailed = result.error != nil
            if let error = result.error {
                // 失败：弹窗展示错误信息（标题/图标走 scanFailed 分支，可重试）
                self.scanCompleteMessage = error
            } else {
                self.scanCompleteMessage = ScanFlowLogic.resolveCompleteMessage(
                    matchedCount: result.matchedCount,
                    unassignedCount: result.unassignedPetUris.count,
                    processedCount: result.processedCount,
                    isNewOnly: scanNewOnly
                )
            }
            // 只有真正完整完成（未取消且无错误）才保存增量游标——
            // 失败/取消时保存会导致下次增量扫描跳过本次未扫到的照片。
            self.showScanCompleteDialog = !result.canceled
            if result.completedSuccessfully {
                self.cursorStore.saveLastSuccessfulScan(scanStart)
                self.loadInitial()
                self.triggerQualityAnalysis()
            }
        }
    }

    /// 扫描前权限前置检查（对应源端 PhotoScanner.checkAndRequestPermission）。
    /// notDetermined 时触发系统授权弹窗；denied/restricted 直接返回 false（由调用方引导去设置）。
    private func ensurePhotoPermission() async -> Bool {
        switch await photoLibrary.authorizationStatus() {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let status = await photoLibrary.requestAuthorization()
            return status == .authorized || status == .limited
        case .denied, .restricted:
            return false
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanProgressText = ""
    }

    // MARK: - 导入

    /// 导入本次扫描发现的宠物照片（未匹配 + 预匹配）。
    /// 预匹配只是扫描阶段的只读判定，真正归属写入在 ImportService 导入时完成。
    func importScannedPhotos() {
        let identifiers = unassignedPetUris + matchedPetUris
        guard !identifiers.isEmpty, !isImporting else { return }
        isImporting = true
        unassignedPetUris = []
        matchedPetUris = []
        showScanCompleteDialog = false

        Task { [weak self] in
            guard let self else { return }
            let service = ImportService(
                photoLibrary: self.photoLibrary, fileStorage: self.fileStorage,
                photoRepo: self.photoRepo, mediaLifecycle: self.mediaLifecycle,
                sandboxDir: self.sandboxDir, petRepo: self.petRepo,
                clipService: self.clipService,
                isPro: self.isPro
            )
            let result = await service.importPhotos(identifiers: identifiers)
            self.isImporting = false
            self.loadInitial()
            self.triggerQualityAnalysis()
            // ADR-0010 配额拦截：有照片因免费上限未导入 → 弹付费墙。
            if result.hitQuota {
                self.showQuotaPaywall = true
            }
            // 自动归属结果提示（复用扫描完成弹窗）；有失败时同样提示，避免静默丢照片（H4）
            if result.imported > 0 || result.failed > 0 {
                self.scanCompleteMessage = ImportFlowLogic.resolveImportSummary(
                    imported: result.imported, matched: result.matched, failed: result.failed)
                self.showScanCompleteDialog = true
            }
        }
    }

    // MARK: - 多选

    func toggleMultiSelect() {
        isMultiSelectMode.toggle()
        if !isMultiSelectMode { selectedPhotoIDs.removeAll() }
    }

    func toggleSelection(_ id: UUID) {
        if selectedPhotoIDs.contains(id) {
            selectedPhotoIDs.remove(id)
        } else {
            selectedPhotoIDs.insert(id)
        }
    }

    /// 手动归属/移出后重新加载（归属变更影响筛选结果与宠物计数缓存）。
    func refreshAfterAssignment() {
        loadInitial()
    }
}
