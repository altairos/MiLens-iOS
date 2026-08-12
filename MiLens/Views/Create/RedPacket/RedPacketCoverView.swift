//  RedPacketCoverView —— 微信红包封面生成页（创作 Tab 新增项目）。
//
//  按 957×1278 微信规格渲染封面排版 + 4 场景模拟预览 + 导出规格素材 + 上传引导。
//  边界：App 只生成素材与预览，不介入发布（发布需用户登录 cover.weixin.qq.com，
//  有注册门槛+审核+付费）。Pro 门控：免费可预览拆红包页 + 导出带水印；
//  Pro 解锁全部 4 场景 + 无水印导出。

import SwiftUI
import UIKit
import Photos
import MiLensKit
import os

private let logger = Logger(subsystem: "com.milens.app", category: "RedPacket")

struct RedPacketCoverView: View {
    let photoID: UUID
    let petID: UUID?

    @Environment(\.viewModelFactory) private var factory
    @Environment(\.proEntitlement) private var entitlement
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var photo: Photo?
    @State private var petName = ""
    @State private var coverTitle = ""
    @State private var isLoading = true

    // 场景预览
    @State private var selectedScene: RedPacketScene = .open

    // 导出/分享
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var shareItem: ShareItem?
    @State private var sharePreview: (image: UIImage, url: URL, filename: String, spec: String)?

    enum RedPacketScene: String, CaseIterable, Identifiable {
        case open      // 拆红包页（最完整展示）
        case send      // 发红包页
        case bubble    // 消息气泡
        case detail    // 详情页

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .open:   return "拆红包页"
            case .send:   return "发红包页"
            case .bubble: return "消息气泡"
            case .detail: return "详情页"
            }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Color.milensActionPrimary)
            } else if let image {
                content(image: image)
            } else {
                loadFailedView
            }
        }
        .background(Color.milensBackground)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(item: Binding<SharePreviewData?>(
            get: { sharePreview.map { SharePreviewData(image: $0.image, url: $0.url, filename: $0.filename, spec: $0.spec) } },
            set: { if $0 == nil { sharePreview = nil } }
        )) { data in
            SharePreviewSheet(
                previewImage: data.image,
                shareURL: data.url,
                filename: data.filename,
                spec: data.spec,
                onDismiss: { sharePreview = nil }
            )
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

    private func content(image: UIImage) -> some View {
        VStack(spacing: 0) {
            WorkshopNavHeader(title: String(localized: "redpacket.title")) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 来源条
                    if let photo {
                        WorkshopSourceBar(
                            meta: String(localized: "source.redPacket.meta"),
                            label: "\(petName) · \(formatDate(photo.takenAt))",
                            onChange: { dismiss() }
                        ) {
                            ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                        }
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.md)
                    }

                    // Overline + 规格
                    HStack {
                        EditorialOverline(text: String(localized: "redpacket.overline"))
                        Spacer()
                        Text(String(localized: "redpacket.spec"))
                            .font(.editorialMetadata)
                            .foregroundStyle(Color.milensTextSecondary)
                    }
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.lg)

                    // Red Packet Workshop（暗卡）
                    VStack(spacing: 0) {
                        HStack(alignment: .top, spacing: 16) {
                            // 封面预览
                            RedPacketCoverArtwork(
                                image: image,
                                coverTitle: coverTitle,
                                includeWatermark: !entitlement.isPro
                            )
                            .frame(width: 150)
                            .aspectRatio(
                                Double(WeChatRedPacketSpec.coverImageWidth) / Double(WeChatRedPacketSpec.coverImageHeight),
                                contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                            // 场景选择
                            VStack(spacing: 8) {
                                ForEach(Array(RedPacketScene.allCases.enumerated()), id: \.element.id) { index, scene in
                                    sceneMiniCell(scene, index: index + 1)
                                }
                            }
                        }
                        .padding(16)

                        Text(String(localized: "redpacket.watermarkHint"))
                            .font(.editorialMetadata)
                            .foregroundStyle(Color.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 14)
                    }
                    .background(Color.milensSealSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.sm)

                    // 场景模拟预览
                    WeChatRedPacketMockView(
                        image: image,
                        coverTitle: coverTitle,
                        scene: selectedScene,
                        isPro: entitlement.isPro
                    )
                        .frame(maxWidth: 342)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                                .stroke(Color.milensBorder, lineWidth: 0.5)
                        }
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.lg)

                    // 封面标题字段编辑行
                    WorkshopFieldRow(
                        label: String(localized: "redpacket.coverTitle"),
                        value: coverTitle.isEmpty ? String(localized: "redpacket.coverTitle.placeholder") : coverTitle,
                        onEdit: nil,
                        showsRule: false
                    )
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.xl)

                    // 封面标题输入（内联）
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        TextField(String(localized: "redpacket.coverTitle.placeholder"), text: $coverTitle, axis: .horizontal)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: coverTitle) { _, newValue in
                                if newValue.count > WeChatRedPacketSpec.coverTitleMaxLength {
                                    coverTitle = String(newValue.prefix(WeChatRedPacketSpec.coverTitleMaxLength))
                                }
                            }
                    }
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.sm)

                    // 上传指引入口
                    NavigationLink(value: Route.redPacketUploadGuide(photoID: photoID, petID: petID)) {
                        Text(String(localized: "redpacket.uploadGuide.link"))
                            .font(.uiBodyStrong)
                            .foregroundStyle(Color.milensActionPrimary)
                    }
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.lg)

                    Text(String(localized: "redpacket.uploadGuide.note"))
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensTextSecondary)
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.xs)

                    Spacer(minLength: 100)
                }
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                CreationActionBar(
                    primaryLabel: String(localized: "redpacket.action.export"),
                    secondaryLabel: String(localized: "share.action.saveLibrary"),
                    primaryAction: { share() },
                    secondaryAction: { Task { await saveToLibrary() } }
                )
                .padding(.horizontal, Spacing.pagePad)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.md)
                .background(Color.milensBackground)
            }
        }
    }

    // MARK: - 场景缩略单元

    private func sceneMiniCell(_ scene: RedPacketScene, index: Int) -> some View {
        let isSelected = selectedScene == scene
        return Button {
            let isUnlocked = scene == .open || entitlement.isPro
            if isUnlocked { selectedScene = scene }
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? Color.milensActionPrimary.opacity(0.2) : Color.milensSealSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(isSelected ? Color.milensActionPrimary : Color.milensSeparator, lineWidth: isSelected ? 1.5 : 1)
                    }
                    .frame(width: 72, height: 44)
                Text("模版\(index)")
                    .font(.editorialMetadata)
                    .foregroundStyle(isSelected ? Color.milensTextPrimary : Color.milensTextSecondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(scene != .open && !entitlement.isPro)
    }
    }

    // MARK: - 动作

    private func renderCover() -> UIImage? {
        guard let image else { return nil }
        let w = WeChatRedPacketSpec.coverImageWidth
        let h = WeChatRedPacketSpec.coverImageHeight
        let artwork = RedPacketCoverArtwork(
            image: image,
            coverTitle: coverTitle,
            includeWatermark: !entitlement.isPro
        )
            .frame(width: CGFloat(w), height: CGFloat(h))
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 1
        return renderer.uiImage
    }

    private func saveToLibrary() async {
        guard let rendered = renderCover() else {
            saveError = "封面渲染失败，请重试"
            return
        }
        // 微信约束 ≤500KB，PNG 先尝试，超限时降级 JPEG
        let data: Data
        if let png = rendered.pngData(), png.count <= WeChatRedPacketSpec.coverImageMaxBytes {
            data = png
        } else if let jpg = rendered.jpegData(compressionQuality: 0.9),
                  jpg.count <= WeChatRedPacketSpec.coverImageMaxBytes {
            data = jpg
        } else {
            // 进一步压缩
            guard let jpg = rendered.jpegData(compressionQuality: 0.6) else {
                saveError = "图片编码失败，请重试"
                return
            }
            data = jpg
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await BeadExportService().saveToPhotoLibrary(pngData: data)
        } catch {
            logger.error("saveToLibrary: 保存失败（\(error.localizedDescription)）")
            saveError = "保存到相册失败：\(error.localizedDescription)"
        }
    }

    private func share() {
        guard let rendered = renderCover() else { return }
        let data: Data
        if let png = rendered.pngData(), png.count <= WeChatRedPacketSpec.coverImageMaxBytes {
            data = png
        } else {
            data = rendered.jpegData(compressionQuality: 0.85) ?? Data()
        }
        let filename = RedPacketCoverLogic.exportFilename(petName: petName)
        let spec = "\(WeChatRedPacketSpec.coverImageWidth) × \(WeChatRedPacketSpec.coverImageHeight) · PNG · \(formatByteCount(data.count))"
        do {
            let url = try BeadExportService().writeShareCache(data: data, filename: filename)
            sharePreview = (image: rendered, url: url, filename: filename, spec: spec)
        } catch {
            logger.error("share: 写入分享缓存失败（\(error.localizedDescription)）")
        }
    }

    /// 格式化字节数为可读字符串（KB/MB）。
    private func formatByteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// 格式化日期。
    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy.MM.dd"
        return fmt.string(from: date)
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
            guard let foundPhoto = try factory.photo(id: photoID) else { return }
            self.photo = foundPhoto
            let path = foundPhoto.thumbnailPath.isEmpty ? foundPhoto.uri : foundPhoto.thumbnailPath
            let loaded = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: path)
            }.value
            guard let loaded else {
                logger.error("load: 照片解码失败（\(path)）")
                return
            }
            image = loaded

            // 宠物名（优先用 petID，回退照片归属）
            var name = ""
            if let petID, let pet = try factory.pet(id: petID) {
                name = pet.name
            } else if let pet = foundPhoto.pet {
                name = pet.name
            }
            petName = name
            coverTitle = RedPacketCoverLogic.coverTitle(petName: name)
        } catch {
            logger.error("load: 读取照片失败（\(error.localizedDescription)）")
        }
    }
}

// MARK: - 封面排版（按微信 957×1278 规格）

/// 红包封面排版：照片铺底 + 上部安全区放宠物名 + 底部渐变（避开微信拆红包页金额/按钮遮挡）。
/// 安全区参考 WeChatRedPacketSpec.safeZoneTopRatio（关键元素放在上部 55% 之内）。
struct RedPacketCoverArtwork: View {
    let image: UIImage
    var coverTitle: String = ""
    var includeWatermark: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let safeBottom = h * WeChatRedPacketSpec.safeZoneTopRatio
            ZStack(alignment: .topLeading) {
                // 照片铺底
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()

                // 底部渐变（增强上半部分文字可读性，不覆盖下部遮挡区）
                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.5)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: h * 0.35)
                .frame(maxHeight: .infinity, alignment: .top)

                // 封面简称（上部安全区内）
                VStack(alignment: .leading, spacing: w * 0.02) {
                    Text("\u{1F43E}")
                        .font(.system(size: w * 0.05))
                    Text(coverTitle)
                        .font(.custom("LXGWWenKai-Regular", size: w * 0.06))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.top, h * 0.06)
                .padding(.leading, w * 0.08)
                .frame(maxWidth: safeBottom, alignment: .topLeading)

                // 水印（右下角，在遮挡区上方）
                if includeWatermark {
                    Text("MiLens")
                        .font(.system(size: w * 0.025, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.trailing, w * 0.06)
                        .padding(.top, h * 0.42)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
        }
        .aspectRatio(
            Double(WeChatRedPacketSpec.coverImageWidth) / Double(WeChatRedPacketSpec.coverImageHeight),
            contentMode: .fit)
    }
}

#Preview {
    NavigationStack {
        RedPacketCoverView(photoID: UUID(), petID: nil)
    }
}
