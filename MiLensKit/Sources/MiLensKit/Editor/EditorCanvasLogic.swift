import Foundation

// EditorCanvasLogic — 编辑器画布状态查询纯逻辑。
// 翻译自源端 entry/.../viewmodels/EditorCanvasViewModel.ets（36 行）。
//
// 从 EditorPage 抽出的状态查询函数，使其可在宿主单测覆盖。
//
// 架构差异：
// - 源端 EditorCanvasViewModel 定义了独立的 `EditorTool` 字符串联合类型（少 bead/cutout），
//   与 EditorToolViewModel 的 `EditorToolMode` 重叠。iOS 统一到 `EditorToolMode`（类型安全）。
// - 源端 tool 字段为 string；iOS 用 EditorToolMode（消除字符串拼写错误风险）。

/// 编辑器画布状态快照。对应源端 `EditorCanvasState`。
public struct EditorCanvasState: Equatable, Sendable {
    public var tool: EditorToolMode
    public var isSaving: Bool
    public var isPhotoLoading: Bool

    public init(tool: EditorToolMode = .none, isSaving: Bool = false, isPhotoLoading: Bool = true) {
        self.tool = tool
        self.isSaving = isSaving
        self.isPhotoLoading = isPhotoLoading
    }
}

/// 默认画布状态：工具 none、非保存中、照片加载中。对应源端 `defaultEditorCanvasState`。
public func defaultEditorCanvasState() -> EditorCanvasState {
    return EditorCanvasState(tool: .none, isSaving: false, isPhotoLoading: true)
}

/// 判断指定工具是否激活。对应源端 `isToolActive`。
public func isToolActive(_ state: EditorCanvasState, tool: EditorToolMode) -> Bool {
    return state.tool == tool
}

/// 是否可以开始保存（非保存中且照片未在加载）。对应源端 `canSave`。
public func canSave(_ state: EditorCanvasState) -> Bool {
    return !state.isSaving && !state.isPhotoLoading
}

/// 是否处于交互态（任一工具激活，排除 none）。对应源端 `isInteracting`。
public func isInteracting(_ state: EditorCanvasState) -> Bool {
    return state.tool != .none
}

/// 照片是否已就绪（加载完成）。对应源端 `isReady`。
public func isReady(_ state: EditorCanvasState) -> Bool {
    return !state.isPhotoLoading
}
