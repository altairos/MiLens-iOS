//  RedPacketExportView —— 红包导出页（对应红包封面开发计划 §6）。
//
//  上段：分享前预览（聊天红包卡片 / 拆红包 / 红包列表多场景模拟，见 RedPacketScenePreview.swift）。
//  下段：底部上滑面板（使用步骤 + 系统分享 + 上传指引入口）。
//  封面和预览共用 RedPacketCoverRenderer 渲染结果（不两套排版逻辑）。

import SwiftUI
import UIKit
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
        ZStack(alignment: .bottom) {
            // 上层：场景预览区（全屏背景 + 编辑式标题 + 预览）
            VStack(spacing: 0) {
                WorkshopNavHeader(title: String(localized: "redpacket.export.shareTitle")) {
                    dismiss()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Overline + 编辑式标题
                        EditorialOverline(text: String(localized: "redpacket.export.sceneOverline"))
                            .padding(.horizontal, Spacing.pagePad)
                            .padding(.top, Spacing.lg)

                        Text(String(localized: "redpacket.export.editorialTitle"))
                            .font(.editorialSection)
                            .foregroundStyle(Color.milensTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Spacing.pagePad)
                            .padding(.top, Spacing.xs)

                        // 场景预览
                        if let image = renderedImage {
                            RedPacketScenePreview(image: image, draft: draft, selectedScene: $selectedScene)
                                .padding(.horizontal, Spacing.pagePad)
                                .padding(.top, Spacing.lg)
                        }
                    }
                    .padding(.bottom, 380) // 为底部面板留空间
                }
                .scrollIndicators(.hidden)
            }

            // 底层：底部上滑面板（使用步骤 + 保存或分享）
            exportBottomSheet
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

    // MARK: - 底部上滑面板

    private var exportBottomSheet: some View {
        VStack(spacing: 0) {
            // 使用步骤
            usageStepsCard
                .padding(.horizontal, Spacing.pagePad)
                .padding(.top, Spacing.lg)

            // 上传指引入口
            uploadGuideEntry

            // 保存中提示
            if isSaving {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.top, Spacing.sm)
            }

            // 保存或分享
            CreationActionBar(
                primaryLabel: String(localized: "redpacket.export.saveOrShare"),
                secondaryLabel: String(localized: "redpacket.export.discard"),
                primaryAction: { share() },
                secondaryAction: { dismiss() }
            )
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.md)
        }
        .padding(.top, Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.milensBackground)
                .shadow(color: .black.opacity(0.08), radius: 8, y: -2)
        )
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
        .padding(.top, Spacing.sm)
    }

    // MARK: - 使用步骤卡

    private var usageStepsCard: some View {
        HStack(spacing: 12) {
            usageStep(number: "1", text: String(localized: "redpacket.export.step.saveImage"))
            usageStep(number: "2", text: String(localized: "redpacket.export.step.openCover"))
            usageStep(number: "3", text: String(localized: "redpacket.export.step.selectCustom"))
        }
        .padding(.top, Spacing.sm)
    }

    private func usageStep(number: String, text: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.milensTextPrimary.opacity(0.14))
                    .frame(width: 22, height: 22)
                Text(number)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.milensActionPrimary)
            }
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.milensTextPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .background(Color.milensSealSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.milensSeparator, lineWidth: 1)
        )
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

    // MARK: - 渲染

    private func renderCover(petImage: UIImage?) -> UIImage? {
        guard let template else { return nil }
        let layers = draft?.layers ?? rpDefaultLayers(for: template)
        let renderer = ImageRenderer(content:
            RedPacketCoverRenderer(
                template: template,
                layers: layers,
                petImage: petImage,
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

            // 工作室 VM 不跨页面存活：按 pet 层 mattePath 回灌持久化的抠图 PNG。
            let petImage = petCutoutImage(from: loaded, store: store)

            guard let rendered = renderCover(petImage: petImage) else { return }
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

    /// 读取草稿持久化的宠物抠图（pet 层 mattePath 标记，PNG 存于草稿目录）。
    private func petCutoutImage(
        from draft: RedPacketCoverDraft,
        store: RedPacketDraftStore
    ) -> UIImage? {
        guard draft.layers.first(where: { $0.kind == .pet })?.mattePath != nil,
              let data = store.loadCutoutPNG(id: draft.id) else { return nil }
        return UIImage(data: data)
    }
}

#Preview {
    NavigationStack {
        RedPacketExportView(draftID: UUID())
    }
}
