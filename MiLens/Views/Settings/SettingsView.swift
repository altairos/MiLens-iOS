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

    /// `.milensbackup` 文件类型（project.yml UTExportedTypeDeclarations 声明为本 App 导出类型）。
    private var milensBackupType: UTType { UTType(exportedAs: "com.milens.backup") }

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
        // 导出预估完成 → 弹确认对话框（展示将导出的规模，用户确认后开始打包）
        .sheet(isPresented: Binding(
            get: { if case .readyToExport = backupVM?.exportState { return true } else { return false } },
            set: { if !$0 { if case .readyToExport = backupVM?.exportState { backupVM?.resetExport() } } }
        )) {
            if case .readyToExport(let estimate) = backupVM?.exportState {
                BackupConfirmSheet(estimate: estimate) {
                    Task { await backupVM?.exportBackup() }
                }
            }
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
        // 导出中 → 阶段进度浮层（长任务时告知「收集/复制/压缩」到哪一步）
        .overlay {
            if let phaseText = currentExportPhaseText {
                ExportProgressOverlay(message: phaseText)
            }
        }
        // 恢复文件选择器（限定 .milensbackup；.item 作为兑底以便旧版系统）
        .fileImporter(
            isPresented: $showRestoreImporter,
            allowedContentTypes: [milensBackupType, .item],
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

                // 离线备份导出（Pro 门控；isAvailable=false 时禁用并提示「即将上线」）
                Button {
                    if backupVM?.isServiceAvailable == false {
                        // 服务不可用：入口已禁用，此处为防御兑底
                    } else if entitlement.isPro {
                        Task { await backupVM?.prepareExport() }
                    } else {
                        showPaywall = true
                    }
                } label: {
                    backupEntryRow(
                        title: String(localized: "settings.backup.export"),
                        subtitle: backupExportSubtitle,
                        inProgress: backupVM?.isExporting == true || backupVM?.isEstimating == true,
                        tint: (entitlement.isPro && backupVM?.isServiceAvailable == true)
                            ? .milensActionPrimary : .milensTextSecondary)
                }
                .buttonStyle(.plain)
                .disabled(backupVM?.isExporting == true
                          || backupVM?.isEstimating == true
                          || backupVM?.isServiceAvailable == false)

                ArchiveDivider().padding(.leading, 32)

                // 备份恢复（所有用户；isAvailable=false 时禁用）
                Button {
                    showRestoreImporter = true
                } label: {
                    backupEntryRow(
                        title: String(localized: "settings.backup.restore"),
                        subtitle: backupVM?.isServiceAvailable == false
                            ? String(localized: "settings.backup.comingSoon") : nil,
                        inProgress: backupVM?.isRestoring == true,
                        tint: .milensTextSecondary)
                }
                .buttonStyle(.plain)
                .disabled(backupVM?.isRestoring == true || backupVM?.isServiceAvailable == false)

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

    // MARK: - 备份状态文案辅助

    /// 导出入口副标题：服务不可用 →「即将上线」；未解锁 →「Pro 专属功能」；否则不显示。
    private var backupExportSubtitle: String? {
        if backupVM?.isServiceAvailable == false {
            return String(localized: "settings.backup.comingSoon")
        }
        if !entitlement.isPro {
            return String(localized: "settings.backup.proOnly")
        }
        return nil
    }

    /// 导出中当前阶段的本地化文案（仅导出进行中返回非空）。
    private var currentExportPhaseText: String? {
        guard let state = backupVM?.exportState else { return nil }
        if case .inProgress(let fraction, let phase) = state {
            let pct = Int((fraction * 100).rounded())
            let phaseLabel: String
            switch phase {
            case .collectingMetadata:
                phaseLabel = String(localized: "settings.backup.phase.collecting")
            case .copyingPhotos:
                phaseLabel = String(localized: "settings.backup.phase.copying")
            case .compressing:
                phaseLabel = String(localized: "settings.backup.phase.compressing")
            case .done:
                phaseLabel = String(localized: "settings.backup.phase.done")
            }
            return String(localized: "settings.backup.phase.progress \(pct) \(phaseLabel)")
        }
        return nil
    }
}

// MARK: - 备份导出确认对话框

/// 导出前展示预估规模（N 个档案、M 张照片），让用户确认后再打包。
/// 避免大库无声产出巨大 ZIP，用户毫无预期。
struct BackupConfirmSheet: View {
    let estimate: BackupEstimate
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "externaldrive.badge.timemachine")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.milensActionPrimary)
                Text(String(localized: "settings.backup.confirmTitle"))
                    .font(.headline)
                    .foregroundStyle(Color.milensTextPrimary)
                // 预估规模
                VStack(spacing: Spacing.xs) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "pawprint")
                            .foregroundStyle(Color.milensTextSecondary)
                        Text(String(localized: "settings.backup.confirmPets \(estimate.petCount)"))
                        Spacer()
                    }
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "photo.on.rectangle")
                            .foregroundStyle(Color.milensTextSecondary)
                        Text(String(localized: "settings.backup.confirmPhotos \(estimate.photoCount)"))
                        Spacer()
                    }
                }
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.md)
                .background(Color.milensCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))

                Text(String(localized: "settings.backup.confirmHint"))
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Spacer()

                Button {
                    onConfirm()
                } label: {
                    Text(String(localized: "settings.backup.confirmAction"))
                        .font(.buttonLabel)
                        .foregroundStyle(Color.milensTextOnActionPrimary)
                        .frame(maxWidth: .infinity, minHeight: Sizing.touchTarget)
                        .background(Color.milensActionPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.milensBackground)
        }
        .modalContentWidth()
    }
}

// MARK: - 备份导出阶段进度浮层

/// 导出打包进行中的阶段进度浮层（半透明遮罩 + 阶段文案 + 进度转圈）。
struct ExportProgressOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                ProgressView()
                    .tint(Color.milensActionPrimary)
                Text(message)
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextPrimary)
            }
            .padding(Spacing.xl)
            .background(Color.milensCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        }
        .accessibilityElement(children: .combine)
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
