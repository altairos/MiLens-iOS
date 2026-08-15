//  SettingsBackupFlow —— 设置页备份导出/恢复流程的 UI 修饰符与状态文案。
//  从 SettingsView.swift 拆出（ADR-0011 §5 规模守卫拆分批次）：
//  文案纯函数（SettingsBackupCopy）+ sheet/alert/进度浮层/恢复文件选择器
//  （SettingsBackupFlowModifier，挂在 settingsContent 上）。

import SwiftUI
import UniformTypeIdentifiers

/// 备份入口的状态文案（纯函数）。
enum SettingsBackupCopy {
    /// 导出入口副标题：
    /// 服务不可用 →「即将上线」；未解锁 →「Pro 专属功能」；
    /// 已解锁 → 展示上次备份时间（「上次备份 8 月 3 日」）或「尚未备份」温柔引导。
    static func exportSubtitle(isPro: Bool, backupVM: BackupViewModel?) -> String? {
        if backupVM?.isServiceAvailable == false {
            return String(localized: "settings.backup.comingSoon")
        }
        if !isPro {
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
    static func exportPhaseText(for state: BackupViewModel.ExportState?) -> String? {
        guard let state else { return nil }
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

/// 备份导出/恢复流程的 sheet / alert / 进度浮层 / 恢复文件选择器。
struct SettingsBackupFlowModifier: ViewModifier {
    let backupVM: BackupViewModel?
    @Binding var showRestoreImporter: Bool
    @Binding var showBackupModeUpdated: Bool

    /// `.milensbackup` 文件类型（project.yml UTExportedTypeDeclarations 声明为本 App 导出类型）。
    private var milensBackupType: UTType { UTType(exportedAs: "com.milens.backup") }

    func body(content: Content) -> some View {
        content
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
                if let phaseText = SettingsBackupCopy.exportPhaseText(for: backupVM?.exportState) {
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
                   isPresented: $showBackupModeUpdated) {
                Button(String(localized: "settings.backup.ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "settings.backup.modeUpdatedMessage"))
            }
    }
}
