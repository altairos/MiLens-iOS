//  组合根（DESIGN.md §4.1）。
//  应用级依赖（ModelContainer / Repository / 平台适配器）经 AppDependencies 构造并注入。
//  启动可靠性（P1）：ModelContainer 创建失败时进入 DatabaseRecoveryView——
//  可重试 / 导出诊断 / 重建本地数据（不 crash）。
//  首次启动引导（Onboarding）在此编排：完成引导后置位 hasCompletedOnboarding，
//  @AppStorage 监听 UserDefaults 变化自动切换到主界面（RootTabView）。
//  对应源端 EntryAbility（HarmonyOS UIAbility 生命周期入口）+ AppServiceLocator DI。

import SwiftUI
import SwiftData

@main
struct MiLensApp: App {
    /// 首次启动引导是否已完成（@AppStorage 自动监听 UserDefaults 变化）
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    /// 外观模式（Settings 页设置：跟随系统/浅色/深色；未知值回退系统）
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue

    /// 启动状态：依赖构造成功后持有（失败为 nil → 展示恢复界面）
    @State private var dependencies: AppDependencies?
    /// 启动失败的错误描述（展示在恢复界面；重试/重建后清除）
    @State private var startupError: String?

    /// 测试环境（XCTest host 加载 @main App）跳过引导直接进主界面
    private let isTesting: Bool

    /// 外观模式 → ColorScheme（.system 映射为 nil 跟随系统）
    private var preferredScheme: ColorScheme? {
        switch AppearanceMode.parse(appearanceRaw) {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    init() {
        // 测试环境（XCTest host 加载 @main App）切 in-memory，避免模拟器
        // Application Support 目录不可写导致 CoreData 存储错误噪音。
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.isTesting = isTesting

        // 构造依赖；失败不 crash——进入 DatabaseRecoveryView（P1 启动可靠性）。
        do {
            _dependencies = State(initialValue: try AppDependencies.make(isTesting: isTesting))
        } catch {
            _startupError = State(initialValue: String(describing: error))
        }
    }

    var body: some Scene {
        WindowGroup {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let dependencies {
            mainContent(dependencies)
                .modelContainer(dependencies.container)
                .environment(\.petRepository, dependencies.petRepo)
                .environment(\.photoRepository, dependencies.photoRepo)
                .environment(\.visionService, dependencies.vision)
                .environment(\.clipInferenceService, dependencies.clipService)
                .environment(\.poseInferenceService, dependencies.poseService)
                .environment(\.photoLibraryAccess, dependencies.photoLibrary)
                .environment(\.fileStorage, dependencies.fileStorage)
                .environment(\.scanCursorStore, dependencies.scanCursorStore)
                .environment(\.mediaLifecycleService, dependencies.mediaLifecycle)
                .environment(\.notifyService, dependencies.notifyService)
                .environment(\.storeService, dependencies.storeService)
                .environment(\.proEntitlement, dependencies.proEntitlement)
                .environment(\.viewModelFactory, dependencies.viewModelFactory)
                .preferredColorScheme(preferredScheme)
                .task {
                    // 启动孤儿审计：清理上一次崩溃/回滚残留的媒体文件（仅生产环境）。
                    // L3：延迟到首屏稳定后执行，不阻塞启动关键路径；IO 在 service 内部降级到 utility 优先级。
                    guard !isTesting else { return }
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    await dependencies.mediaLifecycle.auditOrphans()
                }
        } else {
            DatabaseRecoveryView(
                errorDescription: startupError ?? "未知错误",
                onRetry: retryLaunch,
                onRebuild: rebuildLocalData
            )
        }
    }

    private func mainContent(_ dependencies: AppDependencies) -> some View {
        Group {
            if isTesting || hasCompletedOnboarding {
                RootTabView()
            } else {
                OnboardingView(viewModel: dependencies.onboardingViewModel)
            }
        }
    }

    // MARK: - 启动恢复

    /// 重试：重新构造依赖（容器损坏可能是瞬态的）。
    private func retryLaunch() {
        do {
            dependencies = try AppDependencies.make(isTesting: isTesting)
            startupError = nil
        } catch {
            startupError = String(describing: error)
        }
    }

    /// 重建本地数据：销毁持久化存储后重新构造（仅清除 MiLens 记录，不动系统相册原图）。
    private func rebuildLocalData() {
        do {
            try AppDependencies.destroyPersistentStore()
            dependencies = try AppDependencies.make(isTesting: isTesting)
            startupError = nil
        } catch {
            startupError = String(describing: error)
        }
    }
}
