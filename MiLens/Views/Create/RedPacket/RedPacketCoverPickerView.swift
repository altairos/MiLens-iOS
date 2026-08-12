//  RedPacketCoverPickerView —— 微信红包封面的选照片页（创作 Tab 新增项目）。
//  对照 Workshop 编辑式导航头 + 编辑式网格（统一风格）。
//  从 CreateView「红包封面」入口进入；选一张照片作为封面主体 → 进入 RedPacketCoverView。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "RedPacket")

struct RedPacketCoverPickerView: View {
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
            WorkshopNavHeader(title: String(localized: "picker.redPacket.title")) { dismiss() }
            ContentUnavailableView(
                String(localized: "picker.redPacket.empty"),
                systemImage: "photo.on.rectangle.angled",
                description: Text(String(localized: "picker.redPacket.emptyDesc"))
            )
        }
    }

    // MARK: - 照片网格

    private var photoGrid: some View {
        VStack(spacing: 0) {
            WorkshopNavHeader(title: String(localized: "picker.redPacket.title")) { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(localized: "picker.redPacket.fromArchive"))
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.md)

                    LazyVGrid(columns: columns, spacing: 9) {
                        ForEach(photos) { photo in
                            NavigationLink(value: Route.redPacketCover(
                                photoID: photo.id, petID: photo.pet?.id)) {
                                ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                                    .aspectRatio(108.0 / 100.0, contentMode: .fill)
                                    .frame(width: 108, height: 100)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    .overlay(alignment: .bottomLeading) {
                                        if let pet = photo.pet, !pet.name.isEmpty {
                                            Text(pet.name)
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, Spacing.xs)
                                                .padding(.vertical, 2)
                                                .background(.black.opacity(0.55))
                                                .clipShape(Capsule())
                                                .padding(4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "picker.redPacket.title"))
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
