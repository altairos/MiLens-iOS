//  PrivacyNarrativeLogic —— 隐私叙事差异化纯逻辑
//
//  根据市场配置（MarketProfile.privacyNarrativeStrength）返回隐私承诺项列表。
//  GDPR 区（.strong）追加一条"无云端、不上传"的强化声明，
//  对应 Localization-Plan §4.3 德语区"Alle Fotos bleiben auf Ihrem Gerät.
//  Keine Cloud, kein Upload."的更具体措辞要求。
//
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖，可单测。

import Foundation

/// 隐私承诺项类型（差异化展示的枚举基础）。
/// View 层用 switch 映射到 String Catalog key（保持编译时 key 检查）。
enum PrivacyCommitKind: String, CaseIterable, Identifiable, Equatable {
    case ondevice
    case local
    case control
    /// GDPR 强化声明：仅在 privacyNarrativeStrength == .strong 时出现。
    case gdpr

    var id: String { rawValue }

    /// SF Symbol 图标名。
    var icon: String {
        switch self {
        case .ondevice: return "iphone"
        case .local:    return "cpu"
        case .control:  return "hand.raised"
        case .gdpr:     return "lock.shield"
        }
    }
}

enum PrivacyNarrativeLogic {

    /// 根据市场配置返回隐私承诺项列表。
    ///
    /// 标准市场展示 3 条承诺（设备留存 / 本地分析 / 用户控制）；
    /// GDPR 区（`.strong`）追加第 4 条强化声明，用更具体的措辞重申
    /// "无云端、不上传"（对应德/法语区用户对隐私透明度的更高期望）。
    ///
    /// - Parameter profile: 当前市场差异化配置（测试可注入固定 profile）。
    /// - Returns: 有序承诺项列表，用于 Settings → 数据与隐私 页面渲染。
    static func commitmentKinds(for profile: MarketProfile) -> [PrivacyCommitKind] {
        var kinds: [PrivacyCommitKind] = [.ondevice, .local, .control]
        if profile.privacyNarrativeStrength.isStrong {
            kinds.append(.gdpr)
        }
        return kinds
    }
}
