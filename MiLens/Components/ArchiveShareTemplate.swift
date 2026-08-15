//  ArchiveShareTemplate —— 成长时间线 / 年度回忆册共享手机长图模板。
//
//  设计基准：390 × 1260pt，每页独立阅读；ImageRenderer 固定 3× 输出。
//  封面、月份标题、真实缩略图条目和页脚由两种归档共用。

import SwiftUI
import UIKit
import MiLensKit

enum ArchiveShareLayout {
    static let logicalWidth: CGFloat = 390
    static let pageHeight: CGFloat = 1_260
    static let renderScale: CGFloat = 3
    static let pixelWidth = Int(logicalWidth * renderScale)
    static let pixelHeight = Int(pageHeight * renderScale)
    static let horizontalPadding: CGFloat = 24
    static let footerHeight: CGFloat = 76
    static let coverHeight: CGFloat = 520
    static let photosPerMonth = 3
}

struct ArchiveSharePageShell<Content: View>: View {
    let stats: String
    let pageNumber: Int
    let pageCount: Int
    let includeWatermark: Bool
    let content: Content

    init(
        stats: String,
        pageNumber: Int,
        pageCount: Int,
        includeWatermark: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.stats = stats
        self.pageNumber = pageNumber
        self.pageCount = pageCount
        self.includeWatermark = includeWatermark
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            ArchiveShareFooter(
                stats: stats,
                pageNumber: pageNumber,
                pageCount: pageCount,
                includeWatermark: includeWatermark
            )
        }
        .frame(width: ArchiveShareLayout.logicalWidth, height: ArchiveShareLayout.pageHeight)
        .background(Color.milensPaper)
        .environment(\.colorScheme, .light)
        .clipped()
    }
}

struct ArchiveShareCover: View {
    enum Mode {
        case timeline
        case annual

        var overline: String {
            switch self {
            case .timeline: return "MiLens · GROWTH ARCHIVE"
            case .annual: return "MiLens · YEARLY ARCHIVE"
            }
        }
    }

    let mode: Mode
    let title: String
    let summary: String
    let index: String
    let heroImage: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let heroImage {
                    Image(uiImage: heroImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.milensGrouped
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 44, weight: .regular)) // ui-token:ok 导出模板装饰图标
                            .foregroundStyle(Color.milensTextTertiary)
                    }
                }
            }
            .frame(width: ArchiveShareLayout.logicalWidth, height: 280)
            .clipped()

            VStack(alignment: .leading, spacing: 0) {
                Text(mode.overline)
                    .font(.system(size: 9, weight: .medium)) // ui-token:ok 固定导出画布字号
                    .tracking(0.5)
                    .foregroundStyle(Color.milensActionPrimary)
                Text(title)
                    .font(.custom("LXGWWenKai-Regular", size: 28))
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(2)
                    .padding(.top, 10)
                Text(summary)
                    .font(.system(size: 12)) // ui-token:ok 固定导出画布字号
                    .foregroundStyle(Color.milensTextSecondary)
                    .lineLimit(2)
                    .padding(.top, 8)
                Spacer(minLength: 10)
                Text(index)
                    .font(.custom("Fraunces-Bold", size: 26))
                    .foregroundStyle(Color.milensActionPrimary)
            }
            .padding(.horizontal, ArchiveShareLayout.horizontalPadding)
            .padding(.vertical, 20)
            .frame(width: ArchiveShareLayout.logicalWidth, height: 240, alignment: .leading)
        }
        .frame(height: ArchiveShareLayout.coverHeight)
    }
}

struct ArchiveShareMonthHeader: View {
    let year: Int
    let month: Int
    let countLabel: String

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3, height: 28)
            Text(String(localized: "timeline.month \(month)"))
                .font(.custom("LXGWWenKai-Regular", size: 24))
                .foregroundStyle(Color.milensTextPrimary)
                .padding(.leading, 16)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%04d · %02d", year, month))
                    .font(.system(size: 8, weight: .medium)) // ui-token:ok 固定导出画布字号
                    .foregroundStyle(Color.milensActionPrimary)
                Text(countLabel)
                    .font(.system(size: 8)) // ui-token:ok 固定导出画布字号
                    .foregroundStyle(Color.milensTextSecondary)
            }
        }
        .frame(height: 56)
    }
}

struct ArchiveShareTimelineEntry: View {
    let entry: TimelineEntry
    let image: UIImage?

    private var rowHeight: CGFloat {
        CGFloat(ArchiveSharePagination.entryHeight(for: entry.type))
    }

    private var imageSize: CGSize {
        switch entry.type {
        case .photoNote:
            return CGSize(width: 124, height: 168)
        case .workRecord:
            return CGSize(width: 124, height: 124)
        case .birthday, .adoption, .textNote:
            return CGSize(width: 92, height: 92)
        }
    }

    private var note: String {
        let body = entry.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? entry.subtitle : body
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            photo
                .frame(width: imageSize.width, height: imageSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(TimelineLogic.isoDateString(from: entry.date))
                    .font(.system(size: 8, weight: .medium)) // ui-token:ok 固定导出画布字号
                    .foregroundStyle(Color.milensActionPrimary)
                Text(entry.title)
                    .font(.custom("LXGWWenKai-Regular", size: 19))
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(2)
                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11)) // ui-token:ok 固定导出画布字号
                        .foregroundStyle(Color.milensTextSecondary)
                        .lineLimit(entry.type == .photoNote ? 3 : 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: rowHeight)
    }

    @ViewBuilder
    private var photo: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            ZStack {
                Color.milensGrouped
                Image(systemName: entry.type == .workRecord ? "square.grid.3x3.fill" : "pawprint.fill")
                    .font(.system(size: 18, weight: .regular)) // ui-token:ok 导出模板占位图标
                    .foregroundStyle(Color.milensTextTertiary)
            }
        }
    }
}

struct ArchiveShareRecapStrip: View {
    let month: MonthlyRecap
    let imageMap: [UUID: UIImage]

    private var photoIDs: [UUID] {
        Array(month.photoIDs.prefix(ArchiveShareLayout.photosPerMonth))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(0..<ArchiveShareLayout.photosPerMonth, id: \.self) { index in
                    photoCell(at: index)
                }
            }
            Text(String(localized: "recap.monthCount \(month.totalPhotoCount)"))
                .font(.system(size: 9)) // ui-token:ok 固定导出画布字号
                .foregroundStyle(Color.milensTextSecondary)
        }
        .frame(height: 158, alignment: .topLeading)
    }

    @ViewBuilder
    private func photoCell(at index: Int) -> some View {
        let photoID = index < photoIDs.count ? photoIDs[index] : nil
        Group {
            if let photoID, let image = imageMap[photoID] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.milensGrouped
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .regular)) // ui-token:ok 导出模板占位图标
                        .foregroundStyle(Color.milensTextTertiary)
                }
            }
        }
        .frame(width: 108, height: 108)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct ArchiveShareFooter: View {
    let stats: String
    let pageNumber: Int
    let pageCount: Int
    let includeWatermark: Bool

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MiLens")
                    .font(.custom("Fraunces-Bold", size: 12))
                    .foregroundStyle(Color.milensActionPrimary)
                Text(includeWatermark ? String(localized: "timeline.export.watermark") : stats)
                    .font(.system(size: 8)) // ui-token:ok 固定导出画布字号
                    .foregroundStyle(Color.milensTextSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(String(format: "%02d / %02d", pageNumber, pageCount))
                .font(.system(size: 9, weight: .medium)) // ui-token:ok 固定导出画布字号
                .foregroundStyle(Color.milensTextPrimary)
        }
        .padding(.horizontal, ArchiveShareLayout.horizontalPadding)
        .padding(.vertical, 16)
        .frame(height: ArchiveShareLayout.footerHeight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.milensSeparator)
                .frame(height: 0.5)
                .padding(.horizontal, ArchiveShareLayout.horizontalPadding)
        }
    }
}

struct RecapExportCanvas: View {
    let year: Int
    let page: AnnualArchiveSharePage
    let imageMap: [UUID: UIImage]
    let coverHeroImage: UIImage?
    let totalPhotoCount: Int
    let totalMonthCount: Int
    let pageNumber: Int
    let pageCount: Int
    let includeWatermark: Bool

    private var heroImage: UIImage? {
        coverHeroImage ?? page.months.lazy
            .flatMap(\.photoIDs)
            .compactMap { imageMap[$0] }
            .first
    }

    private var stats: String {
        "\(MemoryRecapLogic.yearlyTitle(year: year)) · \(String(localized: "recap.monthCount \(totalPhotoCount)"))"
    }

    var body: some View {
        ArchiveSharePageShell(
            stats: stats,
            pageNumber: pageNumber,
            pageCount: pageCount,
            includeWatermark: includeWatermark
        ) {
            VStack(spacing: 0) {
                if page.isCover {
                    ArchiveShareCover(
                        mode: .annual,
                        title: MemoryRecapLogic.yearlyTitle(year: year),
                        summary: String(localized: "recap.monthCount \(totalPhotoCount)"),
                        index: "\(totalMonthCount) / 12",
                        heroImage: heroImage
                    )
                }
                VStack(spacing: 16) {
                    ForEach(page.months, id: \.month) { month in
                        VStack(spacing: 0) {
                            ArchiveShareMonthHeader(
                                year: month.year,
                                month: month.month,
                                countLabel: String(localized: "recap.monthCount \(month.totalPhotoCount)")
                            )
                            ArchiveShareRecapStrip(month: month, imageMap: imageMap)
                        }
                    }
                }
                .padding(.horizontal, ArchiveShareLayout.horizontalPadding)
                .padding(.top, page.isCover ? 16 : 24)
                .padding(.bottom, 16)
            }
        }
    }
}
