//  IOSNotificationCenter —— NotificationPosting 的 UserNotifications 框架真实实现
//  （对应源端 notificationManager.publish / cancel）。
//  P1 重构：`schedule` 用 UNCalendarNotificationTrigger 真调度——
//  纪念日年度重复通知 + 时光机每日通知由系统在后台触发，不再依赖前台检查。
//  DESIGN.md §9 平台适配层：业务层只依赖协议，本文件是唯一直接接触 UserNotifications 的地方。

import Foundation
import UserNotifications

final class IOSNotificationCenter: NotificationPosting {

    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        return granted
    }

    func authorizationStatus() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    func schedule(
        title: String, body: String, identifier: String,
        dateComponents: DateComponents, repeats: Bool
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents, repeats: repeats)
        let request = UNNotificationRequest(
            identifier: identifier, content: content, trigger: trigger
        )
        // 权限被拒时 add 不抛错但不送达；业务层通过开关路径保证授权后调度，
        // 调度失败向上抛（调用方可感知），通知非关键路径由调用方 decide 是否降级。
        try await UNUserNotificationCenter.current().add(request)
    }

    func removeNotifications(identifiers: [String]) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func removeAllNotifications() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
