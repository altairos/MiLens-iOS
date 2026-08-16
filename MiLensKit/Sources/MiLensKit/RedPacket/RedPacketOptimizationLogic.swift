import Foundation

// RedPacketOptimizationLogic — 红包封面智能优化纯逻辑（对应红包封面开发计划 §4）。
//
// "智能优化"一次最多执行：
// - 宠物位置适配（移入安全区）
// - 文字安全区移动
//
// 像素级调整（亮度/对比度/锐度）需要滤镜管线支撑，落地前不在摘要中
// 声称已执行（诚实标注：摘要只报告真实发生的变化）。
//
// 优化前后可切换并可撤销。
// 文案使用"建议优化""已为你调整"，不承诺平台审核通过。

// MARK: - 优化参数

/// 智能优化参数（对图层的轻微调整）。仅含可真实落地的图层级调整。
public struct RedPacketOptimizationResult: Equatable, Sendable {
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
        petNewX: Double? = nil,
        petNewY: Double? = nil,
        textNewX: Double? = nil,
        textNewY: Double? = nil,
        summaryKeys: [String] = []
    ) {
        self.petNewX = petNewX
        self.petNewY = petNewY
        self.textNewX = textNewX
        self.textNewY = textNewY
        self.summaryKeys = summaryKeys
    }

    /// 是否有任何优化。
    public var hasOptimizations: Bool {
        petNewX != nil || textNewX != nil
    }
}

// MARK: - 智能优化纯逻辑

/// 红包封面智能优化（对应红包封面开发计划 §4）。
public enum RedPacketOptimizationLogic {

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
                // 清晰度需像素级滤镜重新处理原图，图层级优化无法修复；
                // 不自动调整也不在摘要声称已锐化（诚实标注）。
                break
            case .brightness:
                // 亮度/过曝需像素级滤镜；用 opacity 冒充亮度是伪修复
                // （不透明度变化是变透明不是变亮），不自动处理。
                break
            case .composition:
                // 宠物位置适配到安全区中心（只依赖图层是否存在，不读图层内容）
                if petLayer != nil, item.level == .error {
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
                // 文字移入安全区（只依赖图层是否存在，不读图层内容）
                if textLayer != nil, item.level == .error {
                    let safeCenterX = template.defaultTextPosition.x
                    let safeCenterY = template.defaultTextPosition.y
                    result.textNewX = safeCenterX
                    result.textNewY = safeCenterY
                    summaryKeys.append("redpacket.optimize.textRepositioned")
                }
            }
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
            case .text:
                if let newX = optimization.textNewX { copy.x = newX }
                if let newY = optimization.textNewY { copy.y = newY }
            default:
                break
            }
            return copy
        }
    }

}
