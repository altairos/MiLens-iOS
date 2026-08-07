import Foundation

// EditorSharpnessKernel — 锐化卷积核构造与 RGBA 缓冲区卷积计算。
// 翻译自源端 entry/.../editor/SharpnessKernel.ets（140 行）。
//
// 纯逻辑：无 IO / 无 UI 依赖，可在 Linux 宿主单测完整覆盖。

/// 锐化强度范围常量。对应源端 `MIN_SHARPNESS_STRENGTH` / `MAX_SHARPNESS_STRENGTH`。
public let MIN_SHARPNESS_STRENGTH: Double = 0
public let MAX_SHARPNESS_STRENGTH: Double = 100

/// 3×3 卷积核大小。对应源端 `SHARPEN_KERNEL_SIZE`。
public let SHARPEN_KERNEL_SIZE: Int = 3

/// 把锐化强度（0..100）映射为 3×3 卷积核。对应源端 `buildSharpenKernel`。
///
/// 公式：
/// - amount = strength / 50（strength=100 → amount=2.0）
/// - 中心权重 = 1 + 4 * amount
/// - 4 邻域权重 = -amount
/// - 4 对角权重 = 0
///
/// 返回长度 9 的数组，行优先（row-major）。strength=0 返回单位核（幂等）。
public func buildSharpenKernel(strength: Double) -> [Double] {
    let clamped = clampSharpness(strength)
    let amount = clamped / 50
    let center = 1 + 4 * amount
    let side = -amount
    return [
        0, side, 0,
        side, center, side,
        0, side, 0,
    ]
}

/// 对 RGBA 像素缓冲区应用 3×3 卷积。对应源端 `convolveRgba`。
///
/// - src：原始 RGBA 像素（每像素 4 字节），长度 = width * height * 4
/// - 返回新的 [UInt8]（不修改 src），Alpha 通道原样复制。
/// - 边界采用边缘像素扩展（clamp to edge）。
public func convolveRgba(src: [UInt8], width: Int, height: Int, kernel: [Double]) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: src.count)
    let w = width, h = height
    let identity = isIdentityKernel(kernel)

    for y in 0..<h {
        for x in 0..<w {
            let dstIdx = (y * w + x) * 4
            // Alpha 通道直接复制
            out[dstIdx + 3] = src[dstIdx + 3]

            if identity {
                out[dstIdx] = src[dstIdx]
                out[dstIdx + 1] = src[dstIdx + 1]
                out[dstIdx + 2] = src[dstIdx + 2]
                continue
            }

            var sumR = 0.0, sumG = 0.0, sumB = 0.0
            var ki = 0
            for ky in -1...1 {
                for kx in -1...1 {
                    let sx = clampInt(x + kx, 0, w - 1)
                    let sy = clampInt(y + ky, 0, h - 1)
                    let sIdx = (sy * w + sx) * 4
                    let kw = kernel[ki]
                    sumR += Double(src[sIdx]) * kw
                    sumG += Double(src[sIdx + 1]) * kw
                    sumB += Double(src[sIdx + 2]) * kw
                    ki += 1
                }
            }
            out[dstIdx] = clampByte(sumR)
            out[dstIdx + 1] = clampByte(sumG)
            out[dstIdx + 2] = clampByte(sumB)
        }
    }
    return out
}

/// 把锐化强度钳制到 [0, 100]。NaN/Infinity → 0。对应源端 `clampSharpness`。
public func clampSharpness(_ v: Double) -> Double {
    if !v.isFinite { return MIN_SHARPNESS_STRENGTH }
    return max(MIN_SHARPNESS_STRENGTH, min(MAX_SHARPNESS_STRENGTH, v))
}

// MARK: - 内部辅助

/// 判断卷积核是否为单位核（中心 1，其余 0），用于快速路径。对应源端 `isIdentityKernel`。
private func isIdentityKernel(_ kernel: [Double]) -> Bool {
    kernel.count >= 9 &&
        kernel[4] == 1 &&
        kernel[0] == 0 && kernel[1] == 0 && kernel[2] == 0 &&
        kernel[3] == 0 && kernel[5] == 0 &&
        kernel[6] == 0 && kernel[7] == 0 && kernel[8] == 0
}

/// 把浮点数钳制到 [0, 255] 并四舍五入为字节。对应源端 `clampByte`。
@inline(__always)
private func clampByte(_ v: Double) -> UInt8 {
    if !v.isFinite { return 0 }
    return UInt8(max(0, min(255, v.rounded())))
}

/// 把整数钳制到 [lo, hi]。对应源端 `clampInt`。
@inline(__always)
private func clampInt(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
    max(lo, min(hi, v))
}
