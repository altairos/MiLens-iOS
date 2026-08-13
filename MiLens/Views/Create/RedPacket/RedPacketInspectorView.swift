//  RedPacketInspectorView —— 选中层检查面板（对应红包封面开发计划 §3.2）。
//
//  Phase 1 最小化：活动层操作（删除/置中/恢复）+ 文本内容编辑。
//  样式预置切换结构预留（Phase 2 实现）。

import SwiftUI
import MiLensKit

struct RedPacketInspectorView: View {
    @Bindable var viewModel: RedPacketWorkshopViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // 删除
                actionButton(icon: "trash", label: String(localized: "redpacket.workshop.delete")) {
                    viewModel.deleteActive()
                }

                // 置中
                actionButton(icon: "scope", label: String(localized: "redpacket.workshop.center")) {
                    viewModel.centerActive()
                }

                // 恢复默认
                actionButton(icon: "arrow.counterclockwise", label: String(localized: "redpacket.workshop.reset")) {
                    viewModel.resetActive()
                }

                // 文本编辑（仅文本层）
                if viewModel.activeLayer?.kind == .text {
                    TextField(
                        String(localized: "redpacket.coverTitle.placeholder"),
                        text: Binding(
                            get: { viewModel.textContent },
                            set: { viewModel.updateText($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                }
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.vertical, 8)
        }
    }

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
            .frame(width: 64, height: 56)
        }
        .buttonStyle(.plain)
    }
}
