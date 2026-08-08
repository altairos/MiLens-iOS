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

    // MARK: - 权限前置（对应源端 checkAndRequestPermission）

    func testScanDeniedWithoutPermissionShowsGuideAndSkipsScan() async {
        // 权限被拒（denied）时不得直接跑扫描：弹窗引导去设置，且不保存增量游标
        let library = MockPhotoLibraryAccess(assets: [])
        library.authorizationStatusValue = .denied
        let cursorStore = MockScanCursorStore()
        let vm = makeVM(library: library, cursorStore: cursorStore)

        vm.startScan(scanNewOnly: true)
        await waitForScanToFinish(vm)

        XCTAssertTrue(vm.permissionDenied, "权限被拒应进入引导分支")
        XCTAssertTrue(vm.scanFailed)
        XCTAssertTrue(vm.showScanCompleteDialog, "被拒也弹窗展示引导信息")
        XCTAssertTrue(cursorStore.savedTimestamps.isEmpty, "未授权不得保存游标")
    }

    func testScanRequestsAuthorizationWhenNotDetermined() async {
        // 从未授权（notDetermined）：先弹系统授权，授权后继续扫描并保存游标
        let library = MockPhotoLibraryAccess(assets: [])
        library.authorizationStatusValue = .notDetermined
        library.requestedResult = .authorized
        let cursorStore = MockScanCursorStore()
        let vm = makeVM(library: library, cursorStore: cursorStore)

        vm.startScan(scanNewOnly: true)
        await waitForScanToFinish(vm)

        XCTAssertFalse(vm.permissionDenied, "弹窗授权后应继续扫描")
        XCTAssertFalse(vm.scanFailed)
        XCTAssertEqual(cursorStore.savedTimestamps.count, 1, "授权后完整完成的扫描应保存游标")
    }

    // MARK: - 删除（走媒体生命周期服务）

    func testDeletePhotoGoesThroughMediaLifecycle() async {
        // 删除必须走 MediaLifecycleService（DB + 沙盒文件 + 宠物计数联动），
        // 直接调 photoRepo.deletePhoto 会残留沙盒孤儿文件、宠物计数不刷新
        let pet = Pet(name: "小橘")
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository(pets: [pet])
        let fileStorage = MockFileStorage()
        let photo = Photo(uri: "/documents/MiPhotos/a.jpg", pet: pet, takenAt: Date(), note: "")
        try? photoRepo.insertPhoto(photo)
        fileStorage.preset(Data([1]), at: photo.uri)

        let library = MockPhotoLibraryAccess(assets: [])
        let vm = GalleryViewModel(
            photoRepo: photoRepo, petRepo: petRepo,
            photoLibrary: library, vision: MockVisionService(),
            fileStorage: fileStorage, sandboxDir: "/documents/MiPhotos",
            cursorStore: MockScanCursorStore()
        )
        vm.loadInitial()
        XCTAssertEqual(vm.photos.count, 1)
        XCTAssertEqual(vm.totalPhotoCount, 1)

        vm.deletePhoto(id: photo.id)
        // 删除是异步编排（mediaLifecycle.deletePhoto async）：等待内存状态收敛
        for _ in 0..<200 where vm.photos.count == 1 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(vm.photos.isEmpty)
        XCTAssertEqual(vm.totalPhotoCount, 0)
        XCTAssertNil(try? photoRepo.getPhoto(id: photo.id), "DB 记录必须删除")
        XCTAssertFalse(fileStorage.fileExists(at: photo.uri), "沙盒媒体文件必须联动删除，不留孤儿文件")
    }
}

/// 测试用错误。
private enum GalleryTestError: Error {
    case streamFailure
    case countFailure
}
