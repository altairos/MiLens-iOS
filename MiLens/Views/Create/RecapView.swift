//  RecapView —— 月度精选 / 年度回忆册（情感触点系统 Stage 3，ADR-0010 §3.3）。
//
//  从全部照片构建年度回忆册（MemoryRecapLogic 纯逻辑选片），
//  12 个月代表照片网格预览，Pro 完整长图导出（ImageRenderer，不新建渲染管线，ADR §10.12）。
//  免费版可预览全部代表照片缩略图；导出为 Pro 专属。

import SwiftUI
import UIKit
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

    /// 导出画布每月代表照片上限（内存校准：2400px 宽长图峰值内存控制）。
    /// 预览网格用 8 张/月；导出降到 3 张/月（3 列 1 行），避免 12 月 × 多行超高画布爆内存。
    private static let exportPhotosPerMonth = 3

    private func handleExport() {
        guard entitlement.isPro else {
            showPaywall = true
            return
        }
        guard let recap else { return }

        MetricsRecorder().record(.exportStarted)
        isExporting = true

        let quality = ExportQuality.high.resolved(isPro: entitlement.isPro)
        // 提取 photoID → 缩略图路径（Sendable，可跨 actor 传递；Photo 是 SwiftData @Model 不可跨 actor）。
        let pathMap: [UUID: String] = Dictionary(
            uniqueKeysWithValues: thumbnailMap.compactMap { id, photo in
                let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
                return path.isEmpty ? nil : (id, path)
            })
        let year = recap.year
        let months = recap.months

        // 后台线程渲染：autoreleasepool 确保 CoreGraphics 中间缓冲及时释放；
        // JPEG（非 PNG）大幅降低照片拼贴的内存占用。
        Task.detached(priority: .utility) {
            let outcome = Self.renderRecapImage(
                year: year, months: months, pathMap: pathMap, quality: quality)
            await MainActor.run {
                isExporting = false
                switch outcome {
                case .success(let rendered):
                    guard let preview = UIImage(data: rendered.previewData) else {
                        exportError = String(localized: "recap.renderFailed")
                        return
                    }
                    sharePreview = (image: preview, url: rendered.url,
                                    filename: rendered.filename, spec: rendered.spec)
                    MetricsRecorder().record(.exportCompleted)
                case .failure(let message):
                    exportError = message
                }
            }
        }
    }

    // MARK: - 离屏渲染（后台线程 + autoreleasepool）

    /// 离屏渲染结果（全部 Sendable，可从后台线程返回主线程）。
    private struct RenderedRecap: Sendable {
        let url: URL
        let filename: String
        let spec: String
        /// 降采样预览 JPEG（供分享预览 sheet 展示，非全分辨率长图）。
        let previewData: Data
    }

    /// 渲染年度回忆册长图：预加载降采样缩略图 → ImageRenderer → JPEG 编码 → 写缓存。
    /// 必须在后台线程调用（autoreleasepool 控制 CoreGraphics 峰值内存）。
    /// 静态方法无实例捕获，闭包引用可安全跨 actor 传递。
    private static func renderRecapImage(
        year: Int, months: [MonthlyRecap],
        pathMap: [UUID: String], quality: ExportQuality
    ) -> Result<RenderedRecap, String> {
        autoreleasepool {
            // 1. 预加载降采样缩略图（每格约 宽度/3，避免全分辨率原图进画布）。
            // 每月仅取前 exportPhotosPerMonth 张（内存校准：控制长图高度）。
            let cellPixelSize = Int(CGFloat(quality.maxLongEdgePixels) / 3.0) + 1
            var imageMap: [UUID: UIImage] = [:]
            for month in months {
                for photoID in month.photoIDs.prefix(exportPhotosPerMonth) where imageMap[photoID] == nil {
                    if let path = pathMap[photoID] {
                        imageMap[photoID] = loadDownsampled(path: path, maxPixelSize: cellPixelSize)
                    }
                }
            }

            // 2. 构建 + 渲染画布。
            let canvas = RecapExportCanvas(
                year: year, months: months, imageMap: imageMap,
                quality: quality, photosPerMonth: exportPhotosPerMonth)
            let renderer = ImageRenderer(content: canvas)
            renderer.scale = 1
            guard let image = renderer.uiImage else {
                return .failure(String(localized: "recap.renderFailed"))
            }

            // 3. JPEG 编码（照片拼贴用 JPEG 远小于 PNG）。
            guard let data = image.jpegData(compressionQuality: quality.jpegCompressionQuality) else {
                return .failure(String(localized: "recap.renderFailed"))
            }

            // 4. 降采样预览（长边 1080，供分享 sheet 展示，避免常驻全分辨率长图）。
            let previewData = downscalePreview(image: image, maxDimension: 1080) ?? data

            // 5. 写入分享缓存。
            let filename = "recap_\(year).jpg"
            do {
                let url = try BeadExportService().writeShareCache(data: data, filename: filename)
                let spec = "JPEG · \(formatByteCount(data.count))"
                return .success(RenderedRecap(
                    url: url, filename: filename, spec: spec, previewData: previewData))
            } catch {
                return .failure(String(localized: "recap.exportFailedDetail \(error.localizedDescription)"))
            }
        }
    }

    /// 从文件路径加载降采样 UIImage（CGImageSource thumbnail，避免全分辨率图占满内存）。
    private static func loadDownsampled(path: String, maxPixelSize: Int) -> UIImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else {
            return UIImage(contentsOfFile: path)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(contentsOfFile: path)
        }
        return UIImage(cgImage: cgImage)
    }

    /// 将渲染长图降采样为预览 JPEG Data（maxDimension 为长边像素上限）。
    private static func downscalePreview(image: UIImage, maxDimension: CGFloat) -> Data? {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxDimension else {
            return image.jpegData(compressionQuality: 0.85)
        }
        let scale = maxDimension / longEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).jpegData(
            withCompressionQuality: 0.85
        ) { ctx in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// 格式化字节数为可读字符串（KB/MB）。
    private static func formatByteCount(_ bytes: Int) -> String {
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
/// 缩略图由调用方预加载降采样 UIImage 传入（ImageRenderer 同步渲染不执行 ThumbnailImage 的 .task）。
private struct RecapExportCanvas: View {
    let year: Int
    let months: [MonthlyRecap]
    let imageMap: [UUID: UIImage]
    let quality: ExportQuality
    /// 每月导出照片上限（内存校准：控制长图高度）。
    let photosPerMonth: Int

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
                ForEach(Array(month.photoIDs.prefix(photosPerMonth)), id: \.self) { photoID in
                    photoCell(photoID)
                }
            }
        }
    }

    @ViewBuilder
    private func photoCell(_ photoID: UUID) -> some View {
        if let image = imageMap[photoID] {
            Image(uiImage: image)
                .resizable()
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
