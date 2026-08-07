//  主题尺寸 token —— 翻译自源端 theme/AppTheme.ets（Sp / R / Sz / Motion 类）
//  颜色 token 见 Color+Theme.swift（Asset Catalog 语义色）。
//  随迁移进度按需补全；当前仅含 P1.1 TabView 壳所需。

import CoreGraphics

/// 间距（源端 `Sp`）
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    /// 页面统一左右内边距
    static let pagePad: CGFloat = 20
}

/// 圆角（源端 `R`）
enum Radius {
    static let card: CGFloat = 16
    static let button: CGFloat = 12
    static let buttonLarge: CGFloat = 24
    static let chip: CGFloat = 16
    static let thumb: CGFloat = 12
}

/// 尺寸（源端 `Sz`，按需补全）
enum Sizing {
    static let iconSm: CGFloat = 16
    static let iconMd: CGFloat = 20
    static let iconLg: CGFloat = 24
    /// 触控目标最小尺寸（iOS HIG ≥ 44pt）
    static let touchTarget: CGFloat = 44
    /// 标准底部导航栏高度
    static let tabBarHeight: CGFloat = 56
}

/// 动效 token（源端 `Motion`）
enum Motion {
    static let durationFast: Double = 0.15
    static let durationNormal: Double = 0.25
    static let durationSlow: Double = 0.4
}
