//  StateView —— 页面级状态视图（UI-DESIGN.md §5.3.9 / §11 验收门禁）。
//
//  统一承载 Empty / Error / Permission Denied / Offline-Resource Missing 四态的
//  视觉表面（Loading 用 ProgressView 即可，不由此组件承载）。每态均提供图标、
//  标题、说明与明确下一步动作，确保用户始终有可恢复路径（§11）。
//  组件只负责排版，不持有业务状态；调用方按页面语境传入文案与动作。

import SwiftUI

/// 页面级状态视图（UI-DESIGN.md §5.3.9 / §11 验收门禁）。
struct StateView: View {
    /// SF Symbol 名称。
    let icon: String
    /// 状态标题（displayMedium，状态页主层级）。
    let title: String
    /// 状态说明（可选）。
    var message: String?
    /// 主动作标题（可选，提供时渲染为 ActionPrimary 实心按钮，单屏仅一个）。
    var primaryActionTitle: String?
    /// 主动作回调。
    var primaryAction: (() -> Void)?
    /// 次动作标题（可选，提供时渲染为系统默认按钮，不与主按钮同权重）。
    var secondaryActionTitle: String?
    /// 次动作回调。
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.milensTextSecondary)
            Text(title)
                .font(.displayMedium)
                .foregroundStyle(Color.milensTextPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .multilineTextAlignment(.center)
            }
            if let primaryActionTitle, let primaryAction {
                Button(action: primaryAction) {
                    Text(primaryActionTitle)
                        .font(.buttonLabel)
                        .foregroundStyle(Color.milensTextOnActionPrimary)
                        .frame(maxWidth: .infinity, minHeight: Sizing.touchTarget)
                        .padding(.horizontal, Spacing.xxl)
                        .background(Color.milensActionPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if let secondaryActionTitle, let secondaryAction {
                Button(secondaryActionTitle, action: secondaryAction)
                    .font(.bodyPrimary)
            }
        }
        .padding(.horizontal, Spacing.pagePad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("空状态") {
    StateView(
        icon: "pawprint.fill",
        title: "还没有照片",
        message: "扫描系统相册，自动发现你的宠物照片",
        primaryActionTitle: "开始扫描",
        primaryAction: {}
    )
    .background(Color.milensBackground)
}

#Preview("错误状态") {
    StateView(
        icon: "exclamationmark.triangle",
        title: String(localized: "pet.profile.loadFailed"),
        primaryActionTitle: String(localized: "common.back"),
        primaryAction: {}
    )
    .background(Color.milensBackground)
}
