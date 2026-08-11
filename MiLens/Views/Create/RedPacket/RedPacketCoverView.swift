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

    @State private var image: UIImage?
    @State private var petName = ""
    @State private var coverTitle = ""
    @State private var isLoading = true

    // 场景预览
    @State private var selectedScene: RedPacketScene = .open

    // 导出/分享
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var shareItem: ShareItem?
    @State private var sharePreview: (image: UIImage, url: URL)?
    @State private var showUploadGuide = false

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
        .navigationTitle("红包封面")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showUploadGuide = true
                } label: {
                    Label("上传引导", systemImage: "questionmark.circle")
                }

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
        .sheet(item: Binding<SharePreviewData?>(
            get: { sharePreview.map { SharePreviewData(image: $0.image, url: $0.url) } },
            set: { if $0 == nil { sharePreview = nil } }
        )) { data in
            SharePreviewSheet(
                previewImage: data.image,
                shareURL: data.url,
                onDismiss: { sharePreview = nil }
            )
        }
        .alert("保存失败", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .sheet(isPresented: $showUploadGuide) {
            uploadGuideSheet
        }
        .task { await load() }
    }

    // MARK: - 内容

    private func content(image: UIImage) -> some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // 封面预览（按规格比例）
                RedPacketCoverArtwork(
                    image: image,
                    coverTitle: coverTitle,
                    includeWatermark: !entitlement.isPro
                )
                    .frame(maxWidth: 360)
                    .aspectRatio(
                        Double(WeChatRedPacketSpec.coverImageWidth) / Double(WeChatRedPacketSpec.coverImageHeight),
                        contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                            .stroke(Color.milensBorder, lineWidth: 0.5)
                    }

                // 场景选择器
                sceneSelector

                // 场景模拟预览
                WeChatRedPacketMockView(
                    image: image,
                    coverTitle: coverTitle,
                    scene: selectedScene,
                    isPro: entitlement.isPro
                )
                    .frame(maxWidth: 360)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                            .stroke(Color.milensBorder, lineWidth: 0.5)
                    }

                // 封面简称编辑
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("封面简称（最多 \(WeChatRedPacketSpec.coverTitleMaxLength) 字）")
                        .font(.bodyPrimary.weight(.medium))
                        .foregroundStyle(Color.milensTextPrimary)
                    TextField("宠物名", text: $coverTitle, axis: .horizontal)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: coverTitle) { _, newValue in
                            if newValue.count > WeChatRedPacketSpec.coverTitleMaxLength {
                                coverTitle = String(newValue.prefix(WeChatRedPacketSpec.coverTitleMaxLength))
                            }
                        }
                }
                .padding(Spacing.lg)
                .background(Color.milensCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))

                Text("导出 957×1278 封面图后，按「上传引导」到微信红包封面开放平台提交审核。")
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

    // MARK: - 场景选择器

    private var sceneSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                ForEach(RedPacketScene.allCases) { scene in
                    let isUnlocked = scene == .open || entitlement.isPro
                    Button {
                        if isUnlocked {
                            selectedScene = scene
                        } else {
                            // Pro 场景：可在功能层触发付费墙
                        }
                    } label: {
                        VStack(spacing: Spacing.xs) {
                            Text(scene.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(selectedScene == scene ? Color.white : Color.milensTextSecondary)
                            if !isUnlocked {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.milensTextTertiary)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(selectedScene == scene ? Color.milensActionPrimary : Color.milensGrouped)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isUnlocked)
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    // MARK: - 上传引导 sheet

    private var uploadGuideSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // 注册门槛提示
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Color.milensWarning)
                        Text("微信红包封面开放平台需要视频号/公众号粉丝≥100 或企业认证才能注册。")
                            .font(.bodySecondary)
                            .foregroundStyle(Color.milensTextSecondary)
                    }
                    .padding(Spacing.md)
                    .background(Color.milensWarning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))

                    Text("上传步骤")
                        .font(.titleStandard)
                        .foregroundStyle(Color.milensTextPrimary)
                        .padding(.top, Spacing.lg)

                    ForEach(Array(RedPacketCoverLogic.uploadGuideSteps().enumerated()), id: \.offset) { idx, key in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("\(idx + 1). \(localizedStep(key))")
                                .font(.bodyPrimary)
                                .foregroundStyle(Color.milensTextPrimary)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, Spacing.pagePad)
                .padding(.vertical, Spacing.lg)
            }
            .navigationTitle("上传引导")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showUploadGuide = false }
                }
            }
        }
    }

    /// 简易步骤文案映射（V1 固定中文；后续接入 Localizable.xcstrings）。
    private func localizedStep(_ key: String) -> String {
        switch key {
        case "redpacket.guide.step1": return "电脑访问微信红包封面开放平台 cover.weixin.qq.com"
        case "redpacket.guide.step2": return "点击「定制封面」，上传导出的封面图（957×1278 PNG）"
        case "redpacket.guide.step3": return "填写封面简称，上传品牌 logo（可选）"
        case "redpacket.guide.step4": return "提交审核（约 1-2 小时）"
        case "redpacket.guide.step5": return "审核通过后选择使用人数并支付，生成领取链接"
        default: return key
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
        do {
            let url = try BeadExportService().writeShareCache(data: data, filename: filename)
            sharePreview = (image: rendered, url: url)
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
            let path = photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath
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
