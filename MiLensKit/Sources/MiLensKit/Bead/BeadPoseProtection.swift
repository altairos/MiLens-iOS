import Foundation

// BeadPoseProtection — Pose 关键点保护掩码。
// 逐行翻译自源端 shared/.../bead/BeadPoseProtection.ets（43 行）。

/// 将 5 个关键点展平为 15 元素 Float32 数组（xyz xyz xyz...）。
/// 对应源端 `flattenPoseKeypoints`。
public func flattenPoseKeypoints(_ subject: BeadSubjectContext? = nil) -> [Float] {
    var result = [Float](repeating: 0, count: 15)
    guard let keypoints = subject?.pose?.keypoints, keypoints.count >= 5 else { return result }
    for i in 0..<5 {
        result[i * 3] = Float(keypoints[i].x)
        result[i * 3 + 1] = Float(keypoints[i].y)
        result[i * 3 + 2] = Float(keypoints[i].confidence)
    }
    return result
}

/// 在 mask 上标记 pose 关键点周围的格为保护区域。
/// 对应源端 `applyPoseProtection`。原地修改 mask。
public func applyPoseProtection(
    _ mask: inout [UInt8], _ empty: [UInt8], gridW: Int, gridH: Int,
    crop: CropArea, srcW: Int, srcH: Int, subject: BeadSubjectContext? = nil
) {
    guard let keypoints = subject?.pose?.keypoints, keypoints.count >= 5, crop.w > 0, crop.h > 0 else { return }
    for i in 0..<5 {
        let point = keypoints[i]
        if point.confidence < 0.5 { continue }
        let gx = (point.x * Double(srcW) - Double(crop.x)) / Double(crop.w) * Double(gridW)
        let gy = (point.y * Double(srcH) - Double(crop.y)) / Double(crop.h) * Double(gridH)
        let radius = (i == 3 || i == 4) ? 1.5 : 1.0
        let minX = max(0, floorInt(gx - radius))
        let maxX = min(gridW - 1, ceilInt(gx + radius))
        let minY = max(0, floorInt(gy - radius))
        let maxY = min(gridH - 1, ceilInt(gy + radius))
        for y in minY...maxY {
            for x in minX...maxX {
                let idx = y * gridW + x
                let dx = Double(x) - gx
                let dy = Double(y) - gy
                if empty[idx] == 0 && dx * dx + dy * dy <= radius * radius {
                    mask[idx] = 1
                }
            }
        }
    }
}
