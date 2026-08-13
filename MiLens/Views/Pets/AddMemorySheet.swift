//  AddMemorySheet —— 添加记忆表单（对照 Figma「09·添加记忆」#211:340）。
//  从 TimelineView 拆出（规模守卫，DESIGN.md §6 / AGENTS.md §3）。
//  Figma 表单布局：记忆类型 tab + Evidence Register（珊瑚 rail）+ 日期/照片/标题/正文 + 拨盘式 CTA。
//  保存后写入 PetEvent(sourceType="user")，进入时间线并可被编辑/取消置顶。

import SwiftUI

/// 添加一条记忆（对照 Figma「09·添加记忆」#211:340）。
/// Figma 表单布局：记忆类型 tab + Evidence Register（珊瑚 rail）+ 日期/照片/标题/正文 + 拨盘式 CTA。
/// 保存后写入 PetEvent(sourceType="user")，进入时间线并可被编辑/取消置顶。
struct AddMemorySheet: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: TimelineViewModel
    let pets: [Pet]
    let isPro: Bool
    let firstAccessDate: Date?
    /// 预填充关联照片 ID（从照片详情页进入时传入）。
    var prefilledPhotoID: UUID? = nil

    @State private var selectedPetID: UUID?
    @State private var title = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var isPinned = false
    @State private var relatedPhotoID: UUID? = nil
    @State private var selectedType: MemoryType = .photo

    enum MemoryType: String, CaseIterable {
        case photo, text, date, work
        var labelKey: String {
            switch self {
            case .photo: return "memory.type.photo"
            case .text: return "memory.type.text"
            case .date: return "memory.type.date"
            case .work: return "memory.type.work"
            }
        }
    }

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

    private let dateRange: ClosedRange<Date> = Date.milensEpochStart...Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // 宠物选择
                    if !pets.isEmpty {
                        petSelector
                    }

                    // 记忆类型 tab（对照 Figma #211:347-354 + #333:692-694）
                    typeTabBar

                    // Evidence Register（珊瑚 rail + 日期 + 照片）
                    evidenceRegister

                    // 标题输入框（珊瑚 rail + 白底圆角）
                    titleField

                    // 正文输入框（珊瑚 rail + 字数计数）
                    noteField

                    // 底部提示
                    archiveHint

                    // 错误提示
                    if !viewModel.addMemoryError.isEmpty {
                        Label(viewModel.addMemoryError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.milensDanger)
                            .font(.caption)
                    }
                }
                .padding(.horizontal, Spacing.pagePad)
                .padding(.bottom, 100) // 给 CTA 留空
            }
            .scrollIndicators(.hidden)
            .background(Color.milensBackground)
            .navigationTitle(String(localized: "timeline.addMemory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(String(localized: "memory.draft"))
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                ctaButton
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.milensBackground)
            }
            .onAppear {
                if selectedPetID == nil { selectedPetID = pets.first?.id }
                if let prefilledPhotoID { relatedPhotoID = prefilledPhotoID }
            }
        }
        .modalContentWidth()
    }

    // MARK: - 宠物选择

    private var petSelector: some View {
        Picker(String(localized: "timeline.addMemory.pet"), selection: $selectedPetID) {
            ForEach(pets, id: \.id) { pet in
                Text("\(PetProfileLogic.speciesEmoji(pet.species)) \(pet.name)")
                    .tag(Optional(pet.id))
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: - 记忆类型 tab

    private var typeTabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(MemoryType.allCases, id: \.rawValue) { type in
                    typeTabItem(type)
                }
            }
            // baseline + 选中标记（对照 #333:692-694）
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(height: 1)
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 88, height: 3)
                    .offset(x: CGFloat(MemoryType.allCases.firstIndex(of: selectedType) ?? 0) * 88)
            }
        }
    }

    private func typeTabItem(_ type: MemoryType) -> some View {
        let isSelected = selectedType == type
        return Button {
            withAnimation(.easeInOut(duration: Motion.durationFast)) {
                selectedType = type
            }
        } label: {
            Text(String(localized: String.LocalizationValue(type.labelKey)))
                .font(.bodySecondary)
                .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextPrimary)
                .frame(width: 88, height: 36)
                .background(isSelected ? Color.milensAccentSoft : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Evidence Register（日期 + 照片，珊瑚 rail，对照 Figma #211:356-362 + #333:696）

    private var evidenceRegister: some View {
        HStack(spacing: 0) {
            // 珊瑚 rail（3pt）
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 0) {
                // 发生时间行（对照 #211:356-358）
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "memory.occurredAt"))
                            .font(.editorialMetadata)
                            .foregroundStyle(Color.milensTextSecondary)
                        DatePicker(
                            "",
                            selection: $date, in: dateRange,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .font(.bodyPrimary)
                        .foregroundStyle(Color.milensTextPrimary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: Sizing.iconSm))
                        .foregroundStyle(Color.milensTextSecondary)
                }
                .padding(.leading, 14)
                .padding(.trailing, 14)
                .padding(.vertical, 16)

                Divider().padding(.leading, 14)

                // 照片证据区（对照 #211:360-365）
                if !candidatePhotos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "memory.photoEvidence"))
                            .font(.editorialMetadata)
                            .foregroundStyle(Color.milensTextSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(candidatePhotos.prefix(10), id: \.id) { photo in
                                    let isSelected = relatedPhotoID == photo.id
                                    let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
                                    Button {
                                        relatedPhotoID = isSelected ? nil : photo.id
                                    } label: {
                                        ThumbnailImage(path: path)
                                            .frame(width: 92, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(Color.milensActionPrimary, lineWidth: isSelected ? 2 : 0)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                                // 添加按钮
                                Button {
                                    relatedPhotoID = nil
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.system(size: Sizing.iconMd))
                                            .foregroundStyle(Color.milensTextSecondary)
                                        Text(String(localized: "memory.addMore"))
                                            .font(.editorialMetadata)
                                            .foregroundStyle(Color.milensTextSecondary)
                                    }
                                    .frame(width: 92, height: 80)
                                    .background(Color.milensCard)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.milensBorder, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 14)
                    .padding(.bottom, 16)
                }
            }
            .background(Color.milensCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.leading, -1) // rail 贴左缘
        }
    }

    // MARK: - 标题输入框

    private var titleField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(String(localized: "memory.titleLabel"))
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
            TextField(
                String(localized: "timeline.addMemory.titlePlaceholder"),
                text: $title
            )
            .font(.bodyPrimary)
            .foregroundStyle(Color.milensTextPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .background(Color.milensCard)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.milensBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - 正文输入框

    private var noteField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(String(localized: "memory.bodyLabel"))
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
            ZStack(alignment: .bottomTrailing) {
                TextField(
                    String(localized: "timeline.addMemory.bodyPlaceholder"),
                    text: $note, axis: .vertical
                )
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextPrimary)
                .lineLimit(2...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)

                // 字数计数（对照 #211:372）
                Text("\(note.count) / 300")
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.trailing, 14)
                    .padding(.bottom, 8)
            }
            .background(Color.milensCard)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.milensBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - 底部提示

    private var archiveHint: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.milensActionPrimary)
                .frame(width: 6, height: 6)
            Text(String(localized: "memory.archiveHint"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextSecondary)
            Spacer()
        }
    }

    // MARK: - 拨盘式 CTA（对照 Figma #267:296）

    private var ctaButton: some View {
        Button { submit() } label: {
            HStack {
                Text(String(localized: "memory.saveToPet \(selectedPet?.name ?? "")"))
                    .font(.buttonLabel)
                    .foregroundStyle(Color.milensDarkroomText)
                Spacer()
                // 暗色拨盘圆
                ZStack {
                    Circle()
                        .fill(Color.milensDialSurface)
                        .frame(width: 44, height: 44)
                    Circle()
                        .stroke(Color.milensDarkroomText, lineWidth: 1)
                        .frame(width: 44, height: 44)
                    Image(systemName: "checkmark")
                        .font(.system(size: Sizing.iconMd, weight: .bold))
                        .foregroundStyle(Color.milensDarkroomText)
                }
            }
            .padding(.leading, 24)
            .padding(.trailing, 7)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(canSubmit ? Color.milensActionPrimary : Color.milensTextTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
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
