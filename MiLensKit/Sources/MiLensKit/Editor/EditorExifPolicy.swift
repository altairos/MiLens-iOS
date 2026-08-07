import Foundation

// EditorExifPolicy — EXIF 元数据保存策略。
// 翻译自源端 entry/.../editor/ExifPolicy.ets（221 行）。
//
// 纯逻辑：不执行 IO，不依赖 ArkUI / ImageKit。接收 EXIF 快照 + 原图 URI，
// 输出结构化保存策略。日期/GPS 解析为可单测纯函数。

/// 从原图 ImageSource 读取的 EXIF 快照。对应源端 `ExifSnapshot`。
public struct EditorExifSnapshot: Equatable, Sendable {
    /// 原始拍摄时间（EXIF 格式 "YYYY:MM:DD HH:mm:ss" 或空）。
    public var takenAt: String
    /// 纬度（十进制度数，0 表示无 GPS）。
    public var latitude: Double
    /// 经度（十进制度数，0 表示无 GPS）。
    public var longitude: Double
    /// EXIF Orientation 1-8，0 表示未设置。
    public var orientation: Int
    /// 设备品牌（如 "Apple"），空表示无。
    public var make: String
    /// 设备型号（如 "iPhone 15 Pro"），空表示无。
    public var model: String

    public init(takenAt: String = "", latitude: Double = 0, longitude: Double = 0,
                orientation: Int = 0, make: String = "", model: String = "") {
        self.takenAt = takenAt; self.latitude = latitude; self.longitude = longitude
        self.orientation = orientation; self.make = make; self.model = model
    }
}

/// 空快照（表示原图无 EXIF 或读取失败）。对应源端 `emptyExifSnapshot`。
public func emptyExifSnapshot() -> EditorExifSnapshot {
    return EditorExifSnapshot()
}

/// EXIF 保存策略决策结果。对应源端 `ExifSavePolicy`。
public struct EditorExifSavePolicy: Equatable, Sendable {
    /// 是否保留原拍摄时间（true=有原图 EXIF 且非空，false=标记为新建创作）。
    public var preserveTakenAt: Bool
    /// 写入 Photo.takenAt 的值（ISO8601 格式）。
    public var resolvedTakenAt: String
    /// 写入 Photo.latitude 的值（原图 GPS，无则为 0）。
    public var resolvedLatitude: Double
    /// 写入 Photo.longitude 的值（原图 GPS，无则为 0）。
    public var resolvedLongitude: Double
    /// 写入 Photo.note 的值。
    public var resolvedNote: String
    /// 写入 Photo.originalUri 的值（原图 URI，空表示无原图）。
    public var resolvedOriginalUri: String
    /// 源 EXIF 是否包含有效拍摄时间（诊断标志，供 UI 显示来源）。
    public var hasOriginalExif: Bool

    public init(preserveTakenAt: Bool, resolvedTakenAt: String, resolvedLatitude: Double,
                resolvedLongitude: Double, resolvedNote: String, resolvedOriginalUri: String,
                hasOriginalExif: Bool) {
        self.preserveTakenAt = preserveTakenAt; self.resolvedTakenAt = resolvedTakenAt
        self.resolvedLatitude = resolvedLatitude; self.resolvedLongitude = resolvedLongitude
        self.resolvedNote = resolvedNote; self.resolvedOriginalUri = resolvedOriginalUri
        self.hasOriginalExif = hasOriginalExif
    }
}

// MARK: - 保存策略

/// 编辑后的"编辑副本" note 标记。对应源端 `EDIT_COPY_NOTE`。
public let EDIT_COPY_NOTE: String = "编辑副本"

/// 编辑/创作图片的"新建创作" note 标记。对应源端 `NEW_CREATION_NOTE`。
public let NEW_CREATION_NOTE: String = "编辑/创作图片"

/// 根据原图 EXIF 快照和编辑参数，决定保存策略。对应源端 `resolveExifPolicy`。
///
/// - 有原图 EXIF takenAt 非空 → preserveTakenAt=true
/// - 无原图 EXIF 或 originalUri 为空 → 标记为新建创作，takenAt=nowIso
/// - GPS 坐标始终透传（无则为 0）
/// - note 始终为空串（note 字段留给用户手动备注）
public func resolveExifPolicy(
    snapshot: EditorExifSnapshot, originalUri: String, nowIso: String
) -> EditorExifSavePolicy {
    let hasOriginalExif = !snapshot.takenAt.isEmpty
    let hasOriginalUri = !originalUri.isEmpty
    // 必须同时有原图 URI，即使 EXIF 非空才认为是编辑副本
    let preserveTakenAt = hasOriginalExif && hasOriginalUri

    let resolvedTakenAt = preserveTakenAt
        ? (normalizeExifDate(snapshot.takenAt).isEmpty ? nowIso : normalizeExifDate(snapshot.takenAt))
        : nowIso

    return EditorExifSavePolicy(
        preserveTakenAt: preserveTakenAt,
        resolvedTakenAt: resolvedTakenAt,
        resolvedLatitude: snapshot.latitude,
        resolvedLongitude: snapshot.longitude,
        resolvedNote: "",
        resolvedOriginalUri: originalUri,
        hasOriginalExif: hasOriginalExif)
}

// MARK: - 日期 / GPS 解析

/// 将 EXIF 日期字符串规范为 ISO8601。对应源端 `normalizeExifDate`。
///
/// EXIF DATE_TIME_ORIGINAL 格式 "2026:07:20 14:30:00" → "2026-07-20T14:30:00.000Z"。
/// 非法字符串返回空串。
public func normalizeExifDate(_ exifDate: String) -> String {
    let trimmed = exifDate.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return "" }
    // "YYYY:MM:DD HH:mm:ss" → "YYYY-MM-DDTHH:mm:ss"
    let pattern = #"^(\d{4}):(\d{2}):(\d{2})\s"#
    var normalized = trimmed
    if let regex = try? NSRegularExpression(pattern: pattern) {
        let range = NSRange(normalized.startIndex..., in: normalized)
        normalized = regex.stringByReplacingMatches(in: normalized, range: range,
                                                      withTemplate: "$1-$2-$3T")
    }

    let parseFormatter = DateFormatter()
    parseFormatter.locale = Locale(identifier: "en_US_POSIX")
    parseFormatter.timeZone = TimeZone(identifier: "UTC")
    parseFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    guard let date = parseFormatter.date(from: normalized) else { return "" }

    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return isoFormatter.string(from: date)
}

/// 解析 EXIF GPS Rational 字符串为十进制度数。对应源端 `parseExifGps`。
///
/// EXIF GPS 格式如 "40/1 42/1 5110/1000" 表示 40 度 42 分 5.110 秒。
/// ref 为 "N"/"S" 或 "E"/"W"。解析失败返回 0。
public func parseExifGps(rational: String, ref: String) -> Double {
    let trimmed = rational.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return 0 }
    let parts = trimmed.split(separator: " ").map(String.init)
    if parts.count < 3 { return 0 }

    guard let degrees = parseRational(parts[0]),
          let minutes = parseRational(parts[1]),
          let seconds = parseRational(parts[2]) else { return 0 }

    var decimal = degrees + minutes / 60 + seconds / 3600
    let refUpper = ref.trimmingCharacters(in: .whitespaces).uppercased()
    if refUpper == "S" || refUpper == "W" {
        decimal = -decimal
    }
    return decimal
}

/// 解析 EXIF Rational 字符串（如 "40/1" 或 "5110/1000"）为浮点数。对应源端 `parseRational`。
/// 纯数字字符串（如 "40"）直接解析。解析失败返回 nil。
private func parseRational(_ str: String) -> Double? {
    let trimmed = str.trimmingCharacters(in: .whitespaces)
    if let slashIdx = trimmed.firstIndex(of: "/") {
        let numeratorStr = String(trimmed[trimmed.startIndex..<slashIdx])
        let denominatorStr = String(trimmed[trimmed.index(after: slashIdx)...])
        guard let numerator = Double(numeratorStr), let denominator = Double(denominatorStr),
              denominator != 0 else { return nil }
        return numerator / denominator
    }
    return Double(trimmed)
}
