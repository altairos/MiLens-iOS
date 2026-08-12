//  HomeHeroLogic —— 首页 hero 照片选片与标注纯决策逻辑。
//
//  UI-DESIGN.md §5.1 hero 方案（2026-08-12 细化）：
//  今日照片中最新一张 → 无今日照片时全部照片中按质量分数 top 池随机选一张
//  → 空列表或全部无拍摄时间返回 nil。
//  底部极简标注「今天 · 小橘」/「最近 · 小橘」。
//
//  纯函数：输入照片投影（脱离 SwiftData @Model 以便测试），now / randomIndex 参数化。
//  宿主（HomeViewModel）负责 Repository 查询、petID → 宠物名解析、在 load() 时固定 randomIndex。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

// MARK: - 投影类型

/// hero 选片用的照片投影。
public struct HomeHeroPhoto: Equatable, Sendable {
    public let id: UUID
    /// 拍摄时间；nil 的照片不参与「今日」判定与选片。
    public let takenAt: Date?
    /// 归属宠物 ID（用于 hero 标注宠物名）。
    public let petID: UUID?
    /// 综合质量评分 0…1（0 = 未评分）；回退选片时作为质量 top 池排序键。
    public let qualityScore: Double

    public init(id: UUID = UUID(), takenAt: Date? = nil, petID: UUID? = nil, qualityScore: Double = 0) {
        self.id = id
        self.takenAt = takenAt
        self.petID = petID
        self.qualityScore = qualityScore
    }
}

// MARK: - 选片与标注决策

/// 首页 hero 选片与标注。
public enum HomeHeroLogic {
    /// 判断照片是否为「今日」拍摄（UTC 同年同月同日）。
    ///
    /// - Parameters:
    ///   - takenAt: 照片拍摄时间；nil 返回 false
    ///   - now: 当前时间（注入保证测试可复现）
    public static func isToday(takenAt: Date?, now: Date) -> Bool {
        guard let takenAt else { return false }
        return homeUTCCalendar.isDate(takenAt, inSameDayAs: now)
    }

    /// 选择 hero 照片，三级策略：
    /// 1. 今日照片中最新一张（按 takenAt 降序）
    /// 2. 无今日照片时 → 有拍摄时间的照片按 qualityScore 降序取 top 池（≈30%，至少 5 张），
    ///    按randomIndex 模运算从中随机选一张（每次进入首页不同，增加新鲜感）
    /// 3. 空列表或全部无拍摄时间 → nil
    ///
    /// - Parameters:
    ///   - photos: 全部已导入照片
    ///   - now: 当前时间（注入保证测试可复现）
    ///   - randomIndex: 回退选片的随机种子（调用方在 load() 时固定，避免计算属性每次重算变化）
    /// - Returns: 选中的 hero 照片；无有效候选时返回 nil
    public static func selectHeroPhoto(
        _ photos: [HomeHeroPhoto], now: Date, randomIndex: Int = 0
    ) -> HomeHeroPhoto? {
        // 1. 今日最新
        let todayPhotos = photos
            .filter { isToday(takenAt: $0.takenAt, now: now) }
            .sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }
        if let latestToday = todayPhotos.first {
            return latestToday
        }

        // 2. 回退：有拍摄时间的照片按质量分 top 池随机
        let candidates = photos.filter { $0.takenAt != nil }
        guard !candidates.isEmpty else { return nil }

        let sorted = candidates.sorted { $0.qualityScore > $1.qualityScore }
        // top 池大小：count 的 1/3 向上取整，至少 5 张，至多 candidates 全部。
        // 数量不足 5 张时全部入选（保留随机性以增加新鲜感）。
        let poolSize = min(sorted.count, max(5, (sorted.count + 2) / 3))
        let pool = Array(sorted.prefix(poolSize))
        let safeIndex = ((randomIndex % pool.count) + pool.count) % pool.count
        return pool[safeIndex]
    }

    /// 构建 hero 底部极简标注（UI-DESIGN.md §5.1）。
    ///
    /// 今日照片 → 「今天 · 小橘」；回退照片 → 「最近 · 小橘」；
    /// 无宠物名时省略后半段（仅「今天」/「最近」）。
    ///
    /// - Parameters:
    ///   - petName: 照片归属宠物名（nil 或空串表示未知）
    ///   - isToday: hero 照片是否为今日拍摄
    /// - Returns: 标注文案
    public static func buildHeroCaption(petName: String?, isToday: Bool) -> String {
        let prefix = isToday ? "今天" : "最近"
        guard let petName, !petName.isEmpty else { return prefix }
        return "\(prefix) · \(petName)"
    }
}
