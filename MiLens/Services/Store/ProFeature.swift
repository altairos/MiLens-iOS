import Foundation

/// MiLens Pro 在 V1 的唯一功能清单。
/// 该清单被路由门控、付费墙和设置页共同使用。
enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    case petProfiles
    case photoStorage
    case beadGeneration
    case timeline
    case watermarkFreeExport
    case cardTemplates
    case timelineExport
    case offlineBackup
    case albumModes

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .petProfiles: "paywall.benefit.profiles"
        case .photoStorage: "paywall.benefit.photoStorage"
        case .beadGeneration: "paywall.benefit.beadQuota"
        case .timeline: "paywall.benefit.timeline"
        case .watermarkFreeExport: "paywall.benefit.watermarkFree"
        case .cardTemplates: "paywall.benefit.cardTemplates"
        case .timelineExport: "paywall.benefit.timelineExport"
        case .offlineBackup: "paywall.benefit.offlineBackup"
        case .albumModes: "paywall.benefit.albumModes"
        }
    }

    var systemImage: String {
        switch self {
        case .petProfiles: "pawprint.fill"
        case .photoStorage: "photo.stack"
        case .beadGeneration: "square.grid.3x3"
        case .timeline: "clock.arrow.circlepath"
        case .watermarkFreeExport: "checkmark.seal.fill"
        case .cardTemplates: "rectangle.stack"
        case .timelineExport: "square.and.arrow.up"
        case .offlineBackup: "externaldrive"
        case .albumModes: "book"
        }
    }
}
