//  OnboardingView —— 首次启动引导容器（UI-DESIGN.md §6.1「首次启动」）。
//  步骤：欢迎 → 权限说明 → 扫描 → 创建第一份档案。
//  权限步骤点击继续时先请求授权（拒绝也可继续，可在系统设置补授权）；
//  扫描步骤进入时自动开始（复用 ScanService，只筛选不入库）。
//  视觉：进度指示用四条安静短线（不显示「1/4」式任务压力，§6.1）；
//  主按钮为 ActionPrimary 胶囊（§5.3 PrimaryButton ≥50pt，对比度见 §3.1）；
//  步骤切换淡入 + 轻位移，Reduce Motion 时仅淡入（§7）。
//  依赖由 MiLensApp 组合根构造注入。

import SwiftUI

struct OnboardingView: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            stepContent
            footer
        }
        .background(Color.milensBackground)
        .animation(reduceMotion ? nil : .easeInOut(duration: Motion.durationNormal),
                   value: viewModel.step)
        .onChange(of: viewModel.step) { _, _ in
            viewModel.onStepAppear()
        }
        .task {
            // 首次进入若已在扫描步骤（例如 App 重建恢复），自动启动
            viewModel.onStepAppear()
        }
    }

    // MARK: - 顶部：后退 + 安静短线进度指示

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
                .accessibilityLabel("返回上一步")
            } else {
                Color.clear
                    .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
            }
        }
    }

    /// 四个安静短线（§6.1）：已到达的步骤为实色，未到为分隔色，不给任务压力。
    private var stepIndicator: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(OnboardingViewModel.Step.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= viewModel.step.rawValue
                          ? Color.milensTextPrimary : Color.milensSeparator)
                    .frame(width: 24, height: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(viewModel.step.rawValue + 1) 步，共 \(OnboardingViewModel.Step.allCases.count) 步")
    }

    // MARK: - 步骤内容

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .welcome:
            OnboardingWelcomeStep(viewModel: viewModel)
                .transition(stepTransition)
        case .permission:
            OnboardingPermissionStep(viewModel: viewModel)
                .transition(stepTransition)
        case .scan:
            OnboardingScanStep(viewModel: viewModel)
                .transition(stepTransition)
        case .createPet:
            OnboardingCreatePetStep(viewModel: viewModel)
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

    // MARK: - 底部主按钮（ActionPrimary 胶囊，每屏唯一主 CTA）

    private var footer: some View {
        VStack(spacing: Spacing.sm) {
            // 特征注册引导卡片自含操作按钮（开始注册/稍后再说），隐藏容器主按钮
            if !(viewModel.step == .createPet && viewModel.showFeatureRegistration) {
                Button(action: primaryAction) {
                    Text(primaryButtonTitle)
                        .font(.buttonLabel)
                        .foregroundStyle(Color.milensTextOnActionPrimary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.milensActionPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canAdvance)
                .opacity(canAdvance ? 1 : 0.5)
            }

            // 扫描步骤的辅助跳过入口：扫描中或扫描失败（未完成）时可用
            if viewModel.step == .scan, viewModel.isScanning || !viewModel.scanCompleted {
                Button("跳过扫描") {
                    viewModel.skipScan()
                }
                .font(.caption)
                .foregroundStyle(Color.milensTextSecondary)
                .frame(minHeight: Sizing.touchTarget)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.lg)
    }

    // MARK: - 按钮状态与动作

    private var canAdvance: Bool {
        switch viewModel.step {
        case .welcome:
            return viewModel.privacyAgreed
        case .permission:
            return !viewModel.isRequestingAuth
        case .scan:
            return viewModel.scanCompleted && !viewModel.isScanning
        case .createPet:
            return !viewModel.petName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var primaryButtonTitle: String {
        switch viewModel.step {
        case .welcome: return "开始"
        case .permission: return viewModel.isRequestingAuth ? "请求中..." : "继续"
        case .scan: return "继续"
        case .createPet: return "创建档案"
        }
    }

    private func primaryAction() {
        switch viewModel.step {
        case .welcome:
            viewModel.goToNextStep()
        case .permission:
            // 请求授权后前进（拒绝也允许继续，可在系统设置补授权）
            Task {
                await viewModel.requestPhotoAuthorization()
                viewModel.goToNextStep()
            }
        case .scan:
            viewModel.goToNextStep()
        case .createPet:
            viewModel.submitCreatePet()
        }
    }
}
