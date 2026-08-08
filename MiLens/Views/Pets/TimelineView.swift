//  TimelineView —— 成长时间线（route .timeline，对应源端 pages/TimelinePage.ets）。
//  TimelineViewModel（@Observable）驱动：按年月分组的时间线条目列表 + 按宠物筛选。
//  条目类型：生日🎂 / 领养日🏠 / 照片事件📷。
//  P3 实现：按月分组展示 + 宠物筛选 + 条目点击进入照片大图。

import SwiftUI

struct TimelineView: View {
    @Environment(\.petRepository) private var petRepo
    @Environment(\.photoRepository) private var photoRepo

    @State private var viewModel: TimelineViewModel?
    @State private var pets: [Pet] = []

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
        .task {
            if viewModel == nil {
                let vm = TimelineViewModel(petRepo: petRepo, photoRepo: photoRepo)
                vm.load()
                viewModel = vm
                pets = (try? petRepo.getAllPets()) ?? []
            }
        }
    }

    // MARK: - 内容区

    @ViewBuilder
    private func content(_ vm: TimelineViewModel) -> some View {
        if vm.isLoading {
            ProgressView()
        } else if vm.months.isEmpty {
            emptyState
        } else {
            timelineList(vm)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(Color.milensTextSecondary)
            Text("还没有成长记录")
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
            Text("添加宠物档案和照片后，这里会自动生成成长时间线")
                .font(.caption)
                .foregroundStyle(Color.milensTextTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - 时间线列表

    private func timelineList(_ vm: TimelineViewModel) -> some View {
        ScrollView {
            VStack(spacing: 0) {
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
                .font(.caption)
                .foregroundStyle(isSelected ? Color.milensTextOnAccent : Color.milensTextSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? Color.milensPrimary : Color.milensGrouped)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: Motion.durationFast), value: isSelected)
    }

    // MARK: - 月份分组

    private func monthSection(_ month: TimelineMonth) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // 年份/月份标题
            HStack {
                if month.isYearStart {
                    Text("\(String(month.year)) 年")
                        .font(.displayMedium)
                        .foregroundStyle(Color.milensTextPrimary)
                }
                Spacer()
                Text(monthLabel(month.month))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
            }

            // 条目列表
            VStack(spacing: Spacing.sm) {
                ForEach(month.entries, id: \.id) { entry in
                    entryRow(entry)
                }
            }
            .padding(Spacing.md)
            .background(Color.milensCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.large))
        }
        .padding(.bottom, Spacing.lg)
    }

    private func monthLabel(_ month: Int) -> String {
        let names = ["", "1月", "2月", "3月", "4月", "5月", "6月",
                     "7月", "8月", "9月", "10月", "11月", "12月"]
        return (1...12).contains(month) ? names[month] : "\(month)月"
    }

    // MARK: - 条目

    @ViewBuilder
    private func entryRow(_ entry: TimelineEntry) -> some View {
        let hasPhoto = entry.photoID != nil
        Group {
            if hasPhoto {
                NavigationLink(value: Route.photoView(photoID: entry.photoID!)) {
                    entryContent(entry)
                }
                .buttonStyle(.plain)
            } else {
                entryContent(entry)
            }
        }
    }

    private func entryContent(_ entry: TimelineEntry) -> some View {
        HStack(spacing: Spacing.md) {
            // 类型图标
            iconForType(entry.type)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextPrimary)
                if !entry.subtitle.isEmpty {
                    Text(entry.subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.milensTextTertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, Spacing.xs)
    }

    private func iconForType(_ type: TimelineEntryType) -> some View {
        let (emoji, color): (String, Color) = switch type {
        case .birthday: ("🎂", Color.milensPrimary)
        case .adoption: ("🏠", Color.milensDogAccent)
        case .photoNote: ("📷", Color.milensSuccess)
        }
        return ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 36, height: 36)
            Text(emoji)
                .font(.system(size: 18))
        }
    }
}

#Preview {
    NavigationStack {
        TimelineView()
    }
}
