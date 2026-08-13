//  BeadSettingsPanelView —— 拼豆设置面板（对照 Figma「11·拼豆设置」#91:248）。
//  Identity Strip/Source + Effect Proof 卡片 + 四段尺寸选择器 + Current Recipe +
//  Advanced Settings（颜色/过渡/轮廓/概括度） + Darkroom Pulse 生成按钮。
//  纯决策（applyStylePreset / buildSummary / abstractionLevelLabel）在 MiLensKit。

import SwiftUI
import MiLensKit

struct BeadSettingsPanelView: View {
    @Bindable var vm: BeadViewModel
    let onExport: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct StyleOptionData: Identifiable {
        let key: String
        let title: String
        let description: String
        let badge: String
        var id: String { key }
    }

    private static let styleOptions: [StyleOptionData] = [
        StyleOptionData(key: "illustration_v1", title: "拼豆插画",
                        description: "清爽主体", badge: "推荐"),
        StyleOptionData(key: "faithful_v1", title: "写实还原",
                        description: "保留毛色", badge: ""),
        StyleOptionData(key: "badge_v1", title: "清晰徽章",
                        description: "圆形挂件", badge: ""),
        StyleOptionData(key: "full_photo_v1", title: "保留场景",
                        description: "完整画面", badge: ""),
        StyleOptionData(key: "cute_v1", title: "Q版可爱",
                        description: "极简色块", badge: ""),
    ]

    private static let sizeKeys = ["mini", "standard", "large", "jumbo"]
    private static let sizeLabels = ["15\n迷你", "29\n标准", "52\n特大", "78\n超大"]
    private static let colorKeys = ["simple", "standard", "detailed", "realistic", "auto"]
    private static let colorLabels = ["12\n简单", "24\n标准", "40\n细腻", "60\n还原", "auto\n自动"]
    private static let ditherKeys = ["none", "light", "medium"]
    private static let ditherLabels = ["关闭", "轻微", "明显"]

    private var isGenerating: Bool {
        if case .generating = vm.phase { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                sourceContent
                inspectorContent
            }
            .padding(.horizontal, 18)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(Color.milensBackground)
        .animation(reduceMotion ? nil : .spring(duration: Motion.durationFast, bounce: 0.2), value: vm.settings)
        .animation(reduceMotion ? nil : .spring(duration: Motion.durationFast, bounce: 0.2), value: vm.showAdvancedSettings)
    }

    // MARK: - 可复用子区块（供 iPhone 全量与 iPad 分栏复用）

    /// 源上下文区块：Identity Strip + Effect Proof 卡片。
    /// iPad 左列（Source Workspace）使用。
    @ViewBuilder var sourceContent: some View {
        identityStrip
        effectSection
    }

    /// 参数检查器区块：尺寸 + 配方 + 高级设置 + 生成按钮。
    /// iPad 右列（Parameter Inspector）使用。
    @ViewBuilder var inspectorContent: some View {
        sizeSection
        currentRecipe
        advancedSection
        generateButton
        footerHint
    }

    // MARK: - Identity Strip/Source（对照 #301:888 / Figma Surface/Identity Strip #299:615）
    //  复用可复用 IdentityStrip 组件（UI-DESIGN.md §5.6 契约）。

    private var identityStrip: some View {
        IdentityStrip(
            context: .source,
            meta: String(localized: "create.bead.sourceMeta"),
            label: String(localized: "create.bead.source"),
            action: String(localized: "create.bead.change"),
            onAction: {}
        ) {
            if !vm.thumbnailPath.isEmpty || !vm.photoURI.isEmpty {
                ThumbnailImage(path: vm.thumbnailPath.isEmpty ? vm.photoURI : vm.thumbnailPath)
                    .scaledToFill()
            } else {
                Color.milensAccentSoft
            }
        }
    }

    // MARK: - 选择效果（对照 #91:261-353）

    private var effectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "create.bead.selectEffect"))
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                Text(String(localized: "create.bead.effectCount \(Self.styleOptions.count)"))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensActionPrimary)
            }

            // Effect Proof 卡片横排
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.styleOptions) { option in
                        effectProofCard(option)
                    }
                }
            }
        }
    }

    private func effectProofCard(_ option: StyleOptionData) -> some View {
        let selected = vm.settings.styleKey == option.key
        return Button {
            vm.applyPreset(option.key)
        } label: {
            VStack(spacing: 0) {
                // 暗色预览区
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.milensInk)
                        .frame(width: 88, height: 44)

                    if !option.badge.isEmpty {
                        // Badge（对照 #309:753）
                        Text(option.badge)
                            .font(.editorialOverline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.milensActionPrimary)
                            .clipShape(Capsule())
                            .padding(.top, 45)
                            .padding(.leading, 56)
                    }
                }
                .frame(width: 88, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.editorialMetadata)
                        .foregroundStyle(selected ? Color.milensActionPrimary : Color.milensTextPrimary)
                    Text(option.description)
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensTextTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 10)
            }
            .frame(width: 108, height: 106)
            .background(selected ? Color.milensAccentSoft : Color.milensCard)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? Color.milensActionPrimary : Color.milensBorder,
                            lineWidth: selected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topLeading) {
                // Proof Index（选中标记，对照 #309:755）
                if selected {
                    Rectangle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 22, height: 2)
                        .padding(.leading, 10)
                        .padding(.top, 0)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 图纸尺寸四段选择器（对照 #288:553）

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "create.bead.boardSize"))
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextPrimary)

            HStack(spacing: 0) {
                ForEach(Array(Self.sizeKeys.enumerated()), id: \.offset) { idx, key in
                    sizeSegment(key: key, label: Self.sizeLabels[idx], index: idx)
                }
            }
            .frame(height: 46)
            .background(Color.milensGrouped)
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.milensBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }

    private func sizeSegment(key: String, label: String, index: Int) -> some View {
        let selected = vm.settings.sizeKey == key
        let parts = label.split(separator: "\n")
        return Button {
            vm.settings.sizeKey = key
        } label: {
            VStack(spacing: 1) {
                Text(parts.first ?? "")
                    .font(.bodySecondary)
                    .foregroundStyle(selected ? Color.white : Color.milensTextSecondary)
                if parts.count > 1 {
                    Text(parts[1])
                        .font(.editorialMetadata)
                        .foregroundStyle(selected ? Color.white : Color.milensTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(selected ? Color.milensActionPrimary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Current Recipe 行（对照 #91:324-327）

    private var currentRecipe: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "create.bead.currentRecipe"))
                    .font(.editorialOverline)
                    .tracking(0.4)
                    .foregroundStyle(Color.milensTextTertiary)
                Text(buildSummary(vm.settings))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
            }
            .padding(.leading, 14)
            Spacer()
            Text("\u{203A}")
                .font(.system(size: 17, weight: .medium)) // ui-token:ok 装饰箭头字符
                .foregroundStyle(Color.milensActionPrimary)
                .padding(.trailing, 14)
        }
        .frame(height: 52)
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    // MARK: - 高级设置（对照 #91:328-360）

    private var advancedSection: some View {
        VStack(spacing: 8) {
            // 标题行
            HStack {
                Text(String(localized: "create.bead.advanced"))
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                Button {
                    vm.showAdvancedSettings.toggle()
                } label: {
                    Text(vm.showAdvancedSettings
                         ? String(localized: "create.bead.expanded")
                         : String(localized: "create.bead.collapsed"))
                        .font(.editorialOverline)
                        .tracking(0.4)
                        .foregroundStyle(Color.milensActionPrimary)
                }
                .buttonStyle(.plain)
            }

            if vm.showAdvancedSettings {
                advancedPanel
            }
        }
    }

    private var advancedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 颜色（对照 #91:331-339）
            settingRow(label: String(localized: "create.bead.color")) {
                HStack(spacing: 7) {
                    ForEach(Array(Self.colorKeys.enumerated()), id: \.offset) { idx, key in
                        chipButton(
                            label: Self.colorLabels[idx].split(separator: "\n").first.map(String.init) ?? key,
                            selected: vm.settings.colorKey == key
                        ) {
                            vm.settings.colorKey = key
                        }
                    }
                }
            }
            divider

            // 过渡（对照 #91:340-346）
            settingRow(label: String(localized: "create.bead.transition")) {
                HStack(spacing: 7) {
                    ForEach(Array(Self.ditherKeys.enumerated()), id: \.offset) { idx, key in
                        chipButton(
                            label: Self.ditherLabels[idx],
                            selected: vm.settings.ditherKey == key
                        ) {
                            vm.settings.ditherKey = key
                        }
                    }
                }
            }
            divider

            // 轮廓 toggle（对照 #91:347-356）
            settingRow(label: String(localized: "create.bead.outline")) {
                HStack(spacing: 16) {
                    toggleChip(String(localized: "create.bead.denoise"), isOn: vm.settings.denoise) {
                        vm.settings.denoise = $0
                    }
                    toggleChip(String(localized: "create.bead.cutoutOnly"), isOn: vm.settings.cutout) {
                        vm.settings.cutout = $0
                    }
                }
            }
            divider

            // 概括度 slider（对照 #91:356-360）
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(localized: "create.bead.abstraction"))
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensTextSecondary)
                    Spacer()
                    Text(abstractionLevelLabel(vm.settings.abstractLevel))
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensActionPrimary)
                }
                Slider(value: $vm.settings.abstractLevel, in: 0...1, step: 0.1)
                    .tint(Color.milensActionPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .background(Color.milensGrouped)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func settingRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextTertiary)
                .frame(width: 56, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.milensBorder)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }

    // MARK: - chip 组件（对照 #91:332-339 白底 11px 圆角）

    private func chipButton(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.editorialMetadata)
                .foregroundStyle(selected ? Color.milensActionPrimary : Color.milensTextSecondary)
                .frame(minWidth: 58, minHeight: 30)
                .background(selected ? Color.milensAccentSoft : Color.milensCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(selected ? Color.milensActionPrimary : Color.milensBorder,
                                lineWidth: selected ? 1 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func toggleChip(_ label: String, isOn: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        Button {
            onChange(!isOn)
        } label: {
            Text(label)
                .font(.editorialMetadata)
                .foregroundStyle(isOn ? Color.milensActionPrimary : Color.milensTextSecondary)
                .frame(minWidth: 58, minHeight: 30)
                .background(isOn ? Color.milensAccentSoft : Color.milensCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(isOn ? Color.milensActionPrimary : Color.milensBorder,
                                lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Darkroom Pulse 生成按钮（对照 #268:332 / Figma Action/Darkroom Pulse #263:368）

    private var generateButton: some View {
        DarkroomPulseButton(
            label: primaryButtonTitle,
            context: vm.pattern != nil ? .export_ : .generate,
            isEnabled: !isGenerating,
            isLoading: isGenerating,
            action: {
                if vm.pattern != nil {
                    onExport()
                } else {
                    vm.generate()
                }
            }
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: Motion.durationFast), value: isGenerating)
    }

    private var primaryButtonTitle: String {
        vm.pattern != nil
            ? String(localized: "create.bead.viewExport")
            : String(localized: "create.bead.generatePattern")
    }

    private var footerHint: some View {
        Text(String(localized: "create.bead.localProcessHint"))
            .font(.editorialMetadata)
            .foregroundStyle(Color.milensTextTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}
