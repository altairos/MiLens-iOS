//  NotifyCheckLogic —— 纪念提醒每日检查纯决策逻辑
//  （对应源端 utils/WorkSchedulerUtils.ets scheduleDailyEventCheck
//   + database/photo/PhotoQueryDao.ets getAnniversaryEvents 的过滤语义）。
//
//  纯函数：不依赖 Repository / UserNotifications / SwiftData。
//  宿主（NotifyService）负责 IO：查照片、请求授权、发布/撤销通知。
//
//  架构差异：
//  - 源端用 SQL LIKE '%-MM-DD%' 匹配拍摄日期；iOS 用 Calendar 组件匹配，
//    语义等价且避免字符串格式依赖。
//  - 源端 WorkScheduler 后台每日触发；iOS 采用「前台检查 + 当日去重」：
//    App 激活时运行 runDailyCheck，同一天只执行一次（UserDefaults 标记）。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

enum NotifyCheckLogic {

    /// 每日检查日期标记的 UserDefaults key。
    static let lastCheckDateKey = "lastDailyCheckDate"

    /// 是否应执行每日检查（与上次检查不是同一天则返回 true）。
    /// - Parameters:
    ///   - lastCheckDate: 上次检查时间（nil = 从未检查）
    ///   - now: 当前时间（注入保证测试可复现）
    ///   - calendar: 日历（默认当地时区——用户感知的「今天」）
    static func shouldRunDailyCheck(
        lastCheckDate: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let lastCheckDate else { return true }
        let last = calendar.dateComponents([.year, .month, .day], from: lastCheckDate)
        let current = calendar.dateComponents([.year, .month, .day], from: now)
        return last != current
    }

    /// 日期标记字符串（"yyyy-MM-dd"，当地时区），用于 UserDefaults 去重。
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let comp = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      comp.year ?? 0, comp.month ?? 0, comp.day ?? 0)
    }

    /// 拍摄日期是否匹配指定月日（对应源端 `taken_at LIKE '%-MM-DD%'`）。
    static func matchesMonthDay(
        _ date: Date?,
        month: Int,
        day: Int,
        calendar: Calendar = .current
    ) -> Bool {
        guard let date else { return false }
        let comp = calendar.dateComponents([.month, .day], from: date)
        return comp.month == month && comp.day == day
    }

    /// 拍摄日期是否属于指定年份（对应源端 `NOT LIKE 'YYYY-MM-DD%'` 的排除语义）。
    static func isInYear(
        _ date: Date?,
        year: Int,
        calendar: Calendar = .current
    ) -> Bool {
        guard let date else { return false }
        return calendar.component(.year, from: date) == year
    }
}
