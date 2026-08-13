//  RedPacketExportView —— 红包导出页（对应红包封面开发计划 §6）。
//
//  上段：成品检查（封面大图、规格校验结果、水印状态、重新编辑）。
//  下段：分享前预览（聊天红包卡片 + 多场景模拟） + 保存到相册 / 系统分享 + 上传指引入口。
//  封面和预览共用 RedPacketCoverRenderer 渲染结果（不两套排版逻辑）。

import SwiftUI
import UIKit
import Photos
import MiLensKit
import os

private let logger = Logger(subsystem: "com.milens.app", category: "RedPacketExport")

struct RedPacketExportView: View {
    let draftID: UUID

    @Environment(\.viewModelFactory) private var factory
    @Environment(\.proEntitlement) private var entitlement
    @Environment(\.dismiss) private var dismiss

    @State private var draft: RedPacketCoverDraft?
    @State private var template: RedPacketTemplate?
    @State private var renderedImage: UIImage?
    @State private var exportData: RedPacketExportData?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var shareItem: ShareItem?
    @State private var toast: ExportToastMessage?
    @State private var selectedScene: PreviewScene = .redPacketCard

    enum PreviewScene: String, CaseIterable, Identifiable {
        case redPacketCard  // 红包卡片（聊天消息）
        case openRedPacket  // 拆红包页
        case redPacketList  // 红包列表

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .redPacketCard: return String(localized: "redpacket.export.scene.card")
            case .openRedPacket: return String(localized: "redpacket.export.scene.open")
            case .redPacketList: return String(localized: "redpacket.export.scene.list")
            }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Color.milensActionPrimary)
            } else if let draft, let template {
                content(draft: draft, template: template)
            } else {
                loadFailedView
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

    private func content(draft: RedPacketCoverDraft, template: RedPacketTemplate) -> some View {
        VStack(spacing: 0) {
            WorkshopNavHeader(title: String(localized: "redpacket.export.title")) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // === 上段：成品检查 ===
                    productCheckSection(draft: draft, template: template)

                    // === 下段：分享前预览 ===
                    chatPreviewSection(draft: draft, template: template)

                    // 上传指引入口
                    uploadGuideEntry

                    Spacer(minLength: 100)
                }
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                ExportToastView(kind: toast.kind, message: toast.text)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(2.5))
                            self.toast = nil
                        }
                    }
            }
        }
    }

    // MARK: - 成品检查段

    private func productCheckSection(draft: RedPacketCoverDraft, template: RedPacketTemplate) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            EditorialOverline(text: String(localized: "redpacket.export.productCheck"))
                .padding(.horizontal, Spacing.pagePad)
                .padding(.top, Spacing.lg)

            // 封面大图预览
            if let image = renderedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.sm)
            }

            // 规格校验结果
            specValidationView

            // 水印状态
            watermarkStatusView
        }
    }

    // MARK: - 规格校验

    private var specValidationView: some View {
        VStack(alignment: .leading, spacing: 4) {
            specRow(
                label: String(localized: "redpacket.export.size"),
                value: "\(WeChatRedPacketSpec.coverImageWidth) × \(WeChatRedPacketSpec.coverImageHeight)"
            )
            specRow(
                label: String(localized: "redpacket.export.format"),
                value: exportData?.format.rawValue.uppercased() ?? "PNG"
            )
            if let data = exportData {
                specRow(
                    label: String(localized: "redpacket.export.fileSize"),
                    value: formatByteCount(data.data.count)
                )
                // 规格校验结果
                let validation = validateExport(data: data)
                specRow(
                    label: String(localized: "redpacket.export.status"),
                    value: validation.passed
                        ? String(localized: "redpacket.export.passed")
                        : String(localized: "redpacket.export.exceeded"),
                    valueColor: validation.passed ? .green : .red
                )
                // 失败原因
                if !validation.passed, let reason = validation.reason {
                    Text(reason)
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.red.opacity(0.8))
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, Spacing.sm)
    }

    // MARK: - 水印状态

    private var watermarkStatusView: some View {
        HStack(spacing: 8) {
            Image(systemName: entitlement.isPro ? "checkmark.seal.fill" : "drop.fill")
                .foregroundStyle(entitlement.isPro ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(entitlement.isPro
                     ? String(localized: "redpacket.export.noWatermark")
                     : String(localized: "redpacket.export.hasWatermark"))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextPrimary)
                if !entitlement.isPro {
                    Text(String(localized: "redpacket.export.proHint"))
                        .font(.editorialMetadata)
                        .foregroundStyle(Color.milensActionPrimary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, Spacing.sm)
    }

    // MARK: - 聊天预览段

    private func chatPreviewSection(draft: RedPacketCoverDraft, template: RedPacketTemplate) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            EditorialOverline(text: String(localized: "redpacket.export.chatPreview"))
                .padding(.horizontal, Spacing.pagePad)
                .padding(.top, Spacing.xl)

            // 场景切换
            Picker("", selection: $selectedScene) {
                ForEach(PreviewScene.allCases) { scene in
                    Text(scene.displayName).tag(scene)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.xs)

            // 场景预览
            if let image = renderedImage {
                scenePreview(image: image, draft: draft)
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.sm)
            }

            Text(String(localized: "redpacket.export.previewNote"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextSecondary)
                .padding(.horizontal, Spacing.pagePad)
                .padding(.top, Spacing.xs)
        }
    }

    // MARK: - 场景预览

    private func scenePreview(image: UIImage, draft: RedPacketCoverDraft) -> some View {
        Group {
            switch selectedScene {
            case .redPacketCard:
                redPacketCardScene(image: image, draft: draft)
            case .openRedPacket:
                openRedPacketScene(image: image, draft: draft)
            case .redPacketList:
                redPacketListScene(image: image, draft: draft)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.milensSealSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Text(String(localized: "redpacket.export.sceneLabel"))
                .font(.system(size: 10))
                .foregroundStyle(Color.milensTextSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.milensBackground.opacity(0.8))
                .clipShape(Capsule())
                .padding(6)
        }
    }

    // 场景 1：红包卡片（聊天消息）
    private func redPacketCardScene(image: UIImage, draft: RedPacketCoverDraft) -> some View {
        HStack(alignment: .top, spacing: 8) {
            avatarPlaceholder
            VStack(alignment: .leading, spacing: 4) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 107)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(draft.coverTitle.isEmpty ? String(localized: "redpacket.export.defaultTitle") : draft.coverTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(1)
            }
            .padding(10)
            .background(Color.orange.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Spacer()
        }
    }

    // 场景 2：拆红包页
    private func openRedPacketScene(image: UIImage, draft: RedPacketCoverDraft) -> some View {
        VStack(spacing: 8) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 160)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(draft.coverTitle.isEmpty ? String(localized: "redpacket.export.defaultTitle") : draft.coverTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.milensTextPrimary)
            // 模拟拆开按钮
            Circle()
                .fill(Color.orange.opacity(0.8))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(String(localized: "redpacket.export.openButton"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
        }
    }

    // 场景 3：红包列表
    private func redPacketListScene(image: UIImage, draft: RedPacketCoverDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                avatarPlaceholder.frame(width: 28, height: 28)
                Text(draft.petName.isEmpty ? String(localized: "redpacket.export.defaultSender") : draft.petName)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.milensTextSecondary)
            }
            HStack(spacing: 6) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 48)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                Text(draft.coverTitle.isEmpty ? String(localized: "redpacket.export.defaultTitle") : draft.coverTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(1)
            }
            .padding(6)
            .background(Color.orange.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.gray)
            }
    }

    // MARK: - 上传指引入口

    private var uploadGuideEntry: some View {
        VStack(spacing: 8) {
            if let photoID = draft?.sourcePhotoID {
                NavigationLink(value: Route.redPacketUploadGuide(
                    photoID: photoID, petID: nil
                )) {
                    HStack {
                        Image(systemName: "info.circle")
                        Text(String(localized: "redpacket.uploadGuide.link"))
                    }
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensActionPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.milensActionPrimary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                }
            }
            Text(String(localized: "redpacket.export.howToUse"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextSecondary)
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, Spacing.lg)
    }

    // MARK: - 操作栏

    private var actionBar: some View {
        VStack(spacing: 0) {
            // 保存成功提示
            if isSaving {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.bottom, 4)
            }
            CreationActionBar(
                primaryLabel: String(localized: "redpacket.action.share"),
                secondaryLabel: String(localized: "share.action.saveLibrary"),
                primaryAction: { share() },
                secondaryAction: { Task { await saveToLibrary() } }
            )
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
        .background(Color.milensBackground)
    }

    // MARK: - 加载失败

    private var loadFailedView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.milensTextSecondary)
            Text(String(localized: "redpacket.export.loadFailed"))
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 规格行

    private func specRow(label: String, value: String, valueColor: Color = .milensTextPrimary) -> some View {
        HStack {
            Text(label)
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextSecondary)
            Spacer()
            Text(value)
                .font(.editorialMetadata.monospacedDigit())
                .foregroundStyle(valueColor)
        }
    }

    // MARK: - 校验

    private func validateExport(data: RedPacketExportData) -> (passed: Bool, reason: String?) {
        let result = RedPacketCoverLogic.validateCoverImage(
            data: data.data,
            width: WeChatRedPacketSpec.coverImageWidth,
            height: WeChatRedPacketSpec.coverImageHeight,
            fileExtension: data.fileExtension
        )
        switch result {
        case .valid:
            return (true, nil)
        case .invalidSize(let expected, let actual):
            return (false, String(localized: "redpacket.export.fail.size"))
        case .invalidFileSize(let maxBytes, _):
            return (false, "\(String(localized: "redpacket.export.fail.fileSize")) \(formatByteCount(maxBytes))")
        case .invalidFormat:
            return (false, String(localized: "redpacket.export.fail.format"))
        }
    }

    // MARK: - 动作

    private func share() {
        guard let data = exportData else { return }
        let filename = RedPacketExportLogic.exportFilename(
            petName: draft?.petName ?? "",
            fileExtension: data.fileExtension
        )
        do {
            let url = try BeadExportService().writeShareCache(data: data.data, filename: filename)
            shareItem = ShareItem(url: url)
            toast = .success(String(localized: "redpacket.export.shareReady"))
        } catch {
            logger.error("share: 写入分享缓存失败 \(error.localizedDescription)")
            toast = .failure(String(localized: "redpacket.export.shareFailed"))
        }
    }

    private func saveToLibrary() async {
        guard let data = exportData else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await BeadExportService().saveToPhotoLibrary(pngData: data.data)
            toast = .success(String(localized: "redpacket.export.saved"))
        } catch {
            logger.error("saveToLibrary: 保存失败 \(error.localizedDescription)")
            saveError = String(localized: "redpacket.export.saveFailed")
        }
    }

    // MARK: - 渲染

    private func renderCover() -> UIImage? {
        guard let template else { return nil }
        let layers = draft?.layers ?? rpDefaultLayers(for: template)
        let renderer = ImageRenderer(content:
            RedPacketCoverRenderer(
                template: template,
                layers: layers,
                petImage: nil,
                includeWatermark: !entitlement.isPro
            )
            .frame(
                width: CGFloat(WeChatRedPacketSpec.coverImageWidth),
                height: CGFloat(WeChatRedPacketSpec.coverImageHeight)
            )
        )
        renderer.scale = 1
        return renderer.uiImage
    }

    // MARK: - 数据

    @MainActor
    private func load() async {
        defer { isLoading = false }
        let store = RedPacketDraftStore()
        do {
            guard let loaded = try store.load(id: draftID) else {
                logger.error("load: 草稿不存在 \(self.draftID)")
                return
            }
            draft = loaded
            template = RedPacketTemplateCatalog.find(id: loaded.templateID)

            guard let rendered = renderCover() else { return }
            renderedImage = rendered

            let png = rendered.pngData()
            let jpegHigh = rendered.jpegData(compressionQuality: 0.9)
            let jpegLow = rendered.jpegData(compressionQuality: 0.6)
            exportData = RedPacketExportLogic.chooseBest(
                png: png, jpegHigh: jpegHigh, jpegLow: jpegLow
            )
        } catch {
            logger.error("load: 加载草稿失败 \(error.localizedDescription)")
        }
    }

    // MARK: - 工具

    private func formatByteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

#Preview {
    NavigationStack {
        RedPacketExportView(draftID: UUID())
    }
}
