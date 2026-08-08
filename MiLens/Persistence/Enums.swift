//  宠物种类与性别枚举 —— 翻译自源端 models/Pet.ets（Species / Gender）。
//  SwiftData 以 Int rawValue 持久化，保持与源端数值稳定（0/1/2）。

import Foundation

/// 宠物种类（源端 Species）
enum Species: Int, Codable, CaseIterable {
    case unknown = 0
    case cat = 1
    case dog = 2
}

/// 宠物性别（源端 Gender）
enum Gender: Int, Codable, CaseIterable {
    case unknown = 0
    case male = 1
    case female = 2
}

/// 照片分类标记（对应源端 PhotoCategory，iOS 收敛为 V1 可靠维度）。
/// 默认 unknown；导入时标记 petPhoto（宠物照片）；编辑保存时由
/// MediaLifecycleService 标记 edited（档案「作品」分类来源）。
/// V1 不引入自动「幼年/玩耍/睡觉」等不可靠分类（UI-DESIGN.md §6.4）。
enum PhotoCategory: String, Codable {
    case unknown = "unknown"
    /// 宠物照片（ImportService 导入时设置，对应源端 PET_PHOTO 内容分类）。
    case petPhoto = "pet_photo"
    /// 编辑产物：图片编辑器保存过的照片（「作品」分类的可靠来源）。
    case edited = "edited"
}
