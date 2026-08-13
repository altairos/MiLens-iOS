//  GrowthComparePhotoPickerView —— 成长对比卡片的选照片页。
//  对照 Figma「02 · Picker / Source Pair」#422:809：
//  编辑式导航头 + 编辑式标题 + A/B 角色双选区 + 宠物筛选 + 照片网格 + CreationActionBar。
//  选中两张后顶部出现 Earlier/Recent 角色卡，点击已选照片可重新指定角色。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "GrowthCompare")

struct GrowthComparePhotoPickerView: View {
    @Environment(\.viewModelFactory) private var factory
    @Environment(\.dismiss) private var dismiss

    @State private var photos: [Photo] = []
    @State private var isLoading = true
    /// 已选中的照片 ID（最多 2 张，顺序 = 选择顺序）。
    @State private var selectedIDs: [UUID] = []

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 9)]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Color.milensActionPrimary)
            } else if photos.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .background(Color.milensBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadPhotos() }
    }

    // MARK: - 主内容

    private var content: some View {
        VStack(spacing: 0) {
            WorkshopNavHeader(title: String(localized: "picker.compare.title")) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 编辑式标题
                    Text(String(localized: "picker.compare.headline"))
                        .font(.editorialSection)
                        .foregroundStyle(Color.milensTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.md)

                    // A/B 角色双选区（选满 2 张时出现）
                    if selectedIDs.count == 2 {
                        pairedSelectionRow
                            .padding(.horizontal, Spacing.pagePad)
                            .padding(.top, Spacing.lg)
                    }

                    // 从生命档案选择 + 筛选条
                    Text(String(localized: "picker.compare.fromArchive"))
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.xl)

                    filterRow
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.xs)

                    // 照片网格
                    LazyVGrid(columns: columns, spacing: 9) {
                        ForEach(photos) { photo in
                            photoCell(photo)
                        }
                    }
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.sm)

                    if selectedIDs.count == 2 {
                        Text(String(localized: "picker.compare.hint"))
                            .font(.editorialMetadata)
                            .foregroundStyle(Color.milensTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.horizontal, Spacing.pagePad)
                            .padding(.top, Spacing.md)
                    }

                    Spacer(minLength: 100)
                }
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                if selectedIDs.count == 2 {
                    bottomActionBar
                }
            }
        }
    }

    // MARK: - A/B 角色双选区

    /// 选中两张后，横向展示 Earlier / Recent 两个角色卡 + 中间交换图标。
    private var pairedSelectionRow: some View {
        let pair = selectedPhotos()
        let earlier = pair.0
        let recent = pair.1
        return HStack(spacing: 0) {
            roleCard(photo: earlier, role: .earlier)
            Spacer()
            // 交换图标
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: Sizing.iconSm))
                .foregroundStyle(Color.milensTextTertiary)
                .frame(width: 20, height: 20)
            Spacer()
            roleCard(photo: recent, role: .recent)
        }
    }

    private func roleCard(photo: Photo, role: SelectionRole) -> some View {
        let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
        return VStack(alignment: .leading, spacing: 0) {
            ThumbnailImage(path: path)
                .aspectRatio(contentMode: .fill)
                .frame(width: 140, height: 150)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    Text(role == .earlier ? String(localized: "picker.role.earlier") : String(localized: "picker.role.recent"))
                        .font(.editorialOverline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.milensActionPrimary)
                        .clipShape(Capsule())
                        .padding(6)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(role == .earlier ? "A" : "B")
                    .font(.editorialNumberIndex)
                    .foregroundStyle(Color.milensActionPrimary)
                Text(photo.pet?.name ?? String(localized: "picker.compare.fromArchive"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(1)
                Text(formatDate(photo.takenAt))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .frame(width: 140)
        .background(Color.milensCard)
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.milensActionPrimary, lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .onTapGesture {
            swapRoles()
        }
    }

    private enum SelectionRole { case earlier, recent }

    // MARK: - 筛选条

    private var filterRow: some View {
        HStack(spacing: 24) {
            filterChip(label: String(localized: "picker.filter.all"), isActive: true)
            ForEach(petFilters.prefix(3), id: \.id) { pet in
                filterChip(label: pet.name, isActive: false)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private func filterChip(label: String, isActive: Bool) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.bodySecondary)
                .foregroundStyle(isActive ? Color.milensActionPrimary : Color.milensTextSecondary)
            Rectangle()
                .fill(isActive ? Color.milensActionPrimary : Color.clear)
                .frame(width: 25, height: 2)
        }
    }

    /// 网格中出现的宠物列表（用于筛选条展示）。
    private var petFilters: [Pet] {
        let seen = Set<UUID>()
        return photos.compactMap { p -> Pet? in
            guard let pet = p.pet, !seen.contains(pet.id) else { return nil }
            seen.insert(pet.id)
            return pet
        }
    }

    // MARK: - 照片单元

    @ViewBuilder
    private func photoCell(_ photo: Photo) -> some View {
        let order = selectedIDs.firstIndex(of: photo.id)
        let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
        Button {
            toggleSelection(photo.id)
        } label: {
            ThumbnailImage(path: path)
                .aspectRatio(108.0 / 100.0, contentMode: .fill)
                .frame(width: 108, height: 100)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                    if let order {
                        // A/B 角标
                        Text(order == 0 ? "A" : "B")
                            .font(.editorialNumberIndex)
                            .foregroundStyle(.white)
                            .frame(width: 23, height: 15)
                            .background(Color.milensActionPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(3)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部操作栏

    private var bottomActionBar: some View {
        let pair = selectedPhotos()
        let petID = pair.0.pet?.id ?? pair.1.pet?.id
        return NavigationLink(value: Route.growthCompare(
            earlyPhotoID: pair.0.id,
            latePhotoID: pair.1.id,
            petID: petID
        )) {
            CreationActionBar(
                primaryLabel: String(localized: "picker.compare.start"),
                secondaryLabel: String(localized: "picker.compare.clear"),
                primaryAction: { /* NavigationLink 处理导航 */ },
                secondaryAction: { selectedIDs.removeAll() },
                primaryEnabled: true
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            selectedIDs.removeAll()
        })
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
        .background(Color.milensBackground)
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            WorkshopNavHeader(title: String(localized: "picker.compare.title")) {
                dismiss()
            }
            ContentUnavailableView(
                String(localized: "picker.compare.empty"),
                systemImage: "photo.on.rectangle.angled",
                description: Text(String(localized: "picker.compare.emptyDesc"))
            )
        }
    }

    // MARK: - 选择逻辑

    private func toggleSelection(_ id: UUID) {
        if let idx = selectedIDs.firstIndex(of: id) {
            selectedIDs.remove(at: idx)
        } else if selectedIDs.count < 2 {
            selectedIDs.append(id)
        } else {
            // 已选 2 张，替换最早选的一张
            selectedIDs.removeFirst()
            selectedIDs.append(id)
        }
    }

    /// 交换 A/B 角色（点击角色卡时触发）。
    private func swapRoles() {
        guard selectedIDs.count == 2 else { return }
        selectedIDs.reverse()
    }

    /// 按拍摄时间返回早/晚两张照片。
    private func selectedPhotos() -> (Photo, Photo) {
        let pair = photos.filter { selectedIDs.contains($0.id) }
        guard pair.count == 2 else {
            return (photos[0], photos[0])
        }
        let sorted = pair.sorted { $0.takenAt < $1.takenAt }
        return (sorted[0], sorted[1])
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy.MM.dd"
        return fmt.string(from: date)
    }

    // MARK: - 数据

    @MainActor
    private func loadPhotos() async {
        defer { isLoading = false }
        do {
            photos = try factory.photoList(limit: 200)
        } catch {
            logger.error("loadPhotos: 读取照片列表失败（\(error.localizedDescription)）")
            photos = []
        }
    }
}

#Preview {
    NavigationStack {
        GrowthComparePhotoPickerView()
    }
}
