//  TimelineExportCanvas —— 成长时间线手机分页导出画布。
//
//  与年度回忆册复用 ArchiveShareTemplate；每次只渲染一张 390 × 1260pt 页面，
//  由调用方按 3× 输出为一组 JPEG。关联照片使用预先降采样的真实缩略图。

import SwiftUI
import UIKit

struct TimelineExportCanvas: View {
    let data: TimelineExportData
    let page: TimelineArchiveSharePage
    let imageMap: [UUID: UIImage]
    let coverHeroImage: UIImage?
    let pageNumber: Int
    let pageCount: Int

    private var heroImage: UIImage? {
        coverHeroImage ?? page.months.lazy
            .flatMap(\.entries)
            .compactMap { entry in
                guard let photoID = entry.photoID else { return nil }
                return imageMap[photoID]
            }
            .first
    }

    private var stats: String {
        "\(data.dateRangeText) · \(String(localized: "timeline.export.entryCount \(data.entryCount)"))"
    }

    private var coverIndex: String {
        data.months.first.map { String($0.year) } ?? "MiLens"
    }

    var body: some View {
        ArchiveSharePageShell(
            stats: stats,
            pageNumber: pageNumber,
            pageCount: pageCount,
            includeWatermark: data.includeWatermark
        ) {
            VStack(spacing: 0) {
                if page.isCover {
                    ArchiveShareCover(
                        mode: .timeline,
                        title: "\(String(localized: "timeline.title")) · \(data.title)",
                        summary: stats,
                        index: coverIndex,
                        heroImage: heroImage
                    )
                }

                VStack(spacing: 16) {
                    ForEach(page.months, id: \.yearMonth) { month in
                        VStack(spacing: 0) {
                            ArchiveShareMonthHeader(
                                year: month.year,
                                month: month.month,
                                countLabel: String(localized: "timeline.export.entryCount \(month.entries.count)")
                            )
                            ForEach(month.entries) { entry in
                                ArchiveShareTimelineEntry(
                                    entry: entry,
                                    image: entry.photoID.flatMap { imageMap[$0] }
                                )
                            }
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
