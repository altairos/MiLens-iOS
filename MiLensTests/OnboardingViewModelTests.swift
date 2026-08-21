import XCTest
@testable import MiLens

/// OnboardingViewModel 测试——首次启动引导「First Archive」状态机。
/// 流程：欢迎(空态/隐私摘要) → 建立档案 → 特征注册 → 全面扫描 → 候选确认 → 导入 → 成功。
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
        photoCountError: Error? = nil,
        importExecutor: OnboardingImportExecutor? = nil
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
            cursorStore: cursorStore,
            importExecutor: importExecutor
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
        XCTAssertFalse(vm.termsAgreed)
        XCTAssertFalse(vm.canAdvance)
        XCTAssertEqual(vm.authStatus, .notDetermined)
        XCTAssertEqual(vm.majorStage, 0)
    }

    func testWelcomeRequiresBothLegalDocumentAgreementsToAdvance() {
        let (vm, _, _) = makeVM()
        // 未勾选不能前进
        vm.goToNextStep()
        XCTAssertEqual(vm.step, .welcome)
        // 只同意隐私政策仍不能前进
        vm.privacyAgreed = true
        XCTAssertFalse(vm.canAdvance)
        vm.goToNextStep()
        XCTAssertEqual(vm.step, .welcome)
        // 两份文档都同意后前进到隐私摘要步骤
        vm.termsAgreed = true
        XCTAssertTrue(vm.canAdvance)
        vm.goToNextStep()
        XCTAssertEqual(vm.step, .privacy)
    }

    func testGoBackAtFirstStepDoesNothing() {
        let (vm, _, _) = makeVM()
        vm.goBack()
        XCTAssertEqual(vm.step, .welcome)
    }

    func testMajorStageMapping() {
        let (vm, _, _) = makeVM()
        vm.privacyAgreed = true
        vm.termsAgreed = true
        vm.goToNextStep() // welcome → privacy
        XCTAssertEqual(vm.majorStage, 0)
        vm.goToNextStep() // privacy → createArchive
        XCTAssertEqual(vm.majorStage, 1)
        XCTAssertEqual(vm.stageIndexText, "02")
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

    // MARK: - 建档

    func testCreateArchiveRequiresName() {
        let (vm, _, _) = makeVM()
        vm.step = .createArchive
        XCTAssertFalse(vm.canAdvance, "名字为空不可前进")
        vm.petName = "小满"
        XCTAssertTrue(vm.canAdvance)
    }

    func testAddFirstPetRejectsBlankName() {
        let (vm, _, _) = makeVM()
        XCTAssertFalse(vm.addFirstPet(name: "   "))
        XCTAssertEqual(vm.scanError, "请输入宠物名字")
    }

    func testCreateFirstPetSuccessInsertsPetWithSpecies() {
        let (vm, petRepo, _) = makeVM()
        vm.petName = "小橘"
        vm.petSpecies = .cat
        XCTAssertTrue(vm.createFirstPet())
        XCTAssertEqual(try? petRepo.getAllPets().count, 1)
        let pet = try? petRepo.getAllPets().first
        XCTAssertEqual(pet?.name, "小橘")
        XCTAssertEqual(pet?.species, .cat)
        XCTAssertEqual(vm.scanError, "")
        XCTAssertNotNil(vm.createdPetID)
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

    func testSubmitCreatePetNoClipSkipsFeatureRegister() {
        // 无 CLIP 模型：建档成功后跳过特征注册，直接进入 fullScan
        let (vm, petRepo, _) = makeVM()
        vm.petName = "小满"
        vm.petSpecies = .dog
        vm.submitCreatePet()
        XCTAssertEqual(try? petRepo.getAllPets().count, 1)
        XCTAssertEqual(vm.step, .fullScan, "无 CLIP 时建档后直接进 fullScan")
        XCTAssertFalse(vm.showFeatureRegistration)
    }

    // MARK: - 扫描（fullScan 复用 ScanService）

    func testScanAutoRunsAndReportsFoundCount() async {
        let petBox = DetectionBox(x: 0.1, y: 0.1, width: 0.5, height: 0.5, label: "cat", confidence: 0.9)
        let (vm, _, _) = makeVM(
            assets: [asset("a"), asset("b"), asset("c")],
            detections: [petBox]
        )
        vm.step = .fullScan
        vm.onStepAppear()
        XCTAssertTrue(vm.isScanning)
        XCTAssertFalse(vm.canAdvance, "扫描中不可前进")
        await waitUntil { !vm.isScanning }
        XCTAssertTrue(vm.scanCompleted)
        XCTAssertEqual(vm.scanFoundCount, 3)
        XCTAssertTrue(vm.scanError.isEmpty, "成功后不应残留错误")
        XCTAssertEqual(vm.candidateURIs.count, 3)
        XCTAssertTrue(vm.canAdvance, "扫描完成后可前进")
    }

    func testScanWithNoPhotosCompletesEmpty() async {
        let (vm, _, _) = makeVM()
        vm.step = .fullScan
        vm.onStepAppear()
        await waitUntil { !vm.isScanning }
        XCTAssertTrue(vm.scanCompleted)
        XCTAssertEqual(vm.scanFoundCount, 0)
        XCTAssertTrue(vm.candidateURIs.isEmpty)
    }

    func testSkipScanCancelsAndAllowsAdvance() async {
        let (vm, _, _) = makeVM(assets: [asset("a")])
        vm.step = .fullScan
        vm.onStepAppear()
        XCTAssertTrue(vm.isScanning)
        vm.skipScan()
        XCTAssertFalse(vm.isScanning)
        XCTAssertTrue(vm.scanCompleted)
        // 扫描任务被取消，不应再覆盖状态
        await waitUntil { !vm.isScanning }
        XCTAssertTrue(vm.scanCompleted)
    }

    func testSkipScanCanceledTaskCannotOverwriteCompleted() async {
        // 取消竞争回归：skipScan 先把 scanCompleted 置 true，被取消的旧任务随后
        // 返回 canceled 结果——generation 守卫下不得把它覆盖回 false。
        let (vm, _, _) = makeVM(assets: [asset("a")])
        vm.step = .fullScan
        vm.onStepAppear()
        XCTAssertTrue(vm.isScanning)
        vm.skipScan()
        XCTAssertTrue(vm.scanCompleted)
        // 让出 MainActor，给被取消的旧任务完整执行收尾回写的机会
        for _ in 0..<50 { await Task.yield() }
        XCTAssertTrue(vm.scanCompleted, "被取消的旧任务不得把 scanCompleted 覆盖回 false")
        XCTAssertFalse(vm.isScanning)
    }

    func testScanSuccessSavesCursor() async {
        let cursor = MockScanCursorStore()
        let (vm, _, _) = makeVM(assets: [asset("a")], cursorStore: cursor)
        vm.step = .fullScan
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
        vm.step = .fullScan
        vm.onStepAppear()
        await waitUntil { !vm.isScanning }
        XCTAssertFalse(vm.scanCompleted, "失败不得显示为扫描完成")
        XCTAssertEqual(vm.scanError, "读取照片数量失败", "失败原因必须写入 scanError 供界面展示")
        XCTAssertNil(cursor.lastSuccessfulScan, "扫描失败不得保存增量游标")
    }

    // MARK: - 候选确认

    func testPrepareCandidatesSelectsAllByDefault() async {
        let petBox = DetectionBox(x: 0.1, y: 0.1, width: 0.5, height: 0.5, label: "cat", confidence: 0.9)
        let (vm, _, _) = makeVM(
            assets: [asset("a"), asset("b")],
            detections: [petBox]
        )
        vm.petName = "小满"
        vm.submitCreatePet() // 无 CLIP → fullScan
        vm.onStepAppear()
        await waitUntil { !vm.isScanning }
        vm.step = .candidates
        vm.prepareCandidates()
        XCTAssertEqual(vm.selectedCandidateIDs.count, vm.candidateURIs.count)
    }

    func testToggleCandidate() {
        let (vm, _, _) = makeVM()
        vm.candidateURIs = ["a", "b", "c"]
        vm.selectedCandidateIDs = ["a", "b", "c"]
        vm.toggleCandidate("b")
        XCTAssertFalse(vm.selectedCandidateIDs.contains("b"))
        XCTAssertEqual(vm.selectedCandidateIDs.count, 2)
        vm.toggleCandidate("b")
        XCTAssertTrue(vm.selectedCandidateIDs.contains("b"))
    }

    func testCandidatesCanAdvanceRequiresSelection() {
        let (vm, _, _) = makeVM()
        vm.step = .candidates
        vm.selectedCandidateIDs = []
        XCTAssertFalse(vm.canAdvance)
        vm.selectedCandidateIDs = ["a"]
        XCTAssertTrue(vm.canAdvance)
    }

    // MARK: - 导入

    func testImportConfirmedCandidatesRunsExecutor() async {
        var executedIdentifiers: [String] = []
        var executedPetID: UUID?
        let executor: OnboardingImportExecutor = { ids, petID, _ in
            executedIdentifiers = ids
            executedPetID = petID
            return ids.count
        }
        let (vm, _, _) = makeVM(importExecutor: executor)
        vm.petName = "小满"
        vm.submitCreatePet()
        // 模拟候选
        vm.candidateURIs = ["a", "b"]
        vm.selectedCandidateIDs = ["a", "b"]
        vm.importConfirmedCandidates()
        XCTAssertEqual(vm.step, .importing)
        await waitUntil { vm.step == .success }
        XCTAssertEqual(vm.importedCount, 2)
        XCTAssertEqual(executedIdentifiers, ["a", "b"])
        XCTAssertEqual(executedPetID, vm.createdPetID)
    }

    func testImportWithoutExecutorDegradesGracefully() async {
        let (vm, _, _) = makeVM()
        vm.petName = "小满"
        vm.submitCreatePet()
        vm.candidateURIs = ["a"]
        vm.selectedCandidateIDs = ["a"]
        vm.importConfirmedCandidates()
        await waitUntil { vm.step == .success }
        XCTAssertEqual(vm.importedCount, 0, "无 executor 降级：不执行真实导入，计数为 0")
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

    // MARK: - overline / stageIndexText

    // overline 已 key 化（onboarding.overline.*，catalog 内含 en 译文）：
    // 期望值用 String(localized:) 同表查取，与宿主语言无关，避免 CI 语言环境导致 flaky
    // （参照 DynamicCopyLocaleSnapshotTests 的固定语言思路，查表一致性由本断言保证）。
    func testStepOverlineAndStageIndex() {
        let (vm, _, _) = makeVM()
        XCTAssertEqual(vm.stepOverline, String(localized: "onboarding.overline.welcome"))
        XCTAssertEqual(vm.stageIndexText, "01")
        vm.step = .createArchive
        XCTAssertEqual(vm.stepOverline, String(localized: "onboarding.overline.createArchive"))
        XCTAssertEqual(vm.stageIndexText, "02")
        vm.step = .fullScan
        XCTAssertEqual(vm.stepOverline, String(localized: "onboarding.overline.fullScan"))
        XCTAssertEqual(vm.stageIndexText, "04")
    }
}

/// Onboarding 扫描失败注入用错误（ScanServiceTests 的 MockScanError 为 private，此处独立定义）。
private enum MockOnboardingScanError: Error {
    case countFailure
}
