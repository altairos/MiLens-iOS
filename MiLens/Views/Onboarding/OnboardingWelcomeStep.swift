//  OnboardingWelcomeStep —— 首次启动 Step 1 欢迎页
//  （对应 iOS 设计稿「二、首次启动流程 Step 1」+ 源端 components/onboarding/WelcomeStep）。
//  品牌展示 + 三个核心卖点 + 隐私政策勾选（勾选后才能继续）。

import SwiftUI

struct OnboardingWelcomeStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer(minLength: 40)

            // 品牌区
            VStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.milensAccentSoft)
                        .frame(width: 96, height: 96)
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.milensPrimary)
                }
                Text("咪Lens")
                    .font(.displayLarge)
                Text("记录爱的一生")
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
            }

            // 卖点列表
            VStack(alignment: .leading, spacing: Spacing.lg) {
                featureRow(icon: "photo.stack.fill", text: "找到所有宠物照片")
                featureRow(icon: "person.crop.circle.fill", text: "认识你的每一只宠物")
                featureRow(icon: "heart.fill", text: "保存成长回忆")
            }
            .padding(.horizontal, Spacing.xxl)

            Spacer()

            // 隐私勾选
            VStack(spacing: Spacing.sm) {
                Button {
                    viewModel.privacyAgreed.toggle()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: viewModel.privacyAgreed
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(viewModel.privacyAgreed
                                             ? Color.milensPrimary : Color.milensTextTertiary)
                        Text("我已阅读并同意《隐私政策》")
                            .font(.caption)
                            .foregroundStyle(Color.milensTextSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, Spacing.lg)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.milensPrimary)
                .frame(width: 32)
            Text(text)
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextPrimary)
            Spacer()
        }
    }
}
