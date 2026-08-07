import Foundation

// BeadSemanticGuide — 语义色板引导：复用 CLIP 分类结果调整宠物友好惩罚。
// 逐行翻译自源端 shared/.../bead/BeadSemanticGuide.ets（58 行）。

/// 语义引导结果。对应源端 `BeadSemanticGuideResult`。
public struct BeadSemanticGuideResult: Equatable {
    public var applied: Bool
    public var species: String?
    public var originalPetFriendlyPenalty: Double
    public var petFriendlyPenalty: Double
}

private let minSemanticConfidence = 0.18

/// 物种惩罚缩放因子（私有）。对应源端 `penaltyScaleForSpecies`。
private func penaltyScaleForSpecies(_ species: String) -> Double {
    if species == "fish" { return 0.15 }
    if species == "bird" { return 0.35 }
    if species == "turtle" { return 0.55 }
    return 1
}

/// 可变的生成选项引用（语义引导需要修改 petFriendlyPenalty）。
/// 源端直接修改 BeadGenerateOptions 对象；Swift 侧用 class 使其可变。
public final class BeadGenerateOptionsMutable {
    public var petFriendlyPenalty: Double
    public init(petFriendlyPenalty: Double) {
        self.petFriendlyPenalty = petFriendlyPenalty
    }
}

/// 复用 MindSpore CLIP 分类结果，防止猫/狗导向的毛色惩罚压制有效冷色。
/// 对应源端 `applySemanticPaletteSteering`。
public func applySemanticPaletteSteering(
    _ options: BeadGenerateOptionsMutable,
    detection: DetectionResult?
) -> BeadSemanticGuideResult {
    let original = options.petFriendlyPenalty
    guard let detection, detection.isPet, let species = detection.species,
          detection.topConfidence >= minSemanticConfidence else {
        return BeadSemanticGuideResult(
            applied: false,
            species: detection?.species,
            originalPetFriendlyPenalty: original,
            petFriendlyPenalty: original
        )
    }

    let scale = penaltyScaleForSpecies(species)
    if scale >= 1 {
        return BeadSemanticGuideResult(
            applied: false,
            species: species,
            originalPetFriendlyPenalty: original,
            petFriendlyPenalty: original
        )
    }

    options.petFriendlyPenalty = original * scale
    return BeadSemanticGuideResult(
        applied: true,
        species: species,
        originalPetFriendlyPenalty: original,
        petFriendlyPenalty: options.petFriendlyPenalty
    )
}
