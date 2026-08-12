//  WorkshopComponents —— Figma「15 · Image Workshop」系列页面的可复用编辑式组件。
//
//  对照 Figma `422:852 Image Workshop · Component Source`：
//  - CopperIndexBar：面板顶部铜色索引条（fill_42d9b282）
//  - WorkshopValueRail：调色/字号数值滑杆（Control/Workshop Value Rail）
//  - CreationActionBar：主+次统一操作栏（Action/Creation Output Register）
//  - EditorialOverline / WorkshopPanelHeader：编辑式小标与面板头
//
//  这些组件统一了编辑器面板、分享预览、创作系列的视觉语言，减少逐页重复实现。

import SwiftUI
import MiLensKit

// MARK: - Overline 小标

/// Figma `MiLens/UI/Overline`：10pt Medium + letterSpacing 0.04em。
/// 用于「CREATION DARKROOM」「READY TO KEEP」「PET CARD」等编辑式小标。
struct EditorialOverline: View {
    let text: String
    var color: Color = .milensActionPrimary

    var body: some View {
        Text(text)
            .font(.editorialOverline)
            .tracking(0.4)
            .foregroundStyle(color)
            .textCase(.uppercase)
    }
}

// MARK: - 铜色索引条

/// 面板顶部 2pt 高铜色细条（Figma `Copper Index` fill_42d9b282）。
/// 作为编辑器面板、分享面板的统一视觉锚点。
struct CopperIndexBar: View {
    var body: some View {
        Rectangle()
            .fill(Color.milensActionPrimary)
            .frame(height: 2)
    }
}

// MARK: - 面板头（铜色索引条 + 标题）

/// 编辑器面板统一外壳：铜色索引条 + 标题行（标题 + 可选副标题/动作按钮）。
struct WorkshopPanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            CopperIndexBar()
            HStack {
                Text(title)
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                trailing()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xs)
        }
    }
}

extension WorkshopPanelHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - 数值滑杆（WorkshopValueRail）

/// WorkshopValueRail 的显示状态。
enum WorkshopRailState {
    /// 默认：未修改，Track Active 段用浅灰。
    case `default`
    /// 已修改：Label SemiBold，Track Active 段铜色，Thumb 铜色。
    case changed
    /// 禁用：整体灰。
    case disabled
}

/// 调色/字号数值滑杆（Figma `Control/Workshop Value Rail`）。
///
/// 结构 = Label（左）+ Track（Remaining 灰底 + Active 段）+ Thumb（圆点）+ Value 数值（右）。
/// 替换原生 `Slider`，提供编辑式视觉（双段 Track + 数值标）。
struct WorkshopValueRail: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let state: WorkshopRailState
    var onChange: (Double, EditorSliderGesturePhase) -> Void
    /// 是否为中点归零（如色温 -100...100，中点 0）；true 时 Active 段从中点延伸。
    var bipolar: Bool = false

    /// 当前拖动是否已开始（用于首次 onChanged 发送 .begin 相位）。
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text(label)
                .font(state == .changed ? .system(size: 14, weight: .semibold) : .system(size: 14))
                .foregroundStyle(labelColor)
                .frame(width: 44, alignment: .leading)

            GeometryReader { geo in
                let trackH: CGFloat = 4
                let thumbSize: CGFloat = 16
                let progress = normalizedProgress
                ZStack(alignment: .leading) {
                    // Remaining 底轨
                    Capsule()
                        .fill(trackRemainingColor)
                        .frame(height: trackH)
                        .frame(maxWidth: .infinity)
                    // Active 段
                    activeTrack(progress: progress, width: geo.size.width)
                    // Thumb
                    Circle()
                        .fill(thumbColor)
                        .frame(width: thumbSize, height: thumbSize)
                        .overlay {
                            if state == .disabled {
                                Circle().stroke(Color.milensBorder, lineWidth: 2)
                            }
                        }
                        .offset(x: thumbOffset(progress: progress, trackWidth: geo.size.width, thumbSize: thumbSize))
                }
                .frame(height: max(trackH, thumbSize))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let ratio = min(max(v.location.x / geo.size.width, 0), 1)
                            let newValue = range.lowerBound + ratio * (range.upperBound - range.lowerBound)
                            if !isDragging {
                                isDragging = true
                                onChange(newValue, .begin)
                            }
                            onChange(newValue, .moving)
                        }
                        .onEnded { _ in
                            isDragging = false
                            onChange(value, .end)
                        }
                )
            }
            .frame(height: 20)

            Text(formattedValue)
                .font(.editorialMetadata.monospacedDigit())
                .foregroundStyle(valueColor)
                .frame(width: 36, alignment: .trailing)
        }
        .opacity(state == .disabled ? 0.4 : 1)
    }

    // MARK: - 计算

    private var normalizedProgress: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (value - range.lowerBound) / span
    }

    private func thumbOffset(progress: Double, trackWidth: CGFloat, thumbSize: CGFloat) -> CGFloat {
        CGFloat(progress) * trackWidth - thumbSize / 2
    }

    @ViewBuilder
    private func activeTrack(progress: Double, width: CGFloat) -> some View {
        if bipolar {
            // 双极：Active 段从中点(0.5)向当前值延伸
            let mid: Double = 0.5
            let startX = CGFloat(min(mid, progress)) * width
            let endX = CGFloat(max(mid, progress)) * width
            Capsule()
                .fill(trackActiveColor)
                .frame(height: 4)
                .frame(width: endX - startX)
                .offset(x: startX)
        } else {
            Capsule()
                .fill(trackActiveColor)
                .frame(height: 4)
                .frame(width: CGFloat(progress) * width)
        }
    }

    private var labelColor: Color {
        switch state {
        case .disabled: return .milensTextTertiary
        default: return .milensTextPrimary
        }
    }

    private var trackRemainingColor: Color {
        state == .disabled ? .milensBorder.opacity(0.5) : .milensBorder
    }

    private var trackActiveColor: Color {
        switch state {
        case .changed: return .milensActionPrimary
        case .disabled: return .milensBorder
        default: return .milensTextSecondary.opacity(0.4)
        }
    }

    private var thumbColor: Color {
        switch state {
        case .changed: return .milensActionPrimary
        case .disabled: return .milensGrouped
        default: return .milensCard
        }
    }

    private var valueColor: Color {
        switch state {
        case .changed: return .milensActionPrimary
        case .disabled: return .milensTextTertiary
        default: return .milensTextSecondary
        }
    }

    /// 数值格式化：+08 / −04 / 0 / +12（Figma 样式，两位补零，带正负号）。
    private var formattedValue: String {
        formatAdjustValueLabel(value)
    }
}

// MARK: - 统一操作栏（CreationActionBar）

/// Figma `Action/Creation Output Register`（342×60）：左次按钮 + 中分隔线 + 右主按钮铜色板。
struct CreationActionBar: View {
    let primaryLabel: String
    let secondaryLabel: String
    var primaryAction: () -> Void
    var secondaryAction: () -> Void
    var primaryEnabled: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            // 次按钮（左半，浅底）
            Button(action: secondaryAction) {
                Text(secondaryLabel)
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
            }
            .buttonStyle(.plain)

            // 分隔线
            Rectangle()
                .fill(Color.milensSeparator)
                .frame(width: 1, height: 36)

            // 主按钮（右半，铜色板）
            Button(action: primaryAction) {
                Text(primaryLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.milensTextOnActionPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(primaryEnabled ? Color.milensActionPrimary : Color.milensBorder)
            }
            .buttonStyle(.plain)
            .disabled(!primaryEnabled)
        }
        .frame(height: 60)
        .background(Color.milensAccentWash)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        }
    }
}

// MARK: - 数值格式化纯函数（可单测）

/// 将调整值格式化为 Figma 样式数值标（+08 / −04 / 0）。
/// 抽出为模块级函数便于单测。
func formatAdjustValueLabel(_ value: Double) -> String {
    let rounded = Int(value.rounded())
    if rounded > 0 { return String(format: "+%02d", abs(rounded)) }
    if rounded < 0 { return String(format: "−%02d", abs(rounded)) }
    return "0"
}
