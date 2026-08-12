//  MemoryOrbitTabBar —— MiLens 主导航的「记忆轨道」矢量组件。
//
//  对照 Figma Navigation/Memory Orbit（#272:582）与 UI-DESIGN.md §5.4：
//  - 贴底安全区材质平面（不再使用 350×70 悬浮胶囊）
//  - 四项无文字矢量图标，56×56pt 触控区
//  - 选中态 = 图标上方 20pt 精确深铜红短刻度 + 开放记忆轨道 + 端点
//  - 轨道以三层精确矢量弧叠加形成连续锥度（右深粗 → 左浅细）
//  - 选择变化时三层弧在 ~0.34-0.38s 依次 path trim；Reduce Motion 直接显示最终态
//
//  代码必须读取真实 safe area，不硬编码设备底部高度（§5.4）。

import SwiftUI

struct MemoryOrbitTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabButton(tab)

                if tab != AppTab.allCases.last {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: Sizing.tabBarHeight)
        .background(.bar)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab

        return Button {
            selection = tab
        } label: {
            MemoryOrbitTabIcon(tab: tab, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .frame(width: Layout.buttonSize, height: Layout.buttonSize)
        .contentShape(Rectangle())
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier(tab.accessibilityIdentifier)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private enum Layout {
        static let horizontalPadding: CGFloat = 18
        static let buttonSize: CGFloat = 56
    }
}

/// 固定 56×56 坐标系，避免 SF Symbols 在不同 OS 版本产生轮廓漂移。
///
/// 选中态三层结构（对照 UI-DESIGN.md §5.4）：
/// 1. 图标上方 20pt 精确深铜红短刻度（不使用渐变、不参与动画）
/// 2. 开放记忆轨道——三层矢量弧叠加，右深粗 → 左浅细连续锥度
/// 3. 右端点（深铜色圆点）
private struct MemoryOrbitTabIcon: View {
    let tab: AppTab
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 轨道动效进度（0=未选中空轨道，1=完全展开）。
    @State private var orbitProgress: Double = 0

    var body: some View {
        Canvas { context, _ in
            if isSelected {
                // 短刻度（不参与动画，即时显示）
                let tickRect = CGRect(x: 18, y: 6, width: 20, height: 2.5)
                context.fill(
                    Path(roundedRect: tickRect, cornerRadius: 1.25),
                    with: .color(Color.milensDialSurface)
                )

                // 三层矢量弧叠加形成连续锥度
                drawOrbitArcs(context: context, progress: orbitProgress)

                // 右端点（深铜色）
                if orbitProgress > 0.3 {
                    let endpointOpacity = min((orbitProgress - 0.3) / 0.4, 1.0)
                    let endpointScale = 0.7 + 0.3 * endpointOpacity
                    let cx = 40.6 + (1 - endpointScale) * 2.9
                    let cy = 12.6 + (1 - endpointScale) * 2.9
                    let size = 5.8 * endpointScale
                    context.fill(
                        Path(ellipseIn: CGRect(x: cx, y: cy, width: size, height: size)),
                        with: .color(Color.milensDialSurface.opacity(endpointOpacity))
                    )
                }
            } else {
                // 未选中：一枚记忆点
                context.fill(memoryMarker, with: .color(Color.milensMemoryMarker))
            }

            // glyph（始终显示）
            context.stroke(
                glyphPath,
                with: .color(isSelected ? Color.milensActionPrimary : Color.milensTextSecondary),
                style: StrokeStyle(
                    lineWidth: isSelected ? 1.75 : 1.65,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
        .onAppear { syncProgress() }
        .onChange(of: isSelected) { _, _ in animateProgress() }
    }

    /// 初次出现时同步进度（避免已选中 tab 从 0 动画）。
    private func syncProgress() {
        orbitProgress = isSelected ? 1 : 0
    }

    /// 选择变化时驱动 path trim 动效。
    private func animateProgress() {
        if reduceMotion {
            orbitProgress = isSelected ? 1 : 0
            return
        }
        withAnimation(.easeOut(duration: 0.36)) {
            orbitProgress = isSelected ? 1 : 0
        }
    }

    // MARK: - 三层轨道弧（连续锥度：右深粗 → 左浅细）

    /// 使用三层不同 opacity/lineWidth 的弧叠加，从右向左同时降低颜色深度、透明度与线宽。
    /// progress 控制弧的展开程度（path trim 效果）。
    private func drawOrbitArcs(context: GraphicsContext, progress: Double) {
        // 第一层（右段，最深最粗）
        context.stroke(
            orbitLayer1,
            with: .color(Color.milensDialSurface.opacity(0.95 * progress)),
            style: StrokeStyle(lineWidth: 3.4 * progress, lineCap: .round, lineJoin: .round)
        )
        // 第二层（中段，中等）
        let midProgress = max(0, (progress - 0.1) / 0.9)
        context.stroke(
            orbitLayer2,
            with: .color(Color.milensDialSurface.opacity(0.62 * midProgress)),
            style: StrokeStyle(lineWidth: 2.4 * midProgress, lineCap: .round, lineJoin: .round)
        )
        // 第三层（左段，最浅最细）
        let farProgress = max(0, (progress - 0.2) / 0.8)
        context.stroke(
            orbitLayer3,
            with: .color(Color.milensDialSurface.opacity(0.32 * farProgress)),
            style: StrokeStyle(lineWidth: 1.6 * farProgress, lineCap: .round, lineJoin: .round)
        )
    }

    /// 右段弧（最深粗）：从顶部端点向右下方延伸。
    private var orbitLayer1: Path {
        var path = Path()
        path.move(to: CGPoint(x: 43.2, y: 16.0))
        path.addCurve(
            to: CGPoint(x: 43.2, y: 40.7),
            control1: CGPoint(x: 49.7, y: 28.0),
            control2: CGPoint(x: 49.0, y: 34.0)
        )
        return path
    }

    /// 中段弧（中等）：底部弧线。
    private var orbitLayer2: Path {
        var path = Path()
        path.move(to: CGPoint(x: 43.2, y: 40.7))
        path.addCurve(
            to: CGPoint(x: 18.0, y: 38.0),
            control1: CGPoint(x: 35.7, y: 49.4),
            control2: CGPoint(x: 26.0, y: 46.5)
        )
        return path
    }

    /// 左段弧（最浅细）：从左下向左上收口。
    private var orbitLayer3: Path {
        var path = Path()
        path.move(to: CGPoint(x: 18.0, y: 38.0))
        path.addCurve(
            to: CGPoint(x: 20.5, y: 16.5),
            control1: CGPoint(x: 10.0, y: 29.5),
            control2: CGPoint(x: 11.0, y: 20.5)
        )
        return path
    }

    private var memoryMarker: Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 37.95, y: 15.45, width: 3.1, height: 3.1))
        return path
    }

    private var glyphPath: Path {
        switch tab {
        case .home: return homePath
        case .pets: return petsPath
        case .create: return createPath
        case .settings: return settingsPath
        }
    }

    private var homePath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 20.5, y: 27.2))
        path.addLine(to: CGPoint(x: 28.0, y: 21.5))
        path.addLine(to: CGPoint(x: 35.5, y: 27.2))
        path.addLine(to: CGPoint(x: 35.5, y: 35.5))
        path.addLine(to: CGPoint(x: 20.5, y: 35.5))
        path.closeSubpath()
        path.move(to: CGPoint(x: 25.2, y: 35.5))
        path.addLine(to: CGPoint(x: 25.2, y: 29.8))
        path.addLine(to: CGPoint(x: 30.8, y: 29.8))
        path.addLine(to: CGPoint(x: 30.8, y: 35.5))
        return path
    }

    private var petsPath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 21.7, y: 26.2))
        path.addLine(to: CGPoint(x: 22.7, y: 22.0))
        path.addLine(to: CGPoint(x: 26.1, y: 24.3))
        path.addLine(to: CGPoint(x: 29.9, y: 24.3))
        path.addLine(to: CGPoint(x: 33.3, y: 22.0))
        path.addLine(to: CGPoint(x: 34.3, y: 26.2))
        path.addCurve(
            to: CGPoint(x: 36.0, y: 30.3),
            control1: CGPoint(x: 35.3, y: 27.2),
            control2: CGPoint(x: 36.0, y: 28.7)
        )
        path.addCurve(
            to: CGPoint(x: 28.0, y: 36.3),
            control1: CGPoint(x: 36.0, y: 33.9),
            control2: CGPoint(x: 32.8, y: 36.3)
        )
        path.addCurve(
            to: CGPoint(x: 20.0, y: 30.3),
            control1: CGPoint(x: 23.2, y: 36.3),
            control2: CGPoint(x: 20.0, y: 33.9)
        )
        path.addCurve(
            to: CGPoint(x: 21.7, y: 26.2),
            control1: CGPoint(x: 20.0, y: 28.7),
            control2: CGPoint(x: 20.7, y: 27.2)
        )
        path.closeSubpath()

        path.move(to: CGPoint(x: 24.8, y: 29.7))
        path.addLine(to: CGPoint(x: 24.81, y: 29.7))
        path.move(to: CGPoint(x: 31.2, y: 29.7))
        path.addLine(to: CGPoint(x: 31.21, y: 29.7))
        path.move(to: CGPoint(x: 26.4, y: 32.6))
        path.addCurve(
            to: CGPoint(x: 29.6, y: 32.6),
            control1: CGPoint(x: 27.4, y: 33.4),
            control2: CGPoint(x: 28.6, y: 33.4)
        )
        return path
    }

    private var createPath: Path {
        var path = Path()
        path.addRect(CGRect(x: 22.0, y: 22.2, width: 13.5, height: 13.3))
        path.move(to: CGPoint(x: 20.5, y: 33.2))
        path.addLine(to: CGPoint(x: 20.5, y: 20.5))
        path.addLine(to: CGPoint(x: 33.3, y: 20.5))
        path.move(to: CGPoint(x: 29.6, y: 25.0))
        path.addLine(to: CGPoint(x: 30.4, y: 27.0))
        path.addLine(to: CGPoint(x: 32.4, y: 27.8))
        path.addLine(to: CGPoint(x: 30.4, y: 28.6))
        path.addLine(to: CGPoint(x: 29.6, y: 30.6))
        path.addLine(to: CGPoint(x: 28.8, y: 28.6))
        path.addLine(to: CGPoint(x: 26.8, y: 27.8))
        path.addLine(to: CGPoint(x: 28.8, y: 27.0))
        path.closeSubpath()
        return path
    }

    private var settingsPath: Path {
        var path = Path()
        path.addRect(CGRect(x: 20.5, y: 21.2, width: 15.0, height: 13.6))
        path.move(to: CGPoint(x: 24.0, y: 21.2))
        path.addLine(to: CGPoint(x: 24.0, y: 34.8))
        path.addEllipse(in: CGRect(x: 27.7, y: 23.9, width: 4.2, height: 4.2))
        path.move(to: CGPoint(x: 26.8, y: 32.2))
        path.addCurve(
            to: CGPoint(x: 29.8, y: 29.0),
            control1: CGPoint(x: 27.4, y: 30.1),
            control2: CGPoint(x: 28.4, y: 29.0)
        )
        path.addCurve(
            to: CGPoint(x: 32.8, y: 32.2),
            control1: CGPoint(x: 31.2, y: 29.0),
            control2: CGPoint(x: 32.2, y: 30.1)
        )
        return path
    }
}

private struct MemoryOrbitTabBarPreview: View {
    @State private var selection: AppTab

    init(selection: AppTab) {
        _selection = State(initialValue: selection)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.milensBackground.ignoresSafeArea()
            Text("内容区")
                .font(.titleStandard)
            MemoryOrbitTabBar(selection: $selection)
        }
    }
}

#Preview("Memory Orbit · Light") {
    MemoryOrbitTabBarPreview(selection: .home)
}

#Preview("Memory Orbit · Dark") {
    MemoryOrbitTabBarPreview(selection: .pets)
        .preferredColorScheme(.dark)
}
