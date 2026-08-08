//  EditorToolPanels —— 编辑器底部面板（对应源端 EditorPage.ets 底部工具区）。
//  结构：底部 dock（调整/智能/装饰三组）→ 组内工具行（group != .none 时）→ 工具面板（tool 激活时）。
//  工具面板：裁剪（比例 chips + 取消/确认）、旋转/翻转、调色（5 滑块 + 重置）、
//  文字（添加/选中编辑）、抠图（状态 + 开始/重试）。
//  V1.0 差异：贴纸/相框无素材资源不展示；拼豆（bead）工具由图纸页并行实现，本编辑器不重复入口。

import SwiftUI
import MiLensKit

// MARK: - 底部 dock

/// 底部工具组 dock（对应源端底部 tab 区）。
struct EditorDockView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        HStack {
            dockButton(group: .adjust, icon: "slider.horizontal.3", label: "调整")
            dockButton(group: .smart, icon: "wand.and.stars", label: "智能")
            dockButton(group: .decorate, icon: "textformat", label: "装饰")
        }
        .padding(.vertical, Spacing.sm)
        .background(.black)
        .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(0.15)) }
    }

    private func dockButton(group: EditorToolGroup, icon: String, label: String) -> some View {
        Button {
            viewModel.selectGroup(group)
        } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: Sizing.iconLg))
                Text(label)
                    .font(Font.caption)
            }
            .foregroundStyle(viewModel.isGroupActive(group) ? Color.milensPrimary : Color.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - 组内工具行

/// 组内工具选择行（对应源端组展开后的工具列表）。
struct EditorGroupToolRow: View {
    @Bindable var viewModel: EditorViewModel
    let group: EditorToolGroup

    var body: some View {
        HStack(spacing: Spacing.md) {
            ForEach(tools, id: \.0) { tool, icon, label in
                toolButton(tool: tool, icon: icon, label: label)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(.black)
    }

    /// 组内工具列表（V1.0 无贴纸/相框素材，不展示；bead 由图纸页并行实现）。
    private var tools: [(EditorToolMode, String, String)] {
        switch group {
        case .adjust: return [(.crop, "crop", "裁剪"), (.rotate, "rotate.right", "旋转"), (.adjust, "slider.horizontal.3", "调色")]
        case .smart: return [(.cutout, "scissors", "抠图")]
        case .decorate: return [(.text, "textformat", "文字")]
        case .create, .none: return []
        }
    }

    private func toolButton(tool: EditorToolMode, icon: String, label: String) -> some View {
        Button {
            viewModel.selectTool(tool)
        } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: Sizing.iconMd))
                Text(label)
                    .font(Font.caption)
            }
            .foregroundStyle(viewModel.tool == tool ? Color.milensPrimary : Color.white.opacity(0.85))
            .frame(minWidth: Sizing.touchTarget)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - 工具面板容器

/// 面板区：工具激活时显示对应面板，否则显示组内工具行。
struct EditorPanelArea: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        Group {
            switch viewModel.tool {
            case .crop: EditorCropPanelView(viewModel: viewModel)
            case .rotate: EditorRotatePanelView(viewModel: viewModel)
            case .adjust: EditorAdjustPanelView(viewModel: viewModel)
            case .text: EditorTextPanelView(viewModel: viewModel)
            case .cutout: EditorCutoutPanelView(viewModel: viewModel)
            case .frame, .sticker, .bead, .none:
                if viewModel.group != .none {
                    EditorGroupToolRow(viewModel: viewModel, group: viewModel.group)
                } else {
                    EmptyView()
                }
            }
        }
    }
}

// MARK: - 裁剪面板

/// 裁剪面板：比例 chips + 取消/确认（对应源端 cropRatioOptions + onConfirmCrop）。
struct EditorCropPanelView: View {
    @Bindable var viewModel: EditorViewModel

    private let labels = cropRatioLabels()

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(labels.indices, id: \.self) { index in
                        ratioChip(index: index, label: labels[index])
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
            HStack(spacing: Spacing.md) {
                Button("取消") { viewModel.cancelCrop() }
                    .buttonStyle(EditorPanelButtonStyle(role: .secondary))
                Button("确认") { viewModel.confirmCrop() }
                    .buttonStyle(EditorPanelButtonStyle(role: .primary))
            }
            .padding(.horizontal, Spacing.lg)
        }
        .padding(.vertical, Spacing.sm)
        .background(.black)
    }

    private func ratioChip(index: Int, label: String) -> some View {
        Button {
            viewModel.selectCropRatio(index)
        } label: {
            Text(label)
                .font(Font.caption)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    viewModel.cropRatioIndex == index
                        ? Color.milensPrimary.opacity(0.25)
                        : Color.white.opacity(0.12)
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(
                        viewModel.cropRatioIndex == index ? Color.milensPrimary : Color.clear,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(viewModel.cropRatioIndex == index ? Color.milensPrimary : Color.white)
    }
}

// MARK: - 旋转/翻转面板

/// 旋转/翻转面板：左旋/右旋（像素级）+ 水平/垂直翻转（属性级）。
struct EditorRotatePanelView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        HStack(spacing: Spacing.md) {
            rotateButton(icon: "rotate.left", label: "左旋") { viewModel.rotate(.ccw) }
            rotateButton(icon: "rotate.right", label: "右旋") { viewModel.rotate(.cw) }
            rotateButton(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", label: "水平翻转") {
                viewModel.flip(.horizontal)
            }
            rotateButton(icon: "arrow.up.and.down.righttriangle.up.righttriangle.down", label: "垂直翻转") {
                viewModel.flip(.vertical)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(.black)
    }

    private func rotateButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: Sizing.iconMd))
                Text(label)
                    .font(Font.caption)
            }
            .foregroundStyle(.white)
            .frame(minWidth: Sizing.touchTarget)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - 调色面板

/// 调色面板：亮度/对比度/饱和度/色温/锐化 5 滑块 + 重置（EditorAdjustLogic 驱动）。
struct EditorAdjustPanelView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: Spacing.sm) {
            adjustSlider(field: .brightness, label: "亮度", value: viewModel.adjustState.brightness, range: -100...100)
            adjustSlider(field: .contrast, label: "对比度", value: viewModel.adjustState.contrast, range: -100...100)
            adjustSlider(field: .saturation, label: "饱和度", value: viewModel.adjustState.saturation, range: -100...100)
            adjustSlider(field: .temperature, label: "色温", value: viewModel.adjustState.temperature, range: -100...100)
            adjustSlider(field: .sharpness, label: "锐化", value: viewModel.adjustState.sharpness, range: 0...100)

            Button("重置") { viewModel.resetAdjustments() }
                .font(Font.caption)
                .foregroundStyle(.white.opacity(0.85))
                .disabled(isAdjustNeutral(viewModel.adjustState))
                .opacity(isAdjustNeutral(viewModel.adjustState) ? 0.4 : 1)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(.black)
    }

    private func adjustSlider(field: EditorAdjustField, label: String, value: Double, range: ClosedRange<Double>) -> some View {
        HStack(spacing: Spacing.md) {
            Text(label)
                .font(Font.caption)
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 48, alignment: .leading)
            Slider(
                value: Binding(
                    get: { value },
                    set: { viewModel.onAdjustSliderChange(field, value: $0, phase: .moving) }
                ),
                in: range,
                onEditingChanged: { editing in
                    viewModel.onAdjustSliderChange(
                        field, value: value,
                        phase: editing ? .begin : .end
                    )
                }
            )
            .tint(.milensPrimary)
        }
    }
}

// MARK: - 文字面板

/// 文字面板：添加模式（输入 + 字号 + 颜色 + 描边 + 添加）或选中图层编辑模式。
struct EditorTextPanelView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        if viewModel.showTextLayerEditPanel {
            textLayerEditPanel
        } else {
            textAddPanel
        }
    }

    /// 添加模式（对应源端文本添加工具 UI）。
    private var textAddPanel: some View {
        VStack(spacing: Spacing.sm) {
            TextField("输入文字", text: $viewModel.textInput)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Radius.small))

            HStack(spacing: Spacing.md) {
                Text("字号")
                    .font(Font.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Slider(value: $viewModel.textFontSize, in: 12...96)
                    .tint(.milensPrimary)
                colorDots(selected: viewModel.textColor) { viewModel.textColor = $0 }
                Toggle("描边", isOn: $viewModel.textStrokeEnabled)
                    .font(Font.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .toggleStyle(.button)
                    .tint(.milensPrimary)
            }

            Button("添加到图片") { viewModel.addText() }
                .font(Font.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.sm)
                .background(canAdd ? Color.milensPrimary : Color.white.opacity(0.15))
                .clipShape(Capsule())
                .disabled(!canAdd)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(.black)
    }

    /// 选中文字图层编辑模式（字号/颜色，随手势合并入历史）。
    private var textLayerEditPanel: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Text("字号")
                    .font(Font.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Slider(
                    value: Binding(
                        get: { viewModel.selectedTextFontSize },
                        set: { viewModel.updateActiveText(fontSize: $0, color: viewModel.selectedTextColor) }
                    ),
                    in: 12...96,
                    onEditingChanged: { editing in
                        if editing {
                            viewModel.beginLayerGesture()
                        } else {
                            viewModel.endLayerGesture()
                        }
                    }
                )
                .tint(.milensPrimary)
                colorDots(selected: viewModel.selectedTextColor) {
                    viewModel.updateActiveText(fontSize: viewModel.selectedTextFontSize, color: $0)
                }
                Button {
                    viewModel.deleteActiveLayer()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("删除文字")
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(.black)
    }

    private var canAdd: Bool {
        canAddTextLayer(viewModel.textInput)
    }

    /// 固定色板（V1.0；对应源端颜色选择器基础色）。
    private func colorDots(selected: String, onPick: @escaping (String) -> Void) -> some View {
        HStack(spacing: Spacing.xs) {
            ForEach(EDITOR_TEXT_COLOR_PRESETS, id: \.self) { hex in
                colorDot(hex: hex, selected: selected == hex, onPick: onPick)
            }
        }
    }

    private func colorDot(hex: String, selected: Bool, onPick: @escaping (String) -> Void) -> some View {
        Button {
            onPick(hex)
        } label: {
            Circle()
                .fill(Color(hexString: hex) ?? .white)
                .frame(width: 22, height: 22)
                .overlay {
                    Circle().stroke(
                        selected ? Color.milensPrimary : Color.white.opacity(0.3),
                        lineWidth: selected ? 2 : 1
                    )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("颜色 \(hex)")
    }
}

// MARK: - 抠图面板

/// 抠图面板：状态文案 + 开始/重试（EditorCutoutLogic 驱动，失败即 error，无降级）。
struct EditorCutoutPanelView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(statusText)
                    .font(Font.caption)
                    .foregroundStyle(viewModel.cutoutPhase == .error ? .red : .white.opacity(0.85))
                if viewModel.cutoutPhase == .applied {
                    Text("保存后将以 PNG 格式保留透明背景")
                        .font(Font.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
            Button(actionLabel) {
                Task { await viewModel.startCutout() }
            }
            .font(Font.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.sm)
            .background(viewModel.cutoutPhase == .processing ? Color.white.opacity(0.15) : Color.milensPrimary)
            .clipShape(Capsule())
            .disabled(viewModel.cutoutPhase == .processing)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(.black)
    }

    private var statusText: String {
        viewModel.cutoutStatus.isEmpty ? cutoutStatusText(.idle) : viewModel.cutoutStatus
    }

    private var actionLabel: String {
        switch viewModel.cutoutPhase {
        case .processing: return "识别中…"
        case .applied: return "重新抠图"
        case .error: return "重试"
        case .idle: return "开始抠图"
        }
    }
}

// MARK: - 样式

/// 面板按钮样式（裁剪面板用）。
private struct EditorPanelButtonStyle: ButtonStyle {
    enum Role { case primary, secondary }
    let role: Role

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.caption)
            .foregroundStyle(role == .primary ? .white : .white.opacity(0.85))
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.sm)
            .background(role == .primary ? Color.milensPrimary : Color.white.opacity(0.15))
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 文字颜色预设（V1.0 固定色板）。
private let EDITOR_TEXT_COLOR_PRESETS: [String] = [
    "#FFFFFF", "#000000", "#FF3B30", "#FF9500", "#FFCC00",
    "#34C759", "#00C7BE", "#007AFF", "#5856D6", "#AF52DE",
]
