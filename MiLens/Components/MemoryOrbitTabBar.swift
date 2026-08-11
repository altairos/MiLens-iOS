//  MemoryOrbitTabBar —— MiLens 主导航的「记忆轨道」矢量组件。
//  几何来自 Figma Navigation/Tab Bar（Direction D）：无可见文字，四个 56pt 触控区；
//  选中态以开放轨道和端点表达「回忆正在生长」，未选中态保留一枚记忆点。

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
        .frame(maxWidth: Layout.maxWidth)
        .frame(height: Sizing.tabBarHeight)
        .background(
            Color.milensCard,
            in: RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        )
        .elevation(Elevation.medium)
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
        static let maxWidth: CGFloat = 350
        static let horizontalPadding: CGFloat = 18
        static let buttonSize: CGFloat = 56
        static let cornerRadius: CGFloat = 28
    }
}

/// 固定 56×56 坐标系，避免 SF Symbols 在不同 OS 版本产生轮廓漂移。
private struct MemoryOrbitTabIcon: View {
    let tab: AppTab
    let isSelected: Bool

    var body: some View {
        Canvas { context, _ in
            if isSelected {
                context.stroke(
                    orbitPath,
                    with: .color(Color.milensPrimary),
                    style: StrokeStyle(
                        lineWidth: 3.4,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                context.fill(activeEndpoint, with: .color(Color.milensActionPrimary))
            } else {
                context.fill(memoryMarker, with: .color(Color.milensMemoryMarker))
            }

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
    }

    private var orbitPath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 13.2, y: 14.1))
        path.addCurve(
            to: CGPoint(x: 13.8, y: 42.4),
            control1: CGPoint(x: 5.3, y: 21.1),
            control2: CGPoint(x: 5.5, y: 34.8)
        )
        path.addCurve(
            to: CGPoint(x: 43.2, y: 40.7),
            control1: CGPoint(x: 22.2, y: 50.1),
            control2: CGPoint(x: 35.7, y: 49.4)
        )
        path.addCurve(
            to: CGPoint(x: 42.8, y: 15.1),
            control1: CGPoint(x: 49.7, y: 33.2),
            control2: CGPoint(x: 49.0, y: 22.3)
        )
        return path
    }

    private var activeEndpoint: Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 39.9, y: 12.2, width: 5.8, height: 5.8))
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
            MemoryOrbitTabBar(selection: $selection)
                .padding(Spacing.xl)
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
