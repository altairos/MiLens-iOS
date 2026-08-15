//  RedPacketUploadGuideView —— 微信红包封面上传指引页。
//  对照 Figma「11 · Red Packet / Upload Guide」#422:845：
//  导航头 + 编辑式标题 + Export Ready Proof 卡片 + 时间线步骤 + Platform Note + CreationActionBar。
//  边界：MiLens 只生成与导出，上传/审核/发布均在微信完成。

import SwiftUI
import MiLensKit
import os

private let logger = Logger(subsystem: "com.milens.app", category: "RedPacketGuide")

struct RedPacketUploadGuideView: View {
    let photoID: UUID
    let petID: UUID?

    @Environment(\.viewModelFactory) private var factory
    @Environment(\.proEntitlement) private var entitlement
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var petName = ""
    @State private var coverTitle = ""
    @State private var isLoading = true
    @State private var shareItem: ShareItem?
    @State private var saveError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Color.milensActionPrimary)
            } else {
                content
            }
        }
        .background(Color.milensBackground)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert(String(localized: "redpacket.save.failed"), isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .task { await load() }
    }

    // MARK: - 内容

    private var content: some View {
        VStack(spacing: 0) {
            WorkshopNavHeader(title: String(localized: "upload.title")) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 编辑式标题
                    Text(String(localized: "upload.headline"))
                        .font(.editorialSection)
                        .foregroundStyle(Color.milensTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.md)

                    // Export Ready Proof 卡片
                    exportReadyProof
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.lg)

                    // 时间线步骤
                    VStack(spacing: 0) {
                        WorkshopTimelineStep(
                            index: "01",
                            title: String(localized: "upload.step.01.title"),
                            desc: String(localized: "upload.step.01.desc")
                        )
                        WorkshopTimelineStep(
                            index: "02",
                            title: String(localized: "upload.step.02.title"),
                            desc: String(localized: "upload.step.02.desc")
                        )
                        WorkshopTimelineStep(
                            index: "03",
                            title: String(localized: "upload.step.03.title"),
                            desc: String(localized: "upload.step.03.desc")
                        )
                        WorkshopTimelineStep(
                            index: "04",
                            title: String(localized: "upload.step.04.title"),
                            desc: String(localized: "upload.step.04.desc"),
                            isCompleted: false,
                            showsConnector: false
                        )
                    }
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.xl)

                    // Platform Note
                    HStack(alignment: .top, spacing: 0) {
                        Rectangle()
                            .fill(Color.milensActionPrimary)
                            .frame(width: 4)
                        Text(String(localized: "upload.platformNote"))
                            .font(.editorialMetadata)
                            .foregroundStyle(Color.milensTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.milensSeparator, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.lg)

                    Spacer(minLength: 100)
                }
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                CreationActionBar(
                    primaryLabel: String(localized: "redpacket.action.share"),
                    secondaryLabel: String(localized: "share.action.saveLibrary"),
                    primaryAction: { shareViaWeChat() },
                    secondaryAction: { Task { await saveToLibrary() } }
                )
                .padding(.horizontal, Spacing.pagePad)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.md)
                .background(Color.milensBackground)
            }
        }
    }

    // MARK: - Export Ready Proof

    private var exportReadyProof: some View {
        HStack(spacing: 14) {
            // Mini Cover 缩略
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.milensGrouped
                }
            }
            .frame(width: 67, height: 89)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(alignment: .bottom) {
                Text(coverTitle.isEmpty ? String(localized: "upload.title") : coverTitle)
                    .font(.editorialOverline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                    .padding(4)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "upload.proof.title"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                Text(String(localized: "upload.proof.spec"))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
                Text(String(localized: "upload.proof.watermark"))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
            }

            Spacer()

            Text("\u{2713}")
                .font(.uiTitle)
                .foregroundStyle(Color.milensActionPrimary)
        }
        .padding(14)
        .background(Color.milensSealSurface)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - 动作

    private func renderCover() -> UIImage? {
        guard let image else { return nil }
        let w = WeChatRedPacketSpec.coverImageWidth
        let h = WeChatRedPacketSpec.coverImageHeight
        let template = RedPacketTemplateCatalog.firstFreeTemplate
        let layers = rpDefaultLayers(for: template, petName: petName)
        let artwork = RedPacketCoverRenderer(
            template: template,
            layers: layers,
            petImage: image,
            includeWatermark: !entitlement.isPro
        )
            .frame(width: CGFloat(w), height: CGFloat(h))
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 1
        return renderer.uiImage
    }

    private func saveToLibrary() async {
        guard let rendered = renderCover() else {
            saveError = String(localized: "redpacket.render.failed")
            return
        }
        guard let data = RedPacketCoverEncodeLogic.encodeForSave(
            pngData: { rendered.pngData() },
            jpegData: { rendered.jpegData(compressionQuality: $0) }
        ) else {
            saveError = String(localized: "create.encode.failed")
            return
        }
        do {
            try await BeadExportService().saveToPhotoLibrary(pngData: data)
        } catch {
            logger.error("saveToLibrary: 保存失败（\(error.localizedDescription)）")
            saveError = "保存到相册失败：\(error.localizedDescription)"
        }
    }

    private func shareViaWeChat() {
        guard let rendered = renderCover() else { return }
        let data = RedPacketCoverEncodeLogic.encodeForShare(
            pngData: { rendered.pngData() },
            jpegData: { rendered.jpegData(compressionQuality: $0) }
        )
        let filename = RedPacketCoverLogic.exportFilename(petName: petName)
        do {
            let url = try BeadExportService().writeShareCache(data: data, filename: filename)
            shareItem = ShareItem(url: url)
        } catch {
            logger.error("shareViaWeChat: 写入分享缓存失败（\(error.localizedDescription)）")
        }
    }

    // MARK: - 数据

    @MainActor
    private func load() async {
        defer { isLoading = false }
        do {
            guard let photo = try factory.photo(id: photoID) else { return }
            let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
            let loaded = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: path)
            }.value
            image = loaded

            var name = ""
            if let petID, let pet = try factory.pet(id: petID) {
                name = pet.name
            } else if let pet = photo.pet {
                name = pet.name
            }
            petName = name
            coverTitle = RedPacketCoverLogic.coverTitle(petName: name)
        } catch {
            logger.error("load: 读取照片失败（\(error.localizedDescription)）")
        }
    }
}

#Preview {
    NavigationStack {
        RedPacketUploadGuideView(photoID: UUID(), petID: nil)
    }
}
