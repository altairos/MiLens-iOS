import Foundation

/// MiLens Pro 在 V1 的唯一功能清单。
/// 该清单被路由门控、付费墙和设置页共同使用。
enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    case beadStudio
    case photoEditor

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .beadStudio: "paywall.benefit.export"
        case .photoEditor: "paywall.benefit.create"
        }
    }

    var systemImage: String {
        switch self {
        case .beadStudio: "square.grid.3x3"
        case .photoEditor: "slider.horizontal.3"
        }
    }
}
