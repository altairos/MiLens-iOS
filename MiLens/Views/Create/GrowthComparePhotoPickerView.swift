//  GrowthComparePhotoPickerView —— 成长对比卡片的选照片页（ADR-0010 §3.3，Stage 2）。
//  从 CreateView「成长对比」入口进入；选两张照片（按拍摄时间自动判定早晚）。
//  选中两张后底部出现「生成对比卡」按钮 → 导航到 GrowthCompareView。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "GrowthCompare")

struct GrowthComparePhotoPickerView: View {
    @Environment(\.viewModelFactory) private var factory

    @State private var photos: [Photo] = []
    @State private var isLoading = true
    /// 已选中的照片 ID（最多 2 张）
    @State private var selectedIDs: Set<UUID> = []

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Color.milensPrimary)
            } else if photos.isEmpty {
                emptyState
            } else {
                photoGrid
            }
        }
        .background(Color.milensBackground)
        .navigationTitle("选择两张照片")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if selectedIDs.count == 2 {
                generateButton
            }
        }
        .task { await loadPhotos() }
    }

    // MARK: - 空态

    private var emptyState: some View {
        ContentUnavailableView(
            "还没有照片",
            systemImage: "photo.on.rectangle.angled",
            description: Text("先到相册导入照片，再回来生成成长对比卡片")
        )
    }

    // MARK: - 照片网格（双选）

    private var photoGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("选择同一宠物的两张不同时期照片")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.xs)

                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos) { photo in
                        photoCell(photo)
                    }
                }
            }
            .padding(.bottom, Spacing.xxl)
        }
    }

    @ViewBuilder
    private func photoCell(_ photo: Photo) -> some View {
        let isSelected = selectedIDs.contains(photo.id)
        Button {
            toggleSelection(photo.id)
        } label: {
            ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.milensActionPrimary, lineWidth: 3)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.milensActionPrimary)
                            .background(Circle().fill(.white))
                            .padding(6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let pet = photo.pet, !pet.name.isEmpty {
                        Text(pet.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(.black.opacity(0.55))
                            .clipShape(Capsule())
                            .padding(Spacing.xs)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "已选择" : "选择照片")
    }

    // MARK: - 生成按钮

    private var generateButton: some View {
        let selected = photos.filter { selectedIDs.contains($0.id) }
        let petID = selected.first?.pet?.id
        return NavigationLink(value: Route.growthCompare(
            earlyPhotoID: selected[0].id,
            latePhotoID: selected[1].id,
            petID: petID
        )) {
            Text("生成成长对比卡")
                .font(.bodyPrimary.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(Color.milensActionPrimary)
                .clipShape(Capsule())
                .padding(.horizontal, Spacing.pagePad)
                .padding(.bottom, Spacing.md)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            selectedIDs.removeAll()
        })
    }

    // MARK: - 选择逻辑

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else if selectedIDs.count < 2 {
            selectedIDs.insert(id)
        } else {
            // 已选 2 张，替换最早选的一张
            let first = selectedIDs.first!
            selectedIDs.remove(first)
            selectedIDs.insert(id)
        }
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
