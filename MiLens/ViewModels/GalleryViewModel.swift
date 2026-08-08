//  GalleryViewModel —— 相册页面状态机（@Observable）。
//  持有分页照片列表、筛选状态、扫描/导入编排。
//  决策通过 GalleryPageState 纯函数 + ScanFlowLogic 纯函数完成（DESIGN.md §4）。
//  对应源端 GalleryStore + GalleryActions。

import SwiftUI
import SwiftData

@MainActor
@Observable
final class GalleryViewModel {

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
    var unassignedPetUris: [String] = []

    // MARK: - 导入

    var isImporting = false

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
         cursorStore: any ScanCursorStore = UserDefaultsScanCursorStore()) {
        self.photoRepo = photoRepo
        self.petRepo = petRepo
        self.photoLibrary = photoLibrary
        self.vision = vision
        self.fileStorage = fileStorage
        self.imageAnalyzer = imageAnalyzer
        self.sandboxDir = sandboxDir
        self.clipService = clipService
        self.cursorStore = cursorStore
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
            totalPhotoCount = try photoRepo.getAllPhotoURIs().count
            pets = (try? petRepo.getAllPets()) ?? []
            let page = try photoRepo.getPhotosPage(offset: 0, limit: pageSize)
            photos = page
            hasMorePhotos = page.count == pageSize
            currentLoadedCount = page.count
        } catch {
            photos = []
            hasMorePhotos = false
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

    func deletePhoto(id: UUID) {
        guard let photo = photos.first(where: { $0.id == id }) else { return }
        do {
            try photoRepo.deletePhoto(photo)
            photos.removeAll { $0.id == id }
            totalPhotoCount = max(0, totalPhotoCount - 1)
        } catch {
            // 删除失败不从内存移除，等待用户重试。
        }
    }

    // MARK: - 扫描

    func startScan(scanNewOnly: Bool = false) {
        guard !isScanning else { return }
        isScanning = true
        showScanCompleteDialog = false
        unassignedPetUris = []

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
            self.scanCompleteMessage = ScanFlowLogic.resolveCompleteMessage(
                matchedCount: result.matchedCount,
                unassignedCount: result.unassignedPetUris.count,
                processedCount: result.processedCount,
                isNewOnly: scanNewOnly
            )
            self.showScanCompleteDialog = !result.canceled
            if !result.canceled {
                self.cursorStore.saveLastSuccessfulScan(scanStart)
                self.loadInitial()
                self.triggerQualityAnalysis()
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanProgressText = ""
    }

    // MARK: - 导入

    func importUnassigned() {
        guard !unassignedPetUris.isEmpty, !isImporting else { return }
        isImporting = true
        let identifiers = unassignedPetUris
        unassignedPetUris = []
        showScanCompleteDialog = false

        Task { [weak self] in
            guard let self else { return }
            let service = ImportService(
                photoLibrary: self.photoLibrary, fileStorage: self.fileStorage,
                photoRepo: self.photoRepo, sandboxDir: self.sandboxDir
            )
            _ = await service.importPhotos(identifiers: identifiers)
            self.isImporting = false
            self.loadInitial()
            self.triggerQualityAnalysis()
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
}
