//  BackupService —— 离线照片导出备份/恢复接口预留（ADR-0010 §8）。
//
//  功能：将照片原图 + 完整元数据打包为 .milensbackup（ZIP），
//  通过 ShareSheet 导出到 Files/iCloud Drive/AirDrop，完全离线。
//  V1 仅预留接口，不实现实际打包逻辑。
//
//  隐私原则：App 不主动上传照片。ShareSheet 由用户自行决定存储位置，
//  编辑产物可能随用户启用的系统备份保存。

import Foundation

// MARK: - 备份包数据模型

/// 备份清单（manifest.json），记录备份包版本与统计信息。
struct BackupManifest: Codable, Equatable, Sendable {
    /// 数据结构版本（未来 Schema 迁移用）。
    let schemaVersion: Int
    /// App 版本号（语义化版本，诊断兼容性用）。
    let appVersion: String
    /// 导出端平台标识（"ios" / "harmony" / "android"），供跨平台转换器路由。
    /// 旧版备份包无此字段 → 解码为 nil（向后兼容，按 ios 处理）。
    let platform: String?
    /// 备份导出时间。
    let exportDate: Date
    /// 照片总数。
    let photoCount: Int
    /// 宠物总数。
    let petCount: Int
    /// 分卷集合标识（同一 backupID 的多个卷属于同一次导出）。
    /// 旧版备份包无此字段 → 解码为 nil（向后兼容，按旧格式单卷处理）。
    let backupID: String?
    /// 卷号（1-based）；nil = 旧格式单卷备份。
    let volumeNumber: Int?
    /// 总卷数；nil = 旧格式单卷备份。
    let totalVolumes: Int?

    /// 成员构造器（导出端 + 测试用）。
    init(schemaVersion: Int, appVersion: String, platform: String?,
         exportDate: Date, photoCount: Int, petCount: Int,
         backupID: String? = nil, volumeNumber: Int? = nil,
         totalVolumes: Int? = nil) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.platform = platform
        self.exportDate = exportDate
        self.photoCount = photoCount
        self.petCount = petCount
        self.backupID = backupID
        self.volumeNumber = volumeNumber
        self.totalVolumes = totalVolumes
    }

    /// 自定义解码：旧版备份包缺 backupID/volumeNumber/totalVolumes 时回退为 nil，避免解码失败。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        appVersion = try c.decode(String.self, forKey: .appVersion)
        platform = try c.decodeIfPresent(String.self, forKey: .platform)
        exportDate = try c.decode(Date.self, forKey: .exportDate)
        photoCount = try c.decode(Int.self, forKey: .photoCount)
        petCount = try c.decode(Int.self, forKey: .petCount)
        backupID = try c.decodeIfPresent(String.self, forKey: .backupID)
        volumeNumber = try c.decodeIfPresent(Int.self, forKey: .volumeNumber)
        totalVolumes = try c.decodeIfPresent(Int.self, forKey: .totalVolumes)
    }
}

/// 宠物导出投影（脱离 SwiftData @Model，便于 Codable 序列化）。
/// CLIP featureData 不导出（可从照片重新生成）。
///
/// species / gender 存语义字符串（"cat" / "dog" / "unknown"，"male" / "female" / "unknown"），
/// 跨平台可读；恢复端兼容旧版数字字符串（"0" / "1" / "2"）自动回退解析。
struct PetSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let species: String
    let breed: String
    let gender: String
    let birthday: Date?
    let adoptionDay: Date?
    let avatarFileName: String?
    let notes: String
    let photoCount: Int
    let createdAt: Date
}

/// 照片导出投影。photoFileName 对应 photos/ 目录中的文件名。
///
/// 质量分析字段（sharpness / duplicateOf / isBest）纳入快照，
/// 确保备份恢复后不丢失分析结果。新增字段使用 decodeIfPresent 向后兼容
/// 旧版备份包（缺省为 Photo 默认值），与 PetEventSnapshot 策略一致。
struct PhotoSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let originalURI: String
    let petID: UUID?
    let takenAt: Date?
    let latitude: Double
    let longitude: Double
    let placeName: String
    let note: String
    let isFavorite: Bool
    let eventNotify: Bool
    let width: Int
    let height: Int
    let fileSize: Int64
    let category: String
    let subCategory: String
    let phash: String
    let qualityScore: Double
    /// photos/ 目录中的文件名（{uuid}.jpg）。
    let photoFileName: String
    /// 原始入库时间（保留导入顺序，恢复后排序一致）。
    let createdAt: Date
    /// Laplacian 方差清晰度（对应 Photo.sharpness）。
    let sharpness: Double
    /// 重复归属：指向本组 best 照片的 id（nil = 非重复或自身是 best）。
    let duplicateOf: UUID?
    /// 是否为本重复组的最佳照片（对应 Photo.isBest）。
    let isBest: Bool

    /// 成员构造器（导出端 + 测试用）。
    init(id: UUID, originalURI: String, petID: UUID?, takenAt: Date?,
         latitude: Double, longitude: Double, placeName: String, note: String,
         isFavorite: Bool, eventNotify: Bool, width: Int, height: Int,
         fileSize: Int64, category: String, subCategory: String,
         phash: String, qualityScore: Double, photoFileName: String,
         createdAt: Date,
         sharpness: Double = 0, duplicateOf: UUID? = nil, isBest: Bool = true) {
        self.id = id
        self.originalURI = originalURI
        self.petID = petID
        self.takenAt = takenAt
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
        self.note = note
        self.isFavorite = isFavorite
        self.eventNotify = eventNotify
        self.width = width
        self.height = height
        self.fileSize = fileSize
        self.category = category
        self.subCategory = subCategory
        self.phash = phash
        self.qualityScore = qualityScore
        self.photoFileName = photoFileName
        self.createdAt = createdAt
        self.sharpness = sharpness
        self.duplicateOf = duplicateOf
        self.isBest = isBest
    }

    /// 自定义解码：旧版备份包缺 sharpness/duplicateOf/isBest 时回退为 Photo 默认值，避免解码失败。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        originalURI = try c.decode(String.self, forKey: .originalURI)
        petID = try c.decodeIfPresent(UUID.self, forKey: .petID)
        takenAt = try c.decodeIfPresent(Date.self, forKey: .takenAt)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        placeName = try c.decode(String.self, forKey: .placeName)
        note = try c.decode(String.self, forKey: .note)
        isFavorite = try c.decode(Bool.self, forKey: .isFavorite)
        eventNotify = try c.decode(Bool.self, forKey: .eventNotify)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        fileSize = try c.decode(Int64.self, forKey: .fileSize)
        category = try c.decode(String.self, forKey: .category)
        subCategory = try c.decode(String.self, forKey: .subCategory)
        phash = try c.decode(String.self, forKey: .phash)
        qualityScore = try c.decode(Double.self, forKey: .qualityScore)
        photoFileName = try c.decode(String.self, forKey: .photoFileName)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        sharpness = try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        duplicateOf = try c.decodeIfPresent(UUID.self, forKey: .duplicateOf)
        isBest = try c.decodeIfPresent(Bool.self, forKey: .isBest) ?? true
    }
}

/// 宠物事件导出投影。
/// 包含 PetEvent 全部字段（notify/body/sourceType/isPinned/relatedPhotoID），
/// 确保备份恢复后记忆正文、置顶、来源和关联照片不丢失。
/// 新增字段使用 decodeIfPresent 向后兼容旧版备份包（缺省为 PetEvent 默认值）。
struct PetEventSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let petID: UUID
    let eventType: String
    let eventDate: Date
    let title: String
    /// 是否启用通知提醒（对应 PetEvent.notify）。
    let notify: Bool
    /// 用户记录正文（对应 PetEvent.body）。
    let body: String
    /// 来源标签（对应 PetEvent.sourceType）。
    let sourceType: String
    /// 是否置顶（对应 PetEvent.isPinned）。
    let isPinned: Bool
    /// 关联照片 ID（对应 PetEvent.relatedPhotoID）。
    let relatedPhotoID: UUID?

    /// 成员构造器（导出端 + 测试用）。
    init(id: UUID, petID: UUID, eventType: String, eventDate: Date, title: String,
         notify: Bool = true, body: String = "", sourceType: String = "system",
         isPinned: Bool = false, relatedPhotoID: UUID? = nil) {
        self.id = id
        self.petID = petID
        self.eventType = eventType
        self.eventDate = eventDate
        self.title = title
        self.notify = notify
        self.body = body
        self.sourceType = sourceType
        self.isPinned = isPinned
        self.relatedPhotoID = relatedPhotoID
    }

    /// 自定义解码：旧版备份包缺新字段时回退为 PetEvent 默认值，避免解码失败。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        petID = try c.decode(UUID.self, forKey: .petID)
        eventType = try c.decode(String.self, forKey: .eventType)
        eventDate = try c.decode(Date.self, forKey: .eventDate)
        title = try c.decode(String.self, forKey: .title)
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? true
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        sourceType = try c.decodeIfPresent(String.self, forKey: .sourceType) ?? "system"
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        relatedPhotoID = try c.decodeIfPresent(UUID.self, forKey: .relatedPhotoID)
    }
}

/// 完整备份元数据（metadata.json）。
struct BackupMetadata: Codable, Equatable, Sendable {
    let pets: [PetSnapshot]
    let photos: [PhotoSnapshot]
    let petEvents: [PetEventSnapshot]
}

// MARK: - 进度与结果

/// 备份导出进度。
struct BackupProgress: Equatable, Sendable {
    let current: Int
    let total: Int
    let phase: BackupPhase

    enum BackupPhase: String, Sendable {
        case collectingMetadata   // 收集元数据
        case copyingPhotos        // 复制照片文件
        case compressing          // 压缩打包
        case done                 // 完成
    }

    var fraction: Double {
        total > 0 ? Double(current) / Double(total) : 0
    }
}

/// 备份导出结果。
struct BackupResult: Equatable, Sendable {
    /// 生成的备份文件临时路径列表（单卷为 1 个，多卷为 N 个，供 ShareSheet 分享）。
    let fileURLs: [URL]
    let manifest: BackupManifest
    let metadata: BackupMetadata
}

/// 恢复导入进度。
struct RestoreProgress: Equatable, Sendable {
    let current: Int
    let total: Int
    let phase: RestorePhase

    enum RestorePhase: String, Sendable {
        case decompressing        // 解压
        case validating           // 校验版本
        case importingMetadata    // 导入元数据
        case copyingFiles         // 复制照片文件
        case done                 // 完成
    }

    var fraction: Double {
        total > 0 ? Double(current) / Double(total) : 0
    }
}

/// 恢复导入结果。
struct RestoreResult: Equatable, Sendable {
    let importedPets: Int
    let importedPhotos: Int
    let importedEvents: Int
    /// 跳过的记录数（如重复 ID、版本不兼容字段）。
    let skipped: Int
}

// MARK: - 错误

enum BackupServiceError: Error, LocalizedError, Sendable {
    case serviceUnavailable
    case backupFailed(String)
    case restoreFailed(String)
    case invalidFormat
    case unsupportedVersion(found: Int, supported: Int)
    case writeFailed(String)
    case readFailed(String)
    case cancelled
    /// 备份导出大小超过上限（照片数据总量过大）。
    case backupTooLarge
    /// 备份恢复文件大小超过上限（解压后总量过大）。
    case restoreTooLarge(String)
    /// 多卷备份恢复时卷数不完整（选择文件数与期望不符）。
    case incompleteVolumeSet(found: Int, expected: Int)
    /// 多卷备份恢复时 backupID 不一致（混入了不同导出的卷）。
    case mismatchedBackupID

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:           return "备份功能暂未开放"
        case .backupFailed(let msg):         return "备份失败：\(msg)"
        case .restoreFailed(let msg):        return "恢复失败：\(msg)"
        case .invalidFormat:                 return "备份文件格式无效"
        case .unsupportedVersion(let f, let s): return "备份版本不兼容（文件 v\(f)，支持 v\(s)）"
        case .writeFailed(let msg):          return "写入失败：\(msg)"
        case .readFailed(let msg):           return "读取失败：\(msg)"
        case .cancelled:                     return "操作已取消"
        case .backupTooLarge:                return "备份内容过大，请减少导出范围后重试"
        case .restoreTooLarge(let msg):      return "备份文件过大：\(msg)"
        case .incompleteVolumeSet(let f, let e):
            return "分卷不完整（已选 \(f) 个，共需 \(e) 个），请选择全部 \(e) 个分卷文件后重试"
        case .mismatchedBackupID:            return "选中的分卷不属于同一次导出，请检查后重选"
        }
    }
}

// MARK: - 预估

/// 备份导出前的内容预估（供 UI 在导出前向用户展示规模）。
struct BackupEstimate: Equatable, Sendable {
    /// 将导出的宠物档案数。
    let petCount: Int
    /// 将导出的照片数。
    let photoCount: Int
    /// 预计导出字节数（基于照片 fileSize 之和，供 UI 展示预计大小）。
    let estimatedBytes: Int64
}

// MARK: - 协议

/// 离线备份服务抽象（业务层依赖此协议，不依赖具体实现）。
///
/// 设计要点：
/// - 备份为 **Pro 专属功能**（UI 层门控）。
/// - 恢复对 **所有用户开放**（不限制恢复已获得的备份文件）。
/// - 备份文件扩展名 `.milensbackup`，实际为 ZIP 格式。
/// - 导出后通过 ShareSheet 分享，不联网。
protocol BackupService: Sendable {
    /// 服务是否可用（UI 层据此禁用/隐藏备份入口或显示「即将上线」）。
    var isAvailable: Bool { get }

    /// 预估将导出的内容规模（不实际打包，仅统计计数）。
    /// - Parameter petIDs: 指定宠物 ID（nil = 全部宠物）。
    /// - Returns: 宠物数与照片数预估，供导出前确认展示。
    func estimateBackup(petIDs: [UUID]?) async throws -> BackupEstimate

    /// 导出备份包。
    /// - Parameters:
    ///   - petIDs: 指定宠物 ID（nil = 全部宠物）。
    ///   - progress: 进度回调（主线程）。
    /// - Returns: 备份结果（含临时文件路径，供 ShareSheet 分享）。
    func exportBackup(
        petIDs: [UUID]?,
        progress: @Sendable @MainActor (BackupProgress) -> Void
    ) async throws -> BackupResult

    /// 从备份文件恢复。
    /// - Parameters:
    ///   - urls: 用户通过 DocumentPicker 选择的备份文件 URL 列表
    ///     （单卷为 1 个，多卷为全部分卷）。
    ///   - progress: 进度回调（主线程）。
    /// - Returns: 恢复结果统计。
    /// - Note: 合并导入，不覆盖现有数据（同 ID 跳过）。
    func importBackup(
        from urls: [URL],
        progress: @Sendable @MainActor (RestoreProgress) -> Void
    ) async throws -> RestoreResult
}

// MARK: - 常量

enum BackupConfig {
    /// 备份文件扩展名。
    static let fileExtension = "milensbackup"
    /// 当前备份 Schema 版本。
    static let currentSchemaVersion = 1
    /// 备份包内照片目录名。
    static let photosDirName = "photos"
    /// 备份包内编辑成品目录名。
    static let editsDirName = "edits"
    /// 清单文件名。
    static let manifestFileName = "manifest.json"
    /// 元数据文件名。
    static let metadataFileName = "metadata.json"

    // MARK: - 内存上限（防御性限制，避免大图库 OOM）
    /// 备份包全部条目解压后总字节数上限（2 GB，恢复侧 records 总量校验用）。
    static let maxBackupSizeBytes = 2 * 1024 * 1024 * 1024
    /// 导出侧累计字节数上限（ZIP32 安全边界）。
    ///
    /// ZIP32 使用 UInt32 记录 local header 偏移、条目大小和 central directory 偏移
    ///（上限 ~4 GB）。超过后 `UInt32(truncatingBitPattern:)` 会静默截断，生成不可
    /// 恢复的备份。此处与恢复侧一致限制为 2 GB，为 header/CD 开销留充足余量。
    static let maxTotalExportSizeBytes = 2 * 1024 * 1024 * 1024
    /// 备份包内最大条目数（manifest + metadata + 照片 + 头像 + 事件，以照片为主）。
    static let maxEntryCount = 50_000
    /// 单个条目解压后最大字节数（单张照片上限，200 MB）。
    static let maxSingleEntrySizeBytes = 200 * 1024 * 1024
    /// 流式恢复分块大小（64 KB，copyEntry 峰值内存缓冲）。
    static let backupChunkSizeBytes = 65_536
    /// 多卷分卷时每卷目标字节数（约 1.8 GB，为 ZIP header/CD 留余量）。
    static let volumeTargetSizeBytes: Int = 1_800_000_000
    /// 每个 ZIP 条目的固定开销预算（local header + central directory record + 该照片在
    /// metadata.json 中贡献的 JSON 余量）。分卷预估时叠加到每张照片字节数上，
    /// 避免实际写入超出单卷硬上限后才触发 backupTooLarge。
    static let zipEntryOverheadBytes: Int = 768
}

// MARK: - V1 占位实现

/// 备份服务占位实现（服务不可用时 UI 应通过 `isAvailable == false` 禁用入口，
/// 所有方法 throw `.serviceUnavailable` 作为第二道防线）。
final class UnavailableBackupService: BackupService {
    init() {}

    var isAvailable: Bool { false }

    func estimateBackup(petIDs: [UUID]?) async throws -> BackupEstimate {
        throw BackupServiceError.serviceUnavailable
    }

    func exportBackup(
        petIDs: [UUID]?,
        progress: @Sendable @MainActor (BackupProgress) -> Void
    ) async throws -> BackupResult {
        throw BackupServiceError.serviceUnavailable
    }

    func importBackup(
        from urls: [URL],
        progress: @Sendable @MainActor (RestoreProgress) -> Void
    ) async throws -> RestoreResult {
        throw BackupServiceError.serviceUnavailable
    }
}
