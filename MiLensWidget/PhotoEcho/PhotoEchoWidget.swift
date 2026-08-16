//  PhotoEchoWidget —— 相片回声（WidgetKit-Design.md §3.2）。
//
//  Small / Medium / Large 三种尺寸，可配置伙伴与内容源。
//  - Small：照片全出血 + 顶部微型登记头 + 底部渐变（伙伴名 + 来源）
//  - Medium：左 56% 照片 + 右侧奶油档案纸 + 3pt 铜色登记轨连接
//  - Large：上半照片 + 下半档案纸 + 最近三个月份刻度 + 用户备注
//
//  内容源（PhotoEchoSource）：今日/最近、往日同日回忆、最近拼豆作品。
//  无照片时展示 empty 状态；快照过期展示 stale 状态。

import WidgetKit
import SwiftUI
import MiLensKit

// MARK: - Timeline Entry

struct PhotoEchoEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let petID: UUID?
    let source: PhotoEchoSource
    let randomIndex: Int
}

// MARK: - Timeline Provider

struct PhotoEchoProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PhotoEchoEntry {
        PhotoEchoEntry(date: Date(), snapshot: nil, petID: nil, source: .todayOrRecent, randomIndex: 0)
    }

    func snapshot(for configuration: PhotoEchoConfigIntent, in context: Context) async -> PhotoEchoEntry {
        let snapshot = WidgetSnapshotReader.read()
        return PhotoEchoEntry(
            date: Date(),
            snapshot: snapshot,
            petID: configuration.pet.petID,
            source: configuration.source.toLogic,
            randomIndex: Int.random(in: 0...1000)
        )
    }

    func timeline(for configuration: PhotoEchoConfigIntent, in context: Context) async -> Timeline<PhotoEchoEntry> {
        let now = Date()
        let snapshot = WidgetSnapshotReader.read()
        let entry = PhotoEchoEntry(
            date: now,
            snapshot: snapshot,
            petID: configuration.pet.petID,
            source: configuration.source.toLogic,
            randomIndex: Int.random(in: 0...1000)
        )
        let nextRefresh = WidgetTimelineLogic.photoEchoNextRefresh(after: now)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}

// MARK: - Widget 定义

struct PhotoEchoWidget: Widget {
    let kind: String = "PhotoEchoWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: PhotoEchoConfigIntent.self,
            provider: PhotoEchoProvider()
        ) { entry in
            PhotoEchoWidgetView(entry: entry)
        }
        .configurationDisplayName("widget.photoEcho.name")
        .description("widget.photoEcho.description")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - 视图路由

struct PhotoEchoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PhotoEchoEntry

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
        return hasPets
            ? String(localized: "widget.photoEcho.empty.noPhoto")
            : String(localized: "widget.empty.createPetFirst")
    }

    // ViewBuilder 不支持 guard 语句（首次编译暴露）：改用 if let 结构，
    // 空态分支保持原语义（无快照 → 等待同步；有快照但选不出照片 → 空态文案）。
    @ViewBuilder
    private var contentView: some View {
        if let snapshot = entry.snapshot {
            if let photo = WidgetSelectionLogic.selectPhotoEcho(
                snapshot: snapshot, petID: entry.petID, source: entry.source,
                now: entry.date, randomIndex: entry.randomIndex
            ) {
                switch family {
                case .systemSmall:
                    PhotoEchoSmallView(photo: photo, snapshot: snapshot, now: entry.date)
                case .systemMedium:
                    PhotoEchoMediumView(photo: photo, snapshot: snapshot, now: entry.date)
                case .systemLarge:
                    PhotoEchoLargeView(photo: photo, snapshot: snapshot, now: entry.date)
                default:
                    PhotoEchoSmallView(photo: photo, snapshot: snapshot, now: entry.date)
                }
            } else {
                WidgetEmptyState(message: emptyMessage)
            }
        } else {
            WidgetEmptyState(message: String(localized: "widget.stale.waitingSync"))
        }
    }
}

// MARK: - Small 视图

/// Small：照片全出血 + 顶部微型登记头 + 底部渐变（伙伴名 + 来源）。
struct PhotoEchoSmallView: View {
    let photo: PhotoProjection
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        let image = photo.thumbnailFileName.flatMap { WidgetSnapshotReader.loadImage($0, maxSize: 200) }
        let dateText = formatRegistryDate(photo.takenAt)
        let caption = buildCaption()

        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                WidgetPalette.paper
            }

            VStack {
                HStack {
                    Text("widget.photoEcho.header \(dateText)")
                        .font(WidgetFont.registryCaption)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 60)
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 5) {
                        Rectangle()
                            .fill(WidgetPalette.copper)
                            .frame(width: 12, height: 2)
                        Text(caption)
                            .font(WidgetFont.bodySecondary)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
        .widgetURL(WidgetDeepLinkBuilder.photo(photo.id))
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private func buildCaption() -> String {
        let prefix = WidgetSelectionLogic.isToday(takenAt: photo.takenAt, now: now)
            ? String(localized: "widget.common.today")
            : String(localized: "widget.common.recent")
        let name = photo.petName ?? ""
        return name.isEmpty
            ? prefix
            : String(localized: "widget.common.join \(prefix) \(name)")
    }
}

// MARK: - Medium 视图

/// Medium：左 56% 照片 + 右侧奶油档案纸 + 3pt 铜色登记轨连接。
struct PhotoEchoMediumView: View {
    let photo: PhotoProjection
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        let image = photo.thumbnailFileName.flatMap { WidgetSnapshotReader.loadImage($0, maxSize: 200) }
        let dateText = formatRegistryDate(photo.takenAt)

        HStack(spacing: 0) {
            // 左侧照片 56%
            ZStack(alignment: .bottomLeading) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    WidgetPalette.paper.opacity(0.5)
                }
                LinearGradient(
                    colors: [.clear, .black.opacity(0.5)],
                    startPoint: .center, endPoint: .bottom
                )
                .frame(height: 40)
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .layoutPriority(56)

            // 右侧档案纸
            HStack(spacing: 8) {
                // 铜色登记轨
                CopperRail(height: 44, showsEndpoint: true, fadeToTop: true)
                    .frame(width: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(dateText)
                        .font(WidgetFont.registryCaption)
                        .foregroundStyle(WidgetPalette.copperDeep)
                    if let name = photo.petName, !name.isEmpty {
                        Text(name)
                            .font(WidgetFont.bodyPrimary)
                            .foregroundStyle(WidgetPalette.ink)
                            .lineLimit(1)
                    }
                    if !photo.note.isEmpty {
                        Text(photo.note)
                            .font(WidgetFont.caption)
                            .foregroundStyle(WidgetPalette.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(.trailing, 10)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(44)
            .background(WidgetPalette.paper)
        }
        .widgetURL(WidgetDeepLinkBuilder.photo(photo.id))
        .containerBackground(for: .widget) {
            WidgetPalette.paper
        }
    }
}

// MARK: - Large 视图

/// Large：上半照片 + 下半档案纸 + 最近三个月份刻度 + 用户备注。
struct PhotoEchoLargeView: View {
    let photo: PhotoProjection
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        let image = photo.thumbnailFileName.flatMap { WidgetSnapshotReader.loadImage($0, maxSize: 400) }

        VStack(spacing: 0) {
            // 上半照片
            ZStack(alignment: .bottomLeading) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    WidgetPalette.paper.opacity(0.5)
                }
                LinearGradient(
                    colors: [.clear, .black.opacity(0.5)],
                    startPoint: .center, endPoint: .bottom
                )
                .frame(height: 50)
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 220)

            // 下半档案纸
            HStack(spacing: 10) {
                CopperRail(height: 60, showsEndpoint: true, fadeToTop: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(formatRegistryDate(photo.takenAt))
                        .font(WidgetFont.registryCaption)
                        .foregroundStyle(WidgetPalette.copperDeep)
                    if let name = photo.petName, !name.isEmpty {
                        Text(name)
                            .font(WidgetFont.bodyPrimary)
                            .foregroundStyle(WidgetPalette.ink)
                    }
                    // 最近三个月份刻度
                    monthScaleView
                    if !photo.note.isEmpty {
                        Text(photo.note)
                            .font(WidgetFont.caption)
                            .foregroundStyle(WidgetPalette.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(12)
            .background(WidgetPalette.paper)
        }
        .widgetURL(WidgetDeepLinkBuilder.photo(photo.id))
        .containerBackground(for: .widget) {
            WidgetPalette.paper
        }
    }

    /// 最近三个月份刻度（从 photo.takenAt 所在月份回溯）。
    private var monthScaleView: some View {
        let cal = widgetLocalCalendar
        let months = (0..<3).map { offset -> (Int, Int) in
            let date = cal.date(byAdding: .month, value: -offset, to: photo.takenAt ?? now) ?? now
            return (cal.component(.month, from: date), cal.component(.year, from: date))
        }
        return HStack(spacing: 10) {
            ForEach(months.reversed(), id: \.1) { month, year in
                VStack(spacing: 2) {
                    Text("\(month)")
                        .font(WidgetFont.registryCaption)
                        .foregroundStyle(WidgetPalette.tertiary)
                    Rectangle()
                        .fill(WidgetPalette.copperDeep.opacity(0.4))
                        .frame(width: 16, height: 2)
                }
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - 日期格式化

/// 顶部微型登记头日期格式「8.12」（月.日）。
func formatRegistryDate(_ date: Date?) -> String {
    guard let date else { return "" }
    let cal = widgetLocalCalendar
    let month = cal.component(.month, from: date)
    let day = cal.component(.day, from: date)
    return "\(month).\(day)"
}
