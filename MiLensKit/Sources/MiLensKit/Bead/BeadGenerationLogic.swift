import Foundation

// BeadGenerationLogic — 拼豆生成管线中的纯逻辑函数：主体框计算、正方形裁切、像素/蒙版裁切。
// 逐行翻译自源端 entry/.../viewmodels/BeadGenerationViewModel.ets。
// 从 BeadPatternPage.doGenerate 内联逻辑抽取，可独立单测。

// MARK: - 主体框构建

/// 从预过滤框构建主体上下文（全白蒙版 + 裁剪到图像边界）。
/// 对应源端 `computeSubjectFromBBox`。零面积框返回 nil。
public func computeSubjectFromBBox(box: CropRect, w: Int, h: Int) -> BeadSubjectContext? {
    if box.width <= 0 || box.height <= 0 { return nil }
    let x = Double(Swift.max(0, Swift.min(w - 1, Int(box.x.rounded(.down)))))
    let y = Double(Swift.max(0, Swift.min(h - 1, Int(box.y.rounded(.down)))))
    let width = Double(Swift.max(1, Swift.min(w - Int(x), Int(box.width.rounded(.up)))))
    let height = Double(Swift.max(1, Swift.min(h - Int(y), Int(box.height.rounded(.up)))))
    return BeadSubjectContext(
        bbox: CropRect(x: x, y: y, width: width, height: height),
        mask: [UInt8](repeating: 255, count: w * h)
    )
}

// MARK: - 正方形裁切参数

/// 正方形裁切参数。对应源端 `SquareCropParams`。
public struct SquareCropParams: Equatable {
    public var cropSize: Int
    public var cropX: Int
    public var cropY: Int

    public init(cropSize: Int, cropX: Int, cropY: Int) {
        self.cropSize = cropSize
        self.cropX = cropX
        self.cropY = cropY
    }
}

/// 计算以 bbox 中心为基准的正方形裁切参数。
/// 返回 cropSize、cropX、cropY，保证不越界。对应源端 `computeSquareCropParams`。
public func computeSquareCropParams(bbox: CropRect, imgW: Int, imgH: Int) -> SquareCropParams {
    let side = Swift.max(bbox.width, bbox.height)
    let padding = side * 0.15
    let cropSize = Swift.min(ceilInt(side + padding * 2), Swift.min(imgW, imgH))
    let cx = Int((bbox.x + bbox.width / 2).rounded(.down))
    let cy = Int((bbox.y + bbox.height / 2).rounded(.down))
    let cropX = Swift.max(0, Swift.min(imgW - cropSize, Int((Double(cx) - Double(cropSize) / 2).rounded(.down))))
    let cropY = Swift.max(0, Swift.min(imgH - cropSize, Int((Double(cy) - Double(cropSize) / 2).rounded(.down))))
    return SquareCropParams(cropSize: cropSize, cropX: cropX, cropY: cropY)
}

// MARK: - 像素裁切

/// 从完整 RGBA 像素缓冲中裁出正方形区域。对应源端 `cropPixelsToSquare`。
public func cropPixelsToSquare(
    _ fullPixels: [UInt8], srcW: Int,
    cropX: Int, cropY: Int, cropSize: Int
) -> [UInt8] {
    var cropped = [UInt8](repeating: 0, count: cropSize * cropSize * 4)
    for y in 0..<cropSize {
        for x in 0..<cropSize {
            let srcI = ((cropY + y) * srcW + (cropX + x)) * 4
            let dstI = (y * cropSize + x) * 4
            cropped[dstI] = fullPixels[srcI]
            cropped[dstI + 1] = fullPixels[srcI + 1]
            cropped[dstI + 2] = fullPixels[srcI + 2]
            cropped[dstI + 3] = fullPixels[srcI + 3]
        }
    }
    return cropped
}

/// 从完整蒙版中裁出正方形区域。对应源端 `cropMaskToSquare`。
/// 越界位置填充 0。
public func cropMaskToSquare(
    _ mask: [UInt8], srcW: Int,
    cropX: Int, cropY: Int, cropSize: Int
) -> [UInt8] {
    var cropped = [UInt8](repeating: 0, count: cropSize * cropSize)
    for y in 0..<cropSize {
        for x in 0..<cropSize {
            let srcI = (cropY + y) * srcW + (cropX + x)
            cropped[y * cropSize + x] = srcI < mask.count ? mask[srcI] : 0
        }
    }
    return cropped
}

// MARK: - 裁切后坐标调整

/// 将裁切后的主体框坐标调整为相对于裁切区域的新坐标。对应源端 `adjustSubjectForCrop`。
public func adjustSubjectForCrop(
    originalBbox: CropRect, cropX: Int, cropY: Int, cropSize: Int
) -> BeadSubjectContext {
    return BeadSubjectContext(
        bbox: CropRect(
            x: Swift.max(0, originalBbox.x - Double(cropX)),
            y: Swift.max(0, originalBbox.y - Double(cropY)),
            width: Swift.min(originalBbox.width, Double(cropSize)),
            height: Swift.min(originalBbox.height, Double(cropSize))
        ),
        mask: []
    )
}

/// 将相对原图归一化的关键点转换为相对裁切结果的归一化坐标。对应源端 `adjustPoseForCrop`。
public func adjustPoseForCrop(
    _ pose: BeadPoseData?,
    sourceWidth: Int, sourceHeight: Int,
    cropX: Int, cropY: Int, cropSize: Int
) -> BeadPoseData? {
    guard let pose, sourceWidth > 0, sourceHeight > 0, cropSize > 0 else { return nil }
    let keypoints = pose.keypoints.map { point -> BeadPoseKeypoint in
        let nx = Swift.max(0, Swift.min(1, (point.x * Double(sourceWidth) - Double(cropX)) / Double(cropSize)))
        let ny = Swift.max(0, Swift.min(1, (point.y * Double(sourceHeight) - Double(cropY)) / Double(cropSize)))
        return BeadPoseKeypoint(x: nx, y: ny, confidence: point.confidence)
    }
    return BeadPoseData(keypoints: keypoints)
}
