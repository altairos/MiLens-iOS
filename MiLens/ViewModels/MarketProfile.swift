//  MarketProfile —— 区域差异化配置模型
//
//  把"按市场/地区"的差异化决策收敛为单一入口，与语言层（i18n / .xcstrings）分离。
//  语言翻译由 String Catalog 管理；MarketProfile 管理的是审美、隐私叙事强度、
//  法律区域等无法靠文本翻译表达的差异维度。
//
//  当前已落地的维度（从 Typography.usesWenKai 与 Localization-Plan §4.3/§4.5 提取）：
//  - usesWenKaiDisplay：仅 zh-Hans 用霞鹜文楷（字体层差异，源于语言+script）
//  - privacyNarrativeStrength：DE/FR 为 .strong（GDPR 区需更显式隐私措辞）
//
//  未来扩展方向（待代码层出现承载点后再落地，避免过度设计）：
//  - 审美方向（日韩 cute / 欧美 documentary）—— 影响素材选片
//  - 法律区域（GDPR / PIPA / 个保法）—— 影响隐私页措辞与提示
//  - 价格敏感度（德区强调节省比例）—— 影响付费墙文案
//
//  DESIGN.md §4：纯决策逻辑，无 IO/无 SwiftUI 依赖，可单测。
//  详见 docs/Localization-Plan.md §4.8。

import Foundation

struct MarketProfile: Equatable, Sendable {

    /// 市场/地区标识，用于日志、调试与资产命名。
    let market: Market

    /// 是否使用霞鹜文楷作为 display 字体。
    /// 文楷子集仅覆盖 GB2312 简体字符，zh-Hant/ja/ko 使用会缺字（豆腐块），
    /// 必须回退系统衬线字体。判断依据是语言+script，与地区无关。
    /// 见 Typography.swift displayFont 与 docs/Localization-Plan.md §4.8 字体策略。
    let usesWenKaiDisplay: Bool

    /// 隐私叙事强度。
    /// DE/FR 等 GDPR 区为 .strong，需要更显式的本地化隐私措辞
    /// （如德语版描述建议专门加一段，见 Localization-Plan §4.3）。
    let privacyNarrativeStrength: PrivacyStrength

    // MARK: - 解析

    /// 从 Locale 解析出市场差异化配置。
    ///
    /// 字体差异基于**语言+script**（zh+Hans）；隐私叙事强度基于**地区**（GDPR 区）。
    /// 两者维度独立，因此 Profile 同时需要 locale 的语言与地区信息。
    ///
    /// - Parameter locale: 用户当前 locale（测试传固定 locale 保证可测）。
    /// - Returns: 对应的市场配置；无法识别的地区返回 `.other` 市场 + 默认差异值。
    static func resolve(from locale: Locale) -> MarketProfile {
        let market = Market.from(regionCode: locale.region?.identifier)
        let lang = locale.language
        let usesWenKai = lang.languageCode?.identifier == "zh" && lang.script?.identifier == "Hans"
        let privacy: PrivacyStrength = (market == .germany || market == .france) ? .strong : .standard
        return MarketProfile(
            market: market,
            usesWenKaiDisplay: usesWenKai,
            privacyNarrativeStrength: privacy
        )
    }

    /// 当前环境的 market profile（基于 `Locale.current` 解析）。
    ///
    /// UI 层应优先从 SwiftUI Environment 读取（测试可注入固定 profile）；
    /// 此属性仅供 App 组合根初始化 Environment 用，不在业务逻辑中直接调用。
    static var current: MarketProfile {
        resolve(from: .current)
    }
}

// MARK: - 市场枚举

extension MarketProfile {

    /// 主要发布市场，按地理区域聚合（与语言不完全对齐）。
    /// 例如 en 覆盖美/英/澳/加，但都归入 `.english` 市场。
    enum Market: String, Sendable, CaseIterable, Equatable {
        case china
        case taiwan
        case japan
        case korea
        case germany
        case france
        case english
        case other

        /// 从 ISO 地区码映射到市场。
        /// 德语区（DE/AT/CH）归 `.germany`；英语区主要国家归 `.english`。
        static func from(regionCode: String?) -> Market {
            switch regionCode?.uppercased() {
            case "CN":                     return .china
            case "TW", "HK":               return .taiwan
            case "JP":                     return .japan
            case "KR":                     return .korea
            case "DE", "AT", "CH":         return .germany
            case "FR":                     return .france
            case "US", "GB", "AU", "NZ",
                 "CA", "IE", "SG":         return .english
            default:                       return .other
            }
        }
    }
}

// MARK: - 隐私叙事强度

extension MarketProfile {

    /// 隐私叙事的措辞强度。
    /// `.strong` 用于 GDPR 发源地/高敏感市场（德/法），需在描述、付费墙、
    /// 隐私政策中更显式地陈述"本地处理 / 无云端 / 无上传"。
    enum PrivacyStrength: String, Sendable, Equatable {
        case standard
        case strong

        var isStrong: Bool { self == .strong }
    }
}
