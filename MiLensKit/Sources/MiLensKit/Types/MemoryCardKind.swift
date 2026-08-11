//  MemoryCardKind —— 情感卡片类型统一枚举（ADR-0010 §3.3 / §10.11）。
//
//  纯数据模型：把「纪念日 / 里程碑 / 成长对比 / 回忆册」等情感触点的卡片类型
//  收敛为单一枚举，统一入口文案、通知点击路由、Pro 门控与分享品类。
//  渲染层按内容分组件，不强行合一：单图走 PetCardArtwork，双图走 GrowthCompareArtwork，
//  长图走 TimelineExportCanvas（避免把三种内容结构硬塞进一个 View）。
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 SwiftUI 依赖。

import Foundation

/// 情感卡片类型标识（ADR-0010 §10.11）。
public enum MemoryCardKind: String, CaseIterable, Identifiable, Equatable, Sendable {
    /// 生日纪念卡（年度重复，复用 NotifyService 周年通知）。
    case birthday
    /// 领养日纪念卡（年度重复，复用 NotifyService 周年通知）。
    case adoptionDay
    /// 相处里程碑卡（来到家第 100/365/730/1000 天，MilestoneLogic 计算）。
    case milestone
    /// 成长对比卡（同一宠物早期与现在照片并排，GrowthCompareArtwork 渲染）。
    case growthCompare
    /// 月度精选（按月选代表照片形成小回顾，TimelineExportCanvas 长图）。
    case monthlyRecap
    /// 年度回忆册（一年照片+里程碑汇总，TimelineExportCanvas 长图）。
    case yearlyRecap

    public var id: String { rawValue }

    /// 类型显示名（简体中文，App 层用 String(localized:) 覆盖）。
    public var displayName: String {
        switch self {
        case .birthday:     return "生日纪念"
        case .adoptionDay:  return "领养纪念"
        case .milestone:    return "里程碑"
        case .growthCompare: return "成长对比"
        case .monthlyRecap: return "月度精选"
        case .yearlyRecap:  return "年度回忆"
        }
    }

    /// 本地化 key（App 层 Localizable.xcstrings 对应条目）。
    public var localizationKey: String {
        "memory.kind.\(rawValue)"
    }

    /// SF Symbol 图标（入口/通知占位）。
    public var systemImage: String {
        switch self {
        case .birthday:     return "birthday.cake"
        case .adoptionDay:  return "house.fill"
        case .milestone:    return "star.circle"
        case .growthCompare: return "arrow.left.arrow.right"
        case .monthlyRecap: return "calendar"
        case .yearlyRecap:  return "book.closed"
        }
    }

    /// 是否需要单张照片作为主体（纪念卡/里程碑卡复用 PetCardArtwork 单图排版）。
    /// growthCompare 需双图；monthlyRecap/yearlyRecap 为长图汇总。
    public var requiresSinglePhoto: Bool {
        switch self {
        case .birthday, .adoptionDay, .milestone:
            return true
        case .growthCompare, .monthlyRecap, .yearlyRecap:
            return false
        }
    }

    /// 单图卡片的默认模板（多图/长图种类返回 nil）。
    public var defaultTemplate: PetCardTemplate? {
        switch self {
        case .birthday, .adoptionDay:
            return .classic
        case .milestone:
            return .classic
        case .growthCompare, .monthlyRecap, .yearlyRecap:
            return nil
        }
    }
}

// MARK: - 通知路由辅助

public extension MemoryCardKind {

    /// 该类型是否由年度重复通知触发（生日/领养日每年同日）。
    /// 里程碑由 MilestoneLogic 按天数计算单次触发；回忆册由用户主动进入或年度触发。
    var isAnnuallyRecurring: Bool {
        switch self {
        case .birthday, .adoptionDay:
            return true
        case .milestone, .growthCompare, .monthlyRecap, .yearlyRecap:
            return false
        }
    }
}
