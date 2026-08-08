//  字体层级 —— UI-DESIGN.md §2.2。
//
//  自定义字体（霞鹜文楷 LXGW WenKai + Fraunces，均 SIL OFL，子集化嵌入）。
//  - 中文 display：霞鹜文楷 Regular（PostScript: LXGWWenKai-Regular），仅引入 Regular
//    一个字重——楷书 Regular 已有足够分量感，display 大/中标题靠字号区分而非字重。
//  - 英文 display：Fraunces（衬线，Bold/Semibold 两个字重），供纯英文大标题/品牌名使用。
//  - 正文/UI/数字：系统字体（SF Pro + PingFang），零体积成本，保持原生感。
//
//  SwiftUI `.custom` 不自动按字符切栈：中文标题用 displayLarge（文楷），纯英文标题手动
//  用 displayLargeEN/displayMediumEN（Fraunces）。文楷自带基础拉丁可做回退。
//
//  字体体积见 Resources/Fonts/README.md（合计 ~3.31 MB）。

import SwiftUI

extension Font {
    // MARK: - Display 中文（霞鹜文楷 Regular）

    /// 首页问候（「晚上好」）、档案名字。`.largeTitle` 级别。
    static let displayLarge = Font.custom("LXGWWenKai-Regular", size: 34, relativeTo: .largeTitle)
    /// 区块标题（「它的故事」「一年前的今天」）。`.title2` 级别。
    static let displayMedium = Font.custom("LXGWWenKai-Regular", size: 24, relativeTo: .title2)

    /// 参考视觉稿首页 Hero 的杂志式大标题。
    static let editorialHero = Font.custom("LXGWWenKai-Regular", size: 40, relativeTo: .largeTitle)
    /// 编辑式分节标题、宠物名字和档案故事标题。
    static let editorialSection = Font.custom("LXGWWenKai-Regular", size: 28, relativeTo: .title2)
    /// 编辑式月份/统计数字。
    static let editorialNumber = Font.custom("LXGWWenKai-Regular", size: 34, relativeTo: .title)

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
}
