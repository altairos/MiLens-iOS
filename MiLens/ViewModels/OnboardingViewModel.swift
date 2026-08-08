//  OnboardingViewModel —— 首次启动引导状态机（@Observable）。
//  iOS 设计稿「二、首次启动流程」：欢迎 → 权限说明 → 扫描 → 创建第一份档案。
//  扫描复用 ScanService（扫描只筛选不入库，DESIGN.md §7 边界），
//  建档复用 PetProfileViewModel.addPet 语义。
//  对应源端 Index.ets 引导编排（步骤顺序按 iOS 设计稿调整）。

import Foundation
import os

@MainActor
@Observable
final class OnboardingViewModel {

    private let logger = Logger(subsystem: "com.milens.app", category: "Onboarding")

    // MARK: - 步骤

    enum Step: Int, CaseIterable {
        case welcome = 0
        case permission
        case scan
        case createPet
    }

    // MARK: - 显示层状态

    var step: Step = .welcome
    /// 隐私政策已勾选（Step 0 前进前置条件）
    var privacyAgreed = false

    // 权限
    var authStatus: PhotoLibraryAuthorizationStatus = .notDetermined
    var isRequestingAuth = false

    // 扫描
    var isScanning = false
    var scanProgressText = ""
    var scanFoundCount = 0
    var scanCompleted = false
    var scanError = ""

    // 完成
    var isFinishing = false

    // 建档（Step 3）
    var petName = ""

    // MARK: - 依赖

    private let photoRepo: any PhotoRepositoryProtocol
    private let petRepo: any PetRepositoryProtocol
    private let photoLibrary: any PhotoLibraryAccess
    private let vision: any VisionService
    private let onFinish: () -> Void
    /// Phase 2 CLIP 精筛（nil = 模型缺失，仅 Vision 预筛）
    private let clipService: (any ClipInference)?
    /// 上次成功扫描游标（引导扫描完成即建立基准，供相册增量扫描使用）
    private let cursorStore: any ScanCursorStore

    private var scanTask: Task<Void, Never>?

    init(photoRepo: any PhotoRepositoryProtocol,
         petRepo: any PetRepositoryProtocol,
         photoLibrary: any PhotoLibraryAccess,
         vision: any VisionService,
         onFinish: @escaping () -> Void,
         clipService: (any ClipInference)? = nil,
         cursorStore: any ScanCursorStore = UserDefaultsScanCursorStore()) {
        self.photoRepo = photoRepo
        self.petRepo = petRepo
        self.photoLibrary = photoLibrary
        self.vision = vision
        self.onFinish = onFinish
        self.clipService = clipService
        self.cursorStore = cursorStore
    }

    // MARK: - 步骤控制

    /// 当前步骤是否允许前进（按钮禁用条件）。
    var canAdvance: Bool {
        switch step {
        case .welcome: return privacyAgreed
        case .permission: return true   // denied 也允许继续（可在系统设置补授权）
        case .scan: return !isScanning  // 扫描中不可跳过
        case .createPet: return true
        }
    }

    func goToNextStep() {
        guard canAdvance else { return }
        if step == .scan {
            // 离开扫描步骤时清空扫描错误，避免残留到建档页（扫描失败/跳过场景）
            scanError = ""
        }
        step = Step(rawValue: step.rawValue + 1) ?? .createPet
    }

    func goBack() {
        guard step.rawValue > 0 else { return }
        step = Step(rawValue: step.rawValue - 1) ?? .welcome
    }

    // MARK: - 进入扫描步骤时自动启动

    func onStepAppear() {
        if step == .scan, !isScanning, !scanCompleted, scanError.isEmpty {
            startScan()
        }
    }

    // MARK: - 权限

    func refreshAuthStatus() async {
        authStatus = await photoLibrary.authorizationStatus()
    }

    /// 请求照片权限（对应源端 requestPermissionsAndStartServices 的权限部分）。
    func requestPhotoAuthorization() async {
        guard !isRequestingAuth else { return }
        isRequestingAuth = true
        authStatus = await photoLibrary.requestAuthorization()
        isRequestingAuth = false
    }

    // MARK: - 扫描（复用 ScanService，只筛选不入库）

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scanCompleted = false
        scanError = ""
        scanFoundCount = 0

        let service = ScanService(
            photoLibrary: photoLibrary, vision: vision,
            photoRepo: photoRepo, petRepo: petRepo,
            clipService: clipService
        )
        // 游标 = 本次扫描开始时刻；成功后持久化（引导扫描是全量，之后相册增量扫描以此为基准）
        let scanStart = Date()

        scanTask = Task { [weak self] in
            guard let self else { return }
            let result = await service.scanAlbum { progress in
                self.scanProgressText = "正在寻找它的身影... \(progress.scanned)/\(progress.total)"
                self.scanFoundCount = progress.petPhotosFound
            }
            self.scanFoundCount = result.unassignedPetUris.count
            // 只有真正完整完成（未取消且无错误）才视为完成并保存增量游标——
            // 中途失败：不显示“扫描完成”，错误写入 scanError 供界面展示，
            // 且下次增量扫描不会跳过本次未扫到的照片（与 GalleryViewModel 一致）。
            self.scanCompleted = result.completedSuccessfully
            self.scanError = result.error ?? ""
            self.isScanning = false
            self.scanProgressText = ""
            if result.completedSuccessfully {
                self.cursorStore.saveLastSuccessfulScan(scanStart)
            }
        }
    }

    /// 跳过扫描（直接进入建档）。
    func skipScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanCompleted = true
        scanProgressText = ""
    }

    // MARK: - 建档

    /// 创建第一份档案（用 petName）。成功返回 true（并触发 onFinish 由调用方决定）。
    /// 复用 PetProfileViewModel.addPet 的校验语义（名称/上限/彩蛋）。
    @discardableResult
    func createFirstPet() -> Bool {
        addFirstPet(name: petName)
    }

    /// 创建成功即完成引导（Step 3 主按钮/键盘提交入口）。
    func submitCreatePet() {
        guard createFirstPet() else { return }
        finish()
    }

    /// 创建第一份档案。成功返回 true（并触发 onFinish 由调用方决定）。
    /// 复用 PetProfileViewModel.addPet 的校验语义（名称/上限/彩蛋）。
    @discardableResult
    func addFirstPet(
        name: String, species: Species = .unknown, gender: Gender = .unknown,
        birthday: Date? = nil, adoptionDay: Date? = nil
    ) -> Bool {
        let currentCount: Int
        do {
            currentCount = try petRepo.getAllPets().count
        } catch {
            logger.error("addFirstPet: 读取宠物数量失败（\(error.localizedDescription)），按 0 处理")
            currentCount = 0
        }
        if let nameError = PetProfileLogic.validateNewPetName(name) {
            scanError = nameError
            return false
        }
        if let countError = PetProfileLogic.checkPetCountLimit(currentCount: currentCount) {
            scanError = countError
            return false
        }
        let pet = Pet(
            name: name.trimmingCharacters(in: .whitespaces),
            species: species, gender: gender,
            birthday: birthday, adoptionDay: adoptionDay
        )
        do {
            try petRepo.insertPet(pet)
            scanError = ""
            return true
        } catch {
            scanError = "保存失败，请重试"
            return false
        }
    }

    // MARK: - 完成引导

    /// 完成引导：触发回调（MiLensApp 切换到主界面）。
    func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        scanTask?.cancel()
        onFinish()
    }
}
