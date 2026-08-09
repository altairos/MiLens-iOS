import Foundation

/// MiLens Pro 在 V1 的唯一功能清单。
/// 该清单被路由门控、付费墙和设置页共同使用。
enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    case petProfiles
    case beadGeneration
    case timeline

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .petProfiles: "paywall.benefit.profiles"
        case .beadGeneration: "paywall.benefit.beadQuota"
        case .timeline: "paywall.benefit.timeline"
        }
    }

    var systemImage: String {
        switch self {
        case .petProfiles: "pawprint.fill"
        case .beadGeneration: "square.grid.3x3"
        case .timeline: "clock.arrow.circlepath"
        }
    }
}
