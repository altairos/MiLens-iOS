//  OnboardingPermissionStep —— 首次启动 Step 2 权限说明页（UI-DESIGN.md §6.1）。
//  本地处理三条短说明建立信任：照片不离开设备 / 分析在本机完成 / 由你决定导入什么。
//  说明图标中性细线；卡片 = milensCard + 0.5pt 描边（边框优先于阴影，§5.2）；
//  文楷标题每屏唯一；权限系统弹窗只在点击容器主按钮「继续」后出现（流程不变）。

import SwiftUI

struct OnboardingPermissionStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer(minLength: Spacing.xxl)

            // 图标 + 标题（本屏唯一文楷）
            VStack(spacing: Spacing.md) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.milensTextSecondary)
                Text("隐私优先")
                    .font(.displayMedium)
                    .foregroundStyle(Color.milensTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("你的照片只属于你")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
            }

            // 隐私说明卡片
            VStack(alignment: .leading, spacing: Spacing.lg) {
                privacyRow(icon: "iphone.gen3", title: "照片不会离开设备",
                           subtitle: "所有照片仅在本机处理，不会上传到云端")
                Divider()
                    .overlay(Color.milensSeparator)
                privacyRow(icon: "cpu", title: "AI 分析在本地完成",
                           subtitle: "在本机分析照片，找出可能含宠物的内容")
                Divider()
                    .overlay(Color.milensSeparator)
                privacyRow(icon: "checkmark.circle", title: "由你决定导入什么",
                           subtitle: "扫描只筛选候选照片，确认后才会导入档案")
            }
            .padding(Spacing.xl)
            .background(Color.milensCard)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(Color.milensBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .padding(.horizontal, Spacing.pagePad)

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
                .foregroundStyle(Color.milensTextSecondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: Spacing.xs) {
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
                .padding(.horizontal, Spacing.pagePad)
        }
    }
}
