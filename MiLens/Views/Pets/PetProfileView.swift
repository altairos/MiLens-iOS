//  PetProfileView —— 单只宠物档案详情（route .petProfile）。
//  Ledger 编辑式设计（对照 Figma「02·伙伴档案」#319:1095）：
//  出血肖像 Hero（315pt）+ Archive Panel 浮起覆盖（32px 圆角）+ 四列统计 + 置顶记忆 + 最近照片 + 时间线入口。
//  P3 实现（只读详情）；编辑走 .petEdit 路由，时间线走 .timeline 路由。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "PetProfile")

struct PetProfileView: View {
    let petID: UUID

    @Environment(\.viewModelFactory) private var factory
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.proEntitlement) private var entitlement

    /// 是否处于 regular 宽度（iPad 竖屏 / 大尺寸横屏），启用双栏分栏。
    private var isRegularWidth: Bool { hSizeClass == .regular }

    @State private var pet: Pet?
    @State private var photos: [Photo] = []
    @State private var unassignedPhotos: [Photo] = []
    @State private var selectedCategory: PetPhotoCategory = .all
    @State private var isLoading = true
    @State private var assignmentPhotos: [Photo] = []
    @State private var showAddMemorySheet = false
    private let timelineAccessStore: any TimelineAccessStore = UserDefaultsTimelineAccessStore()

    private let recentPhotoColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private let gridColumns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let pet {
                petArchive(pet)
            } else {
                loadFailedView
            }
        }
        .background(Color.milensBackground)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: Binding(
            get: { !assignmentPhotos.isEmpty },
            set: { if !$0 { assignmentPhotos.removeAll() } }
        )) {
            if !assignmentPhotos.isEmpty {
                PetAssignmentSheet(photos: assignmentPhotos) {
                    Task { await load() }
                }
            }
        }
        .sheet(isPresented: $showAddMemorySheet) {
            if let pet {
                let vm = factory.makeTimelineViewModel()
                AddMemorySheet(
                    viewModel: vm,
                    pets: [pet],
                    isPro: entitlement.isPro,
                    firstAccessDate: timelineAccessStore.firstAccessDate(now: Date())
                )
            }
        }
        .task { await load() }
    }

    // MARK: - 档案主体

    private func petArchive(_ pet: Pet) -> some View {
        if isRegularWidth {
            // iPad 双栏分栏（对照 Figma #307:669 Adaptive Layout · iPad）
            adaptiveArchive(pet)
        } else {
            // iPhone 单列滚动（原布局）
            ScrollView {
                VStack(spacing: 0) {
                    // 出血肖像 Hero（对照 #319:1096-1100）
                    PortraitHero(
                        path: portraitPath,
                        emojiPlaceholder: PetProfileLogic.speciesEmoji(pet.species),
                        name: pet.name,
                        subtitle: petSubtitle(pet),
                        height: 315,
                        petID: pet.id
                    )

                    // Archive Panel 浮起覆盖（对照 #319:1101）
                    archivePanel(pet)
                        .padding(.top, -25) // 覆盖 Hero 底部
                        .padding(.bottom, Spacing.xxl)
                }
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - iPad 双栏分栏（对照 Figma #307:671 Adaptive Columns）

    /// 左列：肖像 Hero + Archive Continuity Note；右列：Archive Panel + Timeline Continuation。
    /// 两列各自独立滚动，间距 18pt（对照 Figma gap: 18px）。
    private func adaptiveArchive(_ pet: Pet) -> some View {
        HStack(alignment: .top, spacing: 18) {
            // 左列（376pt）：肖像 + 连续性标语
            ScrollView {
                VStack(spacing: 18) {
                    PortraitHero(
                        path: portraitPath,
                        emojiPlaceholder: PetProfileLogic.speciesEmoji(pet.species),
                        name: pet.name,
                        subtitle: petSubtitle(pet),
                        height: 700,
                        petID: pet.id
                    )
                    ArchiveContinuityNote(pet: pet)
                }
                .padding(.bottom, Spacing.xxl)
            }
            .frame(width: AdaptiveColumn.archivePortrait)
            .scrollIndicators(.hidden)

            // 右列（390pt）：档案面板 + 时间线续页卡片
            ScrollView {
                VStack(spacing: 18) {
                    archivePanel(pet)
                        .padding(.top, 0)
                    TimelineContinuationCard()
                }
                .padding(.bottom, Spacing.xxl)
            }
            .frame(width: AdaptiveColumn.archivePanel)
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, Spacing.xxl)
        .frame(maxWidth: .infinity)
        .background(Color.milensBackground)
    }

    // MARK: - 出血肖像 Hero

    /// 肖像数据源。
    private var portraitPath: String? {
        guard let pet else { return nil }
        if !pet.avatarPath.isEmpty { return pet.avatarPath }
        guard let latest = photos.first else { return nil }
        return latest.thumbnailPath.isEmpty ? latest.uri : latest.thumbnailPath
    }

    /// 副标题：「喵星人 · 女孩子 · 生于 2024.05.16」（生日用 Fraunces 内联）。
    private func petSubtitle(_ pet: Pet) -> Text {
        let species = PetDisplayLogic.speciesDisplayName(pet.species)
        let gender = PetDisplayLogic.genderDisplayName(pet.gender)
        var subtitle = Text("\(species) · \(gender)")
        if let birthday = pet.birthday {
            let dateStr = birthday.formatted(.iso8601.year().month().day().dateSeparator(.dot))
            subtitle = subtitle + Text(" · ") + Text(String(localized: "pet.profile.born")) + Text(" ") + Text(dateStr).font(.custom("Fraunces-Semibold", size: 12))
        }
        return subtitle.foregroundStyle(.white.opacity(0.92))
    }

    // MARK: - Archive Panel

    /// 浮起覆盖面板：Eyebrow + Intro + 档案起点 + 统计 + 置顶记忆 + 最近照片 + 时间线入口 + 继续记录。
    /// 对照 Figma #319:1101（Surface/Archive Panel，32px 圆角）。
    /// P3.6 增强：重要日子数 + 档案起点 + 继续记录入口（Life-Archive-Design.md §3）。
    private func archivePanel(_ pet: Pet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow + Intro（对照 #I319:1101;296:588-589）
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "pet.profile.eyebrow"))
                    .font(.editorialOverline)
                    .tracking(0.4)
                    .foregroundStyle(Color.milensActionPrimary)
                Text(String(localized: "pet.profile.intro"))
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
                // P3.6：档案起点日期
                if let originDate = archiveOriginDate(pet) {
                    Text(String(localized: "pet.profile.archiveOrigin") + " " +
                         originDate.formatted(.iso8601.year().month().day().dateSeparator(.dot)))
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensTextTertiary)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)

            // 统计行（对照 Archive Stat #I319:1101;296:617-626）
            archiveStatsRow(pet)
                .padding(.top, 20)

            // 分隔线
            Rectangle().fill(Color.milensBorder).frame(height: 0.5)
                .padding(.horizontal, 24)
                .padding(.top, 16)

            // 置顶记忆（对照 #I319:1101;296:595-608）
            if let pinned = pinnedMemory(pet) {
                pinnedMemorySection(pinned)
                    .padding(.top, 16)
            }

            // 最近照片（对照 #I319:1101;296:599-602）
            if !photos.isEmpty {
                recentPhotosSection
                    .padding(.top, 20)
            }

            // 时间线入口 + 继续记录（对照 #I319:1101;296:603-606）
            timelineLink(pet)
                .padding(.top, 20)

            // P3.6：继续记录入口（突出主 CTA，鼓励用户补写记忆）
            continueRecordingEntry(pet)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)

            // 照片分类网格（保留现有功能）
            if hasPhotoContent {
                Divider().padding(.horizontal, 24)
                photosSection
                    .padding(.top, 20)
                    .padding(.horizontal, 24)
            }

            // 备忘事件（保留现有功能）
            if !parsedNotes.isEmpty {
                Divider().padding(.horizontal, 24)
                notesSection
                    .padding(.top, 20)
                    .padding(.horizontal, 24)
            }
        }
        .background(Color.milensBackground)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    // MARK: - 档案起点日期

    /// 计算档案起点日期：最早的事件日期或照片拍摄日期。
    private func archiveOriginDate(_ pet: Pet) -> Date? {
        let eventDates = pet.events.map { $0.eventDate }
        let photoDates = photos.compactMap { $0.takenAt }
        return (eventDates + photoDates).min()
    }

    // MARK: - 统计行

    private func archiveStatsRow(_ pet: Pet) -> some View {
        let workCount = photos.filter { PetPhotoCategoryLogic.isEditedPhoto($0) }.count
        let memoryCount = pet.events.count
        // P3.6：重要日子数 = 生日 + 领养日 + 用户标记事件
        let importantDayCount = pet.events.filter {
            $0.sourceType == "user" || $0.eventType == "birthday" || $0.eventType == "adoption"
        }.count

        return HStack(spacing: 0) {
            ArchiveStatItem(value: "\(pet.photoCount)", label: String(localized: "pet.profile.stat.photos"))
            ArchiveStatItem(value: "\(memoryCount)", label: String(localized: "pet.profile.stat.memories"))
            ArchiveStatItem(value: "\(PetDisplayLogic.daysTogether(from: pet.adoptionDay))", label: String(localized: "pet.profile.stat.days"))
            ArchiveStatItem(value: "\(importantDayCount)", label: String(localized: "pet.profile.stat.importantDays"))
        }
        .padding(.horizontal, 24)
    }

    // MARK: - 置顶记忆

    /// 取置顶的 PetEvent（isPinned）或最近用户记录（sourceType=="user"），
    /// 回退随机一张照片（每次进入页面从全部照片中随机选一张，增加新鲜感）。
    private struct PinnedMemory {
        let title: String
        let note: String
        let dateLabel: String
        let photoPath: String?
    }

    private func pinnedMemory(_ pet: Pet) -> PinnedMemory? {
        // 优先 isPinned 事件
        let pinnedEvents = pet.events.filter { $0.isPinned }
        // 其次用户记录
        let userEvents = pet.events.filter { $0.sourceType == "user" && !$0.body.isEmpty }
        let candidates = pinnedEvents.isEmpty ? userEvents : pinnedEvents

        if let ev = candidates.sorted(by: { $0.eventDate > $1.eventDate }).first {
            let cal = Calendar.current
            let m = cal.component(.month, from: ev.eventDate)
            let d = cal.component(.day, from: ev.eventDate)
            let relatedPhoto = ev.relatedPhotoID.flatMap { rid in photos.first { $0.id == rid } }
            let fallbackPhoto = photos.randomElement()
            let chosen = relatedPhoto ?? fallbackPhoto
            let path = chosen?.thumbnailPath.isEmpty == false ? chosen?.thumbnailPath : chosen?.uri
            return PinnedMemory(
                title: ev.title,
                note: ev.body,
                dateLabel: "RECENT · " + String(format: "%02d.%02d", m, d),
                photoPath: path
            )
        }

        // 回退：从全部照片中随机选一张（每次进入页面不同，增加新鲜感）
        guard let photo = photos.randomElement() else { return nil }
        let dateLabel: String
        if let takenAt = photo.takenAt {
            let cal = Calendar.current
            dateLabel = "RECENT · " + String(format: "%02d.%02d", cal.component(.month, from: takenAt), cal.component(.day, from: takenAt))
        } else {
            dateLabel = "RECENT"
        }
        let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
        return PinnedMemory(
            title: photo.note.isEmpty ? String(localized: "pet.profile.pinned.recent") : photo.note,
            note: "",
            dateLabel: dateLabel,
            photoPath: path
        )
    }

    private func pinnedMemorySection(_ pinned: PinnedMemory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section 标签（独立头部行，对照 #I319:1101;296:595）
            Text(String(localized: "pet.profile.pinned.section"))
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
                .padding(.horizontal, 24)

            // Fold index + 内容行（对照 #I319:1101;296:604-598）
            HStack(alignment: .top, spacing: 15) {
                // 左侧珊瑚竖线 4pt（panel x=16 起，对照 Pinned Fold Index #I319:1101;296:604）
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 4)
                    .cornerRadius(Radius.accentRail)

                VStack(alignment: .leading, spacing: 6) {
                    // 日期 overline（对照 #I319:1101;296:608）
                    Text(pinned.dateLabel)
                        .font(.editorialOverline)
                        .tracking(0.4)
                        .foregroundStyle(Color.milensActionPrimary)
                    // 文楷标题（对照 #I319:1101;296:597）
                    Text(pinned.title)
                        .font(.custom("LXGWWenKai-Regular", size: 16, relativeTo: .body))
                        .foregroundStyle(Color.milensTextPrimary)
                    // 正文（对照 #I319:1101;296:598）
                    if !pinned.note.isEmpty {
                        Text(pinned.note)
                            .font(.bodySecondary)
                            .foregroundStyle(Color.milensTextSecondary)
                    }
                }

                Spacer(minLength: 12)

                // 右侧缩略图 122×86（对照 Pinned Memory Photo #I319:1101;296:596）
                if let path = pinned.photoPath {
                    ThumbnailImage(path: path)
                        .scaledToFill()
                        .frame(width: 122, height: 86)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 24)
        }
    }

    // MARK: - 最近照片

    private var recentPhotosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "pet.profile.recentPhotos"))
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
                .padding(.horizontal, 24)

            HStack(spacing: 12) {
                ForEach(photos.prefix(3), id: \.id) { photo in
                    NavigationLink(value: Route.photoView(photoID: photo.id)) {
                        ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                            .scaledToFill()
                            .frame(width: 100, height: 86)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - 时间线入口

    /// 珊瑚色「查看完整生命时间线 →」+ baseline + arrow。
    /// 对照 #I319:1101;296:603-606。
    private func timelineLink(_ pet: Pet) -> some View {
        NavigationLink(value: Route.timeline) {
            HStack(spacing: 6) {
                Text(String(localized: "pet.profile.timelineLink"))
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensActionPrimary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: Sizing.iconSm, weight: .semibold))
                    .foregroundStyle(Color.milensActionPrimary)
            }
            .padding(.horizontal, 24)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(height: 1)
                    .padding(.leading, 152)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 继续记录入口（P3.6）

    /// 突出的主 CTA：鼓励用户补写记忆（Life-Archive-Design.md §3.3）。
    /// 使用 Focus Dial 风格的主动作按钮，呼应编辑式设计语言。
    private func continueRecordingEntry(_ pet: Pet) -> some View {
        FocusDialButton(
            label: String(localized: "pet.profile.continueRecording"),
            systemImage: "plus",
            isEnabled: true,
            action: { showAddMemorySheet = true }
        )
    }

    // MARK: - 照片分类网格（保留现有功能）

    private var hasPhotoContent: Bool {
        !photos.isEmpty || !unassignedPhotos.isEmpty
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Text(String(localized: "pet.profile.allPhotos"))
                    .font(.titleStandard)
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                if selectedCategory == .unassigned {
                    Text(String(localized: "pet.profile.unassignedHint"))
                        .font(.caption)
                        .foregroundStyle(Color.milensTextTertiary)
                        .multilineTextAlignment(.trailing)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(PetPhotoCategory.profileOrder) { category in
                        FilterChip(
                            title: category.title,
                            isSelected: selectedCategory == category,
                            count: PetPhotoCategoryLogic.count(
                                petPhotos: photos, unassigned: unassignedPhotos, category: category)
                        ) {
                            selectedCategory = category
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }

            let shown = PetPhotoCategoryLogic.filter(
                petPhotos: photos, unassigned: unassignedPhotos, category: selectedCategory)
            if shown.isEmpty {
                emptyCategoryView
            } else {
                LazyVGrid(columns: gridColumns, spacing: 2) {
                    ForEach(shown.prefix(9), id: \.id) { photo in
                        NavigationLink(value: Route.photoView(photoID: photo.id)) {
                            ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                                .clipShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .topTrailing) {
                            if PetPhotoCategoryLogic.isEditedPhoto(photo) {
                                Image(systemName: "paintbrush.pointed.fill")
                                    .font(.system(size: 10)) // ui-token:ok 网格角标小图标
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(Color.milensActionPrimary.opacity(0.85))
                                    .clipShape(Circle())
                                    .padding(4)
                            }
                        }
                        .contextMenu {
                            Button {
                                assignmentPhotos = [photo]
                            } label: {
                                Label(String(localized: "photo.assign.title"), systemImage: "person.crop.circle.badge.plus")
                            }
                        }
                    }
                }
                if shown.count > 9 {
                    NavigationLink(value: Route.gallery) {
                        Text(String(localized: "pet.profile.viewAll \(shown.count)"))
                            .font(.bodySecondary)
                            .foregroundStyle(Color.milensActionPrimary)
                    }
                }
            }
        }
    }

    private var emptyCategoryView: some View {
        VStack(spacing: Spacing.xs) {
            Text(selectedCategory == .all ? String(localized: "pet.profile.noPhotos") : String(localized: "pet.profile.noCategoryPhotos"))
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
            Text(selectedCategory == .unassigned
                 ? String(localized: "pet.profile.unassignedHintBody")
                 : String(localized: "pet.profile.worksHintBody"))
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    // MARK: - 备忘

    private var parsedNotes: [String] {
        PetFormLogic.parseNotesItems(pet?.notes ?? "")
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(String(localized: "pet.profile.importantEvents"))
                .font(.titleStandard)
                .foregroundStyle(Color.milensTextPrimary)
            ForEach(Array(parsedNotes.enumerated()), id: \.offset) { _, note in
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5)) // ui-token:ok 列表项目符号圆点
                        .foregroundStyle(Color.milensPrimary)
                    Text(note)
                        .font(.bodyPrimary)
                        .foregroundStyle(Color.milensTextPrimary)
                    Spacer()
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    // MARK: - 加载失败

    private var loadFailedView: some View {
        StateView(
            icon: "exclamationmark.triangle",
            title: String(localized: "pet.profile.loadFailed"),
            primaryActionTitle: String(localized: "common.back"),
            primaryAction: { dismiss() }
        )
    }

    // MARK: - 数据加载

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            pet = try factory.pet(id: petID)
            if let pet {
                do {
                    photos = try factory.photosByPet(pet)
                } catch {
                    photos = []
                    logger.error("load: 读取宠物照片失败（\(error.localizedDescription)）")
                }
            }
            do {
                unassignedPhotos = try factory.unassignedPhotos(limit: 200)
            } catch {
                unassignedPhotos = []
                logger.error("load: 读取未归属照片失败（\(error.localizedDescription)）")
            }
        } catch {
            pet = nil
        }
    }
}

#Preview {
    NavigationStack {
        PetProfileView(petID: UUID())
    }
}
