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

// MARK: - 页面导航头（WorkshopNavHeader）

/// 统一页面导航头（对照 Figma 02–11 标准 Navigation / Back + Title）。
/// 结构 = 返回圆(44×44) + uiTitle(20pt) + 可选右侧动作。
/// 用于创作成品页，替代系统 `.navigationTitle + .toolbar`。
struct WorkshopNavHeader<Trailing: View>: View {
    let title: String
    var onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.milensTextPrimary)
                    .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "a11y.editor.back"))

            Text(title)
                .font(.uiTitle)
                .foregroundStyle(Color.milensTextPrimary)
                .padding(.leading, 16)

            Spacer()

            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

extension WorkshopNavHeader where Trailing == EmptyView {
    init(title: String, onBack: @escaping () -> Void) {
        self.init(title: title, onBack: onBack) { EmptyView() }
    }
}

// MARK: - 来源照片条（WorkshopSourceBar）

/// 来源照片条（对照 Figma `Source / Xiao Man` #299:604）。
/// 结构 = 左缩略图 + 右三行（Overline Meta / BodyStrong Label / 更换动作）。
/// 圆角不对称 `8 0 18 8`，`milensGrouped` 底 + `milensBorder` 描边。
struct WorkshopSourceBar<ImageContent: View>: View {
    let meta: String
    let label: String
    var onChange: (() -> Void)? = nil
    @ViewBuilder var thumbnail: () -> ImageContent

    var body: some View {
        HStack(spacing: 12) {
            thumbnail()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                EditorialOverline(text: meta)
                Text(label)
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(1)
            }

            Spacer()

            if let onChange {
                Button(String(localized: "source.change"), action: onChange)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.milensActionPrimary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.milensGrouped)
        .overlay {
            // 不对称圆角（Figma borderRadius 8 0 18 8）
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(topLeading: 8, bottomLeading: 0, bottomTrailing: 18, topTrailing: 8),
                style: .continuous
            )
            .stroke(Color.milensBorder, lineWidth: 1)
        }
        .clipShape(UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(topLeading: 8, bottomLeading: 0, bottomTrailing: 18, topTrailing: 8),
            style: .continuous
        ))
    }
}

// MARK: - 模板单元（WorkshopTemplateTab）

/// 模板选择单元状态（对照 Figma `Control/Creation Template Tab`）。
enum WorkshopTemplateState {
    case `default`
    case selected
    case locked
}

/// 模板单元（对照 Figma `Control/Creation Template Tab` #463:1149）。
/// 三态：Default / Selected（铜描边 + 底部 Selection Slot）/ Locked（灰 + Pro Badge）。
struct WorkshopTemplateTab: View {
    let index: String
    let label: String
    let state: WorkshopTemplateState
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Text(index)
                        .font(.editorialNumberIndex)
                        .foregroundStyle(indexColor)
                    if state == .locked {
                        Text("PRO")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.milensActionPrimary)
                            .clipShape(Capsule())
                            .offset(x: 20, y: -22)
                    }
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(labelColor)
            }
            .frame(width: 78, height: 50)
            .background(background)
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(borderColor, lineWidth: state == .selected ? 1 : 0.5)
            }
            .overlay(alignment: .bottom) {
                if state == .selected {
                    Rectangle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 24, height: 2)
                        .padding(.bottom, 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(state == .locked)
    }

    private var indexColor: Color {
        switch state {
        case .selected: return .milensActionPrimary
        case .locked: return .milensTextSecondary
        default: return .milensTextSecondary
        }
    }

    private var labelColor: Color {
        switch state {
        case .selected: return .milensTextPrimary
        case .locked: return .milensTextTertiary
        default: return .milensTextPrimary
        }
    }

    private var background: Color {
        state == .selected ? Color.milensAccentWash : Color.milensCard
    }

    private var borderColor: Color {
        state == .selected ? Color.milensActionPrimary : Color.milensBorder
    }
}

// MARK: - 字段编辑行（WorkshopFieldRow）

/// 字段编辑行（对照 Figma 09/10 的 Label + 值 + 编辑 + Field Rule）。
/// 结构 = 左 Metadata Label + 中 BodyStrong 值 + 右 Caption「编辑」+ 底部 1pt 分隔。
struct WorkshopFieldRow: View {
    let label: String
    let value: String
    var onEdit: (() -> Void)? = nil
    /// 是否显示底部 Field Rule（默认 true，最后一行可关闭）。
    var showsRule: Bool = true

    var body: some View {
        Button {
            onEdit?()
        } label: {
            HStack(alignment: .center, spacing: 0) {
                Text(label)
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
                    .frame(width: 80, alignment: .leading)

                Text(value)
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if onEdit != nil {
                    Text(String(localized: "field.edit"))
                        .font(.caption)
                        .foregroundStyle(Color.milensActionPrimary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            if showsRule {
                Rectangle()
                    .fill(Color.milensSeparator)
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - 时间线步骤（WorkshopTimelineStep）

/// 上传指引时间线步骤（对照 Figma 11 Upload Guide Step Marker）。
/// 结构 = 左圆形 Marker(32×32, 编号) + 竖线 + 右标题(BodyStrong) + 说明(Metadata)。
struct WorkshopTimelineStep: View {
    let index: String
    let title: String
    let desc: String
    /// 是否已完成（圆形填铜色；否则白底描边）。
    var isCompleted: Bool = false
    /// 是否显示底部连接线。
    var showsConnector: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Marker + 竖线
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isCompleted ? Color.milensActionPrimary : Color.milensCard)
                        .overlay {
                            Circle().stroke(Color.milensActionPrimary, lineWidth: 1)
                        }
                    Text(index)
                        .font(.editorialNumberIndex)
                        .foregroundStyle(isCompleted ? Color.milensTextOnActionPrimary : Color.milensActionPrimary)
                }
                .frame(width: 32, height: 32)

                if showsConnector {
                    Rectangle()
                        .fill(Color.milensSeparator)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 32)

            // 文本
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(desc)
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 5)
            .padding(.bottom, showsConnector ? 16 : 0)

            Spacer(minLength: 0)
        }
    }
}
