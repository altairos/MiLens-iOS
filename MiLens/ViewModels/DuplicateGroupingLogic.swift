//  DuplicateGroupingLogic —— 重复照片分组纯逻辑
//  （对应源端 services/QualityScorer.ets buildDuplicateGroups + compareQuality）。
//
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。
//  算法：Union-Find 传递闭包（O(n²)），按质量降序选每组 best。
//  源端 id 为自增整数且有 `id > 0` 过滤；iOS 用 UUID（恒有效），
//  仅按 phash 非空过滤（无效项用空 phash 表示）。

import Foundation

/// 重复分析候选（Photo 的轻量投影，脱离 SwiftData `@Model` 以便纯逻辑测试）。
/// 对应源端 `buildDuplicateGroups` 读取的 Photo 字段子集。
struct DuplicateCandidate: Equatable, Sendable {
    let id: UUID
    let phash: String
    let qualityScore: Double
    let sharpness: Double
    let width: Int
    let height: Int
    let fileSize: Int64
}

/// 重复照片分组纯逻辑（对应源端 `buildDuplicateGroups` + `compareQuality`）。
enum DuplicateGroupingLogic {
    /// 质量比较器（对应源端 `compareQuality`）：
    /// qualityScore → sharpness → 像素数 → fileSize → id 字典序（确定性 tiebreaker）。
    /// 返回 true 表示 `left` 更优（应排在 `right` 前面）。
    static func compareQuality(_ left: DuplicateCandidate, _ right: DuplicateCandidate) -> Bool {
        if left.qualityScore != right.qualityScore {
            return left.qualityScore > right.qualityScore
        }
        if left.sharpness != right.sharpness {
            return left.sharpness > right.sharpness
        }
        let leftPixels = left.width * left.height
        let rightPixels = right.width * right.height
        if leftPixels != rightPixels {
            return leftPixels > rightPixels
        }
        if left.fileSize != right.fileSize {
            return left.fileSize > right.fileSize
        }
        // 源端用自增 id 升序（创建顺序）；iOS 用 UUID 字符串字典序保证确定性输出。
        return left.id.uuidString < right.id.uuidString
    }

    /// 构建传递性重复分组并为每组选一个确定的最佳照片。
    /// - Parameter candidates: 候选照片列表（仅 phash 非空的项参与）
    /// - Returns: 重复组列表（每组 > 1 张，组内按质量降序，组间按 best 的 id 排序）
    static func buildDuplicateGroups(_ candidates: [DuplicateCandidate]) -> [[DuplicateCandidate]] {
        let valid = candidates.filter { !$0.phash.isEmpty }
        let n = valid.count
        guard n > 1 else { return [] }

        // Union-Find（路径压缩，对应源端 parent 数组 + findRoot）
        var parent = Array(0..<n)
        func findRoot(_ index: Int) -> Int {
            var root = index
            while parent[root] != root { root = parent[root] }
            var current = index
            while parent[current] != current {
                let next = parent[current]
                parent[current] = root
                current = next
            }
            return root
        }

        for i in 0..<n {
            for j in (i + 1)..<n {
                guard PerceptualHashLogic.isSimilar(valid[i].phash, valid[j].phash) else { continue }
                let leftRoot = findRoot(i)
                let rightRoot = findRoot(j)
                if leftRoot != rightRoot { parent[rightRoot] = leftRoot }
            }
        }

        var grouped: [Int: [DuplicateCandidate]] = [:]
        for i in 0..<n {
            let root = findRoot(i)
            grouped[root, default: []].append(valid[i])
        }

        var result: [[DuplicateCandidate]] = []
        for (_, var group) in grouped {
            guard group.count > 1 else { continue }
            group.sort(by: compareQuality)
            result.append(group)
        }
        // 组间按 best 的 id 排序（源端按自增 id 升序；iOS 用 UUID 字典序）。
        result.sort { $0[0].id.uuidString < $1[0].id.uuidString }
        return result
    }
}
