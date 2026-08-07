import Foundation

// 风格化底稿相关类型。翻译自源端 BeadTypes.ets 的 StylizedDraft 子集。

/// 虚拟颜色角色。对应源端 `VirtualColorRole`。
public enum VirtualColorRole: String, Sendable {
    case furMain = "fur_main"
    case furShadow = "fur_shadow"
    case furHighlight = "fur_highlight"
    case eye
    case nose
    case outline
    case background
}

/// 虚拟颜色。对应源端 `VirtualColor`。
public struct VirtualColor: Identifiable, Equatable, Sendable {
    public var id: String
    public var rgb: [Int]       // [r, g, b]
    public var lab: [Double]    // [L, a, b]
    public var role: VirtualColorRole?

    public init(id: String, rgb: [Int], lab: [Double], role: VirtualColorRole? = nil) {
        self.id = id
        self.rgb = rgb
        self.lab = lab
        self.role = role
    }
}

/// 底稿诊断信息。对应源端 `DraftDiagnostics`。
public struct DraftDiagnostics: Equatable, Sendable {
    public var usedVirtualColorCount: Int
    public var subjectCoverageRatio: Double
    public var featurePreserveScore: Double
    public var colorBlockCleanliness: Double
    public var neutralShiftRatio: Double
    public var whiteToCoolRatio: Double
    public var averageRegionSize: Double

    public init(usedVirtualColorCount: Int, subjectCoverageRatio: Double,
                featurePreserveScore: Double, colorBlockCleanliness: Double,
                neutralShiftRatio: Double = 0, whiteToCoolRatio: Double = 0,
                averageRegionSize: Double = 0) {
        self.usedVirtualColorCount = usedVirtualColorCount
        self.subjectCoverageRatio = subjectCoverageRatio
        self.featurePreserveScore = featurePreserveScore
        self.colorBlockCleanliness = colorBlockCleanliness
        self.neutralShiftRatio = neutralShiftRatio
        self.whiteToCoolRatio = whiteToCoolRatio
        self.averageRegionSize = averageRegionSize
    }
}

/// 风格化底稿结果。对应源端 `StylizedDraftResult`。
public struct StylizedDraftResult: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var indices: [UInt8]
    public var virtualPalette: [VirtualColor]
    public var featureMask: [UInt8]?
    public var subjectMask: [UInt8]?
    public var diagnostics: DraftDiagnostics

    public init(width: Int, height: Int, indices: [UInt8],
                virtualPalette: [VirtualColor],
                featureMask: [UInt8]? = nil,
                subjectMask: [UInt8]? = nil,
                diagnostics: DraftDiagnostics) {
        self.width = width
        self.height = height
        self.indices = indices
        self.virtualPalette = virtualPalette
        self.featureMask = featureMask
        self.subjectMask = subjectMask
        self.diagnostics = diagnostics
    }
}
