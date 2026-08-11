//  RedPacketCoverPickerView —— 微信红包封面的选照片页（创作 Tab 新增项目）。
//  从 CreateView「红包封面」入口进入；选一张照片作为封面主体 → 进入 RedPacketCoverView。
//  沿用 PetCardPhotoPickerView 单选模式；选宠物后取其名字做封面简称。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "RedPacket")

struct RedPacketCoverPickerView: View {
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
        .navigationTitle("选择封面照片")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPhotos() }
    }

    // MARK: - 空态

    private var emptyState: some View {
        ContentUnavailableView(
            "还没有照片",
            systemImage: "photo.on.rectangle.angled",
            description: Text("先到相册导入照片，再回来生成红包封面")
        )
    }

    // MARK: - 照片网格

    private var photoGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("选择一张竖版照片效果最好（微信红包封面为 957×1278）")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.xs)

                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos) { photo in
                        NavigationLink(value: Route.redPacketCover(
                            photoID: photo.id, petID: photo.pet?.id)) {
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
                        .accessibilityLabel("选择封面照片")
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
