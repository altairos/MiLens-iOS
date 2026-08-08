//  我的（Tab 4）—— P1 实现纪念提醒设置开关。
//  - 「纪念提醒」开关（@AppStorage("reminderNotificationsEnabled")，默认关闭）：
//    打开：请求授权 → 成功则幂等全量重调度；拒绝回弹开关并提示。
//    关闭：撤销全部已调度通知。
//  P5 实现：主题/隐私设置、StoreKit Pro 订阅、帮助、关于。

import SwiftUI

struct SettingsView: View {
    @AppStorage("reminderNotificationsEnabled") private var remindersEnabled = false
    @Environment(\.notifyService) private var notifyService

    @State private var showDeniedAlert = false

    var body: some View {
        List {
            Section {
                Toggle("纪念提醒", isOn: $remindersEnabled)
                    .onChange(of: remindersEnabled) { _, enabled in
                        handleToggle(enabled)
                    }
            } footer: {
                Text("开启后：宠物生日与领养日当天 09:00 提醒；有历史同日照片时每日 09:00 推送时光机。")
            }
        }
        .alert("未获得通知权限", isPresented: $showDeniedAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请在系统设置中允许 MiLens 发送通知，再开启纪念提醒。")
        }
    }

    // MARK: - 开关处理

    private func handleToggle(_ enabled: Bool) {
        guard let notifyService else { return }
        if enabled {
            // 打开：先请求授权；拒绝则回弹开关并提示
            Task {
                guard await notifyService.requestAuthorization() else {
                    remindersEnabled = false
                    showDeniedAlert = true
                    return
                }
                await notifyService.rescheduleAllReminders()
            }
        } else {
            // 关闭：撤销全部已调度通知
            Task { await notifyService.cancelAllNotifications() }
        }
    }
}
