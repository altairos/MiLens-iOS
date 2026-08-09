//  语义颜色 token —— 包装 Asset Catalog 颜色集（Any/Dark Appearance 自动适配）。
//  色值规范见 UI-DESIGN.md §1.2（中性画廊 + 暖色点睛，暖黑深色）。
//  命名统一 milens 前缀，避免与 SwiftUI 内置 Color（.primary/.secondary 等）冲突。

import SwiftUI

extension Color {
    // MARK: - Editorial palette（内联视觉稿）

    /// 奶油纸张底色、深棕黑文字和铜橙强调色。
    static let milensPaper = Color(red: 0.955, green: 0.934, blue: 0.895)
    static let milensInk = Color(red: 0.105, green: 0.085, blue: 0.072)
    static let milensCopper = Color(red: 0.690, green: 0.255, blue: 0.145)
    static let milensStudioBackground = Color(red: 0.085, green: 0.070, blue: 0.062)
    static let milensStudioSurface = Color(red: 0.135, green: 0.115, blue: 0.100)

    // MARK: - Surface 表面

    /// 页面背景（浅：暖白 #FAF8F5 / 深：暖黑 #161311）
    static let milensBackground = Color("SurfaceBackground")
    /// 卡片背景（浅：纯白 / 深：暖深灰 #221E1A）
    static let milensCard = Color("SurfaceCard")
    /// 悬浮元素背景（浅：纯白 / 深：#2C2722）—— FAB/弹层
    static let milensElevated = Color("SurfaceElevated")
    /// 分组/输入框背景（浅：#F2EFEA / 深：#1C1916）
    static let milensGrouped = Color("SurfaceGrouped")

    // MARK: - Text 文字

    /// 标题/正文主色（浅：#1F1B18 / 深：#F2EBE3）
    static let milensTextPrimary = Color("TextPrimary")
    /// 说明/副标题（浅：#6B625B / 深：#B5A89C）
    static let milensTextSecondary = Color("TextSecondary")
    /// 占位/时间戳/最弱信息（浅：#A89F97 / 深：#7A6F64）
    static let milensTextTertiary = Color("TextTertiary")
    /// 品牌色按钮上的文字（纯白）
    static let milensTextOnAccent = Color("TextOnAccent")
    /// 高对比主动作文字（浅色白字 / 深色暖黑字）
    static let milensTextOnActionPrimary = Color("TextOnActionPrimary")

    // MARK: - Accent 品牌与强调

    /// 品牌主色（浅：#FD8663 / 深：#E8845F）—— 只用于 CTA/选中态/品牌瞬间，禁止铺底
    static let milensPrimary = Color("AccentColor")
    /// 高对比主动作底色（浅：#BC4727 / 深：#E8845F）
    static let milensActionPrimary = Color("ActionPrimary")
    /// 品牌色浅底（浅：#FDEEE6 / 深：#3A241C）—— 选中卡片底/标签底
    static let milensAccentSoft = Color("AccentSoft")
    /// 品牌渐变终点（浅：#FE8764 / 深：#D9704A）
    static let milensAccentGradientEnd = Color("AccentGradientEnd")

    // MARK: - Functional 功能色

    /// 成功（浅：#2F7D57 / 深：#72C998）
    static let milensSuccess = Color("Success")
    /// 警告（浅：#9A5B00 / 深：#F0B85A）
    static let milensWarning = Color("Warning")
    /// 删除/错误（浅：#B33A36 / 深：#EF7D76）
    static let milensDanger = Color("Danger")

    // MARK: - Pet 宠物主题

    /// 猫咪主题色（同品牌 #FD8663 / 深：#E8845F）
    static let milensCatAccent = Color("CatAccent")
    /// 狗狗主题色（浅：#57A5E3 / 深：#5B96D0）
    static let milensDogAccent = Color("DogAccent")

    // MARK: - Separator 分隔

    /// 分隔线（浅：#ECE7E1 / 深：#2E2823）
    static let milensSeparator = Color("Separator")
    /// 卡片描边/输入框边（浅：#E5DFD8 / 深：#383129）
    static let milensBorder = Color("Border")
}
