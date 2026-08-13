//  ScanLine —— 共享扫描线组件（扫描中/生成中的视觉进度线）。
//
//  对照 Figma 扫描线（Onboarding Full Scan #47:9、Album Scan Stage #29:14、
//  拼豆 Processing Visual #91:385）与 UI-DESIGN.md §4（动效）。
//
//  收敛三处历史实现的共性问题：
//  - 缓动统一为 easeInOut 往返（避免 linear + autoreverses 在端点瞬间反向的「折返感」）
//  - 去除逐帧重绘的发光阴影（合成器友好的纯填充线）
//  - 尊重 Reduce Motion：静止显示顶线，不挂持续运动动画
//  - 由 isActive 驱动，onDisappear 停止，避免切 Tab/离屏后空转

import SwiftUI

struct ScanLine: View {
    /// 线色（历史各处分别用 milensPrimary / milensActionPrimary）。
    var color: Color = Color.milensActionPrimary
    /// 左右内缩（线宽 = 容器宽 - 2×horizontalInset）。
    var horizontalInset: CGFloat = 74
    /// 距底部停止边距（行程 = 容器高 - bottomInset）。
    var bottomInset: CGFloat = 170
    /// 是否在扫描中；false 或 Reduce Motion 时静止。
    var isActive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 行程进度（0=顶部起点，1=底部终点），供 offset 线性映射。
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let travel = max(0, geo.size.height - bottomInset)
            let lineWidth = max(0, geo.size.width - horizontalInset * 2)
            Rectangle()
                .fill(color)
                .frame(width: lineWidth, height: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))
                .offset(x: horizontalInset, y: travel * progress)
        }
        .allowsHitTesting(false)
        .onAppear { startAnimation() }
        .onChange(of: isActive) { _, _ in startAnimation() }
        .onChange(of: reduceMotion) { _, _ in startAnimation() }
        .onDisappear { progress = 0 }
    }

    private func startAnimation() {
        guard isActive, !reduceMotion else {
            progress = 0
            return
        }
        progress = 0
        withAnimation(.easeInOut(duration: Motion.durationScan).repeatForever(autoreverses: true)) {
            progress = 1
        }
    }
}
