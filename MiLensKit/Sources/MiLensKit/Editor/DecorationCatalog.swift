import Foundation

// DecorationCatalog — 编辑器装饰资源目录（相框 / 贴纸）。
//
// 源端鸿蒙编辑器规划了相框（frame）与贴纸（sticker）能力但未实施。
// EditorLayerModels.swift 已定义 EditorLayerType.frame / .sticker 枚举值，
// createImageLayer 工厂已支持创建对应图层。本文件定义资源目录数据模型、
// 相框自适应元数据（FrameFitMode）与 Pro 门控，为 V1.x 的装饰素材面板预留接口。
//
// 序列化兼容：装饰图层复用现有 EditorLayerSnapshot（type 字段已支持 "frame"/"sticker"）。
// 素材文件路径写入 EditorLayer.resourcePath，渲染由 App 层 ViewModel 解码。
//
// 相框自适应（FrameFitMode）：素材作者在 manifest 声明 fitMode（stretch/ninePatch/ratioSet），
// 导入工具（tools/frame_import.py）写入 catalog.json，运行时 App 层按模式绘制：
// - stretch：单块拉伸（角部变形，仅适合纯色边框）。
// - ninePatch：App 层 renderExport 调用 MiLensKit 的 computeNinePatchTiles 分 9 块绘制。
// - ratioSet：App 层 imageProvider 按 photoAspectRatio 在 supportedRatios 中选最优 PNG。
//
// ADR-0010 §4：isPremium 装饰项对免费用户可见但不可用，点击触发付费墙。

/// 装饰类别。对应 `EditorLayerType.frame` / `.sticker`。
public enum DecorationCategory: String, Sendable, CaseIterable, Codable {
    case frame
    case sticker
}

/// 分组稳定 ID 与展示顺序（开发计划 §5.1；阻塞项8：不再用中文字符串分组）。
/// UI 显示名映射 `decoration.group.*` 本地化 key；`recommended` 恒首位。
public enum DecorationGroupIds {
    /// frame 分组稳定 ID，按 UI 展示顺序声明。
    public static let frame: [String] = ["recommended", "film", "paper", "holiday"]
    /// sticker 分组稳定 ID，按 UI 展示顺序声明。
    public static let sticker: [String] = ["recommended", "paw", "daily", "memorial"]

    /// 给定类别的分组展示顺序（recommended 首位）。
    public static func orderedIds(for category: DecorationCategory) -> [String] {
        category == .frame ? frame : sticker
    }

    /// 分组 ID 是否为给定类别的合法 ID（导入工具 validate 复用）。
    public static func isKnownId(_ id: String, category: DecorationCategory) -> Bool {
        orderedIds(for: category).contains(id)
    }
}

/// 装饰资源元数据。一个相框或一张贴纸的目录描述。
///
/// 素材文件本身不包含在此模型中——`resourcePath` 指向 Bundle 资源名（Asset Catalog imageset 名），
/// App 层在编辑器中通过 UIImage(named:) 解码为 CGImage/UIImage。
/// catalog.json 由 tools/frame_import.py 从素材 manifest 合并生成（见 tools/frame_template/）。
public struct DecorationItem: Identifiable, Equatable, Sendable, Codable {
    /// 唯一标识（如 "frame_polaroid_white"、"sticker_paw_print"）。
    public let id: String
    /// 显示名称（本地化 key 或直接文案）。
    public let name: String
    /// 类别（frame / sticker）。
    public let category: DecorationCategory
    /// 素材文件路径（Asset Catalog imageset 名；ratioSet 模式下作为前缀，
    /// 实际文件名为 `"\(resourcePath)_\(ratio)"`，如 "frame_xxx_1x1"）。
    public let resourcePath: String
    /// 预览缩略图路径（面板列表展示用）。
    public let previewPath: String
    /// 是否为 Pro 专属装饰（免费用户可见但不可用 → 点击触发付费墙）。
    public let isPremium: Bool
    /// 分组稳定 ID（frame: recommended/film/paper/holiday；sticker: recommended/paw/daily/memorial）。
    /// 顺序见 DecorationGroupIds；UI 显示名映射 `decoration.group.*` 本地化 key。
    public let group: String
    /// 排序权重（升序）。
    public let sortOrder: Int

    // MARK: 相框自适应元数据（sticker 忽略，默认 stretch）

    /// 相框自适应模式（仅 frame 有效；sticker 固定 stretch）。
    public let fitMode: FrameFitMode
    /// 九宫格切图内边距（仅 fitMode == .ninePatch 时有效，源图像素空间）。
    public let ninePatchInsets: NinePatchInsets?
    /// 多比例素材支持的比例列表（仅 fitMode == .ratioSet 时有效，
    /// 如 ["1x1", "3x4", "4x3", "16x9", "9x16"]）。
    public let supportedRatios: [String]?
    /// 素材原始宽高比（width/height，面板预览排版用；可选）。
    public let nativeAspectRatio: Double?

    public init(
        id: String, name: String, category: DecorationCategory,
        resourcePath: String, previewPath: String,
        isPremium: Bool = false, group: String = "recommended", sortOrder: Int = 0,
        fitMode: FrameFitMode = .stretch,
        ninePatchInsets: NinePatchInsets? = nil,
        supportedRatios: [String]? = nil,
        nativeAspectRatio: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.resourcePath = resourcePath
        self.previewPath = previewPath
        self.isPremium = isPremium
        self.group = group
        self.sortOrder = sortOrder
        self.fitMode = category == .frame ? fitMode : .stretch
        self.ninePatchInsets = ninePatchInsets
        self.supportedRatios = supportedRatios
        self.nativeAspectRatio = nativeAspectRatio
    }

    /// 判断在给定 Pro 状态下是否可用。
    public func isUsable(isPro: Bool) -> Bool {
        isPro || !isPremium
    }
}

// MARK: - Codable 容错反序列化
//
// 自定义 init(from:) 覆盖编译器合成，两个目的：
// 1. 字段缺失时用默认值（V1.0 catalog.json 可能缺可选字段，decodeIfPresent 容错）；
// 2. 强制 sticker.fitMode = .stretch（贴纸是固定尺寸小图，不需九宫格/多比例）。
// encode(to:) 仍由编译器基于 CodingKeys 自动合成。
extension DecorationItem {
    private enum CodingKeys: String, CodingKey {
        case id, name, category, resourcePath, previewPath
        case isPremium, group, sortOrder
        case fitMode, ninePatchInsets, supportedRatios, nativeAspectRatio
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        let cat = try c.decode(DecorationCategory.self, forKey: .category)
        category = cat
        resourcePath = try c.decode(String.self, forKey: .resourcePath)
        previewPath = try c.decode(String.self, forKey: .previewPath)
        isPremium = try c.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? "recommended"
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        let declaredFit = try c.decodeIfPresent(FrameFitMode.self, forKey: .fitMode) ?? .stretch
        // sticker 强制 stretch（与自定义 init 一致，防 JSON 手写绕过）
        fitMode = cat == .frame ? declaredFit : .stretch
        ninePatchInsets = try c.decodeIfPresent(NinePatchInsets.self, forKey: .ninePatchInsets)
        supportedRatios = try c.decodeIfPresent([String].self, forKey: .supportedRatios)
        nativeAspectRatio = try c.decodeIfPresent(Double.self, forKey: .nativeAspectRatio)
    }
}

/// 装饰资源目录。管理全部可用装饰项的查询与过滤。
///
/// catalog.json（由 tools/frame_import.py 生成）位于 `MiLens/Resources/Decorations/`，
/// App 层启动时通过 DecorationCatalogLoader 解码本结构注入编辑器。
public struct DecorationCatalog: Sendable, Codable {
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

    /// 按分组查询（面板分组展示用）。返回稳定排序的 (id, items) 数组（阻塞项8）：
    /// 已知分组按 DecorationGroupIds 常量序（recommended 恒首位），组内按 sortOrder 升序；
    /// 未知分组按字母序追加（catalog 脏数据容错，不静默丢弃）。
    public func groups(for category: DecorationCategory) -> [(id: String, items: [DecorationItem])] {
        var grouped = Dictionary(grouping: items(for: category), by: { $0.group })
        var result: [(id: String, items: [DecorationItem])] = []
        for id in DecorationGroupIds.orderedIds(for: category) {
            guard let groupItems = grouped.removeValue(forKey: id) else { continue }
            result.append((id: id, items: groupItems))
        }
        for id in grouped.keys.sorted() {
            result.append((id: id, items: grouped[id] ?? []))
        }
        return result
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
///
/// 图层 x/y 为画布中心点坐标（阻塞项2 修正：编辑器坐标以图层中心为锚点）：
/// - frame：中心 = 画布中心，宽高 = 画布尺寸（铺满），rotation=0/scale=1/flip=false。
///   fitMode 不影响几何，只影响渲染方式（stretch 单块 / ninePatch 分块 / ratioSet 选图后单块）。
/// - sticker：基准视觉尺寸 = 画布短边 × 22%（按素材宽高比分配到 width/height，较大边 = 视觉尺寸）；
///   首个贴纸中心 = 画布中心向右上偏移 18% 短边，每多一个贴纸再偏 8% 短边，
///   偏移量按可用半径环形取模并 clamp 在画布内（落点避开画面中心主体，规格 §4.3）。
///
/// - Parameter stickerCount: 当前文档已有贴纸数量（堆叠落点偏移用，默认 0）。
public func createDecorationLayer(
    from item: DecorationItem,
    canvasWidth: Double,
    canvasHeight: Double,
    stickerCount: Int = 0
) -> EditorLayer {
    switch item.category {
    case .frame:
        // 相框铺满画布（zIndex 最底层），fitMode 不影响几何，只影响渲染分块。
        return createImageLayer(
            type: .frame,
            width: canvasWidth,
            height: canvasHeight,
            resourcePath: item.resourcePath,
            x: canvasWidth / 2, y: canvasHeight / 2)
    case .sticker:
        let short = min(canvasWidth, canvasHeight)
        let displaySize = short * 0.22
        // 按素材宽高比分配基准宽高（缺元数据或非法值时按正方形；视觉尺寸 = 较大边）。
        let ratio = item.nativeAspectRatio.flatMap { $0 > 0 ? $0 : nil } ?? 1
        let stickerW = ratio >= 1 ? displaySize : displaySize * ratio
        let stickerH = ratio >= 1 ? displaySize / ratio : displaySize
        // 中心落点：画布中心 + 右上对角偏移（18% + 8% × 已有贴纸数）× 短边，环形回归 + clamp 画布内。
        let offset = (0.18 + 0.08 * Double(max(0, stickerCount))) * short
        let availX = max(canvasWidth / 2 - stickerW / 2, 1)
        let availY = max(canvasHeight / 2 - stickerH / 2, 1)
        let ringX = offset.truncatingRemainder(dividingBy: availX)
        let ringY = offset.truncatingRemainder(dividingBy: availY)
        let x = min(max(canvasWidth / 2 + ringX, stickerW / 2), canvasWidth - stickerW / 2)
        let y = min(max(canvasHeight / 2 - ringY, stickerH / 2), canvasHeight - stickerH / 2)
        return createImageLayer(
            type: .sticker,
            width: stickerW,
            height: stickerH,
            resourcePath: item.resourcePath,
            x: x, y: y)
    }
}
