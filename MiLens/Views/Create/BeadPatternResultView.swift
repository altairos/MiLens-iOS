//  BeadPatternResultView —— 拼豆图纸结果视图（对应源端 BeadPatternResult.ets）。
//  统计行 / 彩色-字母模式切换 / 缩放画布 / 保存高清图纸 / 分享 / 材料清单。
//  画布渲染走 MiLensKit drawBeadPattern（BeadViewModel.refreshPreview 重绘）。

import SwiftUI
import MiLensKit

struct BeadPatternResultView: View {
    @Bindable var vm: BeadViewModel
    @State private var shareItem: ShareItem?

    var body: some View {
        VStack(spacing: 0) {
            if let pattern = vm.pattern {
                statsRow(pattern)
                autoHint(pattern)
                modeChips
                if vm.viewMode != "color" && vm.cellSize * Int(vm.canvasScale) < 8 {
                    Text("💡 放大图纸即可显示编号")
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
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .onChange(of: vm.canvasScale) { _, _ in
            vm.refreshPreview()
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
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
                    .foregroundStyle(Color.milensPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - 模式切换

    private var modeChips: some View {
        HStack(spacing: 8) {
            modeChip("彩色", mode: "color")
            modeChip("字母序号", mode: "letter")
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
                .foregroundStyle(selected ? Color.milensTextOnAccent : Color.milensTextSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Color.milensPrimary : Color.milensGrouped)
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
                    .foregroundStyle(Color.milensPrimary)
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
                    .foregroundStyle(Color.milensPrimary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(Color.milensCard)
        .clipShape(Capsule())
        .padding(.top, 8)
    }

    // MARK: - 导出 / 分享

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                vm.export()
            } label: {
                Text(vm.isExporting ? "导出中..." : "保存高清图纸")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.milensTextOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.milensPrimary)
                    .clipShape(Capsule())
            }
            .disabled(vm.isExporting)

            Button {
                share()
            } label: {
                Text("分享")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.milensPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.milensCard)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.milensPrimary, lineWidth: 1)
                    )
            }
            .disabled(vm.isExporting)
        }
        .padding(.top, 8)
    }

    private func share() {
        Task { @MainActor in
            if let url = await vm.prepareShareFile() {
                shareItem = ShareItem(url: url)
            }
        }
    }

    // MARK: - 材料清单

    private func materialList(_ pattern: BeadPattern) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("材料清单")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.milensTextPrimary)
                .padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(beadMaterialRows(pattern)) { row in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(red: Double(row.rgb.r) / 255,
                                            green: Double(row.rgb.g) / 255,
                                            blue: Double(row.rgb.b) / 255))
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(row.letter)【\(row.symbol)】 \(row.name)")
                                    .font(.caption)
                                    .foregroundStyle(Color.milensTextSecondary)
                                Text("\(row.count) 颗 → 建议准备 \(row.suggestedBuyCount) 颗")
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
