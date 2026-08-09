//  EditorAdjustPanelVM —— 调色工具子状态（M2 拆分，对应源端 EditorAdjustController）。
//  5 滑块（亮度/对比度/饱和度/色温/锐化）+ 重置；决策走 MiLensKit EditorAdjustLogic。
//  锐化基于未锐化底图卷积后叠加调色渲染（对齐源端 releaseSharpenBase 语义）。

import Foundation
import MiLensKit
import Observation

@MainActor
@Observable
final class EditorAdjustPanelVM {

    private unowned let owner: EditorViewModel
    private let document: EditorDocumentController

    init(owner: EditorViewModel) {
        self.owner = owner
        self.document = owner.document
    }

    var state = EditorAdjustPanelState()
    /// 上次成功卷积后记录的锐化强度（resolveSharpnessApply 的 prev 基准；
    /// 对齐源端 releaseSharpenBase：撤销/重置后回到 0，不重复卷积）。
    var renderedSharpness = 0.0

    func onSliderChange(_ field: EditorAdjustField, value: Double, phase: EditorSliderGesturePhase) {
        let gesture = resolveSliderGesture(phase)
        if gesture.shouldBeginGesture { document.beginGesture() }

        switch field {
        case .brightness: state.brightness = value
        case .contrast: state.contrast = value
        case .saturation: state.saturation = value
        case .temperature: state.temperature = value
        case .sharpness: state.sharpness = value
        }

        guard let layer = document.photoLayer() else { return }
        if field == .sharpness {
            // 锐化需要卷积：写回图层值，仅 end/click 且强度变化时渲染（源端异步卷积语义）。
            // prev 基准是「上次渲染的强度」而非图层值，否则 begin/moving 已写回后 end 永不触发。
            let decision = resolveSharpnessApply(
                prevStrength: renderedSharpness, nextStrength: value, phase: phase
            )
            document.updateLayer(layer.id) { $0.adjustments.sharpness = value }
            document.pushHistory()
            if decision.shouldApply {
                renderedSharpness = decision.strength
                owner.refreshPhotoImage()
            }
        } else {
            apply()
        }
        owner.syncState()

        if gesture.shouldEndGesture { document.endGesture() }
    }

    func reset() {
        guard !isAdjustNeutral(state) else { return }
        state = defaultAdjustPanelState()
        if let layer = document.photoLayer() {
            document.updateLayer(layer.id) { $0.adjustments = NEUTRAL_EDITOR_ADJUSTMENTS }
        }
        document.pushHistory()
        owner.refreshPhotoImage()
        owner.syncState()
    }

    /// 像素级操作（裁剪/旋转）后锐化归零（基准内容变化）。
    func resetSharpness() {
        state.sharpness = 0
    }

    /// 把面板状态写回照片图层并渲染（实时预览；手势内 push 自动合并）。
    private func apply() {
        guard let layer = document.photoLayer() else { return }
        let adj = buildAdjustments(state)
        document.updateLayer(layer.id) { $0.adjustments = adj }
        document.pushHistory()
        owner.refreshPhotoImage()
    }

    /// 从照片图层回读面板（进入调色工具 / undo / redo 后同步，源端 syncAdjustmentsFromPhoto）。
    func syncFromLayer() {
        state = syncAdjustPanelState(document.photoLayer()?.adjustments ?? NEUTRAL_EDITOR_ADJUSTMENTS)
    }
}
