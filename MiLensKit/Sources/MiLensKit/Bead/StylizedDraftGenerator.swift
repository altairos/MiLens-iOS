import Foundation

// StylizedDraftGenerator — 风格化底稿统一调度器
// 逐行翻译自源端 shared/.../bead/StylizedDraftGenerator.ets。
//
// 管线流程：
// 1. 图像预处理（vibrance / saturation / contrast / brightness / warmth）
// 2. 背景处理（降饱和 / 模糊 / 清空）
// 3. 虚拟色板提取（加权 Median Cut）
// 4. 像素→虚拟色板映射
// 5. 特征保护 + 孤点清理
// 6. 诊断信息计算

// MARK: - 辅助

@inline(__always)
private func cl255(_ v: Double) -> Double {
    max(0, min(255, v.rounded()))
}

// MARK: - 公共 API

/// 风格化底稿生成入口。
public func generateStylizedDraft(
    rgba: [UInt8],
    width: Int,
    height: Int,
    options: StylizedDraftOptions,
    subjectCtx: BeadSubjectContext? = nil
) -> StylizedDraftResult {
    let total = width * height
    var pixels = rgba

    applyImageEnhancement(&pixels, width: width, height: height,
                          options: options, mask: subjectCtx?.mask)

    // T2b: 关键点制导的局部对比度刚性扩张（pose=null 时跳过）
    if let pose = subjectCtx?.pose {
        applyPoseGuidedContrast(&pixels, width: width, height: height, pose: pose)
    }

    if let mask = subjectCtx?.mask, options.subjectOnly {
        applyBackgroundTreatment(&pixels, width: width, height: height,
                                 mask: mask, options: options)
    }

    let virtualCount = getAbstractionColorCount(level: options.abstractionLevel,
                                                base: options.virtualColorCount)
    var palette = buildVirtualPalette(rgba: pixels, width: width, height: height,
                                      count: virtualCount, mask: subjectCtx?.mask, seed: 42)

    // 灰色救赎 G1：合并虚拟色板中 Lab 距离过近的低色度灰色
    let grayMergeResult = mergeGrayVirtualColors(palette)
    palette = grayMergeResult.palette

    var indices = mapPixelsToVirtualPalette(rgba: pixels, width: width, height: height,
                                            palette: palette, pose: subjectCtx?.pose)

    let featureMask: [UInt8]?
    if options.preserveFaceFeatures, let ctx = subjectCtx, let mask = ctx.mask {
        featureMask = estimateFeatureMask(mask: mask, width: width, height: height,
                                          bbox: ctx.bbox)
    } else {
        featureMask = nil
    }

    indices = protectAndCleanup(
        indices, width: width, height: height,
        featureMask: featureMask, subjectMask: subjectCtx?.mask,
        preserveFace: options.preserveFaceFeatures,
        preservePattern: options.preservePatternRegions,
        pose: subjectCtx?.pose
    )

    if options.backgroundMode == .empty, let mask = subjectCtx?.mask {
        for i in 0..<total {
            if mask[i] == 0 { indices[i] = 255 }
        }
    }

    // 灰色救赎 G2：非主体灰色像素重定向为透明
    if let mask = subjectCtx?.mask, options.subjectOnly, options.backgroundMode != .empty {
        for i in 0..<total {
            if mask[i] != 0 { continue }   // 只处理非主体像素
            if indices[i] == 255 { continue } // 已经是空的
            let idx = Int(indices[i])
            if idx < palette.count {
                let vc = palette[idx]
                let ch = (vc.lab[1] * vc.lab[1] + vc.lab[2] * vc.lab[2]).squareRoot()
                if ch < 10 {
                    indices[i] = 255 // 低色度灰色 → 透明
                }
            }
        }
    }

    // 灰色救赎 G3：Q版模式中间调灰阶跃合并
    if options.styleMode == .cute, let mask = subjectCtx?.mask, let fMask = featureMask {
        // 找到色板中最亮的非灰色虚拟色（用作纯白目标）
        var brightestNonGrayIdx = -1
        var brightestL: Double = 0
        // 找到面积最大的高饱和色（用作合并目标）
        var colorCounts: [Int: Int] = [:]
        for i in 0..<total {
            if indices[i] == 255 { continue }
            if mask[i] == 0 { continue }
            colorCounts[Int(indices[i]), default: 0] += 1
        }
        var dominantIdx = -1
        var dominantCount = 0
        for (idx, cnt) in colorCounts {
            guard idx < palette.count else { continue }
            let vc = palette[idx]
            let ch = (vc.lab[1] * vc.lab[1] + vc.lab[2] * vc.lab[2]).squareRoot()
            if ch > 10 && cnt > dominantCount {
                dominantCount = cnt
                dominantIdx = idx
            }
            if vc.lab[0] > brightestL {
                brightestL = vc.lab[0]
                brightestNonGrayIdx = idx
            }
        }

        for i in 0..<total {
            if indices[i] == 255 { continue }
            if mask[i] == 0 { continue }
            if fMask[i] != 0 { continue } // 特征保护区内的灰保留（五官暗色）
            let idx = Int(indices[i])
            guard idx < palette.count else { continue }
            let vc = palette[idx]
            let ch = (vc.lab[1] * vc.lab[1] + vc.lab[2] * vc.lab[2]).squareRoot()
            let L = vc.lab[0]
            // 仅处理中间调灰色
            if ch >= 8 || L <= 25 || L >= 85 { continue }
            // L > 75 的浅灰 → 归为最亮色（纯白效果）
            if L > 75 && brightestNonGrayIdx >= 0 {
                indices[i] = UInt8(brightestNonGrayIdx)
            } else if dominantIdx >= 0 {
                // 其他中间调灰 → 合并到面积最大的高饱和主色
                indices[i] = UInt8(dominantIdx)
            }
        }
    }

    let diagnostics = computeDiagnostics(indices, width: width, height: height,
                                         palette: palette, mask: subjectCtx?.mask)

    return StylizedDraftResult(
        width: width, height: height,
        indices: indices, virtualPalette: palette,
        featureMask: featureMask, subjectMask: subjectCtx?.mask,
        diagnostics: diagnostics
    )
}

// MARK: - 抽象级别

private func getAbstractionColorCount(level: StylizedDraftAbstractionLevel, base: Int) -> Int {
    switch level {
    case .low:    return min(base + 4, 24)
    case .high:   return max(base - 2, 4)
    case .extreme: return max(base * 6 / 10, 4) // floor(base * 0.6)
    case .medium: return base
    }
}

// MARK: - 图像增强

private func applyImageEnhancement(
    _ pixels: inout [UInt8],
    width: Int, height: Int,
    options: StylizedDraftOptions,
    mask: [UInt8]?
) {
    let total = width * height
    let sat = options.saturationBoost, con = options.contrastBoost
    let bri = options.brightnessBoost, vib = options.vibranceBoost
    let warmth = options.warmthBoost
    if sat == 1 && con == 1 && bri == 1 && vib == 1 && warmth == 0 { return }

    for i in 0..<total {
        let pi = i * 4
        if pixels[pi + 3] < 128 { continue }
        if let mask = mask, mask[i] == 0 { continue }

        var r = Double(pixels[pi])
        var g = Double(pixels[pi + 1])
        var b = Double(pixels[pi + 2])

        if bri != 1 {
            r = cl255(r * bri)
            g = cl255(g * bri)
            b = cl255(b * bri)
        }
        if con != 1 {
            r = cl255((r - 128) * con + 128)
            g = cl255((g - 128) * con + 128)
            b = cl255((b - 128) * con + 128)
        }
        if sat != 1 || vib != 1 {
            let gray = 0.299 * r + 0.587 * g + 0.114 * b
            let curSat = max(abs(r - gray), abs(g - gray), abs(b - gray)) / 255
            let vibMult = vib != 1 ? 1 + (vib - 1) * (1 - curSat) : 1
            let eff = sat * vibMult
            r = cl255(gray + (r - gray) * eff)
            g = cl255(gray + (g - gray) * eff)
            b = cl255(gray + (b - gray) * eff)
        }
        if warmth != 0 {
            r = cl255(r + warmth * 30)
            b = cl255(b - warmth * 20)
        }

        pixels[pi] = UInt8(cl255(r))
        pixels[pi + 1] = UInt8(cl255(g))
        pixels[pi + 2] = UInt8(cl255(b))
    }
}

// MARK: - 背景处理

private func applyBackgroundTreatment(
    _ pixels: inout [UInt8],
    width: Int, height: Int,
    mask: [UInt8],
    options: StylizedDraftOptions
) {
    let total = width * height
    switch options.backgroundMode {
    case .desaturate:
        let f = 1 - options.backgroundDesaturation
        for i in 0..<total {
            if mask[i] != 0 { continue }
            let pi = i * 4
            if pixels[pi + 3] < 128 { continue }
            let r = Double(pixels[pi])
            let g = Double(pixels[pi + 1])
            let b = Double(pixels[pi + 2])
            let gray = 0.299 * r + 0.587 * g + 0.114 * b
            pixels[pi] = UInt8(cl255(gray + (r - gray) * f))
            pixels[pi + 1] = UInt8(cl255(gray + (g - gray) * f))
            pixels[pi + 2] = UInt8(cl255(gray + (b - gray) * f))
        }
    case .blur:
        if options.backgroundBlurRadius > 0 {
            applyBgBlur(&pixels, width: width, height: height,
                        mask: mask, radius: options.backgroundBlurRadius)
        }
    case .replacePlain:
        for i in 0..<total {
            if mask[i] != 0 { continue }
            let pi = i * 4
            pixels[pi] = 240; pixels[pi + 1] = 240; pixels[pi + 2] = 238; pixels[pi + 3] = 255
        }
    case .keep, .empty:
        break
    }
}

// MARK: - T2b: 关键点制导局部对比度

/// 关键点制导局部对比度刚性扩张。
/// 在五官关键点邻域执行 L* 通道两极化推离：
/// - 暗者更暗（强化眼线/瞳孔）
/// - 亮者更亮（强化高光/边缘）
private func applyPoseGuidedContrast(
    _ pixels: inout [UInt8],
    width: Int, height: Int,
    pose: BeadPoseData
) {
    let kpts = pose.keypoints
    if kpts.isEmpty { return }

    // 只使用高置信度关键点（眼睛 0,1 + 鼻子 2）
    let activeKpts = activeKeypoints(from: pose, width: width, height: height)
    if activeKpts.isEmpty { return }

    let sigma: Double = 1.5 // 格为单位的衰减半径
    let gain: Double = 0.35
    let radius = 2  // 5×5 local window for L* mean

    // 只读副本
    let src = pixels

    for y in 0..<height {
        for x in 0..<width {
            let i = y * width + x
            let pi = i * 4
            if src[pi + 3] < 128 { continue }

            // 计算关键点距离权重 ω_kpt = max GaussianDecay
            var omega: Double = 0
            for kpt in activeKpts {
                let dist = ((Double(x) - kpt.px) * (Double(x) - kpt.px) +
                            (Double(y) - kpt.py) * (Double(y) - kpt.py)).squareRoot()
                let w = exp(-(dist * dist) / (2 * sigma * sigma))
                if w > omega { omega = w }
            }
            if omega < 0.1 { continue } // 太远不受影响

            // 计算局部 L* 均值（从只读副本）
            var lSum: Double = 0
            var cnt = 0
            for dy in -radius...radius {
                for dx in -radius...radius {
                    let nx = x + dx, ny = y + dy
                    if nx < 0 || nx >= width || ny < 0 || ny >= height { continue }
                    let ni = ny * width + nx
                    let npi = ni * 4
                    if src[npi + 3] < 128 { continue }
                    lSum += 0.299 * Double(src[npi]) + 0.587 * Double(src[npi + 1]) + 0.114 * Double(src[npi + 2])
                    cnt += 1
                }
            }
            if cnt == 0 { continue }
            let localMean = lSum / Double(cnt)

            // 当前像素亮度
            let lum = 0.299 * Double(src[pi]) + 0.587 * Double(src[pi + 1]) + 0.114 * Double(src[pi + 2])
            let diff = lum - localMean

            // L* 两极化推离
            var boost = gain * abs(diff) * omega
            // 中间调权重：极暗/极亮区域少增强
            let midWeight = lum > 20 && lum < 235 ? 1.0 : 0.3
            boost *= midWeight

            if diff < 0 {
                // 暗者更暗
                let factor = 1 + boost / 255
                pixels[pi] = UInt8(cl255(Double(src[pi]) * (1 / factor)))
                pixels[pi + 1] = UInt8(cl255(Double(src[pi + 1]) * (1 / factor)))
                pixels[pi + 2] = UInt8(cl255(Double(src[pi + 2]) * (1 / factor)))
            } else {
                // 亮者更亮
                let factor = 1 + boost / 255
                pixels[pi] = UInt8(cl255(Double(src[pi]) * factor))
                pixels[pi + 1] = UInt8(cl255(Double(src[pi + 1]) * factor))
                pixels[pi + 2] = UInt8(cl255(Double(src[pi + 2]) * factor))
            }
        }
    }
}

// MARK: - 背景模糊

private func applyBgBlur(
    _ pixels: inout [UInt8],
    width: Int, height: Int,
    mask: [UInt8],
    radius: Int
) {
    let r = max(1, min(radius, 5))
    let tmp = pixels // 只读副本
    for y in 0..<height {
        for x in 0..<width {
            let idx = y * width + x
            if mask[idx] != 0 { continue }
            var sR: Double = 0, sG: Double = 0, sB: Double = 0
            var cnt = 0
            for dy in -r...r {
                for dx in -r...r {
                    let nx = x + dx, ny = y + dy
                    if nx < 0 || nx >= width || ny < 0 || ny >= height { continue }
                    let ni = ny * width + nx
                    if mask[ni] != 0 { continue }
                    let pi = ni * 4
                    if tmp[pi + 3] < 128 { continue }
                    sR += Double(tmp[pi])
                    sG += Double(tmp[pi + 1])
                    sB += Double(tmp[pi + 2])
                    cnt += 1
                }
            }
            if cnt > 0 {
                let pi = idx * 4
                pixels[pi] = UInt8((sR / Double(cnt)).rounded())
                pixels[pi + 1] = UInt8((sG / Double(cnt)).rounded())
                pixels[pi + 2] = UInt8((sB / Double(cnt)).rounded())
            }
        }
    }
}

// MARK: - 诊断

private func computeDiagnostics(
    indices: [UInt8],
    width: Int, height: Int,
    palette: [VirtualColor],
    mask: [UInt8]?
) -> DraftDiagnostics {
    let total = width * height
    var used = Set<Int>()
    var subjTotal = 0, cleanCount = 0, neutralCount = 0
    var counts: [Int: Int] = [:]

    for i in 0..<total {
        let idx = Int(indices[i])
        if idx == 255 { continue }
        used.insert(idx)
        counts[idx, default: 0] += 1
        let isSubj = mask != nil ? mask![i] != 0 : true
        if isSubj {
            subjTotal += 1
            let x = i % width
            let y = i / width
            if x > 0 && x < width - 1 && y > 0 && y < height - 1 {
                if Int(indices[(y - 1) * width + x]) == idx ||
                   Int(indices[(y + 1) * width + x]) == idx ||
                   Int(indices[y * width + (x - 1)]) == idx ||
                   Int(indices[y * width + (x + 1)]) == idx {
                    cleanCount += 1
                }
            }
            if idx < palette.count {
                let vc = palette[idx]
                let ch = (vc.lab[1] * vc.lab[1] + vc.lab[2] * vc.lab[2]).squareRoot()
                if ch < 10 { neutralCount += 1 }
            }
        }
    }

    let avgSize = !used.isEmpty ? Double(subjTotal) / Double(used.count) : 0
    let coverage = subjTotal > 0 ? Double(subjTotal) / Double(subjTotal) : 0
    let cleanliness = subjTotal > 0 ? Double(cleanCount) / Double(subjTotal) : 0
    let neutralRatio = subjTotal > 0 ? Double(neutralCount) / Double(subjTotal) : 0
    let featureScore = min(100, cleanliness * 50 + min(avgSize / 10, 1) * 30 + coverage * 20)

    return DraftDiagnostics(
        usedVirtualColorCount: used.count,
        subjectCoverageRatio: coverage,
        featurePreserveScore: featureScore,
        colorBlockCleanliness: cleanliness,
        neutralShiftRatio: neutralRatio,
        whiteToCoolRatio: 0,
        averageRegionSize: avgSize
    )
}
