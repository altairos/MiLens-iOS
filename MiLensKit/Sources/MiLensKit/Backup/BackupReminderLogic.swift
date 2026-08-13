//  BackupReminderLogic —— 备份引导触发时机的纯决策逻辑。
//
//  决定何时在首页展示备份提醒横幅、何时调度定期备份通知，以及距上次备份的天数。
//  纯函数：不依赖 IO / UserDefaults / SwiftUI，宿主层负责读取 lastBackupDate 并传入。
//  阈值（staleDays / minPhotos）为可测常量，单测覆盖边界。
//
//  设计目标：在不打扰用户的前提下，温柔地引导「完整保存记忆」——
//  数据量太少（刚建档）不打扰，刚备份过不打扰，只有积累了一定记忆且久未备份才轻触。

import Foundation

public enum BackupReminderLogic {

    /// 首页备份提醒横幅：距上次备份超过此天数（含从未备份）且照片量达标时展示。
    public static let bannerStaleDays = 30
    /// 首页备份提醒横幅：触发所需的最小照片数（刚建档数据量太少不打扰）。
    public static let bannerMinPhotos = 20
    /// 定期备份通知：距上次备份超过此天数（含从未备份）时调度提醒。
    public static let reminderStaleDays = 60

    // MARK: - 距上次备份天数

    /// 计算距上次备份的整天数（按自然日，非 24h 周期）。
    /// - Parameters:
    ///   - lastBackupDate: 上次导出备份的时间；nil 表示从未备份。
    ///   - now: 当前时间（注入保证测试可复现）。
    ///   - calendar: 日历（默认当前时区）。
    /// - Returns: 整天数；从未备份返回 nil。负值理论上不会出现（导出时间不应晚于 now），但计算上可能为负。
    public static func daysSinceLastBackup(
        lastBackupDate: Date?, now: Date, calendar: Calendar = .current
    ) -> Int? {
        guard let lastBackupDate else { return nil }
        let startOfLast = calendar.startOfDay(for: lastBackupDate)
        let startOfNow = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: startOfLast, to: startOfNow).day
    }

    // MARK: - 首页横幅触发

    /// 是否应在首页展示备份提醒横幅。
    /// 条件：照片数 ≥ bannerMinPhotos，且（从未备份 OR 距上次备份 ≥ bannerStaleDays）。
    public static func shouldShowHomeBanner(
        lastBackupDate: Date?, photoCount: Int, now: Date, calendar: Calendar = .current
    ) -> Bool {
        guard photoCount >= bannerMinPhotos else { return false }
        let days = daysSinceLastBackup(lastBackupDate: lastBackupDate, now: now, calendar: calendar)
        // 从未备份（days == nil）或超期（days >= 阈值）
        guard let days else { return true }
        return days >= bannerStaleDays
    }

    // MARK: - 定期通知触发

    /// 是否应调度定期备份提醒通知。
    /// 条件：从未备份 OR 距上次备份 ≥ reminderStaleDays。
    public static func shouldScheduleBackupReminder(
        lastBackupDate: Date?, now: Date, calendar: Calendar = .current
    ) -> Bool {
        let days = daysSinceLastBackup(lastBackupDate: lastBackupDate, now: now, calendar: calendar)
        guard let days else { return true }
        return days >= reminderStaleDays
    }
}
