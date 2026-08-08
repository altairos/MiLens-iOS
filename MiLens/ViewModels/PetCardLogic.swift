//  PetCardLogic —— 宠物卡片纯决策逻辑（P4，创作 Tab「宠物卡片」项目）。
//
//  卡片 = 一张照片 + 宠物信息排版（UI-DESIGN.md §6.6：创作首页只展示 V1 可用项目）。
//  本模块负责全部文案组装与模板参数（尺寸/比例/字号档位），View 层只做渲染。
//  源端无对应功能（3D 手办 figure/ 不在 V1 范围），iOS 自研 MVP：单模板纪念卡。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

/// 卡片文案与模板参数（Equatable/Sendable，供预览与导出共用）。
struct PetCardContent: Equatable, Sendable {
    /// 主标题（宠物名；无宠物时回退文案）
    var title: String
    /// 物种 Emoji（无宠物时用爪印）
    var emoji: String
    /// 副标题（物种 · 年龄；无宠物时固定文案）
    var subtitle: String
    /// 日期行（领养纪念「来到家 N 天」优先；否则拍摄日期）
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
    static func content(
        pet: Pet?, takenAt: Date?, now: Date = Date(), calendar: Calendar = .current
    ) -> PetCardContent {
        guard let pet else {
            return PetCardContent(
                title: "这一天",
                emoji: "\u{1F43E}", // 🐾
                subtitle: "值得记住的一天",
                dateLine: dateLine(takenAt: takenAt, pet: nil, now: now, calendar: calendar)
            )
        }
        return PetCardContent(
            title: pet.name,
            emoji: PetProfileLogic.speciesEmoji(pet.species),
            subtitle: subtitle(for: pet, now: now, calendar: calendar),
            dateLine: dateLine(takenAt: takenAt, pet: pet, now: now, calendar: calendar)
        )
    }

    /// 副标题：物种 · 年龄（年龄未知时只显示物种）。
    static func subtitle(for pet: Pet, now: Date = Date(), calendar: Calendar = .current) -> String {
        let species = PetDisplayLogic.speciesDisplayName(pet.species)
        let age = PetDisplayLogic.ageText(from: pet.birthday, now: now, calendar: calendar)
        return age == "未知" ? species : "\(species) · \(age)"
    }

    /// 日期行：有领养日 → 「来到家 N 天」（纪念语义优先）；否则拍摄日期。
    static func dateLine(
        takenAt: Date?, pet: Pet?, now: Date = Date(), calendar: Calendar = .current
    ) -> String {
        if let pet, let adoptionDay = pet.adoptionDay {
            let days = PetDisplayLogic.daysTogether(from: adoptionDay, now: now)
            return "来到家 \(days) 天"
        }
        return PetDisplayLogic.dateText(takenAt, calendar: calendar)
    }
}

/// 画布尺寸（像素，Sendable）。
struct PetCardSize: Equatable, Sendable {
    let width: Int
    let height: Int
}
