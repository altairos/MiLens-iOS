//  BeadResultDisplayLogic —— 拼豆结果页展示纯决策逻辑。
//  从 BeadPatternResultView 下沉（audit-6 P1-4：0% 覆盖大文件补测）。
//  统计行/物料表/Toast 文案主体已在 MiLensKit BeadFlowLogic；本文件只补页面剩余碎片。
//  纯决策逻辑，无 IO/无 SwiftUI 依赖（DESIGN.md §4）。

import Foundation

/// 拼豆结果页展示决策（对照 Figma「05·拼豆图纸」结果区）。
enum BeadResultDisplayLogic {

    /// 身份元信息行："宽×高 · N 色"。
    static func identityMeta(width: Int, height: Int, colorCount: Int) -> String {
        "\(width)×\(height) · \(colorCount) 色"
    }

    /// 缩放滑轨进度：canvasScale / 2 线性映射到 [0, 1]，超界 clamp。
    static func zoomProgress(canvasScale: Double) -> Double {
        min(max(canvasScale / 2.0, 0), 1)
    }
}
