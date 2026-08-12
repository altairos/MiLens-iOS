//  UpcomingDayWidget —— 纪念日倒计时（WidgetKit-Design.md §3.3）。
//
//  Small / Medium 两种尺寸，可配置伙伴。
//  - Small：大号倒计时数字 + 右侧窄幅照片证据 + 左侧登记轨
//  - Medium：照片 + 倒计时并列 + 底部开放时间轨「已陪伴 N 天 → 还有 N 天」
//  当天：倒计时改为「今天」。
//  时间线：今天 23:59 + 明天 00:01 两个 entry，保证倒计时不滞后。

import WidgetKit
import SwiftUI
import MiLensKit

// MARK: - Timeline Entry

struct UpcomingDayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let petID: UUID?
    /// 选中的纪念日（已计算 daysUntil / daysTogether）。
    let selection: UpcomingDaySelection?
}

// MARK: - Timeline Provider

struct UpcomingDayProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UpcomingDayEntry {
        UpcomingDayEntry(date: Date(), snapshot: nil, petID: nil, selection: nil)
    }

    func snapshot(for configuration: SelectPetIntent, in context: Context) async -> UpcomingDayEntry {
        let now = Date()
        let snapshot = WidgetSnapshotReader.read()
        let selection = snapshot.flatMap {
            WidgetSelectionLogic.nextUpcomingDay(snapshot: $0, petID: configuration.pet.petID, now: now)
        }
        return UpcomingDayEntry(date: now, snapshot: snapshot, petID: configuration.pet.petID, selection: selection)
    }

    func timeline(for configuration: SelectPetIntent, in context: Context) async -> Timeline<UpcomingDayEntry> {
        let now = Date()
        let snapshot = WidgetSnapshotReader.read()
        let entryDates = WidgetTimelineLogic.upcomingDayEntries(now: now)

        let entries: [UpcomingDayEntry] = entryDates.map { entryDate in
            let selection = snapshot.flatMap {
                WidgetSelectionLogic.nextUpcomingDay(snapshot: $0, petID: configuration.pet.petID, now: entryDate)
            }
            return UpcomingDayEntry(date: entryDate, snapshot: snapshot, petID: configuration.pet.petID, selection: selection)
        }
        // 最后一个 entry 后的策略：由主 App 主动 reload
        let policy: TimelineReloadPolicy = .after(entryDates.last ?? now.addingTimeInterval(3600))
        return Timeline(entries: entries, policy: policy)
    }
}

// MARK: - Widget 定义

struct UpcomingDayWidget: Widget {
    let kind: String = "UpcomingDayWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectPetIntent.self,
            provider: UpcomingDayProvider()
        ) { entry in
            UpcomingDayWidgetView(entry: entry)
        }
        .configurationDisplayName("纪念日")
        .description("下一个值得记住的日子的倒计时")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - 视图路由

struct UpcomingDayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpcomingDayEntry

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
        return hasPets ? "还没有纪念日" : "先建立一份伙伴档案"
    }

    @ViewBuilder
    private var contentView: some View {
        guard let selection = entry.selection else {
            WidgetEmptyState(message: emptyMessage)
            return
        }
        switch family {
        case .systemSmall:
            UpcomingDaySmallView(selection: selection, snapshot: entry.snapshot)
        case .systemMedium:
            UpcomingDayMediumView(selection: selection, snapshot: entry.snapshot)
        default:
            UpcomingDaySmallView(selection: selection, snapshot: entry.snapshot)
        }
    }
}

// MARK: - Small 视图

/// Small：大号倒计时数字 + 右侧窄幅照片证据 + 左侧登记轨。
struct UpcomingDaySmallView: View {
    let selection: UpcomingDaySelection
    let snapshot: WidgetSnapshot?

    var body: some View {
        HStack(spacing: 8) {
            // 左侧登记轨
            CopperRail(height: 50, showsEndpoint: true, fadeToTop: false)
                .frame(width: 8)

            // 倒计时数字 + 标题
            VStack(alignment: .leading, spacing: 2) {
                Text(countdownText)
                    .font(countdownFont)
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(selection.day.title)
                    .font(WidgetFont.caption)
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(2)
                if selection.daysUntil == 0 {
                    Text("今天是这个日子")
                        .font(WidgetFont.registryCaption)
                        .foregroundStyle(WidgetPalette.copper)
                }
                Spacer()
            }

            Spacer()

            // 右侧窄幅照片证据
            thumbnailView
                .frame(width: 40, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(10)
        .widgetURL(WidgetDeepLinkBuilder.pet(selection.day.petID))
        .containerBackground(for: .widget) {
            WidgetPalette.paper
        }
    }

    private var countdownText: String {
        selection.daysUntil == 0 ? "今天" : "\(selection.daysUntil)"
    }

    private var countdownFont: Font {
        selection.daysUntil == 0 ? WidgetFont.editorialNumber : WidgetFont.editorialLarge
    }

    @ViewBuilder
    private var thumbnailView: some View {
        let thumbPhoto = snapshot?.photos.first { $0.petID == selection.day.petID }
        if let fileName = thumbPhoto?.thumbnailFileName,
           let image = WidgetSnapshotReader.loadImage(fileName, maxSize: 100) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            WidgetPalette.paperDark.opacity(0.1)
        }
    }
}

// MARK: - Medium 视图

/// Medium：照片 + 倒计时并列 + 底部开放时间轨「已陪伴 N 天 → 还有 N 天」。
struct UpcomingDayMediumView: View {
    let selection: UpcomingDaySelection
    let snapshot: WidgetSnapshot?

    var body: some View {
        HStack(spacing: 0) {
            // 左侧照片证据
            ZStack(alignment: .bottom) {
                let thumbPhoto = snapshot?.photos.first { $0.petID == selection.day.petID }
                if let fileName = thumbPhoto?.thumbnailFileName,
                   let image = WidgetSnapshotReader.loadImage(fileName, maxSize: 200) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    WidgetPalette.paper.opacity(0.5)
                }
            }
            .frame(width: 120)
            .frame(maxHeight: .infinity)

            // 右侧倒计时 + 时间轨
            HStack(spacing: 8) {
                CopperRail(height: 50, showsEndpoint: true, fadeToTop: true)
                    .frame(width: 8)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(countdownText)
                            .font(WidgetFont.editorialLarge)
                            .foregroundStyle(WidgetPalette.ink)
                        if selection.daysUntil > 0 {
                            Text("天后")
                                .font(WidgetFont.bodySecondary)
                                .foregroundStyle(WidgetPalette.secondary)
                        }
                    }
                    Text(selection.day.title)
                        .font(WidgetFont.bodyPrimary)
                        .foregroundStyle(WidgetPalette.ink)
                        .lineLimit(1)
                    Text(selection.day.petName)
                        .font(WidgetFont.caption)
                        .foregroundStyle(WidgetPalette.secondary)
                    Spacer()
                    // 开放时间轨
                    openTimelineView
                }
                .padding(.trailing, 12)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WidgetPalette.paper)
        }
        .widgetURL(WidgetDeepLinkBuilder.pet(selection.day.petID))
        .containerBackground(for: .widget) {
            WidgetPalette.paper
        }
    }

    private var countdownText: String {
        selection.daysUntil == 0 ? "今天" : "\(selection.daysUntil)"
    }

    /// 开放时间轨「已陪伴 N 天 → 还有 N 天」。
    /// 不使用进度环或百分比（避免把关系表达成任务完成度）。
    private var openTimelineView: some View {
        HStack(spacing: 6) {
            Text(daysTogetherLabel)
                .font(WidgetFont.registryCaption)
                .foregroundStyle(WidgetPalette.copperDeep)
            Rectangle()
                .fill(WidgetPalette.copperDeep.opacity(0.4))
                .frame(height: 1.5)
                .frame(maxWidth: .infinity)
            Text("还有 \(selection.daysUntil) 天")
                .font(WidgetFont.registryCaption)
                .foregroundStyle(WidgetPalette.tertiary)
        }
    }

    /// 根据来源类型使用不同文案语义。
    private var daysTogetherLabel: String {
        switch selection.day.kind {
        case .birthday: return "出生至今 \(selection.daysTogether) 天"
        case .adoption: return "已陪伴 \(selection.daysTogether) 天"
        case .memorial: return "已记录 \(selection.daysTogether) 天"
        }
    }
}
