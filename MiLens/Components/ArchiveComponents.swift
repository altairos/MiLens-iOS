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
    var body: some View {
        Rectangle()
            .fill(Color.milensSeparator)
            .frame(height: 1 / UIScreen.main.scale)
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
