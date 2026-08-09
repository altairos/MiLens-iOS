//  PetCardView —— 宠物卡片生成页（P4，route .petCard，对应创作 Tab「宠物卡片」项目）。
//
//  卡片 = 一张照片 + 宠物信息排版（UI-DESIGN.md §6.6）。iOS 自研 MVP：
//  预览与导出共用 PetCardArtwork（同一排版，导出用 ImageRenderer 固定 1080×1350）。
//  保存相册走 PHPhotoLibrary（复用 BeadExportService），分享走系统分享单。

import SwiftUI
import UIKit
import Photos
import os

private let logger = Logger(subsystem: "com.milens.app", category: "PetCard")

struct PetCardView: View {
    let photoID: UUID

    @Environment(\.viewModelFactory) private var factory

    @State private var photo: Photo?
    @State private var image: UIImage?
    @State private var content: PetCardContent?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var shareItem: ShareItem?
    @State private var saveError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Color.milensActionPrimary)
            } else if let image, let content {
                cardPreview(image: image, content: content)
            } else {
                loadFailedView
            }
        }
        .background(Color.milensBackground)
        .navigationTitle("宠物卡片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await saveToLibrary() }
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                .disabled(isSaving)

                Button {
                    share()
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                .disabled(isSaving)
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert("保存失败", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .task { await load() }
    }

    // MARK: - 预览

    private func cardPreview(image: UIImage, content: PetCardContent) -> some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // 预览即导出排版（同一 Artwork，等比缩放）
                PetCardArtwork(image: image, content: content)
                    .frame(maxWidth: 480)
                    .aspectRatio(PetCardLogic.exportSize.width.cg / PetCardLogic.exportSize.height.cg,
                                 contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                            .stroke(Color.milensBorder, lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 6)

                Text("长按或保存到相册后，可作为壁纸或分享给家人。")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 动作

    /// 渲染 1080×1350 卡片 PNG（预览与导出同源排版）。
    private func renderCard() -> UIImage? {
        guard let image, let content else { return nil }
        let size = PetCardLogic.exportSize
        let artwork = PetCardArtwork(image: image, content: content)
            .frame(width: size.width.cg, height: size.height.cg)
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 1
        return renderer.uiImage
    }

    private func saveToLibrary() async {
        guard let rendered = renderCard() else {
            saveError = "卡片渲染失败，请重试"
            return
        }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.9) else {
            saveError = "图片编码失败，请重试"
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await BeadExportService().saveToPhotoLibrary(pngData: jpeg)
        } catch {
            logger.error("saveToLibrary: 保存失败（\(error.localizedDescription)）")
            saveError = "保存到相册失败：\(error.localizedDescription)"
        }
    }

    private func share() {
        guard let rendered = renderCard(),
              let jpeg = rendered.jpegData(compressionQuality: 0.9) else { return }
        do {
            let url = try BeadExportService().writeShareCache(data: jpeg, filename: "pet_card_share.jpg")
            shareItem = ShareItem(url: url)
        } catch {
            logger.error("share: 写入分享缓存失败（\(error.localizedDescription)）")
        }
    }

    // MARK: - 加载失败

    private var loadFailedView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.milensTextSecondary)
            Text("照片加载失败")
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 数据

    @MainActor
    private func load() async {
        defer { isLoading = false }
        do {
            guard let photo = try factory.photo(id: photoID) else { return }
            self.photo = photo
            let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
            let loaded = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: path)
            }.value
            guard let loaded else {
                logger.error("load: 照片解码失败（\(path)）")
                return
            }
            image = loaded
            content = PetCardLogic.content(pet: photo.pet, takenAt: photo.takenAt)
        } catch {
            logger.error("load: 读取照片失败（\(error.localizedDescription)）")
        }
    }
}

// MARK: - 卡片排版（预览与导出共用）

/// 宠物卡片版式：照片铺底 + 底部暖黑渐变 + 名字/物种/日期行。
/// 字号与间距按画布宽度比例缩放（预览与 1080px 导出同源）。
struct PetCardArtwork: View {
    let image: UIImage
    let content: PetCardContent

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()

                // 底部暖黑渐变（叠字安全区，高度按模板比例）
                LinearGradient(
                    colors: [Color.black.opacity(0.78), Color.black.opacity(0.0)],
                    startPoint: .bottom, endPoint: .top
                )
                .frame(height: h * PetCardLogic.gradientHeightRatio)
                .frame(maxHeight: .infinity, alignment: .bottom)

                VStack(alignment: .leading, spacing: w * 0.024) {
                    Text("\(content.emoji) \(content.subtitle)")
                        .font(.system(size: w * 0.042, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))

                    Text(content.title)
                        .font(.custom("LXGWWenKai-Regular", size: w * 0.10))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(content.dateLine)
                        .font(.system(size: w * 0.036, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .padding(w * 0.07)
                .padding(.bottom, w * 0.05)
            }
        }
        .aspectRatio(PetCardLogic.exportSize.width.cg / PetCardLogic.exportSize.height.cg,
                     contentMode: .fit)
    }
}

// MARK: - 尺寸换算

private extension Int {
    /// 像素 → 点（导出画布以 1x 逻辑尺寸渲染）
    var cg: CGFloat { CGFloat(self) }
}

#Preview {
    NavigationStack {
        PetCardView(photoID: UUID())
    }
}
