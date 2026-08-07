//  PerceptualHashLogic —— 感知哈希运算纯逻辑
//  （对应源端 utils/pHash.ets 的 hammingDistance / isSimilar / binaryToHex）。
//
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖。
//  注意：源端注释称「DCT pHash」但实际实现为均值哈希（aHash）；
//  iOS 侧沿用实际实现并诚实标注（AGENTS.md §4 保留诚实标注原则）。

import Foundation

/// 感知哈希运算纯逻辑（对应源端 `PHash` 静态方法）。
enum PerceptualHashLogic {
    /// 0–15 的 popcount 查找表（对应源端 `PHash.BIT_COUNTS`）。
    static let bitCounts: [Int] = [0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4]
    /// pHash 汉明距离默认相似阈值（对应源端 `isSimilar` 默认 8）。
    static let defaultSimilarThreshold = 8

    /// 计算两个十六进制 pHash 字符串的汉明距离（不同 bit 数）。
    /// - Parameters:
    ///   - hash1: 十六进制哈希字符串（如 "0000000000000000"）
    ///   - hash2: 同长度十六进制哈希字符串
    /// - Returns: 不同 bit 数；长度不等或含非法字符时返回 999（对应源端降级）
    static func hammingDistance(_ hash1: String, _ hash2: String) -> Int {
        guard hash1.count == hash2.count else { return 999 }
        var distance = 0
        for (c1, c2) in zip(hash1, hash2) {
            guard let left = c1.hexDigitValue, let right = c2.hexDigitValue else { return 999 }
            distance += bitCounts[left ^ right]
        }
        return distance
    }

    /// 判断两张照片是否相似（汉明距离 ≤ 阈值）。
    static func isSimilar(_ hash1: String, _ hash2: String, threshold: Int = defaultSimilarThreshold) -> Bool {
        hammingDistance(hash1, hash2) <= threshold
    }

    /// 将 64 位二进制字符串转为 16 位十六进制字符串。
    static func binaryToHex(_ binary: String) -> String {
        var hex = ""
        var i = binary.startIndex
        while i < binary.endIndex {
            let next = binary.index(i, offsetBy: 4, limitedBy: binary.endIndex) ?? binary.endIndex
            let chunk = String(binary[i..<next])
            if let value = Int(chunk, radix: 2) {
                hex += String(value, radix: 16)
            }
            i = next
        }
        return hex
    }
}
