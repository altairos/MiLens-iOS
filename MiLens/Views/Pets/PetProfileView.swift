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

    /// 是否处于 regular 宽度（iPad 竖屏 / 大尺寸横屏），启用双栏分栏。
    private var isRegularWidth: Bool { hSizeClass == .regular }

    @State private var pet: Pet?
    @State private var photos: [Photo] = []
    @State private var unassignedPhotos: [Photo] = []
    @State private var selectedCategory: PetPhotoCategory = .all
    @State private var isLoading = true
    @State private var assignmentPhotos: [Photo] = []

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
                    portraitHero(pet, height: 315)

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
                    portraitHero(pet, height: 700)
                    continuityNote(pet)
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
                    timelineContinuation(pet)
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

    // MARK: - Archive Continuity Note（对照 #307:680-684）

    /// 左列底部的生命档案连续性标语：LIFE 编号 + 文楷引言 + 说明 + 基线。
    private func continuityNote(_ pet: Pet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LIFE 02 · \(PetDisplayLogic.daysTogether(from: pet.adoptionDay)) DAYS")
                .font(.custom("Jacques Francois", size: 10))
                .tracking(0.4)
                .foregroundStyle(Color.milensActionPrimary)
            Text("将散落的记忆，\n装订成流动的时间之河")
                .font(.custom("LXGWWenKai-Regular", size: 28, relativeTo: .title2))
                .foregroundStyle(Color.milensTextPrimary)
            Text("从第一张照片、第一次出门，到每天微小的变化；所有片段都回到它发生的时间里。")
                .font(.system(size: 14))
                .foregroundStyle(Color.milensTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(Color.milensBorder)
                .frame(width: 180, height: 1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 24)
        .padding(.top, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Timeline Continuation 卡片（对照 #307:715-721）

    /// 右列底部的时间线续页卡片：下一页日期 + 标题 + 副文 + 打开链接。
    private func timelineContinuation(_ pet: Pet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEXT LEAF · 2026.06")
                .font(.custom("Jacques Francois", size: 10))
                .tracking(0.4)
                .foregroundStyle(Color.milensActionPrimary)
            Text("06. 18")
                .font(.custom("Fraunces-Semibold", size: 34))
                .foregroundStyle(Color.milensTextPrimary)
            Text("夏天开始前的傍晚")
                .font(.custom("LXGWWenKai-Regular", size: 20))
                .foregroundStyle(Color.milensTextPrimary)
            Text("一条风很大的路，一次主动跑进海水里的勇气。")
                .font(.system(size: 13))
                .foregroundStyle(Color.milensTextSecondary)
            Rectangle()
                .fill(Color.milensBorder)
                .frame(height: 1)
            NavigationLink(value: Route.timeline) {
                HStack(spacing: 4) {
                    Text("打开完整生命时间线")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.milensActionPrimary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.milensActionPrimary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.milensCard)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - 出血肖像 Hero

    /// 肖像大图 + 底部渐变 + 文楷名字 + 副标题 + More 按钮。
    /// - Parameter height: Hero 高度（iPhone 315pt / iPad 700pt）。
    private func portraitHero(_ pet: Pet, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            // 大图 / 占位
            if let path = portraitPath {
                ThumbnailImage(path: path)
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
            } else {
                Color.milensAccentSoft
                    .frame(height: height)
                    .overlay(
                        Text(PetProfileLogic.speciesEmoji(pet.species))
                            .font(.system(size: 72))
                    )
            }

            // 底部渐变（对照 Portrait Gradient #319:1097）
            LinearGradient(
                colors: [Color.black.opacity(0), Color.milensHeroGradientEnd.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: min(height * 0.54, 330))
            .frame(maxHeight: .infinity, alignment: .bottom)

            // 名字 + 副标题（对照 #319:1099-1100）
            VStack(alignment: .leading, spacing: 4) {
                Text(pet.name)
                    .font(.custom("LXGWWenKai-Regular", size: height > 400 ? 42 : 38,
                                  relativeTo: .largeTitle))
                    .foregroundStyle(.white)
                Text(petSubtitle(pet))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.leading, 28)
            .padding(.bottom, height > 400 ? 32 : 16)

            // 右上角 More Action 按钮（对照 #319:1098）
            VStack {
                HStack {
                    Spacer()
                    Menu {
                        NavigationLink(value: Route.petEdit(petID: pet.id)) {
                            Label(String(localized: "pet.profile.edit"), systemImage: "pencil")
                        }
                    } label: {
                        Circle()
                            .fill(.white)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.milensInk)
                            )
                    }
                }
                Spacer()
            }
            .padding(.trailing, 20)
            .padding(.top, height > 400 ? 48 : 56)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height > 400 ? 28 : 0, style: .continuous))
    }

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

    /// 浮起覆盖面板：Eyebrow + Intro + 四列统计 + 置顶记忆 + 最近照片 + 时间线入口。
    /// 对照 Figma #319:1101（Surface/Archive Panel，32px 圆角）。
    private func archivePanel(_ pet: Pet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow + Intro（对照 #I319:1101;296:588-589）
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "pet.profile.eyebrow"))
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(Color.milensActionPrimary)
                Text(String(localized: "pet.profile.intro"))
                    .font(.system(size: 15))
                    .foregroundStyle(Color.milensTextSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)

            // 四列统计（对照 Archive Stat #I319:1101;296:617-626）
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

            // 时间线入口（对照 #I319:1101;296:603-606）
            timelineLink(pet)
                .padding(.top, 20)
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

    // MARK: - 四列统计

    private func archiveStatsRow(_ pet: Pet) -> some View {
        let workCount = photos.filter { PetPhotoCategoryLogic.isEditedPhoto($0) }.count
        let memoryCount = pet.events.count

        return HStack(spacing: 0) {
            archiveStatItem(value: "\(pet.photoCount)", label: String(localized: "pet.profile.stat.photos"))
            archiveStatItem(value: "\(memoryCount)", label: String(localized: "pet.profile.stat.memories"))
            archiveStatItem(value: "\(PetDisplayLogic.daysTogether(from: pet.adoptionDay))", label: String(localized: "pet.profile.stat.days"))
            archiveStatItem(value: "\(workCount)", label: String(localized: "pet.profile.stat.works"))
        }
        .padding(.horizontal, 24)
    }

    private func archiveStatItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.milensTextPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.milensTextSecondary)
        }
        .frame(maxWidth: .infinity)
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.milensTextSecondary)
                .padding(.horizontal, 24)

            // Fold index + 内容行（对照 #I319:1101;296:604-598）
            HStack(alignment: .top, spacing: 15) {
                // 左侧珊瑚竖线 4pt（panel x=16 起，对照 Pinned Fold Index #I319:1101;296:604）
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 4)
                    .cornerRadius(2)

                VStack(alignment: .leading, spacing: 6) {
                    // 日期 overline（对照 #I319:1101;296:608）
                    Text(pinned.dateLabel)
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.4)
                        .foregroundStyle(Color.milensActionPrimary)
                    // 文楷标题（对照 #I319:1101;296:597）
                    Text(pinned.title)
                        .font(.custom("LXGWWenKai-Regular", size: 16, relativeTo: .body))
                        .foregroundStyle(Color.milensTextPrimary)
                    // 正文（对照 #I319:1101;296:598）
                    if !pinned.note.isEmpty {
                        Text(pinned.note)
                            .font(.system(size: 13))
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
                .font(.system(size: 12, weight: .medium))
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.milensActionPrimary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
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
                                    .font(.system(size: 10))
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
                        .font(.system(size: 5))
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
