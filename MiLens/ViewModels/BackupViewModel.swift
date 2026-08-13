//  BackupViewModel —— 离线备份导出/恢复编排（@Observable）。
//
//  持有 BackupService 并对外暴露进度/结果状态机，供 SettingsView 绑定。
//  决策与服务调用收口在此层；View 只渲染状态（导出中/完成/失败，恢复统计）。
//  导出完成后暴露临时文件 URL，由 View 层经 ShareSheet 让用户选择保存位置。
//
//  导出流程分两步：
//  1. prepareExport() 预估规模（petCount/photoCount），View 据此弹确认对话框；
//  2. exportBackup() 实际打包，导出中状态携带阶段文案（收集/复制/压缩），
//     长任务时用户能看到「卡在哪一步」。
//
//  幂等保护：预估/导出/恢复进行中时重复触发直接忽略，避免并发写临时文件或重复导入。
//  互斥保护：导出与恢复不可同时进行（共享同一 DB 上下文，并发写入有冲突风险），
//  任意一方进行中时另一方直接忽略。
//
//  上次备份时间（lastBackupDate）：导出成功后持久化到 UserDefaults，
//  供设置页副标题展示「上次备份 X 月 X 日」、首页横幅与定期通知判断「多久没备份」。
//  引导触达时机决策下沉 BackupReminderLogic（MiLensKit），本层只读写时间戳。

import Foundation
import MiLensKit
import Observation

@MainActor
@Observable
final class BackupViewModel {

    /// 导出状态机（携带阶段，便于 UI 展示「收集元数据/复制照片/压缩」）。
    enum ExportState: Equatable {
        case idle
        case estimating
        case readyToExport(BackupEstimate)  // 预估完成，待用户确认
        case inProgress(Double, BackupPhase) // fraction 0…1 + 当前阶段
        case done([URL])                    // 临时备份文件列表，待 ShareSheet 分享
        case failed(String)
    }

    /// 恢复状态机。
    enum RestoreState: Equatable {
        case idle
        case inProgress(Double, RestorePhase)
        case done(RestoreResult)
        case failed(String)
    }

    /// 上次备份时间在 UserDefaults 的存储 key（首页横幅 / 定期通知复用）。
    static let lastBackupDateKey = "lastBackupDate"

    private let backupService: any BackupService
    /// 上次备份时间的读写后端（默认 UserDefaults；测试可注入 mock）。
    private let defaults: UserDefaults

    var exportState: ExportState = .idle
    var restoreState: RestoreState = .idle

    /// 服务是否可用（UI 据此禁用备份入口）。
    var isServiceAvailable: Bool { backupService.isAvailable }

    var isExporting: Bool {
        if case .inProgress = exportState { return true }
        return false
    }

    var isEstimating: Bool {
        if case .estimating = exportState { return true }
        return false
    }

    var isRestoring: Bool {
        if case .inProgress = restoreState { return true }
        return false
    }

    init(backupService: any BackupService, defaults: UserDefaults = .standard) {
        self.backupService = backupService
        self.defaults = defaults
    }

    // MARK: - 上次备份时间

    /// 上次成功导出备份的时间；nil 表示从未备份。
    /// 供设置页副标题、首页横幅、定期通知判断「距上次备份多久」。
    var lastBackupDate: Date? {
        defaults.object(forKey: Self.lastBackupDateKey) as? Date
    }

    /// 距上次备份的整天数；从未备份返回 nil。
    var daysSinceLastBackup: Int? {
        BackupReminderLogic.daysSinceLastBackup(
            lastBackupDate: lastBackupDate, now: Date())
    }

    // MARK: - 导出

    /// 预估将导出的内容规模（不打包）。完成后 exportState 进入 .readyToExport，
    /// 由 View 弹确认对话框让用户确认后再调用 exportBackup()。
    func prepareExport() async {
        guard !isEstimating, !isExporting, !isRestoring else { return }
        exportState = .estimating
        do {
            let estimate = try await backupService.estimateBackup(petIDs: nil)
            exportState = .readyToExport(estimate)
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }

    /// 实际导出（用户在确认对话框点「导出」后调用）。
    func exportBackup() async {
        guard !isExporting, !isRestoring else { return }
        exportState = .inProgress(0, .collectingMetadata)
        do {
            let result = try await backupService.exportBackup(petIDs: nil) { [weak self] progress in
                self?.exportState = .inProgress(progress.fraction, progress.phase)
            }
            // 记录成功导出时间，供设置页副标题 / 首页横幅 / 定期通知判断使用。
            defaults.set(Date(), forKey: Self.lastBackupDateKey)
            exportState = .done(result.fileURLs)
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }

    func resetExport() { exportState = .idle }

    // MARK: - 恢复

    func importBackup(from urls: [URL]) async {
        guard !isRestoring, !isExporting else { return }
        restoreState = .inProgress(0, .decompressing)
        do {
            let result = try await backupService.importBackup(from: urls) { [weak self] progress in
                self?.restoreState = .inProgress(progress.fraction, progress.phase)
            }
            restoreState = .done(result)
        } catch {
            restoreState = .failed(error.localizedDescription)
        }
    }

    func resetRestore() { restoreState = .idle }
}
