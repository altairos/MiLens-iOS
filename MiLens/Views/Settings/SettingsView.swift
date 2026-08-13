//  SettingsView —— 「我的」（Tab 4）。
//
//  Ledger 账本式设计语言（对照 Figma「07·我的」#140:415）：
//  珊瑚竖线 rail + Fraunces 编号 + 虚线引导线 + 暖黑 Pro 卡 + 隐私徽章卡。
//  业务逻辑层（SettingsViewModel / SettingsLogic）零改动；所有数据绑定保留。

import SwiftUI
import UniformTypeIdentifiers
import MiLensKit

struct SettingsView: View {
    @AppStorage("reminderNotificationsEnabled") private var remindersEnabled = false
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("photoBackupMode") private var photoBackupModeRaw = PhotoBackupMode.cloudOptimized.rawValue
    /// 跨 Tab 请求进入 Gallery 存储管理模式（与 RootTabView/GalleryView 共享）
    @AppStorage("storageManageRequested") private var storageManageRequested = false
    @Environment(\.notifyService) private var notifyService
    @Environment(\.proEntitlement) private var entitlement
    @Environment(\.backupService) private var backupService
    @Environment(\.fileStorage) private var fileStorage
    @Environment(\.photoRepository) private var photoRepo
    @Environment(\.openURL) private var openURL

    @State private var viewModel: SettingsViewModel?
    @State private var showPaywall = false
    @State private var backupVM: BackupViewModel?
    @State private var showRestoreImporter = false
    /// 照片总数（onAppear / scenePhase active 时刷新）
    @State private var photoCount = 0
    /// 跨 Tab 请求进入备份导出（首页横幅 / 通知 tap 触发；与 RootTabView 共享）
    @AppStorage("backupExportRequested") private var backupExportRequested = false
    /// 铃铛晃动模式（四选一，与 HomeView 共享）
    @AppStorage("bellShakeMode") private var bellShakeModeRaw = BellShakeLogic.ShakeMode.all.rawValue

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
            photoCount = (try? photoRepo.countAllPhotos()) ?? 0
            // 首页横幅 / 通知 tap 发起的跨 Tab 备份请求（Tab 首次 appear 时 onChange 不可靠，onAppear 兜底）
            handleBackupExportRequest()
        }
        .onChange(of: backupExportRequested) { _, _ in
            handleBackupExportRequest()
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
            if case .done(let urls) = backupVM?.exportState {
                BackupShareSheet(urls: urls)
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
        // allowsMultipleSelection=true：支持多卷分卷备份选择全部分卷文件
        .fileImporter(
            isPresented: $showRestoreImporter,
            allowedContentTypes: [milensBackupType, .item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                if !urls.isEmpty { Task { await backupVM?.importBackup(from: urls) } }
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

    /// 消费跨 Tab 备份导出请求：服务可用 + Pro → 预估导出；可用 + 非 Pro → 付费墙。
    /// 不可用时不处理（入口本身已禁用）。
    private func handleBackupExportRequest() {
        guard backupExportRequested, let backupVM else { return }
        backupExportRequested = false
        guard backupVM.isServiceAvailable else { return }
        if entitlement.isPro {
            Task { await backupVM.prepareExport() }
        } else {
            showPaywall = true
        }
    }

    /// 副标题：「MiLens」用 Fraunces，中文用系统字体。
    private var proSubtitle: some View {
        Text("MiLens")
            .font(.custom("Fraunces-Semibold", size: 12))
            .foregroundStyle(Color.milensTextSecondary)
        + Text(String(localized: "settings.subtitle.suffix"))
            .font(.bodySecondary)
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

            // 照片存储管理入口（免费用户超额时珊瑚色高亮提示）
            Button {
                storageManageRequested = true
            } label: {
                storageEntryRow
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.lg)

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
                          || backupVM?.isRestoring == true
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
                .disabled(backupVM?.isRestoring == true
                          || backupVM?.isExporting == true
                          || backupVM?.isEstimating == true
                          || backupVM?.isServiceAvailable == false)

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
            ArchiveDivider().padding(.leading, 32)

            // 03 铃铛提醒
            LedgerRow(index: "03", label: String(localized: "settings.bellShake.title")) {
                Picker("", selection: $bellShakeModeRaw) {
                    ForEach(BellShakeLogic.ShakeMode.allCases, id: \.rawValue) { mode in
                        Text(bellShakeLabel(for: mode)).tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .tint(Color.milensActionPrimary)
            }
        }
    }

    /// 铃铛晃动模式文案
    private func bellShakeLabel(for mode: BellShakeLogic.ShakeMode) -> String {
        switch mode {
        case .off: return String(localized: "settings.bellShake.off")
        case .newPhotoOnly: return String(localized: "settings.bellShake.newPhotoOnly")
        case .anniversaryOnly: return String(localized: "settings.bellShake.anniversaryOnly")
        case .all: return String(localized: "settings.bellShake.all")
        }
    }

    // MARK: - 支持与版本（编号 04/05）

    private func supportContent(_ model: SettingsViewModel) -> some View {
        LedgerSection {
            // 04 帮助
            NavigationLink {
                HelpView()
            } label: {
                LedgerDisclosureRow(
                    index: "04",
                    label: String(localized: "settings.support.help")
                )
            }
            .buttonStyle(.plain)

            ArchiveDivider().padding(.leading, 32)

            // 05 关于
            NavigationLink {
                AboutView(marketing: model.versionMarketing, build: model.versionBuild)
            } label: {
                LedgerDisclosureRow(
                    index: "05",
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

    // MARK: - 照片存储入口行

    /// 照片存储行：图标 + 标题 + 计数（超额时珊瑚色高亮）。
    /// 点击跳转 Gallery 存储管理模式（设置 storageManageRequested，GalleryView 监听）。
    private var storageEntryRow: some View {
        let limit = CommercialRules.photoLimit(isPro: entitlement.isPro)
        let isOverLimit = !entitlement.isPro && photoCount > limit
        return HStack(spacing: Spacing.md) {
            Image(systemName: "photo.stack")
                .font(.system(size: Sizing.iconMd))
                .foregroundStyle(isOverLimit ? Color.milensActionPrimary : Color.milensTextSecondary)
                .frame(width: 32)
            Text(String(localized: "settings.storage.title"))
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextPrimary)
            Spacer()
            Text(String(format: String(localized: "settings.storage.count %lld %lld"),
                         photoCount, limit == Int.max ? 9999 : limit))
                .font(.bodySecondary)
                .foregroundStyle(isOverLimit ? Color.milensActionPrimary : Color.milensTextSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold)) // ui-token:ok SF Symbol 光学图标尺寸
                .foregroundStyle(Color.milensTextTertiary)
        }
        .frame(minHeight: Sizing.touchTarget)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    // MARK: - 备份状态文案辅助

    /// 导出入口副标题：
    /// 服务不可用 →「即将上线」；未解锁 →「Pro 专属功能」；
    /// 已解锁 → 展示上次备份时间（「上次备份 8 月 3 日」）或「尚未备份」温柔引导。
    private var backupExportSubtitle: String? {
        if backupVM?.isServiceAvailable == false {
            return String(localized: "settings.backup.comingSoon")
        }
        if !entitlement.isPro {
            return String(localized: "settings.backup.proOnly")
        }
        // 已解锁 Pro：展示上次备份时间，让用户感知自己的备份状态
        if let lastDate = backupVM?.lastBackupDate {
            let dateText = lastDate.formatted(.dateTime.year().month().day())
            return String(localized: "settings.backup.lastBackup \(dateText)")
        }
        return String(localized: "settings.backup.neverBackup")
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

#Preview {
    NavigationStack {
        SettingsView()
    }
}
