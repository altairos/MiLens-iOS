import Foundation

// EditorAdjustLogic — 编辑器调色面板决策纯逻辑。
// 翻译自源端 entry/.../viewmodels/EditorAdjustViewModel.ets（159 行）。
//
// 从 EditorPage 调色面板（syncAdjustmentsFromPhoto / buildCurrentAdjustments /
// onAdjustSliderChange / resetAdjustments）抽出的决策纯逻辑。
//
// 设计要点：
// - 所有函数无 IO / 无 SwiftUI 依赖，可在宿主单测覆盖。
// - ArkUI SliderChangeMode（数值枚举）不进入逻辑层；本模块定义 SliderGesturePhase
//   字符串枚举，App 层在边界做 SwiftUI 手势阶段 → SliderGesturePhase 映射。
// - buildAdjustments 把面板 5 项状态组装为 EditorColorAdjustments。
// - resolveSliderGesture 返回 shouldBeginGesture / shouldEndGesture 指令位，
//   让手势合并的 Begin/End/Click 判断脱离 inline if 链。
// - resolveSharpnessApply 决定何时触发异步锐化卷积（仅在 end/click 且强度变化时）。

/// 调色面板状态（与 EditorPage adjust* 状态一一对应）。对应源端 `AdjustPanelState`。
public struct EditorAdjustPanelState: Equatable, Sendable {
    public var brightness: Double
    public var contrast: Double
    public var saturation: Double
    public var temperature: Double
    /// 锐化强度 0..100（0 = 不锐化）。对应源端 P0.4 新增字段。
    public var sharpness: Double

    public init(brightness: Double = 0, contrast: Double = 0, saturation: Double = 0,
                temperature: Double = 0, sharpness: Double = 0) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.temperature = temperature
        self.sharpness = sharpness
    }
}

/// 滑块手势阶段（并行于 ArkUI SliderChangeMode / SwiftUI DragGesture 阶段）。
/// 对应源端 `SliderGesturePhase`。
public enum EditorSliderGesturePhase: String, Sendable, Equatable {
    case begin
    case moving
    case end
    case click
}

/// 滑块手势决策指令位。对应源端 `SliderGestureDecision`。
public struct EditorSliderGestureDecision: Equatable, Sendable {
    /// 是否应在 apply 前调 beginGesture（开启手势合并窗口）。
    public let shouldBeginGesture: Bool
    /// 是否应在 apply 后调 endGesture（关闭手势合并窗口，提交一条历史）。
    public let shouldEndGesture: Bool
}

/// 锐化卷积触发决策指令位。对应源端 `SharpnessApplyDecision`。
public struct EditorSharpnessApplyDecision: Equatable, Sendable {
    /// 是否应在此次手势阶段触发异步卷积（仅 end/click 且强度变化时为 true）。
    public let shouldApply: Bool
    /// 应应用的锐化强度（已 clamp 到 0..100）。
    public let strength: Double
}

/// 全 0 面板状态（等价于中性调色）。对应源端 `defaultAdjustPanelState`。
public func defaultAdjustPanelState() -> EditorAdjustPanelState {
    return EditorAdjustPanelState()
}

/// 把面板状态组装为 EditorColorAdjustments。
/// 调用方用返回值调 applyColorAdjustments(adj, commit)。
/// 注意：brightness/contrast/saturation/temperature 通过 CIFilter 实时预览；
/// sharpness 需异步卷积，由 App 层在 slider 释放时单独触发。
/// 这里仍把 sharpness 写入 adjustments，用于元数据记录和导出的一致性。
/// 对应源端 `buildAdjustments`。
public func buildAdjustments(_ state: EditorAdjustPanelState) -> EditorColorAdjustments {
    return EditorColorAdjustments(
        brightness: state.brightness,
        contrast: state.contrast,
        saturation: state.saturation,
        temperature: state.temperature,
        sharpness: clampSharpness(state.sharpness))
}

/// 判断面板 5 项是否全为中性（0），用于决定"重置"按钮是否可见/可点击。
/// 对应源端 `isAdjustNeutral`。
public func isAdjustNeutral(_ state: EditorAdjustPanelState) -> Bool {
    return state.brightness == 0
        && state.contrast == 0
        && state.saturation == 0
        && state.temperature == 0
        && state.sharpness == 0
}

/// 把 EditorColorAdjustments 同步为面板状态（含 sharpness）。
/// 对应源端 `syncAdjustPanelState`。
public func syncAdjustPanelState(_ adj: EditorColorAdjustments) -> EditorAdjustPanelState {
    return EditorAdjustPanelState(
        brightness: adj.brightness,
        contrast: adj.contrast,
        saturation: adj.saturation,
        temperature: adj.temperature,
        sharpness: adj.sharpness)
}

/// 根据手势阶段决定是否开启/关闭手势合并窗口。
/// - begin：shouldBeginGesture=true。
/// - end/click：shouldEndGesture=true。
/// - moving：两者皆 false（被合并的中间帧）。
/// 对应源端 `resolveSliderGesture`。
public func resolveSliderGesture(_ phase: EditorSliderGesturePhase) -> EditorSliderGestureDecision {
    return EditorSliderGestureDecision(
        shouldBeginGesture: phase == .begin,
        shouldEndGesture: phase == .end || phase == .click)
}

/// ArkUI SliderChangeMode（数值枚举）→ SliderGesturePhase 映射。
/// SliderChangeMode：Begin=0, Moving=1, End=2, Click=3。
/// 未知值降级为 moving。对应源端 `mapSliderModeToPhase`。
public func mapSliderModeToPhase(_ modeValue: Int) -> EditorSliderGesturePhase {
    switch modeValue {
    case 0: return .begin
    case 2: return .end
    case 3: return .click
    default: return .moving
    }
}

/// 根据手势阶段、上次提交强度与当前强度，决定是否触发异步锐化卷积。
///
/// 设计要点（与 brightness/contrast 的实时 filter 不同）：
/// - 锐化需要异步卷积，不能每帧触发；
/// - 只在 end/click 阶段且 strength 变化时触发 shouldApply=true；
/// - begin/moving 阶段返回 shouldApply=false（UI 只更新数字显示）；
/// - strength=0 也应触发（表示从非零回到 0，需要"撤销"卷积效果）。
///
/// - Parameters:
///   - prevStrength: 上次成功卷积后记录的强度（来自 layer.adjustments.sharpness）
///   - nextStrength: 当前 slider 的强度值
///   - phase: 当前手势阶段
/// 对应源端 `resolveSharpnessApply`。
public func resolveSharpnessApply(prevStrength: Double, nextStrength: Double,
                                  phase: EditorSliderGesturePhase) -> EditorSharpnessApplyDecision {
    let clamped = clampSharpness(nextStrength)
    let shouldApply = (phase == .end || phase == .click) && clamped != clampSharpness(prevStrength)
    return EditorSharpnessApplyDecision(shouldApply: shouldApply, strength: clamped)
}
