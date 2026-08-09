import Foundation

// BeadPresetResolver — 预设参数解析器。
// 逐行翻译自源端 shared/.../bead/BeadPresetResolver.ets。

private let BEAD_ALGORITHM_VERSION = "bead_v10"

// MARK: - 生成预设工厂

/// 对应源端 `generation()` 辅助函数（27 个位置参数，preserveBrightness 恒为 true）。
private func generation(
    _ paletteId: String, _ maxColors: Int, _ mode: BeadMode,
    _ backgroundMode: BeadBackgroundMode, _ outline: Bool, _ dithering: BeadDithering,
    _ denoise: Bool, _ useSubjectCutout: Bool, _ outlineStrength: Double,
    _ saturationBoost: Double, _ contrastBoost: Double, _ shadowLift: Double,
    _ cleanupSmallRegionMinSize: Int, _ tinyColorUsageRatio: Double,
    _ lightnessBucketCoverage: Double, _ petFriendlyPenalty: Double,
    _ outlineDrawMode: BeadOutlineDrawMode, _ featureProtectionStrength: Double,
    _ autoWhiteBalanceStrength: Double, _ vibranceBoost: Double,
    _ brightnessBoost: Double, _ neutralGuardStrength: Double,
    _ highlightProtectStrength: Double, _ subjectLocalContrast: Double,
    _ backgroundDesaturation: Double, _ backgroundBlurStrength: Double
) -> BeadGenerationPreset {
    return BeadGenerationPreset(
        paletteId: paletteId, maxColors: maxColors, mode: mode,
        backgroundMode: backgroundMode, outline: outline, dithering: dithering,
        denoise: denoise, preserveBrightness: true, useSubjectCutout: useSubjectCutout,
        outlineStrength: outlineStrength, saturationBoost: saturationBoost,
        contrastBoost: contrastBoost, shadowLift: shadowLift,
        cleanupSmallRegionMinSize: cleanupSmallRegionMinSize,
        tinyColorUsageRatio: tinyColorUsageRatio,
        lightnessBucketCoverage: lightnessBucketCoverage,
        petFriendlyPenalty: petFriendlyPenalty, outlineDrawMode: outlineDrawMode,
        featureProtectionStrength: featureProtectionStrength,
        autoWhiteBalanceStrength: autoWhiteBalanceStrength,
        vibranceBoost: vibranceBoost, brightnessBoost: brightnessBoost,
        neutralGuardStrength: neutralGuardStrength,
        highlightProtectStrength: highlightProtectStrength,
        subjectLocalContrast: subjectLocalContrast,
        backgroundDesaturation: backgroundDesaturation,
        backgroundBlurStrength: backgroundBlurStrength
    )
}

// MARK: - 内置预设

/// 构造内置 5 个效果预设。对应源端 BEAD_EFFECT_PRESETS 初始值。
private func makeBuiltinEffectPresets() -> [BeadEffectPreset] {
    return [
        BeadEffectPreset(
            id: "illustration_v1", version: 1, name: "拼豆插画",
            description: "清爽、特征清楚，适合大多数照片",
            recommended: true, recommendedSizes: [58],
            generation: generation("MARD_120", 28, "free", "transparent", true, "none", true, true,
                                   0.70, 1.16, 1.12, 0.12, 3, 0.003, 0.9, 7, "dark", 0.8,
                                   0.65, 1.20, 1.03, 0.9, 0.85, 0.20, 0.35, 0.3),
            styleRules: BeadStyleRules(outlineMode: "dark", backgroundStyle: "transparent", preFilterMode: "vivid")
        ),
        BeadEffectPreset(
            id: "faithful_v1", version: 1, name: "写实还原",
            description: "保留更多毛色与细节，制作难度较高",
            recommended: false, recommendedSizes: [80],
            generation: generation("MARD_221", 60, "free", "transparent", false, "light", false, true,
                                   0.25, 1.06, 1.05, 0.06, 1, 0.001, 0.35, 0, "none", 0.4,
                                   0.35, 1.06, 1.01, 0.8, 0.9, 0.12, 0.85, 0.1),
            styleRules: BeadStyleRules(outlineMode: "none", backgroundStyle: "transparent", preFilterMode: "natural")
        ),
        BeadEffectPreset(
            id: "badge_v1", version: 1, name: "清晰徽章",
            description: "颜色少、色块大，使用圆形裁切，适合挂件和小图",
            recommended: false, recommendedSizes: [40],
            generation: generation("MARD_72", 16, "badge", "transparent", true, "none", true, true,
                                   0.55, 1.18, 1.15, 0.12, 3, 0.003, 0.8, 8, "outer_dark", 0.75,
                                   0.7, 1.18, 1.02, 0.9, 0.8, 0.18, 0, 0),
            styleRules: BeadStyleRules(outlineMode: "outer_dark", backgroundStyle: "transparent", preFilterMode: "badge_clear")
        ),
        BeadEffectPreset(
            id: "full_photo_v1", version: 1, name: "保留场景",
            description: "保留照片背景，适合有纪念意义的画面",
            recommended: false, recommendedSizes: [58],
            generation: generation("MARD_144", 40, "portrait", "light", true, "none", true, false,
                                   0.55, 1.10, 1.08, 0.08, 2, 0.002, 0.65, 2, "none", 0.5,
                                   0.3, 1.06, 1.01, 0.75, 0.85, 0.10, 0.90, 0.1),
            styleRules: BeadStyleRules(outlineMode: "none", backgroundStyle: "light", preFilterMode: "natural")
        ),
        BeadEffectPreset(
            id: "cute_v1", version: 2, name: "Q版可爱",
            description: "极简色块、高对比、清晰轮廓，像表情包一样可爱",
            recommended: false, recommendedSizes: [29, 58],
            generation: generation("MARD_72", 16, "tight_face", "transparent", true, "none", true, true,
                                   0.55, 1.22, 1.18, 0.15, 3, 0.004, 1.0, 10, "mixed", 0.72,
                                   0.55, 1.25, 1.06, 1.0, 0.9, 0.15, 0.30, 0.3),
            styleRules: BeadStyleRules(outlineMode: "mixed", backgroundStyle: "transparent", preFilterMode: "cute_bright")
        ),
    ]
}

/// 可变全局效果预设注册表。对应源端 `BEAD_EFFECT_PRESETS`。
/// 并发安全：所有读（含 public 属性访问）与写经 effectPresetsLock 串行化；
/// 锁内代码一律直接访问私有存储 `_effectPresets`（NSLock 不可重入，避免死锁）；
/// nonisolated(unsafe) 为锁保护的显式声明。
private let effectPresetsLock = NSLock()
private nonisolated(unsafe) var _effectPresets: [BeadEffectPreset] = makeBuiltinEffectPresets()

/// 公开只读访问（快照拷贝，锁保护；M3 复核加固——public 路径不再绕过锁）。
public var BEAD_EFFECT_PRESETS: [BeadEffectPreset] {
    get {
        effectPresetsLock.lock()
        defer { effectPresetsLock.unlock() }
        return _effectPresets
    }
    set {
        effectPresetsLock.lock()
        _effectPresets = newValue
        effectPresetsLock.unlock()
    }
}

// MARK: - 验证辅助

private func clampInteger(_ value: Double, _ min: Double, _ max: Double) -> Int {
    if !value.isFinite { return Int(min) }
    return Int(Swift.max(min, Swift.min(max, value.rounded())))
}

private func clampNumber(_ value: Double, _ min: Double, _ max: Double) -> Double {
    if !value.isFinite { return min }
    return Swift.max(min, Swift.min(max, value))
}

private func isMode(_ value: String) -> Bool {
    return value == "portrait" || value == "fullBody" || value == "free" ||
        value == "tight_face" || value == "badge"
}

private func isBackgroundMode(_ value: String) -> Bool {
    return value == "keep" || value == "remove" || value == "light" || value == "transparent"
}

private func isDithering(_ value: String) -> Bool {
    return value == "none" || value == "light" || value == "medium" || value == "adaptive"
}

private func isOutlineMode(_ value: String) -> Bool {
    return value == "none" || value == "dark" || value == "black" || value == "inner_dark" ||
        value == "outer_dark" || value == "outer_black" || value == "mixed"
}

private func isPreFilterMode(_ value: String) -> Bool {
    return value == "off" || value == "natural" || value == "vivid" ||
        value == "badge_clear" || value == "cute_bright"
}

private func isEffectId(_ value: String) -> Bool {
    return value == "illustration_v1" || value == "faithful_v1" || value == "badge_v1" ||
        value == "full_photo_v1" || value == "cute_v1"
}

private func isFiniteNumber(_ value: Double) -> Bool {
    return value.isFinite
}

private func isSupportedPalette(_ paletteId: String) -> Bool {
    return paletteId == "MARD_72" || paletteId == "MARD_120" || paletteId == "MARD_144" ||
        paletteId == "MARD_221" || paletteId == "MARD_291" ||
        paletteId == "MARD_PET_96" || paletteId == "MARD_PET_160"
}

private func validateStyleRules(_ rules: BeadStyleRules?) -> Bool {
    guard let rules else { return true }
    if let mode = rules.outlineMode, !isOutlineMode(mode) { return false }
    if let bg = rules.backgroundStyle, !isBackgroundMode(bg) { return false }
    if let strength = rules.eyeHighlightStrength,
       (!isFiniteNumber(strength) || strength < 0 || strength > 1) {
        return false
    }
    if let filter = rules.preFilterMode, !isPreFilterMode(filter) { return false }
    return true
}

private func validateGeneration(_ value: BeadGenerationPreset) -> Bool {
    func n(_ v: Double) -> Bool { v.isFinite }
    return isSupportedPalette(value.paletteId) &&
        n(Double(value.maxColors)) && value.maxColors >= 2 && value.maxColors <= 60 &&
        isMode(value.mode) && isBackgroundMode(value.backgroundMode) &&
        isDithering(value.dithering) &&
        n(value.outlineStrength) && value.outlineStrength >= 0 && value.outlineStrength <= 1 &&
        n(value.saturationBoost) && value.saturationBoost >= 1 && value.saturationBoost <= 1.3 &&
        n(value.contrastBoost) && value.contrastBoost >= 1 && value.contrastBoost <= 1.25 &&
        n(value.shadowLift) && value.shadowLift >= 0 && value.shadowLift <= 0.2 &&
        n(Double(value.cleanupSmallRegionMinSize)) && value.cleanupSmallRegionMinSize >= 1 &&
        n(value.tinyColorUsageRatio) && value.tinyColorUsageRatio >= 0 && value.tinyColorUsageRatio <= 0.01 &&
        n(value.lightnessBucketCoverage) && value.lightnessBucketCoverage >= 0 &&
        value.lightnessBucketCoverage <= 1 &&
        n(value.petFriendlyPenalty) && value.petFriendlyPenalty >= 0 && value.petFriendlyPenalty <= 20 &&
        isOutlineMode(value.outlineDrawMode) &&
        n(value.featureProtectionStrength) && value.featureProtectionStrength >= 0 &&
        value.featureProtectionStrength <= 1 &&
        n(value.autoWhiteBalanceStrength) && value.autoWhiteBalanceStrength >= 0 &&
        value.autoWhiteBalanceStrength <= 1 &&
        n(value.vibranceBoost) && value.vibranceBoost >= 1 && value.vibranceBoost <= 1.35 &&
        n(value.brightnessBoost) && value.brightnessBoost >= 0.95 && value.brightnessBoost <= 1.1 &&
        n(value.neutralGuardStrength) && value.neutralGuardStrength >= 0 &&
        value.neutralGuardStrength <= 1 &&
        n(value.highlightProtectStrength) && value.highlightProtectStrength >= 0 &&
        value.highlightProtectStrength <= 1 &&
        n(value.subjectLocalContrast) && value.subjectLocalContrast >= 0 &&
        value.subjectLocalContrast <= 0.35 &&
        n(value.backgroundDesaturation) && value.backgroundDesaturation >= 0 &&
        value.backgroundDesaturation <= 1 &&
        n(value.backgroundBlurStrength) && value.backgroundBlurStrength >= 0 &&
        value.backgroundBlurStrength <= 1
}

// MARK: - StylizedDraft JSON 解析

private let VALID_DRAFT_STYLE_MODES: Set<String> = ["faithful", "illustration", "badge", "cute"]
private let VALID_DRAFT_ABSTRACTION: Set<String> = ["low", "medium", "high", "extreme"]
private let VALID_DRAFT_BG_MODES: Set<String> = ["keep", "desaturate", "blur", "replace_plain", "empty"]

private func parseStylizedDraft(_ json: [String: Any]?) -> StylizedDraftOptions? {
    guard let json else { return nil }
    let def = DEFAULT_STYLIZED_DRAFT_OPTIONS
    let styleMode: StylizedDraftStyleMode = {
        if let s = json["styleMode"] as? String, VALID_DRAFT_STYLE_MODES.contains(s),
           let m = StylizedDraftStyleMode(rawValue: s) { return m }
        return def.styleMode
    }()
    let abstractionLevel: StylizedDraftAbstractionLevel = {
        if let s = json["abstractionLevel"] as? String, VALID_DRAFT_ABSTRACTION.contains(s),
           let l = StylizedDraftAbstractionLevel(rawValue: s) { return l }
        return def.abstractionLevel
    }()
    let backgroundMode: StylizedDraftBackgroundMode = {
        if let s = json["backgroundMode"] as? String, VALID_DRAFT_BG_MODES.contains(s),
           let m = StylizedDraftBackgroundMode(rawValue: s) { return m }
        return def.backgroundMode
    }()
    func jnum(_ key: String) -> Double? {
        if let v = json[key] as? Double { return v }
        if let v = json[key] as? Int { return Double(v) }
        return nil
    }
    func jint(_ key: String) -> Int? {
        if let v = json[key] as? Int { return v }
        if let v = json[key] as? Double { return Int(v) }
        return nil
    }
    return StylizedDraftOptions(
        enabled: (json["enabled"] as? Bool) ?? def.enabled,
        styleMode: styleMode,
        abstractionLevel: abstractionLevel,
        virtualColorCount: clampInteger(jnum("virtualColorCount") ?? Double(def.virtualColorCount), 4, 24),
        subjectOnly: (json["subjectOnly"] as? Bool) ?? def.subjectOnly,
        neutralGuard: (json["neutralGuard"] as? Bool) ?? def.neutralGuard,
        highlightProtect: (json["highlightProtect"] as? Bool) ?? def.highlightProtect,
        preserveFaceFeatures: (json["preserveFaceFeatures"] as? Bool) ?? def.preserveFaceFeatures,
        preservePatternRegions: (json["preservePatternRegions"] as? Bool) ?? def.preservePatternRegions,
        backgroundMode: backgroundMode,
        backgroundDesaturation: clampNumber(jnum("backgroundDesaturation") ?? def.backgroundDesaturation, 0, 1),
        backgroundBlurRadius: clampInteger(Double(jint("backgroundBlurRadius") ?? def.backgroundBlurRadius), 0, 5),
        vibranceBoost: clampNumber(jnum("vibranceBoost") ?? def.vibranceBoost, 0.8, 1.4),
        saturationBoost: clampNumber(jnum("saturationBoost") ?? def.saturationBoost, 0.8, 1.4),
        contrastBoost: clampNumber(jnum("contrastBoost") ?? def.contrastBoost, 0.8, 1.4),
        brightnessBoost: clampNumber(jnum("brightnessBoost") ?? def.brightnessBoost, 0.9, 1.2),
        warmthBoost: clampNumber(jnum("warmthBoost") ?? def.warmthBoost, -0.1, 0.2),
        posterizeStrength: clampNumber(jnum("posterizeStrength") ?? def.posterizeStrength, 0, 1),
        localContrastStrength: clampNumber(jnum("localContrastStrength") ?? def.localContrastStrength, 0, 0.5)
    )
}

// MARK: - 预设复制

private func copyStylizedDraft(_ source: StylizedDraftOptions?) -> StylizedDraftOptions? {
    guard let source else { return nil }
    return source  // struct 是值类型，赋值即拷贝
}

private func copyGeneration(_ source: BeadGenerationPreset) -> BeadGenerationPreset {
    var copy = source
    copy.stylizedDraft = copyStylizedDraft(source.stylizedDraft)
    return copy
}

private func copyStyleRules(_ source: BeadStyleRules?) -> BeadStyleRules? {
    guard let source else { return nil }
    return source
}

private func copyEffect(_ source: BeadEffectPreset) -> BeadEffectPreset {
    var copy = source
    copy.recommendedSizes = source.recommendedSizes
    copy.generation = copyGeneration(source.generation)
    copy.styleRules = copyStyleRules(source.styleRules)
    return copy
}

// MARK: - 样式规则应用

private func defaultStyleRules(_ preset: BeadEffectPreset) -> BeadStyleRules {
    return BeadStyleRules(outlineMode: preset.generation.outlineDrawMode,
                          backgroundStyle: preset.generation.backgroundMode)
}

private func applyPreFilterMode(_ target: inout BeadGenerationPreset, _ mode: BeadPreFilterMode) {
    switch mode {
    case "off":
        target.autoWhiteBalanceStrength = 0
        target.vibranceBoost = 1
        target.brightnessBoost = 1
        target.neutralGuardStrength = 1
        target.highlightProtectStrength = 1
    case "natural":
        target.autoWhiteBalanceStrength = 0.45
        target.vibranceBoost = 1.08
        target.brightnessBoost = 1.01
        target.neutralGuardStrength = 0.9
        target.highlightProtectStrength = 0.9
    case "vivid":
        target.autoWhiteBalanceStrength = 0.65
        target.vibranceBoost = 1.2
        target.brightnessBoost = 1.03
        target.neutralGuardStrength = 0.85
        target.highlightProtectStrength = 0.85
    case "badge_clear":
        target.autoWhiteBalanceStrength = 0.7
        target.vibranceBoost = 1.18
        target.brightnessBoost = 1.02
        target.neutralGuardStrength = 0.9
        target.highlightProtectStrength = 0.8
    default:  // cute_bright
        target.autoWhiteBalanceStrength = 0.55
        target.vibranceBoost = 1.25
        target.brightnessBoost = 1.06
        target.neutralGuardStrength = 1
        target.highlightProtectStrength = 0.9
    }
}

private func applyStyleRules(_ target: inout BeadGenerationPreset, _ rules: BeadStyleRules?) {
    guard let rules else { return }
    if let mode = rules.outlineMode { target.outlineDrawMode = mode }
    if let bg = rules.backgroundStyle { target.backgroundMode = bg }
    if let filter = rules.preFilterMode { applyPreFilterMode(&target, filter) }
}

// MARK: - 预设查找

private func normalizePresetId(_ presetId: String) -> BeadEffectPresetId {
    if presetId == "faithful" || presetId == "faithful_v1" { return "faithful_v1" }
    if presetId == "badge" || presetId == "badge_v1" { return "badge_v1" }
    if presetId == "fullPhoto" || presetId == "full_photo_v1" { return "full_photo_v1" }
    if presetId == "cute" || presetId == "cute_v1" { return "cute_v1" }
    return "illustration_v1"
}

private func findPreset(_ presetId: String) -> BeadEffectPreset {
    let normalized = normalizePresetId(presetId)
    effectPresetsLock.lock()
    defer { effectPresetsLock.unlock() }
    for preset in _effectPresets {
        if preset.id == normalized { return preset }
    }
    return _effectPresets[0]
}

private func replacePresetRegistry(_ presets: [BeadEffectPreset]) {
    effectPresetsLock.lock()
    _effectPresets = presets.map { copyEffect($0) }
    effectPresetsLock.unlock()
}

// MARK: - 覆盖项应用

private func applyOverrides(_ target: inout BeadGenerationPreset, _ overrides: BeadGenerationOverrides?) {
    guard let overrides else { return }
    if let pid = overrides.paletteId, isSupportedPalette(pid) { target.paletteId = pid }
    if let mc = overrides.maxColors { target.maxColors = clampInteger(Double(mc), 2, 60) }
    if let d = overrides.dithering { target.dithering = d }
    if let o = overrides.outline { target.outline = o }
    if let dn = overrides.denoise { target.denoise = dn }
    if let os = overrides.outlineStrength { target.outlineStrength = clampNumber(os, 0, 1) }
    if let sb = overrides.saturationBoost { target.saturationBoost = clampNumber(sb, 1, 1.3) }
    if let cb = overrides.contrastBoost { target.contrastBoost = clampNumber(cb, 1, 1.25) }
    if let sl = overrides.shadowLift { target.shadowLift = clampNumber(sl, 0, 0.2) }
    if let csr = overrides.cleanupSmallRegionMinSize {
        target.cleanupSmallRegionMinSize = clampInteger(Double(csr), 1, 6)
    }
    if let tcr = overrides.tinyColorUsageRatio {
        target.tinyColorUsageRatio = clampNumber(tcr, 0, 0.01)
    }
    if let lbc = overrides.lightnessBucketCoverage {
        target.lightnessBucketCoverage = clampNumber(lbc, 0, 1)
    }
    if let pfp = overrides.petFriendlyPenalty {
        target.petFriendlyPenalty = clampNumber(pfp, 0, 20)
    }
    if let usc = overrides.useSubjectCutout {
        target.useSubjectCutout = usc
        target.backgroundMode = usc ? "transparent" : "light"
    }
    if let odm = overrides.outlineDrawMode {
        target.outlineDrawMode = odm
    }
    if let fps = overrides.featureProtectionStrength {
        target.featureProtectionStrength = clampNumber(fps, 0, 1)
    }
    if let awb = overrides.autoWhiteBalanceStrength {
        target.autoWhiteBalanceStrength = clampNumber(awb, 0, 1)
    }
    if let vb = overrides.vibranceBoost {
        target.vibranceBoost = clampNumber(vb, 1, 1.35)
    }
    if let bb = overrides.brightnessBoost {
        target.brightnessBoost = clampNumber(bb, 0.95, 1.1)
    }
    if let ngs = overrides.neutralGuardStrength {
        target.neutralGuardStrength = clampNumber(ngs, 0, 1)
    }
    if let hps = overrides.highlightProtectStrength {
        target.highlightProtectStrength = clampNumber(hps, 0, 1)
    }
    if let slc = overrides.subjectLocalContrast {
        target.subjectLocalContrast = clampNumber(slc, 0, 0.35)
    }
    if let bd = overrides.backgroundDesaturation {
        target.backgroundDesaturation = clampNumber(bd, 0, 1)
    }
    if let bbs = overrides.backgroundBlurStrength {
        target.backgroundBlurStrength = clampNumber(bbs, 0, 1)
    }
}

// MARK: - 网格约束

private func applyGridConstraints(_ target: inout BeadGenerationPreset, _ gridSize: Int) {
    if gridSize <= 29 {
        target.maxColors = min(target.maxColors, 14)
        target.dithering = "none"
        target.denoise = true
        // 小尺寸下强制降低轮廓强度，避免黑边吞掉主体
        if target.outlineDrawMode == "black" { target.outlineDrawMode = "dark" }
        if target.outlineDrawMode == "outer_black" { target.outlineDrawMode = "outer_dark" }
        // 29×29 自动降低主体局部增强强度，避免毛发纹理碎裂
        target.subjectLocalContrast = min(target.subjectLocalContrast, 0.10)
        target.outlineStrength = min(target.outlineStrength, 0.55)
    } else if gridSize <= 40 {
        target.maxColors = min(target.maxColors, 20)
        target.dithering = "none"
    } else if gridSize <= 58 {
        target.maxColors = min(target.maxColors, 40)
    } else {
        target.maxColors = min(target.maxColors, 60)
    }
}

// MARK: - JSON 验证 + 解析

private func jsonNum(_ dict: [String: Any], _ key: String) -> Double? {
    if let v = dict[key] as? Double { return v }
    if let v = dict[key] as? Int { return Double(v) }
    return nil
}

private func jsonInt(_ dict: [String: Any], _ key: String) -> Int? {
    if let v = dict[key] as? Int { return v }
    if let v = dict[key] as? Double { return Int(v) }
    return nil
}

/// 从 JSON 字典提取并验证 BeadGenerationPreset。验证失败返回 nil。
private func extractGeneration(_ dict: [String: Any]) -> BeadGenerationPreset? {
    guard let paletteId = dict["paletteId"] as? String, isSupportedPalette(paletteId),
          let maxColors = jsonInt(dict, "maxColors"), maxColors >= 2, maxColors <= 60,
          let mode = dict["mode"] as? String, isMode(mode),
          let backgroundMode = dict["backgroundMode"] as? String, isBackgroundMode(backgroundMode),
          let outline = dict["outline"] as? Bool,
          let dithering = dict["dithering"] as? String, isDithering(dithering),
          let denoise = dict["denoise"] as? Bool,
          let preserveBrightness = dict["preserveBrightness"] as? Bool,
          let useSubjectCutout = dict["useSubjectCutout"] as? Bool,
          let outlineStrength = jsonNum(dict, "outlineStrength"),
          outlineStrength >= 0, outlineStrength <= 1,
          let saturationBoost = jsonNum(dict, "saturationBoost"),
          saturationBoost >= 1, saturationBoost <= 1.3,
          let contrastBoost = jsonNum(dict, "contrastBoost"),
          contrastBoost >= 1, contrastBoost <= 1.25,
          let shadowLift = jsonNum(dict, "shadowLift"),
          shadowLift >= 0, shadowLift <= 0.2,
          let cleanupSmallRegionMinSize = jsonInt(dict, "cleanupSmallRegionMinSize"),
          cleanupSmallRegionMinSize >= 1,
          let tinyColorUsageRatio = jsonNum(dict, "tinyColorUsageRatio"),
          tinyColorUsageRatio >= 0, tinyColorUsageRatio <= 0.01,
          let lightnessBucketCoverage = jsonNum(dict, "lightnessBucketCoverage"),
          lightnessBucketCoverage >= 0, lightnessBucketCoverage <= 1,
          let petFriendlyPenalty = jsonNum(dict, "petFriendlyPenalty"),
          petFriendlyPenalty >= 0, petFriendlyPenalty <= 20,
          let outlineDrawMode = dict["outlineDrawMode"] as? String, isOutlineMode(outlineDrawMode),
          let featureProtectionStrength = jsonNum(dict, "featureProtectionStrength"),
          featureProtectionStrength >= 0, featureProtectionStrength <= 1,
          let autoWhiteBalanceStrength = jsonNum(dict, "autoWhiteBalanceStrength"),
          autoWhiteBalanceStrength >= 0, autoWhiteBalanceStrength <= 1,
          let vibranceBoost = jsonNum(dict, "vibranceBoost"),
          vibranceBoost >= 1, vibranceBoost <= 1.35,
          let brightnessBoost = jsonNum(dict, "brightnessBoost"),
          brightnessBoost >= 0.95, brightnessBoost <= 1.1,
          let neutralGuardStrength = jsonNum(dict, "neutralGuardStrength"),
          neutralGuardStrength >= 0, neutralGuardStrength <= 1,
          let highlightProtectStrength = jsonNum(dict, "highlightProtectStrength"),
          highlightProtectStrength >= 0, highlightProtectStrength <= 1,
          let subjectLocalContrast = jsonNum(dict, "subjectLocalContrast"),
          subjectLocalContrast >= 0, subjectLocalContrast <= 0.35,
          let backgroundDesaturation = jsonNum(dict, "backgroundDesaturation"),
          backgroundDesaturation >= 0, backgroundDesaturation <= 1,
          let backgroundBlurStrength = jsonNum(dict, "backgroundBlurStrength"),
          backgroundBlurStrength >= 0, backgroundBlurStrength <= 1
    else { return nil }

    let gen = BeadGenerationPreset(
        paletteId: paletteId, maxColors: maxColors, mode: mode,
        backgroundMode: backgroundMode, outline: outline, dithering: dithering,
        denoise: denoise, preserveBrightness: preserveBrightness,
        useSubjectCutout: useSubjectCutout, outlineStrength: outlineStrength,
        saturationBoost: saturationBoost, contrastBoost: contrastBoost,
        shadowLift: shadowLift, cleanupSmallRegionMinSize: cleanupSmallRegionMinSize,
        tinyColorUsageRatio: tinyColorUsageRatio,
        lightnessBucketCoverage: lightnessBucketCoverage,
        petFriendlyPenalty: petFriendlyPenalty, outlineDrawMode: outlineDrawMode,
        featureProtectionStrength: featureProtectionStrength,
        autoWhiteBalanceStrength: autoWhiteBalanceStrength,
        vibranceBoost: vibranceBoost, brightnessBoost: brightnessBoost,
        neutralGuardStrength: neutralGuardStrength,
        highlightProtectStrength: highlightProtectStrength,
        subjectLocalContrast: subjectLocalContrast,
        backgroundDesaturation: backgroundDesaturation,
        backgroundBlurStrength: backgroundBlurStrength
    )
    if !validateGeneration(gen) { return nil }
    return gen
}

/// 从 JSON 字典提取并验证 BeadStyleRules。验证失败返回 nil（区别于 "无 styleRules" 返回成功）。
private func extractStyleRules(_ dict: [String: Any]?) -> (BeadStyleRules?, Bool) {
    guard let dict else { return (nil, true) }
    let rules = BeadStyleRules(
        outlineMode: dict["outlineMode"] as? String,
        backgroundStyle: dict["backgroundStyle"] as? String,
        eyeHighlightStrength: jsonNum(dict, "eyeHighlightStrength"),
        preFilterMode: dict["preFilterMode"] as? String
    )
    if !validateStyleRules(rules) { return (nil, false) }
    return (rules, true)
}

// MARK: - BeadPresetResolver

/// 预设参数解析器。对应源端 `BeadPresetResolver` class。
public enum BeadPresetResolver {

    /// 从 JSON 文本加载预设配置。成功返回 true，验证失败返回 false 且不修改注册表。
    public static func loadFromJsonText(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        guard let schemaVersion = jsonInt(parsed, "schemaVersion"), schemaVersion == 1,
              let presetsArray = parsed["presets"] as? [[String: Any]],
              presetsArray.count == 5
        else { return false }

        var presets: [BeadEffectPreset] = []
        var seenIds = Set<String>()

        for presetDict in presetsArray {
            guard let id = presetDict["id"] as? String, isEffectId(id), !seenIds.contains(id),
                  let version = jsonInt(presetDict, "version"), version >= 1,
                  let name = presetDict["name"] as? String, !name.isEmpty,
                  let description = presetDict["description"] as? String,
                  let recommended = presetDict["recommended"] as? Bool,
                  let recommendedSizes = presetDict["recommendedSizes"] as? [Int],
                  !recommendedSizes.isEmpty,
                  let genDict = presetDict["generation"] as? [String: Any],
                  let gen = extractGeneration(genDict)
            else { return false }

            for size in recommendedSizes {
                if size < 16 || size > 80 { return false }
            }

            let (styleRules, styleValid) = extractStyleRules(presetDict["styleRules"] as? [String: Any])
            if !styleValid { return false }

            var effect = BeadEffectPreset(
                id: id, version: version, name: name, description: description,
                recommended: recommended, recommendedSizes: recommendedSizes,
                generation: gen, styleRules: styleRules
            )

            // 解析可选 stylizedDraft
            if let draftDict = presetDict["stylizedDraft"] as? [String: Any] {
                effect.generation.stylizedDraft = parseStylizedDraft(draftDict)
            }

            seenIds.insert(id)
            presets.append(effect)
        }

        guard seenIds.count == 5 else { return false }
        replacePresetRegistry(presets)
        return true
    }

    /// 恢复内置预设注册表。
    public static func resetToBuiltIns() {
        effectPresetsLock.lock()
        _effectPresets = makeBuiltinEffectPresets()
        effectPresetsLock.unlock()
    }

    /// 获取效果预设。
    public static func getEffect(_ presetId: String) -> BeadEffectPreset {
        return findPreset(presetId)
    }

    /// 解析预设 + 覆盖项 + 网格约束，返回完整的生成参数。
    public static func resolve(
        _ presetId: String,
        gridSize: Int,
        overrides: BeadGenerationOverrides? = nil
    ) -> ResolvedBeadGeneration {
        let preset = findPreset(presetId)
        let normalizedGridSize = clampInteger(Double(gridSize), 16, 80)
        var resolved = copyGeneration(preset.generation)
        applyStyleRules(&resolved, preset.styleRules ?? defaultStyleRules(preset))
        applyOverrides(&resolved, overrides)
        applyGridConstraints(&resolved, normalizedGridSize)

        let options = BeadGenerateOptions(
            targetWidth: normalizedGridSize,
            targetHeight: normalizedGridSize,
            maxColors: resolved.maxColors,
            paletteId: resolved.paletteId,
            mode: resolved.mode,
            backgroundMode: resolved.backgroundMode,
            outline: resolved.outline,
            dithering: resolved.dithering,
            denoise: resolved.denoise,
            eyeEnhance: true,
            preserveBrightness: resolved.preserveBrightness,
            outlineStrength: resolved.outlineStrength,
            saturationBoost: resolved.saturationBoost,
            contrastBoost: resolved.contrastBoost,
            shadowLift: resolved.shadowLift,
            cleanupSmallRegionMinSize: resolved.cleanupSmallRegionMinSize,
            tinyColorUsageRatio: resolved.tinyColorUsageRatio,
            lightnessBucketCoverage: resolved.lightnessBucketCoverage,
            petFriendlyPenalty: resolved.petFriendlyPenalty,
            outlineDrawMode: resolved.outlineDrawMode,
            featureProtectionStrength: resolved.featureProtectionStrength,
            autoWhiteBalanceStrength: resolved.autoWhiteBalanceStrength,
            vibranceBoost: resolved.vibranceBoost,
            brightnessBoost: resolved.brightnessBoost,
            neutralGuardStrength: resolved.neutralGuardStrength,
            highlightProtectStrength: resolved.highlightProtectStrength,
            subjectLocalContrast: resolved.subjectLocalContrast,
            backgroundDesaturation: resolved.backgroundDesaturation,
            backgroundBlurStrength: resolved.backgroundBlurStrength,
            stylizedDraft: copyStylizedDraft(resolved.stylizedDraft)
        )
        let recipe = BeadGenerationRecipe(
            presetId: preset.id,
            presetVersion: preset.version,
            resolvedOptions: copyGeneration(resolved),
            algorithmVersion: BEAD_ALGORITHM_VERSION
        )
        return ResolvedBeadGeneration(
            options: options, generation: resolved, recipe: recipe,
            isAuto: resolved.paletteId == "MARD_291"
        )
    }

    /// 从 UI 控件值构建覆盖项。
    public static func overridesFromControls(
        colorKey: String,
        dithering: BeadDithering,
        outline: Bool,
        denoise: Bool,
        useSubjectCutout: Bool
    ) -> BeadGenerationOverrides {
        let colorPreset = BEAD_COLOR_PRESETS[colorKey] ?? BEAD_COLOR_PRESETS["standard"]!
        var overrides = BeadGenerationOverrides()
        overrides.paletteId = colorPreset.paletteId
        overrides.maxColors = colorPreset.count
        overrides.dithering = dithering
        overrides.outline = outline
        overrides.denoise = denoise
        overrides.useSubjectCutout = useSubjectCutout
        return overrides
    }
}
