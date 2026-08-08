//  HomeMemoryLogic —— 首页「一年前的今天」回忆横滑纯决策逻辑。
//
//  UI-DESIGN.md §5.1：回忆横滑卡片展示「一年前的今天」。
//  主筛：与今天同月同日且年份更早的历史照片（N 年前的今天），按年份倒序；
//  回退：主筛为空时展示最近历史照片（避免区块空白），标题改为「往日的回忆」。
//  源端无对应实现（首页为设计稿新增概念），行为规格由本文件 + HomeLogicTests 定义并守护。
//
//  纯函数：输入照片投影（脱离 SwiftData @Model），now 参数化，固定 UTC Calendar
//  （对齐 AnniversaryLogic 的 utcCalendar 约定）。宿主（HomeViewModel）负责
//  Repository 查询与投影组装。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

// MARK: - 投影类型

/// 回忆横滑用的照片投影。
public struct HomeMemoryPhoto: Equatable, Sendable {
    public let id: UUID
    /// 拍摄时间；nil 的照片不参与回忆筛选。
    public let takenAt: Date?
    /// 照片备注（当前仅透传，供宿主展示）。
    public let note: String
    /// 归属宠物 ID（用于副标题宠物名）。
    public let petID: UUID?

    public init(id: UUID = UUID(), takenAt: Date? = nil, note: String = "", petID: UUID? = nil) {
        self.id = id
        self.takenAt = takenAt
        self.note = note
        self.petID = petID
    }
}

/// 回忆选片用的宠物投影。
public struct HomeMemoryPet: Equatable, Sendable {
    public let id: UUID
    public let name: String

    public init(id: UUID = UUID(), name: String = "") {
        self.id = id
        self.name = name
    }
}

/// 回忆横滑条目（宿主据此渲染卡片）。
public struct HomeMemoryEntry: Equatable, Sendable {
    public let photoID: UUID
    /// 条目标题：「N年前的今天」/「往日的回忆」。
    public let title: String
    /// 副标题：主筛为宠物名；回退为「2024年8月8日 · 小橘」。
    public let subtitle: String
}

// MARK: - 回忆筛选决策

/// 首页「一年前的今天」回忆筛选。
public enum HomeMemoryLogic {
    /// 回忆横滑默认条数上限。
    public static let defaultLimit = 6

    /// 选择回忆照片：优先「往年的今天」（同月同日且年份更早），按拍摄时间倒序；
    /// 主筛为空时回退最近历史照片（拍摄年份早于今年），按拍摄时间倒序截取 `limit` 张。
    ///
    /// - Parameters:
    ///   - photos: 全部已导入照片
    ///   - now: 当前时间（注入保证测试可复现）
    ///   - limit: 条数上限（默认 6）
    ///   - pets: 全部宠物（用于副标题宠物名解析）
    /// - Returns: 回忆条目列表；无可用照片时为空数组
    public static func selectMemoryPhotos(
        _ photos: [HomeMemoryPhoto],
        now: Date,
        limit: Int = defaultLimit,
        pets: [HomeMemoryPet] = []
    ) -> [HomeMemoryEntry] {
        let calendar = homeUTCCalendar
        let nowYear = calendar.component(.year, from: now)
        let nowMonth = calendar.component(.month, from: now)
        let nowDay = calendar.component(.day, from: now)

        let sameDayPhotos = photos
            .filter { photo in
                guard let takenAt = photo.takenAt else { return false }
                return calendar.component(.month, from: takenAt) == nowMonth
                    && calendar.component(.day, from: takenAt) == nowDay
                    && calendar.component(.year, from: takenAt) < nowYear
            }
            .sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }

        if !sameDayPhotos.isEmpty {
            return sameDayPhotos.prefix(limit).map { photo in
                let photoYear = calendar.component(.year, from: photo.takenAt ?? now)
                return HomeMemoryEntry(
                    photoID: photo.id,
                    title: "\(nowYear - photoYear)年前的今天",
                    subtitle: petName(for: photo.petID, pets: pets)
                )
            }
        }

        let fallbackPhotos = photos
            .filter { photo in
                guard let takenAt = photo.takenAt else { return false }
                return calendar.component(.year, from: takenAt) < nowYear
            }
            .sorted { ($0.takenAt ?? .distantPast) > ($1.takenAt ?? .distantPast) }

        return fallbackPhotos.prefix(limit).map { photo in
            let name = petName(for: photo.petID, pets: pets)
            let dateText = formatMemoryDate(photo.takenAt ?? now)
            let subtitle = name.isEmpty ? dateText : "\(dateText) · \(name)"
            return HomeMemoryEntry(
                photoID: photo.id,
                title: "往日的回忆",
                subtitle: subtitle
            )
        }
    }

    /// 判断照片是否为「历史照片」（拍摄年份严格早于当前年份）。
    /// 与 App 层 AnniversaryLogic.isHistoricalPhoto 行为一致（跨 target 不依赖，独立实现）。
    ///
    /// - Parameters:
    ///   - takenAt: 照片拍摄时间；nil 返回 false
    ///   - now: 当前时间
    public static func isHistoricalPhoto(takenAt: Date?, now: Date) -> Bool {
        guard let takenAt else { return false }
        let calendar = homeUTCCalendar
        return calendar.component(.year, from: takenAt) < calendar.component(.year, from: now)
    }

    /// 格式化拍摄日期为「2024年8月8日」（UTC，无前导零）。
    ///
    /// - Parameter date: 拍摄时间
    /// - Returns: 「年-月-日」中文格式
    public static func formatMemoryDate(_ date: Date) -> String {
        let calendar = homeUTCCalendar
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(year)年\(month)月\(day)日"
    }

    // MARK: - 内部工具

    /// 解析宠物名；未知返回空串。
    private static func petName(for petID: UUID?, pets: [HomeMemoryPet]) -> String {
        guard let petID,
              let pet = pets.first(where: { $0.id == petID }) else { return "" }
        return pet.name
    }
}
