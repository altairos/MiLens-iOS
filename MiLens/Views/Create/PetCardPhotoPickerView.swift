//  PetCardPhotoPickerView —— 宠物卡片的选照片页（CreateView 宠物卡片入口进入）。
//  照片网格沿用 BeadPhotoPickerView 模式；已归属宠物的照片显示宠物名角标，
//  点击照片进入卡片生成（PetCardView）。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "PetCard")

struct PetCardPhotoPickerView: View {
    @Environment(\.viewModelFactory) private var factory

    @State private var photos: [Photo] = []
    @State private var isLoading = true

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
        .navigationTitle("选择照片")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPhotos() }
    }

    // MARK: - 空态

    private var emptyState: some View {
        ContentUnavailableView(
            "还没有照片",
            systemImage: "photo.on.rectangle.angled",
            description: Text("先到相册导入照片，再回来生成宠物卡片")
        )
    }

    // MARK: - 照片网格

    private var photoGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(String(localized: "create.petCard.selectPhoto"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.xs)
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos) { photo in
                        NavigationLink(value: Route.petCard(photoID: photo.id)) {
                            ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 4))
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
                        .accessibilityLabel(String(localized: "a11y.petcard.generate"))
                    }
                }
            }
            .padding(.bottom, Spacing.lg)
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
