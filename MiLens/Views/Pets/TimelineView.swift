//  TimelineView —— 成长时间线（route .timeline，对应源端 pages/TimelinePage.ets）。
//  TimelineViewModel（@Observable）驱动：按年月分组的时间线条目列表 + 按宠物筛选。
//  条目类型：生日🎂 / 领养日🏠 / 照片事件📷。
//  UI rework：左侧竖线 + 圆点节点样式（UI-DESIGN.md §6.5），照片事件配代表照片缩略图。
//  P3 实现：按月分组展示 + 宠物筛选 + 条目点击进入照片大图。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "TimelineView")

struct TimelineView: View {
    @Environment(\.viewModelFactory) private var factory
    @Environment(\.proEntitlement) private var entitlement

    @State private var viewModel: TimelineViewModel?
    @State private var pets: [Pet] = []
    @State private var showPaywall = false
    private let timelineAccessStore: any TimelineAccessStore = UserDefaultsTimelineAccessStore()

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("成长时间线")
        .navigationBarTitleDisplayMode(.large)
        .background(Color.milensBackground)
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
        }
        .onChange(of: entitlement.isPro) { _, isPro in
            let firstAccessDate = timelineAccessStore.firstAccessDate(now: Date())
            viewModel?.load(isPro: isPro, firstAccessDate: firstAccessDate)
        }
        .task {
            if viewModel == nil {
                // 分层收敛：VM 与数据查询均经工厂（View 不再直连 petRepo/photoRepo）
                let vm = factory.makeTimelineViewModel()
                let firstAccessDate = timelineAccessStore.firstAccessDate(now: Date())
                vm.load(isPro: entitlement.isPro, firstAccessDate: firstAccessDate)
                viewModel = vm
                do {
                    pets = try factory.allPets()
                } catch {
                    logger.error("加载宠物筛选列表失败（\(error.localizedDescription)）")
                    pets = []
                }
            }
        }
    }

    // MARK: - 内容区

    @ViewBuilder
    private func content(_ vm: TimelineViewModel) -> some View {
        if vm.isLoading {
            ProgressView()
        } else if vm.months.isEmpty && vm.hasLockedHistory && !entitlement.isPro {
            lockedHistoryEmptyState
        } else if vm.months.isEmpty {
            emptyState
        } else {
            timelineList(vm)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.milensTextSecondary)
            Text("还没有成长记录")
                .font(.displayMedium)
                .foregroundStyle(Color.milensTextPrimary)
            Text("添加宠物档案和照片后，这里会自动生成成长时间线")
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Spacing.pagePad)
    }

    // MARK: - 时间线列表

    private func timelineList(_ vm: TimelineViewModel) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if vm.shouldShowPreviewReminder && !entitlement.isPro {
                    previewReminderBanner(vm)
                        .padding(.bottom, Spacing.md)
                } else if vm.hasLockedHistory && !entitlement.isPro {
                    lockedHistoryBanner
                        .padding(.bottom, Spacing.md)
                }
                // 筛选器
                if !pets.isEmpty {
                    petFilter(vm)
                        .padding(.bottom, Spacing.md)
                }

                // 按月分组
                ForEach(Array(vm.months.enumerated()), id: \.element.yearMonth) { _, month in
                    monthSection(month)
                }
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.vertical, Spacing.sm)
        }
        .scrollIndicators(.hidden)
    }

    private var lockedHistoryEmptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.milensActionPrimary)
            Text("你的早期故事还在这里")
                .font(.displayMedium)
                .foregroundStyle(Color.milensTextPrimary)
            Text("升级 MiLens Pro，查看一年前的成长记录。")
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)
            Button("查看 Pro 权益") { showPaywall = true }
                .buttonStyle(.borderedProminent)
                .tint(Color.milensActionPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Spacing.pagePad)
    }

    private var lockedHistoryBanner: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "lock.fill")
                .foregroundStyle(Color.milensActionPrimary)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("一年前的故事，仍然替你保存着")
                    .font(.bodyPrimary.weight(.semibold))
                    .foregroundStyle(Color.milensTextPrimary)
                Button("升级 MiLens Pro，查看完整成长时间线") {
                    showPaywall = true
                }
                    .font(.caption)
                    .foregroundStyle(Color.milensActionPrimary)
            }
            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.milensAccentSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    private func previewReminderBanner(_ vm: TimelineViewModel) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "clock.badge.checkmark")
                .foregroundStyle(Color.milensActionPrimary)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("完整时间线体验还剩 \(vm.previewDaysRemaining) 天")
                    .font(.bodyPrimary.weight(.semibold))
                    .foregroundStyle(Color.milensTextPrimary)
                Button("现在解锁，继续保存全部故事") { showPaywall = true }
                    .font(.caption)
                    .foregroundStyle(Color.milensActionPrimary)
            }
            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.milensAccentSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    // MARK: - 宠物筛选

    private func petFilter(_ vm: TimelineViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                filterChip(title: "全部", isSelected: vm.selectedPetID == nil) {
                    vm.selectPet(nil)
                }
                ForEach(pets, id: \.id) { pet in
                    filterChip(
                        title: "\(PetProfileLogic.speciesEmoji(pet.species)) \(pet.name)",
                        isSelected: vm.selectedPetID == pet.id
                    ) {
                        vm.selectPet(pet.id)
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.bodySecondary.weight(.semibold))
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

    // MARK: - 月份分组

    private func monthSection(_ month: TimelineMonth) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // 分组标题：年份大分节 + 月份，衬线 displayMedium（§6.5）
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                if month.isYearStart {
                    Text("\(String(month.year))年")
                        .font(.displayMedium)
                        .foregroundStyle(Color.milensTextPrimary)
                }
                Text(monthLabel(month.month))
                    .font(.displayMedium)
                    .foregroundStyle(Color.milensTextPrimary)
            }
            .accessibilityAddTraits(.isHeader)
            .padding(.leading, Spacing.xxl)

            // 节点条目列表
            VStack(spacing: 0) {
                ForEach(Array(month.entries.enumerated()), id: \.element.id) { index, entry in
                    entryRow(
                        entry,
                        isFirst: index == 0,
                        isLast: index == month.entries.count - 1
                    )
                }
            }
        }
        .padding(.bottom, Spacing.lg)
    }

    private func monthLabel(_ month: Int) -> String {
        let names = ["", "1月", "2月", "3月", "4月", "5月", "6月",
                     "7月", "8月", "9月", "10月", "11月", "12月"]
        return (1...12).contains(month) ? names[month] : "\(month)月"
    }

    // MARK: - 条目（节点）

    @ViewBuilder
    private func entryRow(_ entry: TimelineEntry, isFirst: Bool, isLast: Bool) -> some View {
        Group {
            if let photoID = entry.photoID {
                NavigationLink(value: Route.photoView(photoID: photoID)) {
                    entryContent(entry, isFirst: isFirst, isLast: isLast)
                }
                .buttonStyle(.plain)
            } else {
                entryContent(entry, isFirst: isFirst, isLast: isLast)
            }
        }
    }

    private func entryContent(_ entry: TimelineEntry, isFirst: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            // 节点轨：圆点 + 竖线（§6.5 时间线骨架）
            nodeRail(type: entry.type, isFirst: isFirst, isLast: isLast)

            // 照片事件配代表照片缩略图
            if let thumbPath = thumbnailPath(for: entry) {
                ThumbnailImage(path: thumbPath)
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
                    // M4：时间线照片缩略图提供无障碍描述（标题文本已由下方 Text 读出）。
                    .accessibilityLabel("代表照片")
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(entry.title)
                        .font(.bodyPrimary)
                        .foregroundStyle(Color.milensTextPrimary)
                    if let label = typeLabel(entry.type) {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(Color.milensTextTertiary)
                    }
                }
                if !entry.subtitle.isEmpty {
                    Text(entry.subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.milensTextTertiary)
                }
            }
            Spacer(minLength: 0)

            if entry.photoID != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.milensTextTertiary)
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    /// 节点轨：圆点 + 贯穿竖线；首末条目截断线避免悬空头尾。
    private func nodeRail(type: TimelineEntryType, isFirst: Bool, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? Color.clear : Color.milensSeparator)
                .frame(width: 1, height: Spacing.sm + 7)
            Circle()
                .fill(nodeColor(type))
                .frame(width: 8, height: 8)
            Rectangle()
                .fill(isLast ? Color.clear : Color.milensSeparator)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 12)
    }

    private func nodeColor(_ type: TimelineEntryType) -> Color {
        switch type {
        case .birthday: Color.milensPrimary
        case .adoption: Color.milensDogAccent
        case .photoNote: Color.milensSuccess
        }
    }

    /// 类型文字标签：节点不只靠颜色区分（§6.5）。
    private func typeLabel(_ type: TimelineEntryType) -> String? {
        switch type {
        case .birthday: "生日"
        case .adoption: "纪念日"
        case .photoNote: nil
        }
    }

    /// 照片事件的代表缩略图路径；无照片事件返回 nil。
    private func thumbnailPath(for entry: TimelineEntry) -> String? {
        guard entry.photoID != nil else { return nil }
        if !entry.thumbnailPath.isEmpty { return entry.thumbnailPath }
        return entry.photoURI.isEmpty ? nil : entry.photoURI
    }
}

#Preview {
    NavigationStack {
        TimelineView()
    }
}
