//  RedPacketPhotoPickerView —— 红包照片选择页（对应红包封面开发计划 §2.2）。
//
//  从相册选择宠物照片，选中后直接进入工作室（工作室负责 Vision 抠图）。
//  替换旧的 RedPacketCoverPickerView。

import SwiftUI
import UIKit
import MiLensKit
import os

private let logger = Logger(subsystem: "com.milens.app", category: "RedPacketPhotoPicker")

struct RedPacketPhotoPickerView: View {
    let templateID: String

    @Environment(\.viewModelFactory) private var factory
    @Environment(\.dismiss) private var dismiss

    @State private var photos: [Photo] = []
    @State private var isLoading = true

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 9)]

    var body: some View {
        VStack(spacing: 0) {
            WorkshopNavHeader(title: String(localized: "redpacket.workshop.photoPicker")) {
                dismiss()
            }

            Group {
                if isLoading {
                    ProgressView()
                        .tint(Color.milensActionPrimary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if photos.isEmpty {
                    emptyState
                } else {
                    photoGrid
                }
            }
        }
        .background(Color.milensBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadPhotos() }
    }

    // MARK: - 照片网格

    private var photoGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "redpacket.workshop.selectPhoto"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.md)

                // 抠图提示
                Text(String(localized: "redpacket.workshop.cutoutHint"))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.xs)

                LazyVGrid(columns: columns, spacing: 9) {
                    ForEach(photos) { photo in
                        NavigationLink(value: Route.redPacketWorkshop(
                            templateID: templateID,
                            photoID: photo.id,
                            petID: photo.pet?.id
                        )) {
                            ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                                .frame(width: 108, height: 108)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .clipped()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "redpacket.workshop.selectPhoto"))
                    }
                }
                .padding(.horizontal, Spacing.pagePad)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 空态

    private var emptyState: some View {
        ContentUnavailableView(
            String(localized: "redpacket.workshop.noPhotos"),
            systemImage: "photo.on.rectangle.angled",
            description: Text(String(localized: "redpacket.workshop.noPhotosDesc"))
        )
    }

    // MARK: - 数据

    @MainActor
    private func loadPhotos() async {
        defer { isLoading = false }
        do {
            photos = try factory.photoList(limit: 100)
        } catch {
            logger.error("loadPhotos: \(error.localizedDescription)")
        }
    }
}

#Preview {
    NavigationStack {
        RedPacketPhotoPickerView(templateID: "new_year_red")
    }
}
