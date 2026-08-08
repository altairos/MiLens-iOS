import Foundation

// EditorTextToolLogic — 编辑器文字工具决策纯逻辑。
// 翻译自源端 entry/.../viewmodels/EditorTextToolViewModel.ets（76 行）。
//
// 从 EditorPage 文本工具簇抽出的决策纯逻辑，填补"工具 VM 四件套"之外的文本工具缺口
// （裁剪 EditorCropOverlay / 调色 EditorAdjustLogic / 工具 EditorToolLogic /
//   画布 EditorCanvasLogic 已抽完）。
//
// 覆盖的页面状态：
// - 文本添加工具：textInput / textFontSize / textColor / textStrokeEnabled
// - 选中文字图层编辑：selectedTextFontSize / selectedTextColor
// - 激活图层类型：activeLayerType（"" / "text" / ...）
//
// 架构差异：
// - 源端 TEXT_LAYER_TYPE 为字符串常量，与 LayerType.TEXT 的字符串值一致；
//   iOS 复用 EditorLayerType.text.rawValue（单一来源），EDITOR_TEXT_LAYER_TYPE 作为兼容常量。

/// 文本图层类型标识（与 EditorLayerType.text 的 rawValue 一致）。对应源端 `TEXT_LAYER_TYPE`。
public let EDITOR_TEXT_LAYER_TYPE: String = EditorLayerType.text.rawValue

/// 一次文字图层编辑的写入值。对应源端 `TextLayerEdit`。
public struct EditorTextLayerEdit: Equatable, Sendable {
    public let fontSize: Double
    public let color: String

    public init(fontSize: Double, color: String) {
        self.fontSize = fontSize
        self.color = color
    }
}

/// 判断文本添加工具是否激活。对应源端 `isTextToolActive`。
public func isTextToolActive(_ currentTool: EditorToolMode) -> Bool {
    return currentTool == .text
}

/// 文本输入是否可添加为图层（去空白后非空）。
/// 与 EditorPage.addText 的 `if (!textInput.trim()) return` 守卫一致。
/// 对应源端 `canAddTextLayer`。
public func canAddTextLayer(_ textInput: String) -> Bool {
    return !textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// 判断是否应显示"选中文字图层编辑面板"：
/// 激活图层是文本图层，且当前不在文本"添加"模式。
/// 对应源端 `shouldShowTextLayerEditPanel`。
public func shouldShowTextLayerEditPanel(activeLayerType: String, currentTool: EditorToolMode) -> Bool {
    return activeLayerType == EDITOR_TEXT_LAYER_TYPE && currentTool != .text
}

/// 组装一次文字图层编辑的写入值（fontSize + color）。
/// 对应源端 `resolveTextLayerEdit`。
public func resolveTextLayerEdit(fontSize: Double, color: String) -> EditorTextLayerEdit {
    return EditorTextLayerEdit(fontSize: fontSize, color: color)
}

/// 判断当前激活图层是否为可编辑的文本图层（updateActiveTextLayer 守卫）。
/// activeLayerType 为空串或非 text 时返回 false。对应源端 `isTextLayerEditable`。
public func isTextLayerEditable(_ activeLayerType: String) -> Bool {
    return activeLayerType == EDITOR_TEXT_LAYER_TYPE
}
