//  MetricsRecorder —— 本地匿名指标计数器（ADR-0010 §3.4）。
//
//  V1 只记录本地匿名计数，不记录或上传照片内容、文本、宠物名称或照片标识。
//  用于衡量情感触点的消费量与转化漏斗：
//  scan_completed → first_bead_generated → memory_card_previewed →
//  export_started → paywall_shown → purchase_started → share_sheet_opened
//
//  实现为 UserDefaults 整数计数器，无联网、无 PII。
//  后续可按需扩展为导出 JSON 供用户主动分享给开发者（不做自动上传）。
//  DESIGN.md §4：纯计数逻辑 + UserDefaults IO，无 SwiftUI 依赖。

import Foundation

/// V1 匿名指标事件名（ADR-0010 §3.4）。
public enum MetricsEvent: String, CaseIterable, Sendable {
    case scanCompleted = "scan_completed"
    case firstBeadGenerated = "first_bead_generated"
    case memoryCardPreviewed = "memory_card_previewed"
    case growthComparePreviewed = "growth_compare_previewed"
    case exportStarted = "export_started"
    case exportCompleted = "export_completed"
    case paywallShown = "paywall_shown"
    case purchaseStarted = "purchase_started"
    case purchaseCompleted = "purchase_completed"
    case backupExportStarted = "backup_export_started"
    case shareSheetOpened = "share_sheet_opened"
}

/// 本地匿名指标记录器（单例语义，但可注入自定义 UserDefaults 便于测试）。
public struct MetricsRecorder: Sendable {

    private let defaults: UserDefaults

    /// 使用标准 UserDefaults。
    public init() {
        self.init(defaults: .standard)
    }

    /// 注入自定义 UserDefaults（测试用）。
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - 记录

    private static let prefix = "metrics."

    /// 递增指定事件的计数（+1）。
    public func record(_ event: MetricsEvent) {
        let key = Self.prefix + event.rawValue
        let current = defaults.integer(forKey: key)
        defaults.set(current + 1, forKey: key)
    }

    // MARK: - 读取

    /// 读取指定事件的累计计数。
    public func count(for event: MetricsEvent) -> Int {
        defaults.integer(forKey: Self.prefix + event.rawValue)
    }

    /// 导出全部指标为字典（供调试或用户主动分享；不含 PII）。
    public func snapshot() -> [String: Int] {
        var result: [String: Int] = [:]
        for event in MetricsEvent.allCases {
            let c = count(for: event)
            if c > 0 { result[event.rawValue] = c }
        }
        return result
    }

    // MARK: - 重置（测试/用户隐私清除）

    /// 清除全部指标计数。
    public func reset() {
        for event in MetricsEvent.allCases {
            defaults.removeObject(forKey: Self.prefix + event.rawValue)
        }
    }
}
