//  BeadPhotoPickerView —— 拼豆流程的选照片页（CreateView 作品列表入口进入）。
//  对照 Workshop 编辑式导航头 + 编辑式网格（与 02 Picker 统一风格）。
//  点击照片进入拼豆工作室（BeadPatternView）。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "Create")

struct BeadPhotoPickerView: View {
    @Environment(\.viewModelFactory) private var factory
    @Environment(\.dismiss) private var dismiss

    @State private var photos: [Photo] = []
    @State private var isLoading = true

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 9)]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Color.milensActionPrimary)
            } else if photos.isEmpty {
                emptyState
            } else {
                photoGrid
            }
        }
        .background(Color.milensBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadPhotos() }
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 0) {
            WorkshopNavHeader(title: String(localized: "picker.bead.title")) { dismiss() }
            ContentUnavailableView(
                String(localized: "picker.bead.empty"),
                systemImage: "photo.on.rectangle.angled",
                description: Text(String(localized: "picker.bead.emptyDesc"))
            )
        }
    }

    // MARK: - 照片网格

    private var photoGrid: some View {
        VStack(spacing: 0) {
            WorkshopNavHeader(title: String(localized: "picker.bead.title")) { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(localized: "picker.bead.fromArchive"))
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.md)

                    LazyVGrid(columns: columns, spacing: 9) {
                        ForEach(photos) { photo in
                            NavigationLink(value: Route.beadPattern(photoID: photo.id)) {
                                ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                                    .aspectRatio(108.0 / 100.0, contentMode: .fill)
                                    .frame(width: 108, height: 100)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "a11y.bead.generate"))
                        }
                    }
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xxl)
                }
            }
            .scrollIndicators(.hidden)
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
