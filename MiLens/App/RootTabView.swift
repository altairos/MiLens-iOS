//  RootTabView —— 应用主导航根视图。
//  - 4 Tab（首页/宠物/创作/我的），选中项持久化到 UserDefaults（对应源端 @StorageLink('mainTabIndex')）。
//  - scenePhase 生命周期编排在此（对应源端 EntryAbility，P1.2+ 接入资源清理/任务取消）。

import SwiftUI

struct RootTabView: View {
    @AppStorage("selectedTab") private var selectedTabRaw: Int = AppTab.home.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.notifyService) private var notifyService

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
        .tint(.milensPrimary)
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhase(newPhase)
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
        switch route {
        case .gallery:
            GalleryView()
        case .photoView(let photoID):
            PhotoViewView(photoID: photoID)
        case .petProfile(let petID):
            PetProfileView(petID: petID)
        case .beadPattern:
            // P4 实现
            PlaceholderTabView(systemImage: "square.grid.3x3.fill",
                               title: "拼豆图纸", subtitle: "P4 待实现")
        case .petEdit(let petID):
            PetEditView(petID: petID)
        case .timeline:
            TimelineView()
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // 纪念提醒每日检查（对应源端 EntryAbility onPageShow 的 scheduleDailyEventCheck）
            if let notifyService {
                Task { await notifyService.runDailyCheck() }
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
