import Foundation

// EditorCropMath — 裁切区域几何计算（纯逻辑）。
// 翻译自源端 entry/.../editor/CropMath.ets（89 行）。
//
// 从 LayerManager.cropPhotoLayer 抽出的可单测纯函数。
// 坐标系：输入值为画布本地位移坐标系下的浮点坐标。

/// 裁切输入参数。对应源端 `CropInput`。
public struct EditorCropInput: Equatable, Sendable {
    /// 照片图层中心 X。
    public var photoX: Double
    /// 照片图层中心 Y。
    public var photoY: Double
    /// 照片图层宽度（像素）。
    public var photoW: Double
    /// 照片图层高度（像素）。
    public var photoH: Double
    /// 裁切框左上角 X。
    public var cropX: Double
    /// 裁切框左上角 Y。
    public var cropY: Double
    /// 裁切宽度。
    public var cropW: Double
    /// 裁切高度。
    public var cropH: Double

    public init(photoX: Double, photoY: Double, photoW: Double, photoH: Double,
                cropX: Double, cropY: Double, cropW: Double, cropH: Double) {
        self.photoX = photoX; self.photoY = photoY; self.photoW = photoW; self.photoH = photoH
        self.cropX = cropX; self.cropY = cropY; self.cropW = cropW; self.cropH = cropH
    }
}

/// 裁切结果区域（照片像素空间）。对应源端 `CropRegion`。
public struct EditorCropRegion: Equatable, Sendable {
    public var regionX: Int
    public var regionY: Int
    public var regionW: Int
    public var regionH: Int

    public init(regionX: Int, regionY: Int, regionW: Int, regionH: Int) {
        self.regionX = regionX; self.regionY = regionY
        self.regionW = regionW; self.regionH = regionH
    }
}

/// 全零区域，表示无效裁切。对应源端 `ZERO_REGION`。
public let ZERO_CROP_REGION = EditorCropRegion(regionX: 0, regionY: 0, regionW: 0, regionH: 0)

/// 计算照片像素空间中的裁切区域。对应源端 `computeCropRegion`。
///
/// 1. 把照片中心 + 半宽换算为左上角坐标。
/// 2. 将裁切框与照片矩形做标准 AABB 相交测试。
/// 3. 把交集平移到照片像素空间（减去照片左上角坐标）。
/// 4. 对结果做 Math.round + 边界 clamp。
public func computeCropRegion(input: EditorCropInput) -> EditorCropRegion {
    if !isValidCropInput(input) { return ZERO_CROP_REGION }

    let photoLeft = input.photoX - input.photoW / 2
    let photoTop = input.photoY - input.photoH / 2

    let intersectLeft = max(input.cropX, photoLeft)
    let intersectTop = max(input.cropY, photoTop)
    let intersectRight = min(input.cropX + input.cropW, photoLeft + input.photoW)
    let intersectBottom = min(input.cropY + input.cropH, photoTop + input.photoH)

    if intersectRight <= intersectLeft || intersectBottom <= intersectTop {
        return ZERO_CROP_REGION
    }

    let regionX = max(0, Int((intersectLeft - photoLeft).rounded()))
    let regionY = max(0, Int((intersectTop - photoTop).rounded()))
    let regionW = min(Int((intersectRight - intersectLeft).rounded()), Int(input.photoW) - regionX)
    let regionH = min(Int((intersectBottom - intersectTop).rounded()), Int(input.photoH) - regionY)

    if regionW <= 0 || regionH <= 0 { return ZERO_CROP_REGION }

    return EditorCropRegion(regionX: regionX, regionY: regionY, regionW: regionW, regionH: regionH)
}

/// 判断裁切区域是否有效（宽高为正数）。对应源端 `isCropRegionValid`。
public func isCropRegionValid(_ region: EditorCropRegion) -> Bool {
    return region.regionW > 0 && region.regionH > 0
}

/// 判断输入是否数值合法（尺寸为正且无 NaN/Infinity）。对应源端 `isValidCropInput`。
public func isValidCropInput(_ input: EditorCropInput) -> Bool {
    return input.photoW > 0 && input.photoH > 0
        && input.cropW > 0 && input.cropH > 0
        && input.photoX.isFinite && input.photoY.isFinite
        && input.cropX.isFinite && input.cropY.isFinite
}
