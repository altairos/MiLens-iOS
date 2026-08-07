import Foundation

// 拼豆图纸相关的结构与类型。翻译自源端 shared/.../bead/BeadTypes.ets 的图纸子集。
// 随生成管线迁移逐步补全；当前覆盖 Geometry/Stats 模块所需类型。

// MARK: - 坐标 / 区域

/// 裁剪区域（图纸网格坐标）。对应源端 `CropArea`（字段 w/h）。
public struct CropArea: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var w: Int
    public var h: Int

    public init(x: Int, y: Int, w: Int, h: Int) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

/// 源图像裁剪矩形（像素坐标）。对应源端 `CropRect`（字段 width/height）。
public struct CropRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// MARK: - 主体上下文

/// 可选主体上下文；mask 尺寸与输入 RGBA 一致。对应源端 `BeadSubjectContext`。
/// Geometry/Stats 模块仅用到 bbox；mask/pose 留待生成管线接入。
public struct BeadSubjectContext: Sendable {
    public var bbox: CropRect
    public var mask: [UInt8]?
    public var attentionHeatmap: [Float]?
    public var pose: BeadPoseData?

    public init(bbox: CropRect, mask: [UInt8]? = nil, attentionHeatmap: [Float]? = nil, pose: BeadPoseData? = nil) {
        self.bbox = bbox
        self.mask = mask
        self.attentionHeatmap = attentionHeatmap
        self.pose = pose
    }
}

// MARK: - 用量统计

/// 每种颜色的统计数量。对应源端 `BeadColorCount`。
public struct BeadColorCount: Equatable, Sendable {
    public var colorId: String
    public var name: String
    public var symbol: String
    public var rgb: RGBColor
    public var count: Int
    public var suggestedBuyCount: Int

    public init(colorId: String, name: String, symbol: String, rgb: RGBColor, count: Int, suggestedBuyCount: Int) {
        self.colorId = colorId
        self.name = name
        self.symbol = symbol
        self.rgb = rgb
        self.count = count
        self.suggestedBuyCount = suggestedBuyCount
    }
}

// MARK: - 难度评分

/// 难度评分。对应源端 `BeadScore`。
/// `estimatedMinutes` 为 "min~max" 字符串格式。
public struct BeadScore: Equatable, Sendable {
    public var colorError: Double
    public var detailScore: Double
    public var estimatedDifficulty: Double
    public var level: String
    public var totalBeads: Int
    public var colorCount: Int
    public var estimatedMinutes: String

    public init(colorError: Double, detailScore: Double, estimatedDifficulty: Double,
                level: String, totalBeads: Int, colorCount: Int, estimatedMinutes: String) {
        self.colorError = colorError
        self.detailScore = detailScore
        self.estimatedDifficulty = estimatedDifficulty
        self.level = level
        self.totalBeads = totalBeads
        self.colorCount = colorCount
        self.estimatedMinutes = estimatedMinutes
    }
}

// MARK: - 诊断数据

/// 诊断数据 — 评估生成质量。对应源端 `PatternDiagnostics`。
/// 可选字段为 nil 表示该指标未计算（如 `refreshStructuralDiagnostics` 保留之前的色差值）。
public struct PatternDiagnostics: Equatable, Sendable {
    public var averageDeltaE: Double        // 平均色差
    public var maxDeltaE: Double            // 最大色差
    public var usedColorCount: Int          // 实际使用颜色数
    public var tinyColorCount: Int          // 使用量很少的颜色数量（< 阈值）
    public var isolatedPixelRatio: Double   // 孤立色点比例 (0~1)
    public var neutralHueShiftRatio: Double?  // 中性色被映射到有色相颜色的比例
    public var whiteToCoolRatio: Double?      // 高亮低饱和源色映射到冷色的比例
    public var outlineCoverageRatio: Double?  // 轮廓色占主体有效格比例
    public var blackCoverageRatio: Double?    // 黑/近黑占比

    public init(averageDeltaE: Double, maxDeltaE: Double, usedColorCount: Int,
                tinyColorCount: Int, isolatedPixelRatio: Double,
                neutralHueShiftRatio: Double? = nil, whiteToCoolRatio: Double? = nil,
                outlineCoverageRatio: Double? = nil, blackCoverageRatio: Double? = nil) {
        self.averageDeltaE = averageDeltaE
        self.maxDeltaE = maxDeltaE
        self.usedColorCount = usedColorCount
        self.tinyColorCount = tinyColorCount
        self.isolatedPixelRatio = isolatedPixelRatio
        self.neutralHueShiftRatio = neutralHueShiftRatio
        self.whiteToCoolRatio = whiteToCoolRatio
        self.outlineCoverageRatio = outlineCoverageRatio
        self.blackCoverageRatio = blackCoverageRatio
    }
}

// MARK: - 最小颜色使用量阈值

/// 计算最小颜色使用量阈值。对应源端 `minColorUsageThreshold`。
public func minColorUsageThreshold(_ totalBeads: Int) -> Int {
    return max(3, Int(Double(totalBeads) * 0.002))
}

// MARK: - Math 辅助

/// 对齐 JS `Math.floor`：向下取整后转 Int（负数也向下，如 floor(-0.5) = -1）。
@inline(__always)
func floorInt(_ x: Double) -> Int {
    Int(x.rounded(.down))
}

/// 对齐 JS `Math.ceil`：向上取整后转 Int。
@inline(__always)
func ceilInt(_ x: Double) -> Int {
    Int(x.rounded(.up))
}
