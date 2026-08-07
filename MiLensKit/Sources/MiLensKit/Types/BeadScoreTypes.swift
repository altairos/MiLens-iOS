import Foundation

// Scoring/SemanticGuide/PoseProtection 所需的共享类型。
// 翻译自源端 BeadTypes.ets（TriScore）+ types/DetectionResult.ets + BeadTypes.ets（Pose）。

// MARK: - TriScore

/// 三目标评分：识别感 × 0.45 + 美观度 × 0.35 + 可拼性 × 0.20。对应源端 `TriScore`。
public struct TriScore: Equatable, Sendable {
    public var identityScore: Double    // 0–100
    public var aestheticScore: Double   // 0–100
    public var beadabilityScore: Double // 0–100
    public var overall: Double          // 加权总分

    public init(identityScore: Double, aestheticScore: Double, beadabilityScore: Double, overall: Double) {
        self.identityScore = identityScore
        self.aestheticScore = aestheticScore
        self.beadabilityScore = beadabilityScore
        self.overall = overall
    }
}

// MARK: - DetectionResult

/// 宠物检测结果（语义引导用）。对应源端 `types/DetectionResult.ets` 的最小子集。
public struct DetectionResult: Sendable {
    public var isPet: Bool
    public var species: String?
    public var topConfidence: Double

    public init(isPet: Bool, species: String?, topConfidence: Double) {
        self.isPet = isPet
        self.species = species
        self.topConfidence = topConfidence
    }
}

// MARK: - Pose 关键点

/// 宠物五官关键点。对应源端 `BeadPoseKeypoint`。
public struct BeadPoseKeypoint: Equatable, Sendable {
    public var x: Double       // 归一化坐标
    public var y: Double
    public var confidence: Double

    public init(x: Double, y: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

/// 固定顺序关键点集（左眼、右眼、鼻子、左耳尖、右耳尖）。对应源端 `BeadPoseData`。
public struct BeadPoseData: Equatable, Sendable {
    public var keypoints: [BeadPoseKeypoint]

    public init(keypoints: [BeadPoseKeypoint]) {
        self.keypoints = keypoints
    }
}
