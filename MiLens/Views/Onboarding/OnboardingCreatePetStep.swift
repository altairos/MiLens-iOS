//  OnboardingCreatePetStep —— 首次启动 Step 4 建档页
//  （对应 iOS 设计稿「二、首次启动流程 Step 4」）。
//  情绪峰值：扫描发现照片数 + 名字输入；创建动作由容器主按钮触发
//  （OnboardingViewModel.createFirstPet，PetProfileLogic 校验语义）。

import SwiftUI

struct OnboardingCreatePetStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer(minLength: 40)

            // 情绪峰值区（设计稿 Step 4：我们找到了小橘 / 照片：842 张）
            VStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.milensAccentSoft)
                        .frame(width: 96, height: 96)
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.milensPrimary)
                }
                if viewModel.scanFoundCount > 0 {
                    Text("我们找到了它")
                        .font(.displayMedium)
                    Text("照片：\(viewModel.scanFoundCount) 张")
                        .font(.numberStat)
                        .foregroundStyle(Color.milensTextSecondary)
                } else {
                    Text("为它创建第一份档案")
                        .font(.displayMedium)
                    Text("随时可以在相册页扫描并导入更多照片")
                        .font(.bodyPrimary)
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }

            // 名字输入
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("它叫什么名字？")
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
                TextField("输入宠物名字", text: $viewModel.petName)
                    .font(.bodyPrimary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .background(Color.milensCard)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.medium))
                    .submitLabel(.done)
                    .onSubmit { viewModel.submitCreatePet() }
            }
            .padding(.horizontal, Spacing.xxl)

            // 校验错误
            if !viewModel.scanError.isEmpty {
                Label(viewModel.scanError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.milensDanger)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.xxl)
    }
}
