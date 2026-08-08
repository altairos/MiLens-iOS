//  OnboardingView —— 首次启动引导容器（对应 iOS 设计稿「二、首次启动流程」）。
//  步骤：欢迎 → 权限说明 → 扫描 → 创建第一份档案。
//  权限步骤点击继续时先请求授权（拒绝也可继续，可在系统设置补授权）；
//  扫描步骤进入时自动开始（复用 ScanService，只筛选不入库）。
//  依赖由 MiLensApp 组合根构造注入。

import SwiftUI

struct OnboardingView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            stepContent
            footer
        }
        .background(Color.milensBackground)
        .onChange(of: viewModel.step) { _, _ in
            viewModel.onStepAppear()
        }
        .task {
            // 首次进入若已在扫描步骤（例如 App 重建恢复），自动启动
            viewModel.onStepAppear()
        }
    }

    // MARK: - 顶部：后退 + 步骤指示

    private var header: some View {
        HStack {
            if viewModel.step != .welcome {
                Button {
                    viewModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.bodyPrimary)
                        .foregroundStyle(Color.milensTextPrimary)
                        .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
                }
            }
            Spacer()
            Text("\(viewModel.step.rawValue + 1) / \(OnboardingViewModel.Step.allCases.count)")
                .font(.caption)
                .foregroundStyle(Color.milensTextTertiary)
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, Spacing.md)
    }

    // MARK: - 步骤内容

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .welcome:
            OnboardingWelcomeStep(viewModel: viewModel)
                .transition(.opacity)
        case .permission:
            OnboardingPermissionStep(viewModel: viewModel)
                .transition(.opacity)
        case .scan:
            OnboardingScanStep(viewModel: viewModel)
                .transition(.opacity)
        case .createPet:
            OnboardingCreatePetStep(viewModel: viewModel)
                .transition(.opacity)
        }
    }

    // MARK: - 底部主按钮

    private var footer: some View {
        VStack(spacing: Spacing.sm) {
            // 特征注册引导卡片自含操作按钮（开始注册/稍后再说），隐藏容器主按钮
            if !(viewModel.step == .createPet && viewModel.showFeatureRegistration) {
                Button(action: primaryAction) {
                    Text(primaryButtonTitle)
                        .font(.buttonLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.milensPrimary)
                .disabled(!canAdvance)
            }

            // 扫描步骤的辅助跳过入口：扫描中或扫描失败（未完成）时可用
            if viewModel.step == .scan, viewModel.isScanning || !viewModel.scanCompleted {
                Button("跳过扫描") {
                    viewModel.skipScan()
                }
                .font(.caption)
                .foregroundStyle(Color.milensTextSecondary)
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
