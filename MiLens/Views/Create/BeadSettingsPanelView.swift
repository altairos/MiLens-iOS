//  BeadSettingsPanelView —— 拼豆设置面板（对应源端 BeadSettingsPanel.ets）。
//  风格选择 / 尺寸选择 / 当前方案摘要 / 高级设置（颜色、过渡、开关、概括度）/ 生成按钮。
//  纯决策（applyStylePreset / buildSummary / abstractionLevelLabel）在 MiLensKit。

import SwiftUI
import MiLensKit

struct BeadSettingsPanelView: View {
    @Bindable var vm: BeadViewModel

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

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                settingsCard
            }
            .padding(16)
        }
        .background(Color.milensBackground)
    }

    // MARK: - 顶部标题

    private var header: some View {
        VStack(spacing: 6) {
            Text("🧩").font(.system(size: 40))
            Text("把照片变成拼豆作品")
                .font(.headline)
                .foregroundStyle(Color.milensTextPrimary)
            Text("先选想要的效果，其余参数已经帮你配好")
                .font(.subheadline)
                .foregroundStyle(Color.milensTextTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // MARK: - 设置卡片

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("选择效果")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                Text("推荐：拼豆插画")
                    .font(.caption2)
                    .foregroundStyle(Color.milensPrimary)
            }
            .padding(.bottom, 12)

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
                        .foregroundStyle(Color.milensPrimary)
                    Spacer()
                    Text(vm.showAdvancedSettings ? "⌃" : "⌄")
                        .font(.body)
                        .foregroundStyle(Color.milensPrimary)
                }
                .padding(.vertical, 8)
            }

            if vm.showAdvancedSettings {
                advancedSettings
            }

            // 生成按钮
            Button {
                vm.generate()
            } label: {
                Text(isGenerating ? "正在生成..." : "生成拼豆图纸")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.milensTextOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.milensPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
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
        .padding(16)
        .background(Color.milensCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.top, 20)
    }

    // MARK: - 风格选项

    private func styleOption(_ option: StyleOptionData) -> some View {
        let selected = vm.settings.styleKey == option.key
        return Button {
            vm.applyStylePreset(option.key)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(option.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(selected ? Color.milensPrimary : Color.milensTextPrimary)
                        if !option.badge.isEmpty {
                            Text(option.badge)
                                .font(.caption2)
                                .foregroundStyle(Color.milensTextOnAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.milensPrimary)
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
                    .foregroundStyle(Color.milensPrimary)
            }
            .padding(12)
            .background(selected ? Color.milensAccentSoft : Color.milensGrouped)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.milensPrimary : Color.milensBorder,
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
                .foregroundStyle(selected ? Color.milensTextOnAccent : Color.milensTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.milensPrimary : Color.milensGrouped)
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
                        .foregroundStyle(Color.milensPrimary)
                }
                Slider(value: $vm.settings.abstractLevel, in: 0...1, step: 0.1)
                    .tint(Color.milensPrimary)
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
                .foregroundStyle(selected ? Color.milensTextOnAccent : Color.milensTextSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(selected ? Color.milensPrimary : Color.milensGrouped)
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
                .foregroundStyle(selected ? Color.milensTextOnAccent : Color.milensTextSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(selected ? Color.milensPrimary : Color.milensGrouped)
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
                .foregroundStyle(isOn ? Color.milensPrimary : Color.milensTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? Color.milensAccentSoft : Color.milensGrouped)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isOn ? Color.milensPrimary : Color.milensBorder,
                                lineWidth: isOn ? 1 : 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
