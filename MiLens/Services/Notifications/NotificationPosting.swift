//  NotificationPosting —— 本地通知调度协议（对应源端 notificationManager.publish）。
//  把 UNUserNotificationCenter 的直接调用隔离在此协议后面，
//  使 NotifyService 可以通过 mock 覆盖调度/撤销路径（DESIGN.md §9 平台适配层）。
//
//  P1 重构：`post`（立即送达）替换为 `schedule`（UNCalendarNotificationTrigger
//  真调度）——纪念提醒改为「幂等重调度」语义，不再依赖前台每日检查。

import Foundation

/// 本地通知调度错误。
enum NotificationPostingError: Error, Equatable {
    /// 用户未授权通知权限。
    case notAuthorized
}

/// 本地通知调度协议。V1.0 含纪念日/时光机通知所需方法。
protocol NotificationPosting {
    /// 请求通知授权（系统弹窗）。返回当前是否已授权。
    func requestAuthorization() async -> Bool

    /// 当前授权状态。
    func authorizationStatus() async -> Bool

    /// 调度一条本地通知（UNCalendarNotificationTrigger，未来按日期组件触发）。
    /// - Parameters:
    ///   - title: 标题（如 "2年前的今天"）
    ///   - body: 正文（暖心文案，调度时固定内容）
    ///   - identifier: 通知标识符（撤销用，需稳定）
    ///   - dateComponents: 触发日期组件（如月日 + 时分；缺失年份 = 每年重复）
    ///   - repeats: 是否重复（true = 按组件循环触发）
    func schedule(
        title: String, body: String, identifier: String,
        dateComponents: DateComponents, repeats: Bool
    ) async throws

    /// 撤销指定通知（待发送 + 已送达）。
    func removeNotifications(identifiers: [String]) async

    /// 撤销全部通知（待发送 + 已送达）。设置开关关闭时用。
    func removeAllNotifications() async
}

// MARK: - Mock（对应源端 FakeNotificationManager）

/// 记录调度/撤销调用的 mock，用于单元测试。
final class MockNotificationPoster: NotificationPosting {
    /// requestAuthorization 的结果（默认 true，保持既有测试不破坏）
    var authorizationResult = true
    /// 已调度的通知记录（含日期组件与重复标志）
    private(set) var scheduled: [(
        title: String, body: String, identifier: String,
        dateComponents: DateComponents, repeats: Bool
    )] = []
    /// 已撤销的通知标识符
    private(set) var removedIdentifiers: [String] = []
    /// removeAllNotifications 调用次数
    private(set) var removeAllCount = 0
    /// requestAuthorization 调用次数
    private(set) var authorizationRequestCount = 0

    func requestAuthorization() async -> Bool {
        authorizationRequestCount += 1
        return authorizationResult
    }

    func authorizationStatus() async -> Bool {
        authorizationResult
    }

    func schedule(
        title: String, body: String, identifier: String,
        dateComponents: DateComponents, repeats: Bool
    ) async throws {
        scheduled.append((title, body, identifier, dateComponents, repeats))
    }

    func removeNotifications(identifiers: [String]) async {
        removedIdentifiers.append(contentsOf: identifiers)
    }

    func removeAllNotifications() async {
        removeAllCount += 1
    }
}
