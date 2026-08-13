//  RedPacketWorkshopView —— 红包工作室主页（对应红包封面开发计划 §3）。
//
//  顶部导航头（含撤销/重做）+ 画布（957×1278 比例）+ 三通道图层底栏。
//  模板、换图与画面检查收进更多菜单，底栏只承担画布内容选择。

import SwiftUI
import MiLensKit

private enum RedPacketEditingChannel: String, CaseIterable {
    case pet
    case accessory
    case blessing

    var icon: String {
        switch self {
        case .pet: return "pawprint"
        case .accessory: return "sparkles"
        case .blessing: return "textformat"
        }
    }

    var label: String {
        switch self {
        case .pet: return String(localized: "redpacket.workshop.channel.pet")
        case .accessory: return String(localized: "redpacket.workshop.channel.accessory")
        case .blessing: return String(localized: "redpacket.workshop.channel.blessing")
        }
    }
}

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
    @State private var selectedChannel: RedPacketEditingChannel = .pet

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

                    workshopMenu(vm: vm)

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

            // 底部图层通道
            channelDock(vm: vm)
        }
        .onChange(of: vm.activeLayerID) { _, layerID in
            guard let layerID,
                  let layer = vm.layers.first(where: { $0.id == layerID }) else { return }
            switch layer.kind {
            case .pet: selectedChannel = .pet
            case .accessory: selectedChannel = .accessory
            case .text: selectedChannel = .blessing
            default: break
            }
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
                .foregroundStyle(Color.milensWarning)
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

    // MARK: - 更多菜单

    private func workshopMenu(vm: RedPacketWorkshopViewModel) -> some View {
        Menu {
            Button {
                showTemplateSwitcher = true
            } label: {
                Label(String(localized: "redpacket.workshop.tool.template"), systemImage: "rectangle.grid.2x2")
            }
            Button {
                dismiss()
            } label: {
                Label(String(localized: "redpacket.workshop.tool.photo"), systemImage: "photo")
            }
            Button {
                vm.evaluateQuality()
                showQualityReport = true
            } label: {
                Label(String(localized: "redpacket.quality.title"), systemImage: "checkmark.shield")
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.milensTextPrimary)
                if vm.hasQualityIssues {
                    Circle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 6, height: 6)
                        .offset(x: 2, y: -2)
                }
            }
        }
    }

    // MARK: - 三通道底栏

    private func channelDock(vm: RedPacketWorkshopViewModel) -> some View {
        GeometryReader { geometry in
            let columnWidth = geometry.size.width / CGFloat(RedPacketEditingChannel.allCases.count)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: columnWidth / 2, y: 12))
                    path.addLine(to: CGPoint(x: geometry.size.width - columnWidth / 2, y: 12))
                }
                .stroke(Color.milensSeparator, lineWidth: 1)

                ForEach(Array(RedPacketEditingChannel.allCases.enumerated()), id: \.element) { index, channel in
                    let isSelected = selectedChannel == channel
                    channelButton(channel, isSelected: isSelected) {
                        select(channel: channel, viewModel: vm)
                    }
                    .frame(width: columnWidth, height: 72)
                    .position(
                        x: columnWidth * (CGFloat(index) + 0.5),
                        y: 36
                    )
                }
            }
        }
        .frame(height: 72)
        .padding(.horizontal, Spacing.pagePad)
        .background(Color.milensSealSurface)
    }

    private func channelButton(
        _ channel: RedPacketEditingChannel,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.milensActionPrimary.opacity(0.14) : Color.milensSealSurface)
                        .frame(width: 34, height: 34)
                    Circle()
                        .fill(isSelected ? Color.milensActionPrimary : Color.milensSeparator)
                        .frame(width: 5, height: 5)
                        .offset(y: -17)
                    Image(systemName: channel.icon)
                        .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextSecondary)
                }
                .frame(width: 34, height: 34)

                Text(channel.label)
                    .font(.editorialMetadata)
                    .foregroundStyle(isSelected ? Color.milensTextPrimary : Color.milensTextSecondary)
                .frame(height: 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if isSelected {
                    Capsule()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 20, height: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(channel.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(
        channel: RedPacketEditingChannel,
        viewModel: RedPacketWorkshopViewModel
    ) {
        selectedChannel = channel
        switch channel {
        case .pet:
            viewModel.activeLayerID = viewModel.layers.first { $0.kind == .pet }?.id
        case .accessory:
            showAccessoryPicker = true
        case .blessing:
            viewModel.activeLayerID = viewModel.layers.first { $0.kind == .text }?.id
        }
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
