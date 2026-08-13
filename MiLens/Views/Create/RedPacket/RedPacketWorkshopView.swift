//  RedPacketWorkshopView —— 红包工作室主页（对应红包封面开发计划 §3）。
//
//  顶部导航头（含撤销/重做）+ 画布（957×1278 比例）+ 底部四工具栏（照片/配饰/文字/优化）。
//  Phase 2：模板切换 sheet、配饰面板、文本风格切换、撤销/重做。
//  智能优化仍为占位禁用（Phase 3 实现）。

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
    @State private var showTemplateSwitcher = false
    @State private var showAccessoryPicker = false
    @State private var showQualityReport = false

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
        .sheet(isPresented: $showQualityReport) {
            if let vm = viewModel {
                RedPacketQualityReportView(viewModel: vm)
            }
        }
        .sheet(isPresented: $showTemplateSwitcher) {
            if let vm = viewModel {
                templateSwitcherSheet(vm: vm)
            }
        }
        .sheet(isPresented: $showAccessoryPicker) {
            if let vm = viewModel {
                accessoryPickerSheet(vm: vm)
            }
        }
    }

    // MARK: - 内容

    private func content(vm: RedPacketWorkshopViewModel) -> some View {
        VStack(spacing: 0) {
            // 导航头（含撤销/重做）
            WorkshopNavHeader(title: String(localized: "redpacket.workshop.title")) {
                vm.saveDraft()
                dismiss()
            } trailing: {
                HStack(spacing: 12) {
                    // 撤销
                    Button {
                        vm.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16))
                            .foregroundStyle(vm.canUndo ? Color.milensTextPrimary : Color.milensTextSecondary.opacity(0.3))
                    }
                    .disabled(!vm.canUndo)

                    // 重做
                    Button {
                        vm.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 16))
                            .foregroundStyle(vm.canRedo ? Color.milensTextPrimary : Color.milensTextSecondary.opacity(0.3))
                    }
                    .disabled(!vm.canRedo)

                    // 导出
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
                    .frame(height: 140)
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
                icon: "rectangle.grid.2x2",
                label: String(localized: "redpacket.workshop.tool.template"),
                isEnabled: true
            ) {
                showTemplateSwitcher = true
            }

            toolbarButton(
                icon: "photo",
                label: String(localized: "redpacket.workshop.tool.photo"),
                isEnabled: true
            ) {
                dismiss()
            }

            toolbarButton(
                icon: "sticker",
                label: String(localized: "redpacket.workshop.tool.accessory"),
                isEnabled: true
            ) {
                showAccessoryPicker = true
            }

            toolbarButton(
                icon: "textformat",
                label: String(localized: "redpacket.workshop.tool.text"),
                isEnabled: true
            ) {
                if let textLayer = vm.layers.first(where: { $0.kind == .text }) {
                    vm.activeLayerID = textLayer.id
                }
            }

            // 智能优化（Phase 3 启用）
            toolbarButton(
                icon: "wand.and.stars",
                label: String(localized: "redpacket.workshop.tool.optimize"),
                isEnabled: true,
                badge: vm.hasQualityIssues
            ) {
                showQualityReport = true
            }
        }
        .padding(.vertical, 8)
        .background(Color.milensSealSurface)
    }

    private func toolbarButton(
        icon: String, label: String, isEnabled: Bool,
        badge: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(isEnabled ? Color.milensActionPrimary : Color.milensTextSecondary.opacity(0.4))
                    if badge {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(label)
                    .font(.editorialMetadata)
                    .foregroundStyle(isEnabled ? Color.milensTextPrimary : Color.milensTextSecondary.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    // MARK: - 模板切换 Sheet

    private func templateSwitcherSheet(vm: RedPacketWorkshopViewModel) -> some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                    ForEach(RedPacketTemplateCatalog.all) { template in
                        let isCurrent = template.id == vm.template.id
                        let isLocked = !template.isFree && !entitlement.isPro
                        Button {
                            if !isLocked {
                                vm.switchTemplate(to: template.id)
                                showTemplateSwitcher = false
                            }
                        } label: {
                            VStack(spacing: 4) {
                                RedPacketCoverRenderer(
                                    template: template,
                                    layers: rpDefaultLayers(for: template),
                                    petImage: nil,
                                    includeWatermark: false
                                )
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(isCurrent ? Color.milensActionPrimary : Color.clear, lineWidth: 2))
                                .overlay(alignment: .topTrailing) {
                                    if isLocked {
                                        Image(systemName: "lock.fill")
                                            .font(.caption)
                                            .foregroundStyle(.white)
                                            .padding(6)
                                            .background(Color.black.opacity(0.5))
                                            .clipShape(Circle())
                                            .padding(6)
                                    }
                                }

                                Text(template.displayName)
                                    .font(.editorialMetadata)
                                    .foregroundStyle(isCurrent ? Color.milensActionPrimary : Color.milensTextPrimary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isLocked)
                    }
                }
                .padding()
            }
            .navigationTitle(String(localized: "redpacket.workshop.templateSwitcher"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        showTemplateSwitcher = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 配饰选择 Sheet

    private func accessoryPickerSheet(vm: RedPacketWorkshopViewModel) -> some View {
        NavigationStack {
            let accessories = accessoryCatalog()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 16) {
                    ForEach(accessories, id: \.id) { item in
                        Button {
                            vm.addAccessory(resourceRef: item.resourceRef)
                            showAccessoryPicker = false
                        } label: {
                            VStack(spacing: 4) {
                                Text(item.emoji)
                                    .font(.system(size: 36))
                                    .frame(width: 64, height: 64)
                                    .background(Color.milensSealSurface.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(item.name)
                                    .font(.editorialMetadata)
                                    .foregroundStyle(Color.milensTextPrimary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle(String(localized: "redpacket.workshop.tool.accessory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        showAccessoryPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - 配饰目录（程序化占位，Phase 2 基础）

    private struct AccessoryItem {
        let id: String
        let name: String
        let emoji: String
        let resourceRef: String
    }

    private func accessoryCatalog() -> [AccessoryItem] {
        [
            AccessoryItem(id: "lantern", name: "灯笼", emoji: "🏮", resourceRef: "acc_lantern"),
            AccessoryItem(id: "firecracker", name: "鞭炮", emoji: "🧨", resourceRef: "acc_firecracker"),
            AccessoryItem(id: "coin", name: "金币", emoji: "🪙", resourceRef: "acc_coin"),
            AccessoryItem(id: "flower", name: "花卉", emoji: "🌸", resourceRef: "acc_flower"),
            AccessoryItem(id: "paw", name: "爪印", emoji: "🐾", resourceRef: "acc_paw"),
            AccessoryItem(id: "heart", name: "爱心", emoji: "❤️", resourceRef: "acc_heart"),
            AccessoryItem(id: "star", name: "星星", emoji: "⭐", resourceRef: "acc_star"),
            AccessoryItem(id: "bow", name: "蝴蝶结", emoji: "🎀", resourceRef: "acc_bow"),
        ]
    }
}

#Preview {
    NavigationStack {
        RedPacketWorkshopView(templateID: "new_year_red", photoID: UUID(), petID: nil)
    }
}
