//  QualityScoringLogicTests —— 质量评分纯公式测试
//  翻译源端 entry/src/test/MorePureLogic.test.ets 的
//  'ImageUtils computeQualityScore' describe 块（4 用例）。
//  对应源端 ImageUtils.computeQualityScore → QualityScoringLogic.computeQualityScore。

import XCTest
@testable import MiLens

final class QualityScoringLogicTests: XCTestCase {

    // MARK: - 完美清晰度（对应源端 'returns 1.0 for perfect sharpness with pet at full HD'）

    func testPerfectSharpnessWithPetAtFullHDReturnsNearOne() {
        let score = QualityScoringLogic.computeQualityScore(sharpness: 5000, hasPet: true, width: 1920, height: 1080)
        // 0.4*1.0 + 0.3*1.0 + 0.3*1.0 = 1.0
        XCTAssertGreaterThan(score, 0.99)
        XCTAssertLessThanOrEqual(score, 1.0)
    }

    // MARK: - 宠物因子加权（对应源端 'gives higher score with pet than without'）

    func testPetFactorGivesHigherScoreThanWithoutPet() {
        let withPet = QualityScoringLogic.computeQualityScore(sharpness: 3000, hasPet: true, width: 1920, height: 1080)
        let withoutPet = QualityScoringLogic.computeQualityScore(sharpness: 3000, hasPet: false, width: 1920, height: 1080)
        XCTAssertGreaterThan(withPet, withoutPet)
    }

    // MARK: - 清晰度封顶（对应源端 'caps clarity contribution at sharpness/5000'）

    func testClarityCapsAt5000Sharpness() {
        let capped = QualityScoringLogic.computeQualityScore(sharpness: 99999, hasPet: true, width: 1920, height: 1080)
        let at5000 = QualityScoringLogic.computeQualityScore(sharpness: 5000, hasPet: true, width: 1920, height: 1080)
        // 两者 clarityNorm 都被限制在 1.0，总分应相等
        XCTAssertEqual(capped, at5000, accuracy: 0.001)
    }

    // MARK: - 低质量低分（对应源端 'produces lower score for small low-sharpness image without pet'）

    func testSmallLowSharpnessWithoutPetProducesLowScore() {
        let score = QualityScoringLogic.computeQualityScore(sharpness: 0, hasPet: false, width: 100, height: 100)
        // 0.4*0 + 0.3*0.5 + 0.3*(10000/2073600) ≈ 0.15 + 0.0014 ≈ 0.151
        XCTAssertLessThan(score, 0.2)
        XCTAssertGreaterThan(score, 0.1)
    }
}
