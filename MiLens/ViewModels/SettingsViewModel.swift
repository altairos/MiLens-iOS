//  SettingsViewModel —— 「我的」页编排层（@Observable）。
//
//  决策下沉 SettingsLogic（纯函数）；本层只做：版本号读取（Bundle）、
//  纪念提醒开关编排（授权 → 调度/回弹，复用 P1 NotifyService 语义）。

import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {

    /// 通知授权被拒绝提示（View 据此弹 alert）
    var showReminderDeniedAlert = false
    /// 照片副本备份模式切换后重新标记完成提示
    var showBackupModeUpdated = false
    /// 关于页版本号组成部分（Bundle 读取，缺失为 "-"）
    let versionMarketing: String
    let versionBuild: String

    private let notifyService: NotifyService?
    private let fileStorage: (any FileStorage)?
    /// 沙盒媒体根目录（供 View 传递给 handlePhotoBackupModeChange）
    let sandboxDir: String?

    init(notifyService: NotifyService?,
         fileStorage: (any FileStorage)? = nil,
         sandboxDir: String? = nil,
         bundle: Bundle = .main) {
        self.notifyService = notifyService
        self.fileStorage = fileStorage
        self.sandboxDir = sandboxDir
        let parts = SettingsLogic.versionParts(
            marketing: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
        versionMarketing = parts.marketing
        versionBuild = parts.build
    }

    /// 纪念提醒开关处理。
    /// - Returns: 开关最终应保持的值。未授权/服务不可用时返回 false（View 回弹 @AppStorage）。
    func handleReminderToggle(enabled: Bool) async -> Bool {
        guard let notifyService else {
            // 测试 host 无 NotifyService：打开无意义，回弹
            if enabled { showReminderDeniedAlert = true }
            return false
        }
        if !enabled {
            await notifyService.cancelAllNotifications()
            return false
        }
        let authorized = await notifyService.requestAuthorization()
        switch SettingsLogic.resolveReminderToggle(enabled: true, authorized: authorized) {
        case .schedule:
            await notifyService.rescheduleAllReminders()
            return true
        case .rollbackAndPrompt:
            showReminderDeniedAlert = true
            return false
        case .cancelAll:
            // resolveReminderToggle(enabled:true,...) 不会返回 cancelAll
            return false
        }
    }

    // MARK: - 照片副本备份模式切换

    /// 用户切换备份模式后重新标记已有文件（导入副本排除/纳入系统备份）。
    /// IO 操作放到后台执行，完成后置位提示标志。
    /// - Parameters:
    ///   - mode: 新的备份模式
    ///   - sandboxDir: 沙盒媒体根目录（由调用方传入，避免 ViewModel 硬编码路径）
    func handlePhotoBackupModeChange(_ mode: PhotoBackupMode, sandboxDir: String) async {
        let exclude = SettingsLogic.shouldExcludePhotos(mode)
        if let fs = fileStorage as? IOSFileStorage {
            await fs.reapplyBackupExclusion(in: sandboxDir, exclude: exclude)
        }
        showBackupModeUpdated = true
    }
}
