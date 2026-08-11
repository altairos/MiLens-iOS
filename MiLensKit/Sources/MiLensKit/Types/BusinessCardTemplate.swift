//  BusinessCardTemplate —— 宠物名片卡模板定义（创作 Tab 新增项目）。
//
//  纯数据模型：名片卡是信息导向的创作项目（与纪念卡的情感导向并列），
//  模板服务于身份信息排版（头像 + 物种/品种 + 性格标签 + 一句话简介）。
//  View 层（BusinessCardArtwork）根据 template 参数切换排版分支。
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 SwiftUI 依赖。

import Foundation

/// 宠物名片卡模板标识。
public enum BusinessCardTemplate: String, CaseIterable, Identifiable, Equatable, Sendable {
    /// 标准：居中头像 + 信息列 + 标签胶囊（免费默认）。
    case standard
    /// 优雅：衬线留白 + 大号名字 + 细信息（Pro）。
    case elegant
    /// 活泼：圆角彩底 + Emoji 装饰 + 标签网格（Pro）。
    case playful
    /// 极简：纯文字名片，无照片主体（Pro）。
    case minimal

    public var id: String { rawValue }

    /// 模板显示名（简体中文，App 层用 String(localized:) 覆盖）。
    public var displayName: String {
        switch self {
        case .standard: return "标准"
        case .elegant:  return "优雅"
        case .playful:  return "活泼"
        case .minimal:  return "极简"
        }
    }

    /// 本地化 key（App 层 Localizable.xcstrings 对应条目）。
    public var localizationKey: String {
        "businessCard.template.\(rawValue)"
    }

    /// SF Symbol 预览图标（模板选择器缩略图占位，后续可换真实预览）。
    public var previewIcon: String {
        switch self {
        case .standard: return "person.crop.circle"
        case .elegant:  return "rectangle.split.3x1"
        case .playful:  return "sparkles"
        case .minimal:  return "text.alignleft"
        }
    }

    /// 是否为 Pro 专属模板（免费用户可见但不可用，点击触发付费墙）。
    public var isPremium: Bool {
        switch self {
        case .standard: return false
        case .elegant, .playful, .minimal: return true
        }
    }

    /// 判断指定模板在给定 Pro 状态下是否可用。
    public func isUsable(isPro: Bool) -> Bool {
        !isPremium || isPro
    }
}

// MARK: - 门控规则

public extension BusinessCardTemplate {

    /// 免费用户始终可用的默认模板。
    static let freeDefault: BusinessCardTemplate = .standard

    /// 全部可选模板（用于模板选择器展示顺序）。
    static var allTemplates: [BusinessCardTemplate] {
        allCases
    }

    /// Pro 用户可用的全部模板。
    static var proTemplates: [BusinessCardTemplate] {
        allCases.filter { $0.isPremium }
    }

    /// 将模板回退到当前 Pro 状态下可用的模板。
    /// 免费用户传入 Pro 模板时回退到 `.standard`。
    static func resolve(_ template: BusinessCardTemplate, isPro: Bool) -> BusinessCardTemplate {
        template.isUsable(isPro: isPro) ? template : freeDefault
    }
}
