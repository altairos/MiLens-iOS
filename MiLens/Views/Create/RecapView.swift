//  RecapView —— 月度精选 / 年度回忆册（情感触点系统 Stage 3，ADR-0010 §3.3）。
//
//  从全部照片构建年度回忆册（MemoryRecapLogic 纯逻辑选片），
//  12 个月代表照片网格预览，Pro 手机分页图片组导出（共享 ArchiveShareTemplate）。
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
    @State private var sharePreview: SharePreviewData?
    @State private var isExporting = false
    @State private var exportTask: Task<Void, Never>?
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
        .sheet(item: $sharePreview) { data in
            SharePreviewSheet(
                previewImage: data.image,
                shareURL: data.url,
                additionalPreviewImages: data.additionalImages,
                additionalShareURLs: data.additionalURLs,
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
        .onDisappear {
            exportTask?.cancel()
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

    /// 年份选择器：出现/切换时滚动定位到选中年份（列表降序，老年份初始在屏幕外）。
    private var yearSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(availableYears, id: \.self) { year in
                        Button {
                            withAnimation(.easeInOut(duration: Motion.durationFast)) {
                                selectedYear = year
                            }
                        } label: {
                            Text(String(year))
                                .font(.bodyPrimary)
                                .foregroundStyle(selectedYear == year ? Color.milensActionPrimary : Color.milensTextSecondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    selectedYear == year ? Color.milensAccentSoft : Color.clear,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .id(year)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            .task {
                // 等首帧布局完成后再定位，避免 scrollTo 在布局前调用落空。
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
                proxy.scrollTo(selectedYear, anchor: .center)
            }
            .onChange(of: selectedYear) { _, year in
                withAnimation(.easeInOut(duration: Motion.durationFast)) {
                    proxy.scrollTo(year, anchor: .center)
                }
            }
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
                    .font(.uiBodyStrong)
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
                .font(.system(size: 40, weight: .light)) // ui-token:ok 空态装饰大图标
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
        // 提取 photoID → 缩略图路径（Sendable，可跨 actor 传递；Photo 是 SwiftData @Model 不可跨 actor）。
        let pathMap: [UUID: String] = Dictionary(
            uniqueKeysWithValues: thumbnailMap.compactMap { id, photo in
                let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
                return path.isEmpty ? nil : (id, path)
            })
        let year = recap.year
        let months = recap.months
        let totalPhotoCount = recap.totalPhotoCount

        exportTask?.cancel()
        exportTask = Task {
            let outcome = await ArchiveShareRendering.renderAnnualRecap(
                year: year,
                months: months,
                totalPhotoCount: totalPhotoCount,
                pathMap: pathMap,
                quality: quality
            )
            switch outcome {
            case .success(let bundle):
                let images = bundle.pages.compactMap { UIImage(data: $0.previewData) }
                guard images.count == bundle.pages.count else {
                    exportError = String(localized: "recap.renderFailed")
                    isExporting = false
                    return
                }
                guard let image = images.first, let url = bundle.pages.first?.url else { return }
                sharePreview = SharePreviewData(
                    image: image,
                    url: url,
                    additionalImages: Array(images.dropFirst()),
                    additionalURLs: bundle.pages.dropFirst().map(\.url),
                    filename: bundle.filename,
                    spec: bundle.spec
                )
                MetricsRecorder().record(.exportCompleted)
            case .failure(let message):
                exportError = message
            case .cancelled:
                break
            }
            isExporting = false
        }
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
