import Foundation

// 色彩相关值类型。翻译自源端 shared/.../bead/BeadTypes.ets（LabColor / XyzColor /
// NearestColorResult）与 BeadColor 的最小定义。后续 BeadPalette 模块会扩展更多字段。

/// sRGB 整数色彩（0–255 通道）。
public struct RGBColor: Equatable, Sendable {
    public var r: Int
    public var g: Int
    public var b: Int

    public init(_ r: Int, _ g: Int, _ b: Int) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// CIELAB 色彩值。对应源端 `LabColor`。
public struct LabColor: Equatable, Sendable {
    public var L: Double
    public var a: Double
    public var b: Double

    public init(L: Double, a: Double, b: Double) {
        self.L = L
        self.a = a
        self.b = b
    }
}

/// XYZ 色彩值（D65 白点）。对应源端 `XyzColor`。
public struct XyzColor: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// 最近色匹配结果。对应源端 `NearestColorResult`。
public struct NearestColorResult: Equatable, Sendable {
    public var index: Int
    public var distance: Double

    public init(index: Int, distance: Double) {
        self.index = index
        self.distance = distance
    }
}

/// 单个拼豆颜色定义。对应源端 `BeadColor` 的最小迁移；后续 BeadPalette 模块会补全
/// previewRgb/printRgb/tags 等字段。当前仅色彩空间模块用到 rgb。
public struct BeadColor: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var rgb: RGBColor
    public var symbol: String
    public var brand: String

    public init(id: String, name: String, rgb: RGBColor, symbol: String, brand: String) {
        self.id = id
        self.name = name
        self.rgb = rgb
        self.symbol = symbol
        self.brand = brand
    }
}
