//  IOSNotificationCenter —— NotificationPosting 的 UserNotifications 框架真实实现
//  （对应源端 notificationManager.publish / cancel）。
//  立即送达的本地通知：纪念日回忆 + 时光机每日推送。
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

    func post(title: String, body: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier, content: content, trigger: nil
        )
        // 权限被拒时 add 不抛错但不送达；业务层通过 authorizationStatus 判断，
        // 发布失败静默忽略（通知非关键路径，对应源端 publish 的 try/catch warn）。
        try? await UNUserNotificationCenter.current().add(request)
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
