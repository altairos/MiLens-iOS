import Foundation

// RedPacketTemplate — 结构化红包模板（对应红包封面开发计划 §2.1）。
//
// 模板必须是结构化资源，而不是单张背景图。每个模板包含背景/前景层资源、
// 默认宠物位置/缩放/旋转、安全区和风险区、默认文本样式与位置、推荐配饰分类。
// Phase 0 用程序化绘制（渐变/纯色/装饰），resourceRef 字段预留未来真实 PNG 素材。

// MARK: - 归一化矩形

/// 归一化矩形（0–1 坐标系，相对画布）。
public struct RedPacketNormalizedRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// 全画布安全区。
    public static let full = RedPacketNormalizedRect(x: 0, y: 0, width: 1, height: 1)
}

// MARK: - 背景描述符

/// 模板背景/前景的视觉描述（程序化绘制，对应红包封面开发计划 §2.1）。
public enum RedPacketBackgroundDescriptor: Codable, Equatable, Sendable {

    /// 纯色填充。
    case solid(colorHex: String)

    /// 线性渐变。
    /// - colors: 渐变颜色（十六进制），从起点到终点。
    /// - angle: 渐变角度（度，0=上→下，90=左→右）。
    case gradient(colors: [String], angle: Double)

    /// 装饰背景：基础渐变 + 程序化图案。
    /// - base: 底层渐变。
    /// - pattern: 装饰图案类型（如 "circles" / "dots" / "waves"）。
    /// - patternColorHex: 图案颜色（十六进制）。
    case decorated(base: GradientBase, pattern: String, patternColorHex: String)

    /// 资源引用（未来真实 PNG，Phase 0 不使用）。
    case resource(resourceRef: String)

    /// 简化渐变基类（用于 decorated 的 base）。
    public struct GradientBase: Codable, Equatable, Sendable {
        public var colors: [String]
        public var angle: Double
        public init(colors: [String], angle: Double) {
            self.colors = colors
            self.angle = angle
        }
    }
}

// MARK: - 默认变换

/// 默认宠物变换（画布坐标）。
public struct RedPacketDefaultTransform: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var scale: Double
    public var rotation: Double

    public init(x: Double, y: Double, scale: Double = 1.0, rotation: Double = 0) {
        self.x = x
        self.y = y
        self.scale = scale
        self.rotation = rotation
    }
}

// MARK: - 模板

/// 结构化红包模板（对应红包封面开发计划 §2.1）。
public struct RedPacketTemplate: Codable, Equatable, Sendable, Identifiable {

    /// 模板 ID（稳定标识）。
    public var id: String
    /// 模板版本号。
    public var revision: Int
    /// 显示名（直接文本，非本地化 key——保持模板纯数据）。
    public var displayName: String
    /// 本地化 key（App 层从 xcstrings 取，模板层只存 key）。
    public var displayNameKey: String
    /// 描述本地化 key。
    public var descriptionKey: String

    /// 背景层描述。
    public var background: RedPacketBackgroundDescriptor
    /// 前景层描述（nil = 无前景层）。
    public var foreground: RedPacketBackgroundDescriptor?

    /// 默认宠物变换。
    public var defaultPetTransform: RedPacketDefaultTransform
    /// 安全区（归一化，关键元素应在此区域内）。
    public var safeZone: RedPacketNormalizedRect
    /// 风险区（归一化，会被平台遮挡的区域，如拆红包页金额按钮区）。
    public var riskZone: RedPacketNormalizedRect

    /// 默认文本风格预置。
    public var defaultTextStylePreset: RedPacketTextStylePreset
    /// 默认文本位置（画布坐标）。
    public var defaultTextPosition: RedPacketDefaultTransform

    /// 推荐配饰分类。
    public var recommendedAccessoryCategories: [String]

    /// 缩略图描述（用程序化背景渲染）。
    public var thumbnailBackground: RedPacketBackgroundDescriptor

    /// 是否免费模板。
    public var isFree: Bool

    public init(
        id: String,
        revision: Int,
        displayName: String,
        displayNameKey: String,
        descriptionKey: String,
        background: RedPacketBackgroundDescriptor,
        foreground: RedPacketBackgroundDescriptor? = nil,
        defaultPetTransform: RedPacketDefaultTransform,
        safeZone: RedPacketNormalizedRect,
        riskZone: RedPacketNormalizedRect,
        defaultTextStylePreset: RedPacketTextStylePreset,
        defaultTextPosition: RedPacketDefaultTransform,
        recommendedAccessoryCategories: [String],
        thumbnailBackground: RedPacketBackgroundDescriptor? = nil,
        isFree: Bool = true
    ) {
        self.id = id
        self.revision = revision
        self.displayName = displayName
        self.displayNameKey = displayNameKey
        self.descriptionKey = descriptionKey
        self.background = background
        self.foreground = foreground
        self.defaultPetTransform = defaultPetTransform
        self.safeZone = safeZone
        self.riskZone = riskZone
        self.defaultTextStylePreset = defaultTextStylePreset
        self.defaultTextPosition = defaultTextPosition
        self.recommendedAccessoryCategories = recommendedAccessoryCategories
        self.thumbnailBackground = thumbnailBackground ?? background
        self.isFree = isFree
    }
}

// MARK: - 模板目录（冻结 4 套）

/// 红包模板目录。Phase 0 冻结 4 套风格（全程序化）。
public enum RedPacketTemplateCatalog {

    /// 画布尺寸常量。
    public static var canvasWidth: Double { Double(WeChatRedPacketSpec.coverImageWidth) }
    public static var canvasHeight: Double { Double(WeChatRedPacketSpec.coverImageHeight) }

    /// 中心点 x。
    public static var centerX: Double { canvasWidth / 2 }
    /// 中心点 y。
    public static var centerY: Double { canvasHeight / 2 }

    /// 全部模板。
    public static let all: [RedPacketTemplate] = [
        newYearRed,
        fortuneGold,
        floralSpring,
        petFresh,
    ]

    /// 按 ID 查找模板。
    public static func find(id: String) -> RedPacketTemplate? {
        all.first { $0.id == id }
    }

    /// 首套免费模板（Phase 1 单模板闭环使用）。
    public static let firstFreeTemplate: RedPacketTemplate = newYearRed

    // MARK: - 模板 1：新年红（首套免费）

    public static let newYearRed = RedPacketTemplate(
        id: "new_year_red",
        revision: 1,
        displayName: "新年红",
        displayNameKey: "redpacket.template.newYearRed.title",
        descriptionKey: "redpacket.template.newYearRed.desc",
        background: .decorated(
            base: .init(colors: ["#C8102E", "#8B0000"], angle: 135),
            pattern: "circles",
            patternColorHex: "#FFD700"
        ),
        foreground: .gradient(colors: ["#00000000", "#00000066"], angle: 0),
        defaultPetTransform: RedPacketDefaultTransform(
            x: centerX, y: centerY * 0.85, scale: 1.0
        ),
        safeZone: RedPacketNormalizedRect(x: 0.08, y: 0.06, width: 0.84, height: 0.5),
        riskZone: RedPacketNormalizedRect(x: 0, y: 0.7, width: 1, height: 0.3),
        defaultTextStylePreset: .festive,
        defaultTextPosition: RedPacketDefaultTransform(
            x: canvasWidth * 0.5, y: canvasHeight * 0.22
        ),
        recommendedAccessoryCategories: ["newyear", "fortune"],
        isFree: true
    )

    // MARK: - 模板 2：招财金

    public static let fortuneGold = RedPacketTemplate(
        id: "fortune_gold",
        revision: 1,
        displayName: "招财金",
        displayNameKey: "redpacket.template.fortuneGold.title",
        descriptionKey: "redpacket.template.fortuneGold.desc",
        background: .gradient(colors: ["#FFD700", "#DAA520", "#B8860B"], angle: 160),
        foreground: .gradient(colors: ["#00000000", "#00000033"], angle: 0),
        defaultPetTransform: RedPacketDefaultTransform(
            x: centerX, y: centerY * 0.85, scale: 1.0
        ),
        safeZone: RedPacketNormalizedRect(x: 0.08, y: 0.06, width: 0.84, height: 0.5),
        riskZone: RedPacketNormalizedRect(x: 0, y: 0.7, width: 1, height: 0.3),
        defaultTextStylePreset: .goldBlessing,
        defaultTextPosition: RedPacketDefaultTransform(
            x: canvasWidth * 0.5, y: canvasHeight * 0.22
        ),
        recommendedAccessoryCategories: ["fortune", "wealth"],
        isFree: false
    )

    // MARK: - 模板 3：花卉春

    public static let floralSpring = RedPacketTemplate(
        id: "floral_spring",
        revision: 1,
        displayName: "花卉春",
        displayNameKey: "redpacket.template.floralSpring.title",
        descriptionKey: "redpacket.template.floralSpring.desc",
        background: .decorated(
            base: .init(colors: ["#FFE4E1", "#FFB6C1"], angle: 120),
            pattern: "dots",
            patternColorHex: "#FF69B4"
        ),
        foreground: .gradient(colors: ["#00000000", "#00000022"], angle: 0),
        defaultPetTransform: RedPacketDefaultTransform(
            x: centerX, y: centerY * 0.85, scale: 1.0
        ),
        safeZone: RedPacketNormalizedRect(x: 0.08, y: 0.06, width: 0.84, height: 0.5),
        riskZone: RedPacketNormalizedRect(x: 0, y: 0.7, width: 1, height: 0.3),
        defaultTextStylePreset: .handwriting,
        defaultTextPosition: RedPacketDefaultTransform(
            x: canvasWidth * 0.5, y: canvasHeight * 0.22
        ),
        recommendedAccessoryCategories: ["flower", "pet"],
        isFree: false
    )

    // MARK: - 模板 4：宠物清新

    public static let petFresh = RedPacketTemplate(
        id: "pet_fresh",
        revision: 1,
        displayName: "宠物清新",
        displayNameKey: "redpacket.template.petFresh.title",
        descriptionKey: "redpacket.template.petFresh.desc",
        background: .gradient(colors: ["#E0F7FA", "#B2EBF2", "#80DEEA"], angle: 180),
        foreground: .gradient(colors: ["#00000000", "#00000022"], angle: 0),
        defaultPetTransform: RedPacketDefaultTransform(
            x: centerX, y: centerY * 0.85, scale: 1.0
        ),
        safeZone: RedPacketNormalizedRect(x: 0.08, y: 0.06, width: 0.84, height: 0.5),
        riskZone: RedPacketNormalizedRect(x: 0, y: 0.7, width: 1, height: 0.3),
        defaultTextStylePreset: .petName,
        defaultTextPosition: RedPacketDefaultTransform(
            x: canvasWidth * 0.5, y: canvasHeight * 0.22
        ),
        recommendedAccessoryCategories: ["pet", "nature"],
        isFree: false
    )
}
