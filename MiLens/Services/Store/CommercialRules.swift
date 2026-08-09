import Foundation

/// V1 商业规则的单一事实来源。当前权益与未来权益分开维护，避免付费墙把规划功能当成已交付能力。
enum CommercialRules {
    static let freePetLimit = 1
    static let proPetLimit = 20
    static let freeBeadGenerationsPerDay = 5
    static let freeTimelineDays = 365

    static func petLimit(isPro: Bool) -> Int {
        isPro ? proPetLimit : freePetLimit
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
    static func visibleEntries(
        _ entries: [TimelineEntry],
        now: Date,
        isPro: Bool,
        calendar: Calendar = PetDateCalendar.gregorian
    ) -> [TimelineEntry] {
        guard !isPro,
              let cutoff = calendar.date(byAdding: .day, value: -CommercialRules.freeTimelineDays, to: now)
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
        calendar: Calendar = PetDateCalendar.gregorian
    ) -> Bool {
        visibleEntries(entries, now: now, isPro: isPro, calendar: calendar).count < entries.count
    }
}
