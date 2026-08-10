//  OnboardingWelcomeStep —— 首次启动 Step 1 欢迎页（UI-DESIGN.md §6.1）。
//  品牌瞬间：记忆标记（6pt 珊瑚点 + 1pt 短线 + wordmark，§2.1）+ 文楷 Hero 标题
//  「把它的一生，留在这里」（每屏唯一文楷，§4.1）；品牌色只出现在记忆点与主 CTA。
//  三项真实价值走「找到 / 保存 / 再创造」诚实口径（§1.1，不承诺「认识每一只宠物」）；
//  说明性图标中性细线，不用大号爪印/满屏珊瑚（§2.1、P1-1）。
//  隐私政策为可点击链接 + 勾选（勾选后才能继续，流程语义不变）。

import SwiftUI

struct OnboardingWelcomeStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer(minLength: Spacing.xxl)

            // 品牌区：记忆标记 + Hero 标题（本屏唯一文楷）
            VStack(spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(Color.milensPrimary)
                        .frame(width: 6, height: 6)
                    Rectangle()
                        .fill(Color.milensBorder)
                        .frame(width: 24, height: 1)
                    Text("咪Lens")
                        .font(.caption)
                        .foregroundStyle(Color.milensTextSecondary)
                }
                Text("把它的一生，留在这里")
                    .font(.displayLarge)
                    .foregroundStyle(Color.milensTextPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, Spacing.pagePad)

            // 三项真实价值（找到 / 保存 / 再创造）
            VStack(alignment: .leading, spacing: Spacing.lg) {
                featureRow(icon: "photo.on.rectangle", text: "在本机寻找可能含宠物的照片")
                featureRow(icon: "calendar", text: "用时间线保存它的一生")
                featureRow(icon: "square.grid.3x3", text: "把照片变成拼豆与卡片作品")
            }
            .padding(.horizontal, Spacing.pagePad)

            Spacer()

            // 隐私政策：勾选（前进前提）+ 可点击链接
            HStack(spacing: Spacing.xs) {
                Button {
                    viewModel.privacyAgreed.toggle()
                } label: {
                    Image(systemName: viewModel.privacyAgreed
                          ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: Sizing.iconMd))
                        .foregroundStyle(viewModel.privacyAgreed
                                         ? Color.milensActionPrimary : Color.milensTextTertiary)
                        .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "a11y.onboarding.privacyAgree"))
                .accessibilityAddTraits(viewModel.privacyAgreed ? .isSelected : [])

                Text("我已阅读并同意")
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
                if let url = URL(string: SettingsLogic.Links.privacyPolicy) {
                    Link("《隐私政策》", destination: url)
                        .font(.caption)
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }
            .padding(.bottom, Spacing.lg)
        }
    }

    /// 价值条目：中性细线 SF Symbol + 正文，不用品牌色图标。
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: Sizing.iconMd, weight: .light))
                .foregroundStyle(Color.milensTextSecondary)
                .frame(width: 32)
            Text(text)
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextPrimary)
            Spacer()
        }
    }
}
