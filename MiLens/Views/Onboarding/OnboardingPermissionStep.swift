//  OnboardingPermissionStep —— 首次启动 Step 2 权限说明页
//  （对应 iOS 设计稿「二、首次启动流程 Step 2」）。
//  强调隐私：照片不会离开设备、AI 分析在本地完成。请求照片库权限。

import SwiftUI

struct OnboardingPermissionStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer(minLength: 40)

            // 图标 + 标题
            VStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.milensAccentSoft)
                        .frame(width: 96, height: 96)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.milensPrimary)
                }
                Text("隐私优先")
                    .font(.displayMedium)
                Text("你的照片只属于你")
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
            }

            // 隐私说明卡片
            VStack(alignment: .leading, spacing: Spacing.lg) {
                privacyRow(icon: "iphone.gen3", title: "照片不会离开设备",
                           subtitle: "所有照片仅在本机处理，不会上传到云端")
                Divider()
                    .overlay(Color.milensSeparator)
                privacyRow(icon: "cpu.fill", title: "AI 分析在本地完成",
                           subtitle: "宠物识别与照片整理均由设备端 AI 完成")
            }
            .padding(Spacing.xl)
            .background(Color.milensCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.large))
            .padding(.horizontal, Spacing.xxl)

            Spacer()

            // 权限状态提示
            Group {
                switch viewModel.authStatus {
                case .authorized, .limited:
                    authorizedLabel
                case .denied, .restricted:
                    deniedLabel
                case .notDetermined:
                    EmptyView()
                }
            }
            .padding(.bottom, Spacing.lg)
        }
        .task { await viewModel.refreshAuthStatus() }
    }

    // MARK: - 子视图

    private func privacyRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.milensPrimary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
            }
            Spacer()
        }
    }

    private var authorizedLabel: some View {
        Label("已获得相册访问权限", systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(Color.milensSuccess)
    }

    private var deniedLabel: some View {
        VStack(spacing: Spacing.xs) {
            Label("相册权限未开启", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Color.milensWarning)
            Text("可在「设置 → 隐私 → 照片」中开启，也可以稍后在相册页授权")
                .font(.caption)
                .foregroundStyle(Color.milensTextTertiary)
                .multilineTextAlignment(.center)
        }
    }
}
