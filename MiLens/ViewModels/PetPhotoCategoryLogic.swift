//  PetPhotoCategoryLogic —— 档案照片分类纯决策逻辑（UI-DESIGN.md §6.4）。
//
//  档案页照片区按可靠维度分段：全部照片 / 待整理 / 作品。
//  - 全部照片：当前宠物的全部照片；
//  - 作品：图片编辑器保存过的照片（Photo.category == "edited"，由
//    MediaLifecycleService.saveEditedPhoto 标记——V1 唯一可靠来源）；
//  - 待整理：尚未归属任何宠物的照片（pet == nil，相册「待整理」同源）。
//
//  V1 不引入「幼年/玩耍/睡觉」等自动分类（无可靠模型来源，诚实标注原则）。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

/// 档案照片分类维度（可靠来源优先，V1 固定三档）。
enum PetPhotoCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case edited = "edited"
    case unassigned = "unassigned"

    var id: String { rawValue }

    /// 分段标题（用户可见，简体中文）。
    var title: String {
        switch self {
        case .all: return "全部照片"
        case .edited: return "作品"
        case .unassigned: return "待整理"
        }
    }

    /// 档案页显示顺序（全部 → 待整理 → 作品，对应设计稿）。
    static let profileOrder: [PetPhotoCategory] = [.all, .unassigned, .edited]
}

enum PetPhotoCategoryLogic {

    /// 当前宠物照片按分类筛选。
    /// - Parameters:
    ///   - photos: 当前宠物照片集合（全部/作品用）。
    ///   - unassigned: 未归属照片集合（待整理用，由仓储 getUnassignedPhotos 提供）。
    ///   - category: 目标分类。
    /// - Returns: 按拍摄时间倒序（调用方已排序）过滤后的照片。
    static func filter(
        petPhotos: [Photo], unassigned: [Photo], category: PetPhotoCategory
    ) -> [Photo] {
        switch category {
        case .all:
            return petPhotos
        case .edited:
            return petPhotos.filter { $0.category == PhotoCategory.edited.rawValue }
        case .unassigned:
            return unassigned
        }
    }

    /// 分类照片数（chips 计数展示用）。
    static func count(
        petPhotos: [Photo], unassigned: [Photo], category: PetPhotoCategory
    ) -> Int {
        filter(petPhotos: petPhotos, unassigned: unassigned, category: category).count
    }

    /// 是否为「作品」照片（编辑产物标记，供网格角标等轻量展示）。
    static func isEditedPhoto(_ photo: Photo) -> Bool {
        photo.category == PhotoCategory.edited.rawValue
    }
}
