import Foundation

// EditorToolLogic — 编辑器工具切换、宽高比约束、文字图层默认值、
// 裁剪比例选择与裁剪框初始化、工具组双层状态等纯逻辑。
// 翻译自源端 entry/.../viewmodels/EditorToolViewModel.ets（263 行）。
//
// 设计要点：
// - 所有函数无 IO / 无 SwiftUI 依赖，可在宿主单测完整覆盖。
// - 常量（MIN/MAX_CANVAS_ASPECT_RATIO、PRESET_COLORS、CROP_RATIOS、DEFAULT_TEXT_*）
//   作为唯一事实来源，App 层 import 复用。
// - resolveToolToggle 把"点击当前激活工具→none"的决策脱离 inline 三元，
//   并附带 shouldInitCrop 指令位，避免调用方在切换后再次比较工具名。
//
// 架构差异：
// - 源端 EditorToolMode 为字符串联合类型；iOS 用 String enum（类型安全）。
// - 源端 CROP_RATIOS 为运行时可变数组（slice 返回副本）；iOS 用不可变 let，
//   cropRatioOptions 返回值类型数组副本（Swift 值语义天然满足）。

/// 编辑器工具模式。对应源端 `EditorToolMode`。
public enum EditorToolMode: String, Sendable, Equatable {
    case frame
    case text
    case sticker
    case bead
    case crop
    case rotate
    case adjust
    case flip
    case cutout
    case none
}

/// 编辑器工具组（双层状态：组 → 组内工具）。对应源端 `EditorToolGroup`。
public enum EditorToolGroup: String, Sendable, Equatable {
    case adjust
    case smart
    case decorate
    case create
    case none
}

// MARK: - 常量（唯一事实来源）

/// 画布宽高比下限。对应源端 `MIN_CANVAS_ASPECT_RATIO`。
public let MIN_CANVAS_ASPECT_RATIO: Double = 0.6
/// 画布宽高比上限。对应源端 `MAX_CANVAS_ASPECT_RATIO`。
public let MAX_CANVAS_ASPECT_RATIO: Double = 1.8

/// 文字图层默认字号。对应源端 `DEFAULT_TEXT_FONT_SIZE`。
public let DEFAULT_TEXT_FONT_SIZE: Double = 32
/// 文字图层默认颜色。对应源端 `DEFAULT_TEXT_COLOR`。
public let DEFAULT_TEXT_COLOR: String = "#FFFFFF"
/// 文字图层默认启用描边。对应源端 `DEFAULT_TEXT_STROKE_ENABLED`。
public let DEFAULT_TEXT_STROKE_ENABLED: Bool = true
/// 文字图层默认描边宽度。对应源端 `DEFAULT_TEXT_STROKE_WIDTH`。
public let DEFAULT_TEXT_STROKE_WIDTH: Double = 2
/// 文字图层禁用描边时的宽度。对应源端 `TEXT_STROKE_DISABLED_WIDTH`。
public let TEXT_STROKE_DISABLED_WIDTH: Double = 0
/// 裁剪框初始边距（相对画布尺寸的比例）。对应源端 `CROP_INIT_MARGIN`。
public let CROP_INIT_MARGIN: Double = 0.1

// MARK: - 裁剪比例 / 预设颜色

/// 裁剪比例选项。对应源端 `CropRatio`。value=nil 表示自由裁剪。
public struct EditorCropRatio: Equatable, Sendable {
    public let label: String
    public let value: Double?   // nil = free

    public init(label: String, value: Double?) {
        self.label = label
        self.value = value
    }
}

/// 全部裁剪比例选项。对应源端 `CROP_RATIOS`。
public let CROP_RATIOS: [EditorCropRatio] = [
    .init(label: "自由", value: nil),
    .init(label: "1:1", value: 1),
    .init(label: "4:3", value: 4.0 / 3.0),
    .init(label: "3:2", value: 3.0 / 2.0),
    .init(label: "16:9", value: 16.0 / 9.0),
]

/// 文字颜色预设。对应源端 `PRESET_COLORS`。
public let PRESET_COLORS: [String] = [
    "#FFFFFF", "#000000", "#E91E63",
    "#795548", "#607D8B",
]

// MARK: - 决策结果类型

/// 文字图层默认状态。对应源端 `TextLayerDefaults`。
public struct EditorTextLayerDefaults: Equatable, Sendable {
    public let fontSize: Double
    public let color: String
    public let strokeEnabled: Bool
    public let strokeWidth: Double
}

/// 初始裁剪框区域。对应源端 `CropInitRegion`。
public struct EditorCropInitRegion: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    /// 全零区域（无效画布时返回）。
    public static let zero = EditorCropInitRegion(x: 0, y: 0, w: 0, h: 0)
}

/// 工具切换决策。对应源端 `ToolToggleDecision`。
public struct EditorToolToggleDecision: Equatable, Sendable {
    /// 切换后的目标工具。
    public let newTool: EditorToolMode
    /// 进入 crop 工具时是否需要初始化裁剪框。
    public let shouldInitCrop: Bool
}

/// 组内工具项。对应源端 `GroupToolItem`。
public struct EditorGroupToolItem: Equatable, Sendable {
    public let label: String
    public let mode: EditorToolMode
}

/// 组切换决策。对应源端 `GroupToggleDecision`。
public struct EditorGroupToggleDecision: Equatable, Sendable {
    public let newGroup: EditorToolGroup
    public let newTool: EditorToolMode
}

// MARK: - 宽高比 / 文字图层纯函数

/// 把宽高比约束在 [MIN_CANVAS_ASPECT_RATIO, MAX_CANVAS_ASPECT_RATIO]。
/// 用于照片加载、裁剪确认、撤销/重做后的 photoAspectRatio 同步。
/// NaN/Infinity 一律回到 MIN。对应源端 `clampAspectRatio`。
public func clampAspectRatio(_ ratio: Double) -> Double {
    if !ratio.isFinite { return MIN_CANVAS_ASPECT_RATIO }
    return max(MIN_CANVAS_ASPECT_RATIO, min(MAX_CANVAS_ASPECT_RATIO, ratio))
}

/// 返回文字图层的默认状态。对应源端 `defaultTextLayerState`。
public func defaultTextLayerState() -> EditorTextLayerDefaults {
    return EditorTextLayerDefaults(
        fontSize: DEFAULT_TEXT_FONT_SIZE,
        color: DEFAULT_TEXT_COLOR,
        strokeEnabled: DEFAULT_TEXT_STROKE_ENABLED,
        strokeWidth: DEFAULT_TEXT_STROKE_WIDTH)
}

/// 根据是否启用描边计算 strokeWidth。对应源端 `resolveStrokeWidth`。
public func resolveStrokeWidth(_ strokeEnabled: Bool) -> Double {
    return strokeEnabled ? DEFAULT_TEXT_STROKE_WIDTH : TEXT_STROKE_DISABLED_WIDTH
}

// MARK: - 裁剪比例纯函数

/// 返回全部裁剪比例选项的副本。对应源端 `cropRatioOptions`。
public func cropRatioOptions() -> [EditorCropRatio] {
    return CROP_RATIOS
}

/// 返回裁剪比例 label 列表（用于面板渲染）。对应源端 `cropRatioLabels`。
public func cropRatioLabels() -> [String] {
    return CROP_RATIOS.map { $0.label }
}

/// 按索引获取裁剪比例值；越界时返回 nil（= 自由裁剪）。对应源端 `resolveCropRatioByIndex`。
public func resolveCropRatioByIndex(_ index: Int) -> Double? {
    if index < 0 || index >= CROP_RATIOS.count { return nil }
    return CROP_RATIOS[index].value
}

// MARK: - 工具切换纯函数

/// 工具切换决策：点击当前激活工具 → .none；点击其他 → 该工具。
/// 进入 crop 工具时附带 shouldInitCrop=true。对应源端 `resolveToolToggle`。
public func resolveToolToggle(currentTool: EditorToolMode, targetTool: EditorToolMode) -> EditorToolToggleDecision {
    let newTool: EditorToolMode = currentTool == targetTool ? .none : targetTool
    return EditorToolToggleDecision(newTool: newTool, shouldInitCrop: newTool == .crop)
}

/// 判断某个 tab 是否处于激活态。对应源端 `resolveToolTabActive`。
public func resolveToolTabActive(currentTool: EditorToolMode, mode: EditorToolMode) -> Bool {
    return currentTool == mode
}

/// 计算初始裁剪框：在 canvas 内缩进 CROP_INIT_MARGIN，按 ratio 适配。
/// ratio=nil 表示自由裁剪，使用最大可用尺寸。
/// canvas 非正尺寸时返回 zero region。对应源端 `computeCropInitRegion`。
public func computeCropInitRegion(canvasW: Double, canvasH: Double, ratio: Double?) -> EditorCropInitRegion {
    if !(canvasW > 0) || !(canvasH > 0) {
        return .zero
    }
    let maxW = canvasW * (1 - 2 * CROP_INIT_MARGIN)
    let maxH = canvasH * (1 - 2 * CROP_INIT_MARGIN)
    let cropW: Double
    let cropH: Double
    if let r = ratio {
        if maxW / maxH > r {
            cropH = maxH
            cropW = maxH * r
        } else {
            cropW = maxW
            cropH = maxW / r
        }
    } else {
        cropW = maxW
        cropH = maxH
    }
    return EditorCropInitRegion(
        x: (canvasW - cropW) / 2,
        y: (canvasH - cropH) / 2,
        w: cropW,
        h: cropH)
}

// MARK: - 工具组双层状态

private let GROUP_ADJUST_TOOLS: [EditorGroupToolItem] = [
    .init(label: "裁剪", mode: .crop),
    .init(label: "旋转", mode: .rotate),
    .init(label: "调色", mode: .adjust),
    .init(label: "翻转", mode: .flip),
]

private let GROUP_SMART_TOOLS: [EditorGroupToolItem] = [
    .init(label: "抠图", mode: .cutout),
]

private let GROUP_DECORATE_TOOLS: [EditorGroupToolItem] = [
    .init(label: "文字", mode: .text),
    .init(label: "贴纸", mode: .sticker),
    .init(label: "相框", mode: .frame),
]

private let GROUP_CREATE_TOOLS: [EditorGroupToolItem] = [
    .init(label: "拼豆", mode: .bead),
]

/// 工具→组映射。对应源端 `resolveToolGroup`。
public func resolveToolGroup(_ tool: EditorToolMode) -> EditorToolGroup {
    switch tool {
    case .crop, .rotate, .adjust, .flip: return .adjust
    case .text, .sticker, .frame: return .decorate
    case .bead: return .create
    case .cutout: return .smart
    case .none: return .none
    }
}

/// 组→组内工具列表（供组级面板渲染）。对应源端 `toolsInGroup`。
public func toolsInGroup(_ group: EditorToolGroup) -> [EditorGroupToolItem] {
    switch group {
    case .adjust: return GROUP_ADJUST_TOOLS
    case .smart: return GROUP_SMART_TOOLS
    case .decorate: return GROUP_DECORATE_TOOLS
    case .create: return GROUP_CREATE_TOOLS
    case .none: return []
    }
}

/// 组切换决策：点击当前组→none；点击其他→该组（工具重置为 none）。
/// 对应源端 `resolveGroupToggle`。
public func resolveGroupToggle(currentGroup: EditorToolGroup, targetGroup: EditorToolGroup) -> EditorGroupToggleDecision {
    if currentGroup == targetGroup {
        return EditorGroupToggleDecision(newGroup: .none, newTool: .none)
    }
    return EditorGroupToggleDecision(newGroup: targetGroup, newTool: .none)
}

/// 组标签是否高亮（组内任何工具激活时高亮）。对应源端 `isGroupTabActive`。
public func isGroupTabActive(currentTool: EditorToolMode, group: EditorToolGroup) -> Bool {
    if group == .none { return false }
    return resolveToolGroup(currentTool) == group
}
