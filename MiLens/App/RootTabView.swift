//  RootTabView —— 应用主导航根视图。
//  - 4 Tab（首页/宠物/创作/我的），选中项持久化到 UserDefaults（对应源端 @StorageLink('mainTabIndex')）。
//  - scenePhase 生命周期编排在此（对应源端 EntryAbility，P1.2+ 接入资源清理/任务取消）。
//  - 首次出现时校准 Pro 权益（refresh）：Transaction.updates 不保证冷启动推送当前权益，
//    避免已购用户首次进入创作/拼豆入口时被误导向付费墙（P2 启动时序修复）。

import SwiftUI

struct RootTabView: View {
    @AppStorage("selectedTab") private var selectedTabRaw: Int = AppTab.home.rawValue
    @AppStorage("reminderNotificationsEnabled") private var remindersEnabled = false
    /// 上次已知 Pro 状态（用于识别冷启动/前台降级：lastKnownIsPro && !currentIsPro）。
    @AppStorage("lastKnownIsPro") private var lastKnownIsPro = false
    /// 当前降级周期是否已弹提示（防重复打扰；续费后重置）。
    @AppStorage("quotaDowngradePromptPending") private var quotaDowngradePromptPending = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.notifyService) private var notifyService
    @Environment(\.proEntitlement) private var entitlement
    @Environment(\.photoRepository) private var photoRepo

    /// Widget 深链回调路由：外部绑定，新值到达时触发导航。
    @Binding var pendingWidgetRoute: Route?

    init(pendingWidgetRoute: Binding<Route?> = .constant(nil)) {
        self._pendingWidgetRoute = pendingWidgetRoute
    }

    /// 首页 Tab 的导航路径（Widget 深链统一从首页 push）。
    @State private var homePath = NavigationPath()
    /// 降级提示 sheet
    @State private var showDowngradeSheet = false
    /// 付费墙 sheet（跨视图通知 .presentPaywallRequested 触发）
    @State private var showPaywall = false
    /// 跨 Tab 请求进入 Gallery 存储管理模式（与 SettingsView/GalleryView 共享）
    @AppStorage("storageManageRequested") private var storageManageRequested = false
    /// 跨 Tab 请求进入设置页备份导出（首页横幅 / 通知 tap 与 SettingsView 共享）
    @AppStorage("backupExportRequested") private var backupExportRequested = false
    /// 跨 Tab 请求进入相册扫描流程（铃铛确认窗 / 选择菜单 / 通知 tap 共用）
    @AppStorage("newPhotoScanRequested") private var newPhotoScanRequested = false

    var body: some View {
        TabView(selection: selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                NavigationStack(path: tab == .home ? $homePath : .constant(NavigationPath())) {
                    tabView(tab)
                        .navigationTitle(tab.title)
                        .navigationBarTitleDisplayMode(.large)
                        .navigationDestination(for: Route.self) { route in
                            routeDestination(route)
                        }
                }
                .tag(tab)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MemoryOrbitTabBar(selection: selectedTab)
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhase(newPhase)
        }
        .onChange(of: pendingWidgetRoute) { _, newRoute in
            handleWidgetRoute(newRoute)
        }
        .onChange(of: entitlement.isPro) { _, isPro in
            evaluateDowngradePrompt(currentIsPro: isPro)
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentPaywallRequested)) { _ in
            showPaywall = true
        }
        .onChange(of: storageManageRequested) { _, requested in
            if requested {
                selectedTabRaw = AppTab.home.rawValue
                homePath.append(Route.gallery)
            }
        }
        .onChange(of: backupExportRequested) { _, requested in
            // 首页备份横幅 / 备份提醒通知 tap → 切到「我的」Tab（SettingsView 消费并触发导出）
            if requested {
                selectedTabRaw = AppTab.settings.rawValue
            }
        }
        .onChange(of: newPhotoScanRequested) { _, requested in
            // 铃铛确认窗 / 选择菜单 / 新照片通知 tap → 切到首页 Tab 并 push 相册页
            // （GalleryView onAppear/onChange 消费 newPhotoScanRequested 触发扫描流程）
            if requested {
                selectedTabRaw = AppTab.home.rawValue
                homePath.append(Route.gallery)
            }
        }
        .task {
            // 启动权益校准：显式查询 currentProStatus（Transaction.updates 冷启动不保证推送），
            // 保证首次进入任何 Tab（含创作门控与拼豆路由）前权益已恢复真实状态。
            await entitlement.refresh()
            // 冷启动降级检测（App 非活跃期订阅过期后首次启动）
            evaluateDowngradePrompt(currentIsPro: entitlement.isPro)
        }
        .sheet(isPresented: $showDowngradeSheet) {
            QuotaDowngradeSheet(showManageCTA: true)
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
        }
    }

    private var selectedTab: Binding<AppTab> {
        Binding(
            get: { AppTab(rawValue: selectedTabRaw) ?? .home },
            set: { selectedTabRaw = $0.rawValue }
        )
    }

    @ViewBuilder
    private func tabView(_ tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .pets: PetsView()
        case .create: CreateView()
        case .settings: SettingsView()
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: Route) -> some View {
        if route.requiresPro && !entitlement.isPro {
            PaywallView()
        } else {
            switch route {
            case .gallery: GalleryView()
            case .photoView(let photoID): PhotoViewView(photoID: photoID)
            case .editor(let photoID): EditorView(photoID: photoID)
            case .petProfile(let petID): PetProfileView(petID: petID)
            case .beadPhotoPicker: BeadPhotoPickerView()
            case .beadPattern(let photoID): BeadPatternView(photoID: photoID)
            case .petCardPhotoPicker: PetCardPhotoPickerView()
            case .petCard(let photoID, let kind): PetCardView(photoID: photoID, kind: kind)
            case .petEdit(let petID): PetEditView(petID: petID)
            case .timeline: TimelineView()
            case .growthComparePhotoPicker: GrowthComparePhotoPickerView()
            case .growthCompare(let earlyPhotoID, let latePhotoID, let petID):
                GrowthCompareView(earlyPhotoID: earlyPhotoID, latePhotoID: latePhotoID, petID: petID)
            case .businessCardPicker: BusinessCardPickerView()
            case .businessCard(let petID): BusinessCardView(petID: petID)
            case .redPacketTemplatePicker: RedPacketTemplatePickerView()
            case .redPacketPhotoPicker(let templateID):
                RedPacketPhotoPickerView(templateID: templateID)
            case .redPacketWorkshop(let templateID, let photoID, let petID):
                RedPacketWorkshopView(templateID: templateID, photoID: photoID, petID: petID)
            case .redPacketExport(let draftID):
                RedPacketExportView(draftID: draftID)
            case .redPacketUploadGuide(let photoID, let petID):
                RedPacketUploadGuideView(photoID: photoID, petID: petID)
            case .recap(let year):
                RecapView(year: year)
            case .memoryReminders:
                MemoryRemindersView()
            }
        }
    }

    /// 处理 Widget 深链回调：切换到首页 Tab 并 push Route。
    private func handleWidgetRoute(_ route: Route?) {
        guard let route else { return }
        // 切换到首页 Tab（Widget 深链统一从首页 push）
        selectedTabRaw = AppTab.home.rawValue
        // push 目标路由
        homePath.append(route)
        // 清除 pending 状态（避免重复触发）
        pendingWidgetRoute = nil
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // 纪念提醒：仅开关开启时幂等重调度（刷新当日时光机内容）；不自动请求授权
            if let notifyService, remindersEnabled {
                Task { await notifyService.rescheduleAllReminders() }
            }
        case .inactive, .background:
            break
        @unknown default:
            break
        }
    }

    // MARK: - 配额降级检测

    /// 评估是否需要弹出降级提示。在启动 refresh 后和 isPro 变更时调用。
    private func evaluateDowngradePrompt(currentIsPro: Bool) {
        let photoCount = (try? photoRepo.countAllPhotos()) ?? 0
        let shouldPrompt = QuotaGatingLogic.shouldPromptDowngrade(
            lastKnownIsPro: lastKnownIsPro,
            currentIsPro: currentIsPro,
            photoCount: photoCount,
            promptPending: quotaDowngradePromptPending
        )
        if shouldPrompt {
            quotaDowngradePromptPending = true
            showDowngradeSheet = true
        }
        // 续费后重置提示标记，为下一次降级周期准备
        if QuotaGatingLogic.promptShouldReset(isPro: currentIsPro) {
            quotaDowngradePromptPending = false
        }
        // 更新已知状态
        lastKnownIsPro = currentIsPro
    }
}

#Preview {
    RootTabView()
}
