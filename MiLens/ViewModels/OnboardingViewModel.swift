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

    // 特征注册引导（建档成功后展示，对应源端建档完成 → 引导注册特征）
    /// 是否显示特征注册引导卡片（submitCreatePet 建档成功后设置）
    var showFeatureRegistration = false
    /// 刚创建的宠物 ID（addFirstPet 成功时记录，供特征注册使用）
    private(set) var createdPetID: UUID?
    /// 正在提取特征
    var isRegisteringFeatures = false
    /// 特征提取进度（已处理张数）
    var featureRegistrationProgress = 0
    /// 注册结果消息
    var featureRegistrationMessage = ""
    /// 特征注册成功（显示「开始使用」入口）
    var featureRegistered = false

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
    private var featureTask: Task<Void, Never>?
    /// 扫描代次：skipScan/新扫描时递增，旧任务据此丢弃回写（防止取消竞争覆盖状态）
    private var scanGeneration = 0

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
        // 代次递增：skipScan 后旧任务即使随后返回 canceled 也不得回写状态
        scanGeneration += 1
        let generation = scanGeneration
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
                guard self.scanGeneration == generation else { return }
                self.scanProgressText = "正在寻找它的身影... \(progress.scanned)/\(progress.total)"
                self.scanFoundCount = progress.petPhotosFound
            }
            // 已被 skipScan/新扫描接管：旧任务的收尾回写全部丢弃
            guard self.scanGeneration == generation else { return }
            self.scanFoundCount = result.unassignedPetUris.count + result.matchedUris.count
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
        scanGeneration += 1
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
    /// 模型可用时先引导注册视觉特征（自动归属前置条件），否则直接完成。
    func submitCreatePet() {
        guard createFirstPet() else { return }
        if clipService != nil, createdPetID != nil {
            showFeatureRegistration = true
        } else {
            finish()
        }
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
            createdPetID = pet.id
            return true
        } catch {
            scanError = "保存失败，请重试"
            return false
        }
    }

    // MARK: - 特征注册引导

    /// 用选中的照片注册刚创建宠物的视觉特征（8–15 张，与档案编辑页同一链路）。
    /// 异步执行：进度与结果分别写入 featureRegistrationProgress / featureRegistrationMessage。
    func registerCreatedPetFeature(imageDatas: [Data]) {
        guard let petID = createdPetID, !isRegisteringFeatures else { return }
        // 数量校验（对应源端 resolveRegistrationValidation）
        if imageDatas.count < PetFormConstants.minRegistrationPhotos {
            featureRegistrationMessage = "请至少选择 \(PetFormConstants.minRegistrationPhotos) 张照片"
            return
        }
        if imageDatas.count > PetFormConstants.maxRegistrationPhotos {
            featureRegistrationMessage = "最多选择 \(PetFormConstants.maxRegistrationPhotos) 张照片"
            return
        }
        isRegisteringFeatures = true
        featureRegistrationProgress = 0
        featureRegistrationMessage = ""
        featureTask = Task { [weak self] in
            guard let self else { return }
            let matcher = PetMatcher(petRepo: self.petRepo, clipService: self.clipService)
            let ok = await matcher.registerPetFeatures(
                petID: petID, imageDatas: imageDatas
            ) { [weak self] progress in
                self?.featureRegistrationProgress = progress
            }
            self.isRegisteringFeatures = false
            if ok {
                self.featureRegistered = true
                self.featureRegistrationMessage = "已注册 \(imageDatas.count) 张照片的视觉特征"
            } else {
                self.featureRegistrationMessage = "注册失败：\(matcher.lastRegisterDiagnostics)"
            }
            self.featureTask = nil
        }
    }

    /// 跳过特征注册，直接完成引导（「稍后再说」/「取消」）。
    func skipFeatureRegistration() {
        featureTask?.cancel()
        featureTask = nil
        isRegisteringFeatures = false
        showFeatureRegistration = false
        finish()
    }

    /// 注册成功后的「开始使用」入口（完成引导）。
    func finishAfterFeatureRegistration() {
        showFeatureRegistration = false
        finish()
    }

    // MARK: - 完成引导

    /// 完成引导：触发回调（MiLensApp 切换到主界面）。
    func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        // 代次递增：扫描任务即使随后退出也不得再回写状态（防止覆盖完成态）
        scanGeneration += 1
        scanTask?.cancel()
        onFinish()
    }
}
