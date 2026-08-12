//  PetCardLogic —— 宠物卡片纯决策逻辑（P4，创作 Tab「宠物卡片」项目）。
//
//  卡片 = 一张照片 + 宠物信息排版（UI-DESIGN.md §6.6：创作首页只展示 V1 可用项目）。
//  本模块负责全部文案组装与模板参数（尺寸/比例/字号档位），View 层只做渲染。
//  源端无对应功能（3D 手办 figure/ 不在 V1 范围），iOS 自研 MVP：单模板纪念卡。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation
import MiLensKit

/// 卡片文案与模板参数（Equatable/Sendable，供预览与导出共用）。
struct PetCardContent: Equatable, Sendable {
    /// 主标题（宠物名；无宠物时回退文案）
    var title: String
    /// 物种 Emoji（无宠物时用爪印）
    var emoji: String
    /// 副标题（物种 · 年龄；无宠物时固定文案）
    var subtitle: String
    /// 日期行（按相处时长选择陪伴文案；否则回退拍摄日期）
    var dateLine: String
}

enum PetCardLogic {

    // MARK: - 模板参数

    /// 导出画布尺寸（像素，4:5 竖版纪念卡）。
    static let exportSize = PetCardSize(width: 1080, height: 1350)
    /// 底部暖黑渐变占画布高度比例（照片之上叠字区的安全范围）。
    static let gradientHeightRatio = 0.42

    // MARK: - 文案组装

    /// 组装卡片文案。
    /// - Parameters:
    ///   - pet: 照片归属宠物（nil = 照片尚未归属，回退通用文案）。
    ///   - takenAt: 照片拍摄时间（决定日期行回退文案）。
    ///   - now: 当前时间（注入保证可测）。
    ///   - calendar: 日历（默认 current，与 PetDisplayLogic 一致）。
    ///   - locale: 文案语言（默认当前环境；测试传固定 locale）。
    static func content(
        pet: Pet?, takenAt: Date?, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current,
        kind: MemoryCardKind? = nil
    ) -> PetCardContent {
        guard let pet else {
            return PetCardContent(
                title: String(localized: "pet.card.fallbackTitle", locale: locale),
                emoji: "\u{1F43E}", // 🐾
                subtitle: String(localized: "pet.card.fallbackSubtitle", locale: locale),
                dateLine: dateLine(takenAt: takenAt, pet: nil, now: now, calendar: calendar, locale: locale,
                                   kind: kind)
            )
        }
        return PetCardContent(
            title: pet.name,
            emoji: PetProfileLogic.speciesEmoji(pet.species),
            subtitle: subtitle(for: pet, now: now, calendar: calendar, locale: locale),
            dateLine: dateLine(takenAt: takenAt, pet: pet, now: now, calendar: calendar, locale: locale,
                               kind: kind)
        )
    }

    /// 副标题：物种 · 年龄（年龄未知时只显示物种）。
    static func subtitle(
        for pet: Pet, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        let species = PetDisplayLogic.speciesDisplayName(pet.species, locale: locale)
        let age = PetDisplayLogic.ageText(from: pet.birthday, now: now, calendar: calendar, locale: locale)
        return pet.birthday == nil
            ? species
            : String(localized: "pet.card.subtitle \(species) \(age)", locale: locale)
    }

    /// 日期行：按 kind 优先级组装。
    /// - kind == .milestone 且有领养日 → 按相处时长选择里程碑文案
    /// - 有领养日 → 按相处时长选择陪伴文案
    /// - kind == .birthday 且有生日 → 「N 岁生日」
    /// - 否则拍摄日期
    static func dateLine(
        takenAt: Date?, pet: Pet?, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current,
        kind: MemoryCardKind? = nil
    ) -> String {
        // 里程碑优先：用 MiLensKit MilestoneLogic 文案（与通知同源）
        if kind == .milestone, let pet, let adoptionDay = pet.adoptionDay {
            return PetDisplayLogic.companionshipText(
                petName: pet.name, adoptionDay: adoptionDay, now: now, locale: locale)
        }
        // 生日纪念：显示「N 岁生日」
        if kind == .birthday, let pet, let birthday = pet.birthday {
            let years = max(0, calendar.dateComponents([.year], from: birthday, to: now).year ?? 0)
            return String(localized: "pet.card.birthdayYears \(years)", locale: locale)
        }
        // 领养日纪念（默认语义）
        if let pet, let adoptionDay = pet.adoptionDay {
            return PetDisplayLogic.companionshipText(
                petName: pet.name, adoptionDay: adoptionDay, now: now, locale: locale)
        }
        return PetDisplayLogic.dateText(takenAt, calendar: calendar)
    }
}

/// 画布尺寸（像素，Sendable）。
struct PetCardSize: Equatable, Sendable {
    let width: Int
    let height: Int
}
