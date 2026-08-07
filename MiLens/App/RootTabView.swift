//  RootTabView —— 应用主导航根视图。
//  - 4 Tab（首页/宠物/创作/我的），选中项持久化到 UserDefaults（对应源端 @StorageLink('mainTabIndex')）。
//  - scenePhase 生命周期编排在此（对应源端 EntryAbility，P1.2+ 接入资源清理/任务取消）。

import SwiftUI

struct RootTabView: View {
    @AppStorage("selectedTab") private var selectedTabRaw: Int = AppTab.home.rawValue
    @Environment(\.scenePhase) private var scenePhase

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

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active, .inactive, .background:
            break
        @unknown default:
            break
        }
    }
}

#Preview {
    RootTabView()
}
