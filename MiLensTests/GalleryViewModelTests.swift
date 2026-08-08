import XCTest
@testable import MiLens

/// GalleryViewModel 测试——扫描增量游标保存条件（P0 续）。
/// 只有「真正完整完成」的扫描（未取消且无错误）才允许保存游标；
/// 失败/取消时保存会导致下次增量扫描跳过本次未扫到的照片。
/// 使用内存仓储 + MockPhotoLibraryAccess 失败注入 + MockScanCursorStore 记录保存。
@MainActor
final class GalleryViewModelTests: XCTestCase {

    private func makeVM(
        library: MockPhotoLibraryAccess,
        cursorStore: MockScanCursorStore = MockScanCursorStore()
    ) -> GalleryViewModel {
        GalleryViewModel(
            photoRepo: InMemoryPhotoRepository(),
            petRepo: InMemoryPetRepository(),
            photoLibrary: library,
            vision: MockVisionService(),
            fileStorage: MockFileStorage(),
            sandboxDir: "/documents/MiPhotos",
            cursorStore: cursorStore
        )
    }

    /// 等待扫描 Task 结束（isScanning 复位为 false）。
    private func waitForScanToFinish(_ vm: GalleryViewModel) async {
        for _ in 0..<200 where vm.isScanning {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(vm.isScanning, "扫描应在超时前结束")
    }

    // MARK: - 游标保存条件

    func testFailedScanDoesNotSaveCursor() async {
        let library = MockPhotoLibraryAccess(assets: [])
        library.streamError = GalleryTestError.streamFailure
        let cursorStore = MockScanCursorStore()
        let vm = makeVM(library: library, cursorStore: cursorStore)

        vm.startScan(scanNewOnly: true)
        await waitForScanToFinish(vm)

        XCTAssertTrue(vm.scanFailed)
        XCTAssertTrue(vm.showScanCompleteDialog) // 失败也弹窗展示错误信息
        XCTAssertTrue(cursorStore.savedTimestamps.isEmpty, "失败扫描不得保存增量游标")
    }

    func testSuccessfulScanSavesCursor() async {
        let library = MockPhotoLibraryAccess(assets: [])
        let cursorStore = MockScanCursorStore()
        let vm = makeVM(library: library, cursorStore: cursorStore)

        vm.startScan(scanNewOnly: true)
        await waitForScanToFinish(vm)

        XCTAssertFalse(vm.scanFailed)
        XCTAssertEqual(cursorStore.savedTimestamps.count, 1, "完整完成的扫描应保存游标")
    }

    func testScanNewOnlyKeepsBaselineUntilNextSuccess() async {
        // 已有历史游标：本次失败不覆盖，lastSuccessfulScan 保持原值
        let baseline = Date(timeIntervalSince1970: 1000)
        let cursorStore = MockScanCursorStore(lastSuccessfulScan: baseline)
        let library = MockPhotoLibraryAccess(assets: [])
        library.photoCountError = GalleryTestError.countFailure
        let vm = makeVM(library: library, cursorStore: cursorStore)

        vm.startScan(scanNewOnly: true)
        await waitForScanToFinish(vm)

        XCTAssertTrue(vm.scanFailed)
        XCTAssertEqual(cursorStore.savedTimestamps.count, 0)
        XCTAssertEqual(cursorStore.lastSuccessfulScan, baseline, "失败扫描不得覆盖历史游标")
    }
}

/// 测试用错误。
private enum GalleryTestError: Error {
    case streamFailure
    case countFailure
}

