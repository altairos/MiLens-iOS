//  TimelineExportCanvas —— 成长时间线导出渲染视图（ADR-0010 §5 / §10.13）。
//
//  纯 SwiftUI 视图，用于 ImageRenderer 离屏生成长图 PNG。
//  支持 ExportQuality 画质门控（standard 1080px / high 2400px），尺寸按宽度比例缩放。
//  不加载缩略图文件（导出场景追求速度，用占位色块代替照片）。

import SwiftUI
import MiLensKit

struct TimelineExportCanvas: View {
    let data: TimelineExportData
    let quality: ExportQuality

    /// 便捷构造（默认 standard，保持现有调用点兼容）。
    init(data: TimelineExportData, quality: ExportQuality = .standard) {
        self.data = data
        self.quality = quality
    }

    /// 导出宽度（像素，随画质门控）。
    var exportWidth: CGFloat {
        CGFloat(quality.maxLongEdgePixels)
    }

    /// 内部尺寸缩放系数（以 1080 基准宽度为 1.0）。
    private var scale: CGFloat { exportWidth / 1080 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            exportHeader
                .padding(.bottom, 40 * scale)

            ForEach(Array(data.months.enumerated()), id: \.element.yearMonth) { _, month in
                monthBlock(month)
            }

            if data.includeWatermark {
                exportFooter
                    .padding(.top, 40 * scale)
            }
        }
        .padding(60 * scale)
        .frame(width: exportWidth, alignment: .leading)
        .background(Color.white)
    }

    // MARK: - 头部

    private var exportHeader: some View {
        VStack(alignment: .leading, spacing: 16 * scale) {
            Text(String(localized: "timeline.title"))
                .font(.system(size: 20 * scale, weight: .medium)) // ui-token:ok 导出画布动态缩放
                .foregroundStyle(Color.milensTextSecondary)

            Text(data.title)
                .font(.custom("LXGWWenKai-Regular", size: 52 * scale))
                .foregroundStyle(Color.milensTextPrimary)

            HStack(spacing: 12 * scale) {
                Text(data.dateRangeText)
                    .font(.system(size: 22 * scale, weight: .regular, design: .rounded)) // ui-token:ok 导出画布动态缩放
                    .foregroundStyle(Color.milensTextSecondary)
                Text("·")
                    .font(.system(size: 22 * scale)) // ui-token:ok 导出画布动态缩放
                    .foregroundStyle(Color.milensTextTertiary)
                Text(String(localized: "timeline.export.entryCount \(data.entryCount)"))
                    .font(.system(size: 22 * scale, weight: .regular, design: .rounded)) // ui-token:ok 导出画布动态缩放
                    .foregroundStyle(Color.milensTextSecondary)
            }
        }
    }

    // MARK: - 月份块

    private func monthBlock(_ month: TimelineMonth) -> some View {
        VStack(alignment: .leading, spacing: 20 * scale) {
            HStack(alignment: .firstTextBaseline, spacing: 12 * scale) {
                if month.isYearStart {
                    Text(String(localized: "timeline.year \(month.year)"))
                        .font(.custom("LXGWWenKai-Regular", size: 36 * scale))
                        .foregroundStyle(Color.milensTextPrimary)
                }
                Text(String(localized: "timeline.month \(month.month)"))
                    .font(.custom("LXGWWenKai-Regular", size: 36 * scale))
                    .foregroundStyle(Color.milensTextPrimary)
            }
            .padding(.leading, 30 * scale)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(month.entries) { entry in
                    exportEntryRow(entry)
                }
            }
        }
        .padding(.bottom, 40 * scale)
    }

    private func exportEntryRow(_ entry: TimelineEntry) -> some View {
        HStack(alignment: .top, spacing: 24 * scale) {
            VStack(spacing: 0) {
                Circle()
                    .fill(entryIconColor(entry.type))
                    .frame(width: 14 * scale, height: 14 * scale)
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(width: 2 * scale)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 14 * scale)

            VStack(alignment: .leading, spacing: 6 * scale) {
                Text(entry.title)
                    .font(.system(size: 24 * scale, weight: .medium, design: .rounded)) // ui-token:ok 导出画布动态缩放
                    .foregroundStyle(Color.milensTextPrimary)
                if !entry.subtitle.isEmpty {
                    Text(entry.subtitle)
                        .font(.system(size: 18 * scale, weight: .regular, design: .rounded)) // ui-token:ok 导出画布动态缩放
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }
            .padding(.bottom, 28 * scale)
        }
    }

    // MARK: - 底部签名

    private var exportFooter: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 6 * scale) {
                Text(String(localized: "timeline.export.watermark"))
                    .font(.system(size: 18 * scale, weight: .medium, design: .rounded)) // ui-token:ok 导出画布动态缩放
                    .foregroundStyle(Color.milensTextTertiary)
                Text("milens.app")
                    .font(.system(size: 16 * scale, weight: .regular, design: .rounded)) // ui-token:ok 导出画布动态缩放
                    .foregroundStyle(Color.milensTextTertiary)
            }
        }
    }

    // MARK: - 辅助

    private func entryIconColor(_ type: TimelineEntryType) -> Color {
        switch type {
        case .birthday:   return Color.milensPrimary
        case .adoption:   return Color.milensCopper
        case .photoNote:  return Color.milensActionPrimary
        case .textNote:   return Color.milensCopper
        case .workRecord: return Color.milensAccentSoft
        }
    }
}
