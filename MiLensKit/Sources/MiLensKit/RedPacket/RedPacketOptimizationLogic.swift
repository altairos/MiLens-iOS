import Foundation

// RedPacketOptimizationLogic — 红包封面智能优化纯逻辑（对应红包封面开发计划 §4）。
//
// "智能优化"一次最多执行：
// - 轻微亮度/对比度/锐度调整
// - 宠物位置适配（移入安全区）
// - 文字安全区移动
// - 模板预置的描边或阴影
//
// 优化前后可切换并可撤销。
// 文案使用"建议优化""已为你调整"，不承诺平台审核通过。

// MARK: - 优化参数

/// 智能优化参数（对图层的轻微调整）。
public struct RedPacketOptimizationResult: Equatable, Sendable {
    /// 亮度调整值（-0.2…+0.2，加到图层 opacity 或调色效果上）。
    public var brightnessAdjust: Double
    /// 对比度调整值（-0.15…+0.15）。
    public var contrastAdjust: Double
    /// 锐度调整值（0…1）。
    public var sharpnessAdjust: Double
    /// 宠物图层新 x 坐标（移入安全区，nil = 不移动）。
    public var petNewX: Double?
    /// 宠物图层新 y 坐标。
    public var petNewY: Double?
    /// 文本图层新 x 坐标（移入安全区，nil = 不移动）。
    public var textNewX: Double?
    /// 文本图层新 y 坐标。
    public var textNewY: Double?
    /// 应用的优化摘要（供 UI 反馈）。
    public var summaryKeys: [String]

    public init(
        brightnessAdjust: Double = 0,
        contrastAdjust: Double = 0,
        sharpnessAdjust: Double = 0,
        petNewX: Double? = nil,
        petNewY: Double? = nil,
        textNewX: Double? = nil,
        textNewY: Double? = nil,
        summaryKeys: [String] = []
    ) {
        self.brightnessAdjust = brightnessAdjust
        self.contrastAdjust = contrastAdjust
        self.sharpnessAdjust = sharpnessAdjust
        self.petNewX = petNewX
        self.petNewY = petNewY
        self.textNewX = textNewX
        self.textNewY = textNewY
        self.summaryKeys = summaryKeys
    }

    /// 是否有任何优化。
    public var hasOptimizations: Bool {
        brightnessAdjust != 0 || contrastAdjust != 0 || sharpnessAdjust > 0 ||
        petNewX != nil || textNewX != nil
    }
}

// MARK: - 智能优化纯逻辑

/// 红包封面智能优化（对应红包封面开发计划 §4）。
public enum RedPacketOptimizationLogic {

    // MARK: - 常量

    /// 亮度调整上限。
    public static let maxBrightnessAdjust: Double = 0.2
    /// 对比度调整上限。
    public static let maxContrastAdjust: Double = 0.15
    /// 锐度调整上限。
    public static let maxSharpnessAdjust: Double = 0.5

    // MARK: - 根据质量报告生成优化方案

    /// 根据质量报告和当前图层状态生成优化方案。
    /// 纯逻辑：输入只读数据，输出优化参数，不修改图层。
    public static func generateOptimization(
        report: RedPacketQualityReport,
        template: RedPacketTemplate,
        petLayer: RedPacketLayer?,
        textLayer: RedPacketLayer?
    ) -> RedPacketOptimizationResult {
        var result = RedPacketOptimizationResult()
        var summaryKeys: [String] = []

        for item in report.items where item.level.needsAction {
            switch item.dimension {
            case .clarity:
                // 轻微锐化
                if item.level == .warning || item.level == .error {
                    result.sharpnessAdjust = min(result.sharpnessAdjust + 0.3, maxSharpnessAdjust)
                    if !summaryKeys.contains("redpacket.optimize.sharpened") {
                        summaryKeys.append("redpacket.optimize.sharpened")
                    }
                }
            case .brightness:
                // 亮度调整
                if item.suggestionKey.contains("dark") {
                    result.brightnessAdjust = maxBrightnessAdjust
                    summaryKeys.append("redpacket.optimize.brightened")
                } else if item.suggestionKey.contains("overexposed") {
                    result.brightnessAdjust = -maxBrightnessAdjust
                    result.contrastAdjust = maxContrastAdjust
                    summaryKeys.append("redpacket.optimize.contrastAdjusted")
                }
            case .composition:
                // 宠物位置适配到安全区中心
                if let petLayer, item.level == .error {
                    let safeCenterX = template.safeZone.x * rpCanvasWidth +
                                      template.safeZone.width * rpCanvasWidth / 2
                    let safeCenterY = template.safeZone.y * rpCanvasHeight +
                                      template.safeZone.height * rpCanvasHeight / 2
                    result.petNewX = safeCenterX
                    result.petNewY = safeCenterY
                    summaryKeys.append("redpacket.optimize.petRepositioned")
                }
            case .cutout:
                // 抠图问题无法自动修复，只提示
                break
            case .readability:
                // 文字移入安全区
                if let textLayer, item.level == .error {
                    let safeCenterX = template.defaultTextPosition.x
                    let safeCenterY = template.defaultTextPosition.y
                    result.textNewX = safeCenterX
                    result.textNewY = safeCenterY
                    summaryKeys.append("redpacket.optimize.textRepositioned")
                }
            }
        }

        // 始终轻微提升对比度（模板预置优化）
        if result.contrastAdjust == 0 && report.hasIssues {
            result.contrastAdjust = 0.05
        }

        result.summaryKeys = summaryKeys
        return result
    }

    // MARK: - 应用优化到图层

    /// 把优化方案应用到图层列表，返回新图层列表（纯函数，不修改原数组）。
    public static func applyOptimization(
        _ optimization: RedPacketOptimizationResult,
        layers: [RedPacketLayer]
    ) -> [RedPacketLayer] {
        layers.map { layer in
            var copy = layer
            switch layer.kind {
            case .pet:
                if let newX = optimization.petNewX { copy.x = newX }
                if let newY = optimization.petNewY { copy.y = newY }
                // 亮度调整通过 opacity（Phase 3 简化）
                if optimization.brightnessAdjust != 0 {
                    copy.opacity = max(0.5, min(1.0, copy.opacity + optimization.brightnessAdjust))
                }
            case .text:
                if let newX = optimization.textNewX { copy.x = newX }
                if let newY = optimization.textNewY { copy.y = newY }
            default:
                break
            }
            return copy
        }
    }

    // MARK: - 默认优化（无质量报告时的温和优化）

    /// 生成默认温和优化（无质量报告时使用）。
    public static func defaultGentleOptimization(
        template: RedPacketTemplate,
        petLayer: RedPacketLayer?,
        textLayer: RedPacketLayer?
    ) -> RedPacketOptimizationResult {
        var result = RedPacketOptimizationResult()
        result.contrastAdjust = 0.05
        result.sharpnessAdjust = 0.15
        result.summaryKeys = ["redpacket.optimize.gentleApplied"]
        return result
    }
}
