//  MilestoneLogic —— 相处里程碑纯决策逻辑（ADR-0010 §3.2 / §10.11）。
//
//  「来到家第 100/365/730/1000 天」里程碑的计算、命中判定与通知调度数据准备。
//  与年度重复的生日/领养日纪念（复用 NotifyService 周年通知）不同，里程碑按
//  天数单次触发：每个里程碑只在到达当天提醒一次。
//
//  纯函数：不依赖 Repository / UserNotifications / SwiftData。
//  宿主（NotifyService / PetCardView）负责 IO 与实际通知调度 / 卡片渲染。
//  日期计算内部使用固定 UTC Calendar（miLensUTCCalendar），与 HomeMemoryLogic
//  保持同一约定，保证跨环境可复现（测试可在任意时区机器运行）。
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 SwiftUI 依赖。

import Foundation

// MARK: - 里程碑值对象

/// 一个相处里程碑（如「来到家 365 天」）。
public struct PetMilestone: Equatable, Sendable {
    /// 里程碑天数（100 / 365 / 730 / 1000）。
    public let days: Int

    public init(days: Int) {
        self.days = days
    }
}

// MARK: - 决策逻辑

public enum MilestoneLogic {

    /// 全部里程碑天数（按升序，对应 ADR-0010 §3.2 的 100/365/730/1000 天）。
    public static let milestoneDays: [Int] = [100, 365, 730, 1000]

    // MARK: - 整数核心（无日历依赖，最易测试）

    /// 校验指定天数是否为里程碑值，是则返回对应里程碑。
    public static func milestone(forDays days: Int) -> PetMilestone? {
        milestoneDays.contains(days) ? PetMilestone(days: days) : nil
    }

    /// 判定当前已相处天数是否恰好命中某个里程碑。
    /// - Parameter daysElapsed: 自锚点日期起经过的整天数（截断）。
    /// - Returns: 命中的里程碑；未命中（包括已过 / 未到 / 非里程碑值）返回 nil。
    public static func hitMilestone(daysElapsed: Int) -> PetMilestone? {
        milestone(forDays: daysElapsed)
    }

    /// 返回严格大于已相处天数的下一个里程碑（用于「即将到达」提醒）。
    public static func nextMilestone(afterDaysElapsed daysElapsed: Int) -> PetMilestone? {
        guard let days = milestoneDays.first(where: { $0 > daysElapsed }) else { return nil }
        return PetMilestone(days: days)
    }

    /// 返回严格小于已相处天数的上一个里程碑（用于「已达成」回看）。
    public static func previousMilestone(beforeDaysElapsed daysElapsed: Int) -> PetMilestone? {
        guard let days = milestoneDays.last(where: { $0 < daysElapsed }) else { return nil }
        return PetMilestone(days: days)
    }

    // MARK: - 日期计算（内部 UTC Calendar）

    /// 自锚点日期（领养日/生日）到现在的整天数（截断，与 PetDisplayLogic.daysTogether 语义一致）。
    /// 锚点在未来时返回负数。
    public static func daysSince(from anchor: Date, now: Date) -> Int {
        Int(now.timeIntervalSince(anchor) / 86_400)
    }

    /// 里程碑到达的精确日期（锚点 + days 天，UTC 日历日进位）。
    public static func milestoneDate(anchor: Date, days: Int) -> Date {
        miLensUTCCalendar.date(byAdding: .day, value: days, to: anchor) ?? anchor
    }

    /// 从现在到某里程碑到达还剩多少天（负数表示已过）。
    public static func daysRemaining(to milestone: PetMilestone, from anchor: Date, now: Date) -> Int {
        milestone.days - daysSince(from: anchor, now: now)
    }

    /// 返回从现在起 `daysAhead` 天内将到达的全部里程碑（含今日命中的）。
    /// 用于通知批量预排（如每月检查一次，预排未来 35 天内的里程碑通知）。
    public static func upcomingMilestones(
        from anchor: Date, now: Date, daysAhead: Int
    ) -> [PetMilestone] {
        let elapsed = daysSince(from: anchor, now: now)
        let upperBound = elapsed + max(0, daysAhead)
        return milestoneDays
            .filter { $0 >= elapsed && $0 <= upperBound }
            .map { PetMilestone(days: $0) }
    }

    // MARK: - 文案

    /// 里程碑标题文案（与 App 层 pet.card.daysHome 同义，MiLensKit 内用固定中文）。
    /// App 层 PetCardView 渲染时可用 String(localized:) 覆盖；此处供测试与通知文本复用。
    public static func milestoneTitle(days: Int) -> String {
        "来到家 \(days) 天"
    }

    /// 里程碑通知正文（含宠物名，用于本地推送）。
    public static func milestoneNotificationText(petName: String, days: Int) -> String {
        let title = milestoneTitle(days: days)
        return petName.isEmpty ? title : "\(petName)\(title)了"
    }
}
