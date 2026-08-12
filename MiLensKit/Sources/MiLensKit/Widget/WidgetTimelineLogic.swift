//  WidgetTimelineLogic —— Widget 时间线刷新策略纯决策逻辑。
//
//  WidgetKit-Design.md §6.2 时间线契约：
//  - 相片回声：跨日刷新；数据变更由主 App 主动 reload。
//  - 纪念日：为今天与次日边界生成 timeline entry，保证倒计时不滞后。
//  - 档案年轮：数据变更主动 reload；无变更时不高频刷新。
//  - Timeline provider 必须可取消并在读不到共享快照时返回 stale/empty，不得阻塞渲染。
//
//  纯函数：输入当前时间，输出下一次刷新时刻或多个 entry 时刻。
//  日期计算使用固定 UTC Calendar（miLensUTCCalendar），保证跨环境可复现。
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 SwiftUI 依赖。

import Foundation

public enum WidgetTimelineLogic {

    // MARK: - 相片回声

    /// 相片回声的下一次刷新时刻：明天 00:01（跨日选新照片）。
    ///
    /// - Parameter after: 当前时间
    /// - Returns: 明天 00:01 UTC（跨日边界后 1 分钟，确保日历已翻页）
    public static func photoEchoNextRefresh(after: Date) -> Date {
        nextDayStart(after: after)?.addingTimeInterval(60) ?? after.addingTimeInterval(3600)
    }

    // MARK: - 纪念日

    /// 纪念日 Widget 的 timeline entry 时刻（WidgetKit-Design.md §6.2）。
    ///
    /// 返回两个 entry 时刻：今天 23:59（保证今天倒计时可见）和明天 00:01
    /// （跨日后立即更新倒计时）。如果今天 23:59 已过，则从明天 00:01 开始。
    ///
    /// - Parameter now: 当前时间
    /// - Returns: timeline entry 时刻数组（升序）
    public static func upcomingDayEntries(now: Date) -> [Date] {
        let cal = miLensUTCCalendar
        let startOfToday = cal.startOfDay(for: now)

        // 今天 23:59
        let endOfToday = startOfToday
            .addingTimeInterval(23 * 3600 + 59 * 60)

        // 明天 00:01
        guard let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday) else {
            return [now.addingTimeInterval(3600)]
        }
        let tomorrowRefresh = startOfTomorrow.addingTimeInterval(60)

        if endOfToday > now {
            return [endOfToday, tomorrowRefresh]
        }
        return [tomorrowRefresh]
    }

    // MARK: - 档案年轮

    /// 档案年轮的下一次刷新时刻：4 小时后（低频，无变更不高频刷新）。
    ///
    /// - Parameter after: 当前时间
    /// - Returns: 4 小时后的时刻
    public static func archiveNextRefresh(after: Date) -> Date {
        after.addingTimeInterval(4 * 3600)
    }

    // MARK: - 锁屏组件

    /// 锁屏组件（Circular / Rectangular）的下一次刷新时刻。
    ///
    /// 锁屏组件信息密度低，跟随纪念日策略：跨日刷新 + 数据变更主动 reload。
    public static func lockScreenNextRefresh(after: Date) -> Date {
        photoEchoNextRefresh(after: after)
    }

    // MARK: - 内部工具

    /// 计算给定时刻所在日期的下一天起始（00:00 UTC）。
    static func nextDayStart(after: Date) -> Date? {
        let cal = miLensUTCCalendar
        let startOfToday = cal.startOfDay(for: after)
        return cal.date(byAdding: .day, value: 1, to: startOfToday)
    }
}
