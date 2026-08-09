import Foundation

// DecorationCatalog — 编辑器装饰资源目录（相框 / 贴纸）。
//
// 源端鸿蒙编辑器规划了相框（frame）与贴纸（sticker）能力但未实施。
// EditorLayerModels.swift 已定义 EditorLayerType.frame / .sticker 枚举值，
// createImageLayer 工厂已支持创建对应图层。本文件定义资源目录数据模型
// 与 Pro 门控元数据，为 V1.x 的装饰素材面板预留接口。
//
// 序列化兼容：装饰图层复用现有 EditorLayerSnapshot（type 字段已支持 "frame"/"sticker"）。
// 素材文件路径写入 EditorLayer.resourcePath，渲染由 App 层 ViewModel 解码。
//
// ADR-0010 §4：isPremium 装饰项对免费用户可见但不可用，点击触发付费墙。

/// 装饰类别。对应 `EditorLayerType.frame` / `.sticker`。
public enum DecorationCategory: String, Sendable, CaseIterable {
    case frame
    case sticker
}

/// 装饰资源元数据。一个相框或一张贴纸的目录描述。
///
/// 素材文件本身不包含在此模型中——`resourcePath` 指向 Bundle 或按需下载的文件路径，
/// App 层在编辑器中解码为 CGImage/UIImage。
public struct DecorationItem: Identifiable, Equatable, Sendable {
    /// 唯一标识（如 "frame_polaroid_white"、"sticker_paw_print"）。
    public let id: String
    /// 显示名称（本地化 key 或直接文案）。
    public let name: String
    /// 类别（frame / sticker）。
    public let category: DecorationCategory
    /// 素材文件路径（Bundle 资源名或相对路径）。
    public let resourcePath: String
    /// 预览缩略图路径（面板列表展示用）。
    public let previewPath: String
    /// 是否为 Pro 专属装饰（免费用户可见但不可用 → 点击触发付费墙）。
    public let isPremium: Bool
    /// 分组标签（如「基础」「节日」「动物」），面板分组展示用。
    public let group: String
    /// 排序权重（升序）。
    public let sortOrder: Int

    public init(
        id: String, name: String, category: DecorationCategory,
        resourcePath: String, previewPath: String,
        isPremium: Bool = false, group: String = "基础", sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.resourcePath = resourcePath
        self.previewPath = previewPath
        self.isPremium = isPremium
        self.group = group
        self.sortOrder = sortOrder
    }

    /// 判断在给定 Pro 状态下是否可用。
    public func isUsable(isPro: Bool) -> Bool {
        isPro || !isPremium
    }
}

/// 装饰资源目录。管理全部可用装饰项的查询与过滤。
///
/// V1.x 的具体素材在 Assets.xcassets 或按需下载目录中维护；
/// 本目录是运行时查询入口，App 层注入数据源。
public struct DecorationCatalog: Sendable {
    /// 全部装饰项。
    public let items: [DecorationItem]

    public init(items: [DecorationItem]) {
        self.items = items
    }

    /// 按类别查询装饰项（按 sortOrder 升序）。
    public func items(for category: DecorationCategory) -> [DecorationItem] {
        items
            .filter { $0.category == category }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 按 id 查找装饰项。
    public func find(_ id: String) -> DecorationItem? {
        items.first { $0.id == id }
    }

    /// 按分组查询（面板分组展示用）。
    public func groups(for category: DecorationCategory) -> [String: [DecorationItem]] {
        Dictionary(grouping: items(for: category), by: { $0.group })
    }

    /// 当前 Pro 状态下可用的装饰项（过滤掉 isPremium 且非 Pro）。
    public func usableItems(for category: DecorationCategory, isPro: Bool) -> [DecorationItem] {
        items(for: category).filter { $0.isUsable(isPro: isPro) }
    }

    /// 空目录（V1.0 无素材时的占位）。
    public static let empty = DecorationCatalog(items: [])
}

// MARK: - 工厂扩展：从装饰项创建编辑器图层

/// 把装饰项转换为编辑器图层（对应源端 addDecorationLayer）。
/// App 层在 ViewModel 中调用：先查 DecorationItem → 再创建 EditorLayer → 加入 EditorDocument。
public func createDecorationLayer(
    from item: DecorationItem,
    canvasWidth: Double,
    canvasHeight: Double
) -> EditorLayer {
    // 相框默认铺满画布（zIndex 最底层），贴纸默认居中（zIndex 最顶层）。
    switch item.category {
    case .frame:
        return createImageLayer(
            type: .frame,
            width: canvasWidth,
            height: canvasHeight,
            resourcePath: item.resourcePath,
            x: 0, y: 0)
    case .sticker:
        // 贴纸默认尺寸为画布短边的 30%，居中放置
        let stickerSize = min(canvasWidth, canvasHeight) * 0.3
        let centerX = (canvasWidth - stickerSize) / 2
        let centerY = (canvasHeight - stickerSize) / 2
        return createImageLayer(
            type: .sticker,
            width: stickerSize,
            height: stickerSize,
            resourcePath: item.resourcePath,
            x: centerX, y: centerY)
    }
}
