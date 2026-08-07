import XCTest
@testable import MiLensKit

/// BeadSemanticGuide 测试。翻译自源端 shared/.../test/BeadSemanticGuide.test.ets。
final class BeadSemanticGuideTests: XCTestCase {

    private func detection(_ species: String?, _ confidence: Double, _ isPet: Bool = true) -> DetectionResult {
        return DetectionResult(isPet: isPet, species: species, topConfidence: confidence)
    }

    func testDoesNothingWithoutConfidentPetSpecies() {
        let opts = BeadGenerateOptionsMutable(petFriendlyPenalty: 20)
        XCTAssertFalse(applySemanticPaletteSteering(opts, detection: nil).applied)
        XCTAssertFalse(applySemanticPaletteSteering(opts, detection: detection("fish", 0.1)).applied)
        XCTAssertFalse(applySemanticPaletteSteering(opts, detection: detection("fish", 0.9, false)).applied)
        XCTAssertEqual(opts.petFriendlyPenalty, 20)
    }

    func testKeepsCatAndDogPenaltiesUnchanged() {
        let opts = BeadGenerateOptionsMutable(petFriendlyPenalty: 20)
        let result = applySemanticPaletteSteering(opts, detection: detection("cat", 0.9))
        XCTAssertFalse(result.applied)
        XCTAssertEqual(opts.petFriendlyPenalty, 20)
    }

    func testScalesFishBirdAndTurtlePenaltiesBySpecies() {
        let fish = BeadGenerateOptionsMutable(petFriendlyPenalty: 20)
        let bird = BeadGenerateOptionsMutable(petFriendlyPenalty: 20)
        let turtle = BeadGenerateOptionsMutable(petFriendlyPenalty: 20)
        XCTAssertEqual(applySemanticPaletteSteering(fish, detection: detection("fish", 0.9)).petFriendlyPenalty, 3)
        XCTAssertEqual(applySemanticPaletteSteering(bird, detection: detection("bird", 0.9)).petFriendlyPenalty, 7)
        XCTAssertEqual(applySemanticPaletteSteering(turtle, detection: detection("turtle", 0.9)).petFriendlyPenalty, 11)
    }
}
