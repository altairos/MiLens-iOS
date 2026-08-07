import Foundation

// BeadDenoise — 孤立点去除 + 小区域合并 + 少用色合并。
// 逐行翻译自源端 shared/.../bead/BeadDenoise.ets（412 行）。
// BFS 连通域构建 + 合并代价公式 + 线状特征保护。

// MARK: - 连通域结构

/// BFS 连通域信息。对应源端 `Cluster`。
struct Cluster {
    var colorIdx: Int
    var size: Int
    var pixels: [Int]           // flat indices
    var minX: Int; var maxX: Int
    var minY: Int; var maxY: Int
    var perimeter: Int
    var borderNeighbors: [Int: Int]  // neighbor colorIdx → contact edge count
    var touchesProtected: Bool
}

/// 少用色合并结果。对应源端 `MergeTinyColorsResult`。
public struct MergeTinyColorsResult: Equatable {
    public var indices: [UInt16]
    public var paletteUsed: [BeadColor]
    public var mergedCount: Int
}

// MARK: - BFS 连通域构建

/// 构建 4 连通域。对应源端 `buildCluster`。
private func buildCluster(
    _ indices: [UInt16], w: Int, h: Int,
    startIdx: Int, visited: inout [UInt8],
    empty: [UInt8]?, protectMask: [UInt8]?
) -> Cluster {
    let color = Int(indices[startIdx])
    var pixels: [Int] = []
    var queue: [Int] = [startIdx]
    visited[startIdx] = 1
    var touchesProtected = false
    var minX = w, maxX = 0, minY = h, maxY = 0
    var perimeter = 0
    var borderNeighbors: [Int: Int] = [:]
    let dx4 = [0, 0, -1, 1]
    let dy4 = [-1, 1, 0, 0]

    while !queue.isEmpty {
        let ci = queue.removeFirst()
        pixels.append(ci)
        let cx = ci % w
        let cy = ci / w
        if cx < minX { minX = cx }
        if cx > maxX { maxX = cx }
        if cy < minY { minY = cy }
        if cy > maxY { maxY = cy }
        if protectMask != nil && protectMask![ci] != 0 { touchesProtected = true }

        for d in 0..<4 {
            let nx = cx + dx4[d]
            let ny = cy + dy4[d]
            if nx < 0 || nx >= w || ny < 0 || ny >= h { perimeter += 1; continue }
            let ni = ny * w + nx
            if empty != nil && empty![ni] != 0 { perimeter += 1; continue }
            if Int(indices[ni]) == color {
                if visited[ni] == 0 {
                    visited[ni] = 1
                    queue.append(ni)
                }
            } else {
                perimeter += 1
                let nc = Int(indices[ni])
                borderNeighbors[nc, default: 0] += 1
            }
        }
    }

    return Cluster(colorIdx: color, size: pixels.count, pixels: pixels,
                   minX: minX, maxX: maxX, minY: minY, maxY: maxY,
                   perimeter: perimeter, borderNeighbors: borderNeighbors,
                   touchesProtected: touchesProtected)
}

// MARK: - 线状特征检测

/// 判断是否为线状特征。对应源端 `isLineFeature`。
private func isLineFeature(_ cluster: Cluster) -> Bool {
    if cluster.size > 4 { return false }
    let bboxW = cluster.maxX - cluster.minX + 1
    let bboxH = cluster.maxY - cluster.minY + 1
    let aspectRatio = Double(max(bboxW, bboxH)) / Double(max(1, min(bboxW, bboxH)))
    let compactness = Double(cluster.size) / Double(max(1, bboxW * bboxH))
    return aspectRatio >= 2.5 || compactness <= 0.4
}

/// 判断线状特征是否有意义（位于脸部 ROI / 与保护区相邻 / 暗色或高亮色）。
/// 对应源端 `isMeaningfulLine`。
private func isMeaningfulLine(_ cluster: Cluster, _ faceRoi: CropArea?, _ paletteLab: [LabColor]) -> Bool {
    // 1. 位于 Face ROI 内
    if let roi = faceRoi, roi.w > 0, roi.h > 0 {
        let meanX = Double(cluster.minX + cluster.maxX) / 2
        let meanY = Double(cluster.minY + cluster.maxY) / 2
        if meanX >= Double(roi.x) && meanX < Double(roi.x + roi.w) &&
           meanY >= Double(roi.y) && meanY < Double(roi.y + roi.h) {
            return true
        }
    }
    // 2. 与保护区相邻
    if cluster.touchesProtected { return true }
    // 3. 自身颜色是暗色或高亮色
    if isDarkOrHighlight(cluster.colorIdx, paletteLab) { return true }
    return false
}

private func isDarkOrHighlight(_ colorIdx: Int, _ paletteLab: [LabColor]) -> Bool {
    if colorIdx >= paletteLab.count { return false }
    let L = paletteLab[colorIdx].L
    return L < 25 || L > 90
}

// MARK: - 合并代价计算

private func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }

/// 计算将 cluster 合并到 neighborColorIdx 的代价。对应源端 `computeMergeCost`。
private func computeMergeCost(
    _ cluster: Cluster, _ neighborColorIdx: Int,
    _ paletteLab: [LabColor], _ dominantColorSet: Set<Int>,
    _ qModeBoost: Bool
) -> Double {
    if cluster.colorIdx >= paletteLab.count || neighborColorIdx >= paletteLab.count { return 1.0 }
    let dE = weightedDeltaE(paletteLab[cluster.colorIdx], paletteLab[neighborColorIdx])
    let d = clamp01(dE / 30)

    let contact = cluster.borderNeighbors[neighborColorIdx] ?? 0
    let borderContactRatio = cluster.perimeter > 0 ? Double(contact) / Double(cluster.perimeter) : 0

    let dominantPrior = dominantColorSet.contains(neighborColorIdx) ? 1.0 : 0.0

    let cL = paletteLab[cluster.colorIdx].L
    let nL = paletteLab[neighborColorIdx].L
    let sameBucket: Double = (cL < 35 && nL < 35) || (cL >= 35 && cL < 72 && nL >= 35 && nL < 72) || (cL >= 72 && nL >= 72) ? 1 : 0

    let domWeight = qModeBoost ? 0.20 : 0.10

    return d * 0.60 - borderContactRatio * 0.25 - dominantPrior * domWeight - sameBucket * 0.05
}

// MARK: - removeIsolatedPixels

/// 移除孤立像素：4 邻域无同色邻居的像素替换为多数邻居色。对应源端 `removeIsolatedPixels`。
/// 原地修改 indices（使用快照避免链式影响）。
public func removeIsolatedPixels(
    _ indices: inout [UInt16], w: Int, h: Int,
    protectMask: [UInt8]? = nil, empty: [UInt8]? = nil
) {
    let snapshot = indices
    let dx = [0, 0, -1, 1]
    let dy = [-1, 1, 0, 0]
    for y in 0..<h {
        for x in 0..<w {
            let idx = y * w + x
            if (protectMask != nil && protectMask![idx] != 0) || (empty != nil && empty![idx] != 0) { continue }
            let color = Int(snapshot[idx])
            var neighborColors: [Int: Int] = [:]
            for d in 0..<4 {
                let nx = x + dx[d]
                let ny = y + dy[d]
                if nx >= 0 && nx < w && ny >= 0 && ny < h {
                    let ni = ny * w + nx
                    if empty != nil && empty![ni] != 0 { continue }
                    let nc = Int(snapshot[ni])
                    neighborColors[nc, default: 0] += 1
                }
            }
            let sameCount = neighborColors[color] ?? 0
            if sameCount == 0 {
                var bestColor = color
                var bestCount = 0
                for (c, count) in neighborColors {
                    if count > bestCount { bestCount = count; bestColor = c }
                }
                indices[idx] = UInt16(bestColor)
            }
        }
    }
}

// MARK: - mergeSmallRegions

/// 合并小连通域。对应源端 `mergeSmallRegions`。
/// 含线状特征保护 + 合并代价公式。原地修改 indices。
public func mergeSmallRegions(
    _ indices: inout [UInt16], w: Int, h: Int, minSize: Int,
    protectMask: [UInt8]? = nil, empty: [UInt8]? = nil,
    faceRoi: CropArea? = nil, paletteLab: [LabColor]? = nil,
    dominantColorIndices: [Int]? = nil, featureProtectionStrength: Double? = nil,
    qMode: Bool? = nil
) {
    var visited = [UInt8](repeating: 0, count: w * h)
    let protectionThreshold = featureProtectionStrength ?? 0.6
    let dominantSet = Set(dominantColorIndices ?? [])
    let plab = paletteLab ?? []

    // Phase 1: 构建所有连通域
    var clusters: [Cluster] = []
    for startY in 0..<h {
        for startX in 0..<w {
            let startIdx = startY * w + startX
            if visited[startIdx] != 0 || (empty != nil && empty![startIdx] != 0) { continue }
            let cluster = buildCluster(indices, w: w, h: h, startIdx: startIdx, visited: &visited, empty: empty, protectMask: protectMask)
            clusters.append(cluster)
        }
    }

    // Phase 2: 按大小从小到大处理
    clusters.sort { $0.size < $1.size }

    for cluster in clusters {
        if cluster.size >= minSize { continue }

        // 线状特征保护
        if isLineFeature(cluster) && isMeaningfulLine(cluster, faceRoi, plab) && protectionThreshold > 0.5 {
            continue
        }

        // 整个 Cluster 在保护区内 → 跳过
        if cluster.touchesProtected { continue }

        // 选择最优合并目标
        if cluster.borderNeighbors.isEmpty { continue }

        var bestNeighbor = -1
        var bestCost = Double.infinity
        for (neighborColorIdx, _) in cluster.borderNeighbors {
            let cost = computeMergeCost(cluster, neighborColorIdx, plab, dominantSet, qMode ?? false)
            if cost < bestCost {
                bestCost = cost
                bestNeighbor = neighborColorIdx
            }
        }

        if bestNeighbor >= 0 && bestNeighbor != cluster.colorIdx {
            for pi in cluster.pixels {
                indices[pi] = UInt16(bestNeighbor)
            }
        }
    }
}

// MARK: - mergeTinyColors

/// 区域级少用色合并。对应源端 `mergeTinyColors`。
/// 将使用量低于 threshold 的颜色区域合并到最近邻居色，并紧凑化 palette 索引。
public func mergeTinyColors(
    _ indices: inout [UInt16], w: Int, h: Int,
    paletteUsed: [BeadColor], threshold: Int,
    protectMask: [UInt8]? = nil, empty: [UInt8]? = nil
) -> MergeTinyColorsResult {
    // 统计每色数量
    var counts: [Int: Int] = [:]
    for i in 0..<indices.count {
        if empty != nil && empty![i] != 0 { continue }
        let idx = Int(indices[i])
        counts[idx, default: 0] += 1
    }

    // 找出需要合并的颜色
    var tinySet = Set<Int>()
    for (idx, count) in counts {
        if count < threshold { tinySet.insert(idx) }
    }

    if tinySet.isEmpty {
        return MergeTinyColorsResult(indices: indices, paletteUsed: paletteUsed, mergedCount: 0)
    }

    // 区域级合并
    var visited = [UInt8](repeating: 0, count: w * h)
    let dx4 = [0, 0, -1, 1]
    let dy4 = [-1, 1, 0, 0]

    for startY in 0..<h {
        for startX in 0..<w {
            let startIdx = startY * w + startX
            if visited[startIdx] != 0 || (empty != nil && empty![startIdx] != 0) { continue }
            let color = Int(indices[startIdx])

            if !tinySet.contains(color) {
                // 标记同色连通域为已访问
                var queue: [Int] = [startIdx]
                visited[startIdx] = 1
                while !queue.isEmpty {
                    let ci = queue.removeFirst()
                    let cx = ci % w
                    let cy = ci / w
                    for d in 0..<4 {
                        let nx = cx + dx4[d]
                        let ny = cy + dy4[d]
                        if nx >= 0 && nx < w && ny >= 0 && ny < h {
                            let ni = ny * w + nx
                            if visited[ni] == 0 && Int(indices[ni]) == color {
                                visited[ni] = 1
                                queue.append(ni)
                            }
                        }
                    }
                }
                continue
            }

            // BFS this tiny-color cluster
            var regionPixels: [Int] = []
            var queue: [Int] = [startIdx]
            visited[startIdx] = 1
            var protectedRegion = false
            while !queue.isEmpty {
                let ci = queue.removeFirst()
                regionPixels.append(ci)
                if protectMask != nil && protectMask![ci] != 0 { protectedRegion = true }
                let cx = ci % w
                let cy = ci / w
                for d in 0..<4 {
                    let nx = cx + dx4[d]
                    let ny = cy + dy4[d]
                    if nx >= 0 && nx < w && ny >= 0 && ny < h {
                        let ni = ny * w + nx
                        if (empty == nil || empty![ni] == 0) && visited[ni] == 0 && Int(indices[ni]) == color {
                            visited[ni] = 1
                            queue.append(ni)
                        }
                    }
                }
            }

            if protectedRegion { continue }

            // 找最近的非 tiny 邻居色
            var borderColors: [Int: Int] = [:]
            for pi in regionPixels {
                let px = pi % w
                let py = pi / w
                for d in 0..<4 {
                    let nx = px + dx4[d]
                    let ny = py + dy4[d]
                    if nx >= 0 && nx < w && ny >= 0 && ny < h {
                        let ni = ny * w + nx
                        if (empty == nil || empty![ni] == 0) && Int(indices[ni]) != color {
                            let bc = Int(indices[ni])
                            borderColors[bc, default: 0] += 1
                        }
                    }
                }
            }

            var bestColor = color
            var bestCount = 0
            for (c, cnt) in borderColors {
                if !tinySet.contains(c) && cnt > bestCount { bestCount = cnt; bestColor = c }
            }
            // 如果所有边界邻居也是 tiny，选接触最多的
            if bestColor == color {
                for (c, cnt) in borderColors {
                    if cnt > bestCount { bestCount = cnt; bestColor = c }
                }
            }

            if bestColor != color {
                for pi in regionPixels {
                    indices[pi] = UInt16(bestColor)
                }
            }
        }
    }

    // 重建 paletteUsed（只保留使用中的颜色）
    var usedSet = Set<Int>()
    for i in 0..<indices.count {
        if empty == nil || empty![i] == 0 { usedSet.insert(Int(indices[i])) }
    }
    var newPalette: [BeadColor] = []
    var oldToNew: [Int: Int] = [:]
    var newIdx = 0
    // 源端用 Set.forEach 遍历；Swift Set 顺序不确定但结果一致性由索引映射保证。
    for oldIdx in usedSet.sorted() {
        newPalette.append(paletteUsed[oldIdx])
        oldToNew[oldIdx] = newIdx
        newIdx += 1
    }
    for i in 0..<indices.count {
        if empty != nil && empty![i] != 0 { continue }
        if let mapped = oldToNew[Int(indices[i])] {
            indices[i] = UInt16(mapped)
        }
    }

    return MergeTinyColorsResult(indices: indices, paletteUsed: newPalette, mergedCount: tinySet.count)
}
