//  BeadSettingsPanelView —— 拼豆设置面板（对应源端 BeadSettingsPanel.ets）。
//  工作室下半屏：风格选择 / 尺寸选择 / 当前方案摘要 / 高级设置 / 主按钮。
//  已有图纸时主按钮切换为「查看图纸与导出」（参数变化由工作室防抖实时重渲染，
//  无需手动重新生成）。
//  纯决策（applyStylePreset / buildSummary / abstractionLevelLabel）在 MiLensKit。

import SwiftUI
import MiLensKit

struct BeadSettingsPanelView: View {
    @Bindable var vm: BeadViewModel
    /// 打开导出全屏预览（仅 pattern != nil 时由主按钮触发）。
    let onExport: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 风格选项数据（对应源端 StyleOption 列表）。
    private struct StyleOptionData: Identifiable {
        let key: String
        let title: String
        let description: String
        let badge: String
        var id: String { key }
    }

    private static let styleOptions: [StyleOptionData] = [
        StyleOptionData(key: "illustration_v1", title: "拼豆插画",
                        description: "清爽、特征清楚，适合大多数照片", badge: "推荐"),
        StyleOptionData(key: "faithful_v1", title: "写实还原",
                        description: "保留更多毛色与细节，制作难度较高", badge: ""),
        StyleOptionData(key: "badge_v1", title: "清晰徽章",
                        description: "颜色少、色块大，使用圆形裁切，适合挂件和小图", badge: ""),
        StyleOptionData(key: "full_photo_v1", title: "保留场景",
                        description: "保留照片背景，适合有纪念意义的画面", badge: ""),
        StyleOptionData(key: "cute_v1", title: "Q版可爱",
                        description: "极简色块、高对比、黑色轮廓，像表情包一样可爱", badge: ""),
    ]

    /// 尺寸/颜色/过渡选项固定顺序（Dictionary 无序，需显式排序）。
    private static let sizeKeys = ["mini", "standard", "large", "jumbo"]
    private static let colorKeys = ["simple", "standard", "detailed", "realistic", "auto"]
    private static let ditherKeys = ["none", "light", "medium"]

    private var isGenerating: Bool {
        if case .generating = vm.phase { return true }
        return false
    }

    @State private var selectedRailItem = "尺寸"
    @State private var showingParameterSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                parameterRail
                Spacer(minLength: Spacing.xxl)
                compactAction
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.xxl)
            }
            .frame(maxWidth: .infinity, minHeight: 250, alignment: .bottom)
        }
        .background(Color.milensStudioBackground)
        .sheet(isPresented: $showingParameterSheet) {
            NavigationStack {
                ScrollView {
                    settingsCard
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                }
                .background(Color.milensStudioBackground)
                .navigationTitle("调整参数")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { showingParameterSheet = false }
                    }
                }
            }
            .environment(\.colorScheme, .dark)
            // iPad/regular 宽度下参数表单限宽居中（UI-DESIGN.md §8）
            .modalContentWidth(background: .milensStudioBackground)
        }
    }

    private var parameterRail: some View {
        HStack(spacing: 0) {
            railItem(value: "48", title: "尺寸", key: "尺寸")
            railItem(value: "24", title: "色板", key: "色板")
            railItem(value: "Ⅱ", title: "细节", key: "细节")
            railItem(value: "◎", title: "预览", key: "预览")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.milensBorder)
                .frame(height: 1)
        }
    }

    private func railItem(value: String, title: String, key: String) -> some View {
        Button {
            selectedRailItem = key
            if key != "预览" {
                showingParameterSheet = true
            }
        } label: {
            VStack(spacing: Spacing.xs) {
                Text(value)
                    .font(.editorialNumber)
                    .foregroundStyle(selectedRailItem == key ? Color.milensCopper : Color.milensTextSecondary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(selectedRailItem == key ? Color.milensTextPrimary : Color.milensTextSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(selectedRailItem == key ? Color.milensStudioSurface : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var compactAction: some View {
        VStack(spacing: Spacing.md) {
            Button {
                if vm.pattern != nil {
                    onExport()
                } else {
                    vm.generate()
                }
            } label: {
                Text(primaryButtonTitle)
                    .font(.buttonLabel)
                    .foregroundStyle(Color.milensInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.milensCopper)
                    .clipShape(Rectangle())
            }
            .disabled(isGenerating)
        }
    }

    // MARK: - 设置卡片

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("选择效果")
                    .font(.bodySecondary.weight(.medium))
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                Text("推荐：拼豆插画")
                    .font(.caption2)
                    .foregroundStyle(Color.milensActionPrimary)
            }
            .padding(.bottom, Spacing.md)

            ForEach(Self.styleOptions) { option in
                styleOption(option)
            }

            Text("图纸尺寸")
                .font(.caption)
                .foregroundStyle(Color.milensTextTertiary)
                .padding(.top, 18)
                .padding(.bottom, 8)

            HStack {
                ForEach(Self.sizeKeys, id: \.self) { key in
                    sizeChip(key)
                }
            }
            .padding(.bottom, 16)

            // 当前方案摘要
            HStack {
                Text("当前方案")
                    .font(.caption2)
                    .foregroundStyle(Color.milensTextTertiary)
                Spacer()
                Text(buildSummary(vm.settings))
                    .font(.caption2)
                    .foregroundStyle(Color.milensTextSecondary)
            }
            .padding(12)
            .background(Color.milensGrouped)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 12)

            // 高级设置折叠
            Button {
                vm.showAdvancedSettings.toggle()
            } label: {
                HStack {
                    Text(vm.showAdvancedSettings ? "收起高级设置" : "高级设置")
                        .font(.subheadline)
                        .foregroundStyle(Color.milensActionPrimary)
                    Spacer()
                    Image(systemName: vm.showAdvancedSettings ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.milensActionPrimary)
                }
                .padding(.vertical, 8)
            }

            if vm.showAdvancedSettings {
                advancedSettings
            }

            // 主按钮：无图纸时生成；已有图纸时进入导出（参数变化由工作室实时重渲染）
            Button {
                if vm.pattern != nil {
                    onExport()
                } else {
                    vm.generate()
                }
            } label: {
                Text(primaryButtonTitle)
                    .font(.buttonLabel)
                    .foregroundStyle(Color.milensTextOnActionPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.milensActionPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            }
            .disabled(isGenerating)
            .padding(.top, 16)

            Text("启用\"只拼主体\"时会自动抠图；失败后仍会使用原图继续生成")
                .font(.caption2)
                .foregroundStyle(Color.milensTextTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
        .padding(Spacing.lg)
        .background(Color.milensStudioBackground)
        // 参数切换 spring（UI-DESIGN.md §7：Reduce Motion 下即时更新）
        .animation(reduceMotion ? nil : .spring(duration: Motion.durationFast, bounce: 0.2), value: vm.settings)
        .animation(reduceMotion ? nil : .spring(duration: Motion.durationFast, bounce: 0.2), value: vm.showAdvancedSettings)
    }

    private var primaryButtonTitle: String {
        if isGenerating { return "正在生成..." }
        return vm.pattern != nil ? "导出图纸" : "生成拼豆图纸"
    }

    // MARK: - 风格选项

    private func styleOption(_ option: StyleOptionData) -> some View {
        let selected = vm.settings.styleKey == option.key
        return Button {
            vm.applyPreset(option.key)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(option.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(selected ? Color.milensActionPrimary : Color.milensTextPrimary)
                        if !option.badge.isEmpty {
                            Text(option.badge)
                                .font(.caption2)
                                .foregroundStyle(Color.milensTextOnActionPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.milensActionPrimary)
                                .clipShape(Capsule())
                        }
                    }
                    Text(option.description)
                        .font(.caption2)
                        .foregroundStyle(Color.milensTextTertiary)
                }
                Spacer()
                Text(selected ? "✓" : "")
                    .font(.headline)
                    .foregroundStyle(Color.milensActionPrimary)
            }
            .padding(12)
            .background(selected ? Color.milensAccentSoft : Color.milensGrouped)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.milensActionPrimary : Color.milensBorder,
                            lineWidth: selected ? 1.5 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    // MARK: - 选择 chips

    private func sizeChip(_ key: String) -> some View {
        let selected = vm.settings.sizeKey == key
        let label = BEAD_SIZE_PRESETS[key]?.label ?? key
        return Button {
            vm.settings.sizeKey = key
        } label: {
            Text(label)
                .font(.caption)
                .foregroundStyle(selected ? Color.milensTextOnActionPrimary : Color.milensTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.milensActionPrimary : Color.milensGrouped)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 高级设置

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("颜色数量")
                .font(.caption2)
                .foregroundStyle(Color.milensTextTertiary)
                .padding(.bottom, 8)
            HStack {
                ForEach(Self.colorKeys, id: \.self) { key in
                    colorChip(key)
                }
            }
            .padding(.bottom, 12)

            Text("颜色过渡")
                .font(.caption2)
                .foregroundStyle(Color.milensTextTertiary)
                .padding(.bottom, 8)
            HStack {
                ForEach(Self.ditherKeys, id: \.self) { key in
                    ditherChip(key)
                }
            }
            .padding(.bottom, 12)

            HStack {
                toggleChip("线条清晰", isOn: vm.settings.outline) { vm.settings.outline = $0 }
                toggleChip("减少杂点", isOn: vm.settings.denoise) { vm.settings.denoise = $0 }
                toggleChip("只拼主体", isOn: vm.settings.cutout) { vm.settings.cutout = $0 }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("概括度")
                        .font(.caption2)
                        .foregroundStyle(Color.milensTextTertiary)
                    Spacer()
                    Text(abstractionLevelLabel(vm.settings.abstractLevel))
                        .font(.caption2)
                        .foregroundStyle(Color.milensActionPrimary)
                }
                Slider(value: $vm.settings.abstractLevel, in: 0...1, step: 0.1)
                    .tint(Color.milensActionPrimary)
            }
            .padding(.top, 12)
        }
        .padding(12)
        .background(Color.milensGrouped)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 4)
    }

    private func colorChip(_ key: String) -> some View {
        let selected = vm.settings.colorKey == key
        let label = BEAD_COLOR_PRESETS[key]?.label ?? key
        return Button {
            vm.settings.colorKey = key
        } label: {
            Text(label)
                .font(.caption2)
                .foregroundStyle(selected ? Color.milensTextOnActionPrimary : Color.milensTextSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(selected ? Color.milensActionPrimary : Color.milensGrouped)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func ditherChip(_ key: String) -> some View {
        let selected = vm.settings.ditherKey == key
        let label: String
        switch key {
        case "none": label = "关闭"
        case "light": label = "轻微"
        default: label = "明显"
        }
        return Button {
            vm.settings.ditherKey = key
        } label: {
            Text(label)
                .font(.caption2)
                .foregroundStyle(selected ? Color.milensTextOnActionPrimary : Color.milensTextSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(selected ? Color.milensActionPrimary : Color.milensGrouped)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toggleChip(_ label: String, isOn: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        Button {
            onChange(!isOn)
        } label: {
            Text(label)
                .font(.caption2)
                .foregroundStyle(isOn ? Color.milensActionPrimary : Color.milensTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? Color.milensAccentSoft : Color.milensGrouped)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isOn ? Color.milensActionPrimary : Color.milensBorder,
                                lineWidth: isOn ? 1 : 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
