//  NewPhotoReminderLogic —— 新照片/久未添加提醒触发时机的纯决策逻辑。
//
//  决定何时提示用户「系统图库可能有新照片」或「很久没添新照片了」。
//  纯函数：不依赖 IO / UserDefaults / SwiftUI，宿主层负责读取游标/照片数据并传入。
//  阈值（staleDays）为可测常量，单测覆盖边界。
//
//  设计目标：在不打扰用户的前提下，温柔地引导持续记录——
//  系统图库有新照片时轻触（增量检测），超过两周未添加时温和提醒。
//
//  诚实标注：iOS 无公开「照片加入系统图库时间」API，
//  以 creationDate 近似（与 ScanCursorStore 同策略）；老照片导入系统图库后
//  creationDate 早于游标检测不到，全量扫描兜底。

import Foundation

public enum NewPhotoReminderLogic {

    /// 久未添加提醒阈值：距上次添加照片超过此天数（含从未导入）时提醒。
    public static let staleDays = 14

    // MARK: - 距上次添加天数

    /// 计算距上次添加照片的整天数（按自然日，非 24h 周期）。
    /// - Parameters:
    ///   - lastAddedDate: 最近一张照片的创建时间；nil 表示从未导入。
    ///   - now: 当前时间（注入保证测试可复现）。
    ///   - calendar: 日历（默认当前时区）。
    /// - Returns: 整天数；从未导入返回 nil。
    public static func daysSinceLastAdded(
        lastAddedDate: Date?, now: Date, calendar: Calendar = .current
    ) -> Int? {
        guard let lastAddedDate else { return nil }
        let startOfLast = calendar.startOfDay(for: lastAddedDate)
        let startOfNow = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: startOfLast, to: startOfNow).day
    }

    // MARK: - 单项触发判定

    /// 久未添加提醒：从未导入 OR >= staleDays。
    public static func shouldRemindForStaleInput(
        lastAddedDate: Date?, now: Date, calendar: Calendar = .current
    ) -> Bool {
        let days = daysSinceLastAdded(lastAddedDate: lastAddedDate, now: now, calendar: calendar)
        guard let days else { return true }
        return days >= staleDays
    }

    /// 新照片提醒：增量计数 > 0。
    public static func shouldRemindForNewPhotos(newPhotoCount: Int) -> Bool {
        newPhotoCount > 0
    }

    /// 综合提醒（驱动通知调度）：任一条件命中。
    public static func shouldRemind(
        newPhotoCount: Int, lastAddedDate: Date?,
        now: Date, calendar: Calendar = .current
    ) -> Bool {
        shouldRemindForNewPhotos(newPhotoCount: newPhotoCount)
            || shouldRemindForStaleInput(lastAddedDate: lastAddedDate, now: now, calendar: calendar)
    }

    // MARK: - 提醒子类型（决定文案与呈现）

    /// 新照片提醒子类型，决定确认窗/通知文案。
    public enum ReminderKind: Equatable, Sendable {
        /// 系统图库有新照片（count > 0），且未触发久未添加。
        case newPhotos
        /// 久未添加（>= staleDays 或从未导入），且无新照片。
        case staleInput
        /// 两者同时命中。
        case both
        /// 均未命中。
        case none
    }

    /// 根据新照片计数与最近添加时间判定提醒子类型。
    public static func resolveKind(
        newPhotoCount: Int, lastAddedDate: Date?,
        now: Date, calendar: Calendar = .current
    ) -> ReminderKind {
        let hasNew = shouldRemindForNewPhotos(newPhotoCount: newPhotoCount)
        let isStale = shouldRemindForStaleInput(
            lastAddedDate: lastAddedDate, now: now, calendar: calendar)
        switch (hasNew, isStale) {
        case (true, true): return .both
        case (true, false): return .newPhotos
        case (false, true): return .staleInput
        case (false, false): return .none
        }
    }
}
