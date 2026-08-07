import Foundation

// BeadColorSpace — RGB/Lab 转换 + DeltaE76 + 色板匹配。
// 逐行翻译自源端 shared/.../bead/BeadColorSpace.ets，行为一致性由
// MiLensKitTests/BeadColorSpaceTests.swift 守护（对照源端 Hypium 用例）。

// MARK: - sRGB ↔ 线性 RGB

private func srgbToLinear(_ channel: Double) -> Double {
    let c = channel / 255.0
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
}

/// 源端 `linearToSrgb`：clamp 到 [0,1] 后取整。JS `Math.round` 对非负数等价于
/// `.rounded(.toNearestOrAwayFromZero)`（输入经 clamp 已非负）。
private func linearToSrgb(_ c: Double) -> Int {
    let clamped = max(0.0, min(1.0, c))
    if clamped <= 0.0031308 {
        return Int((clamped * 12.92 * 255).rounded(.toNearestOrAwayFromZero))
    } else {
        return Int(((1.055 * pow(clamped, 1.0 / 2.4) - 0.055) * 255).rounded(.toNearestOrAwayFromZero))
    }
}

private func linearToXyz(_ lr: Double, _ lg: Double, _ lb: Double) -> XyzColor {
    return XyzColor(
        x: lr * 0.4124564 + lg * 0.3575761 + lb * 0.1804375,
        y: lr * 0.2126729 + lg * 0.7151522 + lb * 0.0721750,
        z: lr * 0.0193339 + lg * 0.1191920 + lb * 0.9503041
    )
}

// MARK: - XYZ ↔ Lab

private func labF(_ t: Double) -> Double {
    let delta = 6.0 / 29.0
    return t > delta * delta * delta ? cbrt(t) : t / (3.0 * delta * delta) + 4.0 / 29.0
}

private func xyzToLab(_ x: Double, _ y: Double, _ z: Double) -> LabColor {
    let fx = labF(x / 0.95047)
    let fy = labF(y / 1.0)
    let fz = labF(z / 1.08883)
    return LabColor(L: 116.0 * fy - 16.0, a: 500.0 * (fx - fy), b: 200.0 * (fy - fz))
}

private func labToXyz(_ L: Double, _ a: Double, _ b: Double) -> XyzColor {
    let fy = (L + 16.0) / 116.0
    let fx = a / 500.0 + fy
    let fz = fy - b / 200.0
    let delta = 6.0 / 29.0
    let xr = fx > delta ? fx * fx * fx : (116.0 * fx - 16.0) / (3.0 * delta * delta)
    let yr = L > 8.0 ? fy * fy * fy : L / (3.0 * delta * delta)
    let zr = fz > delta ? fz * fz * fz : (116.0 * fz - 16.0) / (3.0 * delta * delta)
    return XyzColor(x: xr * 0.95047, y: yr * 1.0, z: zr * 1.08883)
}

// MARK: - 公共转换

/// RGB(0–255) → CIELAB。对应源端 `rgbToLab`。
public func rgbToLab(_ r: Double, _ g: Double, _ b: Double) -> LabColor {
    let xyz = linearToXyz(srgbToLinear(r), srgbToLinear(g), srgbToLinear(b))
    return xyzToLab(xyz.x, xyz.y, xyz.z)
}

/// CIELAB → sRGB(0–255)。对应源端 `labToRgb`（源端返回 number[3]，Swift 返回 RGBColor）。
public func labToRgb(_ L: Double, _ a: Double, _ b: Double) -> RGBColor {
    let xyz = labToXyz(L, a, b)
    let lr = xyz.x * 3.2404542 + xyz.y * -1.5371385 + xyz.z * -0.4985314
    let lg = xyz.x * -0.9692660 + xyz.y * 1.8760108 + xyz.z * 0.0415560
    let lb = xyz.x * 0.0556434 + xyz.y * -0.2040259 + xyz.z * 1.0572252
    return RGBColor(linearToSrgb(lr), linearToSrgb(lg), linearToSrgb(lb))
}

// MARK: - 色差

/// Delta E 1976（欧几里得距离）。对应源端 `deltaE76`。
public func deltaE76(_ lab1: LabColor, _ lab2: LabColor) -> Double {
    let dL = lab1.L - lab2.L
    let da = lab1.a - lab2.a
    let db = lab1.b - lab2.b
    return sqrt(dL * dL + da * da + db * db)
}

/// 带亮度加权的 Delta E。对应源端 `weightedDeltaE`。
public func weightedDeltaE(_ lab1: LabColor, _ lab2: LabColor) -> Double {
    return deltaE76(lab1, lab2) * 1.0 + abs(lab1.L - lab2.L) * 0.4
}

// MARK: - 色度

/// Lab 色彩的 chroma（饱和度指标），忽略亮度。对应源端 `labChroma`。
public func labChroma(_ lab: LabColor) -> Double {
    return sqrt(lab.a * lab.a + lab.b * lab.b)
}

// MARK: - 色板匹配距离（含美学调整）

/// 高饱和冷色风险评分（私有）。对应源端 `coolHighChromaRisk`。
private func coolHighChromaRisk(_ lab: LabColor) -> Double {
    let chroma = sqrt(lab.a * lab.a + lab.b * lab.b)
    let chromaRisk = max(0, min(1, (chroma - 30) / 35))
    let coolAxis = max(-lab.b, -lab.a * 0.75)
    let coolRisk = max(0, min(1, (coolAxis - 5) / 30))
    return chromaRisk * coolRisk
}

/// 中间调近中性色优先使用带轻微冷暖倾向的灰（私有）。对应源端 `grayAestheticAdjustment`。
private func grayAestheticAdjustment(_ source: LabColor, _ candidate: LabColor, _ baseDistance: Double) -> Double {
    let sourceChroma = labChroma(source)
    let candidateChroma = labChroma(candidate)
    if source.L <= 25 || source.L >= 75 || sourceChroma >= 8 || candidateChroma >= 10 { return 0 }

    if abs(candidate.a) < 1.5 && abs(candidate.b) < 1.5 { return 12 }

    var reward: Double = 0
    if candidate.b < -2 && candidate.b > -10 {
        reward = 3.5
    } else if candidate.a > 0 && candidate.b > 2 && candidate.b < 8 {
        reward = 2.5
    }
    // tint 偏好不能让明显更差的候选仅因调整后距离趋近零而胜出。
    return -min(reward, baseDistance * 0.35)
}

/// 色板匹配距离：在 weightedDeltaE 基础上叠加宠物友好的美学约束。
/// 对应源端 `paletteMatchDistance`。含白毛/粉红/色相保持等多项保护逻辑，逐行忠实翻译。
public func paletteMatchDistance(
    _ source: LabColor,
    _ candidate: LabColor,
    petFriendlyPenalty: Double = 0
) -> Double {
    let base = weightedDeltaE(source, candidate)
    var d = base

    if petFriendlyPenalty > 0 {
        d += petFriendlyPenalty * coolHighChromaRisk(candidate) * (1 - coolHighChromaRisk(source))
    }

    let sourceChroma = labChroma(source)
    let candidateChroma = labChroma(candidate)

    // 双方都有色相时保持源色相族，避免减少色板时红→蓝等跨色相映射。
    if sourceChroma > 16 && candidateChroma > 12 {
        let hueSimilarity = (source.a * candidate.a + source.b * candidate.b)
            / (sourceChroma * candidateChroma)
        if hueSimilarity < 0.2 {
            d += (0.2 - hueSimilarity) * min(28, sourceChroma * 0.65)
        }
    }
    // 深红棕（如 F10）不应成为蓝/绿/紫源色的通用深色兜底。
    if sourceChroma > 18 && candidate.a > 12 && candidate.b > 12
        && (source.a < 2 || source.b < 2) {
        d += min(30, (candidate.a + candidate.b - 24) * 0.45)
    }

    if sourceChroma < 12 && candidateChroma > sourceChroma + 8 {
        d += (candidateChroma - sourceChroma - 8) * 0.8
    }
    // 灰/白毛需要贯穿高光与阴影的中性走廊。
    if sourceChroma < 18 {
        let allowedChroma = source.L > 68
            ? max(9, sourceChroma + 2)
            : max(12, sourceChroma + 4)
        if candidateChroma > allowedChroma {
            let excess = candidateChroma - allowedChroma
            d += excess * (source.L > 68 ? 2.2 : 1.7)
        }
    }
    if sourceChroma < 8 {
        if candidate.b < -4 { d += 8.0 }      // 偏蓝
        if candidate.a < -6 { d += 5.0 }      // 偏绿
        if candidateChroma > 14 { d += 4.0 }  // 过饱和
    }

    // 高亮白毛保护：亮部更不能蓝。
    if source.L > 75 && sourceChroma < 12 {
        if candidate.b < -3 { d += 10.0 }
        if candidate.L < source.L - 12 { d += 4.0 }
        if candidateChroma > sourceChroma + 3 {
            d += (candidateChroma - sourceChroma - 3) * 1.6
        }
    }

    if source.L > 68 && sourceChroma < 18 {
        let tintedEdge = max(abs(candidate.a), abs(candidate.b))
        if tintedEdge > 7 { d += (tintedEdge - 7) * 1.4 }
    }

    // 保持粉色与粉调灰。
    let pinkAxis = max(0, source.a - max(0, -source.b) * 0.25)
    let coolShift = max(source.b - candidate.b, source.a - candidate.a)
    if pinkAxis > 0.75 && coolShift > 1.5 {
        d += min(24, (coolShift - 1.5) * min(1.2, 0.45 + pinkAxis / 18))
    }

    d += grayAestheticAdjustment(source, candidate, base)
    return d
}

// MARK: - 最近色查找

/// 在色板 Lab 数组中查找最近色。对应源端 `findNearestBeadColor`。
public func findNearestBeadColor(
    _ L: Double, _ a: Double, _ b: Double,
    paletteLab: [LabColor],
    petFriendlyPenalty: Double = 0
) -> NearestColorResult {
    var bestIdx = 0
    var bestDist = Double.infinity
    let target = LabColor(L: L, a: a, b: b)
    for i in 0..<paletteLab.count {
        let dist = paletteMatchDistance(target, paletteLab[i], petFriendlyPenalty: petFriendlyPenalty)
        if dist < bestDist {
            bestDist = dist
            bestIdx = i
        }
    }
    return NearestColorResult(index: bestIdx, distance: bestDist)
}

/// 从 RGB 查找最近色板色。对应源端 `findNearestBeadColorRgb`。
public func findNearestBeadColorRgb(
    _ r: Double, _ g: Double, _ b: Double,
    paletteLab: [LabColor],
    petFriendlyPenalty: Double = 0
) -> NearestColorResult {
    let lab = rgbToLab(r, g, b)
    return findNearestBeadColor(lab.L, lab.a, lab.b, paletteLab: paletteLab, petFriendlyPenalty: petFriendlyPenalty)
}

/// 预计算色板的 Lab 数组。对应源端 `precomputePaletteLab`。
public func precomputePaletteLab(_ colors: [BeadColor]) -> [LabColor] {
    return colors.map { rgbToLab(Double($0.rgb.r), Double($0.rgb.g), Double($0.rgb.b)) }
}
