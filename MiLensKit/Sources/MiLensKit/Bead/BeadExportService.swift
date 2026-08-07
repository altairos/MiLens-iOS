import Foundation

// BeadExportService — A4 高清图纸导出。
// 逐行翻译自源端 shared/.../bead/BeadExportService.ets。
// 源端操作 Uint8ClampedArray pixel buffer，Swift 端使用 [UInt8]。

// MARK: - A4 布局常量 @ 300DPI

private let A4_W = 2480
private let A4_H = 3508
private let MARGIN = 80
private let TITLE_H = 90
private let STATS_H = 50
private let FOOTER_H = 50
private let CONTENT_TOP = MARGIN + TITLE_H + STATS_H
private let CONTENT_BOTTOM = A4_H - MARGIN - FOOTER_H
private let SIDEBAR_W = 560
private let GRID_AREA_W = A4_W - MARGIN * 2 - SIDEBAR_W - 40
private let GRID_AREA_H = CONTENT_BOTTOM - CONTENT_TOP

// MARK: - 5×7 位图字体

/// 5×7 位图字体（每个字符 5 字节，每字节代表一行 5 像素位，高位在左）。
private let FONT_5X7: [Character: [UInt8]] = [
    "A": [0x7C, 0x12, 0x11, 0x12, 0x7C],
    "B": [0x7F, 0x49, 0x49, 0x49, 0x36],
    "C": [0x3E, 0x41, 0x41, 0x41, 0x22],
    "D": [0x7F, 0x41, 0x41, 0x22, 0x1C],
    "E": [0x7F, 0x49, 0x49, 0x49, 0x41],
    "F": [0x7F, 0x09, 0x09, 0x09, 0x01],
    "G": [0x3E, 0x41, 0x49, 0x49, 0x3A],
    "H": [0x7F, 0x08, 0x08, 0x08, 0x7F],
    "I": [0x41, 0x41, 0x7F, 0x41, 0x41],
    "J": [0x20, 0x40, 0x40, 0x40, 0x3F],
    "K": [0x7F, 0x08, 0x14, 0x22, 0x41],
    "L": [0x7F, 0x40, 0x40, 0x40, 0x40],
    "M": [0x7F, 0x02, 0x04, 0x02, 0x7F],
    "N": [0x7F, 0x04, 0x08, 0x10, 0x7F],
    "O": [0x3E, 0x41, 0x41, 0x41, 0x3E],
    "P": [0x7F, 0x09, 0x09, 0x09, 0x06],
    "Q": [0x3E, 0x41, 0x51, 0x21, 0x5E],
    "R": [0x7F, 0x09, 0x19, 0x29, 0x46],
    "S": [0x26, 0x49, 0x49, 0x49, 0x32],
    "T": [0x01, 0x01, 0x7F, 0x01, 0x01],
    "U": [0x3F, 0x40, 0x40, 0x40, 0x3F],
    "V": [0x0F, 0x30, 0x40, 0x30, 0x0F],
    "W": [0x7F, 0x20, 0x10, 0x20, 0x7F],
    "X": [0x63, 0x14, 0x08, 0x14, 0x63],
    "Y": [0x03, 0x04, 0x78, 0x04, 0x03],
    "Z": [0x61, 0x51, 0x49, 0x45, 0x43],
    "0": [0x3E, 0x51, 0x49, 0x45, 0x3E],
    "1": [0x00, 0x42, 0x7F, 0x40, 0x00],
    "2": [0x42, 0x61, 0x51, 0x49, 0x46],
    "3": [0x22, 0x41, 0x49, 0x49, 0x36],
    "4": [0x18, 0x14, 0x12, 0x7F, 0x10],
    "5": [0x27, 0x45, 0x45, 0x45, 0x39],
    "6": [0x3E, 0x49, 0x49, 0x49, 0x32],
    "7": [0x01, 0x71, 0x09, 0x05, 0x03],
    "8": [0x36, 0x49, 0x49, 0x49, 0x36],
    "9": [0x26, 0x49, 0x49, 0x49, 0x3E],
    " ": [0x00, 0x00, 0x00, 0x00, 0x00],
    ":": [0x00, 0x36, 0x36, 0x00, 0x00],
    "-": [0x00, 0x08, 0x08, 0x08, 0x00],
    "x": [0x63, 0x14, 0x08, 0x14, 0x63],
    ".": [0x00, 0x60, 0x60, 0x00, 0x00],
]

// MARK: - 字体绘制

/// 在像素 buffer 上绘制一个字符。对应源端 `drawChar`。
private func drawChar(
    _ pixels: inout [UInt8], bufW: Int, bufH: Int,
    ch: Character, x0: Int, y0: Int, scale: Int,
    r: UInt8, g: UInt8, b: UInt8
) {
    let upper = String(ch).uppercased()
    guard let key = upper.first, let glyph = FONT_5X7[key] else { return }
    for row in 0..<7 {
        for col in 0..<5 {
            let bit = (glyph[col] >> row) & 1
            if bit != 0 {
                for sy in 0..<scale {
                    for sx in 0..<scale {
                        let px = x0 + col * scale + sx
                        let py = y0 + row * scale + sy
                        if px >= 0 && px < bufW && py >= 0 && py < bufH {
                            let pi = (py * bufW + px) * 4
                            pixels[pi] = r; pixels[pi + 1] = g; pixels[pi + 2] = b; pixels[pi + 3] = 255
                        }
                    }
                }
            }
        }
    }
}

/// 在像素 buffer 上绘制字符串。对应源端 `drawString`。
private func drawString(
    _ pixels: inout [UInt8], bufW: Int, bufH: Int,
    text: String, x0: Int, y0: Int, scale: Int,
    r: UInt8, g: UInt8, b: UInt8
) {
    var cx = x0
    for ch in text {
        drawChar(&pixels, bufW: bufW, bufH: bufH, ch: ch, x0: cx, y0: y0, scale: scale, r: r, g: g, b: b)
        cx += (5 + 1) * scale
    }
}

/// 计算字符串像素宽度。对应源端 `stringWidth`。
private func stringWidth(_ text: String, scale: Int) -> Int {
    return text.count * 6 * scale - scale
}

// MARK: - 填充辅助

/// 像素缓冲区填充矩形。对应源端 `fillRect`。
private func fillRect(
    _ pixels: inout [UInt8], bufW: Int, bufH: Int,
    x0: Int, y0: Int, w: Int, h: Int,
    r: UInt8, g: UInt8, b: UInt8, a: UInt8
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

/// 填充白色背景。对应源端 `fillWhite`。
private func fillWhite(_ pixels: inout [UInt8], totalPixels: Int) {
    for i in 0..<totalPixels {
        let pi = i * 4
        pixels[pi] = 255; pixels[pi + 1] = 255; pixels[pi + 2] = 255; pixels[pi + 3] = 255
    }
}

private func pad2(_ n: Int) -> String {
    return n < 10 ? "0" + String(n) : String(n)
}

/// 解析 CSS 颜色字符串 'rgb(r,g,b)' 或 '#rrggbb'。对应源端 `parseBorderColor`。
private func parseBorderColor(_ color: String) -> (UInt8, UInt8, UInt8) {
    if color.hasPrefix("rgb(") {
        let inner = String(color.dropFirst(4).dropLast())
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 3,
           let r = Int(parts[0]), let g = Int(parts[1]), let b = Int(parts[2]) {
            return (UInt8(max(0, min(255, r))), UInt8(max(0, min(255, g))), UInt8(max(0, min(255, b))))
        }
    }
    if color.hasPrefix("#") && color.count == 7 {
        let hex = color.dropFirst()
        if let r = UInt8(String(hex.prefix(2)), radix: 16),
           let g = UInt8(String(hex.dropFirst(2).prefix(2)), radix: 16),
           let b = UInt8(String(hex.dropFirst(4).prefix(2)), radix: 16) {
            return (r, g, b)
        }
    }
    return (51, 51, 51)
}

// MARK: - 格子图纸渲染

/// 渲染带 MARD 色号的格子图纸。对应源端 `drawGridSection`。
private func drawGridSection(
    _ pixels: inout [UInt8],
    pattern: BeadPattern, cellSize: Int,
    gx0: Int, gy0: Int, gridW: Int, gridH: Int
) {
    let w = pattern.width
    let h = pattern.height
    let fontScale = cellSize >= 50 ? 2 : 1

    for by in 0..<h {
        for bx in 0..<w {
            let bi = by * w + bx
            let isEmpty = !pattern.empty.isEmpty && pattern.empty[bi] == 1
            let cx0 = gx0 + bx * cellSize
            let cy0 = gy0 + by * cellSize

            if isEmpty {
                fillRect(&pixels, bufW: A4_W, bufH: A4_H,
                         x0: cx0, y0: cy0, w: cellSize, h: cellSize,
                         r: 245, g: 245, b: 245, a: 255)
            } else {
                let idx = Int(pattern.indices[bi])
                guard idx < pattern.paletteUsed.count else { continue }
                let color = pattern.paletteUsed[idx]
                let printRgb = color.rgb
                fillRect(&pixels, bufW: A4_W, bufH: A4_H,
                         x0: cx0, y0: cy0, w: cellSize, h: cellSize,
                         r: UInt8(printRgb.r), g: UInt8(printRgb.g), b: UInt8(printRgb.b), a: 255)

                // MARD 色号文字（始终显示）
                let label = color.symbol
                let tw = stringWidth(label, scale: fontScale)
                let tx = cx0 + (cellSize - tw) / 2
                let ty = cy0 + (cellSize - 7 * fontScale) / 2
                let brightness = Double(printRgb.r) * 0.299 + Double(printRgb.g) * 0.587 + Double(printRgb.b) * 0.114
                let tr: UInt8 = brightness > 128 ? 0 : 255
                drawString(&pixels, bufW: A4_W, bufH: A4_H, text: label,
                           x0: tx, y0: ty, scale: fontScale, r: tr, g: tr, b: tr)
            }
        }
    }

    // 网格线 — 细线
    for y in 0...h {
        let ly = gy0 + y * cellSize
        for x in gx0..<(gx0 + gridW) {
            if x >= 0 && x < A4_W && ly >= 0 && ly < A4_H {
                let pi = (ly * A4_W + x) * 4
                pixels[pi] = UInt8((Double(pixels[pi]) * 0.92).rounded())
                pixels[pi + 1] = UInt8((Double(pixels[pi + 1]) * 0.92).rounded())
                pixels[pi + 2] = UInt8((Double(pixels[pi + 2]) * 0.92).rounded())
                pixels[pi + 3] = 255
            }
        }
    }
    for x in 0...w {
        let lx = gx0 + x * cellSize
        for y in gy0..<(gy0 + gridH) {
            if lx >= 0 && lx < A4_W && y >= 0 && y < A4_H {
                let pi = (y * A4_W + lx) * 4
                pixels[pi] = UInt8((Double(pixels[pi]) * 0.92).rounded())
                pixels[pi + 1] = UInt8((Double(pixels[pi + 1]) * 0.92).rounded())
                pixels[pi + 2] = UInt8((Double(pixels[pi + 2]) * 0.92).rounded())
                pixels[pi + 3] = 255
            }
        }
    }

    // 粗线（每5格）
    let boldLineWidth = max(2, cellSize / 10)
    var y = 0
    while y <= h {
        let ly = gy0 + y * cellSize
        fillRect(&pixels, bufW: A4_W, bufH: A4_H,
                 x0: gx0, y0: ly - boldLineWidth / 2, w: gridW, h: boldLineWidth,
                 r: 60, g: 60, b: 60, a: 255)
        y += BEAD_GRID_BOLD_INTERVAL
    }
    var x = 0
    while x <= w {
        let lx = gx0 + x * cellSize
        fillRect(&pixels, bufW: A4_W, bufH: A4_H,
                 x0: lx - boldLineWidth / 2, y0: gy0, w: boldLineWidth, h: gridH,
                 r: 60, g: 60, b: 60, a: 255)
        x += BEAD_GRID_BOLD_INTERVAL
    }

    // 行列坐标标签
    let labelFontScale = max(1, cellSize / 12)
    var ry = 0
    while ry < h {
        let label = String(ry)
        drawString(&pixels, bufW: A4_W, bufH: A4_H, text: label,
                   x0: gx0 - stringWidth(label, scale: labelFontScale) - 4,
                   y0: gy0 + ry * cellSize + (cellSize - 7 * labelFontScale) / 2,
                   scale: labelFontScale, r: 100, g: 100, b: 100)
        ry += BEAD_GRID_BOLD_INTERVAL
    }
    var rx = 0
    while rx < w {
        let label = String(rx)
        drawString(&pixels, bufW: A4_W, bufH: A4_H, text: label,
                   x0: gx0 + rx * cellSize + (cellSize - stringWidth(label, scale: labelFontScale)) / 2,
                   y0: gy0 - 7 * labelFontScale - 4,
                   scale: labelFontScale, r: 100, g: 100, b: 100)
        rx += BEAD_GRID_BOLD_INTERVAL
    }
}

// MARK: - 色卡对照表

/// 渲染色卡对照表。对应源端 `drawColorChart`。
private func drawColorChart(
    _ pixels: inout [UInt8],
    colorCounts: [BeadColorCount],
    x0: Int, y0: Int, width: Int, height: Int
) {
    drawString(&pixels, bufW: A4_W, bufH: A4_H, text: "COLOR CHART",
               x0: x0, y0: y0, scale: 3, r: 60, g: 60, b: 60)

    let startY = y0 + 40
    let rowH = 36
    let swatchSize = 24
    let maxRows = min(colorCounts.count, (height - 40) / rowH)

    for i in 0..<maxRows {
        let cc = colorCounts[i]
        let ry = startY + i * rowH

        // 色块
        fillRect(&pixels, bufW: A4_W, bufH: A4_H,
                 x0: x0, y0: ry, w: swatchSize, h: swatchSize,
                 r: UInt8(cc.rgb.r), g: UInt8(cc.rgb.g), b: UInt8(cc.rgb.b), a: 255)
        // 色块边框
        fillRect(&pixels, bufW: A4_W, bufH: A4_H, x0: x0, y0: ry, w: swatchSize, h: 1, r: 180, g: 180, b: 180, a: 255)
        fillRect(&pixels, bufW: A4_W, bufH: A4_H, x0: x0, y0: ry + swatchSize - 1, w: swatchSize, h: 1, r: 180, g: 180, b: 180, a: 255)
        fillRect(&pixels, bufW: A4_W, bufH: A4_H, x0: x0, y0: ry, w: 1, h: swatchSize, r: 180, g: 180, b: 180, a: 255)
        fillRect(&pixels, bufW: A4_W, bufH: A4_H, x0: x0 + swatchSize - 1, y0: ry, w: 1, h: swatchSize, r: 180, g: 180, b: 180, a: 255)

        // 字母序号 + MARD色号 + 数量
        let letter = String(UnicodeScalar(65 + i)!)
        let label = "\(letter) \(cc.symbol) \(cc.count)pcs"
        drawString(&pixels, bufW: A4_W, bufH: A4_H, text: label,
                   x0: x0 + swatchSize + 8, y0: ry + 4, scale: 2, r: 50, g: 50, b: 50)

        // 建议购买量（右侧）
        let buyLabel = "x\(cc.suggestedBuyCount)"
        drawString(&pixels, bufW: A4_W, bufH: A4_H, text: buyLabel,
                   x0: x0 + width - stringWidth(buyLabel, scale: 2) - 4, y0: ry + 4,
                   scale: 2, r: 120, g: 120, b: 120)
    }

    if colorCounts.count > maxRows {
        let moreY = startY + maxRows * rowH
        let moreLabel = "+\(colorCounts.count - maxRows) more..."
        drawString(&pixels, bufW: A4_W, bufH: A4_H, text: moreLabel,
                   x0: x0, y0: moreY, scale: 2, r: 150, g: 150, b: 150)
    }
}

// MARK: - 核心导出渲染

/// 渲染 A4 高清图纸到 RGBA pixel buffer。对应源端 `renderA4Export`。
/// 返回像素数组（A4_W * A4_H * 4 字节）。
public func renderA4Export(
    pattern: BeadPattern,
    photoPixels: [UInt8]?, photoW: Int, photoH: Int,
    exportOpts: BeadExportOpts? = nil
) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: A4_W * A4_H * 4)
    fillWhite(&pixels, totalPixels: A4_W * A4_H)

    // --- 标题栏 ---
    drawString(&pixels, bufW: A4_W, bufH: A4_H, text: "BEAD PATTERN",
               x0: MARGIN, y0: MARGIN, scale: 6, r: 40, g: 40, b: 40)
    let brandText = "MiLens"
    let brandW = stringWidth(brandText, scale: 4)
    drawString(&pixels, bufW: A4_W, bufH: A4_H, text: brandText,
               x0: A4_W - MARGIN - brandW, y0: MARGIN + 10, scale: 4, r: 120, g: 120, b: 120)

    // 分隔线
    fillRect(&pixels, bufW: A4_W, bufH: A4_H,
             x0: MARGIN, y0: MARGIN + TITLE_H - 10, w: A4_W - MARGIN * 2, h: 2,
             r: 200, g: 200, b: 200, a: 255)

    // --- 统计栏 ---
    let pW = pattern.width
    let pH = pattern.height
    let totalBeads = pattern.score.totalBeads
    let colorCount = pattern.score.colorCount
    let estMin = pattern.score.estimatedMinutes
    let statsText = "\(pW)x\(pH)  |  \(totalBeads) beads  |  \(colorCount) colors  |  ~\(estMin)"
    drawString(&pixels, bufW: A4_W, bufH: A4_H, text: statsText,
               x0: MARGIN, y0: MARGIN + TITLE_H, scale: 3, r: 80, g: 80, b: 80)

    // 分隔线
    fillRect(&pixels, bufW: A4_W, bufH: A4_H,
             x0: MARGIN, y0: CONTENT_TOP - 10, w: A4_W - MARGIN * 2, h: 1,
             r: 220, g: 220, b: 220, a: 255)

    // --- 计算格子尺寸 ---
    let maxCellW = GRID_AREA_W / pW
    let maxCellH = GRID_AREA_H / pH
    let cellSize = max(8, min(maxCellW, maxCellH))
    let gridPixelW = pW * cellSize
    let gridPixelH = pH * cellSize

    // 格子居中在主区域
    let gridX0 = MARGIN + (GRID_AREA_W - gridPixelW) / 2
    let gridY0 = CONTENT_TOP + (GRID_AREA_H - gridPixelH) / 2

    // --- 渲染格子图纸 ---
    drawGridSection(&pixels, pattern: pattern, cellSize: cellSize,
                    gx0: gridX0, gy0: gridY0, gridW: gridPixelW, gridH: gridPixelH)

    // 圆形裁切 + 边框（徽章模式）
    if exportOpts?.circularCrop == true {
        let radius = Double(min(gridPixelW, gridPixelH)) / 2
        let centerX = Double(gridX0) + Double(gridPixelW) / 2
        let centerY = Double(gridY0) + Double(gridPixelH) / 2
        let borderWidth = max(3, Int((Double(cellSize) * 1.5).rounded()))
        let bc = parseBorderColor(exportOpts?.borderColor ?? "#333333")
        for py in gridY0..<(gridY0 + gridPixelH) {
            for px in gridX0..<(gridX0 + gridPixelW) {
                let dx = Double(px) - centerX
                let dy = Double(py) - centerY
                let dist = sqrt(dx * dx + dy * dy)
                let pi = (py * A4_W + px) * 4
                if dist > Double(radius) {
                    pixels[pi] = 255; pixels[pi + 1] = 255; pixels[pi + 2] = 255; pixels[pi + 3] = 255
                } else if dist > Double(radius) - Double(borderWidth) {
                    pixels[pi] = bc.0; pixels[pi + 1] = bc.1; pixels[pi + 2] = bc.2; pixels[pi + 3] = 255
                }
            }
        }
    }

    // --- 侧栏：原图 + 色卡 ---
    let sidebarX = A4_W - MARGIN - SIDEBAR_W
    let sidebarY = CONTENT_TOP

    // 原图缩略图
    let thumbMaxW = SIDEBAR_W
    let thumbMaxH = 400
    if let photoPixels, photoW > 0 && photoH > 0 {
        let thumbScale = min(Double(thumbMaxW) / Double(photoW), Double(thumbMaxH) / Double(photoH))
        let tw = floorInt(Double(photoW) * thumbScale)
        let th = floorInt(Double(photoH) * thumbScale)
        let thumbX = sidebarX + (SIDEBAR_W - tw) / 2
        let thumbY = sidebarY

        // 原图边框
        fillRect(&pixels, bufW: A4_W, bufH: A4_H,
                 x0: thumbX - 2, y0: thumbY - 2, w: tw + 4, h: th + 4,
                 r: 180, g: 180, b: 180, a: 255)
        // 缩放并写入原图像素
        for y in 0..<th {
            for x in 0..<tw {
                let sx = min(Int(Double(x) / thumbScale), photoW - 1)
                let sy = min(Int(Double(y) / thumbScale), photoH - 1)
                let si = (sy * photoW + sx) * 4
                let di = ((thumbY + y) * A4_W + (thumbX + x)) * 4
                let a = photoPixels[si + 3]
                if a < 128 {
                    let checker = (x / 8 + y / 8) % 2
                    let v: UInt8 = checker != 0 ? 230 : 245
                    pixels[di] = v; pixels[di + 1] = v; pixels[di + 2] = v; pixels[di + 3] = 255
                } else {
                    pixels[di] = photoPixels[si]
                    pixels[di + 1] = photoPixels[si + 1]
                    pixels[di + 2] = photoPixels[si + 2]
                    pixels[di + 3] = 255
                }
            }
        }
    }

    // 色卡对照表
    let chartY0 = sidebarY + thumbMaxH + 40
    let chartX0 = sidebarX
    drawColorChart(&pixels, colorCounts: pattern.colorCounts,
                   x0: chartX0, y0: chartY0,
                   width: SIDEBAR_W,
                   height: A4_H - chartY0 - MARGIN - FOOTER_H - 20)

    // --- 页脚 ---
    let today = Date()
    let cal = Calendar(identifier: .gregorian)
    let components = cal.dateComponents([.year, .month, .day], from: today)
    let dateStr = "\(components.year ?? 2026)-\(pad2(components.month ?? 1))-\(pad2(components.day ?? 1))"
    let footerText = "Generated by MiLens  |  \(dateStr)"
    drawString(&pixels, bufW: A4_W, bufH: A4_H, text: footerText,
               x0: MARGIN, y0: A4_H - MARGIN - FOOTER_H + 20, scale: 2, r: 160, g: 160, b: 160)

    // 页脚分隔线
    fillRect(&pixels, bufW: A4_W, bufH: A4_H,
             x0: MARGIN, y0: A4_H - MARGIN - FOOTER_H, w: A4_W - MARGIN * 2, h: 1,
             r: 220, g: 220, b: 220, a: 255)

    return pixels
}

// MARK: - 导出工具

/// 获取 A4 尺寸 @ 300DPI。对应源端 `getA4Size`。
public func getA4Size() -> CanvasSize {
    return CanvasSize(A4_W, A4_H)
}
