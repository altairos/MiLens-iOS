import Foundation

/// V1 商业规则的单一事实来源。当前权益与未来权益分开维护，避免付费墙把规划功能当成已交付能力。
enum CommercialRules {
    static let freePetLimit = 1
    static let proPetLimit = 20
    static let freeBeadGenerationsPerDay = 5
    static let freeTimelineDays = 365
    static let timelinePreviewDays = 14
    /// 免费版照片保存上限（ADR-0010）。Pro 不限——用 Int.max 表示无限制。
    static let freePhotoLimit = 50
    static let proPhotoLimit = Int.max

    static func petLimit(isPro: Bool) -> Int {
        isPro ? proPetLimit : freePetLimit
    }

    /// 照片保存上限。Pro 返回 Int.max（调用方用 `== .max` 或 `< 实际值` 判断）。
    static func photoLimit(isPro: Bool) -> Int {
        isPro ? proPhotoLimit : freePhotoLimit
    }

    /// 导入配额检查：在已有 currentCount 张照片的基础上，本次尝试导入 requestCount 张。
    /// - Returns: 允许导入的数量（Pro 不限；免费版取 min(剩余配额, 请求数)）
    static func allowedImportCount(
        currentCount: Int, requestCount: Int, isPro: Bool
    ) -> Int {
        guard !isPro else { return requestCount }
        let remaining = max(0, freePhotoLimit - currentCount)
        return min(remaining, requestCount)
    }
}

protocol TimelineAccessStore: AnyObject {
    func firstAccessDate(now: Date) -> Date
}

/// 记录用户首次真正打开时间线的日期；不以安装日计时，避免用户尚未形成数据就被扣体验时间。
final class UserDefaultsTimelineAccessStore: TimelineAccessStore {
    private let defaults: UserDefaults
    private let key = "commercial.timeline.firstAccessDate"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func firstAccessDate(now: Date = Date()) -> Date {
        if let existing = defaults.object(forKey: key) as? Date {
            return existing
        }
        defaults.set(now, forKey: key)
        return now
    }
}

protocol BeadGenerationQuotaStore: AnyObject {
    var usedToday: Int { get }
    func recordSuccessfulGeneration()
}

/// 本地自然日配额。只在生成成功后记账，失败或取消不会消耗次数。
final class UserDefaultsBeadGenerationQuotaStore: BeadGenerationQuotaStore {
    private let defaults: UserDefaults
    private let countKey = "commercial.beadGeneration.count"
    private let dayKey = "commercial.beadGeneration.day"
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    var usedToday: Int {
        guard defaults.object(forKey: dayKey) as? Date == calendar.startOfDay(for: Date()) else {
            return 0
        }
        return defaults.integer(forKey: countKey)
    }

    func recordSuccessfulGeneration() {
        let today = calendar.startOfDay(for: Date())
        let count = defaults.object(forKey: dayKey) as? Date == today ? defaults.integer(forKey: countKey) : 0
        defaults.set(today, forKey: dayKey)
        defaults.set(count + 1, forKey: countKey)
    }
}

enum TimelineAccessLogic {
    static func previewDaysRemaining(
        now: Date,
        firstAccessDate: Date,
        calendar: Calendar = PetDateCalendar.gregorian
    ) -> Int {
        let start = calendar.startOfDay(for: firstAccessDate)
        let today = calendar.startOfDay(for: now)
        let elapsed = max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
        return max(0, CommercialRules.timelinePreviewDays - elapsed)
    }

    static func isInFullHistoryPreview(
        now: Date,
        firstAccessDate: Date,
        calendar: Calendar = PetDateCalendar.gregorian
    ) -> Bool {
        previewDaysRemaining(now: now, firstAccessDate: firstAccessDate, calendar: calendar) > 0
    }

    static func visibleEntries(
        _ entries: [TimelineEntry],
        now: Date,
        isPro: Bool,
        firstAccessDate: Date? = nil,
        calendar: Calendar = PetDateCalendar.gregorian
    ) -> [TimelineEntry] {
        if isPro { return entries }
        if let firstAccessDate,
           isInFullHistoryPreview(now: now, firstAccessDate: firstAccessDate, calendar: calendar) {
            return entries
        }
        guard let cutoff = calendar.date(byAdding: .day, value: -CommercialRules.freeTimelineDays, to: now)
        else { return entries }
        return entries.filter { entry in
            guard let date = entry.date else { return true }
            return date >= cutoff
        }
    }

    static func hasLockedHistory(
        _ entries: [TimelineEntry],
        now: Date,
        isPro: Bool,
        firstAccessDate: Date? = nil,
        calendar: Calendar = PetDateCalendar.gregorian
    ) -> Bool {
        visibleEntries(entries, now: now, isPro: isPro, firstAccessDate: firstAccessDate, calendar: calendar).count < entries.count
    }
}
