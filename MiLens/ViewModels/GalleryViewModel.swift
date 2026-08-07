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
    private let sandboxDir: String

    private let pageSize = 60
    private var scanTask: Task<Void, Never>?

    init(photoRepo: any PhotoRepositoryProtocol,
         petRepo: any PetRepositoryProtocol,
         photoLibrary: any PhotoLibraryAccess,
         vision: any VisionService,
         fileStorage: any FileStorage,
         sandboxDir: String) {
        self.photoRepo = photoRepo
        self.petRepo = petRepo
        self.photoLibrary = photoLibrary
        self.vision = vision
        self.fileStorage = fileStorage
        self.sandboxDir = sandboxDir
    }

    // MARK: - 快照（供 GalleryPageState 纯函数消费）

    var displaySnapshot: GalleryDisplaySnapshot {
        GalleryDisplaySnapshot(
            isLoading: isLoading,
            photoCount: totalPhotoCount,
            visibleCount: photos.count,
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
        if favoritesEnabled {
            photos = photos.filter(\.isFavorite)
        } else {
            loadInitial()
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
            photoRepo: photoRepo, petRepo: petRepo
        )

        scanTask = Task { [weak self] in
            guard let self else { return }
            let result = await service.scanAlbum(afterTimestamp: scanNewOnly ? Date() : nil) { progress in
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
                self.loadInitial()
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
