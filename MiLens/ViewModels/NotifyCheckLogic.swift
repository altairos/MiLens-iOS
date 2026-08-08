//  NotifyCheckLogic —— 纪念提醒日期匹配纯决策逻辑
//  （对应源端 database/photo/PhotoQueryDao.ets getAnniversaryEvents 的过滤语义）。
//
//  纯函数：不依赖 Repository / UserNotifications / SwiftData。
//  宿主（NotifyService）负责 IO：查照片、调度/撤销通知。
//
//  架构差异：
//  - 源端用 SQL LIKE '%-MM-DD%' 匹配拍摄日期；iOS 用 Calendar 组件匹配，
//    语义等价且避免字符串格式依赖。
//  - 源端 WorkScheduler 后台每日触发；iOS 采用 UNCalendarNotificationTrigger
//    真调度（P1）：提醒由系统按日期组件触发，无需前台检查/当日去重。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

enum NotifyCheckLogic {

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
