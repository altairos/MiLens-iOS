//  ArchiveComponents —— Quiet Archive 共用视觉组件。
//
//  这些组件只负责排版与交互表面，不持有业务状态。页面通过它们共享
//  「记忆标记、日期层级、细分隔、单一主动作」这套视觉语法。
//
//  对照 Figma 5.6 可复用组件契约（UI-DESIGN.md §5.6）：
//  - ArchiveStatView（Data/Archive Stat [`295:587`]）：数值 + 单位 + 说明，开放报表排版
//  - ArchivePanel（Surface/Archive Panel [`296:629`]）：连续档案纸容器，嵌套 ArchiveStat
//  - IdentityStrip（Surface/Identity Strip [`299:615`]）：接触印 + 铜色登记轨 + 精确折角

import SwiftUI

struct ArchiveMarker: View {
    let label: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(Color.milensPrimary)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Color.milensSeparator)
                .frame(width: 24, height: 1)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.milensTextSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ArchiveSectionHeader: View {
    let title: String
    var supporting: String?

    init(title: String, supporting: String? = nil) {
        self.title = title
        self.supporting = supporting
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Text(title)
                .font(.titleStandard)
                .foregroundStyle(Color.milensTextPrimary)
            Spacer(minLength: Spacing.sm)
            if let supporting {
                Text(supporting)
                    .font(.caption)
                    .foregroundStyle(Color.milensTextTertiary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

struct ArchivePrimaryButton<Label: View>: View {
    let action: () -> Void
    /// 加载态：显示进度指示器并禁用交互，保留按钮宽高（UI-DESIGN.md §5.3.1：加载时保留宽度并显示进度）。
    var isLoading: Bool = false
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(Color.milensTextOnActionPrimary)
                } else {
                    label()
                }
            }
            .foregroundStyle(Color.milensTextOnActionPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Spacing.lg)
            .background(Color.milensActionPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

struct ArchiveDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color.milensSeparator)
            .frame(height: 1 / displayScale)
    }
}

/// 分段筛选胶囊（档案照片分类 / 时间线宠物筛选共用）。
/// 选中态用 ActionPrimary 实心底，未选中为卡片描边；可选计数徽标。
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var count: Int?
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.bodySecondary.weight(.semibold))
                if let count {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.milensTextOnActionPrimary.opacity(0.8) : Color.milensTextTertiary)
                }
            }
            .foregroundStyle(isSelected ? Color.milensTextOnActionPrimary : Color.milensTextSecondary)
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: Sizing.touchTarget)
            .background(isSelected ? Color.milensActionPrimary : Color.milensCard)
            .overlay {
                Capsule().stroke(Color.milensBorder, lineWidth: isSelected ? 0 : 0.5)
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeInOut(duration: Motion.durationFast), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - ArchiveStatView（Data/Archive Stat [`295:587`]）

/// 档案统计单项：大数值 + 小标签 + 可选单位。
/// 对照 Figma Data/Archive Stat：Value + Label 文本属性，宽度可按统计带等分。
/// 设计纪律：保持开放报表排版，不把每个读数包装成小卡（UI-DESIGN.md §5.6）。
struct ArchiveStatView: View {
    let value: String
    let label: String
    /// 可选单位后缀（如「张」「天」「条」），以较小字号内联显示。
    var unit: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.numberStat)
                    .foregroundStyle(Color.milensTextPrimary)
                if let unit {
                    Text(unit)
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }
            Text(label)
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ArchivePanel（Surface/Archive Panel [`296:629`]）

/// 连续档案纸容器：统计、记忆与近期照片属于同一张连续档案纸，
/// 不拆成同质圆角容器（UI-DESIGN.md §5.6）。
///
/// 视觉：大圆角（32pt）浮起面板，内部分隔依靠细线与留白而非堆叠卡片。
/// 调用方在 `content` 中用 ArchiveStatView/ArchiveDivider 等组装内容。
struct ArchivePanel<Content: View>: View {
    /// 面板圆角（iPhone 32pt / 可按场景调整）。
    var cornerRadius: CGFloat = 32
    /// 面板背景色（默认页面底色，与 Hero 底部渐变衔接）。
    var background: Color = .milensBackground
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - IdentityStrip（Surface/Identity Strip [`299:615`]）

/// Identity Strip 上下文语义：标识「来源照片」或「方案配方」。
enum IdentityStripContext {
    /// 来源照片（拼豆原图）。
    case source
    /// 方案配方（生成结果上下文）。
    case recipe
}

/// 接触印 + 铜色登记轨 + 精确折角的上下文条。
/// 对照 Figma Surface/Identity Strip：Context=Source/Recipe，
/// Label/Meta/Action 可覆盖，照片由实例覆盖。
///
/// 视觉结构：左侧 3pt 铜色登记轨 + 缩略图 + 右侧 Meta/Label/Action。
/// 不泛化为普通设置行（UI-DESIGN.md §5.6）。
struct IdentityStrip<Thumbnail: View>: View {
    /// 上下文语义（影响 Overline 文案默认值）。
    var context: IdentityStripContext = .source
    /// Overline 小标（如「原图」「方案」）。
    var meta: String
    /// 主标签。
    var label: String
    /// 右侧动作文案（如「更换」），nil 时不显示。
    var action: String? = nil
    /// 右侧动作回调。
    var onAction: (() -> Void)? = nil
    /// 缩略图内容（由实例覆盖）。
    @ViewBuilder var thumbnail: () -> Thumbnail

    var body: some View {
        HStack(spacing: 0) {
            // 铜色登记轨 3pt
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3)
                .padding(.vertical, 14)

            // 缩略图 72×72（接触印隐喻）
            thumbnail()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .clipped()
                .padding(.leading, 7)
                .padding(.vertical, 10)

            // 右侧文本列
            VStack(alignment: .leading, spacing: 2) {
                Text(meta)
                    .font(.editorialOverline)
                    .tracking(0.4)
                    .foregroundStyle(Color.milensActionPrimary)
                Text(label)
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(1)
            }
            .padding(.leading, 14)

            Spacer()

            // 右侧动作（更换/查看）
            if let action, let onAction {
                VStack(alignment: .trailing, spacing: 4) {
                    Button(action: onAction) {
                        Text(action)
                            .font(.editorialMetadata)
                            .foregroundStyle(Color.milensActionPrimary)
                    }
                    .buttonStyle(.plain)
                    Rectangle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 22, height: 1)
                }
                .padding(.trailing, 14)
            }
        }
        .frame(minHeight: 92)
        .background(Color.milensGrouped)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            ArchiveMarker(label: "记忆标记")
            ArchiveSectionHeader(title: "它的故事", supporting: "向左看看")
            ArchivePrimaryButton(action: {}) {
                Text("继续")
                    .font(.buttonLabel)
            }

            // ArchiveStatView 示例（等分统计带）
            HStack(spacing: 0) {
                ArchiveStatView(value: "128", label: "照片", unit: "张")
                ArchiveStatView(value: "24", label: "记录", unit: "条")
                ArchiveStatView(value: "365", label: "相伴", unit: "天")
            }

            // IdentityStrip 示例
            IdentityStrip(
                context: .source,
                meta: "原图",
                label: "夏天的傍晚",
                action: "更换",
                onAction: {}
            ) {
                Color.milensAccentSoft
            }

            // ArchivePanel 示例
            ArchivePanel {
                VStack(alignment: .leading, spacing: 16) {
                    Text("连续档案纸")
                        .font(.titleStandard)
                    ArchiveDivider()
                    Text("统计、记忆与近期照片属于同一张连续档案纸。")
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                }
                .padding(24)
            }
        }
        .padding(24)
    }
    .background(Color.milensBackground)
}
