import Foundation

// 渲染相关类型。翻译自源端 BeadTypes.ets 的渲染子集。

/// Canvas 尺寸。对应源端 `CanvasSize`。
public struct CanvasSize: Equatable {
    public var width: Int
    public var height: Int

    public init(_ width: Int, _ height: Int) {
        self.width = width
        self.height = height
    }
}

/// 图纸视图模式。对应源端 `BeadViewMode`（'color' | 'mard' | 'letter'）。
public typealias BeadViewMode = String

/// 粗线间隔（每 5 格一条粗线）。对应源端 `BEAD_GRID_BOLD_INTERVAL`。
public let BEAD_GRID_BOLD_INTERVAL = 5

/// 完整拼豆图纸数据结构。对应源端 `BeadPattern`。
public struct BeadPattern {
    public var width: Int
    public var height: Int
    public var indices: [UInt16]
    public var empty: [UInt8]
    public var protectMask: [UInt8]
    public var faceRoi: CropArea?
    public var paletteUsed: [BeadColor]
    public var colorCounts: [BeadColorCount]
    public var warnings: [String]
    public var score: BeadScore
    public var diagnostics: PatternDiagnostics?
    public var shortSymbols: [String]?
    public var triScore: TriScore?
    public var autoColorHint: String?

    public init(width: Int = 0, height: Int = 0, indices: [UInt16] = [],
                empty: [UInt8] = [], protectMask: [UInt8] = [], faceRoi: CropArea? = nil,
                paletteUsed: [BeadColor] = [],
                colorCounts: [BeadColorCount] = [], warnings: [String] = [],
                score: BeadScore = BeadScore(colorError: 0, detailScore: 0, estimatedDifficulty: 0, level: "", totalBeads: 0, colorCount: 0, estimatedMinutes: ""),
                diagnostics: PatternDiagnostics? = nil,
                shortSymbols: [String]? = nil,
                triScore: TriScore? = nil, autoColorHint: String? = nil) {
        self.width = width; self.height = height; self.indices = indices
        self.empty = empty; self.protectMask = protectMask; self.faceRoi = faceRoi
        self.paletteUsed = paletteUsed
        self.colorCounts = colorCounts; self.warnings = warnings
        self.score = score; self.diagnostics = diagnostics
        self.shortSymbols = shortSymbols
        self.triScore = triScore; self.autoColorHint = autoColorHint
    }

    /// 构造 BeadPatternRef（computeTriScore 等模块需要）。
    public func toRef() -> BeadPatternRef {
        return BeadPatternRef(width: width, height: height, indices: indices,
                              empty: empty, paletteUsed: paletteUsed,
                              score: score, diagnostics: diagnostics)
    }
}

/// 绘图选项。对应源端 `BeadDrawOptions`。
public struct BeadDrawOptions {
    public var circularCrop: Bool?
    public var borderColor: String?

    public init(circularCrop: Bool? = nil, borderColor: String? = nil) {
        self.circularCrop = circularCrop
        self.borderColor = borderColor
    }
}

/// 导出选项。对应源端 `BeadExportOpts`。
public struct BeadExportOpts {
    public var circularCrop: Bool?
    public var borderColor: String?

    public init(circularCrop: Bool? = nil, borderColor: String? = nil) {
        self.circularCrop = circularCrop
        self.borderColor = borderColor
    }
}
