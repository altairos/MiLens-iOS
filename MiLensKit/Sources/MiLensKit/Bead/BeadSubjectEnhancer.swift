import Foundation

// BeadSubjectEnhancer — 主体增强 + 背景简化 + 主体上下文映射。
// 逐行翻译自源端 shared/.../bead/BeadSubjectEnhancer.ets（175 行）。

/// 主体增强选项（对应源端 BeadGenerateOptions 的子集）。
public struct SubjectEnhanceOptions {
    public var subjectLocalContrast: Double
    public var backgroundDesaturation: Double
    public var backgroundBlurStrength: Double
    public var targetWidth: Int
    public var targetHeight: Int

    public init(subjectLocalContrast: Double = 0, backgroundDesaturation: Double = 0,
                backgroundBlurStrength: Double = 0, targetWidth: Int = 58, targetHeight: Int = 58) {
        self.subjectLocalContrast = subjectLocalContrast
        self.backgroundDesaturation = backgroundDesaturation
        self.backgroundBlurStrength = backgroundBlurStrength
        self.targetWidth = targetWidth
        self.targetHeight = targetHeight
    }
}

/// 在中间 RGBA 图上增强主体细节并简化背景。对应源端 `applySubjectAwareEnhancements`。
/// 主体 mask 以原始源宽为行步长采样。原地修改 pixels。
public func applySubjectAwareEnhancements(
    _ pixels: inout [UInt8], width: Int, height: Int, crop: CropArea,
    srcW: Int, srcH: Int, subject: BeadSubjectContext, options: SubjectEnhanceOptions
) {
    var contrastStrength = options.subjectLocalContrast
    let desaturationStrength = options.backgroundDesaturation
    let blurStrength = options.backgroundBlurStrength
    if options.targetWidth <= 29 || options.targetHeight <= 29 {
        let scale = min(1.0, Double(min(options.targetWidth, options.targetHeight)) / 58.0)
        contrastStrength *= scale
    }
    if contrastStrength <= 0 && desaturationStrength <= 0 && blurStrength <= 0 { return }

    let subjectMask = mapSubjectMask(width, height, crop, srcW, srcH, subject.mask ?? [])
    if contrastStrength > 0 { enhanceSubjectContrast(&pixels, width: width, height: height, mask: subjectMask, strength: contrastStrength) }
    if desaturationStrength > 0 { desaturateBackground(&pixels, width: width, height: height, mask: subjectMask, strength: desaturationStrength) }
    if blurStrength > 0 { blurBackground(&pixels, width: width, height: height, mask: subjectMask, strength: blurStrength) }
}

/// 将源 mask 映射到目标网格。对应源端 `mapSubjectMask`。
public func mapSubjectMask(
    _ width: Int, _ height: Int, _ crop: CropArea, _ srcW: Int, _ srcH: Int, _ sourceMask: [UInt8]
) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
        for x in 0..<width {
            let sourceX = floorInt(Double(crop.x) + Double(x) / Double(width) * Double(crop.w))
            let sourceY = floorInt(Double(crop.y) + Double(y) / Double(height) * Double(crop.h))
            if sourceX < 0 || sourceX >= srcW || sourceY < 0 || sourceY >= srcH { continue }
            let sourceIndex = sourceY * srcW + sourceX
            if sourceIndex < sourceMask.count { result[y * width + x] = sourceMask[sourceIndex] }
        }
    }
    return result
}

/// 将主体上下文（mask/bbox/pose/heatmap）映射到目标网格。对应源端 `mapSubjectContextToGrid`。
public func mapSubjectContextToGrid(
    _ width: Int, _ height: Int, _ crop: CropArea, _ srcW: Int, _ srcH: Int,
    _ subject: BeadSubjectContext
) -> BeadSubjectContext {
    let mask = mapSubjectMask(width, height, crop, srcW, srcH, subject.mask ?? [])
    let cropWidth = max(1, crop.w)
    let cropHeight = max(1, crop.h)
    let rawLeft = (subject.bbox.x - Double(crop.x)) / Double(cropWidth) * Double(width)
    let rawTop = (subject.bbox.y - Double(crop.y)) / Double(cropHeight) * Double(height)
    let rawRight = (subject.bbox.x + subject.bbox.width - Double(crop.x)) / Double(cropWidth) * Double(width)
    let rawBottom = (subject.bbox.y + subject.bbox.height - Double(crop.y)) / Double(cropHeight) * Double(height)
    let left = max(0, min(width, floorInt(rawLeft)))
    let top = max(0, min(height, floorInt(rawTop)))
    let right = max(left, min(width, ceilInt(rawRight)))
    let bottom = max(top, min(height, ceilInt(rawBottom)))

    var mappedPose: BeadPoseData? = nil
    if let pose = subject.pose {
        let mappedKpts = pose.keypoints.map { point -> BeadPoseKeypoint in
            let mappedX = (point.x * Double(srcW) - Double(crop.x)) / Double(cropWidth)
            let mappedY = (point.y * Double(srcH) - Double(crop.y)) / Double(cropHeight)
            let insideCrop = mappedX >= 0 && mappedX <= 1 && mappedY >= 0 && mappedY <= 1
            return BeadPoseKeypoint(
                x: max(0, min(1, mappedX)),
                y: max(0, min(1, mappedY)),
                confidence: insideCrop ? point.confidence : 0
            )
        }
        mappedPose = BeadPoseData(keypoints: mappedKpts)
    }

    let attentionHeatmap = mapAttentionHeatmap(subject.attentionHeatmap, crop: crop, srcW: srcW, srcH: srcH)

    return BeadSubjectContext(
        bbox: CropRect(x: Double(left), y: Double(top), width: Double(right - left), height: Double(bottom - top)),
        mask: mask,
        attentionHeatmap: attentionHeatmap,
        pose: mappedPose
    )
}

/// 映射 7×7 注意力热图。对应源端 `mapAttentionHeatmap`（私有）。
private func mapAttentionHeatmap(_ source: [Float]?, crop: CropArea, srcW: Int, srcH: Int) -> [Float]? {
    let heatmapSize = 7
    guard let source, source.count == heatmapSize * heatmapSize, srcW > 0, srcH > 0 else { return nil }
    var mapped = [Float](repeating: 0, count: source.count)
    for y in 0..<heatmapSize {
        for x in 0..<heatmapSize {
            let sourceX = (Double(crop.x) + (Double(x) + 0.5) / Double(heatmapSize) * Double(crop.w)) / Double(srcW)
            let sourceY = (Double(crop.y) + (Double(y) + 0.5) / Double(heatmapSize) * Double(crop.h)) / Double(srcH)
            let heatX = max(0, min(heatmapSize - 1, Int(sourceX * Double(heatmapSize))))
            let heatY = max(0, min(heatmapSize - 1, Int(sourceY * Double(heatmapSize))))
            mapped[y * heatmapSize + x] = source[heatY * heatmapSize + heatX]
        }
    }
    return mapped
}

// MARK: - 内部实现

@inline(__always)
private func clampChannel(_ v: Double) -> UInt8 {
    UInt8(max(0, min(255, v.rounded())))
}

/// 主体局部对比增强。对应源端 `enhanceSubjectContrast`（私有）。
private func enhanceSubjectContrast(_ pixels: inout [UInt8], width: Int, height: Int, mask: [UInt8], strength: Double) {
    let radius = 2
    for y in radius..<(height - radius) {
        for x in radius..<(width - radius) {
            let index = y * width + x
            if mask[index] == 0 { continue }
            let pixelIndex = index * 4
            var luminanceSum = 0.0
            var count = 0
            for dy in -radius...radius {
                for dx in -radius...radius {
                    let neighbor = ((y + dy) * width + (x + dx)) * 4
                    luminanceSum += Double(pixels[neighbor]) * 0.2126 + Double(pixels[neighbor + 1]) * 0.7152 + Double(pixels[neighbor + 2]) * 0.0722
                    count += 1
                }
            }
            let average = luminanceSum / Double(count)
            let current = Double(pixels[pixelIndex]) * 0.2126 + Double(pixels[pixelIndex + 1]) * 0.7152 + Double(pixels[pixelIndex + 2]) * 0.0722
            let difference = (current - average) * strength * 2.5
            pixels[pixelIndex] = clampChannel(Double(pixels[pixelIndex]) + difference)
            pixels[pixelIndex + 1] = clampChannel(Double(pixels[pixelIndex + 1]) + difference)
            pixels[pixelIndex + 2] = clampChannel(Double(pixels[pixelIndex + 2]) + difference)
        }
    }
}

/// 背景降饱和。对应源端 `desaturateBackground`（私有）。
private func desaturateBackground(_ pixels: inout [UInt8], width: Int, height: Int, mask: [UInt8], strength: Double) {
    for i in 0..<(width * height) {
        if mask[i] != 0 { continue }
        let pi = i * 4
        let r = Double(pixels[pi]), g = Double(pixels[pi + 1]), b = Double(pixels[pi + 2])
        let gray = (r * 0.2126 + g * 0.7152 + b * 0.0722).rounded()
        pixels[pi] = UInt8((r * (1 - strength) + gray * strength).rounded())
        pixels[pi + 1] = UInt8((g * (1 - strength) + gray * strength).rounded())
        pixels[pi + 2] = UInt8((b * (1 - strength) + gray * strength).rounded())
    }
}

/// 背景模糊。对应源端 `blurBackground`（私有）。
private func blurBackground(_ pixels: inout [UInt8], width: Int, height: Int, mask: [UInt8], strength: Double) {
    var result = [UInt8](repeating: 0, count: pixels.count)
    let radius = 2
    for y in 0..<height {
        for x in 0..<width {
            let index = y * width + x
            let pi = index * 4
            if mask[index] != 0 {
                result[pi] = pixels[pi]; result[pi + 1] = pixels[pi + 1]
                result[pi + 2] = pixels[pi + 2]; result[pi + 3] = pixels[pi + 3]
                continue
            }
            var red = 0.0, green = 0.0, blue = 0.0, count = 0.0
            for dy in -radius...radius {
                for dx in -radius...radius {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0 && nx < width && ny >= 0 && ny < height {
                        let neighbor = (ny * width + nx) * 4
                        red += Double(pixels[neighbor]); green += Double(pixels[neighbor + 1]); blue += Double(pixels[neighbor + 2]); count += 1
                    }
                }
            }
            result[pi] = UInt8((Double(pixels[pi]) * (1 - strength) + red / count * strength).rounded())
            result[pi + 1] = UInt8((Double(pixels[pi + 1]) * (1 - strength) + green / count * strength).rounded())
            result[pi + 2] = UInt8((Double(pixels[pi + 2]) * (1 - strength) + blue / count * strength).rounded())
            result[pi + 3] = pixels[pi + 3]
        }
    }
    pixels = result
}
