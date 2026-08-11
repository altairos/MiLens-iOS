//  GrowthCompareLogic —— 成长对比卡片纯决策逻辑（ADR-0010 §3.3 / §10.11）。
//
//  「同一宠物早期与现在的照片并排」对比卡的数据准备。
//  负责双照片排序（早→晚）、时间标签计算（年龄或日期）、间隔文案与版式参数。
//  View 层（GrowthCompareArtwork）只做渲染。
//
//  纯函数：不依赖 Repository / SwiftData / SwiftUI。
//  宿主（GrowthCompareView）负责 IO（加载照片、Pro 门控、导出/分享）。
//  日期计算内部使用固定 UTC Calendar（miLensUTCCalendar），与 HomeMemoryLogic /
//  MilestoneLogic 保持同一约定，保证跨环境可复现。
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 SwiftUI 依赖。

import Foundation

// MARK: - 投影类型

/// 成长对比用的照片投影（脱离 SwiftData @Model）。
public struct GrowthComparePhoto: Equatable, Sendable {
    public let id: UUID
    /// 拍摄时间；nil 视为「未知时间」，排序时落后于有时间的照片。
    public let takenAt: Date?

    public init(id: UUID = UUID(), takenAt: Date? = nil) {
        self.id = id
        self.takenAt = takenAt
    }
}

/// 成长对比结果（宿主据此渲染 GrowthCompareArtwork）。
public struct GrowthCompareResult: Equatable, Sendable {
    /// 早期照片 ID（拍摄时间较早的一张）。
    public let earlyPhotoID: UUID
    /// 近期照片 ID（拍摄时间较晚的一张）。
    public let latePhotoID: UUID
    /// 早期照片的时间标签（「1岁2个月」或「2024年3月」）。
    public let earlyLabel: String
    /// 近期照片的时间标签。
    public let lateLabel: String
    /// 两张照片的时间间隔标签（「1年5个月」或「间隔 532 天」）。
    public let gapLabel: String
}

// MARK: - 决策逻辑

public enum GrowthCompareLogic {

    // MARK: - 版式参数

    /// 导出画布尺寸（像素，4:5 竖版双图对比卡，与 PetCardLogic.exportSize 一致）。
    public static let exportWidth = 1080
    public static let exportHeight = 1350

    // MARK: - 排序

    /// 按拍摄时间升序排列两张照片（早→晚）。
    /// nil 拍摄时间视为「最晚」（distantFuture），保证有时间的照片排在前面。
    /// 拍摄时间相同时保持原顺序（稳定）。
    ///
    /// - Parameters:
    ///   - first: 第一张照片
    ///   - second: 第二张照片
    /// - Returns: (早期, 近期) 有序对
    public static func orderedPair(
        _ first: GrowthComparePhoto, _ second: GrowthComparePhoto
    ) -> (early: GrowthComparePhoto, late: GrowthComparePhoto) {
        let firstDate = first.takenAt ?? .distantFuture
        let secondDate = second.takenAt ?? .distantFuture
        return secondDate < firstDate
            ? (early: second, late: first)
            : (early: first, late: second)
    }

    // MARK: - 时间标签

    /// 照片拍摄时的宠物年龄标签（如「1岁2个月」「8个月」）。
    /// 无生日时回退到拍摄日期（「2024年3月」）。
    ///
    /// - Parameters:
    ///   - birthday: 宠物生日；nil 用日期回退
    ///   - takenAt: 照片拍摄时间；nil 返回「未知」
    public static func timeLabel(birthday: Date?, takenAt: Date?) -> String {
        guard let takenAt else { return "未知" }
        guard let birthday else { return formatDateLabel(takenAt) }
        return ageLabel(birthday: birthday, at: takenAt)
    }

    /// 两张照片之间的时间间隔标签（如「1年5个月」「3个月」「间隔 532 天」）。
    public static func gapLabel(early: Date?, late: Date?) -> String {
        guard let early, let late else { return "" }
        let months = monthSpan(from: early, to: late)
        let years = months / 12
        let remainMonths = months % 12
        if years > 0 && remainMonths > 0 {
            return "\(years)年\(remainMonths)个月"
        } else if years > 0 {
            return "\(years)年"
        } else if remainMonths > 0 {
            return "\(remainMonths)个月"
        } else {
            // 不足一个月，按天数显示
            let days = daySpan(from: early, to: late)
            return "间隔 \(days) 天"
        }
    }

    // MARK: - 结果构建

    /// 从两张照片 + 宠物生日构建完整的成长对比结果。
    public static func buildResult(
        early: GrowthComparePhoto,
        late: GrowthComparePhoto,
        birthday: Date?
    ) -> GrowthCompareResult {
        let ordered = orderedPair(early, late)
        return GrowthCompareResult(
            earlyPhotoID: ordered.early.id,
            latePhotoID: ordered.late.id,
            earlyLabel: timeLabel(birthday: birthday, takenAt: ordered.early.takenAt),
            lateLabel: timeLabel(birthday: birthday, takenAt: ordered.late.takenAt),
            gapLabel: gapLabel(early: ordered.early.takenAt, late: ordered.late.takenAt)
        )
    }

    // MARK: - 内部工具

    /// 计算年龄标签（岁+月），与 PetDisplayLogic.ageText 同义（MiLensKit 内用固定中文）。
    private static func ageLabel(birthday: Date, at date: Date) -> String {
        let calendar = miLensUTCCalendar
        let bc = calendar.dateComponents([.year, .month], from: birthday)
        let nc = calendar.dateComponents([.year, .month], from: date)
        let months = ((nc.year ?? 0) - (bc.year ?? 0)) * 12 + ((nc.month ?? 0) - (bc.month ?? 0))
        let years = months / 12
        let remainMonths = months % 12
        if years > 0 && remainMonths > 0 {
            return "\(years)岁\(remainMonths)个月"
        } else if years > 0 {
            return "\(years)岁"
        } else if remainMonths > 0 {
            return "\(remainMonths)个月"
        } else {
            return "刚出生"
        }
    }

    /// 日期回退标签：「2024年3月」。
    private static func formatDateLabel(_ date: Date) -> String {
        let calendar = miLensUTCCalendar
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return "\(year)年\(month)月"
    }

    /// 两个日期之间的整月数差（截断，可为负/0）。
    private static func monthSpan(from early: Date, to late: Date) -> Int {
        let calendar = miLensUTCCalendar
        let ec = calendar.dateComponents([.year, .month], from: early)
        let lc = calendar.dateComponents([.year, .month], from: late)
        return ((lc.year ?? 0) - (ec.year ?? 0)) * 12 + ((lc.month ?? 0) - (ec.month ?? 0))
    }

    /// 两个日期之间的整天数差（截断，可为负/0）。
    private static func daySpan(from early: Date, to late: Date) -> Int {
        max(0, Int(late.timeIntervalSince(early) / 86_400))
    }
}
