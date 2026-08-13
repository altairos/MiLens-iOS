import Foundation

// EditorFilterPresets —— 调色预设滤镜纯数据（iOS 端新增，源端 EditorAdjustController 仅滑块）。
//
// 预设滤镜本质 = 一组预设好的 EditorColorAdjustments 参数。应用时复用现有调色渲染管线
// （CIFilter 调色 + 锐化卷积），不新增任何渲染逻辑。本文件只做数据建模与精确匹配，
// 无 IO / 无 SwiftUI 依赖，可在 MiLensKit 单测覆盖。
//
// 设计要点：
// - 预设**不含锐化**（sharpness 恒为 0）：锐化是异步卷积较重，滤镜应即时点选；
//   锐化仍由手动滑块在 end/click 单独触发，保留源端 releaseSharpenBase 语义。
// - matchPresetFilter 用精确匹配（== EditorColorAdjustments）：用户手动微调任意字段后
//   参数偏离预设 → 返回 nil → UI 自动取消高亮，表示「自定义」。

/// 预设滤镜。对应一组预设好的调色参数 + 本地化名 key。
public struct PresetFilter: Equatable, Sendable, Identifiable {
    /// 稳定标识（高亮回算 / 缩略图缓存 key 用）。
    public let id: String
    /// 本地化 key（View 层用 String(localized:) 查 Localizable.xcstrings）。
    public let nameKey: String
    /// 预设调色参数（sharpness 恒为 0）。
    public let adjustments: EditorColorAdjustments

    public init(id: String, nameKey: String, adjustments: EditorColorAdjustments) {
        self.id = id
        self.nameKey = nameKey
        self.adjustments = adjustments
    }
}

/// 6 款精简预设滤镜（原图排首位）。参数为初稿，真机微调。
/// 值域对齐 EditorColorAdjustments（brightness/contrast/saturation/temperature ±100，sharpness 0..100）。
public let PRESET_FILTERS: [PresetFilter] = [
    PresetFilter(id: "original", nameKey: "editor.filter.original",
                 adjustments: EditorColorAdjustments()),
    PresetFilter(id: "vivid", nameKey: "editor.filter.vivid",
                 adjustments: EditorColorAdjustments(contrast: 20, saturation: 30)),
    PresetFilter(id: "warm", nameKey: "editor.filter.warm",
                 adjustments: EditorColorAdjustments(brightness: 10, saturation: 10, temperature: 35)),
    PresetFilter(id: "cool", nameKey: "editor.filter.cool",
                 adjustments: EditorColorAdjustments(contrast: 10, saturation: -10, temperature: -35)),
    PresetFilter(id: "soft", nameKey: "editor.filter.soft",
                 adjustments: EditorColorAdjustments(brightness: 15, contrast: -15)),
    PresetFilter(id: "mono", nameKey: "editor.filter.mono",
                 adjustments: EditorColorAdjustments(contrast: 10, saturation: -100)),
]

/// 原图预设（全 0 中性）。选它等价于重置调色。
public let ORIGINAL_PRESET_FILTER: PresetFilter = PRESET_FILTERS[0]

/// 精确匹配：参数全等某预设则返回，否则 nil。
/// 用于进入调色 / 撤销重做 / 手动改滑块后回算滤镜高亮（偏离预设 → nil → 不高亮）。
public func matchPresetFilter(_ adj: EditorColorAdjustments) -> PresetFilter? {
    return PRESET_FILTERS.first { $0.adjustments == adj }
}
