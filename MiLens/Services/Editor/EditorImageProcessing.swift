//  EditorImageProcessing —— 编辑器图像处理协议（Core Image/Core Graphics 隔离层）。
//  编辑器像素级操作（调色/锐化/裁剪/旋转/翻转/抠图蒙版/导出编码）全部收敛在此，
//  ViewModel 只依赖协议，测试注入 mock（DESIGN.md §4 平台隔离）。
//
//  调色因子语义（EditorColorAdjust → toFilterFactors）：
//  - brightness/contrast/saturation 映射到 CIColorControls（brightness 加性、contrast/saturation 乘性）。
//  - temperature 映射到 CITemperatureAndTint（正=暖/负=冷，0=原图）。
//  - sharpness 用源端 3×3 卷积核（buildSharpenKernel）→ CIConvolution3X3，保证与源端行为一致。
//
//  注意：抠图蒙版坐标方向约定——Vision 蒙版行序为图像顶部向下，Core Graphics 缓冲行序为底部向上，
//  合成时做垂直翻转（真机验证关注点，见 AGENTS.md §5）。

import CoreGraphics
import CoreImage
import Foundation
import MiLensKit
import UIKit

/// 编辑器图像处理协议（可注入 mock 的单测面）。
protocol EditorImageProcessing {
    /// 调色实时预览（亮度/对比度/饱和度/色温；不含锐化——锐化走异步卷积）。
    func applyingAdjustments(to image: CGImage, adjustments: EditorColorAdjustments) -> CGImage
    /// 锐化卷积（buildSharpenKernel → CIConvolution3X3；strength=0 返回原图）。
    func applyingSharpen(to image: CGImage, strength: Double) -> CGImage
    /// 像素裁切（region 为照片像素空间坐标，对应 computeCropRegion 输出）。
    func cropping(_ image: CGImage, region: EditorCropRegion) -> CGImage?
    /// 旋转（90/270 度；宽高互换由调用方处理）。
    func rotating(_ image: CGImage, degrees: Double) -> CGImage
    /// 翻转（水平/垂直，属性级操作：不改像素，导出时由 renderExport 应用）。
    func flipping(_ image: CGImage, horizontal: Bool) -> CGImage
    /// 抠图蒙版合成：mask 为 0–255 单通道 alpha（尺寸 = 原图尺寸），合成后背景透明。
    func applyingCutoutMask(to image: CGImage, mask: Data, width: Int, height: Int) -> CGImage?
    /// 合成导出：底图（已含调色/锐化/翻转）+ 装饰图层 → 编码数据（按 format 决策 JPEG/PNG）。
    func renderExport(
        baseImage: CGImage, layers: [EditorLayer], canvasSize: CGSize,
        format: EditorSaveFormatDecision
    ) -> Data?
    /// 编码单张图为导出数据（保存用）。
    func encode(_ image: CGImage, format: EditorSaveFormatDecision) -> Data?
}

/// Core Image / Core Graphics 真实实现。
final class CoreImageEditorProcessing: EditorImageProcessing {

    /// CIContext 线程安全，复用单个实例（GPU 加速）。
    private let context = CIContext()

    // MARK: - 调色（实时预览）

    func applyingAdjustments(to image: CGImage, adjustments: EditorColorAdjustments) -> CGImage {
        var ci = CIImage(cgImage: image)
        let factors = toFilterFactors(adjustments)

        // CIColorControls：brightness 加性（-1..1），contrast（0.25..4）/saturation（0..2）乘性。
        if factors.brightnessFactor != 1.0 || factors.contrastFactor != 1.0 || factors.saturationFactor != 1.0,
           let colorControls = CIFilter(name: "CIColorControls") {
            colorControls.setValue(ci, forKey: kCIInputImageKey)
            colorControls.setValue(Float(factors.brightnessFactor - 1), forKey: kCIInputBrightnessKey)
            colorControls.setValue(Float(factors.contrastFactor), forKey: kCIInputContrastKey)
            colorControls.setValue(Float(factors.saturationFactor), forKey: kCIInputSaturationKey)
            if let output = colorControls.outputImage { ci = output }
        }

        // 色温：CITemperatureAndTint 的 inputNeutral/inputTargetNeutral（6500K 基准，±100 → ±5000K）。
        if adjustments.temperature != 0, let temperature = CIFilter(name: "CITemperatureAndTint") {
            temperature.setValue(ci, forKey: kCIInputImageKey)
            temperature.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            temperature.setValue(CIVector(x: 6500 - adjustments.temperature * 50, y: 0), forKey: "inputTargetNeutral")
            if let output = temperature.outputImage { ci = output }
        }

        return render(ci) ?? image
    }

    // MARK: - 锐化（异步卷积）

    func applyingSharpen(to image: CGImage, strength: Double) -> CGImage {
        let clamped = clampSharpness(strength)
        guard clamped > 0 else { return image }
        let kernel = buildSharpenKernel(strength: clamped)
        guard let filter = CIFilter(name: "CIConvolution3X3") else { return image }
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(CIVector(values: kernel.map { CGFloat($0) }, count: 9), forKey: "inputWeights")
        filter.setValue(0, forKey: "inputBias")
        return render(filter.outputImage) ?? image
    }

    // MARK: - 裁剪 / 旋转 / 翻转

    func cropping(_ image: CGImage, region: EditorCropRegion) -> CGImage? {
        guard isCropRegionValid(region) else { return nil }
        let rect = CGRect(x: region.regionX, y: region.regionY,
                          width: region.regionW, height: region.regionH)
        return image.cropping(to: rect)
    }

    func rotating(_ image: CGImage, degrees: Double) -> CGImage {
        let angle = degrees * .pi / 180
        let rotated = CIImage(cgImage: image).transformed(by: CGAffineTransform(rotationAngle: angle))
        // 旋转后 extent 可能带负坐标，平移回正象限（90/270 时宽高互换由调用方处理）。
        let extent = rotated.extent
        let final = rotated.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        return render(final) ?? image
    }

    func flipping(_ image: CGImage, horizontal: Bool) -> CGImage {
        let width = image.width
        let height = image.height
        let scale = horizontal
            ? CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -CGFloat(width), y: 0)
            : CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -CGFloat(height))
        let flipped = CIImage(cgImage: image).transformed(by: scale)
        return render(flipped) ?? image
    }

    // MARK: - 抠图蒙版合成

    func applyingCutoutMask(to image: CGImage, mask: Data, width: Int, height: Int) -> CGImage? {
        guard mask.count == width * height, width == image.width, height == image.height else { return nil }

        // 1. 不透明绘制原图到 RGBA 缓冲（premultipliedLast），行序底部向上。
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 2. 应用蒙版 alpha（Vision 行序顶部向下 → 缓冲行序底部向上，垂直翻转）。
        mask.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: UInt8.self)
            for y in 0..<height {
                let flippedY = height - 1 - y
                for x in 0..<width {
                    let alpha = Int(src[flippedY * width + x])
                    let idx = (y * width + x) * 4
                    pixels[idx + 3] = UInt8(alpha)
                    pixels[idx] = UInt8(Int(pixels[idx]) * alpha / 255)
                    pixels[idx + 1] = UInt8(Int(pixels[idx + 1]) * alpha / 255)
                    pixels[idx + 2] = UInt8(Int(pixels[idx + 2]) * alpha / 255)
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    // MARK: - 导出合成与编码

    func renderExport(
        baseImage: CGImage, layers: [EditorLayer], canvasSize: CGSize,
        format: EditorSaveFormatDecision
    ) -> Data? {
        let width = baseImage.width
        let height = baseImage.height
        guard width > 0, height > 0 else { return nil }
        // 画布坐标 → 导出像素坐标的缩放（画布 fit 显示，导出全尺寸）。
        let scale = CGFloat(width) / max(canvasSize.width, 1)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { _ in
            guard let ctx = UIGraphicsGetCurrentContext() else { return }

            // 底图：应用属性级翻转（flipX/flipY）。
            ctx.saveGState()
            let photo = layers.first { $0.type == .photo }
            if let photo {
                if photo.flipX {
                    ctx.translateBy(x: CGFloat(width), y: 0)
                    ctx.scaleBy(x: -1, y: 1)
                }
                if photo.flipY {
                    ctx.translateBy(x: 0, y: CGFloat(height))
                    ctx.scaleBy(x: 1, y: -1)
                }
            }
            UIImage(cgImage: baseImage).draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            ctx.restoreGState()

            // 装饰图层（V1.0：文字图层；贴纸/相框待素材资源）。
            for layer in layers where layer.type == .text && layer.visible {
                drawTextLayer(layer, scale: scale)
            }
        }
        return encodeImage(image, format: format)
    }

    func encode(_ image: CGImage, format: EditorSaveFormatDecision) -> Data? {
        encodeImage(UIImage(cgImage: image), format: format)
    }

    // MARK: - 内部辅助

    private func render(_ ci: CIImage?) -> CGImage? {
        guard let ci else { return nil }
        return context.createCGImage(ci, from: ci.extent)
    }

    private func drawTextLayer(_ layer: EditorLayer, scale: CGFloat) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let fontSize = layer.fontSize * scale
        guard fontSize > 0 else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor(hexString: layer.fontColor) ?? .white,
            .paragraphStyle: paragraph,
        ]
        let text = layer.text as NSString
        let size = text.size(withAttributes: attributes)
        let boxWidth = layer.maxWidth * scale
        let textRect = CGRect(
            x: -boxWidth / 2, y: -size.height / 2, width: boxWidth, height: size.height
        )

        ctx.saveGState()
        // 图层变换：平移 → 旋转 → 缩放（与画布渲染一致）。
        ctx.translateBy(x: layer.x * scale, y: layer.y * scale)
        ctx.rotate(by: layer.rotation * .pi / 180)
        ctx.scaleBy(x: layer.scale, y: layer.scale)
        if layer.strokeWidth > 0, let strokeColor = UIColor(hexString: layer.strokeColor) {
            let strokeAttributes = attributes.merging([
                .strokeColor: strokeColor,
                .strokeWidth: -layer.strokeWidth * scale,
            ]) { _, new in new }
            text.draw(with: textRect.offsetBy(dx: 0, dy: 0), options: [.usesLineFragmentOrigin],
                      attributes: strokeAttributes, context: nil)
        }
        text.draw(with: textRect, options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
        ctx.restoreGState()
    }

    private func encodeImage(_ image: UIImage, format: EditorSaveFormatDecision) -> Data? {
        switch format.format {
        case "image/png":
            return image.pngData()
        default:
            return image.jpegData(compressionQuality: CGFloat(format.quality) / 100)
        }
    }
}

// MARK: - Mock（对应源端 Fake 系列）

/// 记录调用、返回固定结果的 mock，用于 EditorViewModel 决策测试。
final class MockEditorImageProcessing: EditorImageProcessing {
    private(set) var adjustmentCalls = 0
    private(set) var sharpenCalls: [Double] = []
    private(set) var cropCalls = 0
    private(set) var rotateCalls: [Double] = []
    private(set) var flipCalls = 0
    private(set) var cutoutCalls = 0
    private(set) var renderExportCalls = 0
    private(set) var encodeCalls = 0

    /// 预设输出（默认返回入参原图；crop 失败用 nil 模拟）。
    var cropResult: CGImage?
    var encodeResult: Data?
    var renderExportResult: Data?
    /// 模拟导出失败（renderExport 返回 nil）。
    var renderExportFails = false
    /// 旋转结果序列（每次 rotating 弹出一个；空时返回入参原图，尺寸不变）。
    var rotateResults: [CGImage] = []
    /// 渲染导出收到的图层快照（断言用）。
    private(set) var lastExportLayers: [EditorLayer] = []

    func applyingAdjustments(to image: CGImage, adjustments: EditorColorAdjustments) -> CGImage {
        adjustmentCalls += 1
        return image
    }

    func applyingSharpen(to image: CGImage, strength: Double) -> CGImage {
        sharpenCalls.append(strength)
        return image
    }

    func cropping(_ image: CGImage, region: EditorCropRegion) -> CGImage? {
        cropCalls += 1
        return cropResult ?? image
    }

    func rotating(_ image: CGImage, degrees: Double) -> CGImage {
        rotateCalls.append(degrees)
        guard !rotateResults.isEmpty else { return image }
        return rotateResults.removeFirst()
    }

    func flipping(_ image: CGImage, horizontal: Bool) -> CGImage {
        flipCalls += 1
        return image
    }

    func applyingCutoutMask(to image: CGImage, mask: Data, width: Int, height: Int) -> CGImage? {
        cutoutCalls += 1
        return image
    }

    func renderExport(
        baseImage: CGImage, layers: [EditorLayer], canvasSize: CGSize,
        format: EditorSaveFormatDecision
    ) -> Data? {
        renderExportCalls += 1
        lastExportLayers = layers
        if renderExportFails { return nil }
        return renderExportResult ?? Data([0x89, 0x50, 0x4E, 0x47])
    }

    func encode(_ image: CGImage, format: EditorSaveFormatDecision) -> Data? {
        encodeCalls += 1
        return encodeResult ?? Data([0xFF, 0xD8])
    }
}

// MARK: - 辅助

/// 生成最小测试用 CGImage（白色，像素缓冲随 width×height 分配）。
func makeTestCGImage(width: Int = 1, height: Int = 1) -> CGImage {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    )!
}

private extension UIColor {
    /// 解析 "#RRGGBB" 十六进制颜色（编辑器文字颜色；解析失败返回 nil）。
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
