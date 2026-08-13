//  MemoryRemindersView —— 回忆提醒中心（首页铃铛入口）。
//
//  三段式：今日命中（生日/成为家人的日子/里程碑/往日回忆）+ 全部即将到来的纪念日倒计时
//  + 往日回忆行。作为系统推送通知（NotifyService）的应用内兜底回看：
//  不依赖通知权限、不丢失，用户随时可回看「今天/最近有什么值得回看的」。
//
//  视觉语言复用首页编辑式风格：珊瑚竖线、文楷标题、编辑式回忆行。
//  对照 Notification-Copy-Design.md §1：温柔记录者语气，不制造焦虑。

import SwiftUI

struct MemoryRemindersView: View {
    @Environment(\.viewModelFactory) private var factory
    @State private var viewModel: MemoryRemindersViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView()
                    .tint(Color.milensActionPrimary)
            }
        }
        .background(Color.milensBackground)
        .navigationTitle(String(localized: "reminders.title"))
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            guard viewModel == nil else { return }
            let model = factory.makeMemoryRemindersViewModel()
            model.load()
            viewModel = model
        }
    }

    @ViewBuilder
    private func content(_ model: MemoryRemindersViewModel) -> some View {
        if model.isLoading {
            ProgressView()
                .tint(Color.milensActionPrimary)
        } else if let error = model.loadError {
            remindersErrorState(message: error) { model.load() }
        } else if model.isEmpty {
            remindersEmptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 今日
                    if !model.todayItems.isEmpty {
                        sectionLabel(String(localized: "reminders.section.today"))
                        VStack(spacing: Spacing.sm) {
                            ForEach(model.todayItems) { item in
                                TodayReminderCard(item: item)
                            }
                        }
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.bottom, Spacing.xxl)
                    }

                    // 即将到来的日子
                    if !model.upcomingItems.isEmpty {
                        sectionLabel(String(localized: "reminders.section.upcoming"))
                        VStack(spacing: 0) {
                            ForEach(Array(model.upcomingItems.enumerated()), id: \.element.id) { index, item in
                                UpcomingReminderRow(item: item)
                                if index < model.upcomingItems.count - 1 {
                                    ArchiveDivider().padding(.leading, 32)
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.bottom, Spacing.xxl)
                    }

                    // 往日回忆
                    if !model.memoryItems.isEmpty {
                        sectionLabel(String(localized: "reminders.section.memories"))
                        VStack(spacing: 0) {
                            ForEach(Array(model.memoryItems.enumerated()), id: \.element.id) { index, item in
                                MemoryReminderRow(item: item)
                                if index < model.memoryItems.count - 1 {
                                    ArchiveDivider().padding(.leading, 32)
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.bottom, Spacing.xxl)
                    }
                }
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - 区块标题

    /// 珊瑚竖线 + 文楷标签（对照首页编辑式分区风格）。
    private func sectionLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.milensPrimary)
                .frame(width: 3, height: 16)
                .cornerRadius(Radius.accentRail)
            Text(title)
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.bottom, Spacing.md)
    }

    // MARK: - 空态

    private var remindersEmptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "bell.slash")
                .font(.system(size: 36)) // ui-token:ok 空态装饰大图标
                .foregroundStyle(Color.milensTextTertiary)

            Text(String(localized: "reminders.empty.title"))
                .font(.editorialSection)
                .foregroundStyle(Color.milensTextPrimary)

            Text(String(localized: "reminders.empty.body"))
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)

            Text(String(localized: "reminders.empty.hint"))
                .font(.caption)
                .foregroundStyle(Color.milensTextTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.pagePad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func remindersErrorState(message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36)) // ui-token:ok 错误态装饰大图标
                .foregroundStyle(Color.milensTextTertiary)
            Text(message)
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "home.retry"), action: retry)
                .font(.buttonLabel)
                .buttonStyle(.borderedProminent)
                .tint(Color.milensActionPrimary)
        }
        .padding(.horizontal, Spacing.pagePad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 今日提醒卡片

/// 今日命中卡片：图标 + 标题 + 辅助信息；可跳转宠物档案或照片大图。
private struct TodayReminderCard: View {
    let item: TodayReminder

    var body: some View {
        Group {
            if item.kind == .memory, let photoID = item.photoID {
                NavigationLink(value: Route.photoView(photoID: photoID)) {
                    cardContent
                }
                .buttonStyle(.plain)
            } else if let petID = item.petID {
                NavigationLink(value: Route.petProfile(petID: petID)) {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        HStack(spacing: Spacing.md) {
            // 图标圆底
            ZStack {
                Circle()
                    .fill(Color.milensAccentSoft)
                    .frame(width: 40, height: 40)
                Image(systemName: iconName)
                    .font(.system(size: Sizing.iconSm))
                    .foregroundStyle(Color.milensActionPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(2)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: Spacing.sm)

            Image(systemName: "chevron.right")
                .font(.system(size: Sizing.iconSm, weight: .semibold))
                .foregroundStyle(Color.milensTextTertiary)
        }
        .padding(Spacing.md)
        .background(Color.milensCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    /// 按 kind 映射 SF Symbol（温柔、不夸张）。
    private var iconName: String {
        switch item.kind {
        case .birthday: return "heart.fill"
        case .adoption: return "house.fill"
        case .milestone: return "star.fill"
        case .memory: return "clock.arrow.circlepath"
        }
    }
}

// MARK: - 即将到来的日子行

/// 倒计时行：珊瑚竖线 + 标题 + 距今天数 + 切角按钮。
private struct UpcomingReminderRow: View {
    let item: UpcomingReminder

    var body: some View {
        NavigationLink(value: Route.petProfile(petID: item.petID)) {
            HStack(spacing: 0) {
                // 珊瑚竖线
                Rectangle()
                    .fill(Color.milensPrimary)
                    .frame(width: 4)
                    .cornerRadius(Radius.accentRail)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.bodyPrimary)
                        .foregroundStyle(Color.milensTextPrimary)
                    Text(countdownText)
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                }
                .padding(.leading, 21)
                .padding(.vertical, Spacing.md)

                Spacer(minLength: Spacing.md)

                // 倒计时数字 + 天
                VStack(alignment: .center, spacing: 0) {
                    Text("\(item.daysUntil)")
                        .font(.custom("Fraunces-Semibold", size: 22))
                        .foregroundStyle(Color.milensActionPrimary)
                    Text(countdownLabel)
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensTextTertiary)
                }
                .padding(.trailing, Spacing.sm)
            }
        }
        .buttonStyle(.plain)
    }

    /// 「还有 N 天」/「今天」。
    private var countdownText: String {
        item.daysUntil == 0
            ? String(localized: "reminders.upcoming.today")
            : String(localized: "reminders.upcoming.daysLeft \(item.daysUntil)")
    }

    private var countdownLabel: String {
        item.daysUntil == 0 ? "" : String(localized: "reminders.upcoming.dayUnit")
    }
}

// MARK: - 往日回忆行（编辑式）

/// 往日回忆行：序号 + 标题/副标题 + 缩略图。
private struct MemoryReminderRow: View {
    let item: MemoryReminderItem

    var body: some View {
        NavigationLink(value: Route.photoView(photoID: item.id)) {
            HStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(item.title)
                        .font(.editorialSection)
                        .foregroundStyle(Color.milensTextPrimary)
                        .lineLimit(2)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.milensTextSecondary)
                            .lineLimit(2)
                    }
                    Text(String(localized: "home.memoryOpen"))
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                }

                Spacer(minLength: Spacing.sm)

                ThumbnailImage(path: item.thumbnailPath)
                    .frame(width: 72, height: 96)
                    .aspectRatio(contentMode: .fill)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))

                Image(systemName: "chevron.right")
                    .font(.system(size: Sizing.iconSm, weight: .semibold))
                    .foregroundStyle(Color.milensCopper)
            }
            .padding(.vertical, Spacing.md)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 分隔线（复用首页 ArchiveDivider 风格）

/// 1pt 分隔线（浅色分隔线 token）。
private struct ArchiveDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.milensSeparator)
            .frame(height: 1)
    }
}

#Preview {
    NavigationStack {
        MemoryRemindersView()
    }
}
