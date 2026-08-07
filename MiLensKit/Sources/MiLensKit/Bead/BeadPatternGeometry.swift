import Foundation

// BeadPatternGeometry — 裁切区域 / 脸部 ROI / 徽章蒙版计算。
// 逐行翻译自源端 shared/.../bead/BeadPatternGeometry.ets，纯逻辑，行为一致性由
// BeadPatternGeometryTests 守护。

/// 计算拼豆网格使用的源裁切区域。对应源端 `computePatternCrop`。
public func computePatternCrop(
    srcW: Int, srcH: Int, mode: String, subject: BeadSubjectContext? = nil
) -> CropArea {
    if mode == "free" {
        return CropArea(x: 0, y: 0, w: srcW, h: srcH)
    }
    if mode == "portrait" || mode == "fullBody" || mode == "tight_face" || mode == "badge" {
        if let subject, subject.bbox.width > 0 && subject.bbox.height > 0 {
            var padding = 0.15
            if mode == "fullBody" { padding = 0.30 }
            if mode == "tight_face" { padding = 0.08 }
            if mode == "badge" { padding = 0.12 }
            let side = min(
                max(subject.bbox.width, subject.bbox.height) * (1 + padding * 2),
                Double(min(srcW, srcH))
            )
            let cx = subject.bbox.x + subject.bbox.width / 2
            let cy = subject.bbox.y + subject.bbox.height / 2
            let size = max(1, floorInt(side))
            let x = max(0, min(srcW - size, floorInt(cx - Double(size) / 2)))
            let y = max(0, min(srcH - size, floorInt(cy - Double(size) / 2)))
            return CropArea(x: x, y: y, w: size, h: size)
        }
        let side = min(srcW, srcH)
        return CropArea(x: (srcW - side) / 2, y: (srcH - side) / 2, w: side, h: side)
    }
    return CropArea(x: 0, y: 0, w: srcW, h: srcH)
}

/// 模式对应的 [ratio, margin] 参数（私有）。对应源端 `faceRoiParams`。
private func faceRoiParams(_ mode: String) -> [Double] {
    if mode == "tight_face" || mode == "badge" { return [0.58, 0.12] }
    if mode == "fullBody" { return [0.40, 0.10] }
    if mode == "portrait" { return [0.50, 0.15] }
    return [0.45, 0.12]
}

/// 将主体 bounding box 上部映射到拼豆网格坐标。对应源端 `computeFaceRoi`。
public func computeFaceRoi(
    crop: CropArea, gridW: Int, gridH: Int, mode: String, subject: BeadSubjectContext? = nil
) -> CropArea? {
    guard let subject,
          subject.bbox.width > 0, subject.bbox.height > 0, crop.w > 0, crop.h > 0 else {
        return nil
    }
    let params = faceRoiParams(mode)
    let sourceLeft = subject.bbox.x + subject.bbox.width * params[1]
    let sourceRight = subject.bbox.x + subject.bbox.width * (1 - params[1])
    let sourceTop = subject.bbox.y
    let sourceBottom = subject.bbox.y + subject.bbox.height * params[0]
    let left = max(0, min(gridW, floorInt((sourceLeft - Double(crop.x)) / Double(crop.w) * Double(gridW))))
    let right = max(0, min(gridW, ceilInt((sourceRight - Double(crop.x)) / Double(crop.w) * Double(gridW))))
    let top = max(0, min(gridH, floorInt((sourceTop - Double(crop.y)) / Double(crop.h) * Double(gridH))))
    let bottom = max(0, min(gridH, ceilInt((sourceBottom - Double(crop.y)) / Double(crop.h) * Double(gridH))))
    if right <= left || bottom <= top { return nil }
    return CropArea(x: left, y: top, w: right - left, h: bottom - top)
}

/// 标记圆形徽章外的格子为空。对应源端 `applyBadgeMask`（原地修改 empty 数组）。
public func applyBadgeMask(_ empty: inout [UInt8], w: Int, h: Int) {
    let cx = Double(w - 1) / 2
    let cy = Double(h - 1) / 2
    let radius = max(0.5, Double(min(w, h)) / 2 - 0.5)
    let radiusSquared = radius * radius
    for y in 0..<h {
        for x in 0..<w {
            let dx = Double(x) - cx
            let dy = Double(y) - cy
            if dx * dx + dy * dy > radiusSquared {
                empty[y * w + x] = 1
            }
        }
    }
}
