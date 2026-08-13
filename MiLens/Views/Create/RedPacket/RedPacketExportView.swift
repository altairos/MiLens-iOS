//  RedPacketExportView —— 红包导出页（对应红包封面开发计划 §6）。
//
//  上段：成品检查（封面大图、规格、安全区状态、重新编辑）。
//  下段：聊天语境预览 + 保存到相册 / 系统分享 + 上传指引入口。
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
                   成品检查段(draft: draft, template: template)

                    // === 下段：聊天语境预览 ===
                    聊天预览段(draft: draft, template: template)

                    // 上传指引入口
                    if let photoID = draft.sourcePhotoID {
                        NavigationLink(value: Route.redPacketUploadGuide(
                            photoID: photoID, petID: nil
                        )) {
                            Text(String(localized: "redpacket.uploadGuide.link"))
                                .font(.uiBodyStrong)
                                .foregroundStyle(Color.milensActionPrimary)
                        }
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.lg)
                    }

                    Spacer(minLength: 100)
                }
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
        }
    }

    // MARK: - 成品检查段

    private func 成品检查段(draft: RedPacketCoverDraft, template: RedPacketTemplate) -> some View {
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

            // 规格信息
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
                    specRow(
                        label: String(localized: "redpacket.export.status"),
                        value: RedPacketExportLogic.isWithinSizeLimit(data.data)
                            ? String(localized: "redpacket.export.passed")
                            : String(localized: "redpacket.export.exceeded"),
                        valueColor: RedPacketExportLogic.isWithinSizeLimit(data.data)
                            ? .green : .red
                    )
                }
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.sm)
        }
    }

    // MARK: - 聊天预览段

    private func 聊天预览段(draft: RedPacketCoverDraft, template: RedPacketTemplate) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            EditorialOverline(text: String(localized: "redpacket.export.chatPreview"))
                .padding(.horizontal, Spacing.pagePad)
                .padding(.top, Spacing.xl)

            // 中性聊天红包卡片预览
            if let image = renderedImage {
                chatCardPreview(image: image, draft: draft)
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

    // MARK: - 聊天卡片预览

    private func chatCardPreview(image: UIImage, draft: RedPacketCoverDraft) -> some View {
        VStack(spacing: 8) {
            // 模拟聊天消息
            HStack(alignment: .top, spacing: 8) {
                // 头像占位
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundStyle(Color.gray)
                    }

                // 红包卡片
                VStack(alignment: .leading, spacing: 4) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 107)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    Text(draft.coverTitle.isEmpty ? "恭喜发财" : draft.coverTitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.milensTextPrimary)
                        .lineLimit(1)
                }
                .padding(10)
                .background(Color.orange.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer()
            }

            Text(String(localized: "redpacket.export.scenePreview"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextSecondary)
        }
        .padding(12)
        .background(Color.milensSealSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - 操作栏

    private var actionBar: some View {
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
        } catch {
            logger.error("share: 写入分享缓存失败 \(error.localizedDescription)")
        }
    }

    private func saveToLibrary() async {
        guard let data = exportData else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await BeadExportService().saveToPhotoLibrary(pngData: data.data)
        } catch {
            logger.error("saveToLibrary: 保存失败 \(error.localizedDescription)")
            saveError = "保存到相册失败：\(error.localizedDescription)"
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

            // 渲染封面
            guard let rendered = renderCover() else { return }
            renderedImage = rendered

            // 编码
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
