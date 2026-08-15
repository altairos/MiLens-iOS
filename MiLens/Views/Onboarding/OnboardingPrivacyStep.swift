//  OnboardingPrivacyStep —— 首次启动 01 欢迎 / 隐私摘要（对照 Figma #47:7）。
//  EditorialSection（"你的照片，只属于这台设备"文楷 28）+ On Device 卡片 +
//  Rules 卡片（3 行编号 01/02/03：照片不离开设备/分析在本机完成/由你确认导入）+
//  底部说明"稍后也可在系统设置调整"。
//  FocusDialButton「继续建档」——点击时先请求照片权限（系统弹窗在此触发），
//  授权结果（authorized/denied/limited）都允许继续（可在系统设置补授权）。

import SwiftUI

struct OnboardingPrivacyStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialSection(
                    overline: "FIRST LIGHT · 隐私摘要",
                    title: "你的照片，\n只属于这台设备",
                    bodyText: "「咪Lens」只读取访问范围内的本地照片，\n最终导入什么，始终由你确认。"
                )

                // On Device 卡片
                onDeviceCard
                    .padding(.top, Spacing.xxl)

                // Rules 卡片
                rulesCard
                    .padding(.top, Spacing.lg)

                // 底部说明
                Text("稍后也可以在系统设置中调整照片访问范围。")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextTertiary)
                    .padding(.top, Spacing.xl)

                // 权限状态提示（已请求过后显示）
                authStatusHint
                    .padding(.top, Spacing.md)

                // Focus Dial
                FocusDialButton(
                    label: viewModel.isRequestingAuth ? "请求中…" : "继续建档",
                    systemImage: "arrow.right",
                    isEnabled: !viewModel.isRequestingAuth
                ) {
                    // 点击主按钮时先请求照片权限（系统弹窗在此触发）；
                    // 授权结果（authorized/denied/limited）都允许继续。
                    Task {
                        await viewModel.requestPhotoAuthorization()
                        viewModel.goToNextStep()
                    }
                }
                .padding(.top, Spacing.xxl)
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .task { await viewModel.refreshAuthStatus() }
    }

    // MARK: - On Device 卡片（对照 #47:7 On Device）

    private var onDeviceCard: some View {
        EditorialCard(cornerRadius: Radius.large) {
            VStack(alignment: .leading, spacing: 0) {
                // Brand Orbit + 印章（小型）
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.milensActionPrimary, style: StrokeStyle(lineWidth: 2, dash: [1]))
                            .frame(width: 68, height: 68)
                        Image("BrandSeal")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ON DEVICE")
                            .font(.editorialOverline)
                            .tracking(0.1)
                            .foregroundStyle(Color.milensActionPrimary)
                            .textCase(.uppercase)
                        Text("只在本机整理")
                            .font(.uiTitle)
                            .foregroundStyle(Color.milensTextPrimary)
                    }
                    Spacer()
                }
                .padding(.top, 22)

                Text("不上传照片；不在云端留副本。")
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.top, 8)

                RegisterMark(leadWidth: 42, tailWidth: 200)
                    .padding(.top, 14)

                Text("本机特征基准 · 由你命名")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextTertiary)
                    .padding(.top, 6)
                    .padding(.bottom, 22)
            }
            .padding(.leading, 22)
            .padding(.trailing, 16)
        }
    }

    // MARK: - Rules 卡片（对照 #47:7 Rules，3 行编号规则）

    private var rulesCard: some View {
        EditorialCard(cornerRadius: Radius.large) {
            VStack(alignment: .leading, spacing: 0) {
                ruleRow(number: "01", title: "照片不离开设备",
                        subtitle: "不会上传到服务器", isLast: false)
                ruleRow(number: "02", title: "分析在本机完成",
                        subtitle: "只处理相册缩略图", isLast: false)
                ruleRow(number: "03", title: "由你确认导入",
                        subtitle: "候选不等于识别结果", isLast: true)
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
    }

    private func ruleRow(number: String, title: String, subtitle: String, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Text(number)
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensActionPrimary)
                    .frame(width: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                    Text(subtitle)
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                }
                Spacer()
            }
            .padding(.vertical, 10)

            if !isLast {
                Rectangle()
                    .fill(Color.milensSeparator)
                    .frame(height: 1)
            }
        }
    }

    // MARK: - 权限状态提示

    @ViewBuilder
    private var authStatusHint: some View {
        switch viewModel.authStatus {
        case .authorized:
            Label("已获得全部照片访问权限", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.milensSuccess)
        case .limited:
            Label("已获得部分照片访问权限", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.milensSuccess)
        case .denied, .restricted:
            VStack(alignment: .leading, spacing: 4) {
                Label("相册权限未开启", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.milensWarning)
                Text("可在「设置 → 隐私 → 照片」中开启，扫描需要访问照片才能筛选候选")
                    .font(.caption)
                    .foregroundStyle(Color.milensTextTertiary)
            }
        case .notDetermined:
            EmptyView()
        }
    }
}
