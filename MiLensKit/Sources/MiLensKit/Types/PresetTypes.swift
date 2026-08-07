import Foundation

// 预设参数相关类型。翻译自源端 BeadTypes.ets 的预设子集，
// 供 BeadPresetResolver 使用。所有 mode 类型以 String 存储（对应源端 TS 字符串字面量）。

// MARK: - Mode 类型别名（对应源端 TS string literal types）

public typealias BeadMode = String
public typealias BeadBackgroundMode = String
public typealias BeadDithering = String
public typealias BeadOutlineDrawMode = String
public typealias BeadPreFilterMode = String
public typealias BeadEffectPresetId = String

/// 默认风格化底稿选项。对应源端 `DEFAULT_STYLIZED_DRAFT_OPTIONS`。
public let DEFAULT_STYLIZED_DRAFT_OPTIONS = StylizedDraftOptions()

// MARK: - 生成选项 / 预设

/// 用户侧完整生成参数。对应源端 `BeadGenerateOptions`。
public struct BeadGenerateOptions {
    public var targetWidth: Int
    public var targetHeight: Int
    public var maxColors: Int
    public var paletteId: String
    public var mode: BeadMode
    public var backgroundMode: BeadBackgroundMode
    public var outline: Bool
    public var dithering: BeadDithering
    public var denoise: Bool
    public var eyeEnhance: Bool
    public var preserveBrightness: Bool
    public var outlineStrength: Double
    public var saturationBoost: Double
    public var contrastBoost: Double
    public var shadowLift: Double
    public var cleanupSmallRegionMinSize: Int
    public var tinyColorUsageRatio: Double
    public var lightnessBucketCoverage: Double
    public var petFriendlyPenalty: Double
    public var outlineDrawMode: BeadOutlineDrawMode
    public var featureProtectionStrength: Double
    public var autoWhiteBalanceStrength: Double
    public var vibranceBoost: Double
    public var brightnessBoost: Double
    public var neutralGuardStrength: Double
    public var highlightProtectStrength: Double
    public var subjectLocalContrast: Double
    public var backgroundDesaturation: Double
    public var backgroundBlurStrength: Double
    public var stylizedDraft: StylizedDraftOptions?

    public init(targetWidth: Int, targetHeight: Int, maxColors: Int, paletteId: String,
                mode: BeadMode, backgroundMode: BeadBackgroundMode, outline: Bool,
                dithering: BeadDithering, denoise: Bool, eyeEnhance: Bool,
                preserveBrightness: Bool, outlineStrength: Double, saturationBoost: Double,
                contrastBoost: Double, shadowLift: Double, cleanupSmallRegionMinSize: Int,
                tinyColorUsageRatio: Double, lightnessBucketCoverage: Double,
                petFriendlyPenalty: Double, outlineDrawMode: BeadOutlineDrawMode,
                featureProtectionStrength: Double, autoWhiteBalanceStrength: Double,
                vibranceBoost: Double, brightnessBoost: Double, neutralGuardStrength: Double,
                highlightProtectStrength: Double, subjectLocalContrast: Double,
                backgroundDesaturation: Double, backgroundBlurStrength: Double,
                stylizedDraft: StylizedDraftOptions? = nil) {
        self.targetWidth = targetWidth; self.targetHeight = targetHeight
        self.maxColors = maxColors; self.paletteId = paletteId; self.mode = mode
        self.backgroundMode = backgroundMode; self.outline = outline; self.dithering = dithering
        self.denoise = denoise; self.eyeEnhance = eyeEnhance
        self.preserveBrightness = preserveBrightness; self.outlineStrength = outlineStrength
        self.saturationBoost = saturationBoost; self.contrastBoost = contrastBoost
        self.shadowLift = shadowLift; self.cleanupSmallRegionMinSize = cleanupSmallRegionMinSize
        self.tinyColorUsageRatio = tinyColorUsageRatio
        self.lightnessBucketCoverage = lightnessBucketCoverage
        self.petFriendlyPenalty = petFriendlyPenalty; self.outlineDrawMode = outlineDrawMode
        self.featureProtectionStrength = featureProtectionStrength
        self.autoWhiteBalanceStrength = autoWhiteBalanceStrength
        self.vibranceBoost = vibranceBoost; self.brightnessBoost = brightnessBoost
        self.neutralGuardStrength = neutralGuardStrength
        self.highlightProtectStrength = highlightProtectStrength
        self.subjectLocalContrast = subjectLocalContrast
        self.backgroundDesaturation = backgroundDesaturation
        self.backgroundBlurStrength = backgroundBlurStrength
        self.stylizedDraft = stylizedDraft
    }
}

/// 生成管线可执行预设参数。对应源端 `BeadGenerationPreset`。
public struct BeadGenerationPreset {
    public var paletteId: String
    public var maxColors: Int
    public var mode: BeadMode
    public var backgroundMode: BeadBackgroundMode
    public var outline: Bool
    public var dithering: BeadDithering
    public var denoise: Bool
    public var preserveBrightness: Bool
    public var useSubjectCutout: Bool
    public var outlineStrength: Double
    public var saturationBoost: Double
    public var contrastBoost: Double
    public var shadowLift: Double
    public var cleanupSmallRegionMinSize: Int
    public var tinyColorUsageRatio: Double
    public var lightnessBucketCoverage: Double
    public var petFriendlyPenalty: Double
    public var outlineDrawMode: BeadOutlineDrawMode
    public var featureProtectionStrength: Double
    public var autoWhiteBalanceStrength: Double
    public var vibranceBoost: Double
    public var brightnessBoost: Double
    public var neutralGuardStrength: Double
    public var highlightProtectStrength: Double
    public var subjectLocalContrast: Double
    public var backgroundDesaturation: Double
    public var backgroundBlurStrength: Double
    public var stylizedDraft: StylizedDraftOptions?

    public init(paletteId: String, maxColors: Int, mode: BeadMode,
                backgroundMode: BeadBackgroundMode, outline: Bool, dithering: BeadDithering,
                denoise: Bool, preserveBrightness: Bool, useSubjectCutout: Bool,
                outlineStrength: Double, saturationBoost: Double, contrastBoost: Double,
                shadowLift: Double, cleanupSmallRegionMinSize: Int,
                tinyColorUsageRatio: Double, lightnessBucketCoverage: Double,
                petFriendlyPenalty: Double, outlineDrawMode: BeadOutlineDrawMode,
                featureProtectionStrength: Double, autoWhiteBalanceStrength: Double,
                vibranceBoost: Double, brightnessBoost: Double,
                neutralGuardStrength: Double, highlightProtectStrength: Double,
                subjectLocalContrast: Double, backgroundDesaturation: Double,
                backgroundBlurStrength: Double,
                stylizedDraft: StylizedDraftOptions? = nil) {
        self.paletteId = paletteId; self.maxColors = maxColors; self.mode = mode
        self.backgroundMode = backgroundMode; self.outline = outline; self.dithering = dithering
        self.denoise = denoise; self.preserveBrightness = preserveBrightness
        self.useSubjectCutout = useSubjectCutout; self.outlineStrength = outlineStrength
        self.saturationBoost = saturationBoost; self.contrastBoost = contrastBoost
        self.shadowLift = shadowLift; self.cleanupSmallRegionMinSize = cleanupSmallRegionMinSize
        self.tinyColorUsageRatio = tinyColorUsageRatio
        self.lightnessBucketCoverage = lightnessBucketCoverage
        self.petFriendlyPenalty = petFriendlyPenalty; self.outlineDrawMode = outlineDrawMode
        self.featureProtectionStrength = featureProtectionStrength
        self.autoWhiteBalanceStrength = autoWhiteBalanceStrength
        self.vibranceBoost = vibranceBoost; self.brightnessBoost = brightnessBoost
        self.neutralGuardStrength = neutralGuardStrength
        self.highlightProtectStrength = highlightProtectStrength
        self.subjectLocalContrast = subjectLocalContrast
        self.backgroundDesaturation = backgroundDesaturation
        self.backgroundBlurStrength = backgroundBlurStrength
        self.stylizedDraft = stylizedDraft
    }
}

/// 风格层规则。对应源端 `BeadStyleRules`。
public struct BeadStyleRules {
    public var outlineMode: BeadOutlineDrawMode?
    public var backgroundStyle: BeadBackgroundMode?
    public var eyeHighlightStrength: Double?
    public var preFilterMode: BeadPreFilterMode?

    public init(outlineMode: BeadOutlineDrawMode? = nil, backgroundStyle: BeadBackgroundMode? = nil,
                eyeHighlightStrength: Double? = nil, preFilterMode: BeadPreFilterMode? = nil) {
        self.outlineMode = outlineMode; self.backgroundStyle = backgroundStyle
        self.eyeHighlightStrength = eyeHighlightStrength; self.preFilterMode = preFilterMode
    }
}

/// 用户高级设置覆盖项。对应源端 `BeadGenerationOverrides`。
public struct BeadGenerationOverrides {
    public var paletteId: String?
    public var maxColors: Int?
    public var dithering: BeadDithering?
    public var outline: Bool?
    public var denoise: Bool?
    public var useSubjectCutout: Bool?
    public var outlineStrength: Double?
    public var saturationBoost: Double?
    public var contrastBoost: Double?
    public var shadowLift: Double?
    public var cleanupSmallRegionMinSize: Int?
    public var tinyColorUsageRatio: Double?
    public var lightnessBucketCoverage: Double?
    public var petFriendlyPenalty: Double?
    public var outlineDrawMode: BeadOutlineDrawMode?
    public var featureProtectionStrength: Double?
    public var autoWhiteBalanceStrength: Double?
    public var vibranceBoost: Double?
    public var brightnessBoost: Double?
    public var neutralGuardStrength: Double?
    public var highlightProtectStrength: Double?
    public var subjectLocalContrast: Double?
    public var backgroundDesaturation: Double?
    public var backgroundBlurStrength: Double?
    public var stylizedDraft: StylizedDraftOptions?

    public init() {}
}

/// 保存作品时用于复现生成行为的配方。对应源端 `BeadGenerationRecipe`。
public struct BeadGenerationRecipe {
    public var presetId: BeadEffectPresetId
    public var presetVersion: Int
    public var resolvedOptions: BeadGenerationPreset
    public var algorithmVersion: String

    public init(presetId: BeadEffectPresetId, presetVersion: Int,
                resolvedOptions: BeadGenerationPreset, algorithmVersion: String) {
        self.presetId = presetId; self.presetVersion = presetVersion
        self.resolvedOptions = resolvedOptions; self.algorithmVersion = algorithmVersion
    }
}

/// UI 展示的版本化效果预设。对应源端 `BeadEffectPreset`。
public struct BeadEffectPreset {
    public var id: BeadEffectPresetId
    public var version: Int
    public var name: String
    public var description: String
    public var recommended: Bool
    public var recommendedSizes: [Int]
    public var generation: BeadGenerationPreset
    public var styleRules: BeadStyleRules?

    public init(id: BeadEffectPresetId, version: Int, name: String, description: String,
                recommended: Bool, recommendedSizes: [Int],
                generation: BeadGenerationPreset, styleRules: BeadStyleRules? = nil) {
        self.id = id; self.version = version; self.name = name; self.description = description
        self.recommended = recommended; self.recommendedSizes = recommendedSizes
        self.generation = generation; self.styleRules = styleRules
    }
}

/// resolve 返回值。对应源端 `ResolvedBeadGeneration`。
public struct ResolvedBeadGeneration {
    public var options: BeadGenerateOptions
    public var generation: BeadGenerationPreset
    public var recipe: BeadGenerationRecipe
    public var isAuto: Bool

    public init(options: BeadGenerateOptions, generation: BeadGenerationPreset,
                recipe: BeadGenerationRecipe, isAuto: Bool) {
        self.options = options; self.generation = generation
        self.recipe = recipe; self.isAuto = isAuto
    }
}

// MARK: - 颜色数量预设

/// 颜色数量预设值。对应源端 `BeadColorPresetValue`。
public struct BeadColorPresetValue {
    public var count: Int
    public var label: String
    public var description: String
    public var paletteId: String
    public var isAuto: Bool

    public init(count: Int, label: String, description: String, paletteId: String, isAuto: Bool) {
        self.count = count; self.label = label; self.description = description
        self.paletteId = paletteId; self.isAuto = isAuto
    }
}

/// 颜色数量预设映射。对应源端 `BEAD_COLOR_PRESETS`。
public let BEAD_COLOR_PRESETS: [String: BeadColorPresetValue] = [
    "simple":    BeadColorPresetValue(count: 12, label: "简单", description: "颜色少，适合新手", paletteId: "MARD_72", isAuto: false),
    "standard":  BeadColorPresetValue(count: 24, label: "标准", description: "细节和难度平衡", paletteId: "MARD_120", isAuto: false),
    "detailed":  BeadColorPresetValue(count: 40, label: "细腻", description: "更接近照片", paletteId: "MARD_144", isAuto: false),
    "realistic": BeadColorPresetValue(count: 60, label: "高还原", description: "颜色更多，适合打印图纸", paletteId: "MARD_221", isAuto: false),
    "auto":      BeadColorPresetValue(count: 24, label: "自动", description: "根据照片智能选择", paletteId: "MARD_291", isAuto: true),
]
