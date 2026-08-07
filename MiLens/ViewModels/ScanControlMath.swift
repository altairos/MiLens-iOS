//  ScanControlMath —— 扫描控制纯逻辑
//  （对应源端 viewmodels/ScanControlMath.ets）。
//
//  把扫描恢复断点、阈值解析、日期跳过等决策抽为纯函数，便于单测覆盖。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

enum ScanControlMath {

    // MARK: - 常量（对应源端 constants/AppConstants.ets）

    /// fallback 视觉匹配阈值（CLIP 推理失败时使用手工特征）
    static let fallbackVisualMatchThreshold: Double = 0.85

    /// CLIP 严格匹配阈值（对应源端 MATCH_THRESHOLDS.STRICT）
    static let strictMatchThreshold: Double = 0.82

    // MARK: - 日期过滤

    /// 判断照片是否因 dateAdded 过旧而应跳过（仅扫描新照片模式）。
    /// dateAdded 为秒级时间戳，afterTimestampMs 为毫秒级。
    static func shouldSkipByDateAdded(dateAdded: Double, afterTimestampMs: Double) -> Bool {
        guard afterTimestampMs > 0, dateAdded > 0 else { return false }
        let afterTimestampSec = (afterTimestampMs / 1000).rounded(.down)
        return dateAdded < afterTimestampSec
    }

    // MARK: - 匹配阈值解析

    /// 根据 matchRequired 标志解析匹配阈值。
    /// matchRequired=true → 放宽阈值（手工特征 fallback），否则用严格 CLIP 阈值。
    static func resolveMatchThreshold(matchRequired: Bool) -> Double {
        matchRequired ? fallbackVisualMatchThreshold : strictMatchThreshold
    }

    /// 根据 matchRequired 解析 embedding 类型标签（用于诊断日志）。
    static func resolveEmbeddingKind(matchRequired: Bool) -> String {
        matchRequired ? "fallback" : "clip"
    }

    // MARK: - 扫描恢复断点

    /// 恢复扫描时判断是否已跳过断点。
    /// - alreadyPast=true → 直接返回 true
    /// - alreadyPast=false 且当前 asset 正是断点 → true（本帧仍被跳过）
    /// - alreadyPast=false 且未到断点 → false
    static func updateResumePoint(assetUri: String, lastScannedUri: String, alreadyPast: Bool) -> Bool {
        if alreadyPast { return true }
        return assetUri == lastScannedUri
    }

    // MARK: - 缩略图路径

    /// 沙盒副本路径作为缩略图路径（1024px JPEG 足以用作列表缩略图）。
    static func resolveThumbnailPath(_ sandboxUri: String) -> String {
        sandboxUri
    }
}
