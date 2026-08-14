//  BusinessCardTemplate —— 宠物名片卡模板定义（创作 Tab 新增项目）。
//
//  纯数据模型：名片卡是信息导向的创作项目（与纪念卡的情感导向并列），
//  模板服务于身份信息排版（头像 + 物种/品种 + 性格标签 + 一句话简介）。
//  View 层（BusinessCardArtwork）根据 template 参数切换排版分支。
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 SwiftUI 依赖。

import Foundation

/// 宠物名片卡模板标识（Figma「Namecard」四套方向，与 PetCardTemplate 同构）。
public enum BusinessCardTemplate: String, CaseIterable, Identifiable, Equatable, Sendable {
    /// 博物馆典藏：左侧竖裁照片 + 藏书脊分隔 + 两段式字段 + 纸纤维/竹拓（免费默认）。
    case museum
    /// 私人装帧：铜红装订线 + 护页衬纸 + 内联字段（Pro）。
    case binding
    /// 现代画廊：黑场半调 + 满版照 + 朱砂导轨 + 铜底 ID Block（Pro）。
    case gallery
    /// 夜间暗房：安全灯 + 银盐 + 样片齿孔 + 曝光轨（Pro）。
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
        "businessCard.template.\(rawValue)"
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

public extension BusinessCardTemplate {

    /// 免费用户始终可用的默认模板。
    static let freeDefault: BusinessCardTemplate = .museum

    /// 全部可选模板（用于模板选择器展示顺序）。
    static var allTemplates: [BusinessCardTemplate] {
        allCases
    }

    /// Pro 用户可用的全部模板。
    static var proTemplates: [BusinessCardTemplate] {
        allCases.filter { $0.isPremium }
    }

    /// 将模板回退到当前 Pro 状态下可用的模板。
    /// 免费用户传入 Pro 模板时回退到 `.museum`。
    static func resolve(_ template: BusinessCardTemplate, isPro: Bool) -> BusinessCardTemplate {
        template.isUsable(isPro: isPro) ? template : freeDefault
    }
}
