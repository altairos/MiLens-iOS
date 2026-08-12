//  Haptics —— 触感反馈轻量封装。
//
//  对 UIImpactFeedbackGenerator 的薄封装，集中管理风格，避免散落各处的
//  UIFeedbackGenerator 调用。遵循 iOS HIG：轻量、不打扰、无障碍友好。
//  AGENTS.md §4：异步资源成对释放——generator 为短暂实例，无需 defer 清理。

import UIKit

enum Haptics {

    /// 轻触反馈（按钮点击、Tab 切换）。
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// 中等反馈（确认操作、卡片选中）。
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// 柔和反馈（情感触点：铃铛摇晃、回忆提示等温和场景）。
    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// 成功反馈（操作完成）。
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
