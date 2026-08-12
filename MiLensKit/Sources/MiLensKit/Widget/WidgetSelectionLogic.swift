//  WidgetSelectionLogic —— Widget 内容选片与状态判定纯决策逻辑。
//
//  输入 WidgetSnapshot + 用户配置（伙伴 / 内容源），输出各 Widget 应展示的内容。
//  纯函数：不依赖 Repository / SwiftData / SwiftUI / WidgetKit。
//  宿主（Widget Extension 的 TimelineProvider）负责读取 App Group 快照、调用本逻辑、
//  把结果交给 SwiftUI 视图渲染。
//
//  日期算法对齐 HomeHeroLogic / AnniversaryLogic / HomeMemoryLogic 的约定：
//  内部使用固定 UTC Calendar（miLensUTCCalendar），保证跨环境可复现。
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 SwiftUI 依赖。

import Foundation

// MARK: - 相片回声内容源

/// 相片回声 Widget 的可配置内容源（WidgetKit-Design.md §2 / §6.3）。
///
/// 用户在 Widget 配置中选择；无对应内容时安全降级到最近照片，不伪造回忆。
public enum PhotoEchoSource: String, Codable, Sendable, CaseIterable, Equatable {
    /// 今日照片，无今日照片时回退最近一张（默认）。
    case todayOrRecent
    /// 往日同日回忆（往年同月同日的历史照片）。
    case yearsAgoToday
    /// 最近拼豆作品（PhotoProjection.isWork == true）。
    case recentWork
}

// MARK: - Widget 展示状态

/// Widget 的四种展示状态（WidgetKit-Design.md §4 状态矩阵）。
public enum WidgetDisplayState: Sendable, Equatable {
    /// 展示用户选择伙伴的真实本地数据。
    case content
    /// 无伙伴时提示「先建立一份伙伴档案」；有伙伴无照片时提示「留下一张照片」。
    case empty
    /// 隐私或系统占位状态（照片替换为档案纸纹理，不显示宠物名 / 照片 / 备注）。
    case redacted
    /// 共享快照暂不可读或已过期时展示最后成功更新时间，不用假数据覆盖。
    case stale
}

// MARK: - 选片结果

/// 纪念日 Widget 的选片结果（下一个即将到来的纪念日 + 倒计时 + 陪伴天数）。
public struct UpcomingDaySelection: Sendable, Equatable {
    public let day: UpcomingDayProjection
    /// 距今天数（≥0；0 表示今天就是该纪念日）。
    public let daysUntil: Int
    /// 从原始日期到现在的天数（语义随 kind 变化）。
    public let daysTogether: Int

    public init(day: UpcomingDayProjection, daysUntil: Int, daysTogether: Int) {
        self.day = day
        self.daysUntil = daysUntil
        self.daysTogether = daysTogether
    }
}

// MARK: - 决策逻辑

/// Widget 内容选片与状态判定。
///
/// 全部方法为静态纯函数，输入快照投影与配置，输出展示内容或状态。
public enum WidgetSelectionLogic {

    // MARK: 相片回声选片

    /// 相片回声选片（WidgetKit-Design.md §3.2 / §6.3）。
    ///
    /// 策略随 `source` 变化：
    /// - `.todayOrRecent`：今日最新 → 无今日时最近一张（按 takenAt 降序）。
    /// - `.yearsAgoToday`：往年同月同日的历史照片，取最近年份一张 → 无匹配时回退最近一张。
    /// - `.recentWork`：isWork==true 的照片按 takenAt 降序取第一 → 无作品时回退最近一张。
    ///
    /// `petID == nil` 表示「全部伙伴」；指定 petID 时只在该宠物的照片中选。
    /// 无任何可选照片时返回 nil（宿主展示 empty 状态）。
    ///
    /// - Parameters:
    ///   - snapshot: 共享快照
    ///   - petID: 指定伙伴 ID；nil 表示全部伙伴
    ///   - source: 内容源
    ///   - now: 当前时间（注入保证测试可复现）
    ///   - randomIndex: 回退选片的随机种子（宿主固定，避免每次重算跳图）
    /// - Returns: 选中的照片投影；无候选返回 nil
    public static func selectPhotoEcho(
        snapshot: WidgetSnapshot,
        petID: UUID?,
        source: PhotoEchoSource,
        now: Date,
        randomIndex: Int = 0
    ) -> PhotoProjection? {
        let pool = filteredPhotos(snapshot: snapshot, petID: petID)
        guard !pool.isEmpty else { return nil }

        switch source {
        case .todayOrRecent:
            return selectTodayOrRecent(pool, now: now, randomIndex: randomIndex)
        case .yearsAgoToday:
            return selectYearsAgoToday(pool, now: now) ?? selectTodayOrRecent(pool, now: now, randomIndex: randomIndex)
        case .recentWork:
            let works = pool.filter { $0.isWork }
                .sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }
            return works.first ?? selectTodayOrRecent(pool, now: now, randomIndex: randomIndex)
        }
    }

    /// 按伙伴过滤照片池。petID==nil 时返回全部。
    private static func filteredPhotos(snapshot: WidgetSnapshot, petID: UUID?) -> [PhotoProjection] {
        guard let petID else { return snapshot.photos }
        return snapshot.photos.filter { $0.petID == petID }
    }

    /// 今日最新 → 回退：按质量分 top 池随机（对齐 HomeHeroLogic 策略）。
    private static func selectTodayOrRecent(
        _ photos: [PhotoProjection], now: Date, randomIndex: Int
    ) -> PhotoProjection? {
        // 今日最新
        let today = photos
            .filter { isToday(takenAt: $0.takenAt, now: now) }
            .sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }
        if let latest = today.first { return latest }

        // 回退：有拍摄时间的按质量分 top 池随机
        let candidates = photos.filter { $0.takenAt != nil }
        guard !candidates.isEmpty else {
            // 全部无拍摄时间，取第一张
            return photos.first
        }
        let sorted = candidates.sorted { $0.qualityScore > $1.qualityScore }
        let poolSize = min(sorted.count, max(5, (sorted.count + 2) / 3))
        let pool = Array(sorted.prefix(poolSize))
        let safeIndex = ((randomIndex % pool.count) + pool.count) % pool.count
        return pool[safeIndex]
    }

    /// 往年同月同日的历史照片（最近年份一张）。
    private static func selectYearsAgoToday(
        _ photos: [PhotoProjection], now: Date
    ) -> PhotoProjection? {
        let cal = miLensUTCCalendar
        let nowYear = cal.component(.year, from: now)
        let nowMonth = cal.component(.month, from: now)
        let nowDay = cal.component(.day, from: now)

        return photos
            .filter { photo in
                guard let takenAt = photo.takenAt else { return false }
                return cal.component(.month, from: takenAt) == nowMonth
                    && cal.component(.day, from: takenAt) == nowDay
                    && cal.component(.year, from: takenAt) < nowYear
            }
            .sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }
            .first
    }

    // MARK: 纪念日

    /// 选择下一个即将到来的纪念日（WidgetKit-Design.md §3.3）。
    ///
    /// 遍历快照中的 upcomingDays 候选，把每个 originalDate 推进到今年/明年的下一次
    /// 月日匹配，计算 daysUntil，取天数最近的。`petID==nil` 时考虑全部伙伴。
    ///
    /// - Parameters:
    ///   - snapshot: 共享快照
    ///   - petID: 指定伙伴；nil 表示全部
    ///   - now: 当前时间
    /// - Returns: 选中的纪念日 + daysUntil（≥0）+ daysTogether（≥0）；无候选返回 nil
    public static func nextUpcomingDay(
        snapshot: WidgetSnapshot,
        petID: UUID?,
        now: Date
    ) -> UpcomingDaySelection? {
        let candidates = petID == nil
            ? snapshot.upcomingDays
            : snapshot.upcomingDays.filter { $0.petID == petID }
        guard !candidates.isEmpty else { return nil }

        let selections = candidates.compactMap { computeSelection(for: $0, now: now) }
        return selections.sorted { $0.daysUntil < $1.daysUntil }.first
    }

    /// 按用户配置选取纪念日（WidgetKit-Design.md §3.3 / §6.3）。
    ///
    /// - `dayID == nil`（「自动」）：等价于 `nextUpcomingDay`，取按 petID 过滤后最近的。
    /// - `dayID` 指向某个具体纪念日：在快照候选中按 id 精确匹配并计算倒计时；若该 id
    ///   在当前快照中已不存在（被删除或 petID 不匹配），安全回退到 `nextUpcomingDay`，
    ///   不返回空内容（保证 Widget 始终有内容可展示）。
    ///
    /// `petID` 仅在自动模式或回退时参与过滤；指定了具体 dayID 时以该纪念日为准。
    ///
    /// - Parameters:
    ///   - snapshot: 共享快照
    ///   - petID: 指定伙伴；nil 表示全部（仅自动/回退时生效）
    ///   - dayID: 用户指定的纪念日 id；nil 表示自动取最近
    ///   - now: 当前时间
    /// - Returns: 选中的纪念日；无候选返回 nil
    public static func upcomingDay(
        snapshot: WidgetSnapshot,
        petID: UUID?,
        dayID: String?,
        now: Date
    ) -> UpcomingDaySelection? {
        if let dayID,
           let matched = snapshot.upcomingDays.first(where: { $0.id == dayID }),
           let selection = computeSelection(for: matched, now: now) {
            return selection
        }
        return nextUpcomingDay(snapshot: snapshot, petID: petID, now: now)
    }

    /// 计算单个纪念日候选的倒计时与陪伴天数。
    ///
    /// 把 originalDate 推进到今年/明年的下一次月日匹配，得到 daysUntil（≥0）与
    /// daysTogether（≥0）。日期无效时返回 nil。
    private static func computeSelection(
        for day: UpcomingDayProjection, now: Date
    ) -> UpcomingDaySelection? {
        let cal = miLensUTCCalendar
        let nowYear = cal.component(.year, from: now)

        let comp = cal.dateComponents([.month, .day], from: day.originalDate)
        guard let month = comp.month, let dayNum = comp.day else { return nil }

        var dc = DateComponents()
        dc.year = nowYear
        dc.month = month
        dc.day = dayNum
        guard let thisYear = cal.date(from: dc) else { return nil }

        let startOfToday = cal.startOfDay(for: now)
        let target = thisYear >= startOfToday
            ? thisYear
            : {
                dc.year = nowYear + 1
                return cal.date(from: dc) ?? thisYear
            }()

        let daysUntil = max(0, cal.dateComponents([.day], from: startOfToday, to: cal.startOfDay(for: target)).day ?? 0)
        let daysTogether = max(0, cal.dateComponents([.day], from: day.originalDate, to: now).day ?? 0)
        return UpcomingDaySelection(day: day, daysUntil: daysUntil, daysTogether: daysTogether)
    }

    // MARK: 档案统计

    /// 档案年轮 Widget 的统计数据（WidgetKit-Design.md §3.4）。
    ///
    /// `petID==nil` 时返回快照中的整体统计；指定 petID 时按该宠物过滤重新计数。
    public static func archiveStats(
        snapshot: WidgetSnapshot,
        petID: UUID?
    ) -> ArchiveStats {
        guard let petID else { return snapshot.archiveStats }

        let petPhotos = snapshot.photos.filter { $0.petID == petID }
        let works = petPhotos.filter { $0.isWork }.count
        let startDate = petPhotos
            .compactMap { $0.takenAt }
            .min()

        return ArchiveStats(
            totalPhotos: snapshot.pets.first { $0.id == petID }?.photoCount ?? petPhotos.count,
            totalMemories: 0,
            totalWorks: works,
            archiveStartDate: startDate,
            petCount: 1
        )
    }

    // MARK: 状态判定

    /// 判定 Widget 应处于哪种展示状态（WidgetKit-Design.md §4）。
    ///
    /// - 快照缺失或 schemaVersion 不兼容 → `.stale`
    /// - 快照过期（lastUpdated 超过阈值）→ `.stale`
    /// - 无宠物 → `.empty`
    /// - 有宠物但无照片（且照片池为空）→ `.empty`
    /// - 其余 → `.content`
    public static func resolveState(
        snapshot: WidgetSnapshot?,
        now: Date,
        petID: UUID?
    ) -> WidgetDisplayState {
        guard let snapshot,
              snapshot.schemaVersion == WidgetSharedConfig.currentSchemaVersion else {
            return .stale
        }
        // 过期判定
        let age = now.timeIntervalSince(snapshot.lastUpdated)
        if age > WidgetSharedConfig.staleThresholdSeconds { return .stale }

        if snapshot.pets.isEmpty { return .empty }

        // 指定伙伴时检查该伙伴是否有照片；全部伙伴时检查照片池非空
        if let petID {
            let hasPet = snapshot.pets.contains { $0.id == petID }
            if !hasPet { return .empty }
            let hasPhotos = snapshot.photos.contains { $0.petID == petID }
            if !hasPhotos { return .empty }
        } else if snapshot.photos.isEmpty {
            return .empty
        }

        return .content
    }

    // MARK: 日期工具

    /// 判断照片是否为「今日」拍摄（同年同月同日）。
    public static func isToday(takenAt: Date?, now: Date) -> Bool {
        guard let takenAt else { return false }
        return miLensUTCCalendar.isDate(takenAt, inSameDayAs: now)
    }
}
