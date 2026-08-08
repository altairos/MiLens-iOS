//  组合根（DESIGN.md §4.1）。
//  应用级依赖（ModelContainer / Repository / 平台适配器）在此构造并注入。
//  首次启动引导（Onboarding）在此编排：完成引导后置位 hasCompletedOnboarding，
//  @AppStorage 监听 UserDefaults 变化自动切换到主界面（RootTabView）。
//  对应源端 EntryAbility（HarmonyOS UIAbility 生命周期入口）+ AppServiceLocator DI。

import SwiftUI
import SwiftData

@main
struct MiLensApp: App {
    /// 首次启动引导是否已完成（@AppStorage 自动监听 UserDefaults 变化）
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let container: ModelContainer
    private let petRepo: any PetRepositoryProtocol
    private let photoRepo: any PhotoRepositoryProtocol
    private let vision: any VisionService
    private let clipService: ClipInferenceService?
    private let photoLibrary: any PhotoLibraryAccess
    private let onboardingViewModel: OnboardingViewModel
    /// 纪念提醒服务（测试环境不注入——避免测试进程触发通知授权）
    private let notifyService: NotifyService?
    /// 测试环境（XCTest host 加载 @main App）跳过引导直接进主界面
    private let isTesting: Bool

    init() {
        // V1.0 干净 schema——迁移计划为空。创建失败无恢复意义（无数据库 app 不可用）。
        // 测试环境（XCTest host 加载 @main App）切 in-memory，避免模拟器
        // Application Support 目录不可写导致 CoreData 存储错误噪音。
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.isTesting = isTesting
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = isTesting
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration()
        let container = try! ModelContainer(
            for: schema,
            migrationPlan: MiLensMigrationPlan.self,
            configurations: [config]
        )
        self.container = container
        self.petRepo = SwiftDataPetRepository(context: container.mainContext)
        self.photoRepo = SwiftDataPhotoRepository(context: container.mainContext)
        // 平台适配层：注入真实 VisionService（VNClassifyImageRequest 宠物预筛 + VNGenerateForegroundInstanceMask 分割）。
        // ClipInferenceService 在测试环境跳过（避免加载 ~80MB CLIP 模型拖慢单测）。
        self.vision = IOSVisionService()
        self.clipService = isTesting ? nil : ClipInferenceService.create()
        // 照片库适配器：真实 Photos 框架实现（授权 + 流式遍历）。
        self.photoLibrary = IOSPhotoLibraryAccess()
        // 纪念提醒：每日检查（纪念日 + 时光机）。测试环境不构造，避免触发通知授权。
        self.notifyService = isTesting ? nil : NotifyService(
            photoRepo: self.photoRepo,
            petRepo: self.petRepo,
            poster: IOSNotificationCenter()
        )
        // 首次启动引导状态机（onFinish 置位持久化标记，触发 @AppStorage 切换主界面）。
        self.onboardingViewModel = OnboardingViewModel(
            photoRepo: self.photoRepo,
            petRepo: self.petRepo,
            photoLibrary: self.photoLibrary,
            vision: self.vision,
            onFinish: {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isTesting || hasCompletedOnboarding {
                    RootTabView()
                } else {
                    OnboardingView(viewModel: onboardingViewModel)
                }
            }
            .modelContainer(container)
            .environment(\.petRepository, petRepo)
            .environment(\.photoRepository, photoRepo)
            .environment(\.visionService, vision)
            .environment(\.clipInferenceService, clipService)
            .environment(\.photoLibraryAccess, photoLibrary)
            .environment(\.notifyService, notifyService)
        }
    }
}
