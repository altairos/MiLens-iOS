import Foundation

// DraftToBeadMapper — 虚拟色板 → MARD 拼豆色映射。
// 逐行翻译自源端 shared/.../bead/DraftToBeadMapper.ets（237 行）。
// generateDraftAndMap 依赖 generateStylizedDraft（未迁移），暂跳过。

/// 底稿映射结果。对应源端 `DraftMappingResult`。
public struct DraftMappingResult {
    public var draft: StylizedDraftResult
    public var beadIndices: [UInt16]
}

/// 根据虚拟色在主体/背景中的分布推断角色。对应源端 `inferVirtualColorRoles`（私有）。
private func inferVirtualColorRoles(
    _ draft: StylizedDraftResult, mask: [UInt8]?
) -> [VirtualColorRole] {
    let total = draft.width * draft.height
    let palette = draft.virtualPalette
    let n = palette.count
    var roles = [VirtualColorRole](repeating: .background, count: n)
    var labL = [Double](repeating: 0, count: n)
    for i in 0..<n { labL[i] = palette[i].lab[0] }

    if mask == nil {
        // 无 mask：按面积 + 亮度分桶
        var areaCounts = [Int](repeating: 0, count: n)
        for i in 0..<total {
            let vIdx = Int(draft.indices[i])
            if vIdx == 255 || vIdx >= n { continue }
            areaCounts[vIdx] += 1
        }
        var maxIdx = -1, maxCount = 0
        for i in 0..<n { if areaCounts[i] > maxCount { maxCount = areaCounts[i]; maxIdx = i } }
        if maxIdx < 0 { return [VirtualColorRole](repeating: .furMain, count: n) }
        for i in 0..<n {
            if i == maxIdx {
                roles[i] = .furMain
            } else if labL[i] < 35 && Double(areaCounts[i]) > Double(total) * 0.005 {
                roles[i] = .outline
            } else if labL[i] > labL[maxIdx] + 10 {
                roles[i] = .furHighlight
            } else if labL[i] < labL[maxIdx] - 5 {
                roles[i] = .furShadow
            } else {
                roles[i] = .furMain
            }
        }
        return roles
    }

    // 有 mask：统计主体区域面积
    var subjectCounts = [Int](repeating: 0, count: n)
    for i in 0..<total {
        let vIdx = Int(draft.indices[i])
        if vIdx == 255 || vIdx >= n { continue }
        if mask![i] != 0 { subjectCounts[vIdx] += 1 }
    }
    var maxSubjectIdx = -1, maxSubjectCount = 0
    for i in 0..<n { if subjectCounts[i] > maxSubjectCount { maxSubjectCount = subjectCounts[i]; maxSubjectIdx = i } }
    for i in 0..<n {
        if subjectCounts[i] == 0 { roles[i] = .background; continue }
        if i == maxSubjectIdx {
            roles[i] = .furMain
        } else if labL[i] < 35 && Double(subjectCounts[i]) > Double(total) * 0.005 {
            roles[i] = .outline
        } else if labL[i] > labL[maxSubjectIdx] + 10 {
            roles[i] = .furHighlight
        } else if labL[i] < labL[maxSubjectIdx] - 5 {
            roles[i] = .furShadow
        } else {
            roles[i] = .furMain
        }
    }
    return roles
}

/// 角色偏好标签映射。对应源端 `ROLE_TAG_AFFINITY`。
private let roleTagAffinity: [VirtualColorRole: [BeadColorTag]] = [
    .furMain:      [.warmWhite, .cream, .orangeFur, .brownFur],
    .furShadow:    [.brownFur, .softBlack, .warmGray],
    .furHighlight: [.warmWhite, .cream, .neutralWhite],
    .eye:          [.eyeColor, .black, .softBlack],
    .nose:         [.pinkNose, .brownFur],
    .outline:      [.black, .softBlack],
    .background:   [.background, .coolGray, .neutralWhite],
]

/// 从风格化底稿生成 MARD 拼豆索引图（含角色偏好权重）。
/// 对应源端 `mapDraftToBeadPalette`。
public func mapDraftToBeadPalette(
    _ draft: StylizedDraftResult, paletteLab: [LabColor],
    petPenalty: Double = 0, beadColors: [BeadColor]? = nil,
    mask: [UInt8]? = nil
) -> [UInt16] {
    let total = draft.width * draft.height
    var beadIndices = [UInt16](repeating: 0, count: total)
    let virtualPalette = draft.virtualPalette

    // 推断虚拟色角色
    let roles: [VirtualColorRole]
    if beadColors != nil && beadColors!.count == paletteLab.count {
        roles = inferVirtualColorRoles(draft, mask: mask)
    } else {
        roles = [VirtualColorRole](repeating: .furMain, count: virtualPalette.count)
    }

    // 为每个虚拟颜色预计算最近的 MARD 色板色
    var virtualToMard: [Int] = []
    for vi in 0..<virtualPalette.count {
        let vc = virtualPalette[vi]
        let lab = LabColor(L: vc.lab[0], a: vc.lab[1], b: vc.lab[2])
        let role = roles[vi]
        let preferredTags = roleTagAffinity[role] ?? []

        if let beadColors, !preferredTags.isEmpty {
            var bestIdx = 0
            var bestDist = Double.infinity
            for j in 0..<paletteLab.count {
                var dist = paletteMatchDistance(lab, paletteLab[j], petFriendlyPenalty: petPenalty)
                if let tags = beadColors[j].tags {
                    for pt in preferredTags {
                        if tags.contains(pt) { dist *= 0.85; break }
                    }
                }
                if dist < bestDist { bestDist = dist; bestIdx = j }
            }
            virtualToMard.append(bestIdx)
        } else {
            let nearest = findNearestBeadColor(lab.L, lab.a, lab.b, paletteLab: paletteLab, petFriendlyPenalty: petPenalty)
            virtualToMard.append(nearest.index)
        }
    }

    // 映射每个像素
    for i in 0..<total {
        let vIdx = Int(draft.indices[i])
        if vIdx == 255 {
            beadIndices[i] = 65535
        } else if vIdx < virtualToMard.count {
            beadIndices[i] = UInt16(virtualToMard[vIdx])
        } else {
            beadIndices[i] = 65535
        }
    }
    return beadIndices
}
