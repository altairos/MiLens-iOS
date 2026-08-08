import XCTest
@testable import MiLens

/// OnboardingViewModel 测试——首次启动引导状态机（欢迎→权限→扫描→建档）。
/// 使用纯内存 mock（不碰 SwiftData，规避模拟器 CI 集成崩溃问题，
/// 与 ScanServiceTests 的 skip 策略一致但保留可运行性）。
@MainActor
final class OnboardingViewModelTests: XCTestCase {

    // MARK: - 辅助

    private func makeVM(
        assets: [PhotoAssetMetadata] = [],
        detections: [DetectionBox] = [],
        authStatus: PhotoLibraryAuthorizationStatus = .authorized,
        cursorStore: MockScanCursorStore = MockScanCursorStore(),
        photoCountError: Error? = nil
    ) -> (OnboardingViewModel, InMemoryPetRepository, MockPhotoLibraryAccess) {
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository()
        let photoLibrary = MockPhotoLibraryAccess(assets: assets)
        photoLibrary.authorizationStatusValue = authStatus
        photoLibrary.photoCountError = photoCountError
        let vision = MockVisionService(detections: detections)
        let vm = OnboardingViewModel(
            photoRepo: photoRepo, petRepo: petRepo,
            photoLibrary: photoLibrary, vision: vision,
            onFinish: {},
            cursorStore: cursorStore
        )
        return (vm, petRepo, photoLibrary)
    }

    private func asset(_ id: String) -> PhotoAssetMetadata {
        PhotoAssetMetadata(
            identifier: id, dateTaken: nil, dateAdded: nil,
            pixelWidth: 256, pixelHeight: 256, fileSize: 1024, displayName: "\(id).jpg"
        )
    }

    /// 轮询等待条件成立（让出 MainActor 使扫描 Task 有机会执行）。
    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
        }
    }

    // MARK: - 初始状态与步骤控制

    func testInitialState() {
        let (vm, _, _) = makeVM()
        XCTAssertEqual(vm.step, .welcome)
        XCTAssertFalse(vm.privacyAgreed)
        XCTAssertFalse(vm.canAdvance)
        XCTAssertEqual(vm.authStatus, .notDetermined)
    }

    func testWelcomeRequiresPrivacyAgreementToAdvance() {
        let (vm, _, _) = makeVM()
        // 未勾选不能前进
        vm.goToNextStep()
        XCTAssertEqual(vm.step, .welcome)
        // 勾选后前进到权限步骤
        vm.privacyAgreed = true
        XCTAssertTrue(vm.canAdvance)
        vm.goToNextStep()
        XCTAssertEqual(vm.step, .permission)
    }

    func testGoBackAtFirstStepDoesNothing() {
        let (vm, _, _) = makeVM()
        vm.goBack()
        XCTAssertEqual(vm.step, .welcome)
    }

    func testStepProgressionAndGoBack() {
        let (vm, _, _) = makeVM()
        vm.privacyAgreed = true
        vm.goToNextStep() // welcome → permission
        XCTAssertEqual(vm.step, .permission)
        XCTAssertTrue(vm.canAdvance, "权限步骤 denied 也允许继续")
        vm.goToNextStep() // permission → scan
        XCTAssertEqual(vm.step, .scan)
        vm.goBack() // scan → permission
        XCTAssertEqual(vm.step, .permission)
    }

    // MARK: - 权限

    func testRequestAuthorizationUpdatesStatus() async {
        let (vm, _, photoLibrary) = makeVM()
        photoLibrary.requestedResult = .limited
        await vm.requestPhotoAuthorization()
        XCTAssertEqual(vm.authStatus, .limited)
        XCTAssertFalse(vm.isRequestingAuth)
    }

    func testRefreshAuthStatusReadsCurrentValue() async {
        let (vm, _, photoLibrary) = makeVM(authStatus: .denied)
        await vm.refreshAuthStatus()
        XCTAssertEqual(vm.authStatus, .denied)
    }

    // MARK: - 扫描

    func testScanAutoRunsAndReportsFoundCount() async {
        let petBox = DetectionBox(x: 0.1, y: 0.1, width: 0.5, height: 0.5, label: "cat", confidence: 0.9)
        let (vm, _, _) = makeVM(
            assets: [asset("a"), asset("b"), asset("c")],
            detections: [petBox]
        )
        vm.step = .scan
        vm.onStepAppear()
        XCTAssertTrue(vm.isScanning)
        XCTAssertFalse(vm.canAdvance, "扫描中不可前进")
        await waitUntil { !vm.isScanning }
        XCTAssertTrue(vm.scanCompleted)
        XCTAssertEqual(vm.scanFoundCount, 3)
        XCTAssertTrue(vm.scanError.isEmpty, "成功后不应残留错误")
        XCTAssertTrue(vm.canAdvance, "扫描完成后可前进")
    }

    func testScanWithNoPhotosCompletesEmpty() async {
        let (vm, _, _) = makeVM()
        vm.step = .scan
        vm.onStepAppear()
        await waitUntil { !vm.isScanning }
        XCTAssertTrue(vm.scanCompleted)
        XCTAssertEqual(vm.scanFoundCount, 0)
        XCTAssertTrue(vm.canAdvance)
    }

    func testSkipScanCancelsAndAllowsAdvance() async {
        let (vm, _, _) = makeVM(assets: [asset("a")])
        vm.step = .scan
        vm.onStepAppear()
        XCTAssertTrue(vm.isScanning)
        vm.skipScan()
        XCTAssertFalse(vm.isScanning)
        XCTAssertTrue(vm.scanCompleted)
        XCTAssertTrue(vm.canAdvance)
        // 扫描任务被取消，不应再覆盖状态
        await waitUntil { !vm.isScanning }
        XCTAssertTrue(vm.scanCompleted)
    }

    func testScanSuccessSavesCursor() async {
        let cursor = MockScanCursorStore()
        let (vm, _, _) = makeVM(assets: [asset("a")], cursorStore: cursor)
        vm.step = .scan
        vm.onStepAppear()
        await waitUntil { !vm.isScanning }
        XCTAssertTrue(vm.scanCompleted)
        XCTAssertNotNil(cursor.lastSuccessfulScan, "完整完成后必须保存增量游标基准")
    }

    func testScanFailureShowsErrorAndDoesNotComplete() async {
        let cursor = MockScanCursorStore()
        // 扫描中途失败（photoCount 抛错）：不得显示为完成、错误必须可见、不得保存游标
        let (vm, _, _) = makeVM(
            assets: [asset("a")],
            cursorStore: cursor,
            photoCountError: MockOnboardingScanError.countFailure
        )
        vm.step = .scan
        vm.onStepAppear()
        await waitUntil { !vm.isScanning }
        XCTAssertFalse(vm.scanCompleted, "失败不得显示为扫描完成")
        XCTAssertEqual(vm.scanError, "读取照片数量失败", "失败原因必须写入 scanError 供界面展示")
        XCTAssertNil(cursor.lastSuccessfulScan, "扫描失败不得保存增量游标")

        // 失败后可通过跳过继续（scanCompleted 置位，错误保留供扫描页展示）
        vm.skipScan()
        XCTAssertTrue(vm.scanCompleted)
        XCTAssertEqual(vm.scanError, "读取照片数量失败")

        // 离开扫描步骤时清空错误，不残留到建档页
        vm.goToNextStep()
        XCTAssertEqual(vm.step, .createPet)
        XCTAssertTrue(vm.scanError.isEmpty, "扫描错误不得残留到建档页")
    }

    // MARK: - 建档

    func testAddFirstPetRejectsBlankName() {
        let (vm, _, _) = makeVM()
        XCTAssertFalse(vm.addFirstPet(name: "   "))
        XCTAssertEqual(vm.scanError, "请输入宠物名字")
    }

    func testCreateFirstPetSuccessInsertsPet() {
        let (vm, petRepo, _) = makeVM()
        vm.petName = "小橘"
        XCTAssertTrue(vm.createFirstPet())
        XCTAssertEqual(try? petRepo.getAllPets().count, 1)
        XCTAssertEqual(try? petRepo.getAllPets().first?.name, "小橘")
        XCTAssertEqual(vm.scanError, "")
    }

    func testAddFirstPetEnforcesCountLimit() {
        let (vm, petRepo, _) = makeVM()
        // 预置达到上限的宠物数
        for i in 0..<PetProfileConstants.maxPets {
            try? petRepo.insertPet(Pet(name: "宠物\(i)"))
        }
        XCTAssertFalse(vm.addFirstPet(name: "多一只"))
        XCTAssertEqual(vm.scanError, "最多支持管理 \(PetProfileConstants.maxPets) 只伙伴")
        XCTAssertEqual(try? petRepo.getAllPets().count, PetProfileConstants.maxPets)
    }

    // MARK: - 完成

    func testFinishTriggersCallbackOnce() {
        var finishCount = 0
        let photoRepo = InMemoryPhotoRepository()
        let petRepo = InMemoryPetRepository()
        let vm = OnboardingViewModel(
            photoRepo: photoRepo, petRepo: petRepo,
            photoLibrary: MockPhotoLibraryAccess(),
            vision: MockVisionService(),
            onFinish: { finishCount += 1 }
        )
        vm.finish()
        vm.finish()
        XCTAssertEqual(finishCount, 1)
    }
}

/// Onboarding 扫描失败注入用错误（ScanServiceTests 的 MockScanError 为 private，此处独立定义）。
private enum MockOnboardingScanError: Error {
    case countFailure
}

