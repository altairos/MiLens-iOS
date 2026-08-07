import Foundation

// StylizedDraftOptions 类型 + DraftFeatureProtector + VirtualPaletteBuilder + StylizedDraftGenerator
// 批量翻译自源端的风格化底稿管线（VirtualPaletteBuilder 342行 + DraftFeatureProtector 300行 + StylizedDraftGenerator 374行）。

// MARK: - StylizedDraftOptions

public enum StylizedDraftStyleMode: String, Sendable {
    case faithful, illustration, badge, cute
}
public enum StylizedDraftAbstractionLevel: String, Sendable {
    case low, medium, high, extreme
}
public enum StylizedDraftBackgroundMode: String, Sendable {
    case keep, desaturate, blur, replacePlain = "replace_plain", empty
}

/// 风格化底稿生成选项。对应源端 `StylizedDraftOptions`。
public struct StylizedDraftOptions: Sendable {
    public var enabled: Bool
    public var styleMode: StylizedDraftStyleMode
    public var abstractionLevel: StylizedDraftAbstractionLevel
    public var virtualColorCount: Int
    public var subjectOnly: Bool
    public var neutralGuard: Bool
    public var highlightProtect: Bool
    public var preserveFaceFeatures: Bool
    public var preservePatternRegions: Bool
    public var backgroundMode: StylizedDraftBackgroundMode
    public var backgroundDesaturation: Double
    public var backgroundBlurRadius: Int
    public var vibranceBoost: Double
    public var saturationBoost: Double
    public var contrastBoost: Double
    public var brightnessBoost: Double
    public var warmthBoost: Double
    public var posterizeStrength: Double
    public var localContrastStrength: Double

    public init(enabled: Bool = false, styleMode: StylizedDraftStyleMode = .illustration,
                abstractionLevel: StylizedDraftAbstractionLevel = .medium,
                virtualColorCount: Int = 10, subjectOnly: Bool = true,
                neutralGuard: Bool = true, highlightProtect: Bool = true,
                preserveFaceFeatures: Bool = true, preservePatternRegions: Bool = true,
                backgroundMode: StylizedDraftBackgroundMode = .desaturate,
                backgroundDesaturation: Double = 0.25, backgroundBlurRadius: Int = 1,
                vibranceBoost: Double = 1.0, saturationBoost: Double = 1.0,
                contrastBoost: Double = 1.0, brightnessBoost: Double = 1.0,
                warmthBoost: Double = 0, posterizeStrength: Double = 0.45,
                localContrastStrength: Double = 0.12) {
        self.enabled = enabled; self.styleMode = styleMode
        self.abstractionLevel = abstractionLevel; self.virtualColorCount = virtualColorCount
        self.subjectOnly = subjectOnly; self.neutralGuard = neutralGuard
        self.highlightProtect = highlightProtect; self.preserveFaceFeatures = preserveFaceFeatures
        self.preservePatternRegions = preservePatternRegions; self.backgroundMode = backgroundMode
        self.backgroundDesaturation = backgroundDesaturation; self.backgroundBlurRadius = backgroundBlurRadius
        self.vibranceBoost = vibranceBoost; self.saturationBoost = saturationBoost
        self.contrastBoost = contrastBoost; self.brightnessBoost = brightnessBoost
        self.warmthBoost = warmthBoost; self.posterizeStrength = posterizeStrength
        self.localContrastStrength = localContrastStrength
    }
}
