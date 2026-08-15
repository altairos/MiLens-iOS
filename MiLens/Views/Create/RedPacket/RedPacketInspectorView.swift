//  RedPacketInspectorView —— 选中层检查面板（对应 Figma #3/#4/#5）。
//
//  伙伴图层：拖动/缩放/旋转/居中/换图（Figma #3 手势变换控件）。
//  配饰图层：缩放/旋转/删除（Figma #4 配饰控制）。
//  祝福语图层：文本输入 + 样式 Chip（喜庆/雅致/印章/金色，Figma #5）。

import SwiftUI
import MiLensKit

struct RedPacketInspectorView: View {
    @Bindable var viewModel: RedPacketWorkshopViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // 铜色索引条
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 64, height: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, Spacing.pagePad)

                // 图层头
                layerHeader
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, 4)

                // 按图层类型显示不同控件
                if let kind = viewModel.activeLayer?.kind {
                    switch kind {
                    case .pet:
                        petLayerControls
                    case .accessory:
                        accessoryLayerControls
                    case .text:
                        textLayerControls
                    default:
                        EmptyView()
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - 图层头

    private var layerHeader: some View {
        HStack {
            Text(layerTitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.milensTextPrimary)
            Spacer()
            if viewModel.activeLayer?.kind == .accessory {
                // 配饰层可删除
                Button {
                    viewModel.deleteActive()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.milensTextSecondary)
                }
            } else {
                // 其他层显示"还原"
                Button {
                    viewModel.resetActive()
                } label: {
                    Text(String(localized: "redpacket.workshop.reset"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }
        }
        .frame(height: 27)
    }

    private var layerTitle: String {
        switch viewModel.activeLayer?.kind {
        case .pet: return String(localized: "redpacket.workshop.layer.pet")
        case .accessory: return String(localized: "redpacket.workshop.layer.accessory")
        case .text: return String(localized: "redpacket.workshop.layer.blessing")
        default: return ""
        }
    }

    // MARK: - 伙伴图层手势变换控件（Figma #3）

    private var petLayerControls: some View {
        HStack(spacing: 8) {
            // 拖动由画布手势承担，这里只作高亮指示（Figma #3 默认手势提示），非可点击按钮
            transformBadge(
                icon: "move",
                label: String(localized: "redpacket.workshop.transform.move"),
                isHighlighted: true
            )
            transformButton(
                icon: "plus.magnifyingglass",
                label: String(localized: "redpacket.workshop.transform.scale"),
                isHighlighted: false
            ) {
                viewModel.transformActive(scaleBy: 1.2)
            }
            transformButton(
                icon: "rotate.3d",
                label: String(localized: "redpacket.workshop.transform.rotate"),
                isHighlighted: false
            ) {
                viewModel.transformActive(rotateBy: 15)
            }
            transformButton(
                icon: "scope",
                label: String(localized: "redpacket.workshop.transform.center"),
                isHighlighted: false
            ) {
                viewModel.centerActive()
            }
            transformButton(
                icon: "photo",
                label: String(localized: "redpacket.workshop.transform.changePhoto"),
                isHighlighted: false
            ) {
                // 与更多菜单「换图」同语义：退出工作台，回到抠图确认/照片选择页
                dismiss()
            }
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, 8)
    }

    // MARK: - 配饰图层控件（Figma #4）

    private var accessoryLayerControls: some View {
        HStack(spacing: 8) {
            transformButton(
                icon: "plus.magnifyingglass",
                label: String(localized: "redpacket.workshop.transform.scale"),
                isHighlighted: false
            ) {
                viewModel.transformActive(scaleBy: 1.2)
            }
            transformButton(
                icon: "rotate.3d",
                label: String(localized: "redpacket.workshop.transform.rotate"),
                isHighlighted: false
            ) {
                viewModel.transformActive(rotateBy: 15)
            }
            transformButton(
                icon: "scope",
                label: String(localized: "redpacket.workshop.transform.center"),
                isHighlighted: false
            ) {
                viewModel.centerActive()
            }
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, 8)
    }

    // MARK: - 祝福语图层控件（Figma #5）

    private var textLayerControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 文本内容输入（带背景板 + 编辑按钮）
            HStack(spacing: 0) {
                TextField(
                    String(localized: "redpacket.coverTitle.placeholder"),
                    text: Binding(
                        get: { viewModel.textContent },
                        set: { viewModel.updateText($0) }
                    ),
                    onEditingChanged: { isEditing in
                        // 失焦结束文本会话：连续键入只占一条撤销记录
                        if !isEditing { viewModel.endTextEdit() }
                    }
                )
                .font(.system(size: 12))
                .foregroundStyle(Color.milensTextPrimary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Color.milensSealSurface.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.milensSeparator, lineWidth: 1)
                )
            }
            .padding(.horizontal, Spacing.pagePad)

            // 样式 Chip 横轨
            HStack(spacing: 8) {
                Text(String(localized: "redpacket.workshop.textStyle"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.milensTextPrimary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RedPacketTextStylePreset.allCases, id: \.rawValue) { preset in
                            let isSelected = viewModel.activeLayer?.styleID == preset.rawValue
                            Button {
                                viewModel.applyTextStyle(preset)
                            } label: {
                                Text(presetDisplayName(preset))
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 69, height: 32)
                                    .background(isSelected ? Color.milensActionPrimary.opacity(0.11) : Color.white.opacity(0.66))
                                    .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(isSelected ? Color.milensActionPrimary : Color.milensSeparator, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    // MARK: - 变换单元

    private func transformButton(
        icon: String, label: String, isHighlighted: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            transformBadge(icon: icon, label: label, isHighlighted: isHighlighted)
        }
        .buttonStyle(.plain)
    }

    /// 变换单元视觉（按钮与静态手势指示共用）。
    private func transformBadge(
        icon: String, label: String, isHighlighted: Bool
    ) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.milensActionPrimary)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.milensTextPrimary)
        }
        .frame(width: 62, height: 60)
        .background(isHighlighted ? Color.milensActionPrimary.opacity(0.1) : Color.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isHighlighted ? Color.milensActionPrimary : Color.milensSeparator, lineWidth: 1)
        )
    }

    // MARK: - 风格显示名（对齐 Figma #5 命名）

    private func presetDisplayName(_ preset: RedPacketTextStylePreset) -> String {
        switch preset {
        case .festive: return String(localized: "redpacket.style.festive")
        case .handwriting: return String(localized: "redpacket.style.elegant")
        case .seal: return String(localized: "redpacket.style.seal")
        case .goldBlessing: return String(localized: "redpacket.style.gold")
        case .petName: return String(localized: "redpacket.style.petName")
        }
    }
}
