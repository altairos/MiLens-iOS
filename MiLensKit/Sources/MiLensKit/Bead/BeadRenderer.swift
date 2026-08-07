import Foundation

// BeadRenderer — 图纸渲染（格子 + 颜色 + 编号）。
// 逐行翻译自源端 shared/.../bead/BeadRenderer.ets。
// 源端使用 Canvas 2D API，Swift 端改为操作 RGBA pixel buffer [UInt8]。

// MARK: - 颜色辅助

/// rgb → CSS 字符串。对应源端 `rgbToCss`。
private func rgbToCss(_ rgb: RGBColor) -> String {
    return "rgb(\(rgb.r),\(rgb.g),\(rgb.b))"
}

/// 获取亮度判断文字颜色。对应源端 `textColorForBg`。
private func textColorForBg(_ rgb: RGBColor) -> String {
    let brightness = Double(rgb.r) * 0.299 + Double(rgb.g) * 0.587 + Double(rgb.b) * 0.114
    return brightness > 128 ? "#000000" : "#FFFFFF"
}

// MARK: - 边框颜色推导

/// 根据图案主色调推导边框颜色：取使用量最大的颜色并适当加深。
/// 对应源端 `deriveBadgeBorderColor`。
public func deriveBadgeBorderColor(_ pattern: BeadPattern) -> String {
    if pattern.colorCounts.isEmpty { return "#333333" }
    let dominant = pattern.colorCounts[0]
    let r = dominant.rgb.r
    let g = dominant.rgb.g
    let b = dominant.rgb.b
    let factor = 0.55
    let dr = Int((Double(r) * factor).rounded(.toNearestOrAwayFromZero))
    let dg = Int((Double(g) * factor).rounded(.toNearestOrAwayFromZero))
    let db = Int((Double(b) * factor).rounded(.toNearestOrAwayFromZero))
    return "rgb(\(dr),\(dg),\(db))"
}

// MARK: - 尺寸计算

/// 计算图纸渲染尺寸。对应源端 `calcPatternSize`。
public func calcPatternSize(_ pattern: BeadPattern, cellSize: Int) -> CanvasSize {
    return CanvasSize(pattern.width * cellSize, pattern.height * cellSize)
}

// MARK: - 像素缓冲区绘制

/// 像素缓冲区填充矩形。对应 Canvas `ctx.fillRect`。
private func fillRect(
    _ pixels: inout [UInt8], bufW: Int, bufH: Int,
    x0: Int, y0: Int, w: Int, h: Int,
    r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255
) {
    let x1 = min(x0 + w, bufW)
    let y1 = min(y0 + h, bufH)
    for y in max(0, y0)..<y1 {
        for x in max(0, x0)..<x1 {
            let pi = (y * bufW + x) * 4
            if a < 255 {
                let invA = UInt8(255) - a
                pixels[pi] = UInt8((UInt16(pixels[pi]) * UInt16(invA) + UInt16(r) * UInt16(a)) / 255)
                pixels[pi + 1] = UInt8((UInt16(pixels[pi + 1]) * UInt16(invA) + UInt16(g) * UInt16(a)) / 255)
                pixels[pi + 2] = UInt8((UInt16(pixels[pi + 2]) * UInt16(invA) + UInt16(b) * UInt16(a)) / 255)
            } else {
                pixels[pi] = r; pixels[pi + 1] = g; pixels[pi + 2] = b
            }
            pixels[pi + 3] = 255
        }
    }
}

/// 绘制水平线（1px）。对应 Canvas `ctx.moveTo/lineTo/stroke`。
private func drawHLine(_ pixels: inout [UInt8], bufW: Int, bufH: Int,
                       x0: Int, x1: Int, y: Int, darken: Double) {
    if y < 0 || y >= bufH { return }
    for x in max(0, x0)..<min(x1, bufW) {
        let pi = (y * bufW + x) * 4
        pixels[pi] = UInt8((Double(pixels[pi]) * darken).rounded(.toNearestOrAwayFromZero))
        pixels[pi + 1] = UInt8((Double(pixels[pi + 1]) * darken).rounded(.toNearestOrAwayFromZero))
        pixels[pi + 2] = UInt8((Double(pixels[pi + 2]) * darken).rounded(.toNearestOrAwayFromZero))
        pixels[pi + 3] = 255
    }
}

/// 绘制垂直线（1px）。
private func drawVLine(_ pixels: inout [UInt8], bufW: Int, bufH: Int,
                       x: Int, y0: Int, y1: Int, darken: Double) {
    if x < 0 || x >= bufW { return }
    for y in max(0, y0)..<min(y1, bufH) {
        let pi = (y * bufW + x) * 4
        pixels[pi] = UInt8((Double(pixels[pi]) * darken).rounded(.toNearestOrAwayFromZero))
        pixels[pi + 1] = UInt8((Double(pixels[pi + 1]) * darken).rounded(.toNearestOrAwayFromZero))
        pixels[pi + 2] = UInt8((Double(pixels[pi + 2]) * darken).rounded(.toNearestOrAwayFromZero))
        pixels[pi + 3] = 255
    }
}

// MARK: - 图纸渲染

/// 绘制拼豆图纸到 RGBA pixel buffer。
/// 源端操作 CanvasRenderingContext2D，Swift 端改为操作 [UInt8] RGBA buffer。
/// 文字渲染（MARD 色号/字母）在纯像素模式下不可用，仅填充颜色和网格线。
public func drawBeadPattern(
    pixels: inout [UInt8], canvasW: Int, canvasH: Int,
    pattern: BeadPattern, cellSize: Int, viewMode: BeadViewMode,
    offsetX: Int, offsetY: Int, drawOpts: BeadDrawOptions? = nil
) {
    let w = pattern.width
    let h = pattern.height
    let totalW = w * cellSize
    let totalH = h * cellSize
    let circularCrop = drawOpts?.circularCrop ?? false

    // clearRect: 填充透明
    for y in 0..<canvasH {
        for x in 0..<canvasW {
            let pi = (y * canvasW + x) * 4
            pixels[pi] = 0; pixels[pi + 1] = 0; pixels[pi + 2] = 0; pixels[pi + 3] = 0
        }
    }

    // 绘制每个格子
    for y in 0..<h {
        for x in 0..<w {
            let i = y * w + x
            let isEmpty = !pattern.empty.isEmpty && pattern.empty[i] == 1
            let px = offsetX + x * cellSize
            let py = offsetY + y * cellSize

            if isEmpty {
                fillRect(&pixels, bufW: canvasW, bufH: canvasH,
                         x0: px, y0: py, w: cellSize, h: cellSize,
                         r: 0xF5, g: 0xF5, b: 0xF5)
                continue
            }

            let idx = Int(pattern.indices[i])
            guard idx < pattern.paletteUsed.count else { continue }
            let color = pattern.paletteUsed[idx]
            fillRect(&pixels, bufW: canvasW, bufH: canvasH,
                     x0: px, y0: py, w: cellSize, h: cellSize,
                     r: UInt8(color.rgb.r), g: UInt8(color.rgb.g), b: UInt8(color.rgb.b))
        }
    }

    // Normal grid lines
    for y in 0...h {
        drawHLine(&pixels, bufW: canvasW, bufH: canvasH,
                  x0: offsetX, x1: offsetX + totalW, y: offsetY + y * cellSize, darken: 0.85)
    }
    for x in 0...w {
        drawVLine(&pixels, bufW: canvasW, bufH: canvasH,
                  x: offsetX + x * cellSize, y0: offsetY, y1: offsetY + totalH, darken: 0.85)
    }

    // Bold grid lines (every 5 cells)
    var y = 0
    while y <= h {
        drawHLine(&pixels, bufW: canvasW, bufH: canvasH,
                  x0: offsetX, x1: offsetX + totalW, y: offsetY + y * cellSize, darken: 0.5)
        y += BEAD_GRID_BOLD_INTERVAL
    }
    var x = 0
    while x <= w {
        drawVLine(&pixels, bufW: canvasW, bufH: canvasH,
                  x: offsetX + x * cellSize, y0: offsetY, y1: offsetY + totalH, darken: 0.5)
        x += BEAD_GRID_BOLD_INTERVAL
    }

    // Circular crop mask: clear pixels outside circle
    if circularCrop {
        let radius = Double(min(totalW, totalH)) / 2
        let centerX = Double(offsetX) + Double(totalW) / 2
        let centerY = Double(offsetY) + Double(totalH) / 2
        for py in 0..<canvasH {
            for px in 0..<canvasW {
                let dx = Double(px) - centerX
                let dy = Double(py) - centerY
                let dist = sqrt(dx * dx + dy * dy)
                if dist > radius {
                    let pi = (py * canvasW + px) * 4
                    pixels[pi] = 0; pixels[pi + 1] = 0; pixels[pi + 2] = 0; pixels[pi + 3] = 0
                }
            }
        }
    }
}
