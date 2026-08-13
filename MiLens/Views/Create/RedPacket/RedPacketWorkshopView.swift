//  RedPacketWorkshopView —— 红包工作室主页（对应红包封面开发计划 §3）。
//
//  顶部导航头 + 画布（957×1278 比例）+ 底部四工具栏（照片/配饰/文字/优化）。
//  Phase 1 配饰/智能优化为占位禁用（Phase 2/3 实现）。
//  选中层浮层操作（删除/置中/恢复）。

import SwiftUI
import MiLensKit

struct RedPacketWorkshopView: View {
    let templateID: String
    let photoID: UUID
    let petID: UUID?

    @Environment(\.viewModelFactory) private var factory
    @Environment(\.proEntitlement) private var entitlement
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: RedPacketWorkshopViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm: vm)
            } else {
                ProgressView()
                    .tint(Color.milensActionPrimary)
            }
        }
        .background(Color.milensSealSurface)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if viewModel == nil {
                viewModel = factory.makeRedPacketWorkshopViewModel(
                    templateID: templateID,
                    photoID: photoID,
                    petID: petID,
                    isPro: entitlement.isPro
                )
                Task { await viewModel?.load() }
            }
        }
    }

    // MARK: - 内容

    private func content(vm: RedPacketWorkshopViewModel) -> some View {
        VStack(spacing: 0) {
            // 导航头
            WorkshopNavHeader(title: String(localized: "redpacket.workshop.title")) {
                // 保存草稿后退出
                vm.saveDraft()
                dismiss()
            } trailing: {
                NavigationLink(value: Route.redPacketExport(draftID: vm.draft.id)) {
                    Text(String(localized: "redpacket.workshop.export"))
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensActionPrimary)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    vm.saveDraft()
                })
                .disabled(vm.cutoutPhase != .applied)
            }

            // 抠图状态提示
            if vm.cutoutPhase == .processing {
                cutoutProcessingBar
            } else if vm.cutoutPhase == .error {
                cutoutErrorBar(vm: vm)
            }

            // 画布
            RedPacketCanvasView(viewModel: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 检查面板（选中层时显示）
            if vm.activeLayerID != nil {
                RedPacketInspectorView(viewModel: vm)
                    .frame(height: 120)
                    .background(Color.milensSealSurface)
            }

            // 底部工具栏
            toolbar(vm: vm)
        }
    }

    // MARK: - 抠图状态条

    private var cutoutProcessingBar: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text(String(localized: "redpacket.cutout.processing"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.milensSealSurface)
    }

    private func cutoutErrorBar(vm: RedPacketWorkshopViewModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(String(localized: "redpacket.cutout.failed"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextSecondary)
            Spacer()
            Button {
                Task { await vm.retryCutout() }
            } label: {
                Text(String(localized: "redpacket.cutout.retry"))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensActionPrimary)
            }
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.vertical, 8)
        .background(Color.milensSealSurface)
    }

    // MARK: - 底部工具栏

    private func toolbar(vm: RedPacketWorkshopViewModel) -> some View {
        HStack(spacing: 0) {
            toolbarButton(
                icon: "photo",
                label: String(localized: "redpacket.workshop.tool.photo"),
                isEnabled: true
            ) {
                // Phase 1：返回照片选择
                dismiss()
            }

            toolbarButton(
                icon: "sticker",
                label: String(localized: "redpacket.workshop.tool.accessory"),
                isEnabled: false
            ) {}

            toolbarButton(
                icon: "textformat",
                label: String(localized: "redpacket.workshop.tool.text"),
                isEnabled: true
            ) {
                // 选中文本层
                if let textLayer = vm.layers.first(where: { $0.kind == .text }) {
                    vm.activeLayerID = textLayer.id
                }
            }

            toolbarButton(
                icon: "wand.and.stars",
                label: String(localized: "redpacket.workshop.tool.optimize"),
                isEnabled: false
            ) {}
        }
        .padding(.vertical, 8)
        .background(Color.milensSealSurface)
    }

    private func toolbarButton(
        icon: String, label: String, isEnabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isEnabled ? Color.milensActionPrimary : Color.milensTextSecondary.opacity(0.4))
                Text(label)
                    .font(.editorialMetadata)
                    .foregroundStyle(isEnabled ? Color.milensTextPrimary : Color.milensTextSecondary.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

#Preview {
    NavigationStack {
        RedPacketWorkshopView(templateID: "new_year_red", photoID: UUID(), petID: nil)
    }
}
