import Foundation

// BeadFlowLogic — 拼豆图纸流程编排的纯决策逻辑。
// 翻译自源端 entry/.../pages/BeadPatternPage.ets（doGenerate 装配 / 结果展示 / 导出前置）
// 与 components/BeadSettingsPanel.ets / BeadPatternResult.ets 中的决策分支，
// 供 App 层 BeadViewModel 使用，可在 Linux/CI 上独立测试。
// 页面级副作用（图片加载、抠图、像素 IO、保存相册）不在此层。

// MARK: - 生成阶段状态机

/// 生成任务阶段。对应源端 BeadPatternPage 的 isGenerating / isCuttingOut / pattern 组合。
public enum BeadGenerationPhase: Equatable {
    case idle
    /// 生成中；cutoutInProgress 为 true 时展示"智能抠图"文案（对应源端 isCuttingOut）。
    case generating(cutoutInProgress: Bool)
    case success
    case failure
}

/// 是否可启动新的生成（源端 doGenerate 的 `if (this.isGenerating) return`）。
public func canStartBeadGeneration(_ phase: BeadGenerationPhase) -> Bool {
    if case .generating = phase { return false }
    return true
}

/// 生成中主文案。对应源端 LoadingProgress 下方文本。
public func beadPhaseTitle(_ phase: BeadGenerationPhase) -> String {
    if case .generating(let cutout) = phase {
        return cutout ? "正在智能抠图..." : "正在生成拼豆图纸..."
    }
    return ""
}

/// 生成中副文案。对应源端 LoadingProgress 第二行文本。
public func beadPhaseSubtitle(_ phase: BeadGenerationPhase) -> String {
    if case .generating(let cutout) = phase {
        return cutout ? "识别宠物轮廓并去除背景" : "分析颜色并匹配拼豆色卡"
    }
    return ""
}

// MARK: - 生成参数装配（源端 doGenerate 的 resolved 部分）

/// 从设置状态解析完整生成参数。对应源端：
/// ```ts
/// const resolved = BeadPresetResolver.resolve(styleKey, maxDim, overridesFromControls(...))
/// if (options.stylizedDraft) {
///   options.stylizedDraft.abstractionLevel = vmResolveAbstractionLevel(selectedAbstractLevel)
/// }
/// ```
public func resolveBeadGeneration(settings: BeadSettings) -> ResolvedBeadGeneration {
    let maxDim = BEAD_SIZE_PRESETS[settings.sizeKey]?.maxDim ?? 58
    let overrides = BeadPresetResolver.overridesFromControls(
        colorKey: settings.colorKey,
        dithering: settings.ditherKey,
        outline: settings.outline,
        denoise: settings.denoise,
        useSubjectCutout: settings.cutout)
    let resolved = BeadPresetResolver.resolve(settings.styleKey, gridSize: maxDim, overrides: overrides)
    var options = resolved.options
    if options.stylizedDraft != nil {
        options.stylizedDraft?.abstractionLevel = resolveAbstractionLevel(settings.abstractLevel)
    }
    return ResolvedBeadGeneration(options: options, generation: resolved.generation,
                                  recipe: resolved.recipe, isAuto: resolved.isAuto)
}

// MARK: - 结果展示决策

/// 画布缩放钳制。对应源端结果页缩放区（0.5…5.0）。
public func clampBeadCanvasScale(_ scale: Double) -> Double {
    Swift.max(0.5, Swift.min(5.0, scale))
}

/// 画布缩放步进（±0.25 后钳制）。对应源端结果页 − / + 按钮。
public func stepBeadCanvasScale(_ scale: Double, delta: Double) -> Double {
    clampBeadCanvasScale(scale + delta)
}

/// 合法视图模式白名单。对应源端 `BeadViewMode`（'color' | 'mard' | 'letter'）。
public func normalizeBeadViewMode(_ mode: BeadViewMode) -> BeadViewMode {
    if mode == "color" || mode == "letter" || mode == "mard" { return mode }
    return "color"
}

/// 徽章预览绘制选项。对应源端 BeadPatternResult.badgeDrawOpts。
public func beadDrawOptions(styleKey: String, pattern: BeadPattern?) -> BeadDrawOptions? {
    guard styleKey == "badge_v1", let pattern else { return nil }
    return BeadDrawOptions(circularCrop: true, borderColor: deriveBadgeBorderColor(pattern))
}

/// 徽章导出选项。对应源端 BeadPatternPage.badgeExportOpts。
public func beadExportOptions(styleKey: String, pattern: BeadPattern?) -> BeadExportOpts? {
    guard styleKey == "badge_v1", let pattern else { return nil }
    return BeadExportOpts(circularCrop: true, borderColor: deriveBadgeBorderColor(pattern))
}

/// 结果页顶部统计行。对应源端 BeadPatternResult 的统计 Row。
/// 格式："{w}x{h} | {totalBeads} 颗 | {colorCount} 色 | 预计 {estimatedMinutes} 分钟"。
public func beadStatsLine(_ pattern: BeadPattern) -> String {
    return "\(pattern.width)x\(pattern.height) | \(pattern.score.totalBeads) 颗 | "
        + "\(pattern.score.colorCount) 色 | 预计 \(pattern.score.estimatedMinutes) 分钟"
}

// MARK: - 材料清单

/// 材料清单行。对应源端 BeadPatternResult 的 ForEach(colorCounts) 行。
public struct BeadMaterialRow: Equatable, Identifiable {
    public let letter: String
    public let symbol: String
    public let name: String
    public let rgb: RGBColor
    public let count: Int
    public let suggestedBuyCount: Int

    public init(letter: String, symbol: String, name: String, rgb: RGBColor,
                count: Int, suggestedBuyCount: Int) {
        self.letter = letter
        self.symbol = symbol
        self.name = name
        self.rgb = rgb
        self.count = count
        self.suggestedBuyCount = suggestedBuyCount
    }

    public var id: String { "\(letter)\(symbol)" }
}

/// 组装材料清单（字母从 A 开始编号）。对应源端 `String.fromCharCode(65 + index)`。
public func beadMaterialRows(_ pattern: BeadPattern) -> [BeadMaterialRow] {
    return pattern.colorCounts.enumerated().map { index, cc in
        let letter = String(UnicodeScalar(65 + index)!)
        return BeadMaterialRow(letter: letter, symbol: cc.symbol, name: cc.name,
                               rgb: cc.rgb, count: cc.count,
                               suggestedBuyCount: cc.suggestedBuyCount)
    }
}

/// 概括度滑块文案。对应源端 BeadSettingsPanel 的 `≤0.2 精细 / ≤0.5 适中 / ≤0.8 概括 / 极简`。
public func abstractionLevelLabel(_ level: Double) -> String {
    if level <= 0.2 { return "精细" }
    if level <= 0.5 { return "适中" }
    if level <= 0.8 { return "概括" }
    return "极简"
}

// MARK: - 导出 / 分享决策

/// 是否可开始导出。对应源端 exportPattern/sharePattern 的前置守卫。
public func canStartBeadExport(isExporting: Bool, hasPattern: Bool) -> Bool {
    return !isExporting && hasPattern
}

// MARK: - Toast 文案

/// 用户提示消息。对应源端 showToast 的文案。
public enum BeadToastMessage: Equatable {
    case missingSource
    case generationFailed
    case exportSuccess
    case exportFailed
}

public func beadToastText(_ message: BeadToastMessage) -> String {
    switch message {
    case .missingSource: return "未找到来源照片，请返回后重新进入"
    case .generationFailed: return "生成失败，请重试或关闭智能抠图"
    case .exportSuccess: return "✅ 高清图纸已保存到相册"
    case .exportFailed: return "❌ 导出失败，请重试"
    }
}
