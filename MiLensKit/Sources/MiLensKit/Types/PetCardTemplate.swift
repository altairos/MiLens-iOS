//  PetCardTemplate —— 宠物卡片多模板定义（ADR-0010 §4）。
//
//  纯数据模型：定义模板枚举、元数据与 Pro 门控规则。
//  View 层（PetCardArtwork）根据 template 参数切换排版分支。
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 SwiftUI 依赖。

import Foundation

/// 宠物卡片模板标识（ADR-0010 §4.1）。
public enum PetCardTemplate: String, CaseIterable, Identifiable, Equatable, Sendable {
    /// 经典：全屏照片 + 底部暖黑渐变 + 左下衬线名字（免费默认）。
    case classic
    /// 拍立得：白边相框 + 底部手写体文案区（Pro）。
    case polaroid
    /// 杂志：照片偏上 + 大号 display 标题 + 细体副标题（Pro）。
    case magazine
    /// 极简：纯照片 + 右下角小字签名（Pro）。
    case minimal

    public var id: String { rawValue }

    /// 模板显示名（简体中文，App 层用 String(localized:) 覆盖）。
    public var displayName: String {
        switch self {
        case .classic:   return "经典"
        case .polaroid:  return "拍立得"
        case .magazine:  return "杂志"
        case .minimal:   return "极简"
        }
    }

    /// 本地化 key（App 层 Localizable.xcstrings 对应条目）。
    public var localizationKey: String {
        "petCard.template.\(rawValue)"
    }

    /// SF Symbol 预览图标（模板选择器缩略图占位，后续可换真实预览）。
    public var previewIcon: String {
        switch self {
        case .classic:   return "rectangle.stack"
        case .polaroid:  return "rectangle.dashed"
        case .magazine:  return "book"
        case .minimal:   return "rectangle"
        }
    }

    /// 是否为 Pro 专属模板（免费用户可见但不可用，点击触发付费墙）。
    public var isPremium: Bool {
        switch self {
        case .classic:   return false
        case .polaroid, .magazine, .minimal: return true
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
    static let freeDefault: PetCardTemplate = .classic

    /// 全部可选模板（用于模板选择器展示顺序）。
    static var allTemplates: [PetCardTemplate] {
        allCases
    }

    /// Pro 用户可用的全部模板。
    static var proTemplates: [PetCardTemplate] {
        allCases.filter { $0.isPremium }
    }

    /// 将模板回退到当前 Pro 状态下可用的模板。
    /// 免费用户传入 Pro 模板时回退到 `.classic`。
    static func resolve(_ template: PetCardTemplate, isPro: Bool) -> PetCardTemplate {
        template.isUsable(isPro: isPro) ? template : freeDefault
    }
}
