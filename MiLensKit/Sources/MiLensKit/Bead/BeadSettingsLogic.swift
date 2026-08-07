import Foundation

// BeadSettingsLogic — 拼豆设置面板纯决策逻辑。
// 逐行翻译自源端 entry/.../viewmodels/BeadSettingsViewModel.ets。
// 从 BeadPatternPage 抽取的 preset 解析、settings 管理、summary 生成逻辑。

// MARK: - 设置状态

/// 拼豆设置面板的完整设置状态。对应源端 `BeadSettings`。
public struct BeadSettings: Equatable {
    public var styleKey: String
    public var sizeKey: String
    public var colorKey: String
    public var ditherKey: String
    public var outline: Bool
    public var denoise: Bool
    public var cutout: Bool
    public var abstractLevel: Double

    public init(styleKey: String, sizeKey: String, colorKey: String,
                ditherKey: String, outline: Bool, denoise: Bool,
                cutout: Bool, abstractLevel: Double) {
        self.styleKey = styleKey
        self.sizeKey = sizeKey
        self.colorKey = colorKey
        self.ditherKey = ditherKey
        self.outline = outline
        self.denoise = denoise
        self.cutout = cutout
        self.abstractLevel = abstractLevel
    }
}

// MARK: - 默认设置

/// 返回默认设置。对应源端 `defaultBeadSettings`。
public func defaultBeadSettings() -> BeadSettings {
    return BeadSettings(
        styleKey: "illustration_v1",
        sizeKey: "standard",
        colorKey: "standard",
        ditherKey: "none",
        outline: true,
        denoise: true,
        cutout: true,
        abstractLevel: 0.5
    )
}

// MARK: - 风格预设应用

/// 根据风格预设 key 推导出完整设置。对应源端 `applyStylePreset`。
/// 未知 key 回退到 illustration_v1 的字段值（BeadPresetResolver.getEffect 兜底）。
public func applyStylePreset(_ styleKey: String) -> BeadSettings {
    let effect = BeadPresetResolver.getEffect(styleKey)
    let size = effect.recommendedSizes.first ?? 29
    let sizeKey: String
    if size <= 15 { sizeKey = "mini" }
    else if size <= 29 { sizeKey = "standard" }
    else if size <= 52 { sizeKey = "large" }
    else { sizeKey = "jumbo" }

    let maxColors = effect.generation.maxColors
    let colorKey: String
    if maxColors <= 12 { colorKey = "simple" }
    else if maxColors <= 24 { colorKey = "standard" }
    else if maxColors <= 40 { colorKey = "detailed" }
    else { colorKey = "realistic" }

    return BeadSettings(
        styleKey: styleKey,
        sizeKey: sizeKey,
        colorKey: colorKey,
        ditherKey: effect.generation.dithering,
        outline: effect.generation.outline,
        denoise: effect.generation.denoise,
        cutout: effect.generation.useSubjectCutout,
        abstractLevel: 0.5
    )
}

// MARK: - 摘要生成

/// 构建设置摘要文案。对应源端 `buildSummary`。
/// 格式："{maxDim}x{maxDim} | {colorLabel} | {subjectMode}"。
public func buildSummary(_ settings: BeadSettings) -> String {
    let size = BEAD_SIZE_PRESETS[settings.sizeKey]?.maxDim ?? 29
    let colors = BEAD_COLOR_PRESETS[settings.colorKey]?.label ?? "standard"
    let subjectMode = settings.cutout ? "subject_only" : "with_background"
    return "\(size)x\(size) | \(colors) | \(subjectMode)"
}

// MARK: - 单元尺寸计算

/// 根据图纸宽度计算预览单元格尺寸（像素）。对应源端 `computeCellSize`。
/// 以 360px 宽度为基准，最小不低于 4px。
public func computeCellSize(patternWidth: Int) -> Int {
    let fitCell = 360 / patternWidth
    return max(4, fitCell)
}

// MARK: - 抽象级别解析

/// 将 0–1 的抽象级别数值映射为枚举。对应源端 `resolveAbstractionLevel`。
public func resolveAbstractionLevel(_ level: Double) -> StylizedDraftAbstractionLevel {
    let levels: [StylizedDraftAbstractionLevel] = [.low, .medium, .high, .extreme]
    let idx = Swift.min(3, Int(level * 4))
    return levels[idx]
}
