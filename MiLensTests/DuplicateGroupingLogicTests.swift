//  DuplicateGroupingLogicTests —— 重复分组 + 感知哈希纯逻辑测试
//  翻译源端 entry/src/test/QualityScorer.test.ets（3 用例）。
//  对应源端 PHash.hammingDistance → PerceptualHashLogic.hammingDistance，
//  源端 buildDuplicateGroups → DuplicateGroupingLogic.buildDuplicateGroups。

import XCTest
@testable import MiLens

final class DuplicateGroupingLogicTests: XCTestCase {

    /// 构造固定 UUID 候选（后缀对应源端自增 id，保证确定性）。
    private func candidate(_ idSuffix: Int, hash: String, quality: Double, sharpness: Double = 0) -> DuplicateCandidate {
        DuplicateCandidate(
            id: uuid(idSuffix), phash: hash, qualityScore: quality, sharpness: sharpness,
            width: 100, height: 100, fileSize: 0
        )
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }

    // MARK: - 汉明距离（对应源端 'counts differing hash bits instead of differing hex characters'）

    func testHammingDistanceCountsBitsNotHexChars() {
        XCTAssertEqual(PerceptualHashLogic.hammingDistance("0000000000000000", "f000000000000000"), 4)
        XCTAssertEqual(PerceptualHashLogic.hammingDistance("0000000000000000", "ff00000000000000"), 8)
        // 非法 hex 字符 → 999（源端降级）
        XCTAssertEqual(PerceptualHashLogic.hammingDistance("invalid", "0000000"), 999)
    }

    func testHammingDistanceRejectsMismatchedLengths() {
        XCTAssertEqual(PerceptualHashLogic.hammingDistance("0000", "000000"), 999)
    }

    func testBinaryToHex() {
        XCTAssertEqual(PerceptualHashLogic.binaryToHex("1111000011110000"), "f0f0")
        XCTAssertEqual(PerceptualHashLogic.binaryToHex("0000000000000000"), "0000")
    }

    // MARK: - 传递性分组（对应源端 'forms transitive groups and chooses the highest quality photo'）

    func testFormsTransitiveGroupsAndChoosesHighestQuality() {
        let groups = DuplicateGroupingLogic.buildDuplicateGroups([
            candidate(1, hash: "0000000000000000", quality: 0.2),
            candidate(2, hash: "ff00000000000000", quality: 0.9),
            candidate(3, hash: "ffff000000000000", quality: 0.5),
            candidate(4, hash: "ffffffffffffffff", quality: 0.4),
            candidate(5, hash: "fffffffffffffff0", quality: 0.7),
            // 源端 photo(-1, '0000…0', 1.0) 靠 id<=0 过滤；iOS UUID 恒有效故省略，
            // 改用空 phash 项验证过滤（对应源端 photo(6, '', 1.0)）。
            candidate(6, hash: "", quality: 1.0)
        ])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].count, 3)
        XCTAssertEqual(groups[0][0].id, uuid(2))
        XCTAssertEqual(groups[1][0].id, uuid(5))
    }

    // MARK: - 质量平局 tiebreaker（对应源端 'uses sharpness and id as deterministic quality tie breakers'）

    func testSharpnessAndIdAsDeterministicTieBreakers() {
        let groups = DuplicateGroupingLogic.buildDuplicateGroups([
            candidate(9, hash: "0000000000000000", quality: 0.8, sharpness: 0.3),
            candidate(8, hash: "0000000000000001", quality: 0.8, sharpness: 0.7),
            candidate(7, hash: "0000000000000003", quality: 0.8, sharpness: 0.7)
        ])
        XCTAssertEqual(groups[0][0].id, uuid(7))
    }

    // MARK: - 边界（iOS 增强）

    func testEmptyHashesProduceNoGroups() {
        let groups = DuplicateGroupingLogic.buildDuplicateGroups([
            candidate(1, hash: "", quality: 1.0),
            candidate(2, hash: "", quality: 1.0)
        ])
        XCTAssertTrue(groups.isEmpty)
    }

    func testSingleCandidateProducesNoGroups() {
        let groups = DuplicateGroupingLogic.buildDuplicateGroups([
            candidate(1, hash: "0000000000000000", quality: 1.0)
        ])
        XCTAssertTrue(groups.isEmpty)
    }

    func testDissimilarHashesProduceNoGroups() {
        let groups = DuplicateGroupingLogic.buildDuplicateGroups([
            candidate(1, hash: "0000000000000000", quality: 1.0),
            candidate(2, hash: "ffffffffffffffff", quality: 1.0) // 距离 32，远超阈值 8
        ])
        XCTAssertTrue(groups.isEmpty)
    }
}
