//  HomeView —— 编辑式首页（对照 Figma「01·首页」#319:1026）。
//
//  出血 Hero 大图 + 暗部文楷大标题 + 宠物身份条 + 即将到来的日子区块。
//  HomeViewModel（@Observable）驱动：选片、问候、回忆和纪念日倒计时。
//  分区视图（Hero/日子/回忆行/空态/年度回看/备份横幅）见 HomeSections.swift。

import SwiftUI
import MiLensKit

struct HomeView: View {
    @Environment(\.viewModelFactory) private var factory
    @State private var viewModel: HomeViewModel?
    /// 跨 Tab 请求进入设置页备份导出（与 RootTabView/SettingsView 共享）
    @AppStorage("backupExportRequested") private var backupExportRequested = false
    /// 跨 Tab 请求进入相册扫描流程（铃铛确认窗/选择菜单/推送 tap 共用）
    @AppStorage("newPhotoScanRequested") private var newPhotoScanRequested = false
    /// 铃铛晃动模式（设置页配置，四选一）
    @AppStorage("bellShakeMode") private var bellShakeModeRaw = BellShakeLogic.ShakeMode.all.rawValue

    /// 铃铛确认窗/选择菜单/回忆中心 push 状态
    @State private var showNewPhotoConfirm = false
    @State private var showBellChoiceMenu = false
    @State private var pushReminders = false

    private var bellShakeMode: BellShakeLogic.ShakeMode {
        BellShakeLogic.ShakeMode(rawValue: bellShakeModeRaw) ?? .all
    }

    /// 铃铛触发原因（经开关过滤后的最终状态）
    private var bellTriggerReason: BellShakeLogic.TriggerReason {
        guard let viewModel else { return .none }
        return BellShakeLogic.resolveReason(
            hasAnniversary: viewModel.hasTodayContent,
            hasNewPhoto: viewModel.hasNewPhotoReminder,
            mode: bellShakeMode)
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView()
                    .tint(Color.milensActionPrimary)
            }
        }
        .background(Color.milensBackground)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $pushReminders) {
            MemoryRemindersView()
        }
        // 新照片确认窗（仅 .newPhoto 触发）
        .alert(
            confirmAlertTitle,
            isPresented: $showNewPhotoConfirm
        ) {
            Button(String(localized: "bell.confirm.confirm")) {
                newPhotoScanRequested = true
            }
            Button(String(localized: "bell.confirm.cancel"), role: .cancel) {}
        } message: {
            Text(confirmAlertMessage)
        }
        // 选择菜单（仅 .both 触发）
        .confirmationDialog(
            String(localized: "bell.menu.title"),
            isPresented: $showBellChoiceMenu,
            titleVisibility: .visible
        ) {
            Button(String(localized: "bell.menu.memories")) {
                pushReminders = true
            }
            Button(String(localized: "bell.menu.newPhoto")) {
                newPhotoScanRequested = true
            }
            Button(String(localized: "bell.confirm.cancel"), role: .cancel) {}
        }
        .onAppear {
            guard viewModel == nil else { return }
            let model = factory.makeHomeViewModel()
            model.load()
            viewModel = model
        }
        .task {
            // load 后异步刷新新照片提醒（不阻塞首页主加载）
            await viewModel?.refreshNewPhotoReminder()
        }
    }

    // MARK: - 确认窗文案（按 ReminderKind 区分）

    private var confirmAlertTitle: String {
        guard let viewModel else { return "" }
        switch viewModel.newPhotoReminderKind {
        case .staleInput:
            return String(localized: "bell.confirm.title.stale")
        default:
            return String(localized: "bell.confirm.title.new")
        }
    }

    private var confirmAlertMessage: String {
        guard let viewModel else { return "" }
        switch viewModel.newPhotoReminderKind {
        case .staleInput:
            return String(localized: "bell.confirm.body.stale")
        default:
            return String(localized: "bell.confirm.body.new")
        }
    }

    // MARK: - 铃铛点击分流

    /// 按触发原因执行不同的点击行为。
    /// .none/.anniversary → 进回忆提醒中心；.newPhoto → 弹确认窗；.both → 弹选择菜单。
    private func handleBellTap() {
        switch bellTriggerReason {
        case .none, .anniversary:
            pushReminders = true
        case .newPhoto:
            showNewPhotoConfirm = true
        case .both:
            showBellChoiceMenu = true
        }
    }

    @ViewBuilder
    private func content(_ model: HomeViewModel) -> some View {
        if model.isLoading {
            ProgressView()
                .tint(Color.milensActionPrimary)
        } else if let error = model.loadError {
            HomeRecoverableState(message: error) { model.load() }
        } else if model.photos.isEmpty {
            HomeEmptyState()
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero 区
                    if let photo = model.heroPhoto {
                        NavigationLink(value: Route.photoView(photoID: photo.id)) {
                            HomeHero(
                                photo: photo,
                                model: model,
                                bellTriggerReason: bellTriggerReason,
                                onBellTap: { handleBellTap() }
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "a11y.home.openPhoto \(model.heroCaption)"))
                    }

                    // 备份提醒横幅（数据量达标且久未备份时展示）
                    if model.shouldShowBackupBanner {
                        BackupReminderBanner(photoCount: model.photoTotalCount) {
                            backupExportRequested = true
                        } onClose: {
                            model.dismissBackupBanner()
                        }
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.lg)
                    }

                    // 即将到来的日子
                    if let upcoming = model.upcomingDay {
                        UpcomingDaySection(upcoming: upcoming)
                            .padding(.horizontal, Spacing.pagePad)
                            .padding(.top, Spacing.lg)
                    }

                    // 历史回忆（保留原有编辑式回忆行）
                    if let memory = model.memoryItems.first {
                        NavigationLink(value: Route.photoView(photoID: memory.photo.id)) {
                            MemoryEditorialRow(item: memory)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.xxl)
                    }

                    // 年度回看入口（情感触点系统 Stage 3）
                    if !model.photos.isEmpty {
                        NavigationLink(value: Route.recap(year: nil)) {
                            YearlyRecapEntry()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.lg)
                    }
                }
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
