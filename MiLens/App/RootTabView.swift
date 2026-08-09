//  RootTabView —— 应用主导航根视图。
//  - 4 Tab（首页/宠物/创作/我的），选中项持久化到 UserDefaults（对应源端 @StorageLink('mainTabIndex')）。
//  - scenePhase 生命周期编排在此（对应源端 EntryAbility，P1.2+ 接入资源清理/任务取消）。
//  - 首次出现时校准 Pro 权益（refresh）：Transaction.updates 不保证冷启动推送当前权益，
//    避免已购用户首次进入创作/拼豆入口时被误导向付费墙（P2 启动时序修复）。

import SwiftUI

struct RootTabView: View {
    @AppStorage("selectedTab") private var selectedTabRaw: Int = AppTab.home.rawValue
    @AppStorage("reminderNotificationsEnabled") private var remindersEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.notifyService) private var notifyService
    @Environment(\.proEntitlement) private var entitlement

    var body: some View {
        TabView(selection: Binding(
            get: { selectedTabRaw },
            set: { selectedTabRaw = $0 }
        )) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                NavigationStack {
                    tabView(tab)
                        .navigationTitle(tab.title)
                        .navigationBarTitleDisplayMode(.large)
                        .navigationDestination(for: Route.self) { route in
                            routeDestination(route)
                        }
                }
                .tabItem {
                    Label(tab.title, systemImage: tab.systemImage)
                }
                .tag(tab.rawValue)
            }
        }
        .tint(.milensActionPrimary)
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhase(newPhase)
        }
        .task {
            // 启动权益校准：显式查询 currentProStatus（Transaction.updates 冷启动不保证推送），
            // 保证首次进入任何 Tab（含创作门控与拼豆路由）前权益已恢复真实状态。
            await entitlement.refresh()
        }
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
            case .petCard(let photoID): PetCardView(photoID: photoID)
            case .petEdit(let petID): PetEditView(petID: petID)
            case .timeline: TimelineView()
            }
        }
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
}

#Preview {
    RootTabView()
}
