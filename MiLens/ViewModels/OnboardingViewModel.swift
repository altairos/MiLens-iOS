//  OnboardingViewModel —— 首次启动引导「First Archive」状态机（@Observable）。
//  对照 Figma「相册扫描与配额付费墙原型」#47:2 Onboarding · First Launch 画板。
//
//  流程：欢迎(空态) → 隐私摘要 → 建立档案 → 特征注册(选图/处理/完成) →
//       全面扫描 → 候选确认 → 导入中 → 导入成功 → 完成。
//  与旧 4 步流程的关键差异：**先建档 → 特征注册 → 再扫描**（让扫描有特征基准可比对）。
//  扫描复用 ScanService（只筛选不入库，DESIGN.md §7 边界）；
//  建档复用 PetProfileLogic 校验语义；
//  导入复用 ImportService 链路（由 importExecutor 闭包注入，保持可测）。

import Foundation
import os

/// 引导流程导入执行器：把已确认候选写入档案 + 强制归属到刚创建的宠物。
/// 闭包注入便于生产环境复用 ImportService、测试环境注入模拟实现。
/// onProgress 必须 @escaping：async 执行器内被 ImportService 的进度回
/// 调捕获，跨 await 点调用（non-escaping 参数被 escaping 闭包捕获会拒绝编译）。
typealias OnboardingImportExecutor = @MainActor (
    _ identifiers: [String],
    _ targetPetID: UUID?,
    _ onProgress: @escaping @MainActor (Double) -> Void
) async -> Int

@MainActor
@Observable
final class OnboardingViewModel {

    private let logger = Logger(subsystem: "com.milens.app", category: "Onboarding")

    // MARK: - 步骤（对照 11 画板 / 4 大阶段）

    enum Step: Int, CaseIterable {
        case welcome = 0       // 01 欢迎 / 空态（#47:6）
        case privacy           // 01 欢迎 / 隐私摘要（#47:7）
        case createArchive     // 02 建立档案（#47:10）
        case featureIntro      // 03 特征注册 / 说明与选图（#47:8 / #47:11）
        case featureProcessing // 03 特征注册 / 本机处理（#117:50）
        case featureDone       // 03 特征注册 / 基准已建立（#117:100）
        case fullScan          // 04 全面扫描系统图库（#47:9）
        case candidates        // 04 候选确认（#123:74）
        case importing         // 04 导入中（#123:161）
        case success           // 04 导入成功（#123:198）
    }

    /// 大阶段总数（进度指示器段数与 a11y「第 X 步，共 N 步」标签共用）。
    static let majorStageCount = 4

    /// 当前所属大阶段（0..3，供 OnboardingView 4 段进度指示器点亮）。
    var majorStage: Int {
        switch step {
        case .welcome, .privacy: return 0
        case .createArchive: return 1
        case .featureIntro, .featureProcessing, .featureDone: return 2
        case .fullScan, .candidates, .importing, .success: return 3
        }
    }

    // MARK: - 显示层状态

    var step: Step = .welcome
    /// 隐私政策已勾选（welcome 前进前置条件）
    var privacyAgreed = false

    // 权限
    var authStatus: PhotoLibraryAuthorizationStatus = .notDetermined
    var isRequestingAuth = false

    // 扫描（fullScan 复用 ScanService，只筛选不入库）
    var isScanning = false
    var scanProgressText = ""
    /// 已扫描 / 总数（供 Viewfinder 显示 "1248 / 3860"）
    var scanScanned = 0
    var scanTotal = 0
    /// 扫描发现的候选照片数
    var scanFoundCount = 0
    var scanCompleted = false
    var scanError = ""

    // 候选 / 导入
    /// 候选照片 identifier 列表（扫描完成后填充）
    var candidateURIs: [String] = []
    /// 候选页用户选中的 identifier 集合
    var selectedCandidateIDs: Set<String> = []
    var isImporting = false
    var importPercent: Double = 0
    var importedCount = 0

    // 完成
    var isFinishing = false

    // 建档（createArchive）
    var petName = ""
    var petSpecies: Species = .unknown

    // 特征注册
    /// 是否显示特征注册引导卡片（建档成功后展示）
    var showFeatureRegistration = false
    /// 刚创建的宠物 ID（addFirstPet 成功时记录，供特征注册与导入归属使用）
    private(set) var createdPetID: UUID?
    /// 正在提取特征
    var isRegisteringFeatures = false
    /// 特征提取进度（已处理张数）
    var featureRegistrationProgress = 0
    /// 特征注册处理百分比（0..1，供 Lens 圆环显示，对照 #117:73 "72%"）
    var featureRegisterPercent: Double = 0
    /// 注册结果消息
    var featureRegistrationMessage = ""
    /// 特征注册成功（featureDone 前置条件）
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
    /// 导入执行器（nil = 降级，不执行真实导入；生产环境由 AppDependencies 注入）
    private let importExecutor: OnboardingImportExecutor?

    private var scanTask: Task<Void, Never>?
    private var featureTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    /// 扫描代次：skipScan/新扫描时递增，旧任务据此丢弃回写（防止取消竞争覆盖状态）
    private var scanGeneration = 0

    init(photoRepo: any PhotoRepositoryProtocol,
         petRepo: any PetRepositoryProtocol,
         photoLibrary: any PhotoLibraryAccess,
         vision: any VisionService,
         onFinish: @escaping () -> Void,
         clipService: (any ClipInference)? = nil,
         cursorStore: any ScanCursorStore = UserDefaultsScanCursorStore(),
         importExecutor: OnboardingImportExecutor? = nil) {
        self.photoRepo = photoRepo
        self.petRepo = petRepo
        self.photoLibrary = photoLibrary
        self.vision = vision
        self.onFinish = onFinish
        self.clipService = clipService
        self.cursorStore = cursorStore
        self.importExecutor = importExecutor
    }

    // MARK: - 步骤控制

    /// 当前步骤是否允许前进（按钮禁用条件）。
    var canAdvance: Bool {
        switch step {
        case .welcome: return privacyAgreed
        case .privacy: return true   // denied 也允许继续（可在系统设置补授权）
        case .createArchive: return !petName.trimmingCharacters(in: .whitespaces).isEmpty
        case .featureIntro: return featureSelectionReady
        case .featureProcessing: return false  // 处理中不可前进
        case .featureDone: return true
        case .fullScan: return scanCompleted && !isScanning
        case .candidates: return !selectedCandidateIDs.isEmpty
        case .importing: return false  // 导入中不可前进
        case .success: return true
        }
    }

    func goToNextStep() {
        guard canAdvance else { return }
        if step == .fullScan {
            // 离开扫描步骤时清空扫描错误，避免残留到后续页（扫描失败/跳过场景）
            scanError = ""
        }
        step = Step(rawValue: step.rawValue + 1) ?? .success
    }

    func goBack() {
        guard step.rawValue > 0 else { return }
        step = Step(rawValue: step.rawValue - 1) ?? .welcome
    }

    /// 当前步骤 overline 文案（对照 Figma Caption，供 OnboardingView header 显示）。
    var stepOverline: String {
        switch step {
        case .welcome: return String(localized: "onboarding.overline.welcome")
        case .privacy: return String(localized: "onboarding.overline.privacy")
        case .createArchive: return String(localized: "onboarding.overline.createArchive")
        case .featureIntro: return String(localized: "onboarding.overline.featureIntro")
        case .featureProcessing: return String(localized: "onboarding.overline.featureProcessing")
        case .featureDone: return String(localized: "onboarding.overline.featureDone")
        case .fullScan: return String(localized: "onboarding.overline.fullScan")
        case .candidates: return String(localized: "onboarding.overline.candidates")
        case .importing: return String(localized: "onboarding.overline.importing")
        case .success: return String(localized: "onboarding.overline.success")
        }
    }

    /// 当前大阶段编号文案（01/02/03/04，对照 Figma Fraunces Bold 12）。
    var stageIndexText: String {
        String(format: "%02d", majorStage + 1)
    }

    // MARK: - 进入特定步骤时自动启动

    func onStepAppear() {
        switch step {
        case .fullScan:
            // 进入全面扫描：自动启动（复用 ScanService，只筛选不入库）
            if !isScanning, !scanCompleted, scanError.isEmpty {
                startScan()
            }
        default:
            break
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
        scanScanned = 0
        scanTotal = 0

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
                self.scanProgressText = String(localized: "onboarding.scan.progress \(progress.scanned) \(progress.total)")
                self.scanScanned = progress.scanned
                self.scanTotal = progress.total
                self.scanFoundCount = progress.petPhotosFound
            }
            // 已被 skipScan/新扫描接管：旧任务的收尾回写全部丢弃
            guard self.scanGeneration == generation else { return }
            self.scanFoundCount = result.unassignedPetUris.count + result.matchedUris.count
            // 候选 URI = 未归属 + 预匹配，供候选页展示
            self.candidateURIs = result.unassignedPetUris + result.matchedUris
            // 只有真正完整完成（未取消且无错误）才视为完成并保存增量游标——
            // 中途失败：不显示"扫描完成"，错误写入 scanError 供界面展示，
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

    /// 跳过扫描（直接进入建档后的下一步；当无 CLIP 走降级路径时也用此入口）。
    func skipScan() {
        scanGeneration += 1
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanCompleted = true
        scanProgressText = ""
        candidateURIs = []
    }

    // MARK: - 建档（createArchive）

    /// 创建第一份档案（用 petName + petSpecies）。成功返回 true。
    /// 复用 PetProfileViewModel.addPet 的校验语义（名称/上限/彩蛋）。
    @discardableResult
    func createFirstPet() -> Bool {
        addFirstPet(name: petName, species: petSpecies)
    }

    /// createArchive 主按钮 / 键盘提交入口。
    /// 建档成功后进入特征注册（featureIntro）；无 CLIP 模型时跳过特征注册直接进入 fullScan
    /// （保持诚实标注，不伪装已注册特征）。
    func submitCreatePet() {
        guard createFirstPet() else { return }
        showFeatureRegistration = (clipService != nil)
        if clipService != nil, createdPetID != nil {
            step = .featureIntro
        } else {
            // 无 CLIP 模型：跳过特征注册，直接进入全面扫描
            step = .fullScan
        }
    }

    /// 创建第一份档案。成功返回 true。
    /// 复用 PetProfileViewModel.addPet 的校验语义（名称/上限）。
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
            scanError = String(localized: "onboarding.createArchive.saveFailed")
            return false
        }
    }

    // MARK: - 特征注册

    /// 特征注册选图是否就绪（达到下限张数）。
    var featureSelectionReady: Bool {
        featureRegistrationProgress >= PetFormConstants.minRegistrationPhotos
        || featureRegistered
    }

    /// 用选中的照片注册刚创建宠物的视觉特征（8–15 张，与档案编辑页同一链路）。
    /// 异步执行：进度与结果分别写入 featureRegistrationProgress / featureRegisterPercent / featureRegistrationMessage。
    /// 成功后自动进入 featureDone。
    func registerCreatedPetFeature(imageDatas: [Data]) {
        guard let petID = createdPetID, !isRegisteringFeatures else { return }
        // 数量校验（对应源端 resolveRegistrationValidation）
        if imageDatas.count < PetFormConstants.minRegistrationPhotos {
            featureRegistrationMessage = String(localized: "onboarding.feature.minCount \(PetFormConstants.minRegistrationPhotos)")
            return
        }
        if imageDatas.count > PetFormConstants.maxRegistrationPhotos {
            featureRegistrationMessage = String(localized: "onboarding.feature.maxCount \(PetFormConstants.maxRegistrationPhotos)")
            return
        }
        isRegisteringFeatures = true
        featureRegistrationProgress = 0
        featureRegisterPercent = 0
        featureRegistrationMessage = ""
        step = .featureProcessing
        featureTask = Task { [weak self] in
            guard let self else { return }
            let total = imageDatas.count
            let matcher = PetMatcher(petRepo: self.petRepo, clipService: self.clipService)
            let ok = await matcher.registerPetFeatures(
                petID: petID, imageDatas: imageDatas
            ) { [weak self] progress in
                self?.featureRegistrationProgress = progress
                self?.featureRegisterPercent = Double(progress) / Double(max(total, 1))
            }
            self.isRegisteringFeatures = false
            self.featureRegisterPercent = 1
            if ok {
                self.featureRegistered = true
                self.featureRegistrationMessage = String(localized: "onboarding.feature.registered \(imageDatas.count)")
                self.step = .featureDone
            } else {
                self.featureRegistrationMessage = String(localized: "onboarding.feature.registerFailed \(matcher.lastRegisterDiagnostics)")
            }
            self.featureTask = nil
        }
    }

    /// featureDone「允许扫描系统图库」入口：进入全面扫描阶段。
    func proceedToFullScan() {
        step = .fullScan
    }

    /// 跳过特征注册，直接进入全面扫描（"稍后再说"）。
    func skipFeatureRegistration() {
        featureTask?.cancel()
        featureTask = nil
        isRegisteringFeatures = false
        showFeatureRegistration = false
        step = .fullScan
    }

    // MARK: - 候选确认

    /// 进入候选页时默认全选（对照 AlbumScanFlow 行为）。
    func prepareCandidates() {
        if candidateURIs.isEmpty {
            // 扫描无候选：跳过候选确认，直接进入建档完成（无导入）
            step = .success
            importedCount = 0
            return
        }
        if selectedCandidateIDs.isEmpty {
            selectedCandidateIDs = Set(candidateURIs)
        }
    }

    func toggleCandidate(_ uri: String) {
        if selectedCandidateIDs.contains(uri) {
            selectedCandidateIDs.remove(uri)
        } else {
            selectedCandidateIDs.insert(uri)
        }
    }

    // MARK: - 导入（复用 ImportService 链路，由 importExecutor 闭包注入）

    /// 候选页「确认导入」入口：把已确认候选写入档案 + 强制归属到刚创建的宠物。
    func importConfirmedCandidates() {
        guard !isImporting, !selectedCandidateIDs.isEmpty else { return }
        // Set 迭代顺序随进程哈希种子随机——按候选列表顺序过滤选中项，
        // 保证导入顺序与候选页展示一致（确定性，避免顺序敏感断言 flaky）。
        let identifiers = candidateURIs.filter { selectedCandidateIDs.contains($0) }
        isImporting = true
        importPercent = 0
        step = .importing
        importTask = Task { [weak self] in
            guard let self else { return }
            if let executor = self.importExecutor {
                let count = await executor(identifiers, self.createdPetID) { pct in
                    self.importPercent = pct
                }
                self.importedCount = count
            } else {
                // 降级：无导入执行器（测试/无文件系统依赖环境），不执行真实导入
                self.importedCount = 0
            }
            self.importPercent = 1
            self.isImporting = false
            self.step = .success
            self.importTask = nil
        }
    }

    // MARK: - 完成引导

    /// success 页「开启生命档案」入口（完成引导）。
    func finishAfterImport() {
        finish()
    }

    /// 完成引导：触发回调（MiLensApp 切换到主界面）。
    func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        // 代次递增：扫描任务即使随后退出也不得再回写状态（防止覆盖完成态）
        scanGeneration += 1
        scanTask?.cancel()
        importTask?.cancel()
        onFinish()
    }
}
