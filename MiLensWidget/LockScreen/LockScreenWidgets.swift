//  LockScreenWidgets —— 锁屏组件（WidgetKit-Design.md §3.5）。
//
//  采用系统单色/强调色渲染，品牌识别来自开放轨、端点、排版和内容，不依赖固定铜橙色。
//  - Accessory Circular：只显示天数数字 + 极简开放轨弧线
//  - Accessory Rectangular：最多两行正文（宠物名 + 回忆日期/标题）
//  锁屏不展示照片缩略图（降低敏感内容暴露并保证 tinted/vibrant 模式可读）。

import WidgetKit
import SwiftUI
import MiLensKit

// MARK: - 共享 Timeline Entry

struct LockScreenEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let petID: UUID?
    let selection: UpcomingDaySelection?
    /// 用户指定了某个纪念日但它已不在快照中，且连自动回退也找不到候选。
    /// 为 true 时 Circular 的 empty 状态使用「该纪念日已不存在」文案。
    var specifiedDayMissing: Bool = false
    /// 当前 selection 是否为用户指定的纪念日（true=指定命中，false=自动/回退）。
    /// 决定点击深链是否携带纪念日定位（anniversary vs pet）。锁屏 Rectangular
    /// 使用自动模式，该值为 false。
    var isSpecifiedMatch: Bool = false
}

// MARK: - 共享 Timeline Provider

/// 锁屏·一段回忆 Rectangular 的 Provider：自动取最近纪念日，不支持指定。
struct LockScreenProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LockScreenEntry {
        LockScreenEntry(date: Date(), snapshot: nil, petID: nil, selection: nil)
    }

    func snapshot(for configuration: SelectPetIntent, in context: Context) async -> LockScreenEntry {
        let now = Date()
        let snapshot = WidgetSnapshotReader.read()
        let selection = snapshot.flatMap {
            WidgetSelectionLogic.nextUpcomingDay(snapshot: $0, petID: configuration.pet.petID, now: now)
        }
        return LockScreenEntry(date: now, snapshot: snapshot, petID: configuration.pet.petID, selection: selection)
    }

    func timeline(for configuration: SelectPetIntent, in context: Context) async -> Timeline<LockScreenEntry> {
        let now = Date()
        let snapshot = WidgetSnapshotReader.read()
        let entryDates = WidgetTimelineLogic.upcomingDayEntries(now: now)

        let entries: [LockScreenEntry] = entryDates.map { entryDate in
            let selection = snapshot.flatMap {
                WidgetSelectionLogic.nextUpcomingDay(snapshot: $0, petID: configuration.pet.petID, now: entryDate)
            }
            return LockScreenEntry(date: entryDate, snapshot: snapshot, petID: configuration.pet.petID, selection: selection)
        }
        let policy: TimelineReloadPolicy = .after(entryDates.last ?? now.addingTimeInterval(3600))
        return Timeline(entries: entries, policy: policy)
    }
}

// MARK: - 锁屏·倒计时 Circular Provider（支持选纪念日）

/// 锁屏倒计时的 Timeline Provider，支持用户指定某个纪念日（默认自动取最近）。
/// 与桌面「纪念日」Widget 共用 `SelectAnniversaryIntent`，语义一致。
struct LockScreenCircularProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LockScreenEntry {
        LockScreenEntry(date: Date(), snapshot: nil, petID: nil, selection: nil)
    }

    func snapshot(for configuration: SelectAnniversaryIntent, in context: Context) async -> LockScreenEntry {
        let now = Date()
        let snapshot = WidgetSnapshotReader.read()
        let dayID = configuration.anniversary.dayID
        let selection = snapshot.flatMap {
            WidgetSelectionLogic.upcomingDay(
                snapshot: $0, petID: configuration.pet.petID,
                dayID: dayID, now: now
            )
        }
        var entry = LockScreenEntry(date: now, snapshot: snapshot, petID: configuration.pet.petID, selection: selection)
        entry.specifiedDayMissing = (dayID != nil
            && (snapshot?.upcomingDays.contains { $0.id == dayID } == false)
            && selection == nil)
        entry.isSpecifiedMatch = (dayID != nil && selection?.day.id == dayID)
        return entry
    }

    func timeline(for configuration: SelectAnniversaryIntent, in context: Context) async -> Timeline<LockScreenEntry> {
        let now = Date()
        let snapshot = WidgetSnapshotReader.read()
        let entryDates = WidgetTimelineLogic.upcomingDayEntries(now: now)
        let petID = configuration.pet.petID
        let dayID = configuration.anniversary.dayID
        let missing = dayID != nil
            && (snapshot?.upcomingDays.contains { $0.id == dayID } == false)

        let entries: [LockScreenEntry] = entryDates.map { entryDate in
            let selection = snapshot.flatMap {
                WidgetSelectionLogic.upcomingDay(
                    snapshot: $0, petID: petID, dayID: dayID, now: entryDate
                )
            }
            var entry = LockScreenEntry(date: entryDate, snapshot: snapshot, petID: petID, selection: selection)
            entry.specifiedDayMissing = missing && selection == nil
            entry.isSpecifiedMatch = (dayID != nil && selection?.day.id == dayID)
            return entry
        }
        let policy: TimelineReloadPolicy = .after(entryDates.last ?? now.addingTimeInterval(3600))
        return Timeline(entries: entries, policy: policy)
    }
}

// MARK: - 锁屏·倒计时 Circular

struct LockScreenCircularWidget: Widget {
    let kind: String = "LockScreenCircularWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectAnniversaryIntent.self,
            provider: LockScreenCircularProvider()
        ) { entry in
            LockScreenCircularView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("倒计时")
        .description("指定一个纪念日的倒计时，或自动取最近的一个")
        .supportedFamilies([.accessoryCircular])
    }
}

/// AccessoryCircular：天数数字 + 极简开放轨弧线。
/// 系统单色渲染，不展示照片。
struct LockScreenCircularView: View {
    let entry: LockScreenEntry

    var body: some View {
        let hasContent = entry.selection != nil && !(entry.snapshot?.pets.isEmpty ?? true)
        if hasContent, let selection = entry.selection {
            ZStack {
                // 极简开放轨弧线（用 Arc 替代完整圆环）
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) / 2 - 3
                    var path = Path()
                    // 约 300° 开放弧（底部留开口），呼应「开放年轮」语义
                    path.addArc(center: center, radius: radius,
                                startAngle: .degrees(120), endAngle: .degrees(60), clockwise: false)
                    context.stroke(path, with: .color(.opacity(0.5)), lineWidth: 1.5)
                }
                VStack(spacing: 0) {
                    Text(countdownText(selection))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if selection.daysUntil > 0 {
                        Text("天后")
                            .font(.system(size: 9, weight: .regular))
                            .opacity(0.7)
                    }
                }
            }
            .widgetURL(deepLink(for: selection))
        } else {
            // empty 状态：只显示图标。若用户指定过的纪念日被删除，用问号圈提示。
            Image(systemName: entry.specifiedDayMissing ? "questionmark.circle" : "pawprint")
                .font(.system(size: 18))
                .opacity(0.6)
        }
    }

    private func countdownText(_ selection: UpcomingDaySelection) -> String {
        selection.daysUntil == 0 ? "今天" : "\(selection.daysUntil)"
    }

    /// 点击深链：指定命中时携带纪念日定位（anniversary），自动/回退时跳伙伴档案（pet）。
    private func deepLink(for selection: UpcomingDaySelection) -> URL? {
        entry.isSpecifiedMatch
            ? WidgetDeepLinkBuilder.anniversary(petID: selection.day.petID, dayID: selection.day.id)
            : WidgetDeepLinkBuilder.pet(selection.day.petID)
    }
}

// MARK: - 锁屏·一段回忆 Rectangular

struct LockScreenRectangularWidget: Widget {
    let kind: String = "LockScreenRectangularWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectPetIntent.self,
            provider: LockScreenProvider()
        ) { entry in
            LockScreenRectangularView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("一段回忆")
        .description("宠物名与一段回忆的日期和标题")
        .supportedFamilies([.accessoryRectangular])
    }
}

/// AccessoryRectangular：最多两行正文（宠物名 + 回忆日期/标题）。
/// 不展示照片缩略图（隐私 + tinted/vibrant 可读性）。
struct LockScreenRectangularView: View {
    let entry: LockScreenEntry

    var body: some View {
        let hasContent = entry.selection != nil && !(entry.snapshot?.pets.isEmpty ?? true)
        if hasContent, let selection = entry.selection {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: dayKindIcon(selection.day.kind))
                        .font(.system(size: 10))
                    Text(selection.day.petName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                Text(rectangularSubtitle(selection))
                    .font(.system(size: 12))
                    .opacity(0.8)
                    .lineLimit(1)
            }
            .widgetURL(WidgetDeepLinkBuilder.pet(selection.day.petID))
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Image(systemName: "pawprint")
                    .font(.system(size: 13))
                    .opacity(0.6)
                Text(entry.snapshot?.pets.isEmpty ?? true ? "建档" : "待记录")
                    .font(.system(size: 12))
                    .opacity(0.6)
            }
        }
    }

    /// 根据来源类型选择 SF Symbol。
    private func dayKindIcon(_ kind: UpcomingDayProjection.Kind) -> String {
        switch kind {
        case .birthday: return "gift"
        case .adoption: return "house"
        case .memorial: return "heart"
        }
    }

    /// 副标题：倒计时 + 纪念日标题。
    private func rectangularSubtitle(_ selection: UpcomingDaySelection) -> String {
        let prefix = selection.daysUntil == 0
            ? "今天"
            : "\(selection.daysUntil) 天后"
        return "\(prefix) · \(selection.day.title)"
    }
}
