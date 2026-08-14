import Foundation

// RedPacketQualityLogic — 红包封面质量检测纯逻辑（对应红包封面开发计划 §4）。
//
// 智能能力默认是"建议"，不静默改图。
// 质量报告覆盖 5 个维度：清晰度、亮度、构图、抠图、可读性。
// 每个维度产出检测结果 + 建议动作。
// 检测只做"可诊断"判定，不承诺平台审核通过。

// MARK: - 检测维度

/// 质量检测维度。
public enum RedPacketQualityDimension: String, Codable, Sendable, CaseIterable {
    case clarity     // 清晰度
    case brightness  // 亮度
    case composition // 构图
    case cutout      // 抠图
    case readability // 可读性
}

/// 检测结果级别。
public enum RedPacketQualityLevel: String, Codable, Sendable, CaseIterable {
    case pass     // 通过
    case warning  // 警告
    case error    // 问题

    /// 是否需要建议优化。
    public var needsAction: Bool { self != .pass }
}

// MARK: - 质量条目

/// 单个维度的检测结果。
public struct RedPacketQualityItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String { dimension.rawValue }
    /// 检测维度。
    public var dimension: RedPacketQualityDimension
    /// 结果级别。
    public var level: RedPacketQualityLevel
    /// 检测详情（供诊断）。
    public var detail: String
    /// 本地化 key（建议动作文案）。
    public var suggestionKey: String

    public init(
        dimension: RedPacketQualityDimension,
        level: RedPacketQualityLevel,
        detail: String,
        suggestionKey: String
    ) {
        self.dimension = dimension
        self.level = level
        self.detail = detail
        self.suggestionKey = suggestionKey
    }
}

// MARK: - 质量报告

/// 质量报告（汇总所有维度）。
public struct RedPacketQualityReport: Codable, Equatable, Sendable {
    /// 各维度检测结果。
    public var items: [RedPacketQualityItem]
    /// 生成时间。
    public var generatedAt: Date

    public init(items: [RedPacketQualityItem], generatedAt: Date = Date()) {
        self.items = items
        self.generatedAt = generatedAt
    }

    /// 总体是否有需要操作的问题。
    public var hasIssues: Bool {
        items.contains { $0.level.needsAction }
    }

    /// 错误级别数量。
    public var errorCount: Int {
        items.filter { $0.level == .error }.count
    }

    /// 警告级别数量。
    public var warningCount: Int {
        items.filter { $0.level == .warning }.count
    }

    /// 整体级别（取最差）。
    public var overallLevel: RedPacketQualityLevel {
        if errorCount > 0 { return .error }
        if warningCount > 0 { return .warning }
        return .pass
    }
}

// MARK: - 检测输入

/// 质量检测输入（纯数据，无 UIKit 依赖）。
public struct RedPacketQualityInput: Equatable, Sendable {
    /// 原图分辨率宽（像素）。
    public var imageWidth: Int
    /// 原图分辨率高（像素）。
    public var imageHeight: Int
    /// Laplacian 方差清晰度（0–∞，越高越清晰）。
    public var sharpness: Double
    /// 平均亮度（0–1）。
    public var averageBrightness: Double
    /// 宠物图层有效面积比例（0–1，主体占封面比例）。
    public var petCoverageRatio: Double
    /// 抠图边缘破碎度（0–1，越低越好）。
    public var cutoutEdgeRoughness: Double
    /// 宠物图层是否达到最低安全区覆盖率。
    public var petInSafeZone: Bool
    /// 文本内容（非空时检测可读性）。
    public var textContent: String
    /// 文本层是否在安全区内。
    public var textInSafeZone: Bool
    /// 文字颜色与背景对比度（0–1，越高越好）。
    public var textContrast: Double
    /// 原图像素指标是否成功提取。失败时不得用默认值伪装为通过。
    public var imageMetricsAvailable: Bool
    /// 阴影剪切比例（亮度 <= 8%）。
    public var shadowClippingRatio: Double
    /// 高光剪切比例（亮度 >= 95%）。
    public var highlightClippingRatio: Double
    /// 宠物图层旋转外接框仍在画布内的比例。
    public var petCanvasVisibleRatio: Double
    /// 宠物图层旋转外接框与模板安全区的覆盖比例。
    public var petSafeZoneCoverageRatio: Double
    /// 抠图蒙版指标是否成功提取。
    public var cutoutMetricsAvailable: Bool
    /// 蒙版前景占比。
    public var cutoutForegroundRatio: Double
    /// 蒙版中不属于最大连通主体的比例。
    public var cutoutFragmentationRatio: Double
    /// 前景接触蒙版边界的比例。
    public var cutoutBoundaryTouchRatio: Double

    public init(
        imageWidth: Int,
        imageHeight: Int,
        sharpness: Double,
        averageBrightness: Double,
        petCoverageRatio: Double,
        cutoutEdgeRoughness: Double,
        petInSafeZone: Bool,
        textContent: String,
        textInSafeZone: Bool,
        textContrast: Double,
        imageMetricsAvailable: Bool = true,
        shadowClippingRatio: Double = 0,
        highlightClippingRatio: Double = 0,
        petCanvasVisibleRatio: Double = 1,
        petSafeZoneCoverageRatio: Double = 1,
        cutoutMetricsAvailable: Bool = true,
        cutoutForegroundRatio: Double = 0.4,
        cutoutFragmentationRatio: Double = 0,
        cutoutBoundaryTouchRatio: Double = 0
    ) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.sharpness = sharpness
        self.averageBrightness = averageBrightness
        self.petCoverageRatio = petCoverageRatio
        self.cutoutEdgeRoughness = cutoutEdgeRoughness
        self.petInSafeZone = petInSafeZone
        self.textContent = textContent
        self.textInSafeZone = textInSafeZone
        self.textContrast = textContrast
        self.imageMetricsAvailable = imageMetricsAvailable
        self.shadowClippingRatio = shadowClippingRatio
        self.highlightClippingRatio = highlightClippingRatio
        self.petCanvasVisibleRatio = petCanvasVisibleRatio
        self.petSafeZoneCoverageRatio = petSafeZoneCoverageRatio
        self.cutoutMetricsAvailable = cutoutMetricsAvailable
        self.cutoutForegroundRatio = cutoutForegroundRatio
        self.cutoutFragmentationRatio = cutoutFragmentationRatio
        self.cutoutBoundaryTouchRatio = cutoutBoundaryTouchRatio
    }
}

// MARK: - 质量检测纯逻辑

/// 红包封面质量检测（对应红包封面开发计划 §4 表格）。
public enum RedPacketQualityLogic {

    // MARK: - 阈值常量

    /// 清晰度及格线（Laplacian 方差，低于此值为模糊）。
    public static let sharpnessThreshold: Double = 800
    /// 清晰度警告线。
    public static let sharpnessWarning: Double = 1500
    /// 最低分辨率（像素数，低于此值建议换高分辨率原图）。
    public static let minPixels: Int = 500_000
    /// 亮度过暗阈值（< 此值）。
    public static let brightnessDarkThreshold: Double = 0.2
    /// 亮度过曝阈值（> 此值）。
    public static let brightnessBrightThreshold: Double = 0.85
    /// 阴影/高光大面积剪切阈值。
    public static let clippingWarningMax: Double = 0.22
    /// 宠物面积过小阈值（< 此值）。
    public static let petCoverageMin: Double = 0.15
    /// 主体至少有多少比例仍在画布内。
    public static let petCanvasVisibleMin: Double = 0.92
    /// 抠图边缘破碎度阈值（> 此值）。
    public static let cutoutRoughnessMax: Double = 0.3
    /// 抠图蒙版中碎片像素占比上限。
    public static let cutoutFragmentationMax: Double = 0.12
    /// 抠图主体接触图像边缘的比例上限。
    public static let cutoutBoundaryTouchMax: Double = 0.18
    /// 蒙版前景合理占比范围。
    public static let cutoutForegroundMin: Double = 0.03
    public static let cutoutForegroundMax: Double = 0.92
    /// 文本对比度阈值（< 此值，可读性差）。
    public static let textContrastMin: Double = 0.4

    // MARK: - 完整检测

    /// 对输入执行全部 5 维检测，生成质量报告。
    public static func evaluate(_ input: RedPacketQualityInput) -> RedPacketQualityReport {
        let items: [RedPacketQualityItem] = [
            evaluateClarity(input),
            evaluateBrightness(input),
            evaluateComposition(input),
            evaluateCutout(input),
            evaluateReadability(input),
        ]
        return RedPacketQualityReport(items: items)
    }

    // MARK: - 清晰度

    /// 清晰度检测：原图分辨率、主体有效像素、模糊程度。
    public static func evaluateClarity(_ input: RedPacketQualityInput) -> RedPacketQualityItem {
        guard input.imageMetricsAvailable else {
            return RedPacketQualityItem(
                dimension: .clarity,
                level: .error,
                detail: "无法读取原图像素，尚未完成清晰度检查",
                suggestionKey: "redpacket.quality.clarity.unavailable"
            )
        }
        let pixels = input.imageWidth * input.imageHeight

        // 分辨率过低
        if pixels < minPixels {
            return RedPacketQualityItem(
                dimension: .clarity,
                level: .warning,
                detail: "原图分辨率 \(input.imageWidth)×\(input.imageHeight)（\(pixels) 像素），建议使用更高清的照片",
                suggestionKey: "redpacket.quality.clarity.resolution"
            )
        }

        // 模糊
        if input.sharpness < sharpnessThreshold {
            return RedPacketQualityItem(
                dimension: .clarity,
                level: .error,
                detail: "清晰度偏低（Laplacian 方差 \(Int(input.sharpness))），照片可能模糊",
                suggestionKey: "redpacket.quality.clarity.blur"
            )
        }

        // 轻微模糊警告
        if input.sharpness < sharpnessWarning {
            return RedPacketQualityItem(
                dimension: .clarity,
                level: .warning,
                detail: "清晰度一般（\(Int(input.sharpness))），建议更换更清晰的照片",
                suggestionKey: "redpacket.quality.clarity.soft"
            )
        }

        return RedPacketQualityItem(
            dimension: .clarity,
            level: .pass,
            detail: "清晰度良好",
            suggestionKey: ""
        )
    }

    // MARK: - 亮度

    /// 亮度检测：主体过暗、过曝、背景与主体亮度差。
    public static func evaluateBrightness(_ input: RedPacketQualityInput) -> RedPacketQualityItem {
        guard input.imageMetricsAvailable else {
            return RedPacketQualityItem(
                dimension: .brightness,
                level: .error,
                detail: "无法读取原图像素，尚未完成亮度检查",
                suggestionKey: "redpacket.quality.brightness.unavailable"
            )
        }
        if input.averageBrightness < brightnessDarkThreshold {
            return RedPacketQualityItem(
                dimension: .brightness,
                level: .warning,
                detail: "照片偏暗（亮度 \(Int(input.averageBrightness * 100))%），建议提亮",
                suggestionKey: "redpacket.quality.brightness.dark"
            )
        }

        if input.averageBrightness > brightnessBrightThreshold {
            return RedPacketQualityItem(
                dimension: .brightness,
                level: .warning,
                detail: "照片偏亮（亮度 \(Int(input.averageBrightness * 100))%），可能过曝",
                suggestionKey: "redpacket.quality.brightness.overexposed"
            )
        }

        if input.shadowClippingRatio > clippingWarningMax {
            return RedPacketQualityItem(
                dimension: .brightness,
                level: .warning,
                detail: "暗部细节较少（阴影剪切 \(Int(input.shadowClippingRatio * 100))%），建议适度提亮",
                suggestionKey: "redpacket.quality.brightness.dark"
            )
        }

        if input.highlightClippingRatio > clippingWarningMax {
            return RedPacketQualityItem(
                dimension: .brightness,
                level: .warning,
                detail: "高光细节较少（高光剪切 \(Int(input.highlightClippingRatio * 100))%），建议降低曝光",
                suggestionKey: "redpacket.quality.brightness.overexposed"
            )
        }

        return RedPacketQualityItem(
            dimension: .brightness,
            level: .pass,
            detail: "亮度适中",
            suggestionKey: ""
        )
    }

    // MARK: - 构图

    /// 构图检测：主体过小、被裁切、偏离安全区。
    public static func evaluateComposition(_ input: RedPacketQualityInput) -> RedPacketQualityItem {
        if input.petCanvasVisibleRatio < petCanvasVisibleMin {
            return RedPacketQualityItem(
                dimension: .composition,
                level: .error,
                detail: "宠物主体有 \(Int((1 - input.petCanvasVisibleRatio) * 100))% 超出画布，可能被裁切",
                suggestionKey: "redpacket.quality.composition.clipped"
            )
        }

        // 主体过小
        if input.petCoverageRatio < petCoverageMin {
            return RedPacketQualityItem(
                dimension: .composition,
                level: .warning,
                detail: "宠物主体占比偏小（\(Int(input.petCoverageRatio * 100))%），建议放大或移动",
                suggestionKey: "redpacket.quality.composition.small"
            )
        }

        // 偏离安全区
        if !input.petInSafeZone {
            return RedPacketQualityItem(
                dimension: .composition,
                level: .error,
                detail: "宠物主体仅有 \(Int(input.petSafeZoneCoverageRatio * 100))% 位于安全区，红包控件可能遮挡主体",
                suggestionKey: "redpacket.quality.composition.safezone"
            )
        }

        return RedPacketQualityItem(
            dimension: .composition,
            level: .pass,
            detail: "构图良好",
            suggestionKey: ""
        )
    }

    // MARK: - 抠图

    /// 抠图检测：边缘破碎、透明区域异常、主体不完整。
    public static func evaluateCutout(_ input: RedPacketQualityInput) -> RedPacketQualityItem {
        guard input.cutoutMetricsAvailable else {
            return RedPacketQualityItem(
                dimension: .cutout,
                level: .error,
                detail: "尚未获得有效抠图蒙版，请重新抠图",
                suggestionKey: "redpacket.quality.cutout.unavailable"
            )
        }

        if input.cutoutForegroundRatio < cutoutForegroundMin {
            return RedPacketQualityItem(
                dimension: .cutout,
                level: .error,
                detail: "识别到的主体过少（\(Int(input.cutoutForegroundRatio * 100))%），抠图可能失败",
                suggestionKey: "redpacket.quality.cutout.retry"
            )
        }

        if input.cutoutForegroundRatio > cutoutForegroundMax {
            return RedPacketQualityItem(
                dimension: .cutout,
                level: .warning,
                detail: "前景覆盖 \(Int(input.cutoutForegroundRatio * 100))%，可能混入较多背景",
                suggestionKey: "redpacket.quality.cutout.background"
            )
        }

        if input.cutoutFragmentationRatio > cutoutFragmentationMax {
            return RedPacketQualityItem(
                dimension: .cutout,
                level: .warning,
                detail: "抠图包含较多零散区域（\(Int(input.cutoutFragmentationRatio * 100))%），建议重试",
                suggestionKey: "redpacket.quality.cutout.fragmented"
            )
        }

        if input.cutoutBoundaryTouchRatio > cutoutBoundaryTouchMax {
            return RedPacketQualityItem(
                dimension: .cutout,
                level: .warning,
                detail: "主体与画面边缘接触较多（\(Int(input.cutoutBoundaryTouchRatio * 100))%），请确认耳朵或尾巴是否完整",
                suggestionKey: "redpacket.quality.cutout.incomplete"
            )
        }

        if input.cutoutEdgeRoughness > cutoutRoughnessMax {
            return RedPacketQualityItem(
                dimension: .cutout,
                level: .warning,
                detail: "抠图边缘较粗糙（破碎度 \(Int(input.cutoutEdgeRoughness * 100))%），建议重试",
                suggestionKey: "redpacket.quality.cutout.rough"
            )
        }

        return RedPacketQualityItem(
            dimension: .cutout,
            level: .pass,
            detail: "抠图良好",
            suggestionKey: ""
        )
    }

    // MARK: - 可读性

    /// 可读性检测：文本与背景对比度、文本遮挡风险。
    public static func evaluateReadability(_ input: RedPacketQualityInput) -> RedPacketQualityItem {
        // 无文本内容时跳过
        guard !input.textContent.isEmpty else {
            return RedPacketQualityItem(
                dimension: .readability,
                level: .pass,
                detail: "无文本内容",
                suggestionKey: ""
            )
        }

        // 文本偏离安全区
        if !input.textInSafeZone {
            return RedPacketQualityItem(
                dimension: .readability,
                level: .error,
                detail: "文字位置在风险区内，红包场景中可能被遮挡",
                suggestionKey: "redpacket.quality.readability.zone"
            )
        }

        // 对比度过低
        if input.textContrast < textContrastMin {
            return RedPacketQualityItem(
                dimension: .readability,
                level: .warning,
                detail: "文字与背景对比度偏低，建议更换文字风格",
                suggestionKey: "redpacket.quality.readability.contrast"
            )
        }

        return RedPacketQualityItem(
            dimension: .readability,
            level: .pass,
            detail: "文字可读性良好",
            suggestionKey: ""
        )
    }

    // MARK: - 文字对比度计算（可读性检测支撑）

    /// 对比度满分基准：WCAG 7.5:1（超过 AAA 正文标准 7:1）映射为 1.0。
    /// 3:1（WCAG AA 大文本标准，封面文字均为大号展示字）恰映射为 0.4 = textContrastMin。
    public static let textContrastFullScale: Double = 7.5

    /// 提取背景描述符的代表色：渐变取全部端点色（文字可能落在渐变任意位置），
    /// 装饰背景取底渐变（稀疏图案不主导文字底色），资源背景无法解析返回空。
    public static func backgroundHexColors(_ background: RedPacketBackgroundDescriptor) -> [String] {
        switch background {
        case .solid(let colorHex):
            return [colorHex]
        case .gradient(let colors, _):
            return colors
        case .decorated(let base, _, _):
            return base.colors
        case .resource:
            return []
        }
    }

    /// WCAG 相对亮度（0–1）。支持 #RRGGBB / #RRGGBBAA（alpha 不参与亮度），无法解析返回 nil。
    public static func relativeLuminance(hex: String) -> Double? {
        var value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard value.count == 6 || value.count == 8 else { return nil }
        if value.count == 8 { value = String(value.prefix(6)) }
        var channels: [Double] = []
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let component = UInt64(value[index..<next], radix: 16) else { return nil }
            channels.append(Double(component) / 255.0)
            index = next
        }
        // sRGB 分量 → 线性亮度（WCAG 2.x 定义）
        let linear = channels.map { c in
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    /// WCAG 对比度（1–21）。任一颜色无法解析返回 nil。
    public static func contrastRatio(textHex: String, backgroundHex: String) -> Double? {
        guard let textLuminance = relativeLuminance(hex: textHex),
              let backgroundLuminance = relativeLuminance(hex: backgroundHex) else { return nil }
        let lighter = max(textLuminance, backgroundLuminance)
        let darker = min(textLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// 文字与模板背景的归一化对比度（0–1，越高越好）。
    /// 取文字主色对背景各代表色 WCAG 对比度的最小值（渐变下最保守），
    /// 再按 textContrastFullScale 归一化。只看主色不看描边——描边过细（画布宽 0.2%–0.6%）
    /// 不主导可读性，宁可多报不漏报。背景无可解析代表色或颜色解析失败返回 nil，由调用方决定降级语义。
    public static func textContrast(textHex: String, background: RedPacketBackgroundDescriptor) -> Double? {
        let ratios = backgroundHexColors(background).compactMap {
            contrastRatio(textHex: textHex, backgroundHex: $0)
        }
        guard let worst = ratios.min() else { return nil }
        return min(1.0, worst / textContrastFullScale)
    }
}
