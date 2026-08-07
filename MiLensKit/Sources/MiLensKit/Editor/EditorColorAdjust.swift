import Foundation

// EditorColorAdjust — 调色参数建模与 CIFilter/CoreImage filter 近似。
// 翻译自源端 entry/.../editor/ColorAdjust.ets（143 行）。
//
// 架构差异：
// - 源端 toCanvasFilter 生成 CSS filter 字符串（ArkUI Canvas）。
// - iOS 侧用 CIFilter/Core Image，改为返回结构化因子（brightness/contrast/saturation），
//   由 App 层的渲染管线转换为 CIFilter 参数。toCanvasFilter 保留为兼容/调试用途。

/// 调色参数；每项 0 表示"原图"，正值增强、负值减弱。对应源端 `ColorAdjustments`。
public struct EditorColorAdjustments: Equatable, Sendable {
    /// 亮度：-100..100，0 = 原图。
    public var brightness: Double
    /// 对比度：-100..100，0 = 原图。
    public var contrast: Double
    /// 饱和度：-100..100，0 = 原图。
    public var saturation: Double
    /// 色温：-100..100，正值偏暖、负值偏冷，0 = 原图。
    public var temperature: Double
    /// 锐化：0..100，0 = 不锐化。
    public var sharpness: Double

    public init(brightness: Double = 0, contrast: Double = 0, saturation: Double = 0,
                temperature: Double = 0, sharpness: Double = 0) {
        self.brightness = brightness; self.contrast = contrast
        self.saturation = saturation; self.temperature = temperature
        self.sharpness = sharpness
    }
}

/// 中性（无调整）参数。对应源端 `NEUTRAL_ADJUSTMENTS`。
public let NEUTRAL_EDITOR_ADJUSTMENTS = EditorColorAdjustments()

/// 增量调色参数（所有字段可选）。对应源端 `ColorAdjustDelta`。
public struct EditorColorAdjustDelta: Equatable, Sendable {
    public var brightness: Double?
    public var contrast: Double?
    public var saturation: Double?
    public var temperature: Double?
    public var sharpness: Double?

    public init(brightness: Double? = nil, contrast: Double? = nil, saturation: Double? = nil,
                temperature: Double? = nil, sharpness: Double? = nil) {
        self.brightness = brightness; self.contrast = contrast
        self.saturation = saturation; self.temperature = temperature
        self.sharpness = sharpness
    }
}

/// 结构化 filter 因子（供 App 渲染层转换为 CIFilter 参数）。iOS 新增，替代源端 CSS filter 字符串。
public struct EditorFilterFactors: Equatable, Sendable {
    /// 亮度因子：1.0 = 无变化（对应 CIColorControls.brightness 偏移）
    public var brightnessFactor: Double
    /// 对比度因子：1.0 = 无变化
    public var contrastFactor: Double
    /// 饱和度因子：1.0 = 无变化
    public var saturationFactor: Double

    public init(brightnessFactor: Double = 1.0, contrastFactor: Double = 1.0,
                saturationFactor: Double = 1.0) {
        self.brightnessFactor = brightnessFactor
        self.contrastFactor = contrastFactor
        self.saturationFactor = saturationFactor
    }
}

// MARK: - 纯函数

private let MIN_LINEAR: Double = -100
private let MAX_LINEAR: Double = 100
private let MIN_SHARPNESS: Double = 0
private let MAX_SHARPNESS: Double = 100

/// 钳制调色参数到合法范围。对应源端 `clampAdjustments`。
public func clampAdjustments(_ a: EditorColorAdjustments) -> EditorColorAdjustments {
    return EditorColorAdjustments(
        brightness: clampLinear(a.brightness),
        contrast: clampLinear(a.contrast),
        saturation: clampLinear(a.saturation),
        temperature: clampLinear(a.temperature),
        sharpness: clamp(a.sharpness, lo: MIN_SHARPNESS, hi: MAX_SHARPNESS))
}

/// 判断是否所有参数都是中性。对应源端 `isNeutral`。
public func isNeutral(_ a: EditorColorAdjustments) -> Bool {
    return a.brightness == 0 && a.contrast == 0 && a.saturation == 0
        && a.temperature == 0 && a.sharpness == 0
}

/// 把调色参数转换为结构化 filter 因子。对应源端 `toCanvasFilter`（iOS 改为结构化）。
/// - 0..100 → 1.0..1.8；-100..0 → 0.2..1.0（与源端一致）。
public func toFilterFactors(_ a: EditorColorAdjustments) -> EditorFilterFactors {
    let clamped = clampAdjustments(a)
    return EditorFilterFactors(
        brightnessFactor: clamped.brightness != 0 ? linearToFactor(clamped.brightness) : 1.0,
        contrastFactor: clamped.contrast != 0 ? linearToFactor(clamped.contrast) : 1.0,
        saturationFactor: clamped.saturation != 0 ? linearToFactor(clamped.saturation) : 1.0)
}

/// 把 base 与 delta 合并。对应源端 `mergeAdjustments`。
public func mergeAdjustments(base: EditorColorAdjustments, delta: EditorColorAdjustDelta) -> EditorColorAdjustments {
    return EditorColorAdjustments(
        brightness: delta.brightness ?? base.brightness,
        contrast: delta.contrast ?? base.contrast,
        saturation: delta.saturation ?? base.saturation,
        temperature: delta.temperature ?? base.temperature,
        sharpness: delta.sharpness ?? base.sharpness)
}

// MARK: - 内部辅助

@inline(__always)
private func clampLinear(_ v: Double) -> Double {
    clamp(v, lo: MIN_LINEAR, hi: MAX_LINEAR)
}

@inline(__always)
private func clamp(_ v: Double, lo: Double, hi: Double) -> Double {
    min(max(v, lo), hi)
}

/// 把 -100..100 的线性参数映射到 filter 因子值。对应源端 `linearToFactor`。
/// 0 → 1.0；100 → 1.8；-100 → 0.2。
@inline(__always)
private func linearToFactor(_ linear: Double) -> Double {
    let normalized = linear / 100
    return 1 + normalized * 0.8
}
