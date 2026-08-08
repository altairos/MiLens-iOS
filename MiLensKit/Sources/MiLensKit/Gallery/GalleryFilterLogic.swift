//  GalleryFilterLogic —— 相册宠物筛选 chip 与照片过滤纯决策逻辑。
//
//  UI-DESIGN.md §5.2：顶部悬浮胶囊（全部 / 各宠物），选中态品牌色填充。
//  源端 GalleryFilterPanel 宠物选项为「全部(-1) + 无归属(-2) + 各宠物」，
//  iOS 设计稿未含「无归属」chip，本逻辑按设计稿只生成「全部 + 各宠物」。
//
//  与 App 层 GalleryFilter.petID（nil = 全部）语义对齐，Mac 端桥接零映射；
//  筛选执行仍走现有 GalleryFilter + GalleryViewModel 状态机（计划 1.2）。
//
//  纯函数：输入照片投影（脱离 SwiftData @Model 以便测试）。
//  宿主（GalleryViewModel）负责 Repository 查询；View 只渲染。
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。

import Foundation

// MARK: - 投影类型

/// 筛选 chip 用的宠物投影。
public struct GalleryFilterPet: Equatable, Sendable {
    public let id: UUID
    /// 显示名（「小橘」「旺财」）。
    public let name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// 筛选 chip 展示模型（含选中态，View 只渲染）。
public struct GalleryPetChip: Equatable, Identifiable, Sendable {
    /// 稳定唯一键：`all` 或宠物 UUID 字符串。
    public let id: String
    /// 归属宠物；nil 表示「全部」chip。
    public let petID: UUID?
    /// 标题（「全部」或宠物名）。
    public let title: String
    /// 是否为当前选中态。
    public let isSelected: Bool
}

// MARK: - 决策函数

/// 相册宠物筛选。
public enum GalleryFilterLogic {
    /// 「全部」chip 的稳定 id。
    public static let allChipID = "all"

    /// 构建筛选 chip 列表：置顶「全部」，随后各宠物按输入顺序；标记选中态。
    ///
    /// - Parameters:
    ///   - pets: 全部宠物（通常来自宠物列表）
    ///   - selectedPetID: 当前选中的宠物 ID；nil 表示「全部」
    /// - Returns: chip 列表；选中态互斥（至多一个 isSelected = true）
    public static func buildChips(
        pets: [GalleryFilterPet],
        selectedPetID: UUID?
    ) -> [GalleryPetChip] {
        var chips: [GalleryPetChip] = [
            GalleryPetChip(id: allChipID, petID: nil, title: "全部", isSelected: selectedPetID == nil)
        ]
        for pet in pets {
            chips.append(GalleryPetChip(
                id: pet.id.uuidString,
                petID: pet.id,
                title: pet.name,
                isSelected: selectedPetID == pet.id
            ))
        }
        return chips
    }

    /// 按宠物筛选照片（与 GallerySectionLogic.groupPhotos 链式使用：先筛选后分组）。
    ///
    /// - Parameters:
    ///   - photos: 当前已加载照片
    ///   - petID: 选中的宠物 ID；nil 返回全部（保持输入顺序）
    /// - Returns: 筛选结果，保持输入顺序
    public static func filterPhotos(
        _ photos: [GalleryPhoto],
        petID: UUID?
    ) -> [GalleryPhoto] {
        guard let petID else { return photos }
        return photos.filter { $0.petID == petID }
    }
}
