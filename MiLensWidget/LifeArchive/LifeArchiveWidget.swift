//  LifeArchiveWidget —— 档案年轮（WidgetKit-Design.md §3.4）。
//
//  Medium / Large 两种尺寸，可配置伙伴。
//  - Medium：右重铜色登记线承接「照片/记忆/作品」三项统计 + 编辑式数字
//  - Large：增加起始年份/当前年份/年份节点 + 一张代表照片
//  年轮只是时间与记录数量的可视化，不暗示健康、寿命或宠物识别准确度。

import WidgetKit
import SwiftUI
import MiLensKit

// MARK: - Timeline Entry

struct LifeArchiveEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let petID: UUID?
}

// MARK: - Timeline Provider

struct LifeArchiveProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LifeArchiveEntry {
        LifeArchiveEntry(date: Date(), snapshot: nil, petID: nil)
    }

    func snapshot(for configuration: SelectPetIntent, in context: Context) async -> LifeArchiveEntry {
        let now = Date()
        let snapshot = WidgetSnapshotReader.read()
        return LifeArchiveEntry(date: now, snapshot: snapshot, petID: configuration.pet.petID)
    }

    func timeline(for configuration: SelectPetIntent, in context: Context) async -> Timeline<LifeArchiveEntry> {
        let now = Date()
        let snapshot = WidgetSnapshotReader.read()
        let entry = LifeArchiveEntry(date: now, snapshot: snapshot, petID: configuration.pet.petID)
        let nextRefresh = WidgetTimelineLogic.archiveNextRefresh(after: now)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}

// MARK: - Widget 定义

struct LifeArchiveWidget: Widget {
    let kind: String = "LifeArchiveWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectPetIntent.self,
            provider: LifeArchiveProvider()
        ) { entry in
            LifeArchiveWidgetView(entry: entry)
        }
        .configurationDisplayName("档案年轮")
        .description("这份档案已经积累了多久、多少照片和多少段记忆")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - 视图路由

struct LifeArchiveWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LifeArchiveEntry

    var body: some View {
        let state = WidgetSelectionLogic.resolveState(
            snapshot: entry.snapshot, now: entry.date, petID: entry.petID
        )
        switch state {
        case .stale:
            WidgetStaleState(lastUpdated: entry.snapshot?.lastUpdated)
        case .empty:
            WidgetEmptyState(message: emptyMessage)
        case .content, .redacted:
            contentView
        }
    }

    private var emptyMessage: String {
        let hasPets = !(entry.snapshot?.pets.isEmpty ?? true)
        return hasPets ? "档案还没有照片" : "先建立一份伙伴档案"
    }

    // ViewBuilder 不支持 guard 语句（首次编译暴露）：改用 if let / else，语义不变。
    @ViewBuilder
    private var contentView: some View {
        if let snapshot = entry.snapshot {
            let stats = WidgetSelectionLogic.archiveStats(snapshot: snapshot, petID: entry.petID)
            switch family {
            case .systemMedium:
                LifeArchiveMediumView(stats: stats, snapshot: snapshot)
            case .systemLarge:
                LifeArchiveLargeView(stats: stats, snapshot: snapshot, now: entry.date)
            default:
                LifeArchiveMediumView(stats: stats, snapshot: snapshot)
            }
        } else {
            WidgetEmptyState(message: "等待数据同步")
        }
    }
}

// MARK: - 统计行模型

/// 一行统计项（编辑式数字 + 标签）。
struct ArchiveStatRow {
    let value: Int
    let label: String
}

/// 把 ArchiveStats 转为三行统计项。
func archiveStatRows(_ stats: ArchiveStats) -> [ArchiveStatRow] {
    [
        ArchiveStatRow(value: stats.totalPhotos, label: "照片"),
        ArchiveStatRow(value: stats.totalMemories, label: "记忆"),
        ArchiveStatRow(value: stats.totalWorks, label: "作品"),
    ]
}

// MARK: - Medium 视图

/// Medium：右重铜色登记线承接「照片/记忆/作品」三项统计 + 编辑式数字。
struct LifeArchiveMediumView: View {
    let stats: ArchiveStats
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Spacer()
            // 右重铜色登记线
            CopperRail(height: 80, showsEndpoint: true, fadeToTop: false)
                .frame(width: 8)

            // 三项统计
            VStack(alignment: .leading, spacing: 6) {
                Text("档案年轮")
                    .font(WidgetFont.registryCaption)
                    .foregroundStyle(WidgetPalette.copperDeep)
                ForEach(archiveStatRows(stats).indices, id: \.self) { i in
                    let row = archiveStatRows(stats)[i]
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(row.value)")
                            .font(WidgetFont.editorialNumber)
                            .foregroundStyle(WidgetPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(row.label)
                            .font(WidgetFont.caption)
                            .foregroundStyle(WidgetPalette.secondary)
                    }
                }
                Spacer()
            }
            Spacer()
        }
        .padding(12)
        .widgetURL(WidgetDeepLinkBuilder.timeline())
        .containerBackground(for: .widget) {
            WidgetPalette.paper
        }
    }
}

// MARK: - Large 视图

/// Large：增加起始年份/当前年份/年份节点 + 一张代表照片。
struct LifeArchiveLargeView: View {
    let stats: ArchiveStats
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            // 顶部：代表照片
            let thumbPhoto = snapshot.photos.first
            ZStack(alignment: .bottomLeading) {
                if let fileName = thumbPhoto?.thumbnailFileName,
                   let image = WidgetSnapshotReader.loadImage(fileName, maxSize: 400) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    WidgetPalette.paper.opacity(0.4)
                }
                LinearGradient(
                    colors: [.clear, .black.opacity(0.4)],
                    startPoint: .center, endPoint: .bottom
                )
                .frame(height: 40)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)

            // 下半：年份节点 + 三项统计
            HStack(spacing: 10) {
                CopperRail(height: 100, showsEndpoint: true, fadeToTop: true)

                VStack(alignment: .leading, spacing: 6) {
                    // 年份节点
                    yearScaleView

                    // 三项统计（横排）
                    HStack(spacing: 16) {
                        ForEach(archiveStatRows(stats).indices, id: \.self) { i in
                            let row = archiveStatRows(stats)[i]
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(row.value)")
                                    .font(WidgetFont.editorialNumber)
                                    .foregroundStyle(WidgetPalette.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Text(row.label)
                                    .font(WidgetFont.registryCaption)
                                    .foregroundStyle(WidgetPalette.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)

                    Spacer()
                }
                Spacer()
            }
            .padding(12)
            .background(WidgetPalette.paper)
        }
        .widgetURL(WidgetDeepLinkBuilder.timeline())
        .containerBackground(for: .widget) {
            WidgetPalette.paper
        }
    }

    /// 起始年份 → 当前年份的开放年轮。
    @ViewBuilder
    private var yearScaleView: some View {
        let cal = widgetLocalCalendar
        let nowYear = cal.component(.year, from: now)
        let startYear = stats.archiveStartDate.map { cal.component(.year, from: $0) }

        HStack(spacing: 6) {
            if let startYear {
                Text("\(startYear)")
                    .font(WidgetFont.registryCaption)
                    .foregroundStyle(WidgetPalette.copperDeep)
            }
            Rectangle()
                .fill(WidgetPalette.copperDeep.opacity(0.4))
                .frame(height: 1.5)
                .frame(maxWidth: .infinity)
            Text("\(nowYear)")
                .font(WidgetFont.registryCaption)
                .foregroundStyle(WidgetPalette.copperDeep)
        }
    }
}
