//  BackupService —— 离线照片导出备份/恢复接口预留（ADR-0010 §8）。
//
//  功能：将照片原图 + 完整元数据打包为 .milensbackup（ZIP），
//  通过 ShareSheet 导出到 Files/iCloud Drive/AirDrop，完全离线。
//  V1 仅预留接口，不实现实际打包逻辑。
//
//  隐私原则：照片不离开设备。ShareSheet 本身不联网，
//  用户自行决定存储位置。

import Foundation

// MARK: - 备份包数据模型

/// 备份清单（manifest.json），记录备份包版本与统计信息。
struct BackupManifest: Codable, Equatable, Sendable {
    /// 数据结构版本（未来 Schema 迁移用）。
    let schemaVersion: Int
    /// App 版本号（语义化版本，诊断兼容性用）。
    let appVersion: String
    /// 备份导出时间。
    let exportDate: Date
    /// 照片总数。
    let photoCount: Int
    /// 宠物总数。
    let petCount: Int
}

/// 宠物导出投影（脱离 SwiftData @Model，便于 Codable 序列化）。
/// CLIP featureData 不导出（可从照片重新生成）。
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
}

/// 宠物事件导出投影。
struct PetEventSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let petID: UUID
    let eventType: String
    let eventDate: Date
    let title: String
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
    /// 生成的备份文件临时路径（供 ShareSheet 分享）。
    let fileURL: URL
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
        }
    }
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
    /// 服务是否可用（V1 返回 false）。
    var isAvailable: Bool { get }

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
    ///   - url: 用户通过 DocumentPicker 选择的备份文件 URL。
    ///   - progress: 进度回调（主线程）。
    /// - Returns: 恢复结果统计。
    /// - Note: 合并导入，不覆盖现有数据（同 ID 跳过）。
    func importBackup(
        from url: URL,
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
}

// MARK: - V1 占位实现

/// 备份服务占位实现（V1：所有方法 throw `.serviceUnavailable`）。
/// UI 层通过 `isAvailable == false` 隐藏备份入口或显示「即将上线」。
final class UnavailableBackupService: BackupService {
    init() {}

    var isAvailable: Bool { false }

    func exportBackup(
        petIDs: [UUID]?,
        progress: @Sendable @MainActor (BackupProgress) -> Void
    ) async throws -> BackupResult {
        throw BackupServiceError.serviceUnavailable
    }

    func importBackup(
        from url: URL,
        progress: @Sendable @MainActor (RestoreProgress) -> Void
    ) async throws -> RestoreResult {
        throw BackupServiceError.serviceUnavailable
    }
}
