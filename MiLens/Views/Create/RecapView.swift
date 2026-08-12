//  RecapView —— 月度精选 / 年度回忆册（情感触点系统 Stage 3，ADR-0010 §3.3）。
//
//  从全部照片构建年度回忆册（MemoryRecapLogic 纯逻辑选片），
//  12 个月代表照片网格预览，Pro 完整长图导出（ImageRenderer，不新建渲染管线，ADR §10.12）。
//  免费版可预览全部代表照片缩略图；导出为 Pro 专属。

import SwiftUI
import MiLensKit
import os

private let logger = Logger(subsystem: "com.milens.app", category: "RecapView")

struct RecapView: View {
    @Environment(\.viewModelFactory) private var factory
    @Environment(\.proEntitlement) private var entitlement
    @Environment(\.dismiss) private var dismiss

    /// 初始年份（从路由/首页传入；nil 默认当前年）。
    let initialYear: Int?

    @State private var photos: [Photo] = []
    @State private var pets: [Pet] = []
    @State private var selectedYear: Int
    @State private var isLoading = true
    @State private var showPaywall = false
    @State private var sharePreview: (image: UIImage, url: URL, filename: String, spec: String)?
    @State private var isExporting = false
    @State private var exportError: String?

    init(year: Int? = nil) {
        self.initialYear = year
        let now = Calendar.current.component(.year, from: Date())
        _selectedYear = State(initialValue: year ?? now)
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkshopNavHeader(title: String(localized: "recap.title")) {
                dismiss()
            } trailing: {
                Button {
                    handleExport()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: Sizing.iconLg))
                        .foregroundStyle(Color.milensTextPrimary)
                        .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
                }
                .disabled(isExporting || recap == nil)
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if availableYears.isEmpty {
                emptyState
            } else {
                recapContent
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(Color.milensBackground)
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
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
        .alert(String(localized: "recap.exportFailed"), isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .task { await load() }
    }

    // MARK: - 数据投影

    /// 全部照片转为 RecapPhoto 投影（供 MemoryRecapLogic 纯逻辑选片）。
    private var recapPhotos: [RecapPhoto] {
        photos.map { ph in
            RecapPhoto(
                id: ph.id,
                takenAt: ph.takenAt,
                qualityScore: ph.qualityScore,
                isBest: ph.isBest,
                duplicateOf: ph.duplicateOf,
                petID: ph.pet?.id
            )
        }
    }

    /// 当前选中年份的年度回忆册。
    private var recap: YearlyRecap? {
        let r = MemoryRecapLogic.yearlyRecap(photos: recapPhotos, year: selectedYear)
        return r.months.isEmpty ? nil : r
    }

    /// 照片 ID → 缩略图路径映射（用于代表照片展示）。
    private var thumbnailMap: [UUID: Photo] {
        Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
    }

    /// 可用年份列表（有照片的年份，降序）。
    private var availableYears: [Int] {
        let cal = Calendar.current
        let years = Set(photos.compactMap { ph in
            ph.takenAt.map { cal.component(.year, from: $0) }
        })
        return years.sorted(by: >)
    }

    // MARK: - 内容区

    private var recapContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // 年份选择器
                yearSelector

                // 年度统计
                if let recap {
                    statsHeader(recap)
                }

                // 月度精选网格
                if let recap {
                    ForEach(recap.months, id: \.month) { month in
                        monthSection(month)
                    }
                }
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.vertical, Spacing.sm)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 年份选择器

    private var yearSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(availableYears, id: \.self) { year in
                    Button {
                        withAnimation(.easeInOut(duration: Motion.durationFast)) {
                            selectedYear = year
                        }
                    } label: {
                        Text(String(year))
                            .font(.system(size: 16, weight: selectedYear == year ? .bold : .medium))
                            .foregroundStyle(selectedYear == year ? Color.milensActionPrimary : Color.milensTextSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                selectedYear == year ? Color.milensAccentSoft : Color.clear,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    // MARK: - 年度统计

    private func statsHeader(_ recap: YearlyRecap) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(MemoryRecapLogic.yearlyTitle(year: recap.year))
                .font(.custom("LXGWWenKai-Regular", size: 28, relativeTo: .title2))
                .foregroundStyle(Color.milensTextPrimary)
            Text(String(localized: "recap.totalPhotos \(recap.totalPhotoCount)"))
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
        }
        .padding(.top, Spacing.sm)
    }

    // MARK: - 月度精选

    private func monthSection(_ month: MonthlyRecap) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // 月份标题
            HStack {
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 3, height: 16)
                Text(MemoryRecapLogic.monthlyTitle(year: month.year, month: month.month))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                Text(String(localized: "recap.monthCount \(month.totalPhotoCount)"))
                    .font(.caption)
                    .foregroundStyle(Color.milensTextTertiary)
            }

            // 代表照片横滑网格
            let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(month.photoIDs, id: \.self) { photoID in
                    if let photo = thumbnailMap[photoID] {
                        let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
                        ThumbnailImage(path: path)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .accessibilityLabel(String(localized: "recap.monthPhoto \(MemoryRecapLogic.monthlyTitle(year: month.year, month: month.month))"))
                    }
                }
            }
        }
        .padding(.bottom, Spacing.md)
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.milensTextSecondary)
            Text(String(localized: "recap.empty.title"))
                .font(.displayMedium)
                .foregroundStyle(Color.milensTextPrimary)
            Text(String(localized: "recap.empty.body"))
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Spacing.pagePad)
    }

    // MARK: - 导出（Pro 专属）

    private func handleExport() {
        guard entitlement.isPro else {
            showPaywall = true
            return
        }
        guard let recap else { return }

        MetricsRecorder().record(.exportStarted)
        isExporting = true
        let quality = ExportQuality.high.resolved(isPro: entitlement.isPro)
        let canvas = RecapExportCanvas(
            year: recap.year,
            months: recap.months,
            thumbnailMap: thumbnailMap,
            quality: quality
        )
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1

        guard let image = renderer.uiImage,
              let pngData = image.pngData() else {
            exportError = String(localized: "recap.renderFailed")
            isExporting = false
            return
        }

        do {
            let filename = "recap_\(recap.year).png"
            let url = try BeadExportService().writeShareCache(
                data: pngData, filename: filename
            )
            let spec = "PNG · \(formatByteCount(pngData.count))"
            sharePreview = (image: image, url: url, filename: filename, spec: spec)
            MetricsRecorder().record(.exportCompleted)
        } catch {
            exportError = String(localized: "recap.exportFailedDetail \(error.localizedDescription)")
        }
        isExporting = false
    }

    /// 格式化字节数为可读字符串（KB/MB）。
    private func formatByteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - 数据加载

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            photos = try factory.photoList(limit: 2000)
        } catch {
            photos = []
            logger.error("load: 读取照片失败（\(error.localizedDescription)）")
        }
        do {
            pets = try factory.allPets()
        } catch {
            pets = []
            logger.error("load: 读取宠物失败（\(error.localizedDescription)）")
        }
    }
}

// MARK: - 回忆册导出 Canvas（ImageRenderer 离屏渲染，不新建渲染管线 ADR §10.12）

/// 年度回忆册导出长图：封面年份 + 月度精选照片网格。
/// 宽度随 ExportQuality 门控（standard 1080 / high 2400）。
private struct RecapExportCanvas: View {
    let year: Int
    let months: [MonthlyRecap]
    let thumbnailMap: [UUID: Photo]
    let quality: ExportQuality

    private var scale: CGFloat { CGFloat(quality.maxLongEdgePixels) / 1080 }
    private var columns: Int { 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 40 * scale)

            ForEach(months, id: \.month) { month in
                monthBlock(month)
                    .padding(.bottom, 32 * scale)
            }
        }
        .padding(60 * scale)
        .frame(width: CGFloat(quality.maxLongEdgePixels), alignment: .leading)
        .background(Color.white)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16 * scale) {
            Text(MemoryRecapLogic.yearlyTitle(year: year))
                .font(.custom("LXGWWenKai-Regular", size: 56 * scale))
                .foregroundStyle(Color.milensTextPrimary)
        }
    }

    private func monthBlock(_ month: MonthlyRecap) -> some View {
        VStack(alignment: .leading, spacing: 16 * scale) {
            HStack {
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 3 * scale, height: 20 * scale)
                Text(MemoryRecapLogic.monthlyTitle(year: month.year, month: month.month))
                    .font(.system(size: 26 * scale, weight: .semibold))
                    .foregroundStyle(Color.milensTextPrimary)
            }

            let cols = Array(repeating: GridItem(.flexible(), spacing: 8 * scale), count: columns)
            LazyVGrid(columns: cols, spacing: 8 * scale) {
                ForEach(month.photoIDs, id: \.self) { photoID in
                    photoCell(photoID)
                }
            }
        }
    }

    @ViewBuilder
    private func photoCell(_ photoID: UUID) -> some View {
        if let photo = thumbnailMap[photoID] {
            let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
            ThumbnailImage(path: path)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
        } else {
            Rectangle()
                .fill(Color.milensGrouped)
                .aspectRatio(1, contentMode: .fit)
        }
    }
}
