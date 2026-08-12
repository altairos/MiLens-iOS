//  TimelineView —— 成长时间线（route .timeline，对应源端 pages/TimelinePage.ets）。
//  Ledger 编辑式时间线设计（对照 Figma「03·生命时间线」#140:348）：
//  左侧竖线 rail + 章节大圆点 + Fraunces 年份 + 文楷章节名 + 三种记忆卡片 + 悬浮添加。
//  TimelineViewModel（@Observable）驱动；Pro 门控 / 导出分享 / 宠物筛选保留。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "TimelineView")

struct TimelineView: View {
    @Environment(\.viewModelFactory) private var factory
    @Environment(\.proEntitlement) private var entitlement

    @State private var viewModel: TimelineViewModel?
    @State private var pets: [Pet] = []
    @State private var showPaywall = false
    /// ADR-0010 §5：时间线导出分享状态。
    @State private var sharePreview: (image: UIImage, url: URL)?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showAddMemorySheet = false
    /// 选中的年份筛选（nil = 全部年份）。
    @State private var selectedYear: Int? = nil
    private let timelineAccessStore: any TimelineAccessStore = UserDefaultsTimelineAccessStore()

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(String(localized: "timeline.title"))
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.milensBackground)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    handleExportShare()
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                .disabled(isExporting || viewModel?.months.isEmpty != false)
            }
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
        }
        .sheet(isPresented: $showAddMemorySheet) {
            if let vm = viewModel {
                AddMemorySheet(
                    viewModel: vm,
                    pets: pets,
                    isPro: entitlement.isPro,
                    firstAccessDate: timelineAccessStore.firstAccessDate(now: Date())
                )
            }
        }
        // ADR-0010 §5：导出分享预览面板
        .sheet(item: Binding<SharePreviewData?>(
            get: { sharePreview.map { SharePreviewData(image: $0.image, url: $0.url) } },
            set: { if $0 == nil { sharePreview = nil } }
        )) { data in
            SharePreviewSheet(
                previewImage: data.image,
                shareURL: data.url,
                onDismiss: { sharePreview = nil }
            )
        }
        .alert(String(localized: "timeline.exportFailed"), isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .onChange(of: entitlement.isPro) { _, isPro in
            let firstAccessDate = timelineAccessStore.firstAccessDate(now: Date())
            viewModel?.load(isPro: isPro, firstAccessDate: firstAccessDate)
        }
        .task {
            if viewModel == nil {
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

    // MARK: - 导出分享（ADR-0010 §5）

    private func handleExportShare() {
        guard let vm = viewModel else { return }
        guard entitlement.isPro else {
            showPaywall = true
            return
        }
        let filterTitle = currentFilterTitle(vm)
        guard let exportData = TimelineExportLogic.buildExportData(
            months: vm.months,
            filterTitle: filterTitle,
            includeWatermark: false
        ) else { return }

        isExporting = true
        let canvas = TimelineExportCanvas(data: exportData)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1

        guard let image = renderer.uiImage,
              let pngData = image.pngData() else {
            exportError = String(localized: "timeline.renderFailed")
            isExporting = false
            return
        }

        do {
            let url = try BeadExportService().writeShareCache(
                data: pngData, filename: "timeline_export.png"
            )
            sharePreview = (image: image, url: url)
        } catch {
            exportError = String(localized: "timeline.exportFailedDetail \(error.localizedDescription)")
        }
        isExporting = false
    }

    private func currentFilterTitle(_ vm: TimelineViewModel) -> String {
        if let petID = vm.selectedPetID,
           let pet = pets.first(where: { $0.id == petID }) {
            return "\(PetProfileLogic.speciesEmoji(pet.species)) \(pet.name)"
        }
        return String(localized: "timeline.allPets")
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
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    if vm.shouldShowPreviewReminder && !entitlement.isPro {
                        previewReminderBanner(vm)
                            .padding(.bottom, Spacing.md)
                    } else if vm.hasLockedHistory && !entitlement.isPro {
                        lockedHistoryBanner
                            .padding(.bottom, Spacing.md)
                    }

                    // 宠物筛选（轻量化，对齐设计稿）
                    if !pets.isEmpty {
                        petFilter(vm)
                            .padding(.bottom, Spacing.md)
                    }

                    // 年份选择器
                    yearSelector(vm)
                        .padding(.bottom, Spacing.lg)

                    // 时间轴主体
                    timelineAxis(vm)
                }
                .padding(.horizontal, Spacing.pagePad)
                .padding(.vertical, Spacing.sm)
                .padding(.bottom, 80) // 给悬浮按钮留空
            }
            .scrollIndicators(.hidden)

            // 悬浮添加按钮
            TimelineAddButton {
                showAddMemorySheet = true
            }
            .padding(.trailing, 18)
            .padding(.bottom, 18)
        }
    }

    private var lockedHistoryEmptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.milensActionPrimary)
            Text(String(localized: "timeline.lockedEmptyTitle"))
                .font(.displayMedium)
                .foregroundStyle(Color.milensTextPrimary)
            Text(String(localized: "timeline.lockedEmptyBody"))
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "timeline.viewProBenefits")) { showPaywall = true }
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
                Text(String(localized: "timeline.lockedBannerTitle"))
                    .font(.bodyPrimary.weight(.semibold))
                    .foregroundStyle(Color.milensTextPrimary)
                Button(String(localized: "timeline.lockedBannerCTA")) {
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
                Text(String(localized: "timeline.previewDaysLeft \(vm.previewDaysRemaining)"))
                    .font(.bodyPrimary.weight(.semibold))
                    .foregroundStyle(Color.milensTextPrimary)
                Button(String(localized: "timeline.previewUnlockCTA")) { showPaywall = true }
                    .font(.caption)
                    .foregroundStyle(Color.milensActionPrimary)
            }
            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.milensAccentSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    // MARK: - 宠物筛选（轻量化）

    private func petFilter(_ vm: TimelineViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                filterChip(title: String(localized: "timeline.filterAll"), isSelected: vm.selectedPetID == nil) {
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
                .font(.bodySecondary.weight(isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 年份选择器

    /// 从 months 提取可用年份列表，水平排列。
    private func yearSelector(_ vm: TimelineViewModel) -> some View {
        let years = availableYears(vm)
        guard !years.isEmpty else { AnyView(EmptyView()) }
        return AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(years, id: \.self) { year in
                        yearChip(year: year, isSelected: selectedYear == year || (selectedYear == nil && year == years.last)) {
                            selectedYear = (selectedYear == year) ? nil : year
                        }
                    }
                }
                // baseline
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.milensBorder)
                        .frame(height: 1)
                }
            }
        )
    }

    private func availableYears(_ vm: TimelineViewModel) -> [Int] {
        let years = Set(vm.months.map { $0.year })
        return years.sorted()
    }

    private func yearChip(year: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(String(year))
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextSecondary)
                if isSelected {
                    Circle()
                        .fill(Color.milensBackground)
                        .overlay(Circle().stroke(Color.milensActionPrimary, lineWidth: 2))
                        .frame(width: 10, height: 10)
                } else {
                    Color.clear.frame(width: 10, height: 10)
                }
            }
            .frame(width: 100)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 时间轴主体

    /// 左侧竖线 rail + 章节分组 + 条目卡片。
    private func timelineAxis(_ vm: TimelineViewModel) -> some View {
        let filteredMonths = filteredByYear(vm.months)
        // 按年份分组
        let yearGroups = groupByYear(filteredMonths)

        return HStack(alignment: .top, spacing: 0) {
            // 左侧竖线 rail（1pt，贯穿）
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(width: 1)
                Spacer()
            }
            .frame(width: 40) // rail 区域：节点占 22pt + 左右各约 9pt padding

            // 右侧内容
            VStack(alignment: .leading, spacing: 0) {
                ForEach(yearGroups, id: \.year) { group in
                    chapterSection(group)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 按选中年份过滤月份组。
    private func filteredByYear(_ months: [TimelineMonth]) -> [TimelineMonth] {
        guard let year = selectedYear else { return months }
        return months.filter { $0.year == year }
    }

    /// 按年份分组月份。
    private func groupByYear(_ months: [TimelineMonth]) -> [(year: Int, months: [TimelineMonth])] {
        let years = Set(months.map { $0.year }).sorted()
        return years.map { year in
            (year: year, months: months.filter { $0.year == year })
        }
    }

    /// 一个相处章节：珊瑚大圆点 + Fraunces 年份 + 章节名 + 副标题 + 月内条目。
    private func chapterSection(_ group: (year: Int, months: [TimelineMonth])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 章节标记（圆点向左偏移到 rail 位置）
            HStack(spacing: 0) {
                // 圆点占位（实际圆点通过 overlay 放在 rail 上）
                Color.clear.frame(width: 0, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(String(group.year))
                            .font(.custom("Fraunces-Bold", size: 12))
                            .foregroundStyle(Color.milensActionPrimary)
                    }
                    Text(chapterTitle(group.year, months: group.months))
                        .font(.custom("LXGWWenKai-Regular", size: 19, relativeTo: .title3))
                        .foregroundStyle(Color.milensTextPrimary)
                    Text(String(localized: "timeline.chapter.subtitle"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.milensTextSecondary)
                }
                .offset(x: -30) // 向左拉到 rail 位置
                Spacer()
            }
            .overlay(alignment: .leading) {
                // 珊瑚大圆点覆盖在 rail 上
                Circle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 22, height: 22)
                    .offset(x: -40 + 9) // 对齐 rail 中心
            }
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.md)

            // 月内条目
            ForEach(group.months, id: \.yearMonth) { month in
                monthEntries(month)
            }
        }
    }

    /// 章节标题：根据年份推导「一起生活的第N年」。
    private func chapterTitle(_ year: Int, months: [TimelineMonth]) -> String {
        // 从最早生日推导相处年数（简化：用最早月份年份与当前年份的差）
        guard let firstYear = months.first?.year else { return "" }
        let years = max(1, year - firstYear + 1)
        return String(localized: "timeline.chapter.together \(years)")
    }

    // MARK: - 月内条目

    private func monthEntries(_ month: TimelineMonth) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // 月份小标题（非年份首月才显示）
            if !month.isYearStart {
                Text(monthLabel(month.month))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.leading, 4)
            }

            ForEach(month.entries) { entry in
                entryCard(entry)
            }
        }
        .padding(.bottom, Spacing.lg)
    }

    private func monthLabel(_ month: Int) -> String {
        String(localized: "timeline.month \(month)")
    }

    /// 按条目类型分发到不同记忆卡片。
    @ViewBuilder
    private func entryCard(_ entry: TimelineEntry) -> some View {
        switch entry.type {
        case .photoNote:
            PhotoMemoryCard(entry: entry)
        case .textNote:
            TextMemoryCard(entry: entry)
        case .workRecord:
            WorkRecordCard(entry: entry)
        case .birthday, .adoption:
            // 重要日子：简洁文字行 + 节点
            milestoneRow(entry)
        }
    }

    /// 重要日子行（生日/领养日）：标题 + 日期 + 类型标签。
    private func milestoneRow(_ entry: TimelineEntry) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
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
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - 照片记忆卡片

/// 照片记忆：大图 + 左上「照片记忆」标签 + 日期 + 文楷标题 + 正文。
/// 对照 Figma #140:362-367。
private struct PhotoMemoryCard: View {
    let entry: TimelineEntry

    var body: some View {
        NavigationLink(value: Route.photoView(photoID: entry.photoID ?? UUID())) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // 大图 + 左上角标签
                ZStack(alignment: .topLeading) {
                    if !entry.thumbnailPath.isEmpty {
                        ThumbnailImage(path: entry.thumbnailPath)
                            .scaledToFill()
                            .frame(height: 176)
                            .clipped()
                    } else if !entry.photoURI.isEmpty {
                        ThumbnailImage(path: entry.photoURI)
                            .scaledToFill()
                            .frame(height: 176)
                            .clipped()
                    } else {
                        // 无图占位
                        Rectangle()
                            .fill(Color.milensGrouped)
                            .frame(height: 176)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(Color.milensTextTertiary)
                            )
                    }

                    // 左上角「照片记忆」标签
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.milensActionPrimary)
                            .frame(width: 22, height: 2)
                        Text(String(localized: "timeline.memoryType.photo"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.milensActionPrimary)
                    }
                    .padding(.leading, 14)
                    .padding(.top, 14)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                // 日期（珊瑚）
                Text(entry.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.milensActionPrimary)

                // 文楷标题
                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(.custom("LXGWWenKai-Regular", size: 18, relativeTo: .title3))
                        .foregroundStyle(Color.milensTextPrimary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 文本记忆卡片

/// 文本记忆：浅粉底 #FCE8DF + 左侧珊瑚 rail + 日期 + 正文。
/// 对照 Figma #140:369-371 + #143:411 rail。
private struct TextMemoryCard: View {
    let entry: TimelineEntry

    var body: some View {
        HStack(spacing: 0) {
            // 左侧珊瑚 rail（3pt）
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3)
            // 内容区
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(entry.subtitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.milensActionPrimary)
                if !entry.title.isEmpty {
                    Text(entry.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.milensTextPrimary)
                }
                if !entry.bodyText.isEmpty {
                    Text(entry.bodyText)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.milensTextPrimary)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 18)
            .padding(.vertical, 18)
            Spacer()
        }
        .background(Color(red: 0.988, green: 0.910, blue: 0.875)) // #FCE8DF
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - 作品记录卡片

/// 作品记录：左侧珊瑚 rail + 作品预览 + 类型标签 + 标题 + 来源说明。
/// 对照 Figma #140:374-411。作品预览优先回链来源照片缩略图（relatedPhotoID），
/// 无来源照片时回退到 7x7 拼豆占位网格（拼豆像素级预览属后续功能）。
private struct WorkRecordCard: View {
    let entry: TimelineEntry

    var body: some View {
        HStack(spacing: 0) {
            // 左侧珊瑚 rail（3pt）
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3)
            // 内容区
            HStack(spacing: Spacing.md) {
                // 作品预览（方形）：优先来源照片缩略图，回退拼豆占位网格
                preview
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    // 作品记录类型标签
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.milensActionPrimary)
                            .frame(width: 22, height: 2)
                        Text(String(localized: "timeline.memoryType.work"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.milensActionPrimary)
                    }
                    Text(entry.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.milensTextPrimary)
                    // 日期（珊瑚）
                    Text(entry.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.milensActionPrimary)
                    // 来源说明：优先正文，其次「由一张照片生成」
                    if !entry.bodyText.isEmpty {
                        Text(entry.bodyText)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.milensTextSecondary)
                            .lineLimit(2)
                    } else if entry.photoID != nil {
                        Text(String(localized: "timeline.work.fromPhoto"))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.milensTextSecondary)
                    }
                }
                Spacer()
            }
            .padding(16)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.milensBorder).frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.milensBorder).frame(height: 0.5)
        }
    }

    /// 作品预览：优先来源照片缩略图，回退拼豆占位网格。
    @ViewBuilder
    private var preview: some View {
        if !entry.thumbnailPath.isEmpty {
            ThumbnailImage(path: entry.thumbnailPath)
        } else if !entry.photoURI.isEmpty {
            ThumbnailImage(path: entry.photoURI)
        } else {
            beadGridPlaceholder
        }
    }

    /// 7x7 拼豆占位网格（无来源照片时回退；设计稿配色 #C74729 / #2E2924 交替）。
    private var beadGridPlaceholder: some View {
        let cols = 7
        let rows = 7
        let beadSize: CGFloat = 8
        let gap: CGFloat = 3
        return VStack(spacing: gap) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0..<cols, id: \.self) { c in
                        Circle()
                            .fill((r + c) % 3 == 0 ? Color.milensActionPrimary : Color.milensInk)
                            .frame(width: beadSize, height: beadSize)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.milensGrouped)
    }
}

// MARK: - 悬浮添加按钮

/// 右下角切角珊瑚方块 + plus 图标。
/// 对照 Figma #143:418「Add Memory Cut Corner Key」。
private struct TimelineAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 56, height: 56)
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "timeline.addMemory"))
    }
}

// MARK: - 添加记忆表单 Sheet

/// 添加一条记忆（Life-Archive-Design.md §3.3）。
/// 最小表单：归属宠物 + 标题 + 日期 + 备注 + 关联照片(可选) + 置顶(可选)。
/// 保存后写入 PetEvent(sourceType="user")，进入时间线并可被编辑/取消置顶。
private struct AddMemorySheet: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: TimelineViewModel
    let pets: [Pet]
    let isPro: Bool
    let firstAccessDate: Date?

    @State private var selectedPetID: UUID?
    @State private var title = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var isPinned = false
    @State private var relatedPhotoID: UUID? = nil

    private var selectedPet: Pet? {
        pets.first { $0.id == selectedPetID }
    }

    private var candidatePhotos: [Photo] {
        guard let pet = selectedPet else { return [] }
        return viewModel.photos(for: pet)
    }

    private var canSubmit: Bool {
        selectedPet != nil
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let dateRange: ClosedRange<Date> = {
        let cal = Calendar(identifier: .gregorian)
        // 2000-01-01 在 Gregorian 日历必然有效；失败属于日历基础设施异常。
        guard let start = cal.date(from: DateComponents(year: 2000, month: 1, day: 1)) else {
            fatalError("无法构造 2000-01-01 日期（Gregorian 日历异常）")
        }
        return start...Date()
    }()

    var body: some View {
        NavigationStack {
            Form {
                petSection
                contentSection
                if !candidatePhotos.isEmpty {
                    photoSection
                }
                optionsSection
                if !viewModel.addMemoryError.isEmpty {
                    errorSection
                }
            }
            .scrollContentBackground(.hidden)
            .listRowBackground(Color.milensGrouped)
            .background(Color.milensBackground)
            .navigationTitle(String(localized: "timeline.addMemory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { submit() } label: {
                    Text(String(localized: "timeline.addMemory.save"))
                        .font(.buttonLabel)
                        .foregroundStyle(Color.milensTextOnActionPrimary)
                        .frame(maxWidth: .infinity, minHeight: Sizing.touchTarget)
                        .background(canSubmit ? Color.milensActionPrimary : Color.milensTextTertiary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .padding(.horizontal, Spacing.pagePad)
                .padding(.vertical, Spacing.sm)
            }
            .onAppear {
                if selectedPetID == nil { selectedPetID = pets.first?.id }
            }
        }
        // iPad/regular 宽度下表单限宽居中（UI-DESIGN.md §8）
        .modalContentWidth()
    }

    // MARK: - 表单分区

    private var petSection: some View {
        Section(String(localized: "timeline.addMemory.pet")) {
            if pets.isEmpty {
                Text(String(localized: "timeline.addMemory.noPet"))
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
            } else {
                Picker(String(localized: "timeline.addMemory.pet"), selection: $selectedPetID) {
                    ForEach(pets, id: \.id) { pet in
                        Text("\(PetProfileLogic.speciesEmoji(pet.species)) \(pet.name)")
                            .tag(Optional(pet.id))
                    }
                }
                .environment(\.locale, Locale(identifier: "zh_CN"))
            }
        }
    }

    private var contentSection: some View {
        Section(String(localized: "timeline.addMemory.content")) {
            TextField(
                String(localized: "timeline.addMemory.titlePlaceholder"),
                text: $title
            )
            .font(.bodyPrimary)
            .submitLabel(.done)

            DatePicker(
                String(localized: "timeline.addMemory.date"),
                selection: $date, in: dateRange,
                displayedComponents: .date
            )
            .environment(\.locale, Locale(identifier: "zh_CN"))

            TextField(
                String(localized: "timeline.addMemory.bodyPlaceholder"),
                text: $note, axis: .vertical
            )
            .lineLimit(2...5)
            .font(.bodyPrimary)
        }
    }

    /// 关联照片：横向缩略图选择器（可选）。
    private var photoSection: some View {
        Section(String(localized: "timeline.addMemory.relatedPhoto")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    // 「无」选项
                    relatedPhotoNilButton
                    ForEach(candidatePhotos, id: \.id) { photo in
                        relatedPhotoThumbnail(photo)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    private var relatedPhotoNilButton: some View {
        Button {
            relatedPhotoID = nil
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(Color.milensGrouped)
                    .frame(width: 64, height: 64)
                Image(systemName: "slash.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.milensTextTertiary)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .stroke(Color.milensActionPrimary, lineWidth: relatedPhotoID == nil ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "timeline.addMemory.noPhoto"))
    }

    private func relatedPhotoThumbnail(_ photo: Photo) -> some View {
        let isSelected = relatedPhotoID == photo.id
        let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
        return Button {
            relatedPhotoID = isSelected ? nil : photo.id
        } label: {
            ThumbnailImage(path: path)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .stroke(Color.milensActionPrimary, lineWidth: isSelected ? 2 : 0)
                )
        }
        .buttonStyle(.plain)
    }

    private var optionsSection: some View {
        Section(String(localized: "timeline.addMemory.options")) {
            Toggle(String(localized: "timeline.addMemory.pinned"), isOn: $isPinned)
                .font(.bodyPrimary)
        }
    }

    private var errorSection: some View {
        Section {
            Label(viewModel.addMemoryError, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.milensDanger)
                .font(.caption)
        }
    }

    // MARK: - 提交

    private func submit() {
        guard let pet = selectedPet else { return }
        let ok = viewModel.addMemory(
            to: pet, title: title, date: date, body: note,
            relatedPhotoID: relatedPhotoID, isPinned: isPinned,
            isPro: isPro, firstAccessDate: firstAccessDate
        )
        if ok {
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        TimelineView()
    }
}
