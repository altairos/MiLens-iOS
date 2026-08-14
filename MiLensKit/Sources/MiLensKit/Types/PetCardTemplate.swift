//  PetCardTemplate —— 宠物卡片多模板定义（ADR-0010 §4）。
//
//  纯数据模型：定义模板枚举、元数据与 Pro 门控规则。
//  View 层（PetCardArtwork）根据 template 参数切换排版分支。
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 SwiftUI 依赖。

import Foundation

/// 宠物卡片模板标识（ADR-0010 §4.1，Figma「Keepsake Cards · Premium Directions」四套方向）。
public enum PetCardTemplate: String, CaseIterable, Identifiable, Equatable, Sendable {
    /// 博物馆典藏：白底档案排版 + 朱砂藏印 + 纸纤维 + 竹枝墨拓（免费默认）。
    case museum
    /// 私人装帧：铜红藏书线 + 布纹 + 护页衬纸 + 压印（Pro）。
    case binding
    /// 现代画廊：满版照片 + 黑带丝网半调 + 朱砂导轨（Pro）。
    case gallery
    /// 夜间暗房：深底安全灯 + 银盐颗粒 + 胶片齿孔 + 曝光轨（Pro）。
    case darkroom

    public var id: String { rawValue }

    /// 模板显示名（简体中文直出，Figma 2026.08.14 方向命名）。
    public var displayName: String {
        switch self {
        case .museum:    return "博物馆典藏"
        case .binding:   return "私人装帧"
        case .gallery:   return "现代画廊"
        case .darkroom:  return "夜间暗房"
        }
    }

    /// 本地化 key（App 层 Localizable.xcstrings 对应条目）。
    public var localizationKey: String {
        "petCard.template.\(rawValue)"
    }

    /// SF Symbol 预览图标（模板选择器缩略图占位，后续可换真实预览）。
    public var previewIcon: String {
        switch self {
        case .museum:    return "building.columns"
        case .binding:   return "book.closed"
        case .gallery:   return "photo.artframe"
        case .darkroom:  return "camera.filters"
        }
    }

    /// 是否为 Pro 专属模板（免费用户可见但不可用，点击触发付费墙）。
    public var isPremium: Bool {
        switch self {
        case .museum:    return false
        case .binding, .gallery, .darkroom: return true
        }
    }

    /// 判断指定模板在给定 Pro 状态下是否可用。
    public func isUsable(isPro: Bool) -> Bool {
        !isPremium || isPro
    }
}

// MARK: - 门控规则

public extension PetCardTemplate {

    /// 免费用户始终可用的默认模板。
    static let freeDefault: PetCardTemplate = .museum

    /// 全部可选模板（用于模板选择器展示顺序）。
    static var allTemplates: [PetCardTemplate] {
        allCases
    }

    /// Pro 用户可用的全部模板。
    static var proTemplates: [PetCardTemplate] {
        allCases.filter { $0.isPremium }
    }

    /// 将模板回退到当前 Pro 状态下可用的模板。
    /// 免费用户传入 Pro 模板时回退到 `.museum`。
    static func resolve(_ template: PetCardTemplate, isPro: Bool) -> PetCardTemplate {
        template.isUsable(isPro: isPro) ? template : freeDefault
    }
}
