//  BeadPhotoPickerView —— 拼豆流程的选照片页（CreateView 作品列表入口进入）。
//  照片网格能力沿用原 CreateView：点击照片进入拼豆工作室（BeadPatternView）。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "Create")

struct BeadPhotoPickerView: View {
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
            description: Text("先到相册导入照片，再回来生成拼豆图纸")
        )
    }

    // MARK: - 照片网格

    private var photoGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("选择照片生成拼豆图纸")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.xs)
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos) { photo in
                        NavigationLink(value: Route.beadPattern(photoID: photo.id)) {
                            ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("生成拼豆图纸")
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
