//  PetBusinessCardLogic —— 宠物名片卡纯决策逻辑（创作 Tab 新增项目）。
//
//  名片卡是信息导向的创作项目：身份信息（名字/物种/品种/年龄）+ 性格标签 +
//  一句话简介 + 主人称呼。照片为辅（头像位）。
//  与纪念卡（PetCardLogic，情感导向，重单张照片）并列。
//
//  纯函数：不依赖 Repository / SwiftData / SwiftUI。
//  宿主（BusinessCardView）负责 IO（选宠物、用户输入、Pro 门控、导出/分享）。
//  V1 草稿按 petID 缓存到 UserDefaults，不持久化到 SwiftData（避免 schema 迁移，
//  后续若需长期保存再评估独立扩展表）。
//  DESIGN.md §4：纯决策逻辑，无 IO / 无 SwiftUI 依赖。

import Foundation
#if canImport(UIKit) || canImport(AppKit)
// CFStringTransform 常量在 Apple 平台随 CoreFoundation 模块暴露，新工具链
// 不再经 Foundation 隐式可见，需显式导入（Linux 无此模块，条件编译跳过）
import CoreFoundation
#endif

// MARK: - 投影输入

/// 名片卡组装用的宠物输入（App 层从 Pet @Model 组装，脱离 SwiftData 依赖）。
public struct PetBusinessCardInput: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let speciesName: String
    public let breed: String
    public let genderName: String
    public let ageText: String
    public let avatarPath: String
    /// 生日（MILENS ID 的 MMDD 首选来源；缺省回退 profileCreatedAt）。
    public let birthday: Date?
    /// 建档日期（生日缺失时光 MILENS ID 的回退来源）。
    public let profileCreatedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String = "",
        speciesName: String = "",
        breed: String = "",
        genderName: String = "",
        ageText: String = "",
        avatarPath: String = "",
        birthday: Date? = nil,
        profileCreatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.speciesName = speciesName
        self.breed = breed
        self.genderName = genderName
        self.ageText = ageText
        self.avatarPath = avatarPath
        self.birthday = birthday
        self.profileCreatedAt = profileCreatedAt
    }
}

// MARK: - 名片卡数据

/// 名片卡完整数据（宿主据此渲染 BusinessCardArtwork）。
public struct PetBusinessCardData: Equatable, Sendable {
    public let petID: UUID
    public let name: String
    public let speciesName: String
    public let breed: String
    public let genderName: String
    public let ageText: String
    public let avatarPath: String
    /// 性格标签（已去重、已截断数量）。
    public let tags: [String]
    /// 一句话简介（已校验长度；名片「擅长」行）。
    public let tagline: String
    /// 主人称呼（如「照护人｜小橘妈妈」）。
    public let ownerName: String
    /// 身份行（物种 · 年龄 · 性别，Figma「身份」字段）。
    public let identityLine: String
    /// 档案编号（名字拼音首字母 + 生日 MMDD，如「XM—0521」；无法生成时为空串）。
    public let milensID: String
    /// 季节行（如「2026 · 夏」）。
    public let seasonLine: String
    /// 生成日期行（如「2026.08.14」，名片「拍摄时间」字段）。
    public let shotDateLine: String

    public init(
        petID: UUID,
        name: String,
        speciesName: String,
        breed: String,
        genderName: String,
        ageText: String,
        avatarPath: String,
        tags: [String],
        tagline: String,
        ownerName: String,
        identityLine: String = "",
        milensID: String = "",
        seasonLine: String = "",
        shotDateLine: String = ""
    ) {
        self.petID = petID
        self.name = name
        self.speciesName = speciesName
        self.breed = breed
        self.genderName = genderName
        self.ageText = ageText
        self.avatarPath = avatarPath
        self.tags = tags
        self.tagline = tagline
        self.ownerName = ownerName
        self.identityLine = identityLine
        self.milensID = milensID
        self.seasonLine = seasonLine
        self.shotDateLine = shotDateLine
    }
}

// MARK: - 决策逻辑

public enum PetBusinessCardLogic {

    // MARK: - 版式参数

    /// 导出画布尺寸（像素，16:10 横版名片卡，Figma 720×450 基准 × 2）。
    public static let exportWidth = 1440
    public static let exportHeight = 900

    // MARK: - 长度约束

    /// 一句话简介最大字数。
    public static let maxTaglineLength = 20
    /// 性格标签最大数量。
    public static let maxTagCount = 4
    /// 单个标签最大字数。
    public static let maxTagLength = 6
    /// 主人称呼最大字数。
    public static let maxOwnerNameLength = 12

    // MARK: - 预设标签

    /// 预设性格标签候选（用户可从中选择，也可自定义）。
    public static let availableTags: [String] = [
        "活泼", "黏人", "贪吃", "高冷", "好奇", "温顺",
        "调皮", "胆小", "爱睡", "话痨", "懂事", "傲娇",
    ]

    // MARK: - 校验

    /// 校验一句话简介长度（超长返回 false）。
    public static func validateTagline(_ tagline: String) -> Bool {
        tagline.count <= maxTaglineLength
    }

    /// 校验单个标签长度（先 trim 再判空与长度）。
    public static func validateTag(_ tag: String) -> Bool {
        let trimmed = tag.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.count <= maxTagLength
    }

    /// 校验主人称呼长度。
    public static func validateOwnerName(_ name: String) -> Bool {
        name.count <= maxOwnerNameLength
    }

    // MARK: - 标签处理

    /// 规范化标签列表：去空白、去重（保序）、过滤超长、截断数量。
    public static func normalizeTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespaces)
            guard validateTag(trimmed), !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
            if result.count >= maxTagCount { break }
        }
        return result
    }

    // MARK: - 数据组装

    /// 从宠物输入 + 用户输入组装名片卡数据。
    /// 自动规范化标签、截断超长字段，并派生身份/编号/季节/日期行。
    /// - Parameters:
    ///   - now: 生成时刻（季节行与日期行基准，注入保证可测）。
    ///   - calendar: 日历（默认 current）。
    public static func buildData(
        from pet: PetBusinessCardInput,
        tags: [String],
        tagline: String,
        ownerName: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PetBusinessCardData {
        PetBusinessCardData(
            petID: pet.id,
            name: pet.name,
            speciesName: pet.speciesName,
            breed: pet.breed,
            genderName: pet.genderName,
            ageText: pet.ageText,
            avatarPath: pet.avatarPath,
            tags: normalizeTags(tags),
            tagline: truncate(tagline, max: maxTaglineLength),
            ownerName: truncate(ownerName, max: maxOwnerNameLength),
            identityLine: identityLine(
                speciesName: pet.speciesName, ageText: pet.ageText, genderName: pet.genderName),
            milensID: milensID(
                name: pet.name, birthday: pet.birthday,
                fallbackDate: pet.profileCreatedAt ?? now, calendar: calendar),
            seasonLine: seasonLine(from: now, calendar: calendar),
            shotDateLine: shotDateLine(from: now, calendar: calendar)
        )
    }

    // MARK: - 副标题组装

    /// 物种·品种·性别·年龄 组合副标题（缺字段自动跳过分隔符）。
    public static func subtitleLine(
        speciesName: String, breed: String, genderName: String, ageText: String
    ) -> String {
        var parts: [String] = []
        if !speciesName.isEmpty { parts.append(speciesName) }
        if !breed.isEmpty { parts.append(breed) }
        if !genderName.isEmpty { parts.append(genderName) }
        if !ageText.isEmpty { parts.append(ageText) }
        return parts.joined(separator: " · ")
    }

    /// 身份行：物种 · 年龄 · 性别（Figma Namecard「身份」字段顺序；缺字段跳过分隔符）。
    public static func identityLine(
        speciesName: String, ageText: String, genderName: String
    ) -> String {
        var parts: [String] = []
        if !speciesName.isEmpty { parts.append(speciesName) }
        if !ageText.isEmpty { parts.append(ageText) }
        if !genderName.isEmpty { parts.append(genderName) }
        return parts.joined(separator: " · ")
    }

    /// 主人称呼行（空则返回空串；Figma「照护人｜」前缀）。
    public static func ownerLine(_ ownerName: String) -> String {
        ownerName.isEmpty ? "" : "照护人｜\(ownerName)"
    }

    // MARK: - 档案编号与时间行

    /// MILENS ID：名字拼音首字母（大写）+ 生日 MMDD，以「—」连接（如「XM—0521」）。
    /// 拼音经 CFStringTransform（MandarinLatin + 去声调）；
    /// 非中文名回退原名首字母；生日缺失回退 fallbackDate（建档日期）；
    /// 名字或日期均无法解析时返回空串（View 层空则不渲染该行）。
    public static func milensID(
        name: String, birthday: Date?, fallbackDate: Date?, calendar: Calendar = .current
    ) -> String {
        let initials = nameInitials(name)
        guard !initials.isEmpty, let date = birthday ?? fallbackDate else { return "" }
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(initials)—\(String(format: "%02d%02d", month, day))"
    }

    /// 季节行：「YYYY · 春/夏/秋/冬」（3-5 春、6-8 夏、9-11 秋、12-2 冬）。
    public static func seasonLine(from date: Date, calendar: Calendar = .current) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let season: String
        switch month {
        case 3...5: season = "春"
        case 6...8: season = "夏"
        case 9...11: season = "秋"
        default: season = "冬"
        }
        return "\(year) · \(season)"
    }

    /// 生成日期行：「YYYY.MM.DD」（名片「拍摄时间」字段）。
    public static func shotDateLine(from date: Date, calendar: Calendar = .current) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return String(format: "%04d.%02d.%02d", year, month, day)
    }

    // MARK: - 内部工具

    /// 按字符数截断（不按 UTF-16 单元，避免 emoji 误切）。
    private static func truncate(_ string: String, max length: Int) -> String {
        guard string.count > length else { return string }
        return String(string.prefix(length))
    }

    /// 名字首字母串：中文字符逐个转拼音取首字母（大写拼接，如「小满」→「XM」）；
    /// 无中文时回退首个字母字符的大写（如「Luna」→「L」）；无可用字符返回空串。
    private static func nameInitials(_ name: String) -> String {
        var cjkInitials = ""
        for character in name {
            if let initial = pinyinInitial(of: character) {
                cjkInitials.append(contentsOf: initial)
            }
        }
        if !cjkInitials.isEmpty { return cjkInitials }
        for character in name where character.isLetter {
            return character.uppercased()
        }
        return ""
    }

    /// 单个中文字符的拼音首字母（大写；非中文字符返回 nil）。
    /// CFStringTransform 仅 Apple 平台可用；Linux（WSL2 测试环境）无此 API，
    /// 返回 nil（nameInitials 随后走字母回退，CJK 拼音断言测试在 Linux 跳过）。
    private static func pinyinInitial(of character: Character) -> String? {
        guard let scalar = character.unicodeScalars.first, isCJKIdeograph(scalar) else { return nil }
        #if canImport(UIKit) || canImport(AppKit)
        let mutable = NSMutableString(string: String(character))
        CFStringTransform(mutable, nil, CFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, CFStringTransformStripDiacriticalMarks, false)
        for letter in String(mutable).lowercased() where letter.isLetter {
            return String(letter).uppercased()
        }
        return nil
        #else
        return nil
        #endif
    }

    /// 是否为 CJK 统一表意文字（基本区 + 扩展 A 区）。
    private static func isCJKIdeograph(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }
}
