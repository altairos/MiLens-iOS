//  AvatarCropMath —— 头像裁切纯几何逻辑（对应源端 AvatarCropPage.ets clampOffset/doCrop）。
//
//  把裁切框偏移钳制、坐标转换、裁剪区域计算抽为纯函数，便于单测覆盖。
//  使用 Double 类型避免 CoreGraphics 依赖，保持 MiLensKit 跨平台纯逻辑；
//  App 层调用时做 CGFloat ↔ Double 转换。
//  DESIGN.md §4：纯决策逻辑，无 IO/无平台框架依赖。

import Foundation

// MARK: - 跨平台 2D 几何值类型（避免 CoreGraphics 依赖，加前缀避免与 PatternTypes.CropRect 冲突）

/// 二维尺寸（Double，跨平台）。
public struct AvatarCropSize: Equatable, Sendable {
    public let width: Double
    public let height: Double
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// 二维偏移/点（Double，跨平台）。
public struct AvatarCropOffset: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// 矩形（Double，跨平台）。
public struct AvatarCropRect: Equatable, Sendable {
    public let originX: Double
    public let originY: Double
    public let width: Double
    public let height: Double
    public var maxX: Double { originX + width }
    public var maxY: Double { originY + height }
    public init(originX: Double, originY: Double, width: Double, height: Double) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }
}

public enum AvatarCropMath {

    /// 钳制平移偏移：确保裁剪圆区域始终被图片覆盖。
    /// - Parameters:
    ///   - offset: 用户拖动产生的原始偏移
    ///   - scale: 当前缩放系数（≥1.0）
    ///   - containerSize: 预览容器尺寸（vp/pt，正方形）
    ///   - circleRatio: 裁剪圆占容器宽度比（源端 0.83）
    /// - Returns: 钳制后的安全偏移
    public static func clampOffset(
        offset: AvatarCropOffset, scale: Double, containerSize: Double,
        circleRatio: Double = 0.83
    ) -> AvatarCropOffset {
        guard scale > 0, containerSize > 0 else { return AvatarCropOffset(x: 0, y: 0) }
        let r = circleRatio * containerSize / 2
        // 缩放后图片半边 = scale * containerSize / 2；可移动范围 = 半边 - 裁剪圆半径
        let maxX = scale * containerSize / 2 - r
        let maxY = maxX // 正方形容器 X/Y 对称
        let clampedX = max(-maxX, min(maxX, offset.x))
        let clampedY = max(-maxY, min(maxY, offset.y))
        return AvatarCropOffset(x: clampedX, y: clampedY)
    }

    /// 根据缩放/偏移计算源图像中的裁剪矩形（正方形）。
    ///
    /// 坐标转换（对应源端 doCrop 注释）：
    /// - 容器中心 VP = (W/2, H/2)，对应源像素 (imgW/2, imgH/2)
    /// - 偏移后裁剪中心：srcCenter = imgCenter - offset * ppVp / scale
    /// - 裁剪直径：circleRatio * containerSize / scale * ppVp
    ///   其中 ppVp = imgSize / containerSize（每 VP 对应的像素数）
    ///
    /// - Parameters:
    ///   - imageSize: 源图像原始像素尺寸
    ///   - containerSize: 预览容器尺寸（vp/pt）
    ///   - scale: 用户缩放系数
    ///   - offset: 用户偏移（已钳制）
    ///   - circleRatio: 裁剪圆占容器比
    /// - Returns: 源图像像素坐标系下的正方形裁剪矩形（边界安全）
    public static func computeCropRect(
        imageSize: AvatarCropSize,
        containerSize: Double,
        scale: Double,
        offset: AvatarCropOffset,
        circleRatio: Double = 0.83
    ) -> AvatarCropRect {
        let imgW = imageSize.width
        let imgH = imageSize.height
        guard imgW > 0, imgH > 0, containerSize > 0, scale > 0 else {
            // 回退：中心正方形裁剪
            let side = min(imgW, imgH)
            return AvatarCropRect(originX: (imgW - side) / 2, originY: (imgH - side) / 2,
                                  width: side, height: side)
        }

        // 每 vp 对应的像素数（X/Y 方向独立，源端同理）
        let ppVpX = imgW / containerSize
        let ppVpY = imgH / containerSize

        // 偏移后的裁剪中心（源像素坐标）
        let srcCenterX = imgW / 2 - offset.x * ppVpX / scale
        let srcCenterY = imgH / 2 - offset.y * ppVpY / scale

        // 裁剪直径（取 X/Y 较小值更安全）
        let srcDiamX = circleRatio * containerSize / scale * ppVpX
        let srcDiamY = circleRatio * containerSize / scale * ppVpY
        let cropSize = min(srcDiamX, srcDiamY)

        var cropX = srcCenterX - cropSize / 2
        var cropY = srcCenterY - cropSize / 2

        // 边界钳制
        cropX = max(0, min(cropX, imgW - cropSize))
        cropY = max(0, min(cropY, imgH - cropSize))
        let safeSize = min(cropSize, imgW - cropX, imgH - cropY)

        return AvatarCropRect(originX: cropX, originY: cropY, width: safeSize, height: safeSize)
    }
}

#if canImport(UIKit)
import UIKit
import CoreGraphics

extension AvatarCropMath {

    /// 执行裁剪 + 缩放到目标尺寸（源端 PixelMap.crop + scale 的 iOS 等价）。
    /// - Parameters:
    ///   - image: 源 UIImage
    ///   - cropRect: 源像素坐标系裁剪矩形
    ///   - targetSize: 目标正方形边长（源端 256）
    /// - Returns: 裁剪并缩放后的 UIImage；裁剪区域无效时返回 nil
    public static func cropAndResize(
        image: UIImage, cropRect: AvatarCropRect, targetSize: Double
    ) -> UIImage? {
        let cgRect = CGRect(
            x: CGFloat(cropRect.originX), y: CGFloat(cropRect.originY),
            width: CGFloat(cropRect.width), height: CGFloat(cropRect.height)
        )
        guard let cgImage = image.cgImage,
              cgRect.width > 0, cgRect.height > 0,
              cgRect.origin.x >= 0, cgRect.origin.y >= 0,
              cgRect.maxX <= CGFloat(cgImage.width),
              cgRect.maxY <= CGFloat(cgImage.height) else {
            return nil
        }
        guard let cropped = cgImage.cropping(to: cgRect) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: targetSize, height: targetSize), format: format)
        return renderer.image { _ in
            UIImage(cgImage: cropped, scale: 1, orientation: .up)
                .draw(in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
        }
    }
}
#endif
