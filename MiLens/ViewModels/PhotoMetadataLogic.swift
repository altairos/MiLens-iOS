//  PhotoMetadataLogic —— 照片元数据构造决策纯逻辑
//  （对应源端 viewmodels/PhotoMetadataViewModel.ets）。
//
//  EXIF 日期解析与兜底拍摄时间构造抽为纯函数，便于单测覆盖多格式与边界。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

enum PhotoMetadataLogic {

    /// EXIF 日期正则：支持 "YYYY:MM:DD HH:MM:SS" 与 "YYYY-MM-DD HH:MM:SS"。
    /// Regex 字面量：编译期常量、无内部可变状态，跨隔离共享安全；
    /// iOS SDK 未给 Regex 标注 Sendable，nonisolated(unsafe) 豁免 static let 的并发检查。
    nonisolated(unsafe) private static let exifDatePattern = #/(\d{4})[:\-](\d{2})[:\-](\d{2})\s+(\d{2}):(\d{2}):(\d{2})/#

    /// 解析 EXIF 日期字符串为 Date。
    /// 支持 "YYYY:MM:DD HH:MM:SS" 和 "YYYY-MM-DD HH:MM:SS" 格式；
    /// 其他格式尝试通用解析；失败返回 nil。
    static func parseExifDateString(_ dateStr: String) -> Date? {
        let cleaned = dateStr
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^["']|["']$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // EXIF 标准格式优先
        if let match = cleaned.firstMatch(of: exifDatePattern) {
            let comps = DateComponents(
                year: Int(match.1),
                month: Int(match.2),
                day: Int(match.3),
                hour: Int(match.4),
                minute: Int(match.5),
                second: Int(match.6)
            )
            if let date = Calendar(identifier: .gregorian).date(from: comps) {
                return date
            }
        }
        // 通用格式降级解析（ISO8601 / RFC3339 等）
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: cleaned) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: cleaned)
    }

    /// 构造兜底拍摄时间：优先用已有的 EXIF 日期，其次用文件修改时间（秒级），否则当前时间。
    /// - Parameters:
    ///   - existingTakenAt: 已从 EXIF 或其他来源获得的日期（非 nil 时直接返回）
    ///   - statMtime: 文件修改时间（秒级时间戳，0 表示无效）
    static func resolveFallbackTakenAt(existingTakenAt: Date?, statMtime: TimeInterval) -> Date {
        if let existing = existingTakenAt { return existing }
        if statMtime > 0 { return Date(timeIntervalSince1970: statMtime) }
        return Date()
    }
}
