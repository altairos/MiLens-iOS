// Linux（WSL2 测试环境）无 CoreGraphics，CGSize 由 swift-corelibs-foundation 提供。
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// DecorationComposition — 装饰合成纯函数层。
// 覆盖开发计划阻塞项5（稳定合成顺序）、阻塞项7（画布尺寸重映射）逻辑侧，
// 以及规格 §4.3 贴纸视觉尺寸钳制与数量上限。
// 画布预览（EditorCanvasView）与导出（renderExport）共用同一排序函数。

// MARK: - 稳定合成顺序（阻塞项5）

/// 渲染类型权重：photo 最底，text 最顶。类型权重优先于 zIndex。
func renderOrderWeight(_ type: EditorLayerType) -> Int {
    switch type {
    case .photo: return 0
    case .frame: return 1
    case .sticker: return 2
    case .text: return 3
    }
}

/// 稳定合成顺序：photo → frame → sticker → text；同类型内 zIndex 升序；
/// 同类型同 zIndex 保持原始相对顺序（显式携带原序索引，不依赖标准库排序稳定性）。
public func orderedRenderLayers(_ layers: [EditorLayer]) -> [EditorLayer] {
    layers.enumerated()
        .sorted { lhs, rhs in
            let (li, la) = lhs, (ri, ra) = rhs
            let lw = renderOrderWeight(la.type), rw = renderOrderWeight(ra.type)
            if lw != rw { return lw < rw }
            if la.zIndex != ra.zIndex { return la.zIndex < ra.zIndex }
            return li < ri
        }
        .map(\.element)
}

// MARK: - 贴纸钳制与上限（规格 §4.3）

/// 贴纸显示尺寸下限：画布短边的 8%。
public let STICKER_MIN_VISUAL_RATIO: Double = 0.08
/// 贴纸显示尺寸上限：画布短边的 70%。
public let STICKER_MAX_VISUAL_RATIO: Double = 0.70
/// 贴纸图层数量上限。
public let STICKER_LAYER_LIMIT = 20

/// 钳制贴纸视觉尺寸：显示尺寸（素材宽高较大者 × scale）约束在画布短边 8%–70%。
/// 画布非法或素材尺寸非法（≤ 0）时原样返回 scale（无有效基准，交由调用方兜底）。
public func clampStickerVisualScale(
    nativeW: Double, nativeH: Double, scale: Double,
    canvasW: Double, canvasH: Double
) -> Double {
    let short = min(canvasW, canvasH)
    guard short > 0, scale.isFinite else { return scale }
    let maxDim = max(nativeW, nativeH)
    guard maxDim > 0 else { return scale }
    let display = maxDim * scale
    let clamped = min(max(display, short * STICKER_MIN_VISUAL_RATIO),
                      short * STICKER_MAX_VISUAL_RATIO)
    return clamped / maxDim
}

/// 贴纸数量是否已达上限（仅 sticker 类型计数；隐藏贴纸仍占名额）。
public func isStickerLimitReached(
    _ layers: [EditorLayer], limit: Int = STICKER_LAYER_LIMIT
) -> Bool {
    layers.filter { $0.type == .sticker }.count >= limit
}

// MARK: - 画布尺寸重映射（阻塞项7）

/// 画布尺寸变化时重映射全部图层：
/// - photo：中心与宽高重置为新画布（沿用 setCanvasSize 原有语义）
/// - frame：按新画布重新铺满并重置姿态（规格规定 frame 恒 rotation=0/scale=1/flip=false）
/// - sticker：中心按新旧画布宽高比例归一化迁移，scale 按短边比例缩放后走贴纸钳制
/// - text：中心同 sticker 迁移，scale 按短边比例缩放后维持层钳制 [MIN, MAX_LAYER_SCALE]
/// 尺寸相同或任一画布非法（宽高 ≤ 0）时原样返回。
public func remapLayersForCanvas(
    _ layers: [EditorLayer], from oldSize: CGSize, to newSize: CGSize
) -> [EditorLayer] {
    guard oldSize.width > 0, oldSize.height > 0,
          newSize.width > 0, newSize.height > 0,
          oldSize != newSize else { return layers }

    let scaleX = newSize.width / oldSize.width
    let scaleY = newSize.height / oldSize.height
    let shortScale = min(newSize.width, newSize.height) / min(oldSize.width, oldSize.height)

    return layers.map { layer in
        var l = layer
        switch l.type {
        case .photo:
            l.x = Double(newSize.width / 2)
            l.y = Double(newSize.height / 2)
            l.width = Double(newSize.width)
            l.height = Double(newSize.height)
        case .frame:
            l.x = Double(newSize.width / 2)
            l.y = Double(newSize.height / 2)
            l.width = Double(newSize.width)
            l.height = Double(newSize.height)
            l.rotation = 0
            l.scale = 1
            l.flipX = false
            l.flipY = false
        case .sticker:
            l.x *= Double(scaleX)
            l.y *= Double(scaleY)
            l.scale = clampStickerVisualScale(
                nativeW: l.width, nativeH: l.height, scale: l.scale * Double(shortScale),
                canvasW: Double(newSize.width), canvasH: Double(newSize.height))
        case .text:
            l.x *= Double(scaleX)
            l.y *= Double(scaleY)
            l.scale = clampLayerScale(l.scale * Double(shortScale))
        }
        return l
    }
}
