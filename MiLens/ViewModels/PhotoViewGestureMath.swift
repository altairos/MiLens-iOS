//  PhotoViewGestureMath —— PhotoViewPage 手势/坐标计算纯函数
//  （对应源端 viewmodels/PhotoViewGestureMath.ets）。
//
//  把与容器尺寸、缩放、旋转相关的数学逻辑抽为纯函数，
//  使其可在无 SwiftUI 运行时环境下单测。DESIGN.md §4 纯决策逻辑。

import Foundation

enum PhotoViewGestureMath {

    /// 照片容器的固定宽高比（3:4 竖屏裁剪区）
    static let containerAspectRatio: Double = 3.0 / 4.0

    /// 缩放手势允许的最小/最大值
    static let minScale: Double = 0.5
    static let maxScale: Double = 5.0

    /// 计算高宽比照片在裁剪区内水平方向的最大偏移。
    /// 当 photoAspectRatio > containerAR（照片比容器更宽）时允许左右滑动。
    static func computeMaxCropOffset(containerWidth: Double, photoAspectRatio: Double) -> Double {
        guard containerWidth > 0 else { return 0 }
        let maxOff = containerWidth * (photoAspectRatio - containerAspectRatio) / (2 * containerAspectRatio)
        return max(maxOff, 0)
    }

    /// 计算放大后图片可平移的最大距离（像素）。
    static func computeMaxPanOffset(containerWidth: Double, imageScale: Double) -> Double {
        guard containerWidth > 0, imageScale > 1 else { return 0 }
        return containerWidth * (imageScale - 1) / 2
    }

    /// 将缩放值限制在 [min, max] 范围内。
    static func clampScale(_ scale: Double, min: Double = minScale, max: Double = maxScale) -> Double {
        Swift.min(Swift.max(scale, min), max)
    }

    /// 将平移偏移限制在 [-maxPan, maxPan] 范围内。
    static func clampPanOffset(_ offset: Double, maxPan: Double) -> Double {
        guard maxPan > 0 else { return 0 }
        return Swift.min(Swift.max(offset, -maxPan), maxPan)
    }

    /// 根据原始宽高和当前旋转角度计算显示宽高比。
    /// rotation 为 0/180 时返回 width/height；为 90/270 时返回 height/width。
    /// 无效宽高回退到 4:3 或 3:4。
    static func computeRotatedAspectRatio(width: Double, height: Double, rotation: Int) -> Double {
        let hasValidDims = width > 0 && height > 0
        if rotation == 90 || rotation == 270 {
            return hasValidDims ? height / width : 3.0 / 4.0
        }
        return hasValidDims ? width / height : 4.0 / 3.0
    }

    /// 判断滑动偏移后，新下标是否超出当前窗口范围，需要重新拉取。
    /// - Parameters:
    ///   - currentIndex: 当前在窗口中的下标
    ///   - windowLength: 窗口长度
    ///   - offset: 偏移量（+1 或 -1）
    /// - Returns: true 表示需要重新拉取窗口
    static func shouldReloadWindow(currentIndex: Int, windowLength: Int, offset: Int) -> Bool {
        let nextIndex = currentIndex + offset
        return nextIndex < 0 || nextIndex >= windowLength
    }
}
