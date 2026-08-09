//  TimelineExportCanvas —— 成长时间线导出渲染视图（ADR-0010 §5）。
//
//  纯 SwiftUI 视图，用于 ImageRenderer 离屏生成长图 PNG。
//  宽度固定 1080px，高度按内容自适应。
//  不加载缩略图文件（导出场景追求速度，用占位色块代替照片）。

import SwiftUI

struct TimelineExportCanvas: View {
    let data: TimelineExportData

    /// 导出宽度（像素）。
    static let exportWidth: CGFloat = 1080

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部
            exportHeader
                .padding(.bottom, 40)

            // 月份分组
            ForEach(Array(data.months.enumerated()), id: \.element.yearMonth) { _, month in
                monthBlock(month)
            }

            // 底部签名
            if data.includeWatermark {
                exportFooter
                    .padding(.top, 40)
            }
        }
        .padding(60)
        .frame(width: Self.exportWidth, alignment: .leading)
        .background(Color.white)
    }

    // MARK: - 头部

    private var exportHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("成长时间线")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.milensTextSecondary)

            Text(data.title)
                .font(.custom("LXGWWenKai-Regular", size: 52))
                .foregroundStyle(Color.milensTextPrimary)

            HStack(spacing: 12) {
                Text(data.dateRangeText)
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.milensTextSecondary)
                Text("·")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.milensTextTertiary)
                Text("\(data.entryCount) 条记录")
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.milensTextSecondary)
            }
        }
    }

    // MARK: - 月份块

    private func monthBlock(_ month: TimelineMonth) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // 年月标题
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if month.isYearStart {
                    Text("\(String(month.year))年")
                        .font(.custom("LXGWWenKai-Regular", size: 36))
                        .foregroundStyle(Color.milensTextPrimary)
                }
                Text("\(month.month)月")
                    .font(.custom("LXGWWenKai-Regular", size: 36))
                    .foregroundStyle(Color.milensTextPrimary)
            }
            .padding(.leading, 30)

            // 条目列表
            VStack(alignment: .leading, spacing: 0) {
                ForEach(month.entries) { entry in
                    exportEntryRow(entry)
                }
            }
        }
        .padding(.bottom, 40)
    }

    private func exportEntryRow(_ entry: TimelineEntry) -> some View {
        HStack(alignment: .top, spacing: 24) {
            // 左侧时间线节点
            VStack(spacing: 0) {
                Circle()
                    .fill(entryIconColor(entry.type))
                    .frame(width: 14, height: 14)
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 14)

            // 右侧内容
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.milensTextPrimary)
                if !entry.subtitle.isEmpty {
                    Text(entry.subtitle)
                        .font(.system(size: 18, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }
            .padding(.bottom, 28)
        }
    }

    // MARK: - 底部签名

    private var exportFooter: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text("由 MiLens 制作")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.milensTextTertiary)
                Text("milens.app")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
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
        }
    }
}
