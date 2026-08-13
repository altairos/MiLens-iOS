//  RedPacketInspectorView —— 选中层检查面板（对应红包封面开发计划 §3.2/§3.3）。
//
//  Phase 2：活动层操作（删除/置中/恢复）+ 文本内容编辑 + 预置风格切换。

import SwiftUI
import MiLensKit

struct RedPacketInspectorView: View {
    @Bindable var viewModel: RedPacketWorkshopViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                // 操作按钮行
                HStack(spacing: 12) {
                    actionButton(icon: "trash", label: String(localized: "redpacket.workshop.delete")) {
                        viewModel.deleteActive()
                    }
                    actionButton(icon: "scope", label: String(localized: "redpacket.workshop.center")) {
                        viewModel.centerActive()
                    }
                    actionButton(icon: "arrow.counterclockwise", label: String(localized: "redpacket.workshop.reset")) {
                        viewModel.resetActive()
                    }
                    Spacer()
                }

                // 文本层编辑
                if viewModel.activeLayer?.kind == .text {
                    textEditingSection
                }
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 文本编辑区

    private var textEditingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 文本输入
            TextField(
                String(localized: "redpacket.coverTitle.placeholder"),
                text: Binding(
                    get: { viewModel.textContent },
                    set: { viewModel.updateText($0) }
                )
            )
            .textFieldStyle(.roundedBorder)

            // 预置风格切换
            Text(String(localized: "redpacket.workshop.textStyle"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RedPacketTextStylePreset.allCases, id: \.rawValue) { preset in
                        let isSelected = viewModel.activeLayer?.styleID == preset.rawValue
                        Button {
                            viewModel.applyTextStyle(preset)
                        } label: {
                            Text(presetDisplayName(preset))
                                .font(.system(size: 13))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.milensActionPrimary.opacity(0.2) : Color.clear)
                                .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextSecondary)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(isSelected ? Color.milensActionPrimary : Color.milensSeparator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 操作按钮

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.milensActionPrimary)
                Text(label)
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextPrimary)
            }
            .frame(width: 64, height: 48)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 风格显示名

    private func presetDisplayName(_ preset: RedPacketTextStylePreset) -> String {
        switch preset {
        case .festive: return "新年喜庆"
        case .handwriting: return "温柔手写"
        case .seal: return "极简印章"
        case .goldBlessing: return "金色祝福"
        case .petName: return "宠物昵称"
        }
    }
}
