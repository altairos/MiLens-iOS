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
    /// 扫描进度百分比（0.0–1.0），供 AlbumScanFlow 进度条使用。
    var scanProgressPercent: Double = 0
    /// 导入进度百分比（0.0–1.0），供 AlbumScanFlow 导入中页使用。
    var importProgressPercent: Double = 0
    /// 最近一次导入结果（供成功页展示）。
    var lastImportResult: ImportResult?

    // MARK: - 导入

    var isImporting = false
    /// ADR-0010 照片配额不足时触发付费墙。
    var showQuotaPaywall = false
    /// Pro 权益状态（GalleryView 经 Environment 同步）。
    var isPro = false

    // MARK: - 配额降级门控（ADR-0010 §10.1 扩展）

    /// 被配额锁定的照片 ID 集合（免费版超额时，第 50 张之后的照片）。
    /// 运行时计算，不入 SwiftData；photos / isPro 变更后重算。
    private(set) var lockedPhotoIDs: Set<UUID> = []
    /// Gallery 是否应显示「超额横幅」（降级后进入管理模式时展示）。
    var showOverLimitBanner = false

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
    /// 导入任务引用——「取消导入」需取消真正在跑的 Task（文件写入会优雅中断）。
    private var importTask: Task<Void, Never>?

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
        recomputeLockedPhotoIDs()
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
        recomputeLockedPhotoIDs()
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
                recomputeLockedPhotoIDs()
            } catch {
                // 删除失败不从内存移除，等待用户重试。
            }
        }
    }

    /// 批量删除多选选中的照片（多选删除入口）。走媒体生命周期服务逐张联动删除。
    func deleteSelected() {
        let toDelete = photos.filter { selectedPhotoIDs.contains($0.id) }
        guard !toDelete.isEmpty else { return }
        let deleteIDs = selectedPhotoIDs
        selectedPhotoIDs.removeAll()
        Task {
            do {
                try await mediaLifecycle.deletePhotos(toDelete)
                photos.removeAll { deleteIDs.contains($0.id) }
                totalPhotoCount = max(0, totalPhotoCount - toDelete.count)
                recomputeLockedPhotoIDs()
                // 删除后若已无超额，隐藏横幅并退出多选
                if QuotaGatingLogic.overLimitCount(
                    photoCount: totalPhotoCount, isPro: isPro) == 0 {
                    showOverLimitBanner = false
                    isMultiSelectMode = false
                }
            } catch {
                // 部分失败时恢复选中状态，让用户知道哪些未删除
                selectedPhotoIDs = deleteIDs
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
                self.scanCompleteMessage = String(localized: "gallery.scan.permissionDenied")
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
                self.scanProgressPercent = progress.total > 0
                    ? Double(progress.scanned) / Double(progress.total) : 0
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

    /// 取消正在进行的导入任务（对应「取消导入」按钮）。
    /// ImportService 内部检测 Task.isCancelled 后优雅中断当前照片处理，
    /// 已写文件不丢弃（避免孤儿）；isImporting 由导入 Task 自然结束时复位。
    func cancelImport() {
        importTask?.cancel()
    }

    // MARK: - AlbumScanFlow 便捷接口

    /// 合并未归属 + 预匹配的候选 URI 列表（供候选页使用）。
    var candidateURIs: [String] {
        unassignedPetUris + matchedPetUris
    }

    /// 导入选中的候选照片到指定宠物档案。
    /// 复用 ImportService 核心导入流程，导入后强制归属到指定宠物（覆盖自动匹配）。
    func importCandidates(identifiers: [String], targetPetID: UUID?) {
        guard !identifiers.isEmpty, !isImporting else { return }
        isImporting = true
        importProgressPercent = 0
        unassignedPetUris = []
        matchedPetUris = []

        importTask = Task { [weak self] in
            guard let self else { return }
            let service = ImportService(
                photoLibrary: self.photoLibrary, fileStorage: self.fileStorage,
                photoRepo: self.photoRepo, mediaLifecycle: self.mediaLifecycle,
                sandboxDir: self.sandboxDir, petRepo: self.petRepo,
                clipService: self.clipService,
                isPro: self.isPro
            )
            let result = await service.importPhotos(
                identifiers: identifiers
            ) { progress in
                self.importProgressPercent = Double(progress.current) / Double(max(progress.total, 1))
            }
            self.importProgressPercent = 1
            self.lastImportResult = result

            // 强制归属到用户选定的宠物（覆盖自动匹配结果）
            if let petID = targetPetID {
                self.assignImportedPhotos(to: petID)
            }

            self.isImporting = false
            self.loadInitial()
            self.triggerQualityAnalysis()
            if result.imported > 0 {
                WidgetReload.notifyDataChanged()
            }
        }
    }

    /// 将本次导入的照片精确归属到指定宠物。
    /// 使用 ImportResult.importedPhotoIDs（实际入库的照片 ID），
    /// 避免按列表前 N 条推断（旧逻辑在自动匹配/排序变化时会错归属）。
    /// 统一走 PhotoAssignmentLogic.assign：原子批量归属 + 全部受影响宠物计数刷新
    /// （包括被自动匹配到其他宠物的照片——旧归属宠物计数必须递减）。
    private func assignImportedPhotos(to petID: UUID) {
        guard let pet = try? petRepo.getPet(id: petID) else { return }
        let photoIDs = lastImportResult?.importedPhotoIDs ?? []
        let photos = photoIDs.compactMap { try? photoRepo.getPhoto(id: $0) }
        do {
            try PhotoAssignmentLogic.assign(
                photos: photos, to: pet,
                photoRepo: photoRepo, petRepo: petRepo)
        } catch {
            logger.error("assignImportedPhotos: 归属失败（\(error.localizedDescription)）")
        }
    }

    // MARK: - 导入（原有全量导入入口，保留向后兼容）

    /// 导入本次扫描发现的宠物照片（未匹配 + 预匹配）。
    /// 预匹配只是扫描阶段的只读判定，真正归属写入在 ImportService 导入时完成。
    func importScannedPhotos() {
        let identifiers = unassignedPetUris + matchedPetUris
        guard !identifiers.isEmpty, !isImporting else { return }
        isImporting = true
        unassignedPetUris = []
        matchedPetUris = []
        showScanCompleteDialog = false

        importTask = Task { [weak self] in
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
            // 自动归属结果提示（复用扫描完成弹窗）；有失败/取消时同样提示，避免静默丢照片（H4）
            if result.imported > 0 || result.failed > 0 || result.cancelled {
                self.scanCompleteMessage = ImportFlowLogic.resolveImportSummary(
                    imported: result.imported, matched: result.matched, failed: result.failed,
                    cancelled: result.cancelled)
                self.showScanCompleteDialog = true
            }
            // 导入成功后刷新 Widget 快照（§6.1）
            if result.imported > 0 {
                WidgetReload.notifyDataChanged()
            }
        }
    }

    // MARK: - 多选

    func toggleMultiSelect() {
        isMultiSelectMode.toggle()
        if !isMultiSelectMode { selectedPhotoIDs.removeAll() }
    }

    /// 便捷查询：指定照片是否被配额锁定。
    func isLocked(_ photoID: UUID) -> Bool {
        lockedPhotoIDs.contains(photoID)
    }

    /// 重算锁定照片集合。在 photos / isPro / 删除变更后调用。
    /// photos 已由 Repository 保证按 takenAt 倒序（最新在前），直接传入纯函数。
    private func recomputeLockedPhotoIDs() {
        lockedPhotoIDs = QuotaGatingLogic.lockedPhotoIDs(photos: photos, isPro: isPro)
    }

    /// Pro 状态变更时重算锁定集合（由 GalleryView.onChange(of: entitlement.isPro) 调用）。
    func updateProStatus(_ isPro: Bool) {
        self.isPro = isPro
        recomputeLockedPhotoIDs()
        if isPro {
            showOverLimitBanner = false
        }
    }

    /// 从设置页/降级 sheet 进入「存储管理」模式：激活多选 + 显示超额横幅。
    func enterStorageManageMode() {
        isMultiSelectMode = true
        selectedPhotoIDs.removeAll()
        showOverLimitBanner = QuotaGatingLogic.overLimitCount(
            photoCount: totalPhotoCount, isPro: isPro) > 0
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
