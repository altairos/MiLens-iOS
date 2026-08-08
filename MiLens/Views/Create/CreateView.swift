//  创作（Tab 3）—— 拼豆图纸入口（P4）。
//  从已导入照片中选择，进入拼豆生成流程（BeadPatternView）；
//  宠物卡片生成待 P4 后续（依赖 AI 方案定案）。

import SwiftUI

struct CreateView: View {
    @Environment(\.photoRepository) private var photoRepo

    @State private var photos: [Photo] = []
    @State private var isLoading = true

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if photos.isEmpty {
                emptyState
            } else {
                photoGrid
            }
        }
        .navigationTitle(String(localized: "tab.create"))
        .navigationBarTitleDisplayMode(.large)
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
            VStack(alignment: .leading, spacing: 8) {
                Text("选择照片生成拼豆图纸")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
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
            .padding(.bottom, 16)
        }
    }

    // MARK: - 数据

    @MainActor
    private func loadPhotos() async {
        defer { isLoading = false }
        photos = (try? photoRepo.getPhotosPage(offset: 0, limit: 200)) ?? []
    }
}
