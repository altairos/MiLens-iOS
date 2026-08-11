//  MemoryRecapLogic —— 月度精选 / 年度回忆册纯决策逻辑（ADR-0010 §3.3 / §10.12）。
//
//  按月/年筛选照片，用 qualityScore 排序 + isBest 去重选取代表照片，生成回忆册数据。
//  View 层（RecapView）配合 TimelineExportCanvas 渲染长图（不新建渲染管线，ADR §10.12）。
//
//  纯函数：不依赖 Repository / SwiftData / SwiftUI。
//  宿主（RecapView）负责 IO（查照片、Pro 门控、导出）。
//  日期计算内部使用固定 UTC Calendar（miLensUTCCalendar），跨环境可复现。
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 SwiftUI 依赖。

import Foundation

// MARK: - 投影类型

/// 回忆册选片用的照片投影（脱离 SwiftData @Model）。
public struct RecapPhoto: Equatable, Sendable {
    public let id: UUID
    /// 拍摄时间；nil 不参与回忆册筛选。
    public let takenAt: Date?
    /// 综合质量评分 0…1（0 = 未评分；排序权重）。
    public let qualityScore: Double
    /// 是否为本重复组的最佳照片。
    public let isBest: Bool
    /// 重复归属：指向本组 best 的 id（非 nil 表示该照片是重复项，应被跳过）。
    public let duplicateOf: UUID?
    /// 归属宠物 ID（用于多宠物回忆册的宠物名解析）。
    public let petID: UUID?

    public init(
        id: UUID = UUID(),
        takenAt: Date? = nil,
        qualityScore: Double = 0,
        isBest: Bool = false,
        duplicateOf: UUID? = nil,
        petID: UUID? = nil
    ) {
        self.id = id
        self.takenAt = takenAt
        self.qualityScore = qualityScore
        self.isBest = isBest
        self.duplicateOf = duplicateOf
        self.petID = petID
    }
}

/// 月度精选结果（一个月的代表照片集合）。
public struct MonthlyRecap: Equatable, Sendable {
    public let year: Int
    public let month: Int
    /// 代表照片 ID（按质量降序，已去重）。
    public let photoIDs: [UUID]
    /// 该月可用照片总数（去重前）。
    public let totalPhotoCount: Int
}

/// 年度回忆册结果（12 个月的月度精选汇总）。
public struct YearlyRecap: Equatable, Sendable {
    public let year: Int
    /// 按月份升序的月度精选（跳过无照片的月份）。
    public let months: [MonthlyRecap]
    /// 年度照片总数（去重前）。
    public let totalPhotoCount: Int
    /// 年度代表照片 ID（从全部月度精选中再取前 N 张）。
    public let heroPhotoIDs: [UUID]
}

// MARK: - 决策逻辑

public enum MemoryRecapLogic {

    /// 月度精选每月默认代表照片数上限。
    public static let defaultMonthlyLimit = 8
    /// 年度回忆册封面代表照片数上限。
    public static let defaultYearlyHeroLimit = 12
    /// 未评分照片的默认质量分（视为中等，不完全排除）。
    public static let unscoredFallback: Double = 0.5

    // MARK: - 去重

    /// 过滤掉非最佳重复项（duplicateOf != nil 的照片）。
    /// 单张照片（isBest=false, duplicateOf=nil）保留；重复组最佳（isBest=true）保留。
    public static func deduplicate(_ photos: [RecapPhoto]) -> [RecapPhoto] {
        photos.filter { $0.duplicateOf == nil }
    }

    // MARK: - 排序

    /// 按质量评分降序排序（未评分用 unscoredFallback 填充）。
    /// 质量相同时 isBest 优先，再按 takenAt 倒序（最新优先）。
    public static func sortedByQuality(_ photos: [RecapPhoto]) -> [RecapPhoto] {
        photos.sorted { a, b in
            let scoreA = a.qualityScore > 0 ? a.qualityScore : unscoredFallback
            let scoreB = b.qualityScore > 0 ? b.qualityScore : unscoredFallback
            if scoreA != scoreB { return scoreA > scoreB }
            if a.isBest != b.isBest { return a.isBest && !b.isBest }
            return (a.takenAt ?? .distantPast) > (b.takenAt ?? .distantPast)
        }
    }

    // MARK: - 月度精选

    /// 选取指定月份的代表照片。
    ///
    /// - Parameters:
    ///   - photos: 全部照片投影
    ///   - year: 年份
    ///   - month: 月份（1–12）
    ///   - limit: 代表照片上限（默认 8）
    /// - Returns: 月度精选；该月无照片时 totalPhotoCount 为 0
    public static func monthlyRecap(
        photos: [RecapPhoto], year: Int, month: Int, limit: Int = defaultMonthlyLimit
    ) -> MonthlyRecap {
        let calendar = miLensUTCCalendar
        let inMonth = photos.filter { photo in
            guard let takenAt = photo.takenAt else { return false }
            let c = calendar.dateComponents([.year, .month], from: takenAt)
            return c.year == year && c.month == month
        }
        let deduped = deduplicate(inMonth)
        let top = Array(sortedByQuality(deduped).prefix(limit))
        return MonthlyRecap(
            year: year,
            month: month,
            photoIDs: top.map(\.id),
            totalPhotoCount: inMonth.count
        )
    }

    // MARK: - 年度回忆册

    /// 构建年度回忆册：12 个月的月度精选 + 年度代表照片。
    ///
    /// - Parameters:
    ///   - photos: 全部照片投影
    ///   - year: 年份
    ///   - monthlyLimit: 每月代表照片上限
    ///   - heroLimit: 年度代表照片上限
    public static func yearlyRecap(
        photos: [RecapPhoto],
        year: Int,
        monthlyLimit: Int = defaultMonthlyLimit,
        heroLimit: Int = defaultYearlyHeroLimit
    ) -> YearlyRecap {
        var months: [MonthlyRecap] = []
        var totalPhotos = 0
        for month in 1...12 {
            let recap = monthlyRecap(photos: photos, year: year, month: month, limit: monthlyLimit)
            totalPhotos += recap.totalPhotoCount
            if !recap.photoIDs.isEmpty {
                months.append(recap)
            }
        }
        // 年度代表：全部年度照片去重+排序后取前 heroLimit
        let calendar = miLensUTCCalendar
        let inYear = photos.filter { photo in
            guard let takenAt = photo.takenAt else { return false }
            return calendar.component(.year, from: takenAt) == year
        }
        let heroIDs = Array(sortedByQuality(deduplicate(inYear)).prefix(heroLimit).map(\.id))

        return YearlyRecap(
            year: year,
            months: months,
            totalPhotoCount: totalPhotos,
            heroPhotoIDs: heroIDs
        )
    }

    // MARK: - 标题

    /// 月度精选标题：「2025年3月」。
    public static func monthlyTitle(year: Int, month: Int) -> String {
        "\(year)年\(month)月"
    }

    /// 年度回忆册标题：「2025 年度回忆」。
    public static func yearlyTitle(year: Int) -> String {
        "\(year) 年度回忆"
    }
}
