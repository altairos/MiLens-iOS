import Foundation

// EditorCutoutLogic — 编辑器内嵌抠图状态决策（纯逻辑）。
// 翻译自源端 entry/.../viewmodels/EditorCutoutViewModel.ets（166 行）。
//
// 设计要点：
// - 所有函数无 IO / 无 SwiftUI 依赖，可在宿主单测覆盖。
// - CutoutPhase 四态机：idle → processing → applied / error → idle（重试）。
// - 竞态保护：结果返回后通过 CutoutGuard 判定是否仍然有效。
// - 近似降级：分割结果携带 isFallback 标记时 UI 显示差异化提示。
//
// 架构差异：
// - 源端 generation 为 number（自增整数）；iOS 仍用 Int（值语义，调用方维护递增）。
// - 源端 CutoutGuard.targetLayerId 为 string；iOS 用 String（与 EditorLayer.id 一致）。

/// 抠图阶段。对应源端 `CutoutPhase`。
public enum EditorCutoutPhase: String, Sendable, Equatable {
    case idle
    case processing
    case applied
    case error
}

/// 竞态守卫快照。对应源端 `CutoutGuard`。
/// 异步抠图结果返回时，用此快照判定结果是否仍属于当前有效上下文。
public struct EditorCutoutGuard: Equatable, Sendable {
    /// 页面是否仍为 active（aboutToDisappear 后判 false）。
    public var pageActive: Bool
    /// 照片加载代际（加载新照片后递增）。
    public var photoGeneration: Int
    /// 抠图请求代际（每次发起新抠图递增）。
    public var cutoutGeneration: Int
    /// 目标照片图层 ID。
    public var targetLayerId: String
    /// 目标图层是否仍然存在。
    public var layerExists: Bool

    public init(pageActive: Bool, photoGeneration: Int, cutoutGeneration: Int,
                targetLayerId: String, layerExists: Bool) {
        self.pageActive = pageActive
        self.photoGeneration = photoGeneration
        self.cutoutGeneration = cutoutGeneration
        self.targetLayerId = targetLayerId
        self.layerExists = layerExists
    }
}

/// 抠图请求决策。对应源端 `CutoutStartDecision`。
public struct EditorCutoutStartDecision: Equatable, Sendable {
    /// 是否允许发起抠图。
    public let canStart: Bool
    /// 拒绝原因（简体中文提示，仅在 canStart=false 时有意义）。
    public let rejectReason: String
}

/// 结果验收决策。对应源端 `CutoutResultDecision`。
public struct EditorCutoutResultDecision: Equatable, Sendable {
    /// 结果是否仍然有效（竞态检查）。
    public let isValid: Bool
    /// 是否为近似降级结果（非真实 AI 分割）。
    public let isFallback: Bool
    /// 面向用户的状态文案。
    public let statusText: String
    /// 结果阶段（applied 或 error）。
    public let nextPhase: EditorCutoutPhase
}

// MARK: - 纯函数

/// 判定是否允许开始抠图。
/// 只在 idle / applied / error 阶段允许；processing 中禁止重复提交。
/// 对应源端 `canStartCutout`。
public func canStartCutout(_ phase: EditorCutoutPhase) -> EditorCutoutStartDecision {
    if phase == .processing {
        return EditorCutoutStartDecision(canStart: false, rejectReason: "正在识别主体，请稍候")
    }
    return EditorCutoutStartDecision(canStart: true, rejectReason: "")
}

/// 竞态守卫：判定异步结果是否仍然属于当前有效上下文。
///
/// 以下任一条件成立即判定过期：
/// - 页面已退出
/// - 已加载另一张照片（photoGeneration 不匹配）
/// - 已发起新一轮抠图（cutoutGeneration 不匹配）
/// - 目标图层已被删除或替换
///
/// 对应源端 `isCutoutResultValid`。
public func isCutoutResultValid(_ guard_: EditorCutoutGuard,
                                expectedPhotoGeneration: Int,
                                expectedCutoutGeneration: Int) -> Bool {
    if !guard_.pageActive { return false }
    if guard_.photoGeneration != expectedPhotoGeneration { return false }
    if guard_.cutoutGeneration != expectedCutoutGeneration { return false }
    if !guard_.layerExists { return false }
    return true
}

/// 根据分割结果和竞态状态，产出结果验收决策。
///
/// - Parameters:
///   - isValid: 竞态守卫是否通过（来自 isCutoutResultValid）
///   - resultNull: 分割服务是否返回 null（完全失败）
///   - isFallback: 结果是否为近似降级（中心裁切+椭圆蒙版，非真实 AI 分割）
/// 对应源端 `resolveCutoutResult`。
public func resolveCutoutResult(isValid: Bool, resultNull: Bool, isFallback: Bool) -> EditorCutoutResultDecision {
    // 竞态过期：静默丢弃，不改变阶段
    if !isValid {
        return EditorCutoutResultDecision(
            isValid: false, isFallback: false, statusText: "",
            nextPhase: .processing)  // 保持 processing，等待有效结果或用户离开
    }

    // 完全失败
    if resultNull {
        return EditorCutoutResultDecision(
            isValid: true, isFallback: false,
            statusText: "未能识别主体，请重试或更换照片",
            nextPhase: .error)
    }

    // 近似降级成功
    if isFallback {
        return EditorCutoutResultDecision(
            isValid: true, isFallback: true,
            statusText: "已使用近似裁切，效果可能不如 AI 分割",
            nextPhase: .applied)
    }

    // AI 分割成功
    return EditorCutoutResultDecision(
        isValid: true, isFallback: false,
        statusText: "已移除背景，可撤销",
        nextPhase: .applied)
}

/// 根据阶段返回面板展示文案。对应源端 `cutoutStatusText`。
public func cutoutStatusText(_ phase: EditorCutoutPhase) -> String {
    switch phase {
    case .idle: return "自动识别主体并移除背景"
    case .processing: return "正在识别主体…"
    case .applied: return "已移除背景，可撤销"
    case .error: return "识别失败，可重试"
    }
}

/// 根据阶段决定"开始/重试"按钮是否可点击。
/// processing 时禁用（进行中）；其余阶段可点击。对应源端 `canRetryCutout`。
public func canRetryCutout(_ phase: EditorCutoutPhase) -> Bool {
    return phase != .processing
}
