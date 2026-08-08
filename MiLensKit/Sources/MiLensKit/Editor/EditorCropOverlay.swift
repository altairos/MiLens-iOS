import Foundation

// EditorCropOverlay — 裁剪框覆盖层几何计算（纯逻辑）。
// 翻译自源端 entry/.../viewmodels/EditorCropViewModel.ets（137 行）。
//
// 从 EditorPage.drawCropOverlay 的裁剪框参数计算抽出，与"计算坐标"和"绘制 ctx 命令"分离，
// 使其可在无 SwiftUI/Canvas 运行时下单测。
//
// 与 EditorCropMath 的区别：
// - EditorCropMath 处理照片像素空间的 AABB 相交裁切（确认裁剪时计算实际裁切区域）。
// - 本模块处理画布空间的覆盖层 UI 几何（遮罩/三分线/角手柄），用于交互绘制。
//
// 坐标系：画布本地位移坐标系下的浮点坐标。

/// 裁剪框矩形。对应源端 `CropRect`（画布空间浮点坐标）。
public struct EditorCropRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    /// 全零矩形（无效输入时的兜底）。
    public static let zero = EditorCropRect(x: 0, y: 0, w: 0, h: 0)
}

/// 裁剪框四条遮罩矩形（画布减去裁剪框后的 4 块半透明遮罩区域）。
/// 对应源端 `CropOverlayMask`。
public struct EditorCropOverlayMask: Equatable, Sendable {
    public var top: EditorCropRect
    public var bottom: EditorCropRect
    public var left: EditorCropRect
    public var right: EditorCropRect
}

/// 九宫格辅助线坐标。对应源端 `CropThirdsLines`。
public struct EditorCropThirdsLines: Equatable, Sendable {
    /// 垂直辅助线的 x 坐标（2 条）。
    public var xLines: [Double]
    /// 水平辅助线的 y 坐标（2 条）。
    public var yLines: [Double]
}

/// 四角直角（L 形）角标位置 + 方向。对应源端 `CropCornerHandle`。
public struct EditorCropCornerHandle: Equatable, Sendable {
    /// 角点 x 坐标。
    public var x: Double
    /// 角点 y 坐标。
    public var y: Double
    /// 水平方向（1 = 向右，-1 = 向左）。
    public var dx: Int
    /// 垂直方向（1 = 向下，-1 = 向上）。
    public var dy: Int
}

// MARK: - 样式常量（唯一事实来源）

/// 遮罩颜色（半透明黑）。对应源端 `CROP_OVERLAY_COLOR`。
public let CROP_OVERLAY_COLOR: String = "rgba(0,0,0,0.5)"
/// 裁剪框边框颜色。对应源端 `CROP_BORDER_COLOR`。
public let CROP_BORDER_COLOR: String = "#FFFFFF"
/// 裁剪框边框宽度。对应源端 `CROP_BORDER_WIDTH`。
public let CROP_BORDER_WIDTH: Double = 2
/// 九宫格辅助线颜色。对应源端 `CROP_GRID_COLOR`。
public let CROP_GRID_COLOR: String = "rgba(255,255,255,0.3)"
/// 九宫格辅助线宽度。对应源端 `CROP_GRID_WIDTH`。
public let CROP_GRID_WIDTH: Double = 1
/// 角标直角线段长度。对应源端 `CROP_HANDLE_LENGTH`。
public let CROP_HANDLE_LENGTH: Double = 20
/// 角标直角线段宽度。对应源端 `CROP_HANDLE_WIDTH`。
public let CROP_HANDLE_WIDTH: Double = 4
/// 九宫格辅助线索引（1/3 与 2/3 位置）。对应源端 `CROP_THIRDS_INDICES`。
public let CROP_THIRDS_INDICES: [Double] = [1, 2]

// MARK: - 纯函数

/// 计算裁剪框外围 4 块半透明遮罩矩形。
/// 顺序：top（裁剪框上方全宽）/ bottom（下方全宽）/ left（左侧裁剪框高度）/ right（右侧裁剪框高度）。
/// 画布尺寸裁剪框相切时对应遮罩维度为 0。对应源端 `computeCropOverlayMask`。
public func computeCropOverlayMask(canvasW: Double, canvasH: Double, rect: EditorCropRect) -> EditorCropOverlayMask {
    return EditorCropOverlayMask(
        top: EditorCropRect(x: 0, y: 0, w: canvasW, h: rect.y),
        bottom: EditorCropRect(x: 0, y: rect.y + rect.h, w: canvasW, h: canvasH - rect.y - rect.h),
        left: EditorCropRect(x: 0, y: rect.y, w: rect.x, h: rect.h),
        right: EditorCropRect(x: rect.x + rect.w, y: rect.y, w: canvasW - rect.x - rect.w, h: rect.h))
}

/// 计算九宫格辅助线坐标（各 2 条）。
/// 坐标 = 裁剪框起点 + 裁剪框尺寸 × i / 3（i ∈ {1, 2}）。对应源端 `computeCropThirdsLines`。
public func computeCropThirdsLines(rect: EditorCropRect) -> EditorCropThirdsLines {
    var xLines: [Double] = []
    var yLines: [Double] = []
    for i in CROP_THIRDS_INDICES {
        xLines.append(rect.x + rect.w * i / 3)
        yLines.append(rect.y + rect.h * i / 3)
    }
    return EditorCropThirdsLines(xLines: xLines, yLines: yLines)
}

/// 计算四角 L 形角标位置 + 方向。
/// 顺序：左上(dx=1,dy=1) / 右上(dx=-1,dy=1) / 右下(dx=-1,dy=-1) / 左下(dx=1,dy=-1)。
/// 对应源端 `computeCropCornerHandles`。
public func computeCropCornerHandles(rect: EditorCropRect) -> [EditorCropCornerHandle] {
    return [
        EditorCropCornerHandle(x: rect.x, y: rect.y, dx: 1, dy: 1),
        EditorCropCornerHandle(x: rect.x + rect.w, y: rect.y, dx: -1, dy: 1),
        EditorCropCornerHandle(x: rect.x + rect.w, y: rect.y + rect.h, dx: -1, dy: -1),
        EditorCropCornerHandle(x: rect.x, y: rect.y + rect.h, dx: 1, dy: -1),
    ]
}

/// 把裁剪框 clamp 到画布范围内，确保 w/h 为非负。
/// - 画布尺寸为 NaN/Infinity 或非正时返回 zero。
/// - x/y 不小于 0；x+w 不超过 canvasW；y+h 不超过 canvasH。
/// - w/h 超过画布尺寸时截断；小于 0 时归 0。
/// 对应源端 `clampCropRect`。
public func clampCropRect(canvasW: Double, canvasH: Double, rect: EditorCropRect) -> EditorCropRect {
    if !canvasW.isFinite || !canvasH.isFinite || canvasW <= 0 || canvasH <= 0 {
        return .zero
    }
    if !rect.x.isFinite || !rect.y.isFinite || !rect.w.isFinite || !rect.h.isFinite {
        return .zero
    }
    var w = rect.w
    var h = rect.h
    if w < 0 { w = 0 }
    if h < 0 { h = 0 }
    if w > canvasW { w = canvasW }
    if h > canvasH { h = canvasH }
    var x = rect.x
    var y = rect.y
    if x < 0 { x = 0 }
    if y < 0 { y = 0 }
    if x > canvasW - w { x = canvasW - w }
    if y > canvasH - h { y = canvasH - h }
    return EditorCropRect(x: x, y: y, w: w, h: h)
}
