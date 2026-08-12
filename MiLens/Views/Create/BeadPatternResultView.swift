//  BeadPatternResultView —— 拼豆图纸导出页（全屏预览，对应源端 BeadPatternResult.ets）。
//  统计行 / 彩色-字母模式切换 / 缩放画布 / 保存相册 / 分享 / A4 PDF / 材料清单。
//  画布渲染走 MiLensKit drawBeadPattern（BeadViewModel.refreshPreview 重绘）。

import SwiftUI
import MiLensKit

struct BeadPatternResultView: View {
    @Bindable var vm: BeadViewModel
    @Environment(\.proEntitlement) private var entitlement
    @State private var shareItem: ShareItem?
    @State private var showPaywall = false
    /// ADR-0010 分享预览面板状态。
    @State private var sharePreview: (image: UIImage, url: URL)?

    var body: some View {
        VStack(spacing: 0) {
            if let pattern = vm.pattern {
                statsRow(pattern)
                autoHint(pattern)
                modeChips
                if vm.viewMode != "color" && vm.cellSize * Int(vm.canvasScale) < 8 {
                    Text(String(localized: "create.bead.zoomHint"))
                        .font(.caption2)
                        .foregroundStyle(Color.milensTextTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                }
                canvas
                zoomRow
                actionButtons
                materialList(pattern)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.xxl)
        .background(Color.milensBackground)
        .onChange(of: vm.canvasScale) { _, _ in
            vm.refreshPreview()
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        // ADR-0010 分享预览面板
        .sheet(item: Binding<SharePreviewData?>(
            get: { sharePreview.map { SharePreviewData(image: $0.image, url: $0.url) } },
            set: { if $0 == nil { sharePreview = nil } }
        )) { data in
            SharePreviewSheet(
                previewImage: data.image,
                shareURL: data.url,
                onDismiss: { sharePreview = nil }
            )
        }
        // Pro 门控：未解锁时导出（保存相册/分享/PDF）拦截到付费墙
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
        }
        // 保存相册真正完成后的一次轻成功触感（UI-DESIGN.md §7）
        .sensoryFeedback(.success, trigger: vm.toastMessage) { _, new in
            new == .exportSuccess
        }
    }

    // MARK: - 统计行

    private func statsRow(_ pattern: BeadPattern) -> some View {
        Text(beadStatsLine(pattern))
            .font(.caption)
            .foregroundStyle(Color.milensTextTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func autoHint(_ pattern: BeadPattern) -> some View {
        Group {
            if let hint = pattern.autoColorHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(Color.milensActionPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - 模式切换

    private var modeChips: some View {
        HStack(spacing: 8) {
            modeChip(String(localized: "create.bead.mode.color"), mode: "color")
            modeChip(String(localized: "create.bead.mode.letter"), mode: "letter")
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    private func modeChip(_ label: String, mode: String) -> some View {
        let selected = vm.viewMode == mode
        return Button {
            vm.setViewMode(mode)
        } label: {
            Text(label)
                .font(.caption)
                .foregroundStyle(selected ? Color.milensTextOnActionPrimary : Color.milensTextSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Color.milensActionPrimary : Color.milensGrouped)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 画布 + 缩放

    private var canvas: some View {
        ScrollView([.horizontal, .vertical]) {
            Group {
                if let image = vm.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                } else {
                    ProgressView()
                        .frame(width: 300, height: 300)
                }
            }
            .frame(minWidth: 320, minHeight: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.milensBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.milensBorder, lineWidth: 0.5)
        )
    }

    private var zoomRow: some View {
        HStack {
            Button {
                vm.stepCanvasScale(-0.25)
            } label: {
                Text("−").font(.title3)
                    .frame(width: 40, height: 36)
                    .foregroundStyle(Color.milensActionPrimary)
            }
            Text("\(Int((vm.canvasScale * 100).rounded()))%")
                .font(.caption)
                .foregroundStyle(Color.milensTextSecondary)
                .frame(width: 50)
            Button {
                vm.stepCanvasScale(0.25)
            } label: {
                Text("+").font(.title3)
                    .frame(width: 40, height: 36)
                    .foregroundStyle(Color.milensActionPrimary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(Color.milensCard)
        .clipShape(Capsule())
        .padding(.top, 8)
    }

    // MARK: - 导出（基础 PNG 保存/分享免费，A4 PDF 作为 Pro/计划权益）

    private var actionButtons: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                vm.export()
            } label: {
                Text(vm.isExporting
                     ? String(localized: "create.bead.exporting")
                     : String(localized: "create.bead.saveAlbum"))
                    .font(.bodySecondary.weight(.medium))
                    .foregroundStyle(Color.milensTextOnActionPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.milensActionPrimary)
                    .clipShape(Capsule())
            }
            .disabled(vm.isExporting)

            Button {
                share()
            } label: {
                Text(String(localized: "common.share"))
                    .font(.bodySecondary.weight(.medium))
                    .foregroundStyle(Color.milensActionPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.milensCard)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.milensActionPrimary, lineWidth: 1)
                    )
            }
            .disabled(vm.isExporting)

            // A4 PDF 与 PNG 走同一渲染结果（renderA4Export），仅封装为单页 PDF；
            // 经系统分享面板可打印或存储到文件。
            Button {
                exportPDF()
            } label: {
                Text(String(localized: "create.bead.a4pdf"))
                    .font(.bodySecondary.weight(.medium))
                    .foregroundStyle(Color.milensActionPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.milensCard)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.milensActionPrimary, lineWidth: 1)
                    )
            }
            .disabled(vm.isExporting)
        }
        .padding(.top, Spacing.sm)
    }

    private func share() {
        Task { @MainActor in
            guard let url = await vm.prepareShareFile() else { return }
            if let preview = vm.previewImage {
                sharePreview = (image: preview, url: url)
            } else {
                shareItem = ShareItem(url: url)
            }
        }
    }

    private func exportPDF() {
        guard entitlement.isPro else { showPaywall = true; return }
        Task { @MainActor in
            if let url = await vm.preparePDFFile() {
                shareItem = ShareItem(url: url)
            }
        }
    }

    // MARK: - 材料清单

    private func materialList(_ pattern: BeadPattern) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "create.bead.materialList"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.milensTextPrimary)
                .padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(beadMaterialRows(pattern)) { row in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4) // ui-token:ok 业务动态色（拼豆调色板 RGB 数据）
                                .fill(Color(red: Double(row.rgb.r) / 255,
                                            green: Double(row.rgb.g) / 255,
                                            blue: Double(row.rgb.b) / 255))
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(row.letter)【\(row.symbol)】 \(row.name)")
                                    .font(.caption)
                                    .foregroundStyle(Color.milensTextSecondary)
                                Text(String(localized: "create.bead.materialCount \(row.count) \(row.suggestedBuyCount)"))
                                    .font(.caption2)
                                    .foregroundStyle(Color.milensTextTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(maxHeight: 180)
        }
        .padding(12)
        .background(Color.milensCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

// MARK: - 系统分享（UIActivityViewController 包装，对应源端 sharePattern 后的系统分享）

/// 分享文件包装（URL 不符合 Identifiable，sheet(item:) 需要）。
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
