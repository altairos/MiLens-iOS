import Foundation

// EditorLayerGeometry — 图层几何计算纯逻辑。
// 翻译自源端 entry/.../editor/LayerGeometry.ets（210 行）。
//
// 与 EditorCropMath / EditorColorAdjust 同级，属于编辑器领域的可单测纯函数。
// 输入只读 EditorLayer 字段，不修改 layer 对象。

// MARK: - 常量

public let MIN_LAYER_SCALE: Double = 0.1
public let MAX_LAYER_SCALE: Double = 5.0
public let DEFAULT_SELECTION_COLOR: String = "#007DFF"
public let SELECTION_LINE_WIDTH: Double = 2
public let SELECTION_DASH_ON: Double = 6
public let SELECTION_DASH_OFF: Double = 4
public let CORNER_HANDLE_SIZE: Double = 8

// MARK: - 几何数据结构

/// 图层半宽/半高。对应源端 `LayerHalfSize`。
public struct EditorLayerHalfSize: Equatable, Sendable {
    public var halfW: Double
    public var halfH: Double

    public init(halfW: Double, halfH: Double) {
        self.halfW = halfW; self.halfH = halfH
    }
}

/// 图层本地坐标。对应源端 `LocalPoint`。
public struct EditorLocalPoint: Equatable, Sendable {
    public var localX: Double
    public var localY: Double

    public init(localX: Double, localY: Double) {
        self.localX = localX; self.localY = localY
    }
}

/// 选择框几何参数。对应源端 `SelectionBoxGeometry`。
public struct EditorSelectionBoxGeometry: Equatable, Sendable {
    public var halfW: Double
    public var halfH: Double
    public var scale: Double
    public var lineWidth: Double
    public var dashPattern: [Double]
    public var handleSize: Double
    /// 4 个角的本地坐标 [x, y]，顺序：左上/右上/右下/左下。
    public var corners: [[Double]]

    public init(halfW: Double, halfH: Double, scale: Double, lineWidth: Double,
                dashPattern: [Double], handleSize: Double, corners: [[Double]]) {
        self.halfW = halfW; self.halfH = halfH; self.scale = scale
        self.lineWidth = lineWidth; self.dashPattern = dashPattern
        self.handleSize = handleSize; self.corners = corners
    }
}

/// 照片导出区域。对应源端 `PhotoExportRegion`。
public struct EditorPhotoExportRegion: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    public var valid: Bool

    public init(x: Double, y: Double, w: Double, h: Double, valid: Bool) {
        self.x = x; self.y = y; self.w = w; self.h = h; self.valid = valid
    }
}

// MARK: - 纯函数

/// 计算图层的半宽 / 半高（已乘 scale）。对应源端 `computeLayerHalfSize`。
/// TextLayer：宽度取 maxWidth，高度取 fontSize。ImageLayer：宽度取 width，高度取 height。
/// NaN/非正尺寸归一为 fallback（text: 200/32, image: 100/100）。
public func computeLayerHalfSize(_ layer: EditorLayer) -> EditorLayerHalfSize {
    if layer.type == .text {
        let w = layer.maxWidth.isFinite && layer.maxWidth > 0 ? layer.maxWidth : 200
        let h = layer.fontSize.isFinite && layer.fontSize > 0 ? layer.fontSize : 32
        return EditorLayerHalfSize(halfW: w * layer.scale / 2, halfH: h * layer.scale / 2)
    } else {
        let w = layer.width.isFinite && layer.width > 0 ? layer.width : 100
        let h = layer.height.isFinite && layer.height > 0 ? layer.height : 100
        return EditorLayerHalfSize(halfW: w * layer.scale / 2, halfH: h * layer.scale / 2)
    }
}

/// 把画布坐标反变换到图层本地坐标。对应源端 `rotatePointToLocal`。
public func rotatePointToLocal(
    layerX: Double, layerY: Double, rotationDeg: Double,
    tapX: Double, tapY: Double
) -> EditorLocalPoint {
    let safeRotation = rotationDeg.isFinite ? rotationDeg : 0
    let rad = -safeRotation * .pi / 180
    let dx = tapX - layerX
    let dy = tapY - layerY
    let cosR = cos(rad)
    let sinR = sin(rad)
    return EditorLocalPoint(
        localX: dx * cosR - dy * sinR,
        localY: dx * sinR + dy * cosR)
}

/// 判断点是否落在图层边界内。对应源端 `isPointInLayer`。
public func isPointInLayer(_ layer: EditorLayer, tapX: Double, tapY: Double) -> Bool {
    if !layer.visible { return false }
    let half = computeLayerHalfSize(layer)
    if half.halfW <= 0 || half.halfH <= 0 { return false }
    let local = rotatePointToLocal(layerX: layer.x, layerY: layer.y,
                                   rotationDeg: layer.rotation, tapX: tapX, tapY: tapY)
    return abs(local.localX) <= half.halfW && abs(local.localY) <= half.halfH
}

/// 把 scale clamp 到 [MIN_LAYER_SCALE, MAX_LAYER_SCALE]。对应源端 `clampLayerScale`。
public func clampLayerScale(_ scale: Double) -> Double {
    if !scale.isFinite { return MIN_LAYER_SCALE }
    return max(MIN_LAYER_SCALE, min(MAX_LAYER_SCALE, scale))
}

/// 计算选择框的全部几何参数。对应源端 `computeSelectionBoxGeometry`。
public func computeSelectionBoxGeometry(_ layer: EditorLayer) -> EditorSelectionBoxGeometry {
    let half = computeLayerHalfSize(layer)
    let safeScale = layer.scale > 0 ? layer.scale : 1
    return EditorSelectionBoxGeometry(
        halfW: half.halfW,
        halfH: half.halfH,
        scale: safeScale,
        lineWidth: SELECTION_LINE_WIDTH / safeScale,
        dashPattern: [SELECTION_DASH_ON / safeScale, SELECTION_DASH_OFF / safeScale],
        handleSize: CORNER_HANDLE_SIZE / safeScale,
        corners: [
            [-half.halfW, -half.halfH],
            [half.halfW, -half.halfH],
            [half.halfW, half.halfH],
            [-half.halfW, half.halfH],
        ])
}

/// 根据照片图层的位置和尺寸计算导出区域。对应源端 `computePhotoExportRegion`。
public func computePhotoExportRegion(
    photoLayer: EditorLayer, canvasW: Double, canvasH: Double
) -> EditorPhotoExportRegion {
    let zero = EditorPhotoExportRegion(x: 0, y: 0, w: 0, h: 0, valid: false)
    if !canvasW.isFinite || !canvasH.isFinite || canvasW <= 0 || canvasH <= 0 { return zero }

    let pw = photoLayer.width * photoLayer.scale
    let ph = photoLayer.height * photoLayer.scale
    if !pw.isFinite || !ph.isFinite || pw <= 0 || ph <= 0 { return zero }

    let px = photoLayer.x - pw / 2
    let py = photoLayer.y - ph / 2
    let xStart = max(0, px)
    let yStart = max(0, py)
    let xEnd = min(canvasW, px + pw)
    let yEnd = min(canvasH, py + ph)
    let w = xEnd - xStart
    let h = yEnd - yStart
    if w <= 0 || h <= 0 { return zero }
    return EditorPhotoExportRegion(x: xStart, y: yStart, w: w, h: h, valid: true)
}
