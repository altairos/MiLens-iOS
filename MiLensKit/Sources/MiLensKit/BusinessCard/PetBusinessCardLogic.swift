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

    public init(
        id: UUID = UUID(),
        name: String = "",
        speciesName: String = "",
        breed: String = "",
        genderName: String = "",
        ageText: String = "",
        avatarPath: String = ""
    ) {
        self.id = id
        self.name = name
        self.speciesName = speciesName
        self.breed = breed
        self.genderName = genderName
        self.ageText = ageText
        self.avatarPath = avatarPath
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
    /// 一句话简介（已校验长度）。
    public let tagline: String
    /// 主人称呼（如「铲屎官：小橘妈妈」）。
    public let ownerName: String

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
        ownerName: String
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
    }
}

// MARK: - 决策逻辑

public enum PetBusinessCardLogic {

    // MARK: - 版式参数

    /// 导出画布尺寸（像素，3:4 竖版名片卡，适合社交分享）。
    public static let exportWidth = 1080
    public static let exportHeight = 1440

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
    /// 自动规范化标签、截断超长字段。
    public static func buildData(
        from pet: PetBusinessCardInput,
        tags: [String],
        tagline: String,
        ownerName: String
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
            ownerName: truncate(ownerName, max: maxOwnerNameLength)
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

    /// 主人称呼行（空则返回空串）。
    public static func ownerLine(_ ownerName: String) -> String {
        ownerName.isEmpty ? "" : "铲屎官：\(ownerName)"
    }

    // MARK: - 内部工具

    /// 按字符数截断（不按 UTF-16 单元，避免 emoji 误切）。
    private static func truncate(_ string: String, max length: Int) -> String {
        guard string.count > length else { return string }
        return String(string.prefix(length))
    }
}
