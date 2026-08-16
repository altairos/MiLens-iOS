//  PetProfileLogic —— 宠物档案页面纯决策逻辑
//  （对应源端 viewmodels/PetProfileViewModel.ets）。
//
//  把 PetProfilePage 散落的决策下沉为可单测的纯函数：
//  物种 Emoji 映射、宠物名称校验、数量上限检查、彩蛋（同日生日）判定。
//
//  架构差异：源端 birthday 为 ISO 日期字符串（'2024-07-03'），用 substring 比较 MM-DD；
//  iOS Pet 存 Date?，故拆为 monthDayString(from:) 提取 + shouldShowEasterEgg(monthDay:) 比较，
//  避免 locale/时区字符串解析的脆弱性。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

// MARK: - 常量

enum PetProfileConstants {
    /// 开发者生日（MM-DD），用于彩蛋判定（对应源端 EASTER_EGG_BIRTHDAY）
    static let easterEggBirthdayMMdd = "07-03"
    /// 宠物数量上限（对应源端 checkPetCountLimit 默认阈值）
    static let maxPets = CommercialRules.proPetLimit
}

// MARK: - 纯决策函数

enum PetProfileLogic {

    // ─── 物种 Emoji ───

    /// 根据物种返回 Emoji 字符串（对应源端 getSpeciesEmoji）。
    static func speciesEmoji(_ species: Species) -> String {
        switch species {
        case .cat: return "\u{1F431}"   // 🐱
        case .dog: return "\u{1F436}"   // 🐶
        case .unknown: return "\u{1F43E}" // 🐾
        }
    }

    // ─── 校验 ───

    /// 校验新宠物名称。返回 nil 表示通过，否则返回错误文案（对应源端 validateNewPetName）。
    static func validateNewPetName(_ name: String, locale: Locale = .current) -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(localized: "pet.form.name.required", locale: locale)
        }
        return nil
    }

    /// 检查宠物数量是否已达上限（对应源端 checkPetCountLimit）。
    /// 返回 nil 表示通过，否则返回错误文案。
    static func checkPetCountLimit(currentCount: Int, maxPets: Int = PetProfileConstants.maxPets, locale: Locale = .current) -> String? {
        if currentCount >= maxPets {
            return String(localized: "pet.form.countLimit \(maxPets)", locale: locale)
        }
        return nil
    }

    // ─── 彩蛋（同日生日）───

    /// 从日期提取 "MM-DD" 字符串，用于彩蛋比较。nil 返回空串。
    /// 采用 Gregorian 日历保证跨 locale 一致（对应源端 substring(5,10) 的语义）。
    static func monthDayString(from date: Date?, calendar: Calendar = PetDateCalendar.gregorian) -> String {
        guard let date else { return "" }
        let comps = calendar.dateComponents([.month, .day], from: date)
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%02d-%02d", m, d)
    }

    /// 判断 "MM-DD" 字符串是否为彩蛋日期（对应源端 shouldShowEasterEgg）。
    /// 调用方先用 monthDayString(from:) 提取，再传入比较。
    static func shouldShowEasterEgg(monthDay: String) -> Bool {
        monthDay == PetProfileConstants.easterEggBirthdayMMdd
    }
}

// MARK: - 共享日历

/// 宠物日期计算的固定 Gregorian 日历（UTC），保证纯逻辑跨环境可复现。
enum PetDateCalendar {
    static let gregorian: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        // “UTC” 标识符解析失败时回退 .gmt（同为零偏移时区，语义等价）。
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return cal
    }()
}
