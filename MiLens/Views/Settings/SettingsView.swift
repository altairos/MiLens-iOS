//  SettingsView —— 「我的」（Tab 4，UI Rework 4.4 / PLAN.md P5）。
//
//  分组顺序遵循 UI-DESIGN.md §6.9：Pro 状态 → 数据与隐私 → 通知 → 外观 → 支持 → 关于。
//  - Pro 订阅入口：未解锁 → 付费墙 sheet（4.5）；已解锁 → 状态 + App Store 订阅管理链接。
//  - 外观：跟随系统/浅色/深色，@AppStorage 持久化，MiLensApp 根应用 preferredColorScheme。
//  - 纪念提醒：授权放开关路径，拒绝回弹（沿用 P1 NotifyService 语义，编排入 SettingsViewModel）。
//  - 决策全部下沉 SettingsLogic / SettingsViewModel；文案全部 String(localized:)。
//
//  无账号系统：不显示头像/昵称/「登录」（UI-DESIGN.md §6.9）。

import SwiftUI

struct SettingsView: View {
    @AppStorage("reminderNotificationsEnabled") private var remindersEnabled = false
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue
    @Environment(\.notifyService) private var notifyService
    @Environment(\.proEntitlement) private var entitlement

    @State private var viewModel: SettingsViewModel?
    @State private var showPaywall = false

    var body: some View {
        Group {
            if let viewModel {
                settingsList(viewModel)
            } else {
                ProgressView()
                    .tint(.milensPrimary)
            }
        }
        .background(Color.milensBackground)
        .onAppear {
            guard viewModel == nil else { return }
            viewModel = SettingsViewModel(notifyService: notifyService)
        }
        .task {
            // 权益校准：权益流由应用级 ProEntitlementStore 常驻消费，页面只读状态
            await entitlement.refresh()
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
        }
    }

    // MARK: - 分组列表

    private func settingsList(_ model: SettingsViewModel) -> some View {
        List {
            proSection
            privacySection
            notificationSection(model)
            appearanceSection
            supportSection
            aboutSection(model)
        }
        .scrollContentBackground(.hidden)
        .background(Color.milensBackground)
        .frame(maxWidth: 620)   // 设置表单最大可读宽度（UI-DESIGN.md §5.1）
        .frame(maxWidth: .infinity)
        .alert(
            String(localized: "settings.notifications.denied.title"),
            isPresented: Binding(
                get: { model.showReminderDeniedAlert },
                set: { model.showReminderDeniedAlert = $0 }
            )
        ) {
            Button(String(localized: "settings.notifications.denied.ok"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.notifications.denied.message"))
        }
    }

    // MARK: Pro 状态

    private var proSection: some View {
        Section {
            if entitlement.isPro {
                Label {
                    Text(String(localized: "settings.pro.active.title"))
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.milensSuccess)
                }
                if let url = URL(string: SettingsLogic.Links.manageSubscriptions) {
                    Link(destination: url) {
                        Label(String(localized: "settings.pro.manage"), systemImage: "arrow.up.right.square")
                    }
                }
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "seal")
                            .font(.system(size: Sizing.iconMd))
                            .foregroundStyle(Color.milensActionPrimary)
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(String(localized: "settings.pro.unlock.title"))
                                .font(.bodyPrimary)
                                .foregroundStyle(Color.milensTextPrimary)
                            Text(String(localized: "settings.pro.unlock.subtitle"))
                                .font(.caption)
                                .foregroundStyle(Color.milensTextSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: Sizing.iconSm, weight: .semibold))
                            .foregroundStyle(Color.milensTextTertiary)
                    }
                    .frame(minHeight: Sizing.touchTarget)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(String(localized: "settings.section.pro"))
        }
    }

    // MARK: 数据与隐私

    private var privacySection: some View {
        Section {
            NavigationLink {
                PrivacyInfoView()
            } label: {
                Label(String(localized: "settings.privacy.local"), systemImage: "lock.shield")
            }
            if let url = URL(string: SettingsLogic.Links.privacyPolicy) {
                Link(destination: url) {
                    Label(String(localized: "settings.privacy.policy"), systemImage: "doc.text")
                }
            }
        } header: {
            Text(String(localized: "settings.section.privacy"))
        }
    }

    // MARK: 通知

    private func notificationSection(_ model: SettingsViewModel) -> some View {
        Section {
            Toggle(String(localized: "settings.notifications.reminders"), isOn: $remindersEnabled)
                .onChange(of: remindersEnabled) { _, enabled in
                    Task {
                        let kept = await model.handleReminderToggle(enabled: enabled)
                        if kept != enabled { remindersEnabled = kept }
                    }
                }
        } header: {
            Text(String(localized: "settings.section.notifications"))
        } footer: {
            Text(String(localized: "settings.notifications.footer"))
        }
    }

    // MARK: 外观

    private var appearanceSection: some View {
        Section {
            Picker(selection: $appearanceRaw) {
                ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                    Text(appearanceLabel(for: mode)).tag(mode.rawValue)
                }
            } label: {
                Text(String(localized: "settings.appearance.title"))
            }
        } header: {
            Text(String(localized: "settings.section.appearance"))
        }
    }

    private func appearanceLabel(for mode: AppearanceMode) -> String {
        switch mode {
        case .system: return String(localized: "settings.appearance.system")
        case .light: return String(localized: "settings.appearance.light")
        case .dark: return String(localized: "settings.appearance.dark")
        }
    }

    // MARK: 支持

    private var supportSection: some View {
        Section {
            NavigationLink {
                HelpView()
            } label: {
                Label(String(localized: "settings.support.help"), systemImage: "questionmark.circle")
            }
        } header: {
            Text(String(localized: "settings.section.support"))
        }
    }

    // MARK: 关于

    private func aboutSection(_ model: SettingsViewModel) -> some View {
        Section {
            NavigationLink {
                AboutView(marketing: model.versionMarketing, build: model.versionBuild)
            } label: {
                Label(String(localized: "settings.about.entry"), systemImage: "info.circle")
            }
            HStack {
                Text(String(localized: "settings.about.version"))
                Spacer()
                Text("\(model.versionMarketing) (\(model.versionBuild))")
                    .foregroundStyle(Color.milensTextSecondary)
            }
        } header: {
            Text(String(localized: "settings.section.about"))
        }
    }
}
