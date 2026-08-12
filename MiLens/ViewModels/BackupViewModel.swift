//  BackupViewModel —— 离线备份导出/恢复编排（@Observable）。
//
//  持有 BackupService 并对外暴露进度/结果状态机，供 SettingsView 绑定。
//  决策与服务调用收口在此层；View 只渲染状态（导出中/完成/失败，恢复统计）。
//  导出完成后暴露临时文件 URL，由 View 层经 ShareSheet 让用户选择保存位置。
//
//  幂等保护：导出/恢复进行中时重复触发直接忽略，避免并发写临时文件或重复导入。

import Foundation
import Observation

@MainActor
@Observable
final class BackupViewModel {

    /// 导出状态机。
    enum ExportState: Equatable {
        case idle
        case inProgress(Double)   // fraction 0…1
        case done(URL)            // 临时备份文件，待 ShareSheet 分享
        case failed(String)
    }

    /// 恢复状态机。
    enum RestoreState: Equatable {
        case idle
        case inProgress(Double)
        case done(RestoreResult)
        case failed(String)
    }

    private let backupService: any BackupService

    var exportState: ExportState = .idle
    var restoreState: RestoreState = .idle

    var isExporting: Bool {
        if case .inProgress = exportState { return true }
        return false
    }

    var isRestoring: Bool {
        if case .inProgress = restoreState { return true }
        return false
    }

    init(backupService: any BackupService) {
        self.backupService = backupService
    }

    // MARK: - 导出

    func exportBackup() async {
        guard !isExporting else { return }
        exportState = .inProgress(0)
        do {
            let result = try await backupService.exportBackup(petIDs: nil) { [weak self] progress in
                self?.exportState = .inProgress(progress.fraction)
            }
            exportState = .done(result.fileURL)
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }

    func resetExport() { exportState = .idle }

    // MARK: - 恢复

    func importBackup(from url: URL) async {
        guard !isRestoring else { return }
        restoreState = .inProgress(0)
        do {
            let result = try await backupService.importBackup(from: url) { [weak self] progress in
                self?.restoreState = .inProgress(progress.fraction)
            }
            restoreState = .done(result)
        } catch {
            restoreState = .failed(error.localizedDescription)
        }
    }

    func resetRestore() { restoreState = .idle }
}
