//  HomeHeroLogic —— 首页 hero 照片选片与标注纯决策逻辑。
//
//  UI-DESIGN.md §5.1 hero 方案：今日最新/最佳照片 → 无今日照片回退最近一张；
//  底部极简标注「今天 · 小橘」。源端无对应实现（首页 hero 为设计稿新增概念），
//  行为规格由本文件 + HomeLogicTests 定义并守护。
//
//  纯函数：输入照片投影（脱离 SwiftData @Model 以便测试），now 参数化。
//  宿主（HomeViewModel）负责 Repository 查询与 petID → 宠物名解析。
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

    public init(id: UUID = UUID(), takenAt: Date? = nil, petID: UUID? = nil) {
        self.id = id
        self.takenAt = takenAt
        self.petID = petID
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

    /// 选择 hero 照片：今日照片中最新一张 → 无今日照片则全部照片中最新一张 → 空列表返回 nil。
    ///
    /// 排序键为 `takenAt`；无拍摄时间的照片不参与选片（无法判定新旧）。
    ///
    /// - Parameters:
    ///   - photos: 全部已导入照片
    ///   - now: 当前时间（注入保证测试可复现）
    /// - Returns: 选中的 hero 照片；照片列表为空或无有效拍摄时间时返回 nil
    public static func selectHeroPhoto(_ photos: [HomeHeroPhoto], now: Date) -> HomeHeroPhoto? {
        let todayPhotos = photos
            .filter { isToday(takenAt: $0.takenAt, now: now) }
            .sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }
        if let latestToday = todayPhotos.first {
            return latestToday
        }
        return photos
            .filter { $0.takenAt != nil }
            .sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }
            .first
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
