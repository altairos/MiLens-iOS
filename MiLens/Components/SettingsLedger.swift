//  SettingsLedger —— 「我的」页 Ledger 账本式设计语言组件。
//
//  对照 Figma「07·我的」(#140:415)：
//  - 珊瑚色竖线 rail（3pt）作为分组锚点
//  - Fraunces Bold 编号（01/02/03/04）标识行序
//  - 虚线引导线（dotted leader）连接标签与尾部值/控件
//  - 暖黑 Pro 卡 + 隐私徽章卡为专用表面
//
//  仅负责排版与交互表面，不持有业务状态。页面通过这些组件共享
//  「编号、虚线引导、单一主动作」这套视觉语法（后续页面可复用）。
//  对照 UI-DESIGN.md 设计 token；颜色见 Color+Theme.swift。

import SwiftUI

// MARK: - 分组小标题

/// 分组标题：12pt Medium，milensTextSecondary，左对齐（非 uppercase）。
/// 对照 Figma #140:425/#140:433/#151:384「隐私与数据 / 偏好设置 / 支持与版本」。
struct SettingsSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.milensTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 虚线引导线

/// 弹性虚线引导线：连接行内标签与尾部控件/值。
/// 对照 Figma EL-86376389 / EL-61818d3d（strokeDashes [1,5]，opacity 0.72/0.64）。
/// 装饰元素，对 VoiceOver 隐藏。
struct DottedLeader: View {
    var body: some View {
        Line()
            .stroke(
                style: StrokeStyle(
                    lineWidth: 1,
                    dash: [1, 5]
                )
            )
            .foregroundStyle(Color.milensTextSecondary.opacity(0.68))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// 水平直线形状（供 DottedLeader 描边）。
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return p
    }
}

// MARK: - 分组容器

/// Ledger 分组容器：左侧珊瑚 rail（3pt）+ 右侧内容列。
/// 对照 Figma「Preference Ledger Rail / Support Ledger Rail」#149:385 / #151:386。
///
/// 行间分隔由内部行自管理（虚线引导线即视觉分隔，不再加实体 divider）。
/// rail 高度随内容自适应；圆角与 wash 由调用方按需叠加（见 PrivacyBadgeCard）。
struct LedgerSection<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            // 左侧珊瑚竖线 rail（3pt）
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3)
            // 右侧内容
            VStack(spacing: 0) {
                content()
            }
        }
    }
}

// MARK: - 通用行

/// Ledger 通用行：编号 + 标签 + 虚线引导线 + 尾部内容。
/// 对照 Figma「Preference Row」layout_ff6e81d1（row, padding 0 6 0 16, gap 8, 342×54）。
///
/// - Parameters:
///   - index: 编号文案（"01".."04"），Fraunces Bold 12 珊瑚色
///   - label: 行标签，Regular 15 主文色
///   - trailing: 尾部内容（Toggle / Disclosure 值 + chevron / 自定义）
struct LedgerRow<Trailing: View>: View {
    let index: String
    let label: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(index)
                .font(.custom("Fraunces-Bold", size: 12))
                .foregroundStyle(Color.milensActionPrimary)

            Text(label)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.milensTextPrimary)
                .fixedSize(horizontal: true, vertical: false)

            DottedLeader()

            trailing()
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

/// 带尾标的 Ledger 展示行（纯展示，不含点击逻辑）。
/// 对照 Figma「Support / Help」「Support / About」（尾部 chevron / 「→」）。
/// 调用方按需用 NavigationLink / Button / Link 包裹以处理导航。
struct LedgerDisclosureRow: View {
    let index: String
    let label: String
    var trailingText: String? = nil

    var body: some View {
        LedgerRow(index: index, label: label) {
            HStack(spacing: 6) {
                if let trailingText {
                    Text(trailingText)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.milensTextSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.milensTextSecondary)
            }
        }
    }
}

// MARK: - Pro 暖黑卡片

/// Pro 卡片：暖黑底 #14110F，4px 圆角，Fraunces 标题。
/// 对照 Figma #140:419「MiLens Pro」（342×154，#14110F，Radius 4）。
///
/// - 未解锁（引导态）：品牌名 + 标语「让长期档案更完整」+ 辅文 + CTA「了解 Pro 版 →」
/// - 已解锁（激活态）：品牌名 + 成功徽章 + 标语「全部功能已解锁」+ CTA「管理订阅 →」
///
/// 深色模式：#14110F 与页面底 #161311 对比不足，切换为更亮的暖灰 #2A2520 保持浮起感。
struct ProHeroCard: View {
    /// 是否已激活 Pro；切换文案与成功徽章。
    var isPro: Bool = false
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            cardContent
        }
        .buttonStyle(.plain)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("MiLens Pro")
                        .font(.custom("Fraunces-Semibold", size: 19))
                        .foregroundStyle(Color.white)
                    // 已激活：成功色徽章做视觉确认
                    if isPro {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.milensSuccess)
                    }
                }

                Text(String(localized: headlineKey))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.top, 11)

                Text(String(localized: bodyKey))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.milensProBody)
                    .padding(.top, 12)
            }
            .padding(.leading, 20)
            .padding(.top, 18)

            HStack {
                Spacer()
                Text(String(localized: ctaKey))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white)
            }
            .padding(.trailing, 25)
            .padding(.bottom, 21)
            .padding(.top, 29)

            // 底部珊瑚 accent rule（对照 Pro Accent Rule #145:406，卡片底部右侧）
            HStack {
                Spacer()
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 104, height: 1)
            }
            .padding(.trailing, 0)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    // MARK: 文案选择（按激活状态切换）

    private var headlineKey: String.LocalizationValue {
        isPro ? "settings.pro.card.headline.active" : "settings.pro.card.headline"
    }

    private var bodyKey: String.LocalizationValue {
        isPro ? "settings.pro.card.body.active" : "settings.pro.card.body"
    }

    private var ctaKey: String.LocalizationValue {
        isPro ? "settings.pro.card.cta.active" : "settings.pro.card.cta"
    }

    /// 深色模式下提亮暖黑，避免与页面底色融为一体。
    private var cardBackground: Color {
        Color.milensProCardDark
    }
}

// MARK: - 隐私徽章状态卡

/// 隐私状态卡：浅粉 wash + 珊瑚 rail + 珊瑚圆形徽章（含锁图标）。
/// 对照 Figma #140:426「Privacy Status」+#145:407「Privacy Rail Wash」+#140:427 徽章。
///
/// wash 宽 16pt 贴左侧，rail 3pt 覆盖其上；徽章 40pt 居中放锁图标。
struct PrivacyBadgeCard: View {

    var body: some View {
        HStack(spacing: 0) {
                // 左侧 wash + rail（16pt 宽，对照 Privacy Rail Wash #145:407）
                ZStack {
                    Rectangle()
                        .fill(Color.milensAccentWash)
                    Rectangle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 3)
                        .frame(maxHeight: .infinity, alignment: .leading)
                }
                .frame(width: 16)

                // 珊瑚圆形徽章（40pt，紧跟 wash 右缘）
                Circle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.white)
                    )
                    .padding(.leading, 16)

                // 右侧文案
                VStack(alignment: .leading, spacing: 7) {
                    Text(String(localized: "settings.privacy.badge.title"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.milensTextPrimary)
                    Text(String(localized: "settings.privacy.badge.body"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.milensTextSecondary)
                }
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.trailing, 16)
            }
            .frame(minHeight: 80)
            .background(Color.milensCard)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(height: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(height: 0.5)
            }
            .contentShape(Rectangle())
    }
}

// MARK: - 页脚

/// 居中页脚：无联网功能 · 无信息收集 · 无需注册账号。
/// 对照 Figma #140:441（11pt #A89F97 居中）。
struct SettingsFooter: View {
    var body: some View {
        Text(String(localized: "settings.footer.privacy"))
            .font(.system(size: 11))
            .foregroundStyle(Color.milensTextTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.lg)
    }
}

// MARK: - Preview

#Preview("Ledger 组件 · 浅色") {
    ScrollView {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SettingsSectionLabel(title: "偏好设置")

            LedgerSection {
                LedgerRow(index: "01", label: "通知") {
                    Toggle("", isOn: .constant(true))
                        .labelsHidden()
                        .tint(Color.milensActionPrimary)
                }
                LedgerRow(index: "02", label: "外观") {
                    HStack(spacing: 6) {
                        Text("跟随系统")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.milensTextSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.milensTextSecondary)
                    }
                }
            }

            SettingsSectionLabel(title: "支持与版本")

            LedgerSection {
                LedgerDisclosureRow(index: "03", label: "帮助与支持")
                LedgerDisclosureRow(index: "04", label: "关于 MiLens", trailingText: "V1.0")
            }

            ProHeroCard {}

            ProHeroCard(isPro: true) {}

            PrivacyBadgeCard()

            SettingsFooter()
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, Spacing.lg)
    }
    .background(Color.milensBackground)
    .preferredColorScheme(.light)
}

#Preview("Ledger 组件 · 深色") {
    ScrollView {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            ProHeroCard {}
            ProHeroCard(isPro: true) {}
            PrivacyBadgeCard {}
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, Spacing.lg)
    }
    .background(Color.milensBackground)
    .preferredColorScheme(.dark)
}
