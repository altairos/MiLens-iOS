//  BeadPatternResultView —— 拼豆图纸导出页（对照 Figma「10·拼豆结果」#211:492）。
//  Identity Strip + Pattern Workspace + Materials Summary + Export Dock。
//  画布渲染走 MiLensKit drawBeadPattern（BeadViewModel.refreshPreview 重绘）。
//  保存/分享/A4 PDF 导出逻辑。

import SwiftUI
import MiLensKit

struct BeadPatternResultView: View {
    @Bindable var vm: BeadViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.proEntitlement) private var entitlement
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var shareItem: ShareItem?
    @State private var showPaywall = false
    @State private var sharePreview: (image: UIImage, url: URL, filename: String, spec: String)?

    /// 是否处于 regular 宽度（iPad 竖屏 / 大尺寸横屏），启用双栏分栏。
    private var isRegularWidth: Bool { hSizeClass == .regular }

    var body: some View {
        Group {
            if isRegularWidth {
                iPadBody
            } else {
                compactBody
            }
        }
        .background(Color.milensBackground)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            customHeader
        }
        .overlay(alignment: .bottom) {
            if let message = vm.toastMessage {
                Text(beadToastText(message))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.bottom, 20)
            }
        }
        .onChange(of: vm.canvasScale) { _, _ in vm.refreshPreview() }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(item: Binding<SharePreviewData?>(
            get: { sharePreview.map { SharePreviewData(image: $0.image, url: $0.url, filename: $0.filename, spec: $0.spec) } },
            set: { if $0 == nil { sharePreview = nil } }
        )) { data in
            SharePreviewSheet(
                previewImage: data.image,
                shareURL: data.url,
                filename: data.filename,
                spec: data.spec,
                onDismiss: { sharePreview = nil }
            )
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
        }
        .sensoryFeedback(.success, trigger: vm.toastMessage) { _, new in
            new == .exportSuccess
        }
    }

    // MARK: - iPhone 紧凑布局

    private var compactBody: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let pattern = vm.pattern {
                    identityStrip(pattern)
                    patternWorkspace(pattern)
                    materialsSummary(pattern)
                    exportDock
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - iPad 双栏分栏（对照 Figma #313:921 Adaptive Workspace）

    /// 左列（Pattern Canvas Column，408pt）：统计 + 画布 + 材料清单；
    /// 右列（Export Inspector，354pt）：身份条 + 显示方式 + 导出面板。中间 24pt 间距。
    private var iPadBody: some View {
        HStack(alignment: .top, spacing: AdaptiveColumn.splitGap) {
            if let pattern = vm.pattern {
                // 左列：画布工作区
                ScrollView {
                    VStack(spacing: 14) {
                        patternWorkspace(pattern)
                        materialsSummary(pattern)
                    }
                    .padding(.bottom, Spacing.xxl)
                }
                .frame(width: AdaptiveColumn.studioSource)
                .scrollIndicators(.hidden)

                // 右列：导出检查器
                ScrollView {
                    VStack(spacing: 14) {
                        identityStrip(pattern)
                        BeadResultOutputPanel(
                            isExporting: vm.isExporting,
                            onExport: { vm.export() },
                            onShare: { share() },
                            onA4Export: { handleA4Export() }
                        )
                    }
                    .padding(.bottom, Spacing.xxl)
                }
                .frame(width: AdaptiveColumn.studioInspector)
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, Spacing.xxl)
    }

    // MARK: - 自定义头部（WorkshopNavHeader 统一风格）

    private var customHeader: some View {
        WorkshopNavHeader(title: String(localized: "create.bead.studio")) {
            dismiss()
        }
    }

    // MARK: - Identity Strip（对照 #301:981）

    private func identityStrip(_ pattern: BeadPattern) -> some View {
        HStack(spacing: 0) {
            // Registration Rail（珊瑚 3pt）
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3)
                .padding(.vertical, 14)

            // 来源照片 40×40
            if !vm.thumbnailPath.isEmpty || !vm.photoURI.isEmpty {
                ThumbnailImage(path: vm.thumbnailPath.isEmpty ? vm.photoURI : vm.thumbnailPath)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(.leading, 7)
            }

            // 标签 + Meta
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "create.bead.title"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextPrimary)
                Text(identityMeta(pattern))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensActionPrimary)
            }
            .padding(.leading, 10)

            Spacer()

            // Action（调整方案）
            VStack(alignment: .trailing, spacing: 4) {
                Button {
                    dismiss()
                } label: {
                    Text(String(localized: "create.bead.adjust"))
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensActionPrimary)
                }
                .buttonStyle(.plain)
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 22, height: 1)
            }
            .padding(.trailing, 14)
        }
        .frame(height: 60)
        .background(Color.milensGrouped)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func identityMeta(_ pattern: BeadPattern) -> String {
        BeadResultDisplayLogic.identityMeta(
            width: pattern.width, height: pattern.height, colorCount: pattern.score.colorCount
        )
    }

    // MARK: - Pattern Workspace（对照 #211:503-509）

    private func patternWorkspace(_ pattern: BeadPattern) -> some View {
        VStack(spacing: 0) {
            // 统计行（对照 #211:504）
            Text(beadStatsLine(pattern))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            // View Mode 选择器（对照 #288:591, 204×34 分段控件）
            viewModeSelector
                .padding(.bottom, 12)

            // Bead Board（暗色画布，对照 #211:509, 240×240）
            beadBoard
                .frame(maxWidth: .infinity)

            // Zoom Range（对照 #288:607）
            zoomRange
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
        .background(Color.milensGrouped)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - View Mode 分段选择器（对照 #288:591）

    private var viewModeSelector: some View {
        HStack(spacing: 0) {
            viewModeSegment(String(localized: "create.bead.mode.color"), mode: "color")
            viewModeSegment(String(localized: "create.bead.mode.letter"), mode: "letter")
        }
        .frame(width: 204, height: 34)
        .background(Color.milensGrouped)
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func viewModeSegment(_ label: String, mode: String) -> some View {
        let selected = vm.viewMode == mode
        return Button {
            vm.setViewMode(mode)
        } label: {
            Text(label)
                .font(.editorialMetadata)
                .foregroundStyle(selected ? Color.white : Color.milensTextSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(selected ? Color.milensActionPrimary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bead Board（暗色画布，对照 #211:509）

    private var beadBoard: some View {
        Group {
            if let image = vm.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(0)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.milensInk)
                    .frame(width: 240, height: 240)
                    .overlay(ProgressView().tint(.white))
            }
        }
    }

    // MARK: - Zoom Range（对照 #288:607）

    private var zoomRange: some View {
        HStack(spacing: 8) {
            Button {
                vm.stepCanvasScale(-0.25)
            } label: {
                Text("\u{2212}")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensActionPrimary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            // 轨道
            GeometryReader { geo in
                let trackWidth = geo.size.width - 48
                let progress = BeadResultDisplayLogic.zoomProgress(canvasScale: vm.canvasScale)
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.milensBorder)
                        .frame(height: 2)
                    Rectangle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: trackWidth * progress, height: 2)
                    Circle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 10, height: 10)
                        .offset(x: trackWidth * progress - 5)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 24)

            Button {
                vm.stepCanvasScale(0.25)
            } label: {
                Text("+")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensActionPrimary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 204, height: 44)
    }

    // MARK: - Materials Summary（对照 #211:957-976）

    private func materialsSummary(_ pattern: BeadPattern) -> some View {
        let rows = Array(beadMaterialRows(pattern).prefix(8))
        return VStack(alignment: .leading, spacing: 0) {
            // 标题行
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "create.bead.materialList"))
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextPrimary)
                Text("\(pattern.score.colorCount) 色 · 按用量排序")
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextTertiary)
                Spacer()
                Text(String(localized: "create.bead.viewAll"))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensActionPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, 8)

            // 色板横排（对照 #211:961-976）
            if !rows.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(rows) { row in
                            VStack(spacing: 3) {
                                Circle() // ui-token:ok 业务动态色（拼豆调色板 RGB 数据）
                                    .fill(Color(red: Double(row.rgb.r) / 255,
                                                green: Double(row.rgb.g) / 255,
                                                blue: Double(row.rgb.b) / 255))
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle().stroke(Color.milensInk.opacity(0.7), lineWidth: 0.7)
                                    )
                                Text("\(row.letter)\(row.symbol)")
                                    .font(.editorialOverline)
                                    .foregroundStyle(Color.milensTextTertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 13)
                }
                .frame(height: 50)
            }
        }
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Export Dock（对照 #211:977-983）

    private var exportDock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "create.bead.export.title"))
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 13)

            Text(String(localized: "create.bead.export.desc"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextTertiary)
                .padding(.horizontal, 16)
                .padding(.top, 5)

            // 按钮行
            HStack(spacing: 12) {
                // Darkroom Pulse 主按钮（保存高清图纸）
                Button {
                    vm.export()
                } label: {
                    Group {
                        if vm.isExporting {
                            ProgressView().tint(.white)
                        } else {
                            Text(String(localized: "create.bead.saveHd"))
                                .font(.buttonLabel)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(vm.isExporting)

                // 分享按钮
                Button {
                    share()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Color.milensCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(Color.milensBorder, lineWidth: 1)
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: Sizing.iconSm, weight: .medium))
                            .foregroundStyle(Color.milensActionPrimary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(vm.isExporting)

                // A4 PDF 图纸按钮（Pro 专属，免费用户点击弹付费墙）
                Button {
                    handleA4Export()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Color.milensCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(Color.milensBorder, lineWidth: 1)
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: "doc.text")
                            .font(.system(size: Sizing.iconSm, weight: .medium))
                            .foregroundStyle(Color.milensActionPrimary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(vm.isExporting)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(Color.milensGrouped)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - 导出逻辑

    private func share() {
        Task { @MainActor in
            guard let url = await vm.prepareShareFile() else { return }
            if let preview = vm.previewImage {
                let filename = url.lastPathComponent
                let spec = "PNG"
                sharePreview = (image: preview, url: url, filename: filename, spec: spec)
            } else {
                shareItem = ShareItem(url: url)
            }
        }
    }

    /// A4 PDF 图纸导出（Pro 专属；免费用户弹付费墙）。
    private func handleA4Export() {
        guard entitlement.isPro else {
            showPaywall = true
            return
        }
        Task { @MainActor in
            guard let url = await vm.preparePDFFile() else { return }
            shareItem = ShareItem(url: url)
        }
    }
}
