//  EditorToolPanels —— 编辑器底部面板（对应源端 EditorPage.ets 底部工具区）。
//  结构：底部 dock（调整/智能/装饰三组）→ 组内工具行（group != .none 时）→ 工具面板（tool 激活时）。
//  工具面板：裁剪（比例 chips + 取消/确认）、旋转/翻转、调色（预设滤镜横滚条 + 手动 5 滑块）、
//  文字（添加/选中编辑）、抠图（状态 + 开始/重试）、装饰（相框/贴纸，EditorDecorationPanelView）。
//  V1.0 差异：贴纸/相框入口由 catalog 非空门禁（§10，空 catalog 不显示）；拼豆（bead）工具由图纸页并行实现。

import SwiftUI
import MiLensKit

// MARK: - 底部 dock

/// 底部工具组 dock（对应源端底部 tab 区）。
struct EditorDockView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        HStack {
            dockButton(group: .adjust, icon: "slider.horizontal.3", label: String(localized: "a11y.editor.adjust"))
            dockButton(group: .smart, icon: "wand.and.stars", label: String(localized: "a11y.editor.smart"))
            dockButton(group: .decorate, icon: "textformat", label: String(localized: "a11y.editor.decorate"))
        }
        .padding(.vertical, Spacing.xs)
        .background(Color.milensBackground)
        .overlay(alignment: .top) { Divider().overlay(Color.milensSeparator) }
    }

    private func dockButton(group: EditorToolGroup, icon: String, label: String) -> some View {
        let isActive = viewModel.isGroupActive(group)
        return Button {
            viewModel.selectGroup(group)
        } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: Sizing.iconLg))
                Text(label)
                    .font(Font.caption)
            }
            .foregroundStyle(isActive ? Color.milensActionPrimary : Color.milensTextSecondary)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                if isActive {
                    Rectangle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 32, height: 2)
                }
            }
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
        .background(Color.milensBackground)
    }

    /// 组内工具列表（decorate：文字 + 贴纸/相框，后两者由 catalog 非空门禁，§10；bead 由图纸页并行实现）。
    private var tools: [(EditorToolMode, String, String)] {
        switch group {
        case .adjust: return [(.crop, "crop", "裁剪"), (.rotate, "rotate.right", "旋转"), (.adjust, "slider.horizontal.3", "调色"), (.flip, "arrow.left.and.right.righttriangle.left.righttriangle.right", "翻转")]
        case .smart: return [(.cutout, "scissors", "抠图")]
        case .decorate:
            var list: [(EditorToolMode, String, String)] = [(.text, "textformat", "文字")]
            if viewModel.hasStickerItems { list.append((.sticker, "sticker", "贴纸")) }
            if viewModel.hasFrameItems { list.append((.frame, "photo.on.rectangle", "相框")) }
            return list
        case .create, .none: return []
        }
    }

    private func toolButton(tool: EditorToolMode, icon: String, label: String) -> some View {
        let isActive = viewModel.tool == tool
        return Button {
            viewModel.selectTool(tool)
        } label: {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: Sizing.iconMd))
                Text(label)
                    .font(Font.caption)
            }
            .foregroundStyle(isActive ? Color.milensActionPrimary : Color.milensTextSecondary)
            .frame(minWidth: Sizing.touchTarget)
            .overlay(alignment: .bottom) {
                if isActive {
                    Rectangle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 24, height: 2)
                }
            }
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
            case .rotate, .flip: EditorTransformPanelView(viewModel: viewModel)
            case .adjust: EditorAdjustPanelView(viewModel: viewModel)
            case .text: EditorTextPanelView(viewModel: viewModel)
            case .cutout: EditorCutoutPanelView(viewModel: viewModel)
            case .frame, .sticker: EditorDecorationPanelView(viewModel: viewModel)
            case .bead, .none:
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

/// 裁剪面板：铜索引头 + 构图比例行 + Transform Rail（旋转/翻转）。
/// 对照 Figma `04 · Editor / Crop` #422:817 Crop Controls。
struct EditorCropPanelView: View {
    @Bindable var viewModel: EditorViewModel

    private let labels = cropRatioLabels()

    var body: some View {
        VStack(spacing: 0) {
            WorkshopPanelHeader(title: String(localized: "editor.panel.crop"))

            // 比例选择行
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(labels.indices, id: \.self) { index in
                        ratioSlot(index: index, label: labels[index])
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
            }

            // Transform Rail（旋转/翻转，对照 Figma Transform Rail）
            EditorTransformRail(
                onRotateCCW: { viewModel.rotate(.ccw) },
                onRotateCW: { viewModel.rotate(.cw) },
                onFlipH: { viewModel.flip(.horizontal) },
                onFlipV: { viewModel.flip(.vertical) }
            )
            .padding(.top, Spacing.sm)

            // 确认/取消裁剪
            HStack(spacing: Spacing.md) {
                Button("取消") { viewModel.cropVM.cancelCrop() }
                    .buttonStyle(EditorPanelButtonStyle(role: .secondary))
                Button("确认") { viewModel.cropVM.confirmCrop() }
                    .buttonStyle(EditorPanelButtonStyle(role: .primary))
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.sm)
        }
        .background(Color.milensBackground)
    }

    /// 比例槽（文字 + 选中底部校准线），对照 Figma `Ratio Slot`。
    private func ratioSlot(index: Int, label: String) -> some View {
        let isSelected = viewModel.cropVM.cropRatioIndex == index
        return Button {
            viewModel.cropVM.selectCropRatio(index)
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.bodyPrimary)
                    .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextPrimary)
                Rectangle()
                    .fill(isSelected ? Color.milensActionPrimary : Color.clear)
                    .frame(width: 32, height: 2)
            }
            .frame(width: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 旋转/翻转面板（独立工具入口）

/// 旋转/翻转独立面板（`.rotate` / `.flip` 工具激活时）。
/// 对照 Figma Editor Tool Row 中 旋转/翻转 的 Transform Rail。
struct EditorTransformPanelView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            WorkshopPanelHeader(title: viewModel.tool == .rotate
                ? String(localized: "editor.panel.rotate")
                : String(localized: "editor.panel.flip"))
            EditorTransformRail(
                onRotateCCW: { viewModel.rotate(.ccw) },
                onRotateCW: { viewModel.rotate(.cw) },
                onFlipH: { viewModel.flip(.horizontal) },
                onFlipV: { viewModel.flip(.vertical) }
            )
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.sm)
        }
        .background(Color.milensBackground)
    }
}

// MARK: - Transform Rail（可复用旋转/翻转控件）

/// Transform Rail：左转/右转/水平/垂直 四格，带分隔线。
/// 对照 Figma `Transform Rail` #515:1039。
struct EditorTransformRail: View {
    var onRotateCCW: () -> Void
    var onRotateCW: () -> Void
    var onFlipH: () -> Void
    var onFlipV: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            transformCell(icon: "rotate.left", label: String(localized: "editor.transform.ccw"), action: onRotateCCW)
            transformDivider
            transformCell(icon: "rotate.right", label: String(localized: "editor.transform.cw"), action: onRotateCW)
            transformDivider
            transformCell(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", label: String(localized: "editor.transform.flipH"), action: onFlipH)
            transformDivider
            transformCell(icon: "arrow.up.and.down.righttriangle.up.righttriangle.down", label: String(localized: "editor.transform.flipV"), action: onFlipV)
        }
        .padding(.horizontal, Spacing.lg)
        .overlay(alignment: .top) { Divider().overlay(Color.milensSeparator) }
        .overlay(alignment: .bottom) { Divider().overlay(Color.milensSeparator) }
    }

    private func transformCell(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: Sizing.iconMd))
                Text(label)
                    .font(.editorialMetadata)
            }
            .foregroundStyle(Color.milensTextPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private var transformDivider: some View {
        Rectangle()
            .fill(Color.milensSeparator)
            .frame(width: 1, height: 32)
    }
}

// MARK: - 调色面板

/// 调色面板：铜索引头 + 调色 + 5 个 WorkshopValueRail + 重置。
/// 对照 Figma `03 · Editor / Adjust` #422:813 Adjustment Panel。
struct EditorAdjustPanelView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        @Bindable var adjustVM = viewModel.adjustVM
        VStack(spacing: 0) {
            WorkshopPanelHeader(title: String(localized: "editor.panel.adjust")) {
                Button(String(localized: "editor.adjust.reset")) { adjustVM.reset() }
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensActionPrimary)
                    .disabled(isAdjustNeutral(adjustVM.state))
                    .opacity(isAdjustNeutral(adjustVM.state) ? 0.4 : 1)
            }

            // 预设滤镜横滚条（主交互入口）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(PRESET_FILTERS) { preset in
                        filterCell(preset, adjustVM: adjustVM)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)
            }
            .overlay(alignment: .bottom) { Divider().overlay(Color.milensSeparator) }

            // 手动调整入口（默认折叠，点开才显示 5 滑块）
            manualAdjustToggle(adjustVM: adjustVM)

            if adjustVM.isSlidersExpanded {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        valueRail(field: .brightness, label: "亮度", value: adjustVM.state.brightness, range: -100...100)
                        valueRail(field: .contrast, label: "对比度", value: adjustVM.state.contrast, range: -100...100)
                        valueRail(field: .saturation, label: "饱和度", value: adjustVM.state.saturation, range: -100...100)
                        valueRail(field: .temperature, label: "色温", value: adjustVM.state.temperature, range: -100...100, bipolar: true)
                        valueRail(field: .sharpness, label: "锐化", value: adjustVM.state.sharpness, range: 0...100)
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.xs)
                    .padding(.bottom, Spacing.sm)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(Color.milensBackground)
    }

    /// 预设滤镜单元：缩略图(54×54) + 名称，选中态铜色描边。
    private func filterCell(_ preset: PresetFilter, adjustVM: EditorAdjustPanelVM) -> some View {
        let isSelected = adjustVM.selectedFilterID == preset.id
        return Button {
            adjustVM.applyPreset(preset)
        } label: {
            VStack(spacing: 4) {
                Group {
                    if let thumb = adjustVM.filterThumbnail(for: preset) {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.milensGrouped)
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? Color.milensActionPrimary : Color.milensBorder,
                                lineWidth: isSelected ? 2 : 0.5)
                }

                Text(NSLocalizedString(preset.nameKey, comment: ""))
                    .font(.bodySecondary)
                    .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextSecondary)
                    .lineLimit(1)
            }
            .frame(width: 62)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString(preset.nameKey, comment: ""))
    }

    /// 手动调整折叠入口：点击展开 / 收起 5 滑块。
    private func manualAdjustToggle(adjustVM: EditorAdjustPanelVM) -> some View {
        Button {
            adjustVM.toggleSlidersExpanded()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13)) // ui-token:ok SF Symbol 光学图标尺寸
                Text(String(localized: "editor.adjust.manual"))
                    .font(.editorialMetadata)
                Spacer()
                Image(systemName: adjustVM.isSlidersExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold)) // ui-token:ok SF Symbol 光学图标尺寸
            }
            .foregroundStyle(Color.milensTextSecondary)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func valueRail(field: EditorAdjustField, label: String, value: Double, range: ClosedRange<Double>, bipolar: Bool = false) -> some View {
        let isNeutral = value == 0
        return WorkshopValueRail(
            label: label,
            value: value,
            range: range,
            state: isNeutral ? .default : .changed,
            onChange: { newValue, phase in
                viewModel.adjustVM.onSliderChange(field, value: newValue, phase: phase)
            },
            bipolar: bipolar
        )
    }
}

// MARK: - 文字面板

/// 文字面板：铜索引头 + 文字图层 + 添加/编辑模式。
/// 对照 Figma `05 · Editor / Text` #422:821 Text Controls。
struct EditorTextPanelView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        @Bindable var textVM = viewModel.textVM
        if textVM.showEditPanel {
            textLayerEditPanel(textVM: textVM)
        } else {
            textAddPanel(textVM: textVM)
        }
    }

    /// 添加模式（对应源端文本添加工具 UI）。
    private func textAddPanel(textVM: EditorTextPanelVM) -> some View {
        @Bindable var textVM = textVM
        return VStack(spacing: 0) {
            WorkshopPanelHeader(title: String(localized: "editor.panel.text"))

            VStack(spacing: Spacing.sm) {
                TextField(String(localized: "editor.text.placeholder"), text: $textVM.textInput)
                    .font(.body)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.milensGrouped)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.small))

                HStack(spacing: Spacing.md) {
                    Text(String(localized: "editor.text.size"))
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensTextSecondary)
                    Slider(value: $textVM.textFontSize, in: 12...96)
                        .tint(.milensActionPrimary)
                    Text("\(Int(textVM.textFontSize)) pt")
                        .font(.editorialMetadata.monospacedDigit())
                        .foregroundStyle(Color.milensActionPrimary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    colorDots(selected: textVM.textColor) { textVM.textColor = $0 }
                }

                Toggle(String(localized: "editor.text.stroke"), isOn: $textVM.textStrokeEnabled)
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
                    .toggleStyle(.button)
                    .tint(.milensActionPrimary)

                Button(String(localized: "editor.text.add")) { textVM.add() }
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextOnActionPrimary)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.sm)
                    .background(canAdd(textVM) ? Color.milensActionPrimary : Color.milensBorder)
                    .clipShape(Capsule())
                    .disabled(!canAdd(textVM))
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.sm)
        }
        .background(Color.milensBackground)
    }

    /// 选中文字图层编辑模式（字号/颜色/删除，随手势合并入历史）。
    private func textLayerEditPanel(textVM: EditorTextPanelVM) -> some View {
        VStack(spacing: 0) {
            WorkshopPanelHeader(title: String(localized: "editor.panel.text")) {
                Button {
                    textVM.deleteActiveLayer()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.milensDanger)
                }
                .accessibilityLabel(String(localized: "a11y.editor.deleteText"))
            }

            HStack(spacing: Spacing.md) {
                Text(String(localized: "editor.text.size"))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
                Slider(
                    value: Binding(
                        get: { textVM.selectedTextFontSize },
                        set: { textVM.updateActiveText(fontSize: $0, color: textVM.selectedTextColor) }
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
                .tint(.milensActionPrimary)
                Text("\(Int(textVM.selectedTextFontSize)) pt")
                    .font(.editorialMetadata.monospacedDigit())
                    .foregroundStyle(Color.milensActionPrimary)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                colorDots(selected: textVM.selectedTextColor) {
                    textVM.updateActiveText(fontSize: textVM.selectedTextFontSize, color: $0)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.sm)
            }
        }
        .background(Color.milensBackground)
    }

    private func canAdd(_ textVM: EditorTextPanelVM) -> Bool {
        canAddTextLayer(textVM.textInput)
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
                        selected ? Color.milensActionPrimary : Color.milensBorder,
                        lineWidth: selected ? 2 : 1
                    )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "a11y.editor.color \(hex)"))
    }
}

// MARK: - 抠图面板

/// 抠图面板：铜索引头 + 主体抠图 + 双格信息 + 开始/重试。
/// 对照 Figma `06 · Editor / Cutout` #422:825 Cutout Controls。
struct EditorCutoutPanelView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            WorkshopPanelHeader(title: String(localized: "editor.panel.cutout")) {
                if viewModel.cutoutVM.phase == .applied {
                    Text(String(localized: "editor.cutout.done"))
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensActionPrimary)
                }
            }

            HStack(spacing: 0) {
                // 本地处理
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "editor.cutout.localProcessing"))
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensTextSecondary)
                    Text(String(localized: "editor.cutout.notUploaded"))
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.milensSeparator)
                    .frame(width: 1, height: 36)

                // 输出格式
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "editor.cutout.outputFormat"))
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensTextSecondary)
                    Text(String(localized: "editor.cutout.transparentPng"))
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Spacing.md)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)

            // 状态 + 开始/重试按钮
            HStack(spacing: Spacing.md) {
                Text(statusText)
                    .font(.editorialMetadata)
                    .foregroundStyle(viewModel.cutoutVM.phase == .error ? Color.milensDanger : Color.milensTextSecondary)
                Spacer(minLength: 0)
                Button(actionLabel) {
                    Task { await viewModel.cutoutVM.start() }
                }
                .font(.uiBodyStrong)
                .foregroundStyle(Color.milensTextOnActionPrimary)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.sm)
                .background(viewModel.cutoutVM.phase == .processing ? Color.milensBorder : Color.milensActionPrimary)
                .clipShape(Capsule())
                .disabled(viewModel.cutoutVM.phase == .processing)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.sm)
        }
        .background(Color.milensBackground)
    }

    private var statusText: String {
        viewModel.cutoutVM.status.isEmpty ? cutoutStatusText(.idle) : viewModel.cutoutVM.status
    }

    private var actionLabel: String {
        switch viewModel.cutoutVM.phase {
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
            .font(.uiBodyStrong)
            .foregroundStyle(role == .primary ? Color.milensTextOnActionPrimary : Color.milensTextPrimary)
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.sm)
            .background(role == .primary ? Color.milensActionPrimary : Color.milensGrouped)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 文字颜色预设（V1.0 固定色板）。
private let EDITOR_TEXT_COLOR_PRESETS: [String] = [
    "#FFFFFF", "#000000", "#FF3B30", "#FF9500", "#FFCC00",
    "#34C759", "#00C7BE", "#007AFF", "#5856D6", "#AF52DE",
]
