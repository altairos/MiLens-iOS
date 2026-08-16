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
                    overline: viewModel.stepOverline,
                    title: String(localized: "onboarding.privacy.title"),
                    bodyText: String(localized: "onboarding.privacy.body")
                )

                // On Device 卡片
                onDeviceCard
                    .padding(.top, Spacing.xxl)

                // Rules 卡片
                rulesCard
                    .padding(.top, Spacing.lg)

                // 底部说明
                Text(String(localized: "onboarding.privacy.hint"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextTertiary)
                    .padding(.top, Spacing.xl)

                // 权限状态提示（已请求过后显示）
                authStatusHint
                    .padding(.top, Spacing.md)

                // Focus Dial
                FocusDialButton(
                    label: viewModel.isRequestingAuth
                        ? String(localized: "onboarding.privacy.requesting")
                        : String(localized: "onboarding.privacy.cta"),
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
                        Text(String(localized: "onboarding.privacy.onDevice"))
                            .font(.editorialOverline)
                            .tracking(0.1)
                            .foregroundStyle(Color.milensActionPrimary)
                            .textCase(.uppercase)
                        Text(String(localized: "onboarding.privacy.card.title"))
                            .font(.uiTitle)
                            .foregroundStyle(Color.milensTextPrimary)
                    }
                    Spacer()
                }
                .padding(.top, 22)

                Text(String(localized: "onboarding.privacy.card.body"))
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.top, 8)

                RegisterMark(leadWidth: 42, tailWidth: 200)
                    .padding(.top, 14)

                Text(String(localized: "onboarding.privacy.card.note"))
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
                ruleRow(number: "01",
                        title: String(localized: "onboarding.privacy.rule.leave"),
                        subtitle: String(localized: "onboarding.privacy.rule.leave.detail"), isLast: false)
                ruleRow(number: "02",
                        title: String(localized: "onboarding.privacy.rule.local"),
                        subtitle: String(localized: "onboarding.privacy.rule.local.detail"), isLast: false)
                ruleRow(number: "03",
                        title: String(localized: "onboarding.privacy.rule.confirm"),
                        subtitle: String(localized: "onboarding.privacy.rule.confirm.detail"), isLast: true)
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
            Label(String(localized: "onboarding.privacy.auth.full"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.milensSuccess)
        case .limited:
            Label(String(localized: "onboarding.privacy.auth.limited"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.milensSuccess)
        case .denied, .restricted:
            VStack(alignment: .leading, spacing: 4) {
                Label(String(localized: "onboarding.privacy.auth.denied"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.milensWarning)
                Text(String(localized: "onboarding.privacy.auth.denied.hint"))
                    .font(.caption)
                    .foregroundStyle(Color.milensTextTertiary)
            }
        case .notDetermined:
            EmptyView()
        }
    }
}
