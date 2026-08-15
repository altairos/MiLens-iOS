//  OnboardingView —— 首次启动引导「First Archive」容器（对照 Figma #47:2）。
//  步骤：欢迎(空态/隐私摘要) → 建立档案 → 特征注册(选图/处理/完成) →
//       全面扫描 → 候选确认 → 导入中 → 导入成功。
//  Header：后退 + 安静短线进度指示（4 段，按 majorStage 点亮）+ 阶段编号。
//  每屏 step 自含主 CTA（FocusDialButton / ContactProofButton），容器不再注入统一 footer。
//  步骤切换淡入 + 轻位移，Reduce Motion 时仅淡入。
//  依赖由 MiLensApp 组合根构造注入。

import SwiftUI

struct OnboardingView: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            stepContent
        }
        .background(Color.milensBackground)
        .animation(reduceMotion ? nil : .easeInOut(duration: Motion.durationNormal),
                   value: viewModel.step)
        .onChange(of: viewModel.step) { _, _ in
            viewModel.onStepAppear()
        }
        .task {
            // 首次进入若已在 fullScan（例如 App 重建恢复），自动启动
            viewModel.onStepAppear()
        }
    }

    // MARK: - 顶部：后退 + 安静短线进度指示 + 阶段编号

    private var header: some View {
        HStack {
            backButtonSlot
            Spacer()
            stepIndicator
            Spacer()
            // 与后退按钮等宽占位，保持指示器视觉居中
            Color.clear
                .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, Spacing.md)
    }

    private var backButtonSlot: some View {
        Group {
            if viewModel.step != .welcome {
                Button {
                    viewModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.bodyPrimary)
                        .foregroundStyle(Color.milensTextPrimary)
                        .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "a11y.onboarding.back"))
            } else {
                Color.clear
                    .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
            }
        }
    }

    /// 四个安静短线（§6.1）：当前大阶段及之前为珊瑚实色，之后为分隔色，不给任务压力。
    /// 右侧显示当前阶段编号 01–04（Fraunces Bold 12，对照 Figma #94:23）。
    private var stepIndicator: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(0..<4, id: \.self) { stage in
                Capsule()
                    .fill(stage <= viewModel.majorStage
                          ? Color.milensActionPrimary : Color.milensSeparator)
                    .frame(width: 24, height: 2)
            }
            Text(viewModel.stageIndexText)
                .font(.custom("Fraunces-Bold", size: 28))
                .foregroundStyle(Color.milensActionPrimary)
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "a11y.onboarding.step \(viewModel.majorStage + 1) \(OnboardingViewModel.majorStageCount)"))
    }

    // MARK: - 步骤内容

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .welcome:
            OnboardingWelcomeStep(viewModel: viewModel)
                .transition(stepTransition)
        case .privacy:
            OnboardingPrivacyStep(viewModel: viewModel)
                .transition(stepTransition)
        case .createArchive:
            OnboardingCreateArchiveStep(viewModel: viewModel)
                .transition(stepTransition)
        case .featureIntro, .featureProcessing, .featureDone:
            OnboardingFeatureRegisterStep(viewModel: viewModel)
                .transition(stepTransition)
        case .fullScan:
            OnboardingFullScanStep(viewModel: viewModel)
                .transition(stepTransition)
        case .candidates:
            OnboardingCandidatesStep(viewModel: viewModel)
                .transition(stepTransition)
        case .importing, .success:
            OnboardingImportStep(viewModel: viewModel)
                .transition(stepTransition)
        }
    }

    /// 步骤过渡：淡入 + 轻位移（§7 页面局部变化 200–260ms）；Reduce Motion 仅淡入。
    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 12)),
            removal: .opacity
        )
    }
}
