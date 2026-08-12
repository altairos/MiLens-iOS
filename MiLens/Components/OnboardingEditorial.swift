//  OnboardingEditorial —— 首次启动「First Archive」引导流程共享编辑式原子组件。
//  对照 Figma「相册扫描与配额付费墙原型」#47:2 First Launch 画板：
//  - FocusDialButton：机械拨盘式主 CTA（铜红 surface + 铜色拨盘 + 精密刻度弧 + glyph + 文字）
//  - ContactProofButton：相册入口次级 CTA（浅粉 wash 底 + 文字 + 描边箭头框）
//  - EditorialSection：overline caption + 文楷 Section 标题 + 可选正文（统一各画板顶部排版）
//  - EditorialCard：左 3pt 竖 rail + 描边卡片容器
//  - RegisterMark：短线（lead 段 + tail 段）+ 右端 8pt 圆点端点
//  - WaypointRow：珊瑚点 + Value 文字（横向并列标记）
//  色值全部走语义 token，不硬编码。专用表面色（milensDialSurface/milensDarkroomText
//  /milensDarkroomBorder）沿用暗房定义，注释标 ui-token:ok。

import SwiftUI

// MARK: - FocusDialButton

/// 机械拨盘式主操作按钮（对照 Figma Action/Focus Dial 组件集 89:2 / 89:35）。
///
/// 视觉结构：左侧大块铜红 surface + 文字标签；右侧 54pt 铜色拨盘圆 + 内圆描边 +
/// 三段精密刻度弧（不同 opacity）+ 中央 glyph（SF Symbol）。disabled 态整体降透明度。
///
/// ui-token:ok —— 本组件直接复用暗房/编辑式专用表面 token（milensActionPrimary 作铜红
/// surface、milensDialSurface 作拨盘、milensDarkroomText 作浅文字），这些 token 已在
/// Color+Theme.swift 集中定义并注释，非视图内硬编码。
struct FocusDialButton: View {
    let label: String
    var systemImage: String = "plus"
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // 左侧文字标签区（铜红 surface）
                Text(label)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.milensDarkroomText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 18)

                // 右侧机械拨盘
                dial
                    .frame(width: 54, height: 54)
                    .padding(.trailing, 2)
            }
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.milensActionPrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.milensDarkroomText.opacity(0.25), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.36)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    /// 机械拨盘：铜色圆底 + 内圆描边 + 三段刻度弧 + 中央 glyph。
    private var dial: some View {
        ZStack {
            // 拨盘圆底（铜色）
            Circle()
                .fill(Color.milensDialSurface)
            // 内圆描边
            Circle()
                .stroke(Color.milensDarkroomText.opacity(0.5), lineWidth: 1)
                .padding(5)
            // 三段精密刻度弧（不同 opacity，对照 Figma precision arc top/right/left）
            precisionArc(start: -90, end: -50, opacity: 1.0)
            precisionArc(start: 35, end: 75, opacity: 0.72)
            precisionArc(start: 165, end: 200, opacity: 0.42)
            // 中央 glyph
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.milensDarkroomText)
        }
    }

    /// 一段刻度弧（基于角度区间，stroke 一段圆环）。
    private func precisionArc(start: Double, end: Double, opacity: Double) -> some View {
        Circle()
            .trim(from: start / 360, to: end / 360)
            .stroke(Color.milensDarkroomText.opacity(opacity),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            .padding(3)
            .rotationEffect(.degrees(0))
    }
}

// MARK: - ContactProofButton

/// 相册入口次级主操作（对照 Figma Action/Contact Proof 组件集 9:7 / 9:17）。
///
/// 视觉：浅粉 wash 底 + 左文字（milensActionPrimary Bold）+ 右描边箭头框。
/// disabled 态整体降透明度（对照 #117:174 / #133:30 等进行中态）。
struct ContactProofButton: View {
    let label: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.milensActionPrimary)
                    .lineLimit(1)
                Spacer()
                arrowBox
            }
            .padding(.leading, 18)
            .padding(.trailing, 5)
            .frame(height: 54)
            .background(Color.milensAccentWash)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var arrowBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.milensActionPrimary, lineWidth: 1)
                .frame(width: 42, height: 32)
            Text("\u{2192}")
                .font(.system(size: 20))
                .foregroundStyle(Color.milensActionPrimary)
        }
    }
}

// MARK: - EditorialSection

/// 编辑式标题区：overline caption + 文楷 Section 标题 + 可选正文。
/// 对照各画板顶部排版（#47:7 / #47:10 / #47:8 等）。
struct EditorialSection: View {
    let overline: String
    let title: String
    var body: String? = nil
    /// 标题右上角的辅助元素（如特征注册页的「12 / 15」大数字）。
    var trailing: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(overline)
                .font(.system(size: 12))
                .tracking(0.1)
                .foregroundStyle(Color.milensTextSecondary)
                .textCase(.uppercase)

            HStack(alignment: .top, spacing: 8) {
                Text(title)
                    .font(.editorialSection)
                    .foregroundStyle(Color.milensTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let trailing { trailing }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let body {
                Text(body)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.milensTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - EditorialCard

/// 左 3pt 竖 rail + 描边卡片容器。
/// 承载 On Device / Rules / Empty Identity / Guidance / Feature Seal / Viewfinder 等卡片。
struct EditorialCard<Content: View>: View {
    var cornerRadius: CGFloat = Radius.large
    /// 左侧竖 rail 色（默认铜色 #7C3F30 = milensDialSurface，对照 Figma Spine #94:28）
    var railColor: Color = Color.milensDialSurface
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(railColor)
                .frame(width: 2)
            content()
        }
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - RegisterMark

/// 短线（lead 段 + tail 段）+ 右端 8pt 圆点端点。
/// 对照各画板底部 "Register" 标记（#94:36/#94:37/#94:38 等）。
///
/// Figma 色值映射（ui-token:ok）：
/// - lead 短段：#E5DFD8 = milensBorder（浅灰，对照 #94:36 Register / Lead）
/// - tail 长段：#7C3F30 = milensDialSurface（铜色深，对照 #94:37 Register / Tail）
/// - marker 端点：#BC4727 = milensActionPrimary（珊瑚，对照 #94:38 Register / Marker）
struct RegisterMark: View {
    var leadWidth: CGFloat = 46
    var tailWidth: CGFloat = 228
    /// 端点圆点色（默认珊瑚；lead/tail 色固定走 token 对齐 Figma）
    var markerColor: Color = Color.milensActionPrimary

    var body: some View {
        HStack(spacing: 0) {
            // lead 短段（浅灰）
            Rectangle()
                .fill(Color.milensBorder)
                .frame(width: leadWidth, height: 2)
            // tail 长段（铜色深）
            Rectangle()
                .fill(Color.milensDialSurface)
                .frame(width: tailWidth, height: 2)
            // marker 端点（珊瑚）
            Circle()
                .fill(markerColor)
                .frame(width: 8, height: 8)
                .padding(.leading, -2)
            Spacer(minLength: 0)
        }
        .frame(height: 8)
    }
}

// MARK: - WaypointRow

/// 横向并列的珊瑚点 + Value 文字标记（对照 #94:40-#94:45 本机整理/由你确认/随时可删）。
struct WaypointRow: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                waypoint(item)
            }
        }
    }

    private func waypoint(_ text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(Color.milensActionPrimary)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.milensTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
