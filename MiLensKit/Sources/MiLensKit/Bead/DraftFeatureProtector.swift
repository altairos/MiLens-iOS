import Foundation

// DraftFeatureProtector — 五官特征保护 + 孤点清理
// 逐行翻译自源端 shared/.../bead/DraftFeatureProtector.ets。
//
// 在虚拟色板映射后的 index map 上执行后处理：
// 1. 保护五官区域（眼睛、鼻子）的颜色连续性
// 2. 清理孤立像素（噪声孤点）
// 3. 可选：保护花纹区域的颜色连续性

// MARK: - 像素坐标（内部共享）

/// 归一化关键点 → 像素坐标后的中间表示。
internal struct PixelCoord {
    var px: Double
    var py: Double
}

/// 预计算有效关键点像素坐标（眼睛 0,1 + 鼻子 2，confidence > 0.3）。
internal func activeKeypoints(from pose: BeadPoseData?, width: Int, height: Int) -> [PixelCoord] {
    guard let pose = pose else { return [] }
    let kpts = pose.keypoints
    var result: [PixelCoord] = []
    let limit = min(kpts.count, 3)
    for k in 0..<limit {
        if kpts[k].confidence > 0.3 {
            result.append(PixelCoord(px: kpts[k].x * Double(width),
                                     py: kpts[k].y * Double(height)))
        }
    }
    return result
}

// MARK: - 公共 API

/// 对虚拟色板 index map 执行特征保护和孤点清理（返回修改后的副本）。
///
/// - Parameters:
///   - indices: 虚拟色板索引图（0–254 为色板索引，255 为空）
///   - featureMask: 可选五官 mask（非零=五官区域）
///   - subjectMask: 可选主体 mask（非零=主体）
///   - preserveFace: 是否保护五官
///   - preservePattern: 是否保护花纹
///   - pose: 可选关键点数据
/// - Returns: 清理后的 index map
public func protectAndCleanup(
    _ indices: [UInt8],
    width: Int,
    height: Int,
    featureMask: [UInt8]? = nil,
    subjectMask: [UInt8]? = nil,
    preserveFace: Bool = true,
    preservePattern: Bool = true,
    pose: BeadPoseData? = nil
) -> [UInt8] {
    var result = indices

    // Phase 1: 孤点清理 — 全图（pose 关键点附近暗色连通域豁免）
    removeIsolatedPixels(&result, width: width, height: height,
                         subjectMask: subjectMask, pose: pose)

    // Phase 2: 五官区域特征保护
    if preserveFace, let featureMask = featureMask {
        protectFeatureRegions(&result, width: width, height: height,
                              featureMask: featureMask)
    }

    // Phase 3: 花纹区域保护（可选）
    if preservePattern, let subjectMask = subjectMask {
        smoothSubjectBoundaries(&result, width: width, height: height,
                                subjectMask: subjectMask)
    }

    return result
}

// MARK: - 孤点清理

/// 移除孤立像素：如果一个像素的颜色与其 4-邻域都不相同，替换为邻域众数。
/// 仅在主体区域内执行。
private func removeIsolatedPixels(
    _ indices: inout [UInt8],
    width: Int,
    height: Int,
    subjectMask: [UInt8]?,
    pose: BeadPoseData?
) {
    // Swift 安全：1..<(height-1) 在 height ≤ 1 时为非法 Range（JS 源端自动跳过空循环）
    guard width > 1 && height > 1 else { return }

    var changes: [(index: Int, value: UInt8)] = []

    // T2d: 预计算有效关键点像素坐标（眼睛 0,1 + 鼻子 2）
    let activeKpts = activeKeypoints(from: pose, width: width, height: height)
    let kptExemptRadius: Double = 1.0 // 格为单位的五官豁免半径
    let kptExemptRadiusSq = kptExemptRadius * kptExemptRadius

    for y in 1..<(height - 1) {
        for x in 1..<(width - 1) {
            let idx = y * width + x
            let val = indices[idx]
            if val == 255 { continue }             // 空像素跳过
            if let subjectMask = subjectMask, subjectMask[idx] == 0 { continue } // 非主体跳过

            // T2d: 关键点附近的暗色像素豁免孤点清理（保护眼线/瞳孔/鼻头）
            if !activeKpts.isEmpty {
                var nearKpt = false
                for kpt in activeKpts {
                    let dx = Double(x) - kpt.px
                    let dy = Double(y) - kpt.py
                    if dx * dx + dy * dy < kptExemptRadiusSq {
                        nearKpt = true
                        break
                    }
                }
                if nearKpt { continue } // 豁免：不做孤点判定
            }

            // 4-邻域
            let neighbors: [UInt8] = [
                indices[(y - 1) * width + x],
                indices[(y + 1) * width + x],
                indices[y * width + (x - 1)],
                indices[y * width + (x + 1)],
            ]

            // 检查是否有至少一个邻居同色
            var sameCount = 0
            for n in neighbors {
                if n == val { sameCount += 1 }
            }

            if sameCount == 0 {
                // 孤立点：替换为邻域众数（跳过 255）
                var counts: [UInt8: Int] = [:]
                for n in neighbors {
                    if n == 255 { continue }
                    counts[n, default: 0] += 1
                }
                var modeVal = val
                var modeCount = 0
                for (key, cnt) in counts {
                    if cnt > modeCount {
                        modeCount = cnt
                        modeVal = key
                    }
                }
                if modeVal != val {
                    changes.append((idx, modeVal))
                }
            }
        }
    }

    // 应用修改
    for (index, value) in changes {
        indices[index] = value
    }
}

// MARK: - 五官特征保护

/// 保护五官区域的颜色连续性。在五官 mask 区域内，如果某个像素与其邻域主色不同，
/// 则将其替换为邻域主色（更强的平滑）。
private func protectFeatureRegions(
    _ indices: inout [UInt8],
    width: Int,
    height: Int,
    featureMask: [UInt8]
) {
    // Swift 安全：1..<(height-1) 在 height ≤ 1 时为非法 Range
    guard width > 1 && height > 1 else { return }

    // 对五官区域做 2 次迭代平滑
    for _ in 0..<2 {
        var changes: [(index: Int, value: UInt8)] = []

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                if featureMask[idx] == 0 { continue }
                let val = indices[idx]
                if val == 255 { continue }

                // 8-邻域统计
                var counts: [UInt8: Int] = [:]
                for dy in -1...1 {
                    for dx in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        let nIdx = (y + dy) * width + (x + dx)
                        let nVal = indices[nIdx]
                        if nVal == 255 { continue }
                        counts[nVal, default: 0] += 1
                    }
                }

                // 找邻域众数
                var modeVal = val
                var modeCount = 0
                for (key, cnt) in counts {
                    if cnt > modeCount {
                        modeCount = cnt
                        modeVal = key
                    }
                }

                // 如果当前像素不是邻域众数，且众数占比超过 50%
                if modeVal != val && modeCount >= 4 {
                    changes.append((idx, modeVal))
                }
            }
        }

        for (index, value) in changes {
            indices[index] = value
        }
    }
}

// MARK: - 主体边界平滑

/// 主体边界平滑：在主体边缘 2px 范围内做轻微平滑，减少锯齿状色块边界。
private func smoothSubjectBoundaries(
    _ indices: inout [UInt8],
    width: Int,
    height: Int,
    subjectMask: [UInt8]
) {
    // Swift 安全：1..<(height-1) 在 height ≤ 1 时为非法 Range
    guard width > 1 && height > 1 else { return }

    // 检测主体边界像素（主体内且邻接非主体的像素）
    var boundaryPixels: [Int] = []
    for y in 1..<(height - 1) {
        for x in 1..<(width - 1) {
            let idx = y * width + x
            if subjectMask[idx] == 0 { continue }
            // 检查是否有非主体邻居
            let hasNonSubject =
                subjectMask[(y - 1) * width + x] == 0 ||
                subjectMask[(y + 1) * width + x] == 0 ||
                subjectMask[y * width + (x - 1)] == 0 ||
                subjectMask[y * width + (x + 1)] == 0
            if hasNonSubject {
                boundaryPixels.append(idx)
            }
        }
    }

    // 对边界像素做一次平滑（替换为邻域主体内众数）
    var changes: [(index: Int, value: UInt8)] = []
    for idx in boundaryPixels {
        let x = idx % width
        let y = idx / width
        let val = indices[idx]
        if val == 255 { continue }

        var counts: [UInt8: Int] = [:]
        for dy in -1...1 {
            for dx in -1...1 {
                if dx == 0 && dy == 0 { continue }
                let nIdx = (y + dy) * width + (x + dx)
                if subjectMask[nIdx] == 0 { continue }
                let nVal = indices[nIdx]
                if nVal == 255 { continue }
                counts[nVal, default: 0] += 1
            }
        }

        var modeVal = val
        var modeCount = 0
        for (key, cnt) in counts {
            if cnt > modeCount {
                modeCount = cnt
                modeVal = key
            }
        }

        if modeVal != val && modeCount >= 4 {
            changes.append((idx, modeVal))
        }
    }

    for (index, value) in changes {
        indices[index] = value
    }
}

// MARK: - 五官 mask 估计

/// 构建简易五官 mask（从主体 bbox 和对称性估计）。
/// 注意：这是一个启发式估计，精确的五官位置应从外部传入。
public func estimateFeatureMask(
    mask: [UInt8],
    width: Int,
    height: Int,
    bbox: CropRect
) -> [UInt8] {
    var featureMask = [UInt8](repeating: 0, count: width * height)

    // 估计五官区域为 bbox 上部 40% 的中心 60% 区域
    let featureTop = floorInt(bbox.y + bbox.height * 0.15)
    let featureBottom = floorInt(bbox.y + bbox.height * 0.55)
    let featureLeft = floorInt(bbox.x + bbox.width * 0.2)
    let featureRight = floorInt(bbox.x + bbox.width * 0.8)

    var y = featureTop
    while y < featureBottom && y < height {
        var x = featureLeft
        while x < featureRight && x < width {
            let idx = y * width + x
            if mask[idx] != 0 {
                featureMask[idx] = 1
            }
            x += 1
        }
        y += 1
    }

    return featureMask
}
