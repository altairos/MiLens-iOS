import Foundation

// BeadPatternService — 拼豆图纸生成主入口 / 编排器。
// 翻译自源端 shared/.../bead/BeadPatternService.ets（760 行）。
//
// 架构差异（DESIGN.md §8）：
// - 源端 Native C++ + ArkTS fallback 双路径 → iOS 合并为纯 Swift 单一路径
// - 源端 TaskPool + jobId 取消表 → iOS async/await + Task.checkCancellation()
// - 源端 AppErrorHandler/TaskLogger → 静默降级（纯算法库不含任务日志）

// MARK: - 错误类型

/// 拼豆生成错误。对应源端 `throw new Error(...)` 的分类化版本。
public enum BeadPatternError: Error, Equatable {
    case invalidSourceSize(width: Int, height: Int)
    case invalidSourceBuffer(got: Int, expected: Int)
    case invalidTargetSize(width: Int, height: Int)
    case invalidColorLimit(Int)
    case unknownPalette(String)
    case canceled
}

// MARK: - 输入校验

/// 校验生成输入。对应源端 `validateGenerationInput`。
/// Swift 的 Int 天然是安全整数且无小数，省略源端的 isSafeInteger / Math.floor 检查。
func validateGenerationInput(
    srcPixels: [UInt8], srcW: Int, srcH: Int, options: BeadGenerateOptions
) throws {
    let sourcePixels = srcW * srcH
    let validSourceSize = srcW > 0 && srcH > 0 && srcW <= 32768 && srcH <= 32768 &&
        sourcePixels <= 64 * 1024 * 1024
    if !validSourceSize {
        throw BeadPatternError.invalidSourceSize(width: srcW, height: srcH)
    }
    let requiredBytes = sourcePixels * 4
    if srcPixels.count < requiredBytes {
        throw BeadPatternError.invalidSourceBuffer(got: srcPixels.count, expected: requiredBytes)
    }
    let validTarget = options.targetWidth > 0 && options.targetHeight > 0 &&
        options.targetWidth <= 256 && options.targetHeight <= 256
    if !validTarget {
        throw BeadPatternError.invalidTargetSize(width: options.targetWidth, height: options.targetHeight)
    }
    if options.maxColors < 2 || options.maxColors > 512 {
        throw BeadPatternError.invalidColorLimit(options.maxColors)
    }
}

// MARK: - 同步入口

/// 生成拼豆图纸（同步）。对应源端 `generateBeadPattern`（单路径，无 Native fallback）。
public func generateBeadPattern(
    srcPixels: [UInt8], srcW: Int, srcH: Int,
    options: BeadGenerateOptions, subject: BeadSubjectContext? = nil
) throws -> BeadPattern {
    try validateGenerationInput(srcPixels: srcPixels, srcW: srcW, srcH: srcH, options: options)
    return try generateBeadPatternCore(srcPixels: srcPixels, srcW: srcW, srcH: srcH,
                                       options: options, subject: subject)
}

// MARK: - 异步入口（支持取消）

/// 异步生成拼豆图纸。对应源端 `generateBeadPatternAsync`。
/// 取消方式：调用方 `Task.cancel()`，内部在关键点通过 `Task.checkCancellation()` 抛出 `CancellationError`。
/// CPU 密集工作为同步执行；调用方需在合适优先级的 Task 中调用以避免阻塞主 actor。
public func generateBeadPatternAsync(
    srcPixels: [UInt8], srcW: Int, srcH: Int,
    options: BeadGenerateOptions, subject: BeadSubjectContext? = nil
) async throws -> BeadPattern {
    try Task.checkCancellation()
    try validateGenerationInput(srcPixels: srcPixels, srcW: srcW, srcH: srcH, options: options)
    return try generateBeadPatternCore(srcPixels: srcPixels, srcW: srcW, srcH: srcH,
                                       options: options, subject: subject)
}

// MARK: - 核心生成管线

/// 核心生成管线（纯 Swift 单路径）。对应源端 `generateBeadPatternArkTS`。
func generateBeadPatternCore(
    srcPixels src: [UInt8], srcW: Int, srcH: Int,
    options: BeadGenerateOptions, subject: BeadSubjectContext? = nil
) throws -> BeadPattern {
    // 1. 复制源像素，将主体 mask 混入 alpha 通道
    var srcPixels = src
    if let mask = subject?.mask, mask.count == srcW * srcH {
        for i in 0..<mask.count {
            srcPixels[i * 4 + 3] = min(srcPixels[i * 4 + 3], mask[i])
        }
    }

    // 2. 裁切 + 人脸 ROI
    let crop = computePatternCrop(srcW: srcW, srcH: srcH, mode: options.mode, subject: subject)
    let faceRoi = computeFaceRoi(crop: crop, gridW: options.targetWidth, gridH: options.targetHeight,
                                 mode: options.mode, subject: subject)

    // 3. 提取裁切区域
    try Task.checkCancellation()
    var cropped = [UInt8](repeating: 0, count: crop.w * crop.h * 4)
    for y in 0..<crop.h {
        for x in 0..<crop.w {
            let si = ((crop.y + y) * srcW + (crop.x + x)) * 4
            let di = (y * crop.w + x) * 4
            cropped[di] = srcPixels[si]; cropped[di + 1] = srcPixels[si + 1]
            cropped[di + 2] = srcPixels[si + 2]; cropped[di + 3] = srcPixels[si + 3]
        }
    }

    // 4. 两阶段缩放：先放大到 4× 再做面积缩放到目标尺寸
    let midW = options.targetWidth * 4
    let midH = options.targetHeight * 4
    var midPixels = areaResizeRgba(cropped, srcW: crop.w, srcH: crop.h, dstW: midW, dstH: midH)
    let neutralReferencePixels = areaResizeRgba(
        cropped, srcW: crop.w, srcH: crop.h, dstW: options.targetWidth, dstH: options.targetHeight)

    // 5. 预处理：USM 锐化 / 色彩增强 / 主体感知
    if options.outline { applyUnsharpMask(&midPixels, w: midW, h: midH, amount: options.outlineStrength) }
    if options.preserveBrightness {
        enhancePetColors(
            &midPixels, pixelCount: midW * midH,
            saturationBoost: options.saturationBoost, contrastBoost: options.contrastBoost,
            shadowLiftAmount: options.shadowLift, autoWhiteBalanceStrength: options.autoWhiteBalanceStrength,
            vibranceBoost: options.vibranceBoost, brightnessBoost: options.brightnessBoost,
            neutralGuardStrength: options.neutralGuardStrength, highlightProtectStrength: options.highlightProtectStrength)
    }
    if let subject {
        applySubjectAwareEnhancements(
            &midPixels, width: midW, height: midH, crop: crop, srcW: srcW, srcH: srcH,
            subject: subject,
            options: SubjectEnhanceOptions(
                subjectLocalContrast: options.subjectLocalContrast,
                backgroundDesaturation: options.backgroundDesaturation,
                backgroundBlurStrength: options.backgroundBlurStrength,
                targetWidth: options.targetWidth, targetHeight: options.targetHeight))
    }

    // 6. 最终缩放 + 空格掩码
    try Task.checkCancellation()
    let finalPixels = areaResizeRgba(midPixels, srcW: midW, srcH: midH,
                                     dstW: options.targetWidth, dstH: options.targetHeight)
    var empty = [UInt8](repeating: 0, count: options.targetWidth * options.targetHeight)
    for i in 0..<empty.count {
        empty[i] = finalPixels[i * 4 + 3] < 128 ? 1 : 0
    }
    if options.mode == "badge" { applyBadgeMask(&empty, w: options.targetWidth, h: options.targetHeight) }

    // 7. 保护掩码 + Pose 保护
    var protectMask = buildProtectMask(
        finalPixels, w: options.targetWidth, h: options.targetHeight, empty: empty,
        protectionStrength: options.featureProtectionStrength, faceRoi: faceRoi,
        attentionHeatmap: subject?.attentionHeatmap)
    applyPoseProtection(
        &protectMask, empty, gridW: options.targetWidth, gridH: options.targetHeight,
        crop: crop, srcW: srcW, srcH: srcH, subject: subject)

    // 8. 加载色卡池 + 自适应主色提取
    guard let paletteDef = getBeadPalette(options.paletteId) else {
        throw BeadPatternError.unknownPalette(options.paletteId)
    }
    let allPaletteColors = paletteDef.colors

    let dominantColors = medianCutExtract(
        pixels: finalPixels, pixelCount: options.targetWidth * options.targetHeight,
        targetColors: options.maxColors, empty: empty, protectMask: protectMask)
    let selectedColors = selectBestPaletteColors(
        dominantColors: dominantColors, allPaletteColors: allPaletteColors,
        maxColors: options.maxColors, lightnessBucketCoverage: options.lightnessBucketCoverage,
        petFriendlyPenalty: options.petFriendlyPenalty, sourcePixels: neutralReferencePixels, empty: empty)
    let paletteLab = precomputePaletteLab(selectedColors)

    // 9. 风格化底稿（概括度控制）
    try Task.checkCancellation()
    var draftOverridePixels: [UInt8]? = nil
    if options.stylizedDraft?.enabled == true, let draftOpts = options.stylizedDraft {
        let draftSubject = subject.map {
            mapSubjectContextToGrid(options.targetWidth, options.targetHeight, crop, srcW, srcH, $0)
        }
        let draftResult = generateStylizedDraft(
            rgba: finalPixels, width: options.targetWidth, height: options.targetHeight,
            options: draftOpts, subjectCtx: draftSubject)
        var overridePx = [UInt8](repeating: 0, count: finalPixels.count)
        for i in 0..<draftResult.indices.count {
            let pi = i * 4
            let virtualIndex = Int(draftResult.indices[i])
            if virtualIndex == 255 || virtualIndex >= draftResult.virtualPalette.count {
                overridePx[pi + 3] = 0
                continue
            }
            let rgb = draftResult.virtualPalette[virtualIndex].rgb
            overridePx[pi] = UInt8(max(0, min(255, rgb[0]))); overridePx[pi + 1] = UInt8(max(0, min(255, rgb[1])))
            overridePx[pi + 2] = UInt8(max(0, min(255, rgb[2]))); overridePx[pi + 3] = finalPixels[pi + 3]
        }
        draftOverridePixels = overridePx
    }
    let workSource = draftOverridePixels ?? finalPixels

    // 10. 抖动 + 色卡映射
    var indices: [UInt16]
    if options.dithering == "adaptive" {
        indices = mapToPalette(workSource, w: options.targetWidth, h: options.targetHeight,
                               paletteLab: paletteLab, empty: empty, petFriendlyPenalty: options.petFriendlyPenalty)
        var ditherPixels = workSource
        applyAdaptiveBayerDither(
            &ditherPixels, w: options.targetWidth, h: options.targetHeight,
            paletteLab: paletteLab, protectMask: protectMask, empty: empty,
            faceRoi: faceRoi, petFriendlyPenalty: options.petFriendlyPenalty, indicesOut: &indices)
    } else if options.dithering == "light" || options.dithering == "medium" {
        let strength = options.dithering == "light" ? 0.5 : 1.0
        var workPixels = workSource
        applyFloydSteinbergSerpentine(
            &workPixels, w: options.targetWidth, h: options.targetHeight,
            paletteLab: paletteLab, strength: strength,
            protectMask: protectMask, empty: empty, petFriendlyPenalty: options.petFriendlyPenalty)
        indices = mapToPalette(workPixels, w: options.targetWidth, h: options.targetHeight,
                               paletteLab: paletteLab, empty: empty, petFriendlyPenalty: options.petFriendlyPenalty)
    } else {
        indices = mapToPalette(workSource, w: options.targetWidth, h: options.targetHeight,
                               paletteLab: paletteLab, empty: empty, petFriendlyPenalty: options.petFriendlyPenalty)
    }

    // 11. 去噪
    try Task.checkCancellation()
    remapReferenceNeutralPixels(&indices, referencePixels: neutralReferencePixels,
                                paletteLab: paletteLab, empty: empty)
    if options.denoise {
        removeIsolatedPixels(&indices, w: options.targetWidth, h: options.targetHeight,
                             protectMask: protectMask, empty: empty)
        let topDominantIdx = computeTopDominantIndices(indices: indices, empty: empty, topN: 5)
        mergeSmallRegions(
            &indices, w: options.targetWidth, h: options.targetHeight,
            minSize: options.cleanupSmallRegionMinSize, protectMask: protectMask, empty: empty,
            faceRoi: faceRoi, paletteLab: paletteLab, dominantColorIndices: topDominantIdx,
            featureProtectionStrength: options.featureProtectionStrength, qMode: false)
    }

    // 12. 最小使用量合并
    var effectiveBeads = 0
    for i in 0..<empty.count where empty[i] == 0 { effectiveBeads += 1 }
    let threshold = max(3, Int(Double(effectiveBeads) * options.tinyColorUsageRatio))
    let mergeResult = mergeTinyColorsByPalette(
        indices, w: options.targetWidth, h: options.targetHeight,
        paletteUsed: selectedColors, threshold: threshold, protectMask: protectMask, empty: empty)
    indices = mergeResult.indices
    var usedPalette = mergeResult.paletteUsed

    // 13. 眼睛高光补偿
    if options.eyeEnhance {
        applyEyeHighlight(&indices, w: options.targetWidth, h: options.targetHeight,
                          palette: usedPalette, originalPixels: finalPixels,
                          empty: empty, faceRoi: faceRoi)
    }

    // 14. 轮廓绘制
    if options.outlineDrawMode != "none" {
        usedPalette = drawOutline(
            &indices, w: options.targetWidth, h: options.targetHeight,
            palette: usedPalette, mode: options.outlineDrawMode,
            protectMask: protectMask, empty: empty, pose: subject?.pose)
    }
    cleanFinalNeutralFringes(&indices, w: options.targetWidth, h: options.targetHeight,
                             paletteLab: precomputePaletteLab(usedPalette),
                             sourcePixels: neutralReferencePixels, empty: empty)
    enforceReferenceNeutralRgb(&indices, w: options.targetWidth, h: options.targetHeight,
                               referencePixels: neutralReferencePixels, palette: usedPalette, empty: empty)

    // 15. 统计 + 评分 + 诊断
    let colorCounts = computePatternColorCounts(indices: indices, paletteUsed: usedPalette, empty: empty)
    let score = computePatternDifficulty(colorCounts: colorCounts, totalPixels: effectiveBeads,
                                         w: options.targetWidth, h: options.targetHeight)
    let diagnostics = computeDiagnostics(indices: indices, w: options.targetWidth, h: options.targetHeight,
                                         paletteUsed: usedPalette, originalPixels: finalPixels, empty: empty)

    return BeadPattern(
        width: options.targetWidth, height: options.targetHeight,
        indices: indices, empty: empty, protectMask: protectMask, faceRoi: faceRoi,
        paletteUsed: usedPalette, colorCounts: colorCounts, warnings: [],
        score: score, diagnostics: diagnostics,
        shortSymbols: generatePatternShortSymbols(paletteUsed: usedPalette, colorCounts: colorCounts))
}

// MARK: - 自动模式候选风格

/// 候选风格参数组合。对应源端 `AutoStyleCandidate`。
private struct AutoStyleCandidate {
    let name: String
    let mode: BeadMode
    let preferredColorCounts: [Int]
    let saturationBoost: Double
    let contrastBoost: Double
    let shadowLift: Double
    let outlineStrength: Double
    let cleanupSmallRegionMinSize: Int
    let lightnessBucketCoverage: Double
    let petFriendlyPenalty: Double
    let outlineDrawMode: BeadOutlineDrawMode
    let autoWhiteBalanceStrength: Double
    let vibranceBoost: Double
    let brightnessBoost: Double
    let neutralGuardStrength: Double
    let highlightProtectStrength: Double
}

/// 自动模式候选风格矩阵。对应源端 `AUTO_STYLE_CANDIDATES`。
private let AUTO_STYLE_CANDIDATES: [AutoStyleCandidate] = [
    AutoStyleCandidate(name: "清爽插画风", mode: "tight_face",
                       preferredColorCounts: [12, 24, 40, 60],
                       saturationBoost: 1.16, contrastBoost: 1.12, shadowLift: 0.12,
                       outlineStrength: 0.70, cleanupSmallRegionMinSize: 3,
                       lightnessBucketCoverage: 0.9, petFriendlyPenalty: 7,
                       outlineDrawMode: "dark",
                       autoWhiteBalanceStrength: 0.65, vibranceBoost: 1.20, brightnessBoost: 1.03,
                       neutralGuardStrength: 0.9, highlightProtectStrength: 0.85),
    AutoStyleCandidate(name: "写实还原风", mode: "portrait",
                       preferredColorCounts: [24, 40, 60],
                       saturationBoost: 1.06, contrastBoost: 1.05, shadowLift: 0.06,
                       outlineStrength: 0.25, cleanupSmallRegionMinSize: 1,
                       lightnessBucketCoverage: 0.35, petFriendlyPenalty: 0,
                       outlineDrawMode: "none",
                       autoWhiteBalanceStrength: 0.35, vibranceBoost: 1.06, brightnessBoost: 1.01,
                       neutralGuardStrength: 0.8, highlightProtectStrength: 0.9),
    AutoStyleCandidate(name: "清晰徽章风", mode: "badge",
                       preferredColorCounts: [16, 24],
                       saturationBoost: 1.18, contrastBoost: 1.15, shadowLift: 0.12,
                       outlineStrength: 0.55, cleanupSmallRegionMinSize: 3,
                       lightnessBucketCoverage: 0.8, petFriendlyPenalty: 8,
                       outlineDrawMode: "outer_dark",
                       autoWhiteBalanceStrength: 0.7, vibranceBoost: 1.18, brightnessBoost: 1.02,
                       neutralGuardStrength: 0.9, highlightProtectStrength: 0.8),
]

/// 从候选风格 + 色数构造生成选项。
private func makeAutoOptions(
    style: AutoStyleCandidate, maxK: Int, targetWidth: Int, targetHeight: Int,
    paletteId: String, outline: Bool, denoise: Bool
) -> BeadGenerateOptions {
    return BeadGenerateOptions(
        targetWidth: targetWidth, targetHeight: targetHeight, maxColors: maxK,
        paletteId: paletteId, mode: style.mode, backgroundMode: "light",
        outline: outline, dithering: "none", denoise: denoise,
        eyeEnhance: true, preserveBrightness: true,
        outlineStrength: style.outlineStrength, saturationBoost: style.saturationBoost,
        contrastBoost: style.contrastBoost, shadowLift: style.shadowLift,
        cleanupSmallRegionMinSize: style.cleanupSmallRegionMinSize,
        tinyColorUsageRatio: 0.002, lightnessBucketCoverage: style.lightnessBucketCoverage,
        petFriendlyPenalty: style.petFriendlyPenalty, outlineDrawMode: style.outlineDrawMode,
        featureProtectionStrength: 0.7, autoWhiteBalanceStrength: style.autoWhiteBalanceStrength,
        vibranceBoost: style.vibranceBoost, brightnessBoost: style.brightnessBoost,
        neutralGuardStrength: style.neutralGuardStrength,
        highlightProtectStrength: style.highlightProtectStrength,
        subjectLocalContrast: 0, backgroundDesaturation: 0, backgroundBlurStrength: 0)
}

/// 自动模式回退选项（所有候选都失败时使用）。
private func makeAutoFallbackOptions(
    targetWidth: Int, targetHeight: Int, paletteId: String,
    outline: Bool, denoise: Bool
) -> BeadGenerateOptions {
    return BeadGenerateOptions(
        targetWidth: targetWidth, targetHeight: targetHeight, maxColors: 24,
        paletteId: paletteId, mode: "portrait", backgroundMode: "light",
        outline: outline, dithering: "none", denoise: denoise,
        eyeEnhance: true, preserveBrightness: true,
        outlineStrength: 0.6, saturationBoost: 1.12, contrastBoost: 1.10,
        shadowLift: 0.10, cleanupSmallRegionMinSize: 2, tinyColorUsageRatio: 0.002,
        lightnessBucketCoverage: 0.8, petFriendlyPenalty: 6, outlineDrawMode: "none",
        featureProtectionStrength: 0.6, autoWhiteBalanceStrength: 0.5,
        vibranceBoost: 1.12, brightnessBoost: 1.02,
        neutralGuardStrength: 0.8, highlightProtectStrength: 0.8,
        subjectLocalContrast: 0, backgroundDesaturation: 0, backgroundBlurStrength: 0)
}

// MARK: - 自动模式（同步）

/// 自动模式：色数 × 风格矩阵中用 TriScore 选最优。对应源端 `generateBeadPatternAuto`。
public func generateBeadPatternAuto(
    srcPixels: [UInt8], srcW: Int, srcH: Int,
    targetWidth: Int, targetHeight: Int,
    paletteId: String, outline: Bool, denoise: Bool
) throws -> BeadPattern {
    let limit = getColorLimitBySize(width: targetWidth, height: targetHeight, preset: "standard")
    var best: BeadPattern? = nil
    var bestScore = -Double.infinity
    var candidateCount = 0

    for style in AUTO_STYLE_CANDIDATES {
        for k in style.preferredColorCounts {
            let maxK = min(k, limit)
            if maxK < k && k > 24 { continue }
            if candidateCount >= 8 { break }
            candidateCount += 1

            let options = makeAutoOptions(style: style, maxK: maxK, targetWidth: targetWidth,
                                          targetHeight: targetHeight, paletteId: paletteId,
                                          outline: outline, denoise: denoise)
            do {
                let p = try generateBeadPattern(srcPixels: srcPixels, srcW: srcW, srcH: srcH, options: options)
                guard p.diagnostics != nil else { continue }
                let tri = computeTriScore(p.toRef())
                var pp = p
                pp.triScore = tri
                if tri.overall > bestScore {
                    bestScore = tri.overall
                    pp.autoColorHint = "已自动选择 \(pp.score.colorCount) 色 · \(style.name)（综合 \(tri.overall) 分）"
                    best = pp
                }
            } catch {
                // 单个候选失败 → 跳过继续
            }
        }
        if candidateCount >= 8 { break }
    }

    if let best { return best }
    let fallback = makeAutoFallbackOptions(targetWidth: targetWidth, targetHeight: targetHeight,
                                           paletteId: paletteId, outline: outline, denoise: denoise)
    var p = try generateBeadPattern(srcPixels: srcPixels, srcW: srcW, srcH: srcH, options: fallback)
    p.autoColorHint = "已使用 24 种颜色（默认）"
    return p
}

// MARK: - 自动模式（异步，支持取消）

/// 异步自动模式。对应源端 `generateBeadPatternAutoAsync`。
/// 每个候选间检查取消；单个候选失败跳过，整体取消向上抛出。
public func generateBeadPatternAutoAsync(
    srcPixels: [UInt8], srcW: Int, srcH: Int,
    baseOptions: BeadGenerateOptions, subject: BeadSubjectContext? = nil
) async throws -> BeadPattern {
    var best: BeadPattern? = nil
    var bestScore = -Double.infinity
    var candidateCount = 0

    for style in AUTO_STYLE_CANDIDATES {
        for k in style.preferredColorCounts {
            try Task.checkCancellation()
            let limit = getColorLimitBySize(width: baseOptions.targetWidth, height: baseOptions.targetHeight, preset: "standard")
            let maxK = min(k, limit)
            if maxK < k && k > 24 { continue }
            if candidateCount >= 8 { break }
            candidateCount += 1

            let options = BeadGenerateOptions(
                targetWidth: baseOptions.targetWidth, targetHeight: baseOptions.targetHeight,
                maxColors: maxK, paletteId: baseOptions.paletteId, mode: style.mode,
                backgroundMode: baseOptions.backgroundMode, outline: baseOptions.outline, dithering: "none",
                denoise: baseOptions.denoise, eyeEnhance: baseOptions.eyeEnhance,
                preserveBrightness: baseOptions.preserveBrightness,
                outlineStrength: style.outlineStrength, saturationBoost: style.saturationBoost,
                contrastBoost: style.contrastBoost, shadowLift: style.shadowLift,
                cleanupSmallRegionMinSize: style.cleanupSmallRegionMinSize,
                tinyColorUsageRatio: baseOptions.tinyColorUsageRatio,
                lightnessBucketCoverage: style.lightnessBucketCoverage,
                petFriendlyPenalty: style.petFriendlyPenalty, outlineDrawMode: style.outlineDrawMode,
                featureProtectionStrength: baseOptions.featureProtectionStrength,
                autoWhiteBalanceStrength: style.autoWhiteBalanceStrength,
                vibranceBoost: style.vibranceBoost, brightnessBoost: style.brightnessBoost,
                neutralGuardStrength: style.neutralGuardStrength,
                highlightProtectStrength: style.highlightProtectStrength,
                subjectLocalContrast: baseOptions.subjectLocalContrast,
                backgroundDesaturation: baseOptions.backgroundDesaturation,
                backgroundBlurStrength: baseOptions.backgroundBlurStrength,
                stylizedDraft: baseOptions.stylizedDraft)

            do {
                let pattern = try await generateBeadPatternAsync(
                    srcPixels: srcPixels, srcW: srcW, srcH: srcH, options: options, subject: subject)
                guard pattern.diagnostics != nil else { continue }
                let tri = computeTriScore(pattern.toRef())
                var pp = pattern
                pp.triScore = tri
                if tri.overall > bestScore {
                    bestScore = tri.overall
                    pp.autoColorHint = "已自动选择 \(pp.score.colorCount) 色 · \(style.name)（综合 \(tri.overall) 分）"
                    best = pp
                }
            } catch {
                try Task.checkCancellation()
                // 单个候选失败 → 跳过继续（取消时 checkCancellation 抛出传播）
            }
        }
        if candidateCount >= 8 { break }
    }

    try Task.checkCancellation()
    if let best { return best }

    let fallbackOptions = BeadGenerateOptions(
        targetWidth: baseOptions.targetWidth, targetHeight: baseOptions.targetHeight,
        maxColors: 24, paletteId: baseOptions.paletteId, mode: baseOptions.mode,
        backgroundMode: baseOptions.backgroundMode, outline: baseOptions.outline, dithering: "none",
        denoise: baseOptions.denoise, eyeEnhance: baseOptions.eyeEnhance,
        preserveBrightness: baseOptions.preserveBrightness,
        outlineStrength: baseOptions.outlineStrength, saturationBoost: baseOptions.saturationBoost,
        contrastBoost: baseOptions.contrastBoost, shadowLift: baseOptions.shadowLift,
        cleanupSmallRegionMinSize: baseOptions.cleanupSmallRegionMinSize,
        tinyColorUsageRatio: baseOptions.tinyColorUsageRatio,
        lightnessBucketCoverage: baseOptions.lightnessBucketCoverage,
        petFriendlyPenalty: baseOptions.petFriendlyPenalty,
        outlineDrawMode: baseOptions.outlineDrawMode,
        featureProtectionStrength: baseOptions.featureProtectionStrength,
        autoWhiteBalanceStrength: baseOptions.autoWhiteBalanceStrength,
        vibranceBoost: baseOptions.vibranceBoost, brightnessBoost: baseOptions.brightnessBoost,
        neutralGuardStrength: baseOptions.neutralGuardStrength,
        highlightProtectStrength: baseOptions.highlightProtectStrength,
        subjectLocalContrast: baseOptions.subjectLocalContrast,
        backgroundDesaturation: baseOptions.backgroundDesaturation,
        backgroundBlurStrength: baseOptions.backgroundBlurStrength,
        stylizedDraft: baseOptions.stylizedDraft)
    var fallback = try await generateBeadPatternAsync(
        srcPixels: srcPixels, srcW: srcW, srcH: srcH, options: fallbackOptions, subject: subject)
    try Task.checkCancellation()
    fallback.autoColorHint = "已使用 24 种颜色（默认）"
    return fallback
}
