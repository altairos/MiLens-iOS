//  字体层级 —— UI-DESIGN.md §2.2。
//
//  自定义字体均采用 SIL OFL 1.1，按语言/地区子集化嵌入：
//  - 简中：霞鹜文楷 GB；繁中台湾：霞鹜文楷 TC；繁中香港：芫茜雅楷。
//  - 日文：Klee One；英文/法文/德文：Fraunces（Latin Extended）。
//  - CJK 标题使用 Regular；Fraunces 使用 Bold/Semibold 两个静态字重。
//  - 编辑式衬线 overline：Jacques Francois Regular（PostScript: JacquesFrancois-Regular），
//    10pt 小标（「LIFE 02 · …」「ARCHIVE OUTPUT」），调用方配 .tracking(0.4)。
//  - 正文/UI/数字：系统字体（SF Pro + PingFang），零体积成本，保持原生感。
//
//  Figma UI 文本样式（MiLens/UI/Title、/Body Strong、/Overline、/Metadata）标注字体为
//  「Noto Sans SC Medium」，iOS 不打包 Noto Sans SC，统一回退系统字体（简中 PingFang /
//  拉丁 SF Pro），分别对应 uiTitle / uiBodyStrong / editorialOverline / editorialMetadata。
//  详见 UI-DESIGN.md §4.1「Figma UI 文本样式 → iOS 字体映射（已知替换）」。
//
//  SwiftUI `.custom` 不自动按字符切栈；标题字体由 MarketProfile 选择。
//
//  字体体积见 Resources/Fonts/README.md（合计 ~3.37 MB）。

import SwiftUI
import UIKit

extension Font {
    // MARK: - 语言感知 display 字体

    /// 标题字体族按语言+script 选择；正文/UI 仍走系统字体 token。
    /// 这里读全局 current——View 层如需按注入的 profile 选择字体，可用
    /// `@Environment(\.marketProfile)` 自行判断。
    /// 见 MiLens/ViewModels/MarketProfile.swift 与 docs/Localization-Plan.md §4.8。
    private static var displayFontFamily: MarketProfile.DisplayFontFamily {
        MarketProfile.current.displayFontFamily
    }

    /// 标题使用 MarketProfile 选择的区域字体；未知语言回退系统衬线。
    private static func displayFont(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        switch displayFontFamily {
        case .wenKaiGB:
            return Font.custom("LXGWWenKai-Regular", size: size, relativeTo: style)
        case .wenKaiTC:
            return Font.custom("LXGWWenKaiTC-Regular", size: size, relativeTo: style)
        case .jyunsaiKaai:
            return Font.custom("JyunsaiKaai", size: size, relativeTo: style)
        case .kleeOne:
            return Font.custom("KleeOne-Regular", size: size, relativeTo: style)
        case .fraunces:
            let postScriptName = size >= 32 ? "Fraunces-Bold" : "Fraunces-Semibold"
            return Font.custom(postScriptName, size: size, relativeTo: style)
        case .systemSerif:
            return Font.system(style, design: .serif)
        }
    }

    // MARK: - Display（按语言/地区选择标题字体）

    /// 首页问候（「晚上好」）、档案名字。`.largeTitle` 级别。
    static let displayLarge = displayFont(34, relativeTo: .largeTitle)
    /// 区块标题（「它的故事」「一年前的今天」）。`.title2` 级别。
    static let displayMedium = displayFont(24, relativeTo: .title2)

    /// 参考视觉稿首页 Hero 的杂志式大标题。
    static let editorialHero = displayFont(40, relativeTo: .largeTitle)
    /// 编辑式分节标题、宠物名字和档案故事标题。
    static let editorialSection = displayFont(28, relativeTo: .title2)
    /// 编辑式月份/统计数字。
    static let editorialNumber = displayFont(34, relativeTo: .title)

    // MARK: - Display 英文（Fraunces，纯英文大标题专用）

    /// 英文大标题（品牌名「MiLens」、英文标语）。`.largeTitle` 级别，Bold。
    static let displayLargeEN = Font.custom("Fraunces-Bold", size: 34, relativeTo: .largeTitle)
    /// 英文次级标题。`.title2` 级别，Semibold。
    static let displayMediumEN = Font.custom("Fraunces-Semibold", size: 24, relativeTo: .title2)

    // MARK: - Standard（系统原生感）

    /// 导航栏标题/卡片标题。`.title3` 级别，半粗。
    static let titleStandard = Font.system(.title3).weight(.semibold)
    /// 正文。`.body` 级别。
    static let bodyPrimary = Font.body
    /// 说明文字。`.subheadline` 级别。
    static let bodySecondary = Font.subheadline
    /// 时间戳/辅助信息。`.caption` 级别。
    static let caption = Font.caption
    /// 按钮文字。`.body` 级别，半粗。
    static let buttonLabel = Font.body.weight(.semibold)

    // MARK: - Number（数字/统计，圆体）

    /// 统计数字（「3280」「3岁2个月」）。`.title2` 级别，圆体粗体。
    static let numberStat = Font.system(.title2, design: .rounded).bold()

    // MARK: - Workshop 编辑式小标（对照 Figma `15 · Image Workshop`）

    /// 系统字体 + 固定字号 + Dynamic Type 缩放参照。
    /// Font.system 无 relativeTo: 重载（App target 首次编译暴露），
    /// 用 UIFontMetrics 等价实现 custom(_:size:relativeTo:) 的缩放语义。
    private static func scaledSystemFont(
        size: CGFloat, weight: UIFont.Weight = .regular, relativeTo style: UIFont.TextStyle
    ) -> Font {
        Font(UIFontMetrics(forTextStyle: style)
            .scaledFont(for: UIFont.systemFont(ofSize: size, weight: weight)))
    }

    /// Overline 小标（「CREATION DARKROOM」「READY TO KEEP」）。
    /// Figma `MiLens/UI/Overline`：10pt Medium + letterSpacing 0.04em。
    /// 文字间距通过调用方 `.tracking(0.4)` 补足（SwiftUI tracking 单位为 pt）。
    static let editorialOverline = scaledSystemFont(size: 10, weight: .medium, relativeTo: .caption1)

    /// Metadata 元信息（「图纸 · 色号 · 用量」「2021.04.18」）。
    /// Figma `MiLens/UI/Metadata`：11pt Regular。
    static let editorialMetadata = scaledSystemFont(size: 11, relativeTo: .caption1)

    /// 项目编号 / 步骤编号（「01」「02」「03」）。
    /// Figma `MiLens/Number/Index`：Fraunces-Bold 12pt。
    static let editorialNumberIndex = Font.custom("Fraunces-Bold", size: 12, relativeTo: .caption)

    /// UI Title（「成品预览」「拼豆工作室」「选择两段时光」）。
    /// Figma `MiLens/UI/Title`：20pt Medium + letterSpacing -0.01em。
    static let uiTitle = scaledSystemFont(size: 20, weight: .medium, relativeTo: .title3)

    /// UI Body Strong（「从生命档案选择」「窗边观察员」）。
    /// Figma `MiLens/UI/Body Strong`：15pt Medium。
    static let uiBodyStrong = scaledSystemFont(size: 15, weight: .medium, relativeTo: .body)
}
