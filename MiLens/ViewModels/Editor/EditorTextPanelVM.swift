//  EditorTextPanelVM —— 文字工具子状态（M2 拆分，对应源端 EditorTextController）。
//  添加模式（输入/字号/颜色/描边）与选中文字图层编辑模式；决策走 MiLensKit EditorTextToolLogic。

import Foundation
import MiLensKit
import Observation

@MainActor
@Observable
final class EditorTextPanelVM {

    private unowned let owner: EditorViewModel
    private let document: EditorDocumentController

    init(owner: EditorViewModel) {
        self.owner = owner
        self.document = owner.document
    }

    // 添加面板输入（Slider/Toggle 绑定）
    var textInput = ""
    var textFontSize: Double = DEFAULT_TEXT_FONT_SIZE
    var textColor: String = DEFAULT_TEXT_COLOR
    var textStrokeEnabled: Bool = DEFAULT_TEXT_STROKE_ENABLED
    // 选中图层编辑面板（跟随选中图层）
    private(set) var selectedTextFontSize: Double = DEFAULT_TEXT_FONT_SIZE
    private(set) var selectedTextColor: String = DEFAULT_TEXT_COLOR

    /// 选中文字图层的编辑面板是否可见。
    var showEditPanel: Bool {
        shouldShowTextLayerEditPanel(
            activeLayerType: document.activeLayer?.type.rawValue ?? "",
            currentTool: owner.tool
        )
    }

    func add() {
        guard canAddTextLayer(textInput), owner.canvasSize.width > 0 else { return }
        var layer = createTextLayer(
            text: textInput, x: owner.canvasSize.width / 2, y: owner.canvasSize.height / 2,
            fontSize: textFontSize
        )
        layer.fontColor = textColor
        layer.strokeWidth = resolveStrokeWidth(textStrokeEnabled)
        document.add(&layer)
        document.pushHistory()
        textInput = ""
        owner.syncState()
    }

    func updateActiveText(fontSize: Double, color: String) {
        guard let layer = document.activeLayer,
              isTextLayerEditable(layer.type.rawValue) else { return }
        document.updateLayer(layer.id) { l in
            l.fontSize = fontSize
            l.fontColor = color
        }
        selectedTextFontSize = fontSize
        selectedTextColor = color
        document.pushHistory()
        owner.syncState()
    }

    func deleteActiveLayer() {
        guard let layer = document.activeLayer, layer.type != .photo else { return }
        document.remove(layer.id)
        document.pushHistory()
        owner.syncState()
    }
}
