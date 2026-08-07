import Foundation

// BeadOutline — 颜色边界轮廓绘制。
// 逐行翻译自源端 shared/.../bead/BeadOutline.ets（319 行）。
// 7 种模式：none/black/dark/inner_dark/outer_dark/outer_black/mixed。
// 外轮廓（空格边缘）vs 内部边界（颜色变化），保护区跳过。
// 复用已迁移的 labToRgb 代替源端内部简化版（行为等价）。

/// 对颜色索引网格执行轮廓绘制。返回可能扩展后的 palette（新增暗化色/黑色）。
/// 对应源端 `drawOutline`。原地修改 indices。
public func drawOutline(
    _ indices: inout [UInt16], w: Int, h: Int,
    palette: [BeadColor], mode: String,
    protectMask: [UInt8]? = nil, empty: [UInt8]? = nil,
    pose: BeadPoseData? = nil
) -> [BeadColor] {
    if mode == "none" { return palette }

    var resultPalette = palette
    let paletteLab = precomputePaletteLab(palette)

    // 第一步：找边界格并区分外轮廓 / 内部边界
    var outerBorders = Set<Int>()
    var innerBorders = Set<Int>()

    for y in 0..<h {
        for x in 0..<w {
            let i = y * w + x
            if empty != nil && empty![i] != 0 { continue }
            if protectMask != nil && protectMask![i] != 0 { continue }
            let myIdx = Int(indices[i])
            var isBorder = false
            var isOuter = false

            if x > 0 && Int(indices[y * w + (x - 1)]) != myIdx { isBorder = true }
            if !isBorder && x < w - 1 && Int(indices[y * w + (x + 1)]) != myIdx { isBorder = true }
            if !isBorder && y > 0 && Int(indices[(y - 1) * w + x]) != myIdx { isBorder = true }
            if !isBorder && y < h - 1 && Int(indices[(y + 1) * w + x]) != myIdx { isBorder = true }

            if !isBorder, let empty {
                if x > 0 && empty[y * w + (x - 1)] != 0 { isBorder = true; isOuter = true }
                if !isBorder && x < w - 1 && empty[y * w + (x + 1)] != 0 { isBorder = true; isOuter = true }
                if !isBorder && y > 0 && empty[(y - 1) * w + x] != 0 { isBorder = true; isOuter = true }
                if !isBorder && y < h - 1 && empty[(y + 1) * w + x] != 0 { isBorder = true; isOuter = true }
            }

            if isBorder && !isOuter, let empty {
                if (x > 0 && empty[y * w + (x - 1)] != 0) ||
                   (x < w - 1 && empty[y * w + (x + 1)] != 0) ||
                   (y > 0 && empty[(y - 1) * w + x] != 0) ||
                   (y < h - 1 && empty[(y + 1) * w + x] != 0) {
                    isOuter = true
                }
            }

            if isBorder {
                if isOuter { outerBorders.insert(i) } else { innerBorders.insert(i) }
            }
        }
    }

    if outerBorders.isEmpty && innerBorders.isEmpty { return resultPalette }

    // 第二步：根据 mode 分配目标和样式
    var targetOuter = Set<Int>()
    var targetInner = Set<Int>()
    var outerStyle = "none"
    var innerStyle = "none"

    switch mode {
    case "black":
        targetOuter = outerBorders; targetInner = innerBorders; outerStyle = "black"; innerStyle = "black"
    case "dark":
        targetOuter = outerBorders; targetInner = innerBorders; outerStyle = "dark"; innerStyle = "dark"
    case "inner_dark":
        targetInner = innerBorders; innerStyle = "soft_dark"
    case "outer_dark":
        targetOuter = outerBorders; outerStyle = "dark"
    case "outer_black":
        targetOuter = outerBorders; outerStyle = "black"
    case "mixed":
        targetOuter = outerBorders; targetInner = innerBorders; outerStyle = "dark"; innerStyle = "soft_dark"
    default:
        return resultPalette
    }

    // 第三步：应用轮廓

    // 黑色轮廓
    var blackTargets = Set<Int>()
    if outerStyle == "black" { blackTargets.formUnion(targetOuter) }
    if innerStyle == "black" { blackTargets.formUnion(targetInner) }
    if !blackTargets.isEmpty {
        resultPalette = applyBlackOutline(&indices, palette: resultPalette, paletteLab: paletteLab, targets: blackTargets)
    }

    // 暗化轮廓
    var darkTargets = Set<Int>()
    if outerStyle == "dark" { darkTargets.formUnion(targetOuter) }
    if innerStyle == "dark" { darkTargets.formUnion(targetInner) }
    if !darkTargets.isEmpty {
        resultPalette = applyDarkOutline(&indices, palette: resultPalette, paletteLab: paletteLab, targets: darkTargets, lDrop: 20)
    }

    // 轻微暗化（内部边界专用，含 pose 智能内轮廓）
    var softDarkTargets = Set<Int>()
    if innerStyle == "soft_dark" {
        var activeKpts: [(px: Double, py: Double)] = []
        if let pose {
            for k in 0..<min(pose.keypoints.count, 3) {
                if pose.keypoints[k].confidence > 0.3 {
                    activeKpts.append((px: pose.keypoints[k].x * Double(w), py: pose.keypoints[k].y * Double(h)))
                }
            }
        }
        let kptOutlineRadius = 2.0
        let kptOutlineRadiusSq = kptOutlineRadius * kptOutlineRadius

        for i in targetInner {
            if activeKpts.isEmpty {
                softDarkTargets.insert(i)
                continue
            }
            let x = i % w, y = i / w
            for kpt in activeKpts {
                let dx = Double(x) - kpt.px, dy = Double(y) - kpt.py
                if dx * dx + dy * dy < kptOutlineRadiusSq {
                    softDarkTargets.insert(i)
                    break
                }
            }
        }
    }
    if !softDarkTargets.isEmpty {
        resultPalette = applyDarkOutline(&indices, palette: resultPalette, paletteLab: paletteLab, targets: softDarkTargets, lDrop: 10)
    }

    return resultPalette
}

// MARK: - 内部实现

/// 将指定边界格替换为黑色。对应源端 `applyBlackOutline`（私有）。
private func applyBlackOutline(
    _ indices: inout [UInt16], palette: [BeadColor], paletteLab: [LabColor],
    targets: Set<Int>
) -> [BeadColor] {
    var resultPalette = palette
    var darkestIdx = 0
    var darkestL = 101.0
    for p in 0..<paletteLab.count {
        if paletteLab[p].L < darkestL { darkestL = paletteLab[p].L; darkestIdx = p }
    }
    var outlineColorIdx = darkestIdx
    if darkestL > 15 {
        resultPalette.append(BeadColor(id: "_outline_black", name: "轮廓黑",
                                        rgb: RGBColor(15, 15, 15), symbol: "OL", brand: ""))
        outlineColorIdx = resultPalette.count - 1
    }
    for i in targets {
        indices[i] = UInt16(outlineColorIdx)
    }
    return resultPalette
}

/// 将指定边界格暗化。对应源端 `applyDarkOutline`（私有）。
private func applyDarkOutline(
    _ indices: inout [UInt16], palette: [BeadColor], paletteLab: [LabColor],
    targets: Set<Int>, lDrop: Double
) -> [BeadColor] {
    var darkPalette = palette

    // 按原始色索引分组边界格
    var borderByColor: [Int: [Int]] = [:]
    for i in targets {
        let origIdx = Int(indices[i])
        borderByColor[origIdx, default: []].append(i)
    }

    for origIdx in borderByColor.keys.sorted() {
        let positions = borderByColor[origIdx]!
        let origLab = paletteLab[origIdx]
        let darkL = max(5, origLab.L - lDrop)
        let saturationReduction = lDrop <= 12 ? 0.75 : 0.6
        let darkA = origLab.a * saturationReduction
        let darkB = origLab.b * saturationReduction
        let darkRgb = labToRgb(darkL, darkA, darkB)

        darkPalette.append(BeadColor(
            id: palette[origIdx].id + "_dark",
            name: palette[origIdx].name + "(暗)",
            rgb: darkRgb, symbol: palette[origIdx].symbol, brand: ""
        ))
        let newIdx = darkPalette.count - 1
        for pos in positions {
            indices[pos] = UInt16(newIdx)
        }
    }
    return darkPalette
}
