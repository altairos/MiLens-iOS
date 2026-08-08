//  GallerySectionLogic —— 相册按日分组纯决策逻辑。
//
//  UI-DESIGN.md §5.2：相册按日期分组，每天一个小标题（「8月7日 · 周三」）。
//  源端 Gallery 为筛选 + 网格（无分组标题），分组为 iOS 设计稿新增概念，
//  行为规格由本文件 + GallerySectionLogicTests 定义并守护。
//
//  规则（对齐源端相册排序约定 taken_at DESC，最新在前）：
//  - 按自然日分组（固定 UTC Calendar），组间日期倒序（新 → 旧）；
//  - 组内按拍摄时间倒序，同时间保持输入顺序（稳定排序）；
//  - 无拍摄时间的照片归入末尾「未标注日期」组（title 为空串，View 按需显示）。
//
//  纯函数：输入照片投影（脱离 SwiftData @Model 以便测试）。
//  宿主（GalleryViewModel）负责 Repository 查询与分页加载，
//  每次数据变化后对当前已加载照片重新分组。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

// MARK: - 投影类型

/// 相册分组用的照片投影（筛选 → 分组链式复用）。
public struct GalleryPhoto: Equatable, Sendable {
    public let id: UUID
    /// 拍摄时间；nil 的照片归入「未标注日期」组。
    public let takenAt: Date?
    /// 归属宠物 ID；nil 表示未关联宠物。
    public let petID: UUID?

    public init(id: UUID = UUID(), takenAt: Date? = nil, petID: UUID? = nil) {
        self.id = id
        self.takenAt = takenAt
        self.petID = petID
    }
}

// MARK: - 分组结果

/// 相册按日分组结果。
public struct GalleryDateSection: Equatable, Sendable {
    /// 拍摄日期（年/月/日）；nil 表示「未标注日期」组。
    public let year: Int?
    public let month: Int?
    public let day: Int?
    /// 分组标题（「8月7日 · 周三」）；未标注日期组为空串。
    public let title: String
    /// 组内照片（按拍摄时间倒序）。
    public let photos: [GalleryPhoto]
}

// MARK: - 分组决策

/// 相册按日分组。
public enum GallerySectionLogic {
    /// 周几中文名（Calendar weekday 1=周日 … 7=周六，索引 -1 对应）。
    private static let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    /// 自然日分组键。
    private struct DayKey: Hashable {
        let year: Int
        let month: Int
        let day: Int
    }

    /// 构建分组标题（「8月7日 · 周三」，月日不补零）。
    ///
    /// - Parameters:
    ///   - year: 年份
    ///   - month: 月份（1–12）
    ///   - day: 日（1–31）
    ///   - calendar: 计算周几用的日历（默认固定 UTC Calendar）
    static func dayTitle(year: Int, month: Int, day: Int, calendar: Calendar = miLensUTCCalendar) -> String {
        var dc = DateComponents()
        dc.year = year
        dc.month = month
        dc.day = day
        guard let date = calendar.date(from: dc) else { return "\(month)月\(day)日" }
        let weekday = calendar.component(.weekday, from: date)
        let name = weekdayNames.indices.contains(weekday - 1) ? weekdayNames[weekday - 1] : ""
        return "\(month)月\(day)日 · \(name)"
    }

    /// 按自然日分组照片（组间日期倒序，组内拍摄时间倒序，无日期照片放末尾）。
    ///
    /// - Parameters:
    ///   - photos: 当前已加载照片（分页加载后传入，宿主负责追加时重新分组）
    ///   - calendar: 计算自然日用的日历；nil 使用固定 UTC Calendar（默认，保证跨环境可复现）
    /// - Returns: 分组结果；空输入返回空数组
    public static func groupPhotos(
        _ photos: [GalleryPhoto],
        calendar: Calendar? = nil
    ) -> [GalleryDateSection] {
        let cal = calendar ?? miLensUTCCalendar
        var buckets: [DayKey: [GalleryPhoto]] = [:]
        var undated: [GalleryPhoto] = []
        for photo in photos {
            guard let takenAt = photo.takenAt else {
                undated.append(photo)
                continue
            }
            let c = cal.dateComponents([.year, .month, .day], from: takenAt)
            guard let year = c.year, let month = c.month, let day = c.day else {
                undated.append(photo)
                continue
            }
            buckets[DayKey(year: year, month: month, day: day), default: []].append(photo)
        }
        // 组间日期倒序（新 → 旧）
        let sortedKeys = buckets.keys.sorted {
            ($0.year, $0.month, $0.day) > ($1.year, $1.month, $1.day)
        }
        var result = sortedKeys.map { key -> GalleryDateSection in
            let sortedPhotos = (buckets[key] ?? []).sorted {
                ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast)
            }
            return GalleryDateSection(
                year: key.year, month: key.month, day: key.day,
                title: dayTitle(year: key.year, month: key.month, day: key.day, calendar: cal),
                photos: sortedPhotos
            )
        }
        // 未标注日期组放在末尾（title 空串）
        if !undated.isEmpty {
            result.append(GalleryDateSection(year: nil, month: nil, day: nil, title: "", photos: undated))
        }
        return result
    }
}
