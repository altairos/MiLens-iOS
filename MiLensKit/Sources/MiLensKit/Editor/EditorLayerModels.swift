import Foundation

// EditorLayerModels — 编辑器图层类型定义。
// 翻译自源端 entry/.../editor/LayerModels.ets（137 行）。
//
// 架构差异：
// - 源端 ImageLayer.pixelMap 为 image.PixelMap（ArkUI 运行时资源）。
// - iOS 纯逻辑层不含 CGImage（App-only），用可选泛型或省略。
//   App 层在 ViewModel 中持有 CGImage?, 此处只定义可单测的几何/属性字段。

/// 图层类型。对应源端 `LayerType`。
public enum EditorLayerType: String, Sendable {
    case photo = "photo"
    case frame = "frame"
    case sticker = "sticker"
    case text = "text"
}

/// 图层公共属性。对应源端 `Layer` 接口。
/// 不含 pixelMap / sharpenBase 等运行时图像资源（由 App 层 ViewModel 持有）。
public struct EditorLayer: Identifiable, Equatable, Sendable {
    public var id: String
    public var type: EditorLayerType
    public var zIndex: Int
    public var visible: Bool
    public var x: Double
    public var y: Double
    public var scale: Double
    public var rotation: Double
    public var opacity: Double
    public var flipX: Bool
    public var flipY: Bool

    // ImageLayer 字段（type == .photo/.frame/.sticker 时有效）
    public var width: Double
    public var height: Double
    public var resourcePath: String
    public var hasAlpha: Bool
    public var adjustments: EditorColorAdjustments

    // TextLayer 字段（type == .text 时有效）
    public var text: String
    public var fontSize: Double
    public var fontFamily: String
    public var fontColor: String
    public var strokeWidth: Double
    public var strokeColor: String
    public var shadowOffsetX: Double
    public var shadowOffsetY: Double
    public var shadowBlur: Double
    public var shadowColor: String
    public var maxWidth: Double

    public init(id: String, type: EditorLayerType, zIndex: Int = 0, visible: Bool = true,
                x: Double = 0, y: Double = 0, scale: Double = 1.0, rotation: Double = 0,
                opacity: Double = 1.0, flipX: Bool = false, flipY: Bool = false,
                width: Double = 0, height: Double = 0, resourcePath: String = "",
                hasAlpha: Bool = false,
                adjustments: EditorColorAdjustments = NEUTRAL_EDITOR_ADJUSTMENTS,
                text: String = "", fontSize: Double = 32, fontFamily: String = "sans-serif",
                fontColor: String = "#FFFFFF", strokeWidth: Double = 2,
                strokeColor: String = "#000000",
                shadowOffsetX: Double = 0, shadowOffsetY: Double = 0,
                shadowBlur: Double = 0, shadowColor: String = "#000000",
                maxWidth: Double = 400) {
        self.id = id; self.type = type; self.zIndex = zIndex; self.visible = visible
        self.x = x; self.y = y; self.scale = scale; self.rotation = rotation
        self.opacity = opacity; self.flipX = flipX; self.flipY = flipY
        self.width = width; self.height = height; self.resourcePath = resourcePath
        self.hasAlpha = hasAlpha; self.adjustments = adjustments
        self.text = text; self.fontSize = fontSize; self.fontFamily = fontFamily
        self.fontColor = fontColor; self.strokeWidth = strokeWidth; self.strokeColor = strokeColor
        self.shadowOffsetX = shadowOffsetX; self.shadowOffsetY = shadowOffsetY
        self.shadowBlur = shadowBlur; self.shadowColor = shadowColor; self.maxWidth = maxWidth
    }
}

// MARK: - 工厂函数

/// 图层 ID 序列号。并发安全：仅经 layerIdLock 访问（strict concurrency 下的显式声明）。
private nonisolated(unsafe) var _editorLayerIdCounter = 0
private let _editorLayerIdLock = NSLock()

/// 生成唯一图层 ID。对应源端 `generateId`。
public func generateEditorLayerId() -> String {
    _editorLayerIdLock.lock()
    _editorLayerIdCounter += 1
    let seq = _editorLayerIdCounter
    _editorLayerIdLock.unlock()
    return "layer_\(Int(Date().timeIntervalSince1970 * 1000))_\(seq)"
}

/// 创建图片图层。对应源端 `createImageLayer`。
/// 注意：不包含 PixelMap，App 层在 ViewModel 中单独管理图像资源。
public func createImageLayer(
    type: EditorLayerType, width: Double, height: Double,
    resourcePath: String = "", x: Double = 0, y: Double = 0
) -> EditorLayer {
    return EditorLayer(
        id: generateEditorLayerId(), type: type,
        x: x, y: y, width: width, height: height, resourcePath: resourcePath)
}

/// 创建文字图层。对应源端 `createTextLayer`。
public func createTextLayer(text: String, x: Double = 0, y: Double = 0, fontSize: Double = 32) -> EditorLayer {
    return EditorLayer(
        id: generateEditorLayerId(), type: .text,
        x: x, y: y, text: text, fontSize: fontSize)
}
