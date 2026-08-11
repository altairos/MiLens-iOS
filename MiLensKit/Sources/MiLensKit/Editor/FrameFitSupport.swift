import Foundation

// FrameFitSupport — 相框自适应绘制核心逻辑（纯函数，可单测）。
//
// 配合 DecorationCatalog / EditorImageProcessing 使用：
// - DecorationItem.fitMode 声明素材自适应模式（stretch / ninePatch / ratioSet）。
// - ninePatch 模式下 computeNinePatchTiles 把素材切成 9 块（四角不变形、四边单向拉伸、
//   中央透明窗口双向拉伸），返回 (srcRect, dstRect) 对，由 App 层 CGContext 逐块 draw。
// - ratioSet 模式由 App 层 imageProvider 按 photoAspectRatio 选最优比例素材，
//   选定后仍按 stretch 单块绘制；MiLensKit 不参与比例选择。
//
// 设计原则：MiLensKit 不含 CGImage，所有坐标用 Double 字段（与 EditorLayerGeometry 一致）。
// App 层 renderExport 调用本模块拿到 9 个 (src, dst) 矩形后用 CGContext.draw 逐块绘制。

/// 相框自适应模式。对应素材 manifest 的 `fitMode` 字段。
public enum FrameFitMode: String, Sendable, Codable, CaseIterable {
    /// 拉伸铺满（角部装饰会变形；仅适合纯色/渐变边框）。
    case stretch
    /// 九宫格切图：四角不缩、四边单向拉伸、中央透明窗口双向拉伸。
    /// 角部装饰不变形，是几何/线条类相框的推荐模式。
    case ninePatch
    /// 多比例素材：每个相框提供多张不同比例的 PNG，运行时选最接近照片比例的一张。
    /// 适合花纹复杂的相框（如拍立得、手绘）。比例选择由 App 层 imageProvider 完成。
    case ratioSet
}

/// 九宫格切图的边缘内边距（源图像素空间）。
/// 对应素材 manifest 的 `ninePatchInsets` 字段。
public struct NinePatchInsets: Equatable, Sendable, Codable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }

    /// 是否对给定源图尺寸合法（非负、留出中央窗口）。
    public func isValid(srcWidth: Double, srcHeight: Double) -> Bool {
        srcWidth > 0 && srcHeight > 0 &&
        top >= 0 && left >= 0 && bottom >= 0 && right >= 0 &&
        top + bottom < srcHeight && left + right < srcWidth
    }
}

/// 单个九宫格绘制块：源矩形（像素空间）→ 目标矩形（导出像素空间）。
/// App 层按 src 矩形从素材 CGImage 截取，draw 到 dst 矩形。
public struct NinePatchTile: Equatable, Sendable {
    public var srcX: Double
    public var srcY: Double
    public var srcW: Double
    public var srcH: Double
    public var dstX: Double
    public var dstY: Double
    public var dstW: Double
    public var dstH: Double
}

/// 九宫格 9 块的固定返回顺序：左上、上、右上、左、中、右、左下、下、右下。
public let NINE_PATCH_TILE_ORDER: [String] = [
    "topLeft", "top", "topRight",
    "left", "center", "right",
    "bottomLeft", "bottom", "bottomRight",
]

/// 计算九宫格 9 个绘制块（顺序见 NINE_PATCH_TILE_ORDER）。
///
/// inset 在目标空间按比例缩放（scaleX = dstW/srcW，scaleY = dstH/srcH），
/// 保证视觉边框宽度随画布等比变化。inset 非法时退化为整图单块拉伸（不崩）。
///
/// - Parameters:
///   - srcWidth/srcHeight: 素材 PNG 像素尺寸。
///   - insets: 源图像素空间的四边内边距。
///   - dstX/dstY/dstW/dstH: 目标矩形（导出像素空间，左上原点）。
/// - Returns: 恰好 9 个 NinePatchTile；inset 非法时返回单块（整图 → 整目标）。
public func computeNinePatchTiles(
    srcWidth: Double, srcHeight: Double,
    insets: NinePatchInsets,
    dstX: Double, dstY: Double, dstW: Double, dstH: Double
) -> [NinePatchTile] {
    // 非法 inset（含 0 画布）→ 退化为单块整图拉伸（与 stretch 等价）。
    guard insets.isValid(srcWidth: srcWidth, srcHeight: srcHeight),
          dstW > 0, dstH > 0 else {
        return [NinePatchTile(
            srcX: 0, srcY: 0, srcW: srcWidth, srcH: srcHeight,
            dstX: dstX, dstY: dstY, dstW: dstW, dstH: dstH)]
    }

    let scaleX = dstW / srcWidth
    let scaleY = dstH / srcHeight
    let dTop = insets.top * scaleY
    let dLeft = insets.left * scaleX
    let dBottom = insets.bottom * scaleY
    let dRight = insets.right * scaleX

    let sInnerW = srcWidth - insets.left - insets.right
    let sInnerH = srcHeight - insets.top - insets.bottom
    let dInnerW = dstW - dLeft - dRight
    let dInnerH = dstH - dTop - dBottom

    let sLeft = insets.left, sRight = insets.right, sTop = insets.top, sBottom = insets.bottom
    let sInnerX = sLeft, sInnerY = sTop
    let sRightX = srcWidth - sRight, sBottomY = srcHeight - sBottom

    let dInnerX = dstX + dLeft, dInnerY = dstY + dTop
    let dRightX = dstX + dstW - dRight, dBottomY = dstY + dstH - dBottom

    return [
        // TL
        NinePatchTile(srcX: 0, srcY: 0, srcW: sLeft, srcH: sTop,
                      dstX: dstX, dstY: dstY, dstW: dLeft, dstH: dTop),
        // T
        NinePatchTile(srcX: sInnerX, srcY: 0, srcW: sInnerW, srcH: sTop,
                      dstX: dInnerX, dstY: dstY, dstW: dInnerW, dstH: dTop),
        // TR
        NinePatchTile(srcX: sRightX, srcY: 0, srcW: sRight, srcH: sTop,
                      dstX: dRightX, dstY: dstY, dstW: dRight, dstH: dTop),
        // L
        NinePatchTile(srcX: 0, srcY: sInnerY, srcW: sLeft, srcH: sInnerH,
                      dstX: dstX, dstY: dInnerY, dstW: dLeft, dstH: dInnerH),
        // C
        NinePatchTile(srcX: sInnerX, srcY: sInnerY, srcW: sInnerW, srcH: sInnerH,
                      dstX: dInnerX, dstY: dInnerY, dstW: dInnerW, dstH: dInnerH),
        // R
        NinePatchTile(srcX: sRightX, srcY: sInnerY, srcW: sRight, srcH: sInnerH,
                      dstX: dRightX, dstY: dInnerY, dstW: dRight, dstH: dInnerH),
        // BL
        NinePatchTile(srcX: 0, srcY: sBottomY, srcW: sLeft, srcH: sBottom,
                      dstX: dstX, dstY: dBottomY, dstW: dLeft, dstH: dBottom),
        // B
        NinePatchTile(srcX: sInnerX, srcY: sBottomY, srcW: sInnerW, srcH: sBottom,
                      dstX: dInnerX, dstY: dBottomY, dstW: dInnerW, dstH: dBottom),
        // BR
        NinePatchTile(srcX: sRightX, srcY: sBottomY, srcW: sRight, srcH: sBottom,
                      dstX: dRightX, dstY: dBottomY, dstW: dRight, dstH: dBottom),
    ]
}

// MARK: - 比例匹配（ratioSet 模式用）

/// 把 "WxH"（如 "3x4"、"16x9"）解析为 (width, height)；非法返回 nil。
public func parseAspectRatioToken(_ token: String) -> (Double, Double)? {
    let parts = token.split(separator: "x")
    guard parts.count == 2,
          let w = Double(parts[0]), let h = Double(parts[1]),
          w > 0, h > 0 else { return nil }
    return (w, h)
}

/// 从候选比例中选最接近 targetRatio 的一个（比值最近，正负方向都接受）。
/// 候选为空时返回 nil。
public func pickClosestAspectRatio(targetRatio: Double, candidates: [String]) -> String? {
    guard !candidates.isEmpty else { return nil }
    var best: (token: String, diff: Double)?
    for token in candidates {
        guard let (w, h) = parseAspectRatioToken(token) else { continue }
        let diff = abs(targetRatio - w / h)
        if best == nil || diff < best!.diff {
            best = (token, diff)
        }
    }
    return best?.token
}
