//  NotificationAppDelegate —— UNUserNotificationCenter 代理 + 冷启动 tap 路由入口。
//
//  SwiftUI 无原生通知 tap 回调，通过 @UIApplicationDelegateAdaptor 接入 AppDelegate：
//  - didFinishLaunching 时注册为 UN center delegate（保证冷启动从通知拉起时也能收到 tap）；
//  - willPresent 控制前台展示（提醒类通知在前台仍弹横幅）；
//  - didReceive 解析标识符 → NotificationTapDestination，由 MiLensApp 查代表照片后构造 Route。
//  DESIGN.md §9 平台适配层：路由解析下沉为纯函数（NotificationDeepLink），本类只做回调转发。

import UIKit
import UserNotifications

/// 通知 tap 路由 AppDelegate（经 @UIApplicationDelegateAdaptor 注入 MiLensApp）。
final class NotificationAppDelegate: NSObject, UIApplicationDelegate, ObservableObject {

    /// 待处理的通知 tap 目的地（非 nil 时 MiLensApp 消费并清空）。
    @Published var pendingDestination: NotificationTapDestination?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 冷启动从通知拉起时，系统在 SwiftUI 视图创建前投递 tap；
        // 此处尽早注册 delegate，避免漏接首帧 didReceive。
        UNUserNotificationCenter.current().delegate = self
        return true
    }
}

extension NotificationAppDelegate: UNUserNotificationCenterDelegate {

    /// 前台收到通知时仍展示横幅 + 声音（纪念提醒需即时感知）。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// 用户 tap 通知 → 解析标识符 → 发布待路由目的地。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        pendingDestination = NotificationDeepLink.destination(
            fromIdentifier: response.notification.request.identifier)
    }
}
