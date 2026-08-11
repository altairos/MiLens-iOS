//  主题尺寸/深度 token —— 对应 UI-DESIGN.md §3（间距/圆角/深度）与 §4（动效）。
//  颜色 token 见 Color+Theme.swift（Asset Catalog 语义色）。
//  字体 token 见 Typography.swift。

import CoreGraphics
import SwiftUI

/// 间距（UI-DESIGN.md §3.1）
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    /// 页面统一左右内边距（付费 App 更慷慨的留白）
    static let pagePad: CGFloat = 24
    /// 横屏/紧凑宽度的页面内边距
    static let pagePadCompact: CGFloat = 16
}

/// 圆角（UI-DESIGN.md §3.2，三档 + 向后兼容旧名）
enum Radius {
    /// chip / 小按钮 / tag
    static let small: CGFloat = 10
    /// 中等元素 / 输入框 / 次级卡片
    static let medium: CGFloat = 14
    /// 大卡片 / hero 照片 / 主卡片（画廊画框感）
    static let large: CGFloat = 20
    /// 缩略图
    static let thumb: CGFloat = 12

    // 向后兼容（P1.1 旧命名）—— 指向新三档
    static let card: CGFloat = large
    static let button: CGFloat = medium
    static let buttonLarge: CGFloat = large
    static let chip: CGFloat = small
}

/// 尺寸（UI-DESIGN.md §3，按需补全）
enum Sizing {
    static let iconSm: CGFloat = 16
    static let iconMd: CGFloat = 20
    static let iconLg: CGFloat = 24
    /// 触控目标最小尺寸（iOS HIG ≥ 44pt）
    static let touchTarget: CGFloat = 44
    /// Memory Orbit 底部导航浮层高度；单个按钮仍为 56pt。
    static let tabBarHeight: CGFloat = 70
}

/// 内容最大可读宽度（UI-DESIGN.md §5.1：正文 680 / 表单 620）。
/// 用于 Modal 表单限宽与长文居中，避免在 iPad/regular 宽度下全屏铺开（§8）。
enum ReadingWidth {
    /// 正文最大可读宽度。
    static let body: CGFloat = 680
    /// 设置/表单最大宽度。
    static let form: CGFloat = 620
}

/// 动效时长 token（UI-DESIGN.md §4）
enum Motion {
    /// 即时反馈：点击态、chip 切换
    static let durationFast: Double = 0.15
    /// 默认转场
    static let durationNormal: Double = 0.25
    /// hero、揭示
    static let durationSlow: Double = 0.4
}

/// 深度/阴影 token（UI-DESIGN.md §3.3）。
///
/// 设计纪律：极克制。默认**不用阴影**，改用表面色分层（Background → Card → Elevated）
/// 或 border（`Color.milensBorder`，0.5pt）。只有悬浮元素（FAB/吸底操作栏/弹层）才用阴影。
enum Elevation {
    /// 轻阴影：吸底操作栏等轻微悬浮。
    static let soft = ShadowSpec(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    /// 中阴影：FAB / 弹层。
    static let medium = ShadowSpec(color: .black.opacity(0.10), radius: 20, x: 0, y: 8)
    /// 品牌强调阴影：品牌色按钮（仅需要强调时）。
    static let accent = ShadowSpec(color: .milensPrimary.opacity(0.18), radius: 16, x: 0, y: 6)
}

/// 阴影规格描述，配合 SwiftUI `.shadow(color:radius:x:y:)` 使用。
struct ShadowSpec {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// 便捷修饰符：`.elevation(.soft)`
extension View {
    /// 应用 UI-DESIGN.md 定义的阴影 token。
    func elevation(_ spec: ShadowSpec) -> some View {
        shadow(color: spec.color, radius: spec.radius, x: spec.x, y: spec.y)
    }

    /// 限制 Modal/表单内容最大宽度并居中（UI-DESIGN.md §8：Modal 表单不全屏铺开）。
    ///
    /// 仅在 regular 水平 size class（iPad、iPhone 横屏大尺寸）生效；compact 环境
    /// 原样返回，不影响 iPhone 竖屏全宽布局。背景色用于填充限宽后两侧的留白，
    /// 避免露出系统 sheet 默认底色造成色差。
    ///
    /// - Parameters:
    ///   - maxWidth: 内容最大宽度（默认 `ReadingWidth.form` = 620）。
    ///   - background: 限宽区背景色（默认 `Color.milensBackground`）。
    func modalContentWidth(
        _ maxWidth: CGFloat = ReadingWidth.form,
        background: Color = .milensBackground
    ) -> some View {
        modifier(ModalContentWidthModifier(maxWidth: maxWidth, background: background))
    }
}

/// `modalContentWidth` 的实现：regular 宽度下限宽居中并铺背景。
private struct ModalContentWidthModifier: ViewModifier {
    let maxWidth: CGFloat
    let background: Color
    @Environment(\.horizontalSizeClass) private var hSizeClass

    func body(content: Content) -> some View {
        if hSizeClass == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
                .background(background)
        } else {
            content
        }
    }
}
