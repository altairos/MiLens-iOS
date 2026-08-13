//  QuotaDowngradeSheet —— 配额降级提示 sheet（ADR-0010 §10.1 扩展）。
//
//  两种使用场景：
//  1. RootTabView 检测到 Pro→免费降级且照片超额：双 CTA（续费恢复 / 管理存储）
//  2. GalleryView 锁定照片被点击：仅续费 CTA（用户已在相册，可看到锁定照片）
//
//  视觉语法复用 Ledger 组件体系（珊瑚竖线 + 文楷标题 + 暖白卡）。

import SwiftUI

struct QuotaDowngradeSheet: View {
    /// 是否展示「管理存储」CTA（降级提示时为 true；锁定照片点击时为 false）。
    var showManageCTA: Bool = false

    @Environment(\.dismiss) private var dismiss
    @AppStorage("storageManageRequested") private var storageManageRequested = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Spacer()

                // 锁标图标
                Image(systemName: "lock.fill")
                    .font(.system(size: 48)) // ui-token:ok 页头装饰大图标
                    .foregroundStyle(Color.milensActionPrimary)

                Text(String(localized: "quota.locked.sheet.title"))
                    .font(.displayMedium)
                    .foregroundStyle(Color.milensTextPrimary)

                Text(String(localized: "quota.locked.sheet.body"))
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)

                Spacer()

                // 主 CTA：续费恢复全部
                Button {
                    dismiss()
                    // 延迟一拍 present 付费墙，避免与当前 sheet dismiss 动画冲突
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        NotificationCenter.default.post(
                            name: .presentPaywallRequested, object: nil)
                    }
                } label: {
                    Text(String(localized: "quota.locked.sheet.cta.renew"))
                        .font(.buttonLabel)
                        .foregroundStyle(Color.milensTextOnActionPrimary)
                        .frame(maxWidth: .infinity, minHeight: Sizing.touchTarget)
                        .background(Color.milensActionPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // 次 CTA：管理存储（仅降级提示时展示）
                if showManageCTA {
                    Button {
                        storageManageRequested = true
                        dismiss()
                    } label: {
                        Text(String(localized: "quota.locked.sheet.cta.manage"))
                            .font(.bodyPrimary.weight(.medium))
                            .foregroundStyle(Color.milensTextPrimary)
                            .frame(maxWidth: .infinity, minHeight: Sizing.touchTarget)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    dismiss()
                } label: {
                    Text("知道了")
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextTertiary)
                }
                .buttonStyle(.plain)
                .padding(.top, Spacing.sm)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.milensBackground)
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 付费墙请求通知名

extension Notification.Name {
    /// 请求弹出付费墙（跨视图通知：降级 sheet / 锁定照片 sheet dismiss 后触发）。
    static let presentPaywallRequested = Notification.Name("presentPaywallRequested")
}

#Preview {
    QuotaDowngradeSheet(showManageCTA: true)
}
