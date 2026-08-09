//  SettingsView —— 「我的」（Tab 4）。
//
//  使用轻量分组表面替代默认 Form/List 的厚重层级；顺序仍保持：
//  Pro → 数据与隐私 → 通知 → 外观 → 支持 → 关于。

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
                settingsContent(viewModel)
            } else {
                ProgressView()
                    .tint(Color.milensActionPrimary)
            }
        }
        .background(Color.milensBackground)
        .onAppear {
            guard viewModel == nil else { return }
            viewModel = SettingsViewModel(notifyService: notifyService)
        }
        .task {
            await entitlement.refresh()
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
        }
    }

    private func settingsContent(_ model: SettingsViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ArchiveMarker(label: "由你掌握")
                    .padding(.top, Spacing.sm)

                Text("把它的一生，安静地留在这里。")
                    .font(.displayMedium)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xxl)

                settingsSection(title: String(localized: "settings.section.pro")) {
                    proContent
                }
                settingsSection(title: String(localized: "settings.section.privacy")) {
                    privacyContent
                }
                settingsSection(title: String(localized: "settings.section.notifications")) {
                    notificationContent(model)
                }
                settingsSection(title: String(localized: "settings.section.appearance")) {
                    appearanceContent
                }
                settingsSection(title: String(localized: "settings.section.support")) {
                    supportContent
                }
                settingsSection(title: String(localized: "settings.section.about")) {
                    aboutContent(model)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.pagePad)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
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

    private var proContent: some View {
        VStack(spacing: 0) {
            if entitlement.isPro {
                settingsLabelRow(
                    icon: "checkmark.seal.fill",
                    title: String(localized: "settings.pro.active.title"),
                    tint: .milensSuccess
                )
                if let url = URL(string: SettingsLogic.Links.manageSubscriptions) {
                    ArchiveDivider().padding(.leading, 56)
                    Link(destination: url) {
                        settingsLabelRow(
                            icon: "arrow.up.right.square",
                            title: String(localized: "settings.pro.manage"),
                            tint: .milensTextSecondary
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "seal")
                            .font(.system(size: Sizing.iconMd))
                            .foregroundStyle(Color.milensActionPrimary)
                            .frame(width: Sizing.iconLg)
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(String(localized: "settings.pro.unlock.title"))
                                .font(.bodyPrimary.weight(.semibold))
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
                    .frame(minHeight: 64)
                }
                .buttonStyle(.plain)
            }
            proFeatureRows
        }
    }

    private var proFeatureRows: some View {
        VStack(spacing: 0) {
            ArchiveDivider().padding(.leading, 56)
            ForEach(ProFeature.allCases) { feature in
                settingsLabelRow(
                    icon: feature.systemImage,
                    title: String(localized: String.LocalizationValue(feature.localizationKey)),
                    tint: .milensTextSecondary
                )
                if feature != ProFeature.allCases.last {
                    ArchiveDivider().padding(.leading, 56)
                }
            }
            ArchiveDivider().padding(.leading, 56)
            settingsLabelRow(
                icon: "person.2",
                title: String(localized: "paywall.benefit.family"),
                tint: .milensTextSecondary
            )
        }
    }

    private var privacyContent: some View {
        VStack(spacing: 0) {
            NavigationLink {
                PrivacyInfoView()
            } label: {
                settingsLabelRow(
                    icon: "lock.shield",
                    title: String(localized: "settings.privacy.local")
                )
            }
            .buttonStyle(.plain)

            if let url = URL(string: SettingsLogic.Links.privacyPolicy) {
                ArchiveDivider().padding(.leading, 56)
                Link(destination: url) {
                    settingsLabelRow(
                        icon: "doc.text",
                        title: String(localized: "settings.privacy.policy")
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func notificationContent(_ model: SettingsViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "bell")
                    .font(.system(size: Sizing.iconMd))
                    .foregroundStyle(Color.milensTextSecondary)
                    .frame(width: Sizing.iconLg)
                Toggle(String(localized: "settings.notifications.reminders"), isOn: $remindersEnabled)
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextPrimary)
                    .onChange(of: remindersEnabled) { _, enabled in
                        Task {
                            let kept = await model.handleReminderToggle(enabled: enabled)
                            if kept != enabled { remindersEnabled = kept }
                        }
                    }
            }
            Text(String(localized: "settings.notifications.footer"))
                .font(.caption)
                .foregroundStyle(Color.milensTextSecondary)
                .padding(.leading, 44)
        }
        .padding(.vertical, Spacing.md)
    }

    private var appearanceContent: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: Sizing.iconMd))
                .foregroundStyle(Color.milensTextSecondary)
                .frame(width: Sizing.iconLg)
            Text(String(localized: "settings.appearance.title"))
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextPrimary)
            Spacer(minLength: Spacing.sm)
            Picker(String(localized: "settings.appearance.title"), selection: $appearanceRaw) {
                ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                    Text(appearanceLabel(for: mode)).tag(mode.rawValue)
                }
            }
            .labelsHidden()
            .tint(Color.milensActionPrimary)
        }
        .frame(minHeight: Sizing.touchTarget)
    }

    private var supportContent: some View {
        NavigationLink {
            HelpView()
        } label: {
            settingsLabelRow(
                icon: "questionmark.circle",
                title: String(localized: "settings.support.help")
            )
        }
        .buttonStyle(.plain)
    }

    private func aboutContent(_ model: SettingsViewModel) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                AboutView(marketing: model.versionMarketing, build: model.versionBuild)
            } label: {
                settingsLabelRow(
                    icon: "info.circle",
                    title: String(localized: "settings.about.entry")
                )
            }
            .buttonStyle(.plain)

            ArchiveDivider().padding(.leading, 56)
            HStack(spacing: Spacing.md) {
                Image(systemName: "number")
                    .font(.system(size: Sizing.iconMd))
                    .foregroundStyle(Color.milensTextSecondary)
                    .frame(width: Sizing.iconLg)
                Text(String(localized: "settings.about.version"))
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                Text("\(model.versionMarketing) (\(model.versionBuild))")
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
            }
            .frame(minHeight: Sizing.touchTarget)
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.milensTextSecondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, Spacing.lg)
            .background(Color.milensCard)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .stroke(Color.milensBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        }
        .padding(.bottom, Spacing.xxl)
    }

    private func settingsLabelRow(
        icon: String,
        title: String,
        tint: Color = .milensTextSecondary
    ) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: Sizing.iconMd))
                .foregroundStyle(tint)
                .frame(width: Sizing.iconLg)
            Text(title)
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: Sizing.iconSm, weight: .semibold))
                .foregroundStyle(Color.milensTextTertiary)
        }
        .frame(minHeight: Sizing.touchTarget)
        .contentShape(Rectangle())
    }

    private func appearanceLabel(for mode: AppearanceMode) -> String {
        switch mode {
        case .system: return String(localized: "settings.appearance.system")
        case .light: return String(localized: "settings.appearance.light")
        case .dark: return String(localized: "settings.appearance.dark")
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
