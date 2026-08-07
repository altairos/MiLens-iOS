//  字体层级 —— UI-DESIGN.md §2.2。
//
//  当前用系统字体 + design 修饰（serif/rounded）定义层级语义，自动响应 Dynamic Type。
//  自定义字体（霞鹜文楷 LXGW WenKai + Fraunces，均 SIL OFL）待阶段 A 第 4 步
//  子集化引入后，将 display* 切换为 `.custom(_:size:relativeTo:)`。
//  切换点见各 display 属性注释。

import SwiftUI

extension Font {
    // MARK: - Display（情感标题，衬线 design）
    //
    // 字体到位后的切换示例：
    //   static let displayLarge = Font.custom("LXGWWenKai-Bold", size: 34, relativeTo: .largeTitle)
    //   static let displayLargeEN = Font.custom("Fraunces-Bold", size: 34, relativeTo: .largeTitle)

    /// 首页问候（「晚上好」）、档案名字。`.largeTitle` 级别，衬线粗体。
    static let displayLarge = Font.system(.largeTitle, design: .serif).bold()
    /// 区块标题（「它的故事」「一年前的今天」）。`.title2` 级别，衬线半粗。
    static let displayMedium = Font.system(.title2, design: .serif).weight(.semibold)

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
