//  WidgetDesignSystem —— Widget Extension 专用设计系统。
//
//  Widget Extension 不能引用主 App 的 Color+Theme / Theme / Typography（这些文件
//  依赖 Asset Catalog colorset，不在 Widget target 的 sources 中）。本文件内联
//  对应的色值与排版 token，视觉语义对齐 UI-DESIGN.md §1.2 与 WidgetKit-Design.md §3。
//
//  设计语法（WidgetKit-Design.md §3.1 共同结构）：
//  - 系统负责外部 Widget 容器圆角；内部不再叠加一层通用大圆角卡片。
//  - 连续档案纸、照片出血、铜色登记轨、开放年轮、编辑式数字层级。
//  - 珊瑚橙只标记当下事件或可点击端点；深铜红用于登记线、时间刻度和数据编号。

import SwiftUI
import MiLensKit

// MARK: - 色彩 token（内联，对齐 Color+Theme.swift 的语义色）

enum WidgetPalette {
    // Surface
    static let paper = Color(red: 0.955, green: 0.934, blue: 0.895)       // 奶油纸张
    static let paperDark = Color(red: 0.135, green: 0.115, blue: 0.100)   // 暖黑纸面
    static let ink = Color(red: 0.105, green: 0.085, blue: 0.072)         // 深棕黑文字
    static let inkDark = Color(red: 0.945, green: 0.918, blue: 0.870)     // 浅暖文字（深色态）

    // 铜色登记轨
    static let copper = Color(red: 0.690, green: 0.255, blue: 0.145)      // 铜橙强调
    static let copperDeep = Color(red: 0.560, green: 0.200, blue: 0.110)  // 深铜红（登记线/刻度）

    // 辅助
    static let copperSoft = Color(red: 0.972, green: 0.910, blue: 0.870)  // 铜色浅底
    static let secondary = Color(red: 0.420, green: 0.385, blue: 0.355)   // 次级文字
    static let tertiary = Color(red: 0.660, green: 0.625, blue: 0.590)    // 辅助文字
    static let separator = Color(red: 0.860, green: 0.820, blue: 0.770)   // 分隔线
}

// MARK: - 字体 token（内联，对齐 Typography.swift 的层级）

enum WidgetFont {
    /// 编辑式大标题（倒计时数字）—— 系统圆体粗体。
    static let editorialLarge = Font.system(size: 44, weight: .bold, design: .rounded)
    /// 编辑式数字（统计值）。
    static let editorialNumber = Font.system(size: 28, weight: .bold, design: .rounded)
    /// 区块标题。
    static let sectionTitle = Font.system(size: 15, weight: .semibold)
    /// 正文（宠物名/标题）。
    static let bodyPrimary = Font.system(size: 14, weight: .medium)
    /// 说明文字。
    static let bodySecondary = Font.system(size: 13, weight: .regular)
    /// 微型登记头（顶部 MiLens/日期）。
    static let registryCaption = Font.system(size: 10, weight: .semibold)
    /// 时间戳/辅助信息。
    static let caption = Font.system(size: 11, weight: .regular)
}

// MARK: - 铜色登记轨

/// 铜色登记轨视图（WidgetKit-Design.md §3.1）。
///
/// 3pt 宽竖线 + 可选端点圆点，用于连接日期、标题与伙伴身份。
/// 从清晰端点向另一端可逐渐变淡（呼应 Memory Orbit），不画手绘线。
struct CopperRail: View {
    /// 轨道高度。
    var height: CGFloat = 28
    /// 端点圆点是否显示。
    var showsEndpoint: Bool = true
    /// 是否渐变（从下端清晰到上端变淡）。
    var fadeToTop: Bool = false

    var body: some View {
        GeometryReader { geo in
            let h = min(geo.size.height, height)
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(
                        fadeToTop
                        ? AnyShapeStyle(LinearGradient(
                            colors: [WidgetPalette.copperDeep.opacity(0.2), WidgetPalette.copperDeep],
                            startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(WidgetPalette.copperDeep)
                    )
                    .frame(width: 3, height: h)
                if showsEndpoint {
                    Circle()
                        .fill(WidgetPalette.copper)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 8, height: h, alignment: .bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: height)
    }
}

// MARK: - 照片出血 + 渐变遮罩

/// 照片出血视图（WidgetKit-Design.md §3.2 Small）。
///
/// 照片全出血铺底 + 底部渐变承载伙伴名与来源；顶部微型登记头。
struct PhotoBleedView: View {
    let image: UIImage?
    let topLabel: String          // 顶部「MiLens / 日期」
    let bottomLabel: String       // 底部「今天 · 小橘」
    let showsCopperLine: Bool

    var body: some View {
        ZStack(alignment: .top) {
            // 照片出血
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                WidgetPalette.paper.opacity(0.5)
            }

            // 底部渐变
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 70)
            }

            // 顶部微型登记头
            VStack {
                HStack {
                    Text(topLabel)
                        .font(WidgetFont.registryCaption)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                Spacer()
                // 底部标注
                HStack(alignment: .center, spacing: 5) {
                    if showsCopperLine {
                        Rectangle()
                            .fill(WidgetPalette.copper)
                            .frame(width: 14, height: 2)
                    }
                    Text(bottomLabel)
                        .font(WidgetFont.bodySecondary)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .widgetURL(deepLinkURL(for: image))
    }

    private func deepLinkURL(for image: UIImage?) -> URL? {
        // Small 照片点击回主 App 首页（具体 photoID 由 Widget 视图层在 widgetURL 设置）
        URL(string: "\(WidgetSharedConfig.deepLinkScheme)://home")
    }
}

// MARK: - 状态占位视图

/// empty 状态提示（WidgetKit-Design.md §4）。
struct WidgetEmptyState: View {
    let message: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "pawprint")
                .font(.system(size: 24))
                .foregroundStyle(WidgetPalette.copper.opacity(0.6))
            Text(message)
                .font(WidgetFont.bodySecondary)
                .foregroundStyle(WidgetPalette.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            WidgetPalette.paper
        }
    }
}

/// stale 状态提示（展示最后更新时间）。
struct WidgetStaleState: View {
    let lastUpdated: Date?
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 20))
                .foregroundStyle(WidgetPalette.tertiary)
            if let lastUpdated {
                Text("widget.stale.updated \(lastUpdated.formatted(.dateTime.month().day().hour().minute()))")
                    .font(WidgetFont.caption)
                    .foregroundStyle(WidgetPalette.tertiary)
            } else {
                Text("widget.stale.waitingSync")
                    .font(WidgetFont.caption)
                    .foregroundStyle(WidgetPalette.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            WidgetPalette.paper.opacity(0.6)
        }
    }
}

// MARK: - 深链工具

enum WidgetDeepLinkBuilder {
    static func photo(_ id: UUID) -> URL? {
        URL(string: "\(WidgetSharedConfig.deepLinkScheme)://photo/\(id.uuidString)")
    }
    static func pet(_ id: UUID) -> URL? {
        URL(string: "\(WidgetSharedConfig.deepLinkScheme)://pet/\(id.uuidString)")
    }
    static func timeline() -> URL? {
        URL(string: "\(WidgetSharedConfig.deepLinkScheme)://timeline")
    }
    static func bead(_ id: UUID) -> URL? {
        URL(string: "\(WidgetSharedConfig.deepLinkScheme)://bead/\(id.uuidString)")
    }

    /// 纪念日 Widget 点击深链：定位到该纪念日所属伙伴的档案页，并通过 query
    /// 携带 `day` 参数以备未来定位到具体事件。当前 App 端解析为 `petProfile`
    /// （与 `pet` 行为一致），`day` 参数为预留扩展。
    /// - Parameters:
    ///   - petID: 该纪念日的所属伙伴 ID
    ///   - dayID: 纪念日稳定 id（`UpcomingDayProjection.id`）
    static func anniversary(petID: UUID, dayID: String) -> URL? {
        URL(string: "\(WidgetSharedConfig.deepLinkScheme)://anniversary/\(petID.uuidString)?day=\(dayID)")
    }
}

// MARK: - 日历工具

/// Widget 侧使用的本地日历（跟随用户时区，与 MiLensKit 纯逻辑的 UTC 日历区分）。
/// Widget 渲染日期标签时使用用户本地日历更自然；倒计时计算经 WidgetSelectionLogic（UTC）保证一致性。
let widgetLocalCalendar: Calendar = .current
