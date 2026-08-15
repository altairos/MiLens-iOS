//  EditorDocumentController —— 编辑器文档与历史协作对象（M2 拆分：对应源端 EditorPage.ets
//  的 document/history 编排层）。持有 EditorDocument + EditorHistory，提供图层增删改、
//  历史入栈/重置/撤销重做等原子操作；不持有 @Observable 状态（观察状态由 EditorViewModel
//  syncState() 从本控制器刷新，保持单一观察面）。

import CoreGraphics
import Foundation
import MiLensKit

@MainActor
final class EditorDocumentController {

    private let document = EditorDocument()
    private let history = EditorHistory<String, Int>(maxDepth: 30)

    // MARK: - 只读快照

    var layers: [EditorLayer] { document.getLayers() }
    var activeLayer: EditorLayer? { document.activeLayer }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    /// 照片底图图层（文档内 zIndex 最低的 photo 图层）。
    func photoLayer() -> EditorLayer? {
        document.getLayers().first { $0.type == .photo }
    }

    // MARK: - 历史

    /// 当前快照（JSON）入历史；手势内自动合并。
    func pushHistory() {
        history.push(document.serialize() ?? "[]")
    }

    /// 像素级操作后：历史基线重置（iOS 差异，见 EditorViewModel 文件头注释）。
    func resetHistory() {
        history.initialize(document.serialize() ?? "[]")
    }

    /// 撤销：弹出 undo 栈顶快照恢复（对应源端 history.undo）。
    func undoHistory() {
        if let entry = history.undo() { document.restore(entry.snapshot) }
    }

    /// 重做：弹出 redo 栈顶快照恢复（对应源端 history.redo）。
    func redoHistory() {
        if let entry = history.redo() { document.restore(entry.snapshot) }
    }

    func beginGesture() { history.beginGesture() }
    func endGesture() { history.endGesture() }

    // MARK: - 文档操作

    func addPassive(_ layer: inout EditorLayer) {
        document.addPassive(&layer)
    }

    func add(_ layer: inout EditorLayer) {
        document.add(&layer)
    }

    func remove(_ id: String) {
        document.remove(id)
    }

    func select(_ id: String?) {
        document.select(id)
    }

    func updateLayer(_ id: String, _ mutate: (inout EditorLayer) -> Void) {
        document.updateLayer(id, mutate)
    }

    /// 点选命中：顶层优先（LayerGeometry.isPointInLayer）；底图与相框不可选中
    /// （frame 铺满画布会挡住全部点击，阻塞项6：仅 sticker/text 可命中）。
    func selectLayer(at point: CGPoint) {
        let hit = document.getLayers().reversed().first { layer in
            (layer.type == .sticker || layer.type == .text)
                && isPointInLayer(layer, tapX: point.x, tapY: point.y)
        }
        document.select(hit?.id)
    }

    /// 拖动活动图层（增量）：移动后应用中心吸附 + 中心 clamp（M2 质量项，规格 §4.3）。
    /// 返回吸附决策（View 据此绘制中心参考线）；nil = 无活动图层或画布无效（不吸附）。
    @discardableResult
    func moveActiveLayer(dx: Double, dy: Double, canvasSize: CGSize) -> LayerSnapResult? {
        guard let layer = document.activeLayer else { return nil }
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            document.updateLayer(layer.id) { l in
                l.x += dx
                l.y += dy
            }
            return nil
        }
        var snap: LayerSnapResult?
        document.updateLayer(layer.id) { l in
            let result = snapAndClampLayerCenter(
                x: l.x + dx, y: l.y + dy,
                canvasW: Double(canvasSize.width), canvasH: Double(canvasSize.height))
            l.x = result.x
            l.y = result.y
            snap = result
        }
        return snap
    }

    /// 缩放活动图层：贴纸按视觉尺寸钳制（8%–70% 短边），其余维持 MIN/MAX_LAYER_SCALE。
    func scaleActiveLayer(by factor: Double, canvasSize: CGSize) {
        guard let layer = document.activeLayer else { return }
        let newScale: Double
        if layer.type == .sticker {
            newScale = clampStickerVisualScale(
                nativeW: layer.width, nativeH: layer.height,
                scale: layer.scale * factor,
                canvasW: Double(canvasSize.width), canvasH: Double(canvasSize.height)
            )
        } else {
            newScale = clampLayerScale(layer.scale * factor)
        }
        document.updateLayer(layer.id) { $0.scale = newScale }
    }

    func rotateActiveLayer(by degrees: Double) {
        guard let layer = document.activeLayer else { return }
        document.updateLayer(layer.id) { $0.rotation += degrees }
    }
}
