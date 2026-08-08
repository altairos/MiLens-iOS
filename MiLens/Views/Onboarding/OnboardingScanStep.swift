//  OnboardingScanStep —— 首次启动 Step 3 扫描页（UI-DESIGN.md §6.1）。
//  避免工具化表达：不显示「正在分析 10000 张照片」，改为「正在寻找它的身影...」。
//  状态图标中性细线，功能色（Success/Warning）只表达状态；发现计数用记忆标记
//  （6pt 珊瑚点，§2.1 允许出现在扫描完成）。文楷标题每屏唯一。
//  扫描只筛选不入库（DESIGN.md §7），由 OnboardingViewModel 编排 ScanService。

import SwiftUI

struct OnboardingScanStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer(minLength: Spacing.xxl)

            // 状态图标（固定高度，状态切换不抖动）
            Group {
                if viewModel.isScanning {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Color.milensTextSecondary)
                } else if viewModel.scanCompleted, !viewModel.scanError.isEmpty {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color.milensWarning)
                } else if viewModel.scanCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color.milensSuccess)
                } else {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }
            .frame(height: 48)

            // 主文案（避免工具化表达；本屏唯一文楷）
            VStack(spacing: Spacing.md) {
                Text(mainTitle)
                    .font(.displayMedium)
                    .foregroundStyle(Color.milensTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(mainSubtitle)
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .multilineTextAlignment(.center)
            }

            // 发现统计：记忆标记 + 圆体数字（§2.1 扫描完成品牌瞬间）
            if viewModel.scanFoundCount > 0 {
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(Color.milensPrimary)
                        .frame(width: 6, height: 6)
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
        .padding(.horizontal, Spacing.pagePad)
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
