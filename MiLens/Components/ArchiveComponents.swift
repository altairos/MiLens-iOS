//  ArchiveComponents —— Quiet Archive 共用视觉组件。
//
//  这些组件只负责排版与交互表面，不持有业务状态。页面通过它们共享
//  「记忆标记、日期层级、细分隔、单一主动作」这套视觉语法。

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
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(Color.milensTextOnActionPrimary)
                .frame(maxWidth: .infinity, minHeight: 50)
                .padding(.horizontal, Spacing.lg)
                .background(Color.milensActionPrimary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
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
        .animation(.easeInOut(duration: Motion.durationFast), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        ArchiveMarker(label: "记忆标记")
        ArchiveSectionHeader(title: "它的故事", supporting: "向左看看")
        ArchivePrimaryButton(action: {}) {
            Text("继续")
                .font(.buttonLabel)
        }
    }
    .padding(24)
    .background(Color.milensBackground)
}
