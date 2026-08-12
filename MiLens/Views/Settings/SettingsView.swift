//  SettingsView —— 「我的」（Tab 4）。
//
//  Ledger 账本式设计语言（对照 Figma「07·我的」#140:415）：
//  珊瑚竖线 rail + Fraunces 编号 + 虚线引导线 + 暖黑 Pro 卡 + 隐私徽章卡。
//  业务逻辑层（SettingsViewModel / SettingsLogic）零改动；所有数据绑定保留。

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("reminderNotificationsEnabled") private var remindersEnabled = false
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("photoBackupMode") private var photoBackupModeRaw = PhotoBackupMode.cloudOptimized.rawValue
    @Environment(\.notifyService) private var notifyService
    @Environment(\.proEntitlement) private var entitlement
    @Environment(\.backupService) private var backupService
    @Environment(\.fileStorage) private var fileStorage
    @Environment(\.openURL) private var openURL

    @State private var viewModel: SettingsViewModel?
    @State private var showPaywall = false
    @State private var backupVM: BackupViewModel?
    @State private var showRestoreImporter = false

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
            if viewModel == nil {
                let sandboxDir = URL.documentsDirectory
                    .appendingPathComponent(ScanConfig.sandboxDirName).path
                viewModel = SettingsViewModel(
                    notifyService: notifyService,
                    fileStorage: fileStorage,
                    sandboxDir: sandboxDir
                )
            }
            if backupVM == nil {
                backupVM = BackupViewModel(backupService: backupService)
            }
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
                // 标题区：对照 Figma #140:416/#140:418
                Text(String(localized: "settings.title"))
                    .font(.displayMedium)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.top, Spacing.lg)

                // 副标题：MiLens 用 Fraunces，其余系统字体（Text 拼接混合字体）
                proSubtitle
                    .padding(.top, Spacing.sm)

                // Pro 区
                proContent
                    .padding(.top, Spacing.xl)

                // 隐私与数据
                SettingsSectionLabel(title: String(localized: "settings.section.privacy"))
                    .padding(.top, Spacing.xxl)
                privacyContent

                // 偏好设置
                SettingsSectionLabel(title: String(localized: "settings.section.preferences"))
                    .padding(.top, Spacing.xxl)
                preferenceContent(model)

                // 支持与版本
                SettingsSectionLabel(title: String(localized: "settings.section.support"))
                    .padding(.top, Spacing.xxl)
                supportContent(model)

                // 页脚
                SettingsFooter()
                    .padding(.top, Spacing.xxl)
            }
            .frame(maxWidth: ReadingWidth.form, alignment: .leading)
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
        // 导出完成 → 弹出分享面板（用户选择保存到 Files/iCloud Drive/AirDrop）
        .sheet(isPresented: Binding(
            get: { if case .done = backupVM?.exportState { return true } else { return false } },
            set: { if !$0 { backupVM?.resetExport() } }
        )) {
            if case .done(let url) = backupVM?.exportState {
                BackupShareSheet(url: url)
            }
        }
        // 导出失败提示
        .alert(String(localized: "settings.backup.failed"),
               isPresented: Binding(
                   get: { if case .failed = backupVM?.exportState { return true } else { return false } },
                   set: { if !$0 { backupVM?.resetExport() } }
               )) {
            Button(String(localized: "settings.backup.ok"), role: .cancel) { backupVM?.resetExport() }
        } message: {
            if case .failed(let msg) = backupVM?.exportState { Text(msg) }
        }
        // 恢复文件选择器（选 .milensbackup）
        .fileImporter(
            isPresented: $showRestoreImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { Task { await backupVM?.importBackup(from: url) } }
            case .failure:
                break
            }
        }
        // 恢复完成 → 显示统计
        .alert(String(localized: "settings.backup.restoreComplete"),
               isPresented: Binding(
                   get: { if case .done = backupVM?.restoreState { return true } else { return false } },
                   set: { if !$0 { backupVM?.resetRestore() } }
               )) {
            Button(String(localized: "settings.backup.ok"), role: .cancel) { backupVM?.resetRestore() }
        } message: {
            if case .done(let result) = backupVM?.restoreState {
                Text(String(localized: "settings.backup.restoreSummary \(result.importedPets) \(result.importedPhotos) \(result.importedEvents) \(result.skipped)"))
            }
        }
        // 恢复失败提示
        .alert(String(localized: "settings.backup.failed"),
               isPresented: Binding(
                   get: { if case .failed = backupVM?.restoreState { return true } else { return false } },
                   set: { if !$0 { backupVM?.resetRestore() } }
               )) {
            Button(String(localized: "settings.backup.ok"), role: .cancel) { backupVM?.resetRestore() }
        } message: {
            if case .failed(let msg) = backupVM?.restoreState { Text(msg) }
        }
        // 备份模式切换完成提示
        .alert(String(localized: "settings.backup.modeUpdated"),
               isPresented: Binding(
                   get: { model.showBackupModeUpdated },
                   set: { model.showBackupModeUpdated = $0 }
               )) {
            Button(String(localized: "settings.backup.ok"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.backup.modeUpdatedMessage"))
        }
    }

    /// 副标题：「MiLens」用 Fraunces，中文用系统字体。
    private var proSubtitle: some View {
        Text("MiLens")
            .font(.custom("Fraunces-Semibold", size: 12))
            .foregroundStyle(Color.milensTextSecondary)
        + Text(String(localized: "settings.subtitle.suffix"))
            .font(.system(size: 12))
            .foregroundStyle(Color.milensTextSecondary)
    }

    // MARK: - Pro

    @ViewBuilder
    private var proContent: some View {
        if entitlement.isPro {
            // 已激活：暖黑卡显示已解锁状态，点击进入订阅管理
            ProHeroCard(isPro: true) {
                if let url = URL(string: SettingsLogic.Links.manageSubscriptions) {
                    openURL(url)
                }
            }
        } else {
            // 未解锁：点击弹付费墙
            ProHeroCard {
                showPaywall = true
            }
            proFeaturePreview
                .padding(.top, Spacing.lg)
        }
    }

    /// Pro 功能预览列表（未解锁时展示，作为 ProHeroCard 下方的功能清单）。
    /// 设计稿未展示多行；此处用轻量行（图标 + 标题），ArchiveDivider 分隔。
    private var proFeaturePreview: some View {
        VStack(spacing: 0) {
            ForEach(ProFeature.allCases) { feature in
                settingsPlainRow(
                    icon: feature.systemImage,
                    title: String(localized: String.LocalizationValue(feature.localizationKey))
                )
                if feature != ProFeature.allCases.last {
                    ArchiveDivider().padding(.leading, 32)
                }
            }
            ArchiveDivider().padding(.leading, 32)
            settingsPlainRow(
                icon: "person.2",
                title: String(localized: "paywall.benefit.family")
            )
        }
    }

    // MARK: - 隐私与数据

    private var privacyContent: some View {
        VStack(spacing: 0) {
            // 隐私状态徽章卡（点击进隐私详情）
            NavigationLink {
                PrivacyInfoView()
            } label: {
                PrivacyBadgeCard()
            }
            .buttonStyle(.plain)

            // 备份/政策行（无编号，置于 LedgerSection 内保持 rail 视觉一致）
            LedgerSection {
                // 隐私政策
                if let url = URL(string: SettingsLogic.Links.privacyPolicy) {
                    Link(destination: url) {
                        settingsPlainRow(
                            icon: "doc.text",
                            title: String(localized: "settings.privacy.policy")
                        )
                    }
                    .buttonStyle(.plain)
                    ArchiveDivider().padding(.leading, 32)
                }

                // 离线备份导出（Pro 门控）
                Button {
                    if entitlement.isPro {
                        Task { await backupVM?.exportBackup() }
                    } else {
                        showPaywall = true
                    }
                } label: {
                    backupEntryRow(
                        title: String(localized: "settings.backup.export"),
                        subtitle: entitlement.isPro ? nil : String(localized: "settings.backup.proOnly"),
                        inProgress: backupVM?.isExporting == true,
                        tint: entitlement.isPro ? .milensActionPrimary : .milensTextSecondary)
                }
                .buttonStyle(.plain)
                .disabled(backupVM?.isExporting == true)

                ArchiveDivider().padding(.leading, 32)

                // 备份恢复（所有用户）
                Button {
                    showRestoreImporter = true
                } label: {
                    backupEntryRow(
                        title: String(localized: "settings.backup.restore"),
                        subtitle: nil,
                        inProgress: backupVM?.isRestoring == true,
                        tint: .milensTextSecondary)
                }
                .buttonStyle(.plain)
                .disabled(backupVM?.isRestoring == true)

                ArchiveDivider().padding(.leading, 32)

                // 照片副本系统备份策略开关
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "icloud")
                            .font(.system(size: Sizing.iconMd))
                            .foregroundStyle(Color.milensTextSecondary)
                            .frame(width: 32)
                        Toggle(
                            String(localized: "settings.backup.photoBackupMode"),
                            isOn: Binding(
                                get: { PhotoBackupMode.parse(photoBackupModeRaw) == .dataSafe },
                                set: { newValue in
                                    let mode: PhotoBackupMode = newValue ? .dataSafe : .cloudOptimized
                                    photoBackupModeRaw = mode.rawValue
                                    if let sandboxDir = viewModel?.sandboxDir {
                                        Task {
                                            await viewModel?.handlePhotoBackupModeChange(mode, sandboxDir: sandboxDir)
                                        }
                                    }
                                }
                            )
                        )
                        .font(.bodyPrimary)
                        .foregroundStyle(Color.milensTextPrimary)
                        .tint(Color.milensActionPrimary)
                    }
                    Text(String(localized: "settings.backup.photoBackupMode.footer"))
                        .font(.caption)
                        .foregroundStyle(Color.milensTextSecondary)
                        .padding(.leading, 44)
                }
                .padding(.vertical, Spacing.md)
                .padding(.horizontal, 6)

                ArchiveDivider().padding(.leading, 32)

                // 备份安全引导提示
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(String(localized: "settings.backup.hint.title"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.milensTextSecondary)
                    Text(String(localized: "settings.backup.hint.body"))
                        .font(.caption)
                        .foregroundStyle(Color.milensTextTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.md)
                .padding(.horizontal, 6)
            }
            .padding(.top, Spacing.lg)
        }
    }

    // MARK: - 偏好设置（编号 01/02）

    private func preferenceContent(_ model: SettingsViewModel) -> some View {
        LedgerSection {
            // 01 通知
            LedgerRow(index: "01", label: String(localized: "settings.notifications.reminders")) {
                Toggle("", isOn: $remindersEnabled)
                    .labelsHidden()
                    .tint(Color.milensActionPrimary)
                    .onChange(of: remindersEnabled) { _, enabled in
                        Task {
                            let kept = await model.handleReminderToggle(enabled: enabled)
                            if kept != enabled { remindersEnabled = kept }
                        }
                    }
            }
            ArchiveDivider().padding(.leading, 32)

            // 02 外观
            LedgerRow(index: "02", label: String(localized: "settings.appearance.title")) {
                Picker(String(localized: "settings.appearance.title"), selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(appearanceLabel(for: mode)).tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .tint(Color.milensActionPrimary)
            }
        }
    }

    // MARK: - 支持与版本（编号 03/04）

    private func supportContent(_ model: SettingsViewModel) -> some View {
        LedgerSection {
            // 03 帮助
            NavigationLink {
                HelpView()
            } label: {
                LedgerDisclosureRow(
                    index: "03",
                    label: String(localized: "settings.support.help")
                )
            }
            .buttonStyle(.plain)

            ArchiveDivider().padding(.leading, 32)

            // 04 关于
            NavigationLink {
                AboutView(marketing: model.versionMarketing, build: model.versionBuild)
            } label: {
                LedgerDisclosureRow(
                    index: "04",
                    label: String(localized: "settings.about.entry"),
                    trailingText: "\(model.versionMarketing)"
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 行视图

    /// 简洁行：图标 + 标题（无 chevron，用于 Pro 功能预览）。
    private func settingsPlainRow(icon: String, title: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: Sizing.iconMd))
                .foregroundStyle(Color.milensTextSecondary)
                .frame(width: 32)
            Text(title)
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextPrimary)
            Spacer()
        }
        .frame(minHeight: Sizing.touchTarget)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    /// 备份行：图标 + 标题/副标题 + 进度/chevron。
    @ViewBuilder
    private func backupEntryRow(
        title: String,
        subtitle: String?,
        inProgress: Bool,
        tint: Color
    ) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "externaldrive")
                .font(.system(size: Sizing.iconMd))
                .foregroundStyle(tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }
            Spacer()
            if inProgress {
                ProgressView().tint(Color.milensTextTertiary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: Sizing.iconSm, weight: .semibold))
                    .foregroundStyle(Color.milensTextTertiary)
            }
        }
        .frame(minHeight: Sizing.touchTarget)
        .padding(.horizontal, 6)
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

// MARK: - 备份导出分享面板

/// 导出完成后展示：提供 ShareLink 让用户选择保存位置（Files/iCloud Drive/AirDrop）。
/// 不联网——系统 ShareSheet 完全由用户掌控。
struct BackupShareSheet: View {
    let url: URL

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.milensSuccess)
                Text(String(localized: "settings.backup.exportReady"))
                    .font(.headline)
                    .foregroundStyle(Color.milensTextPrimary)
                Text(String(localized: "settings.backup.exportReadyHint"))
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
                    .multilineTextAlignment(.center)
                ShareLink(item: url) {
                    Label(String(localized: "settings.backup.share"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.milensActionPrimary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.milensBackground)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
