//  EditorDecorationPanelView —— 装饰面板（相框/贴纸）UI（对应开发计划 §4 交互规格）。
//  结构：铜索引头（标题 + 右侧 28pt 图标动作）→ 横向分类轨（分组胶囊）→ 横向素材轨。
//  素材单元 60×56pt 三态 Default/Selected/Locked（Figma `Picker/Decoration Asset Cell` 552:1084）：
//  Locked 展示真实预览 + PRO 角标，点击不改文档，由面板 VM 置 pendingPaywallItem → EditorView 弹付费墙。
//  标题行图标动作（§4.1）：贴纸 = 删除当前贴纸（无选中禁用）；相框 = 移除当前相框（无相框禁用）。
//  目录为空时显示真实空态，不注入演示素材；预览图经 DecorationImageLoader 异步解码（阻塞项4）。

import SwiftUI
import MiLensKit

struct EditorDecorationPanelView: View {
    @Bindable var viewModel: EditorViewModel
    @Environment(\.proEntitlement) private var entitlement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var panelVM = viewModel.decorationVM
        VStack(spacing: 0) {
            WorkshopPanelHeader(title: panelTitle) {
                headerAction(panelVM: panelVM)
            }

            if let group = panelVM.currentGroup {
                groupRail(panelVM: panelVM)
                itemRail(panelVM: panelVM, items: group.items)
            } else {
                emptyState
            }
        }
        .background(Color.milensBackground)
        .overlay(alignment: .top) { stickerLimitToast(panelVM: panelVM) }
        // Reduce Motion（规格 §9.3）：关闭 toast 过渡动画，直接切换（信息不依赖动画传达）
        .animation(reduceMotion ? nil : .easeInOut(duration: Motion.durationNormal),
                   value: panelVM.showsStickerLimitToast)
    }

    // MARK: - 标题行

    private var panelTitle: String {
        viewModel.tool == .sticker
            ? String(localized: "editor.panel.sticker")
            : String(localized: "editor.panel.frame")
    }

    /// 标题行右侧图标动作：贴纸面板删除当前贴纸；相框面板移除当前相框（§4.1，VoiceOver 完整标签）。
    @ViewBuilder
    private func headerAction(panelVM: EditorDecorationPanelVM) -> some View {
        if viewModel.tool == .sticker {
            headerIconButton(
                a11yLabel: String(localized: "a11y.editor.deleteSticker"),
                isEnabled: panelVM.hasActiveSticker
            ) {
                panelVM.deleteActiveSticker()
            }
        } else {
            headerIconButton(
                a11yLabel: String(localized: "a11y.editor.removeFrame"),
                isEnabled: panelVM.currentFrameResourcePath != nil
            ) {
                panelVM.removeFrame()
            }
        }
    }

    private func headerIconButton(a11yLabel: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: Sizing.iconMd))
                .foregroundStyle(Color.milensDanger)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(a11yLabel)
    }

    // MARK: - 分类轨

    /// 横向分组胶囊轨（分组名 `decoration.group.*` 本地化，动态 key 由 xcstrings 手工维护）。
    private func groupRail(panelVM: EditorDecorationPanelVM) -> some View {
        let groups = panelVM.groups
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(groups.indices, id: \.self) { index in
                    groupChip(
                        title: groupName(groups[index].id),
                        isSelected: index == panelVM.groupIndex
                    ) {
                        panelVM.selectGroup(index)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xs)
        }
    }

    /// 分组显示名（动态 key `decoration.group.*`）。运行时拼接 key 必须用
    /// NSLocalizedString：String.LocalizationValue 插值会把 key 归一为
    /// "decoration.group.%@" 导致查表失败、显示 key 原文（数据驱动本地化惯例）。
    private func groupName(_ id: String) -> String {
        NSLocalizedString("decoration.group.\(id)", comment: "装饰面板分组名（动态 key）")  // loc:dynamic
    }

    private func groupChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.bodySecondary)
                .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(isSelected ? Color.milensAccentWash : Color.milensGrouped)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(isSelected ? Color.milensActionPrimary : Color.clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - 素材轨

    private func itemRail(panelVM: EditorDecorationPanelVM, items: [DecorationItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                ForEach(items) { item in
                    decorationCell(panelVM: panelVM, item: item)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.sm)
        }
    }

    /// 素材单元 60×56pt 四态：Default（Card 底 + hairline 描边）/ Selected（铜描边 2pt + AccentWash 底，
    /// 仅相框有选中态）/ Locked（真实预览 + PRO 角标 + 降不透明度；点击触发付费墙而非禁用）/
    /// Unavailable（预览图解码失败，§7.2：警示占位 + 降不透明度 + 禁用，不可入文档）。
    private func decorationCell(panelVM: EditorDecorationPanelVM, item: DecorationItem) -> some View {
        let isLocked = !item.isUsable(isPro: entitlement.isPro)
        let isUnavailable = panelVM.isAssetUnavailable(item)
        let isSelected = panelVM.category == .frame
            && panelVM.currentFrameResourcePath == item.resourcePath
        return Button {
            if panelVM.category == .frame {
                panelVM.applyFrame(item, isPro: entitlement.isPro)
            } else {
                panelVM.addSticker(item, isPro: entitlement.isPro)
            }
        } label: {
            DecorationPreviewImage(name: item.previewPath) {
                panelVM.markPreviewUnavailable(item.previewPath)
            }
                .frame(width: 60, height: 56)
                .background(isSelected ? Color.milensAccentWash : Color.milensCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .stroke(isSelected ? Color.milensActionPrimary : Color.milensBorder,
                                lineWidth: isSelected ? 2 : 0.5)
                }
                .overlay(alignment: .topTrailing) {
                    if isLocked { proBadge }
                }
                .opacity(isLocked ? 0.6 : (isUnavailable ? 0.5 : 1))
        }
        .buttonStyle(.plain)
        .disabled(isUnavailable)
        .accessibilityLabel(cellA11yLabel(item, isLocked: isLocked, isUnavailable: isUnavailable))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// PRO 角标（对照 WorkshopTemplateTab 锁定态角标样式）。
    private var proBadge: some View {
        Text("PRO")
            .font(.system(size: 8, weight: .bold)) // ui-token:ok 微型角标
            .foregroundStyle(Color.milensTextOnActionPrimary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.milensActionPrimary)
            .clipShape(Capsule())
            .padding(2)
            .accessibilityLabel(String(localized: "a11y.editor.decoration.proBadge"))
    }

    /// 素材名与锁定态均为动态 key 查表（NSLocalizedString，同 groupName 理由）；
    /// key 缺失时回退 key 原文（素材 name key 由导入流程手工维护于 xcstrings）。
    private func cellA11yLabel(_ item: DecorationItem, isLocked: Bool, isUnavailable: Bool) -> String {
        let name = NSLocalizedString(item.name, comment: "装饰素材显示名（动态 key）")
        var label = name
        if isLocked {
            label += "，\(String(localized: "a11y.editor.decoration.proBadge"))"
        }
        if isUnavailable {
            label += "，\(String(localized: "a11y.editor.decoration.unavailable"))"
        }
        return label
    }

    // MARK: - 空态与提示

    /// 真实空态（§4.1：目录为空/解析失败/资源全缺时不注入演示素材）。
    private var emptyState: some View {
        Text(String(localized: "decoration.panel.empty"))
            .font(.bodySecondary)
            .foregroundStyle(Color.milensTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
    }

    /// 贴纸上限提示（VM 置位后 2.5s 自动复位，复用 ExportToast 视觉）。
    @ViewBuilder
    private func stickerLimitToast(panelVM: EditorDecorationPanelVM) -> some View {
        if panelVM.showsStickerLimitToast {
            ExportToastView(kind: .failure, message: stickerLimitMessage)
                .padding(.top, Spacing.xl)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: panelVM.showsStickerLimitToast) {
                    do {
                        try await Task.sleep(for: .seconds(2.5))
                    } catch {
                        return // 视图销毁或状态复位
                    }
                    panelVM.clearStickerLimitToast()
                }
        }
    }

    private var stickerLimitMessage: String {
        String(localized: "decoration.sticker.limit \(STICKER_LAYER_LIMIT)")
    }
}

// MARK: - 素材预览图

/// 素材预览图：DecorationImageLoader 异步解码 + NSCache（阻塞项4：解码移出 body）。
/// 加载前不占位填充（透出单元底色 milensCard）；解码失败显示警示占位并回调上报
/// （§7.2：不静默空白，面板据此显示不可用状态并禁用添加）。
private struct DecorationPreviewImage: View {
    let name: String
    var onUnavailable: (() -> Void)? = nil
    @State private var uiImage: UIImage?
    @State private var isLoadFailed = false

    var body: some View {
        ZStack {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            }
            if isLoadFailed {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .medium)) // ui-token:ok 警示占位
                    .foregroundStyle(Color.milensTextSecondary)
                    .accessibilityHidden(true) // 单元 a11y 由 cellA11yLabel 统一描述
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: name) {
            if let image = await DecorationImageLoader.load(name) {
                uiImage = image
                isLoadFailed = false
            } else {
                uiImage = nil
                isLoadFailed = true
                onUnavailable?()
            }
        }
    }
}
