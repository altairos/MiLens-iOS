//  PetProfileView —— 单只宠物档案详情（route .petProfile，对应源端 PetEditPage 头部展示 + 照片网格）。
//  传记式布局（UI-DESIGN.md §6.4）：顶部出血肖像大图（约屏高 40%）+ 名字浮于底部渐变，
//  统计（照片数/相处天数/年龄）、最近照片网格、备忘、编辑/时间线入口。
//  P3 实现（只读详情）；编辑走 .petEdit 路由，时间线走 .timeline 路由。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "PetProfile")

struct PetProfileView: View {
    let petID: UUID

    @Environment(\.viewModelFactory) private var factory
    @Environment(\.dismiss) private var dismiss

    @State private var pet: Pet?
    @State private var photos: [Photo] = []
    @State private var unassignedPhotos: [Photo] = []
    @State private var selectedCategory: PetPhotoCategory = .all
    @State private var isLoading = true
    /// 手动归属 sheet 的照片列表（非空=显示 sheet）
    @State private var assignmentPhotos: [Photo] = []

    private let photoColumns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let pet {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            heroSection(pet, height: proxy.size.height * 0.4)
                            VStack(spacing: Spacing.xxl) {
                                profileHeader(pet)
                                statsRow(pet)
                                storySection(pet)
                                if hasPhotoContent {
                                    photosSection
                                }
                                if !parsedNotes.isEmpty {
                                    notesSection
                                }
                                actionButtons(pet)
                            }
                            .padding(.horizontal, Spacing.pagePad)
                            .padding(.top, Spacing.lg)
                            .padding(.bottom, Spacing.md)
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            } else {
                loadFailedView
            }
        }
        .background(Color.milensPaper)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: Binding(
            get: { !assignmentPhotos.isEmpty },
            set: { if !$0 { assignmentPhotos.removeAll() } }
        )) {
            if !assignmentPhotos.isEmpty {
                PetAssignmentSheet(photos: assignmentPhotos) {
                    // 归属变更后重新加载（本宠物照片/待整理列表/计数均可能变化）
                    Task { await load() }
                }
            }
        }
        .task { await load() }
    }

    // MARK: - 出血肖像

    /// 肖像数据源：avatarPath 非空用头像，否则回退最近一张照片，再回退物种占位（不伪造图像）。
    private var portraitPath: String? {
        guard let pet else { return nil }
        if !pet.avatarPath.isEmpty { return pet.avatarPath }
        guard let latest = photos.first else { return nil }
        return latest.thumbnailPath.isEmpty ? latest.uri : latest.thumbnailPath
    }

    private func heroSection(_ pet: Pet, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let path = portraitPath {
                ThumbnailImage(path: path)
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Color.milensAccentSoft
                Text(PetProfileLogic.speciesEmoji(pet.species))
                    .font(.system(size: 72))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack {
                HStack {
                    Text("肖像 1 / 4")
                    Spacer()
                    Text("编辑")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.xxl)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .ignoresSafeArea(edges: .top)
    }

    private func profileHeader(_ pet: Pet) -> some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            Text(pet.name)
                .font(.editorialSection)
                .foregroundStyle(Color.milensTextPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: Spacing.sm)

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(String(localized: "pet.profile.speciesAge \(PetDisplayLogic.speciesDisplayName(pet.species)) \(pet.birthday != nil ? PetDisplayLogic.ageText(from: pet.birthday) : "—")"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                Text(String(localized: "pet.card.daysHome \(PetDisplayLogic.daysTogether(from: pet.adoptionDay))"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
            }
        }
    }

    // MARK: - 标签行

    private func tagRow(_ pet: Pet) -> some View {
        EmptyView()
    }

    // MARK: - 统计行

    private func statsRow(_ pet: Pet) -> some View {
        HStack(spacing: 0) {
            statItem(value: "\(pet.photoCount)", label: "照片")
            divider
            statItem(value: "\(PetDisplayLogic.daysTogether(from: pet.adoptionDay))", label: String(localized: "pet.profile.daysLabel"))
            divider
            statItem(
                value: pet.birthday != nil
                    ? PetDisplayLogic.ageText(from: pet.birthday) : "—",
                label: "年龄"
            )
        }
        .padding(.vertical, Spacing.md)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.milensBorder)
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.milensBorder)
                .frame(height: 1)
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(.numberStat)
                .foregroundStyle(Color.milensTextPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.milensTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.milensSeparator)
            .frame(width: 0.5, height: 32)
    }

    // MARK: - 照片网格

    /// 任一分类有照片即展示照片区（全部/作品为空时，待整理可能仍有内容）。
    private var hasPhotoContent: Bool {
        !photos.isEmpty || !unassignedPhotos.isEmpty
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Text("照片")
                    .font(.titleStandard)
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                if selectedCategory == .unassigned {
                    Text("尚未归属宠物的照片")
                        .font(.caption)
                        .foregroundStyle(Color.milensTextTertiary)
                        .multilineTextAlignment(.trailing)
                }
            }

            // 分类分段：全部照片 / 待整理 / 作品（UI-DESIGN.md §6.4，可靠维度）
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
                LazyVGrid(columns: photoColumns, spacing: 2) {
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
                        Text("查看全部 \(shown.count) 张")
                            .font(.bodySecondary)
                            .foregroundStyle(Color.milensActionPrimary)
                    }
                }
            }
        }
    }

    private var emptyCategoryView: some View {
        VStack(spacing: Spacing.xs) {
            Text(selectedCategory == .all ? "还没有照片" : "这个分类还没有照片")
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
            Text(selectedCategory == .unassigned
                 ? "在相册中导入或扫描照片后，尚未归属宠物的照片会出现在这里。"
                 : "在图片编辑器中保存过的照片，会出现在这里。")
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    private func storySection(_ pet: Pet) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("它的故事")
                    .font(.editorialSection)
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                Text("\(Calendar.current.component(.year, from: pet.createdAt))—现在")
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
            }

            if parsedNotes.isEmpty {
                Text("这些照片，构成了它来到你身边后的全部档案。")
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
            } else {
                ForEach(Array(parsedNotes.prefix(3).enumerated()), id: \.offset) { index, note in
                    HStack(alignment: .top, spacing: Spacing.md) {
                        Text("\(Calendar.current.component(.year, from: pet.createdAt) + index)")
                            .font(.editorialNumber)
                            .foregroundStyle(Color.milensCopper)
                            .frame(width: 64, alignment: .leading)
                        Rectangle()
                            .fill(Color.milensBorder)
                            .frame(width: 1)
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(index == 0 ? String(localized: "pet.profile.daysHomeTitle") : String(localized: "pet.profile.memoryTitle"))
                                .font(.bodyPrimary.weight(.semibold))
                                .foregroundStyle(Color.milensTextPrimary)
                            Text(note)
                                .font(.bodySecondary)
                                .foregroundStyle(Color.milensTextSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
    }

    // MARK: - 备忘

    private var parsedNotes: [String] {
        PetFormLogic.parseNoteItems(pet?.notes ?? "")
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("重要事件")
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
        .padding(Spacing.lg)
        .background(Color.milensPaper)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.milensBorder)
                .frame(height: 1)
        }
    }

    // MARK: - 操作按钮

    private func actionButtons(_ pet: Pet) -> some View {
        VStack(spacing: Spacing.md) {
            NavigationLink(value: Route.petEdit(petID: pet.id)) {
                Label("编辑档案", systemImage: "pencil")
                    .font(.buttonLabel)
                    .foregroundStyle(Color.milensTextOnActionPrimary)
                    .frame(maxWidth: .infinity, minHeight: Sizing.touchTarget)
                    .background(Color.milensActionPrimary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            NavigationLink(value: Route.timeline) {
                Label("成长时间线", systemImage: "calendar.badge.clock")
                    .font(.buttonLabel)
                    .foregroundStyle(Color.milensTextPrimary)
                    .frame(maxWidth: .infinity, minHeight: Sizing.touchTarget)
                    .overlay {
                        Capsule().stroke(Color.milensBorder, lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 加载失败

    private var loadFailedView: some View {
        // 复用统一状态组件（UI-DESIGN.md §5.3.9）：图标 + 标题 + 明确退出路径。
        StateView(
            icon: "exclamationmark.triangle",
            title: String(localized: "pet.profile.loadFailed"),
            primaryActionTitle: String(localized: "common.back"),
            primaryAction: { dismiss() }
        )
    }

    // MARK: - 辅助

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color.milensTextSecondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(Color.milensGrouped)
            .clipShape(Capsule())
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
            // 待整理分类：未归属宠物的照片（失败时置空，不阻断档案展示）
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
