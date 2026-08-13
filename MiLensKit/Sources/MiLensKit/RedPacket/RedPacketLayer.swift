import Foundation

// RedPacketLayer — 红包封面图层模型（独立于 EditorLayer，对应红包封面开发计划 §3.1）。
//
// 渲染顺序固定为：背景层 → 宠物抠图层 → 配饰/文本层 → 前景层。
// 背景与前景属于模板层（不可选择），配饰和文本分别建模，不合并为一张可编辑图片。
// 坐标统一使用 957×1278 设计画布坐标，x/y 为图层中心点坐标。

// MARK: - 图层类型

/// 红包图层种类。对应红包封面开发计划 §3.1 图层结构。
public enum RedPacketLayerKind: String, Codable, Sendable, CaseIterable {
    /// 模板背景层（固定、不可选择）。
    case templateBackground
    /// 宠物抠图层（可移动、缩放、旋转）。
    case pet
    /// 配饰图层（可移动、缩放、旋转、删除）。
    case accessory
    /// 文本图层（可移动、缩放、旋转、编辑内容）。
    case text
    /// 模板前景层（固定、不可选择）。
    case templateForeground

    /// 是否为模板固定层（不可选择）。
    public var isTemplateFixed: Bool {
        self == .templateBackground || self == .templateForeground
    }

    /// 是否为用户可编辑图层（可选择、移动、删除）。
    public var isUserEditable: Bool {
        !isTemplateFixed
    }
}

// MARK: - 文本样式

/// 文本风格（内容与样式分离，对应红包封面开发计划 §3.3）。
public struct RedPacketTextStyle: Codable, Equatable, Sendable {
    /// 字体族名（系统字体或自定义字体 PostScript 名）。
    public var fontFamily: String
    /// 字号比例（相对画布宽度，导出时 fontSize = fontSizeRatio × coverImageWidth）。
    public var fontSizeRatio: Double
    /// 文字颜色（十六进制，如 "#FFFFFF"）。
    public var colorHex: String
    /// 描边颜色（十六进制）。
    public var strokeColorHex: String
    /// 描边宽度比例（相对画布宽度，0 = 无描边）。
    public var strokeWidthRatio: Double
    /// 对齐方式。
    public var alignment: RedPacketTextAlignment
    /// 文字阴影颜色（十六进制，无阴影留空）。
    public var shadowColorHex: String

    public init(
        fontFamily: String,
        fontSizeRatio: Double,
        colorHex: String = "#FFFFFF",
        strokeColorHex: String = "#000000",
        strokeWidthRatio: Double = 0,
        alignment: RedPacketTextAlignment = .leading,
        shadowColorHex: String = ""
    ) {
        self.fontFamily = fontFamily
        self.fontSizeRatio = fontSizeRatio
        self.colorHex = colorHex
        self.strokeColorHex = strokeColorHex
        self.strokeWidthRatio = strokeWidthRatio
        self.alignment = alignment
        self.shadowColorHex = shadowColorHex
    }
}

/// 文本对齐方式。
public enum RedPacketTextAlignment: String, Codable, Sendable, CaseIterable {
    case leading
    case center
    case trailing
}

// MARK: - 文本风格预置

/// 预置文本风格（对应红包封面开发计划 §3.3：新年喜庆、温柔手写、极简印章、金色祝福、宠物昵称）。
public enum RedPacketTextStylePreset: String, Codable, Sendable, CaseIterable {
    case festive       // 新年喜庆
    case handwriting   // 温柔手写
    case seal          // 极简印章
    case goldBlessing  // 金色祝福
    case petName       // 宠物昵称

    /// 预置样式定义。
    public var style: RedPacketTextStyle {
        switch self {
        case .festive:
            // 新年喜庆：金描边白字
            return RedPacketTextStyle(
                fontFamily: "LXGWWenKai-Bold",
                fontSizeRatio: 0.06,
                colorHex: "#FFFFFF",
                strokeColorHex: "#C8102E",
                strokeWidthRatio: 0.006,
                shadowColorHex: "#000000"
            )
        case .handwriting:
            // 温柔手写：手写体棕字
            return RedPacketTextStyle(
                fontFamily: "LXGWWenKai-Regular",
                fontSizeRatio: 0.055,
                colorHex: "#FFF8E7",
                strokeColorHex: "#8B4513",
                strokeWidthRatio: 0.002,
                alignment: .center
            )
        case .seal:
            // 极简印章：白字红底风格
            return RedPacketTextStyle(
                fontFamily: "Songti-SC-Bold",
                fontSizeRatio: 0.05,
                colorHex: "#FFFFFF",
                strokeColorHex: "#9B1B30",
                strokeWidthRatio: 0.004,
                alignment: .center
            )
        case .goldBlessing:
            // 金色祝福：金字深描边
            return RedPacketTextStyle(
                fontFamily: "LXGWWenKai-Bold",
                fontSizeRatio: 0.065,
                colorHex: "#FFD700",
                strokeColorHex: "#8B0000",
                strokeWidthRatio: 0.005,
                alignment: .center
            )
        case .petName:
            // 宠物昵称：简洁白字
            return RedPacketTextStyle(
                fontFamily: "LXGWWenKai-Regular",
                fontSizeRatio: 0.05,
                colorHex: "#FFFFFF",
                strokeColorHex: "#333333",
                strokeWidthRatio: 0.003,
                alignment: .leading
            )
        }
    }
}

// MARK: - 图层

/// 红包封面图层。独立于 EditorLayer（对应红包封面开发计划 §3.1）。
/// 不持有运行时图像资源（CGImage/UIImage），资源保存为文件路径或资源 ID。
public struct RedPacketLayer: Identifiable, Equatable, Codable, Sendable {

    /// 图层唯一标识。
    public var id: String
    /// 图层种类。
    public var kind: RedPacketLayerKind
    /// z 序（渲染顺序：大值在上层）。
    public var zIndex: Int

    // MARK: 公共几何属性（画布坐标，中心点）
    /// 中心点 x 坐标（画布坐标，0–957）。
    public var x: Double
    /// 中心点 y 坐标（画布坐标，0–1278）。
    public var y: Double
    /// 缩放（1.0 = 原始尺寸）。
    public var scale: Double
    /// 旋转角度（度，0–360）。
    public var rotation: Double
    /// 不透明度（0–1）。
    public var opacity: Double
    /// 是否可见。
    public var visible: Bool
    /// 图层逻辑宽度（画布坐标，用于命中测试）。
    public var width: Double
    /// 图层逻辑高度（画布坐标，用于命中测试）。
    public var height: Double

    // MARK: 图片层属性（kind == .pet / .accessory 时有效）
    /// 资源引用（Asset Catalog 名或文件路径）。
    public var resourceRef: String
    /// 宠物层专用：抠图蒙版路径（未来扩展）。
    public var mattePath: String?

    // MARK: 文本层属性（kind == .text 时有效）
    /// 文本内容。
    public var text: String
    /// 文本风格 ID（对应 RedPacketTextStylePreset.rawValue）。
    public var styleID: String

    public init(
        id: String,
        kind: RedPacketLayerKind,
        zIndex: Int = 0,
        x: Double = 0,
        y: Double = 0,
        scale: Double = 1.0,
        rotation: Double = 0,
        opacity: Double = 1.0,
        visible: Bool = true,
        width: Double = 0,
        height: Double = 0,
        resourceRef: String = "",
        mattePath: String? = nil,
        text: String = "",
        styleID: String = RedPacketTextStylePreset.festive.rawValue
    ) {
        self.id = id
        self.kind = kind
        self.zIndex = zIndex
        self.x = x
        self.y = y
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
        self.visible = visible
        self.width = width
        self.height = height
        self.resourceRef = resourceRef
        self.mattePath = mattePath
        self.text = text
        self.styleID = styleID
    }
}

// MARK: - 图层工厂

/// 图层 ID 序列号（并发安全）。
private nonisolated(unsafe) var _rpLayerIdCounter = 0
private let _rpLayerIdLock = NSLock()

/// 生成唯一红包图层 ID。
public func generateRedPacketLayerId() -> String {
    _rpLayerIdLock.lock()
    _rpLayerIdCounter += 1
    let seq = _rpLayerIdCounter
    _rpLayerIdLock.unlock()
    return "rp_layer_\(Int(Date().timeIntervalSince1970 * 1000))_\(seq)"
}

/// 创建模板背景层。
public func makeRedPacketTemplateBackgroundLayer() -> RedPacketLayer {
    let w = Double(WeChatRedPacketSpec.coverImageWidth)
    let h = Double(WeChatRedPacketSpec.coverImageHeight)
    return RedPacketLayer(
        id: generateRedPacketLayerId(),
        kind: .templateBackground,
        zIndex: 0,
        x: w / 2, y: h / 2,
        width: w, height: h
    )
}

/// 创建模板前景层。
public func makeRedPacketTemplateForegroundLayer() -> RedPacketLayer {
    let w = Double(WeChatRedPacketSpec.coverImageWidth)
    let h = Double(WeChatRedPacketSpec.coverImageHeight)
    return RedPacketLayer(
        id: generateRedPacketLayerId(),
        kind: .templateForeground,
        zIndex: 999,
        x: w / 2, y: h / 2,
        width: w, height: h
    )
}

/// 创建宠物抠图层（默认隐藏，加载抠图后显示）。
public func makeRedPacketPetLayer(
    x: Double, y: Double, scale: Double = 1.0,
    width: Double = 0, height: Double = 0,
    resourceRef: String = "", mattePath: String? = nil
) -> RedPacketLayer {
    return RedPacketLayer(
        id: generateRedPacketLayerId(),
        kind: .pet,
        zIndex: 100,
        x: x, y: y,
        scale: scale,
        width: width, height: height,
        resourceRef: resourceRef,
        mattePath: mattePath
    )
}

/// 创建文本图层。
public func makeRedPacketTextLayer(
    text: String, x: Double, y: Double,
    stylePreset: RedPacketTextStylePreset = .festive,
    width: Double = 400, height: Double = 60
) -> RedPacketLayer {
    return RedPacketLayer(
        id: generateRedPacketLayerId(),
        kind: .text,
        zIndex: 200,
        x: x, y: y,
        width: width, height: height,
        text: text,
        styleID: stylePreset.rawValue
    )
}
