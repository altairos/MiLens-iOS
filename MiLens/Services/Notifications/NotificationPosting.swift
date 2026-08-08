//  NotificationPosting —— 本地通知发布协议（对应源端 notificationManager.publish）。
//  把 UNUserNotificationCenter 的直接调用隔离在此协议后面，
//  使 NotifyService 可以通过 mock 覆盖发布/撤销路径（DESIGN.md §9 平台适配层）。

import Foundation

/// 本地通知发布错误。
enum NotificationPostingError: Error, Equatable {
    /// 用户未授权通知权限。
    case notAuthorized
}

/// 本地通知发布协议。V1.0 含纪念日/时光机通知所需方法。
protocol NotificationPosting {
    /// 请求通知授权（系统弹窗）。返回当前是否已授权。
    func requestAuthorization() async -> Bool

    /// 当前授权状态。
    func authorizationStatus() async -> Bool

    /// 发布一条本地通知（立即送达）。
    /// - Parameters:
    ///   - title: 标题（如 "2年前的今天"）
    ///   - body: 正文（暖心文案）
    ///   - identifier: 通知标识符（撤销用，需稳定）
    func post(title: String, body: String, identifier: String) async

    /// 撤销指定通知（待发送 + 已送达）。
    func removeNotifications(identifiers: [String]) async

    /// 撤销全部通知（待发送 + 已送达）。设置开关关闭时用。
    func removeAllNotifications() async
}

// MARK: - Mock（对应源端 FakeNotificationManager）

/// 记录发布/撤销调用的 mock，用于单元测试。
final class MockNotificationPoster: NotificationPosting {
    /// requestAuthorization 的结果（默认 true，保持既有测试不破坏）
    var authorizationResult = true
    /// 已发布的通知记录
    private(set) var posted: [(title: String, body: String, identifier: String)] = []
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

    func post(title: String, body: String, identifier: String) async {
        posted.append((title, body, identifier))
    }

    func removeNotifications(identifiers: [String]) async {
        removedIdentifiers.append(contentsOf: identifiers)
    }

    func removeAllNotifications() async {
        removeAllCount += 1
    }
}
