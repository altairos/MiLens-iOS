//  OnboardingScanStep —— 首次启动 Step 3 扫描页
//  （对应 iOS 设计稿「二、首次启动流程 Step 3」）。
//  避免工具化表达：不显示「正在分析 10000 张照片」，改为「正在寻找它的身影...」。
//  扫描只筛选不入库（DESIGN.md §7），由 OnboardingViewModel 编排 ScanService。

import SwiftUI

struct OnboardingScanStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer(minLength: 40)

            // 状态图标区
            ZStack {
                Circle()
                    .fill(Color.milensAccentSoft)
                    .frame(width: 96, height: 96)
                Group {
                    if viewModel.isScanning {
                        ProgressView()
                            .controlSize(.large)
                            .tint(Color.milensPrimary)
                    } else if viewModel.scanCompleted, !viewModel.scanError.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.milensWarning)
                    } else if viewModel.scanCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.milensPrimary)
                    } else {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.milensPrimary)
                    }
                }
            }

            // 主文案（设计稿 Step 3：避免工具化表达）
            VStack(spacing: Spacing.md) {
                Text(mainTitle)
                    .font(.displayMedium)
                Text(mainSubtitle)
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .multilineTextAlignment(.center)
            }

            // 发现统计
            if viewModel.scanFoundCount > 0 {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "pawprint.fill")
                        .foregroundStyle(Color.milensPrimary)
                    Text("发现 \(viewModel.scanFoundCount) 张宠物照片")
                        .font(.numberStat)
                        .foregroundStyle(Color.milensTextPrimary)
                }
            }

            Spacer()

            // 错误/跳过提示
            if !viewModel.scanError.isEmpty {
                Text(viewModel.scanError)
                    .font(.caption)
                    .foregroundStyle(Color.milensTextTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, Spacing.lg)
            }
        }
        .padding(.horizontal, Spacing.xxl)
    }

    private var mainTitle: String {
        if viewModel.isScanning { return "正在寻找它的身影..." }
        if viewModel.scanCompleted, !viewModel.scanError.isEmpty { return "扫描暂时没完成" }
        if viewModel.scanCompleted { return "扫描完成" }
        return "准备开始"
    }

    private var mainSubtitle: String {
        if viewModel.isScanning {
            return "正在浏览你的相册，寻找宠物的痕迹"
        }
        if viewModel.scanCompleted, !viewModel.scanError.isEmpty {
            return "你可以跳过扫描，稍后在相册页随时开始"
        }
        if viewModel.scanCompleted {
            return viewModel.scanFoundCount > 0
                ? "这些照片可以随时导入相册"
                : "没有发现宠物照片，可以先为它创建档案"
        }
        return "马上就好"
    }
}
