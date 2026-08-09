//  GalleryMode —— 相簿浏览模式定义（ADR-0010 §9）。
//
//  纯数据模型：定义浏览模式枚举、元数据与 Pro 门控规则。
//  View 层（GalleryView）根据 mode 参数切换浏览模式分支。
//  V1 实现网格模式（当前默认），其他模式在 V1.x 实施。
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 SwiftUI 依赖。

import Foundation

/// Gallery 浏览模式标识（ADR-0010 §9.2）。
public enum GalleryMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    /// 网格：当前默认，按日期分组的瀑布流网格（免费默认）。
    case grid
    /// 剪贴簿：纸质背景 + 胶带贴图 + 手写日期标注 + 3D 翻页动画（Pro）。
    case scrapbook
    /// 拍立得散页：拍立得白边照片散落排列，点击翻转看背面信息（Pro）。
    case polaroidScatter
    /// 杂志画册：全屏照片 + 大留白 + 衬线页码 + 横向滑动翻页（Pro）。
    case magazine

    public var id: String { rawValue }

    /// 模式显示名（简体中文，App 层用 String(localized:) 覆盖）。
    public var displayName: String {
        switch self {
        case .grid:            return "网格"
        case .scrapbook:       return "剪贴簿"
        case .polaroidScatter: return "拍立得"
        case .magazine:        return "杂志"
        }
    }

    /// 本地化 key（App 层 Localizable.xcstrings 对应条目）。
    public var localizationKey: String {
        "gallery.mode.\(rawValue)"
    }

    /// SF Symbol 图标（模式切换器用）。
    public var systemImage: String {
        switch self {
        case .grid:            return "square.grid.2x2"
        case .scrapbook:       return "book"
        case .polaroidScatter: return "rectangle.on.rectangle.angled"
        case .magazine:        return "magazine"
        }
    }

    /// 是否为 Pro 专属模式（免费用户可见但不可用，点击触发付费墙）。
    public var isPremium: Bool {
        switch self {
        case .grid: return false
        case .scrapbook, .polaroidScatter, .magazine: return true
        }
    }

    /// 判断指定模式在给定 Pro 状态下是否可用。
    public func isUsable(isPro: Bool) -> Bool {
        !isPremium || isPro
    }
}

// MARK: - 门控规则

public extension GalleryMode {

    /// 免费用户始终可用的默认模式。
    static let freeDefault: GalleryMode = .grid

    /// 全部浏览模式（用于模式切换器展示顺序）。
    static var allModes: [GalleryMode] {
        allCases
    }

    /// Pro 用户可用的全部模式。
    static var premiumModes: [GalleryMode] {
        allCases.filter(\.isPremium)
    }

    /// 将模式回退到当前 Pro 状态下可用的模式。
    /// 免费用户传入 Pro 模式时回退到 `.grid`。
    static func resolve(_ mode: GalleryMode, isPro: Bool) -> GalleryMode {
        mode.isUsable(isPro: isPro) ? mode : freeDefault
    }
}
