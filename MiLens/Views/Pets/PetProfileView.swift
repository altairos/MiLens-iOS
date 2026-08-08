//  PetProfileView —— 单只宠物档案详情（route .petProfile，对应源端 PetEditPage 头部展示 + 照片网格）。
//  传记式布局（UI-DESIGN.md §6.4）：顶部出血肖像大图（约屏高 40%）+ 名字浮于底部渐变，
//  统计（照片数/相处天数/年龄）、最近照片网格、备忘、编辑/时间线入口。
//  P3 实现（只读详情）；编辑走 .petEdit 路由，时间线走 .timeline 路由。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "PetProfile")

struct PetProfileView: View {
    let petID: UUID

    @Environment(\.petRepository) private var petRepo
    @Environment(\.photoRepository) private var photoRepo
    @Environment(\.dismiss) private var dismiss

    @State private var pet: Pet?
    @State private var photos: [Photo] = []
    @State private var isLoading = true

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
                                tagRow(pet)
                                statsRow(pet)
                                if !photos.isEmpty {
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
        .background(Color.milensBackground)
        .navigationTitle(pet?.name ?? "档案")
        .navigationBarTitleDisplayMode(.inline)
        // 出血肖像延伸到导航栏下方；滚出肖像后系统会恢复导航栏底色（iOS 17 行为）
        .toolbarBackground(.hidden, for: .navigationBar)
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

            // 底部渐变：透明 → 页面背景色，名字浮在渐变上保持对比
            LinearGradient(
                colors: [Color.milensBackground.opacity(0), Color.milensBackground],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(pet.name)
                .font(.displayLarge)
                .foregroundStyle(Color.milensTextPrimary)
                .padding(.horizontal, Spacing.pagePad)
                .padding(.bottom, Spacing.sm)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - 标签行

    private func tagRow(_ pet: Pet) -> some View {
        HStack(spacing: Spacing.sm) {
            tag(PetDisplayLogic.speciesDisplayName(pet.species))
            if pet.birthday != nil {
                tag(PetDisplayLogic.ageText(from: pet.birthday))
            }
            tag(PetDisplayLogic.genderDisplayName(pet.gender))
            Spacer()
        }
    }

    // MARK: - 统计行

    private func statsRow(_ pet: Pet) -> some View {
        HStack(spacing: 0) {
            statItem(value: "\(pet.photoCount)", label: "照片")
            divider
            statItem(value: "\(PetDisplayLogic.daysTogether(from: pet.adoptionDay))", label: "相处天数")
            divider
            statItem(
                value: pet.birthday != nil
                    ? PetDisplayLogic.ageText(from: pet.birthday) : "—",
                label: "年龄"
            )
        }
        .padding(Spacing.lg)
        .background(Color.milensCard)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
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

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("最近照片")
                .font(.titleStandard)
                .foregroundStyle(Color.milensTextPrimary)
            LazyVGrid(columns: photoColumns, spacing: 2) {
                ForEach(photos.prefix(9), id: \.id) { photo in
                    NavigationLink(value: Route.photoView(photoID: photo.id)) {
                        ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
            if photos.count > 9 {
                NavigationLink(value: Route.gallery) {
                    Text("查看全部 \(photos.count) 张")
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensPrimary)
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
        .background(Color.milensCard)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
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
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.milensTextSecondary)
            Text("档案加载失败")
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
            Button("返回") { dismiss() }
                .tint(Color.milensPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            pet = try petRepo.getPet(id: petID)
            if let pet {
                do {
                    photos = try photoRepo.getPhotosByPet(pet)
                } catch {
                    photos = []
                    logger.error("load: 读取宠物照片失败（\(error.localizedDescription)）")
                }
            }
        } catch {
            pet = nil
        }
    }
}
