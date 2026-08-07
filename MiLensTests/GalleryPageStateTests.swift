import XCTest
@testable import MiLens

/// GalleryPageState 测试（对应源端 GalleryPageState.test.ets）。
/// 覆盖 resolveContentKind / hasVisiblePhotos / canLoadMore / 筛选决策 / 任务互斥 / 进度文案。
final class GalleryPageStateTests: XCTestCase {

    // MARK: - 快照构造辅助

    private func display(
        isLoading: Bool = true, photoCount: Int = 0, visibleCount: Int = 0,
        hasMorePhotos: Bool = false, galleryChromeHidden: Bool = false
    ) -> GalleryDisplaySnapshot {
        var snap = GalleryDisplaySnapshot.initial
        snap.isLoading = isLoading
        snap.photoCount = photoCount
        snap.visibleCount = visibleCount
        snap.hasMorePhotos = hasMorePhotos
        snap.galleryChromeHidden = galleryChromeHidden
        return snap
    }

    private func filterState(
        filterEnabled: Bool = false, favoritesEnabled: Bool = false,
        selectedFilter: GalleryFilter = .empty
    ) -> GalleryFilterSnapshot {
        var snap = GalleryFilterSnapshot.initial()
        snap.filterEnabled = filterEnabled
        snap.favoritesEnabled = favoritesEnabled
        snap.selectedFilter = selectedFilter
        return snap
    }

    private func scanState(
        isScanning: Bool = false, scanPaused: Bool = false,
        showScanCompleteDialog: Bool = false, scanTotal: Int = 0, scanFound: Int = 0
    ) -> GalleryScanSnapshot {
        var snap = GalleryScanSnapshot.initial
        snap.isScanning = isScanning
        snap.scanPaused = scanPaused
        snap.showScanCompleteDialog = showScanCompleteDialog
        snap.scanTotal = scanTotal
        snap.scanFound = scanFound
        return snap
    }

    private func taskState(isImporting: Bool = false, isExporting: Bool = false) -> GalleryTaskSnapshot {
        var snap = GalleryTaskSnapshot.initial
        snap.isImporting = isImporting
        snap.isExporting = isExporting
        return snap
    }

    // MARK: - resolveContentKind

    func testResolveContentKindReturnsLoadingWhenIsLoading() {
        let kind = GalleryPageState.resolveContentKind(display: display(isLoading: true, visibleCount: 0), filter: filterState())
        XCTAssertEqual(kind, .loading)
    }

    func testResolveContentKindReturnsEmptyDefaultWhenNoFilterAndNoPhotos() {
        let kind = GalleryPageState.resolveContentKind(display: display(isLoading: false, visibleCount: 0), filter: filterState())
        XCTAssertEqual(kind, .emptyDefault)
    }

    func testResolveContentKindReturnsEmptyFilteredWhenFilterActiveAndNoPhotos() {
        let kind = GalleryPageState.resolveContentKind(
            display: display(isLoading: false, visibleCount: 0),
            filter: filterState(filterEnabled: true)
        )
        XCTAssertEqual(kind, .emptyFiltered)
    }

    func testResolveContentKindReturnsEmptyFilteredWhenFavoritesEnabledAndNoPhotos() {
        let kind = GalleryPageState.resolveContentKind(
            display: display(isLoading: false, visibleCount: 0),
            filter: filterState(favoritesEnabled: true)
        )
        XCTAssertEqual(kind, .emptyFiltered)
    }

    func testResolveContentKindReturnsContentWhenVisibleCountGreaterThanZero() {
        let kind = GalleryPageState.resolveContentKind(
            display: display(isLoading: false, visibleCount: 10),
            filter: filterState()
        )
        XCTAssertEqual(kind, .content)
    }

    func testResolveContentKindPrefersLoadingOverContentWhenBothFlagsSet() {
        let kind = GalleryPageState.resolveContentKind(
            display: display(isLoading: true, visibleCount: 10),
            filter: filterState()
        )
        XCTAssertEqual(kind, .loading)
    }

    // MARK: - hasVisiblePhotos

    func testHasVisiblePhotosIsFalseForZeroCount() {
        XCTAssertFalse(GalleryPageState.hasVisiblePhotos(display(visibleCount: 0)))
    }

    func testHasVisiblePhotosIsTrueForOnePhoto() {
        XCTAssertTrue(GalleryPageState.hasVisiblePhotos(display(visibleCount: 1)))
    }

    func testHasVisiblePhotosIsTrueForManyPhotos() {
        XCTAssertTrue(GalleryPageState.hasVisiblePhotos(display(visibleCount: 500)))
    }

    // MARK: - canLoadMore

    func testCanLoadMoreIsFalseWhenHasMorePhotosIsFalse() {
        XCTAssertFalse(GalleryPageState.canLoadMore(display(hasMorePhotos: false, isLoading: false)))
    }

    func testCanLoadMoreIsTrueWhenHasMorePhotosAndNotLoading() {
        XCTAssertTrue(GalleryPageState.canLoadMore(display(hasMorePhotos: true, isLoading: false)))
    }

    func testCanLoadMoreIsFalseWhenIsLoadingEvenIfHasMore() {
        XCTAssertFalse(GalleryPageState.canLoadMore(display(hasMorePhotos: true, isLoading: true)))
    }

    func testCanLoadMoreIgnoresGalleryChromeHidden() {
        XCTAssertTrue(GalleryPageState.canLoadMore(display(hasMorePhotos: true, isLoading: false, galleryChromeHidden: true)))
    }

    func testCanLoadMoreIgnoresVisibleCountBoundary() {
        XCTAssertTrue(GalleryPageState.canLoadMore(display(hasMorePhotos: true, isLoading: false, visibleCount: 500)))
    }

    // MARK: - isFilterEmpty / isFilterActive / isNonDefaultFilter

    func testIsFilterEmptyIsTrueForDefaultFilter() {
        XCTAssertTrue(GalleryPageState.isFilterEmpty(.empty))
    }

    func testIsFilterEmptyIsFalseWhenPetIDSet() {
        XCTAssertFalse(GalleryPageState.isFilterEmpty(GalleryFilter(petID: UUID())))
    }

    func testIsFilterEmptyIsFalseWhenDateRangeSet() {
        XCTAssertFalse(GalleryPageState.isFilterEmpty(GalleryFilter(dateRange: "近7天")))
    }

    func testIsFilterEmptyIsFalseWhenLocationSet() {
        XCTAssertFalse(GalleryPageState.isFilterEmpty(GalleryFilter(location: "北京")))
    }

    func testIsFilterActiveIsFalseWhenNeitherFlagSet() {
        XCTAssertFalse(GalleryPageState.isFilterActive(filterState(filterEnabled: false, favoritesEnabled: false)))
    }

    func testIsFilterActiveIsTrueWhenFilterEnabledOnly() {
        XCTAssertTrue(GalleryPageState.isFilterActive(filterState(filterEnabled: true, favoritesEnabled: false)))
    }

    func testIsFilterActiveIsTrueWhenFavoritesEnabledOnly() {
        XCTAssertTrue(GalleryPageState.isFilterActive(filterState(filterEnabled: false, favoritesEnabled: true)))
    }

    func testIsNonDefaultFilterIsFalseForDefault() {
        XCTAssertFalse(GalleryPageState.isNonDefaultFilter(filterState()))
    }

    func testIsNonDefaultFilterIsTrueWhenFavoritesEnabled() {
        XCTAssertTrue(GalleryPageState.isNonDefaultFilter(filterState(favoritesEnabled: true)))
    }

    func testIsNonDefaultFilterIsTrueWhenFilterEnabledWithNonEmptyConditions() {
        let fs = filterState(filterEnabled: true, selectedFilter: GalleryFilter(petID: UUID()))
        XCTAssertTrue(GalleryPageState.isNonDefaultFilter(fs))
    }

    func testIsNonDefaultFilterIsFalseWhenFilterEnabledButConditionsEmpty() {
        let fs = filterState(filterEnabled: true, selectedFilter: .empty)
        XCTAssertFalse(GalleryPageState.isNonDefaultFilter(fs))
    }

    // MARK: - isAnyTaskRunning / shouldDisableGalleryAction

    func testIsAnyTaskRunningIsFalseWhenIdle() {
        XCTAssertFalse(GalleryPageState.isAnyTaskRunning(scan: scanState(), task: taskState()))
    }

    func testIsAnyTaskRunningIsTrueWhenScanning() {
        XCTAssertTrue(GalleryPageState.isAnyTaskRunning(scan: scanState(isScanning: true), task: taskState()))
    }

    func testIsAnyTaskRunningIsTrueWhenImporting() {
        XCTAssertTrue(GalleryPageState.isAnyTaskRunning(scan: scanState(), task: taskState(isImporting: true)))
    }

    func testIsAnyTaskRunningIsTrueWhenExporting() {
        XCTAssertTrue(GalleryPageState.isAnyTaskRunning(scan: scanState(), task: taskState(isExporting: true)))
    }

    func testShouldDisableGalleryActionMatchesIsAnyTaskRunningForAllTaskKinds() {
        XCTAssertTrue(GalleryPageState.shouldDisableGalleryAction(scan: scanState(isScanning: true), task: taskState()))
        XCTAssertTrue(GalleryPageState.shouldDisableGalleryAction(scan: scanState(), task: taskState(isImporting: true)))
        XCTAssertTrue(GalleryPageState.shouldDisableGalleryAction(scan: scanState(), task: taskState(isExporting: true)))
        XCTAssertFalse(GalleryPageState.shouldDisableGalleryAction(scan: scanState(), task: taskState()))
    }

    func testShouldDisableGalleryActionIgnoresScanPaused() {
        XCTAssertTrue(GalleryPageState.shouldDisableGalleryAction(scan: scanState(isScanning: true, scanPaused: true), task: taskState()))
    }

    // MARK: - isGalleryInteractable

    func testIsGalleryInteractableIsFalseWhenIsLoading() {
        XCTAssertFalse(GalleryPageState.isGalleryInteractable(display: display(isLoading: true), scan: scanState(), task: taskState()))
    }

    func testIsGalleryInteractableIsFalseWhenScanning() {
        XCTAssertFalse(GalleryPageState.isGalleryInteractable(display: display(isLoading: false), scan: scanState(isScanning: true), task: taskState()))
    }

    func testIsGalleryInteractableIsTrueWhenIdleAndNotLoading() {
        XCTAssertTrue(GalleryPageState.isGalleryInteractable(display: display(isLoading: false), scan: scanState(), task: taskState()))
    }

    // MARK: - shouldShowScanComplete

    func testShouldShowScanCompleteIsTrueWhenFlagSetAndNotScanning() {
        XCTAssertTrue(GalleryPageState.shouldShowScanComplete(scanState(showScanCompleteDialog: true, isScanning: false)))
    }

    func testShouldShowScanCompleteIsFalseWhenScanning() {
        XCTAssertFalse(GalleryPageState.shouldShowScanComplete(scanState(showScanCompleteDialog: true, isScanning: true)))
    }

    func testShouldShowScanCompleteIsFalseWhenFlagNotSet() {
        XCTAssertFalse(GalleryPageState.shouldShowScanComplete(scanState(showScanCompleteDialog: false, isScanning: false)))
    }

    // MARK: - resolveScanProgressLabel

    func testResolveScanProgressLabelIsEmptyWhenBothCountersZero() {
        XCTAssertEqual(GalleryPageState.resolveScanProgressLabel(scanState(scanTotal: 0, scanFound: 0)), "")
    }

    func testResolveScanProgressLabelFormatsFoundOverTotal() {
        XCTAssertEqual(GalleryPageState.resolveScanProgressLabel(scanState(scanTotal: 100, scanFound: 42)), "42 / 100")
    }

    func testResolveScanProgressLabelFormatsWhenOnlyFoundSet() {
        XCTAssertEqual(GalleryPageState.resolveScanProgressLabel(scanState(scanTotal: 0, scanFound: 5)), "5 / 0")
    }

    // MARK: - 默认值工厂

    func testInitialDisplaySnapshotStartsInLoadingPhase() {
        let s = GalleryDisplaySnapshot.initial
        XCTAssertTrue(s.isLoading)
        XCTAssertEqual(s.visibleCount, 0)
        XCTAssertFalse(s.hasMorePhotos)
    }

    func testInitialFilterSnapshotStartsInactiveWithProvidedFilter() {
        let s = GalleryFilterSnapshot.initial(filter: .empty)
        XCTAssertFalse(s.filterEnabled)
        XCTAssertFalse(s.favoritesEnabled)
        XCTAssertEqual(s.selectedFilter, .empty)
    }

    func testInitialScanAndTaskSnapshotsAreAllFalse() {
        let sc = GalleryScanSnapshot.initial
        let ts = GalleryTaskSnapshot.initial
        XCTAssertFalse(sc.isScanning)
        XCTAssertFalse(sc.showScanCompleteDialog)
        XCTAssertFalse(ts.isImporting)
        XCTAssertFalse(ts.isExporting)
    }
}
