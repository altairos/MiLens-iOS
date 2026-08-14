//  RedPacketQualityInputBuilder —— 质量检测输入组装纯逻辑。
//
//  从图层/模板/图像指标状态提取 RedPacketQualityInput：
//  清晰度用原图（透明轮廓会抬高 Laplacian），亮度优先抠图主体，
//  文字对比度用 WCAG 真实计算（P2-4）。纯函数，可单测。

import Foundation
import MiLensKit

/// 组装质量检测输入（无状态，输入全部显式传参）。
enum RedPacketQualityInputBuilder {

    /// - Parameters:
    ///   - layers: 当前草稿图层。
    ///   - template: 当前模板。
    ///   - sourceMetrics: 原图像素指标（清晰度/分辨率基准）。
    ///   - cutoutMetrics: 抠图主体像素指标（亮度优先采用，缺失回退原图）。
    ///   - maskMetrics: 抠图蒙版结构指标（缺失视为未完成抠图）。
    ///   - cutoutApplied: 抠图是否已成功应用（决定 cutoutMetricsAvailable）。
    static func make(
        layers: [RedPacketLayer],
        template: RedPacketTemplate,
        sourceMetrics: RedPacketImageMetrics?,
        cutoutMetrics: RedPacketImageMetrics?,
        maskMetrics: RedPacketMaskMetrics?,
        cutoutApplied: Bool
    ) -> RedPacketQualityInput {
        let petLayer = layers.first { $0.kind == .pet }
        let textLayer = layers.first { $0.kind == .text }

        // 清晰度/分辨率使用原图，避免透明轮廓抬高 Laplacian；亮度优先检查抠出的主体。
        let clarityMetrics = sourceMetrics
        let toneMetrics = cutoutMetrics ?? sourceMetrics

        // 宠物面积比例
        let petCoverage: Double
        if let pet = petLayer, pet.visible {
            let petArea = pet.width * pet.scale * pet.height * pet.scale
            let canvasArea = rpCanvasWidth * rpCanvasHeight
            petCoverage = min(1, petArea / canvasArea)
        } else {
            petCoverage = 0
        }

        // 宠物是否在安全区
        let petInZone: Bool
        let petSafeZoneCoverage: Double
        let petCanvasVisible: Double
        if let pet = petLayer {
            petSafeZoneCoverage = rpLayerSafeZoneCoverageRatio(pet, template: template)
            petCanvasVisible = rpLayerCanvasVisibleRatio(pet)
            petInZone = petSafeZoneCoverage >= 0.65
        } else {
            petInZone = false
            petSafeZoneCoverage = 0
            petCanvasVisible = 0
        }

        // 文本是否在安全区
        let textInZone: Bool
        if let text = textLayer {
            textInZone = rpIsLayerInSafeZone(text, template: template)
        } else {
            textInZone = true
        }

        // 文字与模板背景的真实对比度（WCAG，文字主色 vs 背景代表色，渐变取最保守端）。
        // 无文本层/颜色不可解析时不构成可读性问题，取满分（空文本已在 evaluateReadability 跳过）。
        let textContrastValue: Double
        if let textLayer,
           let style = RedPacketTextStylePreset(rawValue: textLayer.styleID)?.style {
            textContrastValue = RedPacketQualityLogic.textContrast(
                textHex: style.colorHex,
                background: template.background
            ) ?? 1.0
        } else {
            textContrastValue = 1.0
        }

        return RedPacketQualityInput(
            imageWidth: clarityMetrics?.pixelWidth ?? 0,
            imageHeight: clarityMetrics?.pixelHeight ?? 0,
            sharpness: clarityMetrics?.sharpness ?? 0,
            averageBrightness: toneMetrics?.averageBrightness ?? 0,
            petCoverageRatio: petCoverage,
            cutoutEdgeRoughness: maskMetrics?.edgeRoughness ?? 0,
            petInSafeZone: petInZone,
            textContent: textLayer?.text ?? "",
            textInSafeZone: textInZone,
            textContrast: textContrastValue,
            imageMetricsAvailable: clarityMetrics != nil && toneMetrics != nil,
            shadowClippingRatio: toneMetrics?.shadowClippingRatio ?? 0,
            highlightClippingRatio: toneMetrics?.highlightClippingRatio ?? 0,
            petCanvasVisibleRatio: petCanvasVisible,
            petSafeZoneCoverageRatio: petSafeZoneCoverage,
            cutoutMetricsAvailable: cutoutApplied && maskMetrics != nil,
            cutoutForegroundRatio: maskMetrics?.foregroundRatio ?? 0,
            cutoutFragmentationRatio: maskMetrics?.fragmentationRatio ?? 0,
            cutoutBoundaryTouchRatio: maskMetrics?.boundaryTouchRatio ?? 0
        )
    }
}
