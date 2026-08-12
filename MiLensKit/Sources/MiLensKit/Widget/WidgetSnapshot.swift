//  WidgetSnapshot —— 主 App 与 Widget Extension 共享的数据快照模型。
//
//  Widget 不直接打开 SwiftData store（WidgetKit-Design.md §6.1）：主 App 在数据变更后
//  把所需投影写入 App Group 容器（一个有上限的 JSON + 降采样缩略图），Widget 只读这个
//  快照。共享内容只包含 Widget 渲染必需的字段：UUID、显示名、日期、计数、最多一行标题、
//  深链目标和缩略图文件名；不包含全尺寸照片、备注全文或敏感分析数据。
//
//  纯 Codable + Sendable：可在主 App（SwiftData 投影）和 Widget Extension（JSON 解码）
//  之间安全跨进程传递。DESIGN.md §4：MiLensKit 纯类型，无 IO / 无 SwiftUI 依赖。

import Foundation

// MARK: - 共享配置常量

/// 主 App 与 Widget Extension 共享的 App Group 容器与文件命名约定。
///
/// 两侧（App target 与 Widget Extension target）必须在 entitlements 中声明同一个
/// App Group，本枚举给出统一的容器 ID、快照文件名与缩略图目录名，避免硬编码漂移。
public enum WidgetSharedConfig {
    /// App Group 容器标识（两侧 entitlements 必须一致）。
    public static let appGroupID = "group.com.milens.app"
    /// 快照 JSON 文件名（存于 App Group 容器根目录）。
    public static let snapshotFileName = "widget_snapshot.json"
    /// 缩略图子目录名（存于 App Group 容器内）。
    public static let thumbnailsDirName = "widget_thumbnails"
    /// 深链 URL Scheme（`milens://photo/{id}` 等）。
    public static let deepLinkScheme = "milens"
    /// 快照格式的当前 schema 版本；结构变更时递增，Widget 据此判断兼容性。
    public static let currentSchemaVersion = 1
    /// 快照被认为「过期」的阈值（秒）；超过此阈值 Widget 展示 stale 状态。
    public static let staleThresholdSeconds: TimeInterval = 6 * 3600
}

// MARK: - 顶层快照

/// Widget 渲染所需的完整数据快照。
///
/// 主 App 负责组装并写入 App Group；Widget 的 TimelineProvider 负责读取并交给
/// `WidgetSelectionLogic` 选择展示内容。快照大小有界：照片投影列表上限约 50 条，
/// 缩略图文件上限约 20 个，单图 ≤300pt。
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    /// 全部宠物档案投影。
    public let pets: [PetProjection]
    /// 最近一批照片投影（按拍摄时间倒序，上限由写入方控制）。
    public let photos: [PhotoProjection]
    /// 即将到来的纪念日候选（生日 / 领养日 / 用户纪念事件）。
    public let upcomingDays: [UpcomingDayProjection]
    /// 档案整体统计。
    public let archiveStats: ArchiveStats
    /// 快照写入时间（UTC）。
    public let lastUpdated: Date
    /// 快照格式版本（用于兼容性判断）。
    public let schemaVersion: Int

    public init(
        pets: [PetProjection],
        photos: [PhotoProjection],
        upcomingDays: [UpcomingDayProjection],
        archiveStats: ArchiveStats,
        lastUpdated: Date,
        schemaVersion: Int = WidgetSharedConfig.currentSchemaVersion
    ) {
        self.pets = pets
        self.photos = photos
        self.upcomingDays = upcomingDays
        self.archiveStats = archiveStats
        self.lastUpdated = lastUpdated
        self.schemaVersion = schemaVersion
    }
}

// MARK: - 宠物投影

/// 宠物档案投影（Widget 所需字段的子集）。
public struct PetProjection: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    /// 物种原始字符串（"cat" / "dog" / "unknown" 等，UI 层负责本地化）。
    public let species: String
    public let birthday: Date?
    public let adoptionDay: Date?
    /// 该宠物的照片计数缓存。
    public let photoCount: Int

    public init(
        id: UUID,
        name: String,
        species: String,
        birthday: Date?,
        adoptionDay: Date?,
        photoCount: Int
    ) {
        self.id = id
        self.name = name
        self.species = species
        self.birthday = birthday
        self.adoptionDay = adoptionDay
        self.photoCount = photoCount
    }
}

// MARK: - 照片投影

/// 照片投影（Widget 所需字段的子集）。
///
/// `thumbnailFileName` 指向 App Group 缩略图目录下的文件；Widget 据此拼路径加载
/// 降采样后的图像（不读取全尺寸原图）。
public struct PhotoProjection: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// 归属宠物 ID（nil = 未归属）。
    public let petID: UUID?
    /// 归属宠物显示名（冗余字段，Widget 直接渲染避免二次查表）。
    public let petName: String?
    /// 缩略图文件名（位于 App Group/thumbnails/，nil = 无缩略图）。
    public let thumbnailFileName: String?
    public let takenAt: Date?
    /// 最多一行的标题/备注摘要（WidgetKit-Design.md §6.1：最多一行标题）。
    public let note: String
    /// 综合质量评分 0…1（选片排序用）。
    public let qualityScore: Double
    /// 是否为作品记录（拼豆 / 编辑产物，用于「最近拼豆作品」内容源）。
    public let isWork: Bool

    public init(
        id: UUID,
        petID: UUID?,
        petName: String?,
        thumbnailFileName: String?,
        takenAt: Date?,
        note: String,
        qualityScore: Double,
        isWork: Bool
    ) {
        self.id = id
        self.petID = petID
        self.petName = petName
        self.thumbnailFileName = thumbnailFileName
        self.takenAt = takenAt
        self.note = note
        self.qualityScore = qualityScore
        self.isWork = isWork
    }
}

// MARK: - 纪念日投影

/// 即将到来的纪念日候选投影。
///
/// `kind` 标注来源类型，决定「已陪伴天数」的文案语义（生日=出生至今 / 领养=已陪伴 /
/// 纪念=已记录）。`originalDate` 是该纪念日的原始发生日期（如出生日），Widget 据此
/// 推算下一次月日匹配与倒计时。
public struct UpcomingDayProjection: Codable, Sendable, Equatable {
    /// 纪念日来源类型。
    public let kind: Kind
    public let petID: UUID
    public let petName: String
    /// 纪念日标题（「小满的生日」/「第一次见面的日子」）。
    public let title: String
    /// 该纪念日的原始发生日期。
    public let originalDate: Date

    public init(kind: Kind, petID: UUID, petName: String, title: String, originalDate: Date) {
        self.kind = kind
        self.petID = petID
        self.petName = petName
        self.title = title
        self.originalDate = originalDate
    }

    /// 纪念日来源类型，决定陪伴天数的文案语义。
    public enum Kind: String, Codable, Sendable, Equatable {
        /// 生日：daysTogether 语义 = 「出生至今 N 天」。
        case birthday
        /// 领养日：daysTogether 语义 = 「已陪伴 N 天」。
        case adoption
        /// 其他用户纪念事件：daysTogether 语义 = 「已记录 N 天」。
        case memorial
    }
}

// MARK: - 档案统计

/// 档案整体统计投影（档案年轮 Widget 直接消费）。
public struct ArchiveStats: Codable, Sendable, Equatable {
    /// 照片总数。
    public let totalPhotos: Int
    /// 记忆总数（PetEvent 中 sourceType=user 的记录数）。
    public let totalMemories: Int
    /// 作品总数（Photo.category == "edited"）。
    public let totalWorks: Int
    /// 档案起始日期（最早的照片拍摄时间或宠物创建时间）。
    public let archiveStartDate: Date?
    /// 宠物数量。
    public let petCount: Int

    public init(
        totalPhotos: Int,
        totalMemories: Int,
        totalWorks: Int,
        archiveStartDate: Date?,
        petCount: Int
    ) {
        self.totalPhotos = totalPhotos
        self.totalMemories = totalMemories
        self.totalWorks = totalWorks
        self.archiveStartDate = archiveStartDate
        self.petCount = petCount
    }

    /// 空统计（无宠物 / 无照片时的默认值）。
    public static let empty = ArchiveStats(
        totalPhotos: 0, totalMemories: 0, totalWorks: 0,
        archiveStartDate: nil, petCount: 0
    )
}

// MARK: - 空快照

public extension WidgetSnapshot {
    /// 完全为空的快照（无宠物无照片），Widget 据此展示 empty 状态。
    static let empty = WidgetSnapshot(
        pets: [],
        photos: [],
        upcomingDays: [],
        archiveStats: .empty,
        lastUpdated: .distantPast,
        schemaVersion: WidgetSharedConfig.currentSchemaVersion
    )
}
