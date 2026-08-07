import XCTest
@testable import MiLensKit

// BeadPatternService 可靠性测试。
// 翻译自源端 entry/.../test/BeadPatternReliability.test.ets（6 用例）。
//
// 架构差异（DESIGN.md §8）：
// - 源端 Native C++ vs ArkTS parity 测试 → iOS 单路径，parity 改为确定性回归
// - 源端 jobId + cancelBeadPatternGeneration → iOS Task.cancel() + CancellationError
// - 源端 `as BeadGenerateOptions` 字面量 → iOS BeadGenerateOptions 构造器（全参数）
// - 新增：输入校验、auto 模式确定性、异步取消 3 个用例

// MARK: - Fixture 工厂

/// 构造渐变 RGBA fixture（对应源端 `makeFixture`）。
private func makeFixture(width: Int, height: Int) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            pixels[i] = UInt8((Double(x) * 255 / Double(max(1, width - 1))).rounded())
            pixels[i + 1] = UInt8((Double(y) * 255 / Double(max(1, height - 1))).rounded())
            pixels[i + 2] = (x + y) % 3 == 0 ? 40 : 210
            pixels[i + 3] = (x < 2 && y < 2) ? 0 : 255
        }
    }
    return pixels
}

/// 构造默认生成选项（对应源端 `options()`）。
private func makeOptions() -> BeadGenerateOptions {
    return BeadGenerateOptions(
        targetWidth: 29, targetHeight: 29, maxColors: 12, paletteId: "MARD_72",
        mode: "portrait", backgroundMode: "light", outline: true, dithering: "none",
        denoise: true, eyeEnhance: true, preserveBrightness: true,
        outlineStrength: 0.6, saturationBoost: 1.12, contrastBoost: 1.10,
        shadowLift: 0.10, cleanupSmallRegionMinSize: 2, tinyColorUsageRatio: 0.002,
        lightnessBucketCoverage: 0.8, petFriendlyPenalty: 6, outlineDrawMode: "none",
        featureProtectionStrength: 0.6, autoWhiteBalanceStrength: 0.5,
        vibranceBoost: 1.12, brightnessBoost: 1.02,
        neutralGuardStrength: 0.8, highlightProtectStrength: 0.8,
        subjectLocalContrast: 0, backgroundDesaturation: 0, backgroundBlurStrength: 0)
}

// MARK: - 辅助函数

/// 计算两个 pattern 之间的 RGB 匹配率（对应源端 `matchingRatio`）。
private func matchingRatio(_ a: BeadPattern, _ b: BeadPattern) -> Double {
    var matched = 0
    for i in 0..<a.indices.count {
        let ar = a.paletteUsed[Int(a.indices[i])].rgb
        let br = b.paletteUsed[Int(b.indices[i])].rgb
        if ar.r == br.r && ar.g == br.g && ar.b == br.b { matched += 1 }
    }
    return Double(matched) / Double(a.indices.count)
}

/// 统计保护掩码中标记的格子数（对应源端 `countProtected`）。
private func countProtected(_ pattern: BeadPattern) -> Int {
    return pattern.protectMask.filter { $0 != 0 }.count
}

// MARK: - 测试

final class BeadPatternServiceTests: XCTestCase {

    // MARK: 基本生成

    /// 同步生成应产出合法图纸。对应源端 'Native and ArkTS keep the same contract' 的契约部分。
    func testGenerateProducesValidPattern() throws {
        let fixture = makeFixture(width: 48, height: 36)
        let pattern = try generateBeadPattern(srcPixels: fixture, srcW: 48, srcH: 36, options: makeOptions())

        XCTAssertEqual(pattern.width, 29)
        XCTAssertEqual(pattern.height, 29)
        XCTAssertEqual(pattern.indices.count, 29 * 29)
        XCTAssertEqual(pattern.empty.count, 29 * 29)
        XCTAssertEqual(pattern.protectMask.count, 29 * 29)
        XCTAssertEqual(pattern.paletteUsed.count, pattern.colorCounts.count)
        XCTAssertNotNil(pattern.diagnostics)
        XCTAssertNotNil(pattern.shortSymbols)
        // score.totalBeads 应 ≤ 网格总面积（空格不算）
        XCTAssertLessThanOrEqual(pattern.score.totalBeads, 29 * 29)
    }

    /// 两次相同输入应产出高度一致的结果（确定性回归，替代源端 Native vs ArkTS parity）。
    /// 不要求 100% 一致：底层子模块用 Swift Set/Dictionary 替代 JS Map，
    /// 迭代顺序在 count 相同时可能产生不同合并结果（< 2% 像素差异）。
    func testDeterministicGeneration() throws {
        let fixture = makeFixture(width: 48, height: 36)
        let opts = makeOptions()
        let p1 = try generateBeadPattern(srcPixels: fixture, srcW: 48, srcH: 36, options: opts)
        let p2 = try generateBeadPattern(srcPixels: fixture, srcW: 48, srcH: 36, options: opts)
        XCTAssertGreaterThan(matchingRatio(p1, p2), 0.97, "同输入两次生成 RGB 匹配率应 > 97%")
        XCTAssertEqual(p1.score.totalBeads, p2.score.totalBeads)
    }

    // MARK: subject mask

    /// 主体 mask 应减少有效格子数。对应源端 'Native and ArkTS apply explicit subject mask'。
    func testSubjectMaskReducesBeads() throws {
        let width = 48, height = 36
        var mask = [UInt8](repeating: 0, count: width * height)
        for y in 8..<28 {
            for x in 12..<36 { mask[y * width + x] = 255 }
        }
        let subject = BeadSubjectContext(
            bbox: CropRect(x: 12, y: 8, width: 24, height: 20), mask: mask)
        let pattern = try generateBeadPattern(
            srcPixels: makeFixture(width: width, height: height),
            srcW: width, srcH: height, options: makeOptions(), subject: subject)
        XCTAssertLessThan(pattern.score.totalBeads, width * height,
                         "主体 mask 应减少有效格子（边缘透明格被标记为空）")
    }

    // MARK: feature protection

    /// 特征保护强度越高 → 保护掩码标记的格子越多。对应源端 'feature protection strength affects masks'。
    func testFeatureProtectionStrengthAffectsMask() throws {
        let fixture = makeFixture(width: 48, height: 36)
        var low = makeOptions(); low.featureProtectionStrength = 0
        var high = makeOptions(); high.featureProtectionStrength = 1
        let pLow = try generateBeadPattern(srcPixels: fixture, srcW: 48, srcH: 36, options: low)
        let pHigh = try generateBeadPattern(srcPixels: fixture, srcW: 48, srcH: 36, options: high)
        XCTAssertGreaterThan(countProtected(pHigh), countProtected(pLow),
                            "高保护强度应标记更多保护格")
    }

    // MARK: face ROI

    /// 主体 bbox 偏移时 Face ROI 应跟随。对应源端 'maps shifted subject bbox into the same dynamic Face ROI'。
    func testShiftedSubjectBboxMapsToFaceROI() throws {
        let width = 80, height = 60
        var mask = [UInt8](repeating: 0, count: width * height)
        for y in 18..<54 {
            for x in 40..<76 { mask[y * width + x] = 255 }
        }
        let subject = BeadSubjectContext(
            bbox: CropRect(x: 40, y: 18, width: 36, height: 36), mask: mask)
        var opts = makeOptions()
        opts.targetWidth = 29; opts.targetHeight = 29; opts.mode = "free"
        let pattern = try generateBeadPattern(
            srcPixels: makeFixture(width: width, height: height),
            srcW: width, srcH: height, options: opts, subject: subject)
        let roi = try XCTUnwrap(pattern.faceRoi, "free 模式 + 主体应有 faceRoi")
        XCTAssertGreaterThan(roi.x, opts.targetWidth / 2, "ROI 应跟随偏移的 bbox 落在右半区")
        XCTAssertGreaterThan(roi.y, 0)
    }

    // MARK: diagnostics

    /// 轮廓后处理应使 diagnostics.outlineCoverageRatio > 0。对应源端 'refreshes diagnostics after outline post-processing'。
    func testDiagnosticsAfterOutline() throws {
        var outlined = makeOptions()
        outlined.outlineDrawMode = "dark"
        let pattern = try generateBeadPattern(
            srcPixels: makeFixture(width: 48, height: 36), srcW: 48, srcH: 36, options: outlined)
        let outlineRatio = pattern.diagnostics?.outlineCoverageRatio ?? 0
        XCTAssertGreaterThan(outlineRatio, 0, "dark 轮廓应使 outlineCoverageRatio > 0")
        XCTAssertEqual(pattern.diagnostics?.usedColorCount, pattern.colorCounts.count)
    }

    // MARK: 输入校验（新增）

    func testRejectsInvalidSourceSize() {
        let opts = makeOptions()
        // 0 宽
        XCTAssertThrowsError(try generateBeadPattern(
            srcPixels: [UInt8](repeating: 255, count: 4), srcW: 0, srcH: 10, options: opts))
        // 超大尺寸
        let huge = [UInt8](repeating: 255, count: 4)
        XCTAssertThrowsError(try generateBeadPattern(
            srcPixels: huge, srcW: 40000, srcH: 40000, options: opts))
    }

    func testRejectsInvalidSourceBuffer() {
        let opts = makeOptions()
        // 缓冲区太小
        let tiny = [UInt8](repeating: 255, count: 10)
        XCTAssertThrowsError(try generateBeadPattern(
            srcPixels: tiny, srcW: 48, srcH: 36, options: opts))
    }

    func testRejectsInvalidTargetSize() {
        let fixture = makeFixture(width: 48, height: 36)
        var opts = makeOptions()
        opts.targetWidth = 0; opts.targetHeight = 29
        XCTAssertThrowsError(try generateBeadPattern(
            srcPixels: fixture, srcW: 48, srcH: 36, options: opts))
    }

    func testRejectsInvalidColorLimit() {
        let fixture = makeFixture(width: 48, height: 36)
        var opts = makeOptions()
        opts.maxColors = 1
        XCTAssertThrowsError(try generateBeadPattern(
            srcPixels: fixture, srcW: 48, srcH: 36, options: opts))
    }

    func testRejectsUnknownPalette() {
        let fixture = makeFixture(width: 48, height: 36)
        var opts = makeOptions()
        opts.paletteId = "NONEXISTENT_PALETTE"
        XCTAssertThrowsError(try generateBeadPattern(
            srcPixels: fixture, srcW: 48, srcH: 36, options: opts)) { error in
            guard case BeadPatternError.unknownPalette = error else {
                XCTFail("应抛出 unknownPalette，实际：\(error)"); return
            }
        }
    }

    // MARK: auto 模式（新增）

    func testAutoModeProducesValidPattern() throws {
        let fixture = makeFixture(width: 48, height: 36)
        let pattern = try generateBeadPatternAuto(
            srcPixels: fixture, srcW: 48, srcH: 36,
            targetWidth: 29, targetHeight: 29,
            paletteId: "MARD_72", outline: true, denoise: true)
        XCTAssertEqual(pattern.width, 29)
        XCTAssertEqual(pattern.height, 29)
        XCTAssertNotNil(pattern.autoColorHint, "auto 模式应设置 autoColorHint")
        XCTAssertNotNil(pattern.triScore, "auto 模式应计算 triScore")
    }

    // MARK: 异步 + 取消（新增）

    func testAsyncGenerationProducesSameResultAsSync() async throws {
        let fixture = makeFixture(width: 48, height: 36)
        let opts = makeOptions()
        let syncPattern = try generateBeadPattern(srcPixels: fixture, srcW: 48, srcH: 36, options: opts)
        let asyncPattern = try await generateBeadPatternAsync(
            srcPixels: fixture, srcW: 48, srcH: 36, options: opts)
        // 同步/异步走同一 generateBeadPatternCore，差异仅来自 Set/Dictionary 迭代序。
        XCTAssertGreaterThan(matchingRatio(syncPattern, asyncPattern), 0.97,
                       "同步和异步 RGB 匹配率应 > 97%")
    }

    func testAsyncAutoModeProducesValidPattern() async throws {
        let fixture = makeFixture(width: 48, height: 36)
        let opts = makeOptions()
        let pattern = try await generateBeadPatternAutoAsync(
            srcPixels: fixture, srcW: 48, srcH: 36, baseOptions: opts)
        XCTAssertEqual(pattern.width, 29)
        XCTAssertEqual(pattern.height, 29)
        XCTAssertNotNil(pattern.autoColorHint)
    }

    func testAsyncGenerationCanCancel() async {
        // 核心管线现在在步骤 3/6/9/11 各有 Task.checkCancellation() 检查点，
        // 配合 cancel() 后再 await task.value 确保取消信号被观测。
        let fixture = makeFixture(width: 256, height: 192)
        let opts = makeOptions()
        let task = Task { try await generateBeadPatternAsync(
            srcPixels: fixture, srcW: 256, srcH: 192, options: opts) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("取消的任务应抛出错误")
        } catch {
            // 预期 CancellationError 或 BeadPatternError.canceled
        }
    }
}
