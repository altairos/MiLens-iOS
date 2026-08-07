//  语义颜色 token —— 包装 Asset Catalog 颜色集（Any/Dark Appearance 自动适配）。
//  色值翻译自源端 theme/themeColors.ets + theme/baseColors.ets。
//  随迁移进度按需补全；当前含 P1.1 所需核心语义色。

import SwiftUI

extension Color {
    /// 品牌主色（源端 primary，#FD8663 / dark #E07B5E）
    static let milensPrimary = Color("AccentColor")
    /// 页面背景（源端 bg）
    static let milensBackground = Color("SurfaceBackground")
    /// 卡片背景（源端 card）
    static let milensCard = Color("SurfaceCard")
    /// 标题文字（源端 title）
    static let milensTextPrimary = Color("TextPrimary")
    /// 正文/说明文字（源端 body / caption）
    static let milensTextSecondary = Color("TextSecondary")
}
