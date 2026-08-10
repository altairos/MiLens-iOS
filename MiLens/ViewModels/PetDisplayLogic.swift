//  PetDisplayLogic —— 宠物档案显示格式化纯逻辑
//  （翻译源端 models/Pet.ets getSpeciesName/getGenderName/getAge/getDaysTogether
//   + utils/DateUtils.ets calcAge/calcDaysTogether）。
//
//  把 Pet 模型上散落的显示文案下沉为可单测的纯函数，避免 View 直接做日期运算。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

enum PetDisplayLogic {

    // ─── 物种 / 性别显示名 ───

    /// 物种显示名（对应源端 getSpeciesName；locale 默认当前环境，测试传固定 locale）。
    static func speciesDisplayName(_ species: Species, locale: Locale = .current) -> String {
        switch species {
        case .cat: return String(localized: "pet.species.cat", locale: locale)
        case .dog: return String(localized: "pet.species.dog", locale: locale)
        case .unknown: return String(localized: "pet.species.unknown", locale: locale)
        }
    }

    /// 性别显示名（对应源端 getGenderName；locale 默认当前环境）。
    static func genderDisplayName(_ gender: Gender, locale: Locale = .current) -> String {
        switch gender {
        case .male: return String(localized: "pet.gender.male", locale: locale)
        case .female: return String(localized: "pet.gender.female", locale: locale)
        case .unknown: return String(localized: "pet.gender.unknown", locale: locale)
        }
    }

    // ─── 年龄（对应源端 calcAge）───

    /// 格式化年龄文案。nil 生日返回「未知」。
    /// - Parameters:
    ///   - birthday: 生日；nil 返回「未知」。
    ///   - now: 当前时间（注入保证可测）。
    ///   - calendar: 日历（默认 current，与源端 new Date() 本地时区语义一致）。
    ///   - locale: 文案语言（默认当前环境；测试传固定 locale）。
    /// - Returns: "3岁"、"3岁2个月"、"8个月"、"0个月"、"未知"。
    static func ageText(
        from birthday: Date?, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        guard let birthday else { return String(localized: "pet.age.unknown", locale: locale) }
        let bc = calendar.dateComponents([.year, .month], from: birthday)
        let nc = calendar.dateComponents([.year, .month], from: now)
        let months = ((nc.year ?? 0) - (bc.year ?? 0)) * 12 + ((nc.month ?? 0) - (bc.month ?? 0))
        let years = months / 12
        let remainMonths = months % 12
        if years > 0 {
            // 年/月各为复数 key（pet.age.years/pet.age.months），中间用本地化连接符
            // （zh 空串 → "3岁2个月"；en 空格 → "3 years 2 months"）
            let yearsText = String(localized: "pet.age.years \(years)", locale: locale)
            if remainMonths > 0 {
                let monthsText = String(localized: "pet.age.months \(remainMonths)", locale: locale)
                return yearsText + String(localized: "pet.age.join", locale: locale) + monthsText
            }
            return yearsText
        }
        return String(localized: "pet.age.months \(remainMonths)", locale: locale)
    }

    // ─── 相处天数（对应源端 calcDaysTogether）───

    /// 计算从领养日到今天的天数。nil 返回 0。
    /// - Important: 与源端一致使用「截断除法」，未来日期返回负数。
    static func daysTogether(
        from adoptionDay: Date?, now: Date = Date()
    ) -> Int {
        guard let adoptionDay else { return 0 }
        let seconds = now.timeIntervalSince(adoptionDay)
        return Int(seconds / 86_400)
    }

    // ─── 日期格式化（供表单/详情页显示）───

    /// 将日期格式化为 "yyyy-MM-dd"（对应源端 ISO 日期字符串显示）。
    static func dateText(
        _ date: Date?, calendar: Calendar = PetDateCalendar.gregorian
    ) -> String {
        guard let date else { return "" }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
