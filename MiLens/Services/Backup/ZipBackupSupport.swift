//  ZipBackupSupport —— ZipBackupService 的支撑类型与纯函数转换层。
//
//  从 ZipBackupService.swift 拆出（600 行规模守卫，见 docs/audit/remediation-plan.md
//  P1-1），代码逐字保持，行为零变更（ZipBackupServiceTests 往返/去重/多卷用例守护）。
//
//  内容：
//  - 包格式常量与分卷配置（avatarsDirName / VolumeSplitConfig）
//  - JSON 编解码器（ISO8601 日期，键排序保证 manifest 可 diff）
//  - 导出/恢复中间数据模型（ExportBundle / PrevalidationResult / RestoreVolume）
//  - 线程安全计数器（StreamProgressCounter / ExportSizeGuard）
//  - 快照 ⇄ SwiftData 模型纯函数转换（static，不触碰实例状态）

import Foundation
import MiLensKit

/// 备份包内头像目录名（照片统一走 `BackupConfig.photosDirName`，头像独立目录避免命名冲突）。
let avatarsDirName = "avatars"

/// 分卷决策阈值（可注入，便于测试用小阈值触发多卷）。
/// 生产默认值取 `BackupConfig`（2 GB 触发多卷，每卷约 1.8 GB）。
struct VolumeSplitConfig: Sendable {
    /// 预估总字节数（含每条目开销）超过此值时触发多卷导出。
    let multiVolumeThreshold: Int
    /// 多卷导出时每卷的目标字节数（贪心分组上限）。
    let volumeTargetSizeBytes: Int

    static let `default` = VolumeSplitConfig(
        multiVolumeThreshold: BackupConfig.maxTotalExportSizeBytes,
        volumeTargetSizeBytes: BackupConfig.volumeTargetSizeBytes)
}

// MARK: - JSON 编解码（ISO8601 日期，键排序保证 manifest 可 diff）

extension ZipBackupService {

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - 导出包内部模型

/// 导出收集结果：宠物/事件快照（全集）+ 照片快照（全集）+ 文件清单。
/// 分卷导出时按 volumePhotoGroups 分割照片，头像只在卷 1 包含。
struct ExportBundle {
    let petSnaps: [PetSnapshot]
    let eventSnaps: [PetEventSnapshot]
    let photoSnaps: [PhotoSnapshot]
    /// 照片文件清单（zipPath → sourcePath → stat 真实字节数）。
    let photoFiles: [(zipPath: String, sourcePath: String, size: Int64)]
    /// 头像文件清单（每卷都包含，体积小）。
    let avatarFiles: [(zipPath: String, sourcePath: String, size: Int64)]
    /// 所有照片的预估总字节数（基于文件系统真实大小，stat 失败时 fallback DB fileSize）。
    let estimatedPhotoBytes: Int64
    /// 所有头像的预估总字节数（stat 真实大小）。
    let estimatedAvatarBytes: Int64
}

/// 预校验结果：确定哪些照片/宠物会被实际导入，以及头像首主映射。
struct PrevalidationResult: Sendable {
    let photos: Set<UUID>
    let pets: Set<UUID>
    /// 头像文件名 → 首个声明的宠物 id。只有 owner 绑定头像路径，
    /// 冲突的第二只宠物 avatarPath 为空。
    let avatarOwnerByFileName: [String: UUID]
}

/// 恢复时单个卷的读取结果（输入流保持打开，供后续文件拷贝使用）。
struct RestoreVolume {
    let manifest: BackupManifest
    let metadata: BackupMetadata
    let input: any ZipInputStream
    let recordMap: [String: ZipReader.ZipEntryRecord]
}

/// 线程安全进度计数器（流式导出闭包按序递增，供进度回调使用）。
/// writeArchive 顺序处理 entries，但闭包是 @Sendable，需保证计数器本身线程安全。
final class StreamProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    let total: Int

    init(total: Int) { self.total = total }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    @discardableResult
    func next() -> Int {
        lock.lock()
        _value += 1
        let result = _value
        lock.unlock()
        return result
    }
}

/// 导出总量守卫（线程安全累计器）。
///
/// `ZipWriter.writeArchive` 顺序处理 entries，但闭包是 @Sendable，累计器本身
/// 需保证线程安全。每次 `add` 累计字节数，超限时抛 `backupTooLarge` 阻止
/// 生成超 ZIP32 4GB 地址范围的不可恢复备份。
final class ExportSizeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var _total = 0
    private let maxBytes: Int

    init(maxBytes: Int) { self.maxBytes = maxBytes }

    func add(_ bytes: Int) throws {
        lock.lock()
        _total += bytes
        let total = _total
        lock.unlock()
        guard total <= maxBytes else {
            throw BackupServiceError.backupTooLarge
        }
    }
}

// MARK: - Snapshot 转换辅助

extension ZipBackupService {

    struct ResolvedAvatar {
        let fileName: String
        let sourcePath: String
    }

    static func resolveAvatar(
        for pet: Pet,
        fileExists: (String) -> Bool
    ) -> ResolvedAvatar? {
        guard !pet.avatarPath.isEmpty, fileExists(pet.avatarPath) else { return nil }
        let ext = fileExtension(for: pet.avatarPath)
        return ResolvedAvatar(fileName: "\(pet.id.uuidString).\(ext)", sourcePath: pet.avatarPath)
    }

    /// 校验外部备份中的文件名是否为安全的纯文件名（防路径穿越）。
    /// 合法文件名：非空、不含路径分隔符（`/` `\`）、非 `.` / `..`。
    /// photoFileName / avatarFileName 均由导出端生成（`{uuid}.{ext}`），
    /// 但恢复端面对的是外部文件，必须防御手写/篡改的备份包。
    static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty
            && !name.contains("/")
            && !name.contains("\\")
            && name != "."
            && name != ".."
    }

    static func snapshot(pet: Pet, avatarFileName: String?) -> PetSnapshot {
        PetSnapshot(
            id: pet.id,
            name: pet.name,
            species: Self.semanticSpecies(for: pet.species),
            breed: pet.breed,
            gender: Self.semanticGender(for: pet.gender),
            birthday: pet.birthday,
            adoptionDay: pet.adoptionDay,
            avatarFileName: avatarFileName,
            notes: pet.notes,
            photoCount: pet.photoCount,
            createdAt: pet.createdAt)
    }

    // MARK: - 枚举语义化（跨平台可读）

    /// 导出端：Species → 语义字符串（"cat" / "dog" / "unknown"）。
    static func semanticSpecies(for species: Species) -> String {
        switch species {
        case .unknown: return "unknown"
        case .cat: return "cat"
        case .dog: return "dog"
        }
    }

    /// 导出端：Gender → 语义字符串（"male" / "female" / "unknown"）。
    static func semanticGender(for gender: Gender) -> String {
        switch gender {
        case .unknown: return "unknown"
        case .male: return "male"
        case .female: return "female"
        }
    }

    /// 恢复端：语义字符串 → Species。
    /// 向后兼容：旧版备份包存数字字符串（"0"/"1"/"2"），自动回退解析。
    static func parseSpecies(_ raw: String) -> Species {
        switch raw.lowercased() {
        case "cat", "1": return .cat
        case "dog", "2": return .dog
        default: return .unknown   // "unknown" / "0" / 未知值
        }
    }

    /// 恢复端：语义字符串 → Gender。
    /// 向后兼容：旧版备份包存数字字符串（"0"/"1"/"2"），自动回退解析。
    static func parseGender(_ raw: String) -> Gender {
        switch raw.lowercased() {
        case "male", "1": return .male
        case "female", "2": return .female
        default: return .unknown   // "unknown" / "0" / 未知值
        }
    }

    static func snapshot(photo: Photo, petID: UUID?, fileName: String) -> PhotoSnapshot {
        PhotoSnapshot(
            id: photo.id,
            originalURI: photo.originalURI,
            petID: petID,
            takenAt: photo.takenAt,
            latitude: photo.latitude,
            longitude: photo.longitude,
            placeName: photo.placeName,
            note: photo.note,
            isFavorite: photo.isFavorite,
            eventNotify: photo.eventNotify,
            width: photo.width,
            height: photo.height,
            fileSize: photo.fileSize,
            category: photo.category,
            subCategory: photo.subCategory,
            phash: photo.phash,
            qualityScore: photo.qualityScore,
            photoFileName: fileName,
            createdAt: photo.createdAt,
            sharpness: photo.sharpness,
            duplicateOf: photo.duplicateOf,
            isBest: photo.isBest)
    }

    static func recreate(
        pet snap: PetSnapshot, sandboxDir: String,
        avatarOwnerByFileName: [String: UUID]
    ) -> Pet {
        let species = Self.parseSpecies(snap.species)
        let gender = Self.parseGender(snap.gender)
        let avatarPath: String
        // 只有头像首主宠物（owner == snap.id）才绑定头像路径；冲突的第二只宠物
        // avatarPath 为空，避免两宠物指向同一头像文件。
        if let avatarName = snap.avatarFileName,
           avatarOwnerByFileName[avatarName] == snap.id,
           Self.isSafeFileName(avatarName) {
            avatarPath = "\(sandboxDir)/\(avatarsDirName)/\(avatarName)"
        } else {
            avatarPath = ""
        }
        return Pet(
            id: snap.id,
            name: snap.name,
            species: species,
            breed: snap.breed,
            gender: gender,
            birthday: snap.birthday,
            adoptionDay: snap.adoptionDay,
            avatarPath: avatarPath,
            notes: snap.notes,
            featureData: nil,
            photoCount: snap.photoCount,
            createdAt: snap.createdAt,
            updatedAt: snap.createdAt)
    }

    static func recreate(
        photo snap: PhotoSnapshot, uri: String, pet: Pet?
    ) -> Photo {
        Photo(
            id: snap.id,
            uri: uri,
            originalURI: snap.originalURI,
            pet: pet,
            takenAt: snap.takenAt,
            latitude: snap.latitude,
            longitude: snap.longitude,
            placeName: snap.placeName,
            thumbnailPath: "",
            note: snap.note,
            isFavorite: snap.isFavorite,
            eventNotify: snap.eventNotify,
            width: snap.width,
            height: snap.height,
            fileSize: snap.fileSize,
            category: snap.category,
            subCategory: snap.subCategory,
            createdAt: snap.createdAt,
            phash: snap.phash,
            sharpness: snap.sharpness,
            qualityScore: snap.qualityScore,
            duplicateOf: snap.duplicateOf,
            isBest: snap.isBest)
    }

    static func fileExtension(for path: String) -> String {
        let ext = (path as NSString).pathExtension
        return ext.isEmpty ? "jpg" : ext.lowercased()
    }

    /// 取照片文件的真实大小（字节）：优先 stat 文件系统，失败时 fallback DB fileSize。
    /// 分卷决策与预估均基于此值，避免 DB fileSize 过期（0 或偏小）导致误判单卷。
    static func actualSize(for photo: Photo, fileStorage: any FileStorage) -> Int64 {
        if let size = fileStorage.fileSize(at: photo.uri), size > 0 {
            return size
        }
        return photo.fileSize
    }

    static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        // 包含时分秒，避免同一天多次导出覆盖同一文件名路径。
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
