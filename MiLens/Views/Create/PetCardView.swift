//  PetCardView —— 宠物卡片生成页（P4，route .petCard，对应创作 Tab「宠物卡片」项目）。
//
//  卡片 = 一张照片 + 宠物信息排版（UI-DESIGN.md §6.6）。iOS 自研 MVP：
//  预览与导出共用 PetCardArtwork（同一排版，导出用 ImageRenderer 固定 1080×1350）。
//  保存相册走 PHPhotoLibrary（复用 BeadExportService），分享走系统分享单。

import SwiftUI
import UIKit
import Photos
import MiLensKit
import os

private let logger = Logger(subsystem: "com.milens.app", category: "PetCard")

struct PetCardView: View {
    let photoID: UUID
    /// ADR-0010 §10.11：情感卡片类型（nil = 普通纪念卡，行为同 P4）。
    var kind: MemoryCardKind? = nil

    @Environment(\.viewModelFactory) private var factory
    @Environment(\.proEntitlement) private var entitlement
    @Environment(\.dismiss) private var dismiss

    @State private var photo: Photo?
    @State private var image: UIImage?
    @State private var content: PetCardContent?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var shareItem: ShareItem?
    @State private var saveError: String?
    /// ADR-0010 分享预览面板状态。
    @State private var sharePreview: (image: UIImage, url: URL, filename: String, spec: String)?
    /// 保存到相册的统一成功/失败反馈（顶部胶囊 + 触感）。
    @State private var exportToast: ExportToastMessage?
    /// ADR-0010 §4：卡片模板选择（持久化到 UserDefaults）。
    @AppStorage("petCardTemplate") private var selectedTemplateRaw: String = PetCardTemplate.classic.rawValue
    /// ADR-0010 §4：非 Pro 用户点击 Pro 模板时弹付费墙。
    @State private var showTemplatePaywall = false
    /// Figma 07 Annotation Register：一行注释（Display + 编辑 sheet）。
    @State private var annotation = ""
    @State private var showAnnotationEditor = false

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
        .toolbar(.hidden, for: .navigationBar)
        .exportToast($exportToast)
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        // ADR-0010 分享预览面板
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
        .alert(String(localized: "create.save.failed"), isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        // ADR-0010 §4.2：Pro 模板门控弹窗
        .sheet(isPresented: $showTemplatePaywall) {
            NavigationStack { PaywallView() }
        }
        // Figma 07A：注释编辑 sheet
        .sheet(isPresented: $showAnnotationEditor) {
            AnnotationEditorSheet(annotation: $annotation, limit: 36)
        }
        .task {
            await load()
            MetricsRecorder().record(.memoryCardPreviewed)
        }
    }

    // MARK: - 预览

    private var selectedTemplate: PetCardTemplate {
        PetCardTemplate(rawValue: selectedTemplateRaw) ?? .classic
    }

    /// 当前 Pro 状态下实际生效的模板（免费用户回退到 classic）。
    private var resolvedTemplate: PetCardTemplate {
        PetCardTemplate.resolve(selectedTemplate, isPro: entitlement.isPro)
    }

    private func cardPreview(image: UIImage, content: PetCardContent) -> some View {
        VStack(spacing: 0) {
            WorkshopNavHeader(title: String(localized: "create.petCard.title")) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 来源条
                    if let photo {
                        WorkshopSourceBar(
                            meta: String(localized: "source.petCard.meta"),
                            label: photo.pet?.name ?? String(localized: "create.petCard.title"),
                            onChange: { dismiss() }
                        ) {
                            ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                        }
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.md)
                    }

                    // Overline + 规格
                    HStack {
                        EditorialOverline(text: String(localized: "petcard.overline"))
                        Spacer()
                        Text(String(localized: "petcard.spec"))
                            .font(.editorialMetadata)
                            .foregroundStyle(Color.milensTextSecondary)
                    }
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.lg)

                    // 预览即导出排版（同一 Artwork，等比缩放）
                    PetCardArtwork(
                        image: image,
                        content: content,
                        template: resolvedTemplate,
                        includeWatermark: !entitlement.isPro
                    )
                        .frame(maxWidth: 342)
                        .aspectRatio(PetCardLogic.exportSize.width.cg / PetCardLogic.exportSize.height.cg,
                                     contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                                .stroke(Color.milensBorder, lineWidth: 0.5)
                        }
                        .elevation(.medium)
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.sm)

                    // 模板选择器
                    Text(String(localized: "businesscard.selectTemplate"))
                        .font(.uiBodyStrong)
                        .foregroundStyle(Color.milensTextPrimary)
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.xl)

                    templateRail
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.xs)

                    // 注释行
                    WorkshopFieldRow(
                        label: String(localized: "field.annotation.label"),
                        value: annotation.isEmpty ? String(localized: "field.annotation.placeholder") : annotation,
                        onEdit: { showAnnotationEditor = true },
                        showsRule: false
                    )
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, Spacing.xl)

                    Spacer(minLength: 100)
                }
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                CreationActionBar(
                    primaryLabel: String(localized: "action.saveShare"),
                    secondaryLabel: String(localized: "action.saveDraft"),
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

    // MARK: - 模板选择器（WorkshopTemplateTab）

    private var templateRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(Array(PetCardTemplate.allTemplates.enumerated()), id: \.element.id) { index, template in
                    WorkshopTemplateTab(
                        index: String(format: "%02d", index + 1),
                        label: template.displayName,
                        state: templateState(template),
                        action: {
                            if template.isUsable(isPro: entitlement.isPro) {
                                selectedTemplateRaw = template.rawValue
                            } else {
                                showTemplatePaywall = true
                            }
                        }
                    )
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private func templateState(_ template: PetCardTemplate) -> WorkshopTemplateState {
        if !template.isUsable(isPro: entitlement.isPro) { return .locked }
        return selectedTemplate == template ? .selected : .default
    }

    // MARK: - 动作

    /// 渲染 1080×1350 卡片 PNG（预览与导出同源排版）。
    private func renderCard() -> UIImage? {
        guard let image, let content else { return nil }
        let size = PetCardLogic.exportSize
        let artwork = PetCardArtwork(
            image: image,
            content: content,
            template: resolvedTemplate,
            includeWatermark: !entitlement.isPro
        )
            .frame(width: size.width.cg, height: size.height.cg)
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 1
        return renderer.uiImage
    }

    private func saveToLibrary() async {
        guard let rendered = renderCard() else {
            exportToast = .failure(String(localized: "create.render.failed"))
            return
        }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.9) else {
            exportToast = .failure(String(localized: "create.encode.failed"))
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await BeadExportService().saveToPhotoLibrary(pngData: jpeg)
            exportToast = .success(String(localized: "create.save.success"))
        } catch {
            logger.error("saveToLibrary: 保存失败（\(error.localizedDescription)）")
            saveError = String(localized: "create.save.libraryFailed \(error.localizedDescription)")
        }
    }

    private func share() {
        guard let rendered = renderCard(),
              let jpeg = rendered.jpegData(compressionQuality: 0.9) else { return }
        let petName = photo?.pet?.name ?? ""
        let filename = "MiLens_\(petName)_\(String(localized: "create.petCard.title")).jpg"
        let spec = "\(PetCardLogic.exportSize.width) × \(PetCardLogic.exportSize.height) · JPEG · \(formatByteCount(jpeg.count))"
        do {
            let url = try BeadExportService().writeShareCache(data: jpeg, filename: filename)
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

    // MARK: - 加载失败

    private var loadFailedView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40)) // ui-token:ok 错误态装饰大图标
                .foregroundStyle(Color.milensTextSecondary)
            Text(String(localized: "create.load.failed"))
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
            content = PetCardLogic.content(pet: photo.pet, takenAt: photo.takenAt, kind: kind)
        } catch {
            logger.error("load: 读取照片失败（\(error.localizedDescription)）")
        }
    }
}

// MARK: - 注释编辑 Sheet（Figma 07A Annotation Editing）

/// 一行注释的原位编辑 sheet（Display + Editing 统一草稿）。
/// 36 个中文字符上限；空值回退到占位文案。
/// PetCard / GrowthCompare 共用。
struct AnnotationEditorSheet: View {
    @Binding var annotation: String
    let limit: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(String(localized: "field.annotation.placeholder"))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
                TextField(String(localized: "field.annotation.placeholder"), text: $annotation, axis: .horizontal)
                    .font(.bodyPrimary)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: annotation) { _, newValue in
                        if newValue.count > limit {
                            annotation = String(newValue.prefix(limit))
                        }
                    }
                Text("\(annotation.count)/\(limit)")
                    .font(.caption)
                    .foregroundStyle(Color.milensTextTertiary)
                Spacer()
            }
            .padding(Spacing.lg)
            .navigationTitle(String(localized: "field.annotation.label"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.ok")) { dismiss() }
                }
            }
        }
    }
}

// MARK: - 卡片排版（预览与导出共用）

/// 宠物卡片版式：照片铺底 + 底部暖黑渐变 + 名字/物种/日期行。
/// 字号与间距按画布宽度比例缩放（预览与 1080px 导出同源）。
struct PetCardArtwork: View {
    let image: UIImage
    let content: PetCardContent
    /// ADR-0010 §4：卡片模板（决定排版分支）。
    var template: PetCardTemplate = .classic
    /// ADR-0010：免费版导出在底部渐变区显示半透明「MiLens」水印。
    var includeWatermark: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            switch template {
            case .classic:
                classicLayout(w: w, h: h)
            case .polaroid:
                polaroidLayout(w: w, h: h)
            case .magazine:
                magazineLayout(w: w, h: h)
            case .minimal:
                minimalLayout(w: w, h: h)
            }
        }
        .aspectRatio(PetCardLogic.exportSize.width.cg / PetCardLogic.exportSize.height.cg,
                     contentMode: .fit)
    }

    // MARK: - 经典（全屏照片 + 底部渐变 + 左下文字）

    private func classicLayout(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: w, height: h)
                .clipped()

            LinearGradient(
                colors: [Color.black.opacity(0.78), Color.black.opacity(0.0)],
                startPoint: .bottom, endPoint: .top
            )
            .frame(height: h * PetCardLogic.gradientHeightRatio)
            .frame(maxHeight: .infinity, alignment: .bottom)

            classicTextBlock(w: w)

            watermarkOverlay(w: w)
        }
    }

    private func classicTextBlock(w: CGFloat) -> some View {
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

    // MARK: - 拍立得（白边相框 + 底部文字区）

    private func polaroidLayout(w: CGFloat, h: CGFloat) -> some View {
        let border = w * 0.06
        let photoH = h * 0.70
        return VStack(spacing: 0) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: w - border * 2, height: photoH)
                .clipped()
                .padding(.top, border)
            // 底部文字区（白底深字）
            VStack(alignment: .leading, spacing: w * 0.02) {
                Text(content.title)
                    .font(.custom("LXGWWenKai-Regular", size: w * 0.075))
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(content.emoji) \(content.subtitle) · \(content.dateLine)")
                    .font(.system(size: w * 0.034, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.milensTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, border)
            .padding(.top, w * 0.04)
            .padding(.bottom, border)
            .frame(maxHeight: .infinity)
            .background(Color.white)
            .overlay(alignment: .bottomTrailing) {
                if includeWatermark {
                    Text("MiLens")
                        .font(.system(size: w * 0.028, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.milensTextTertiary)
                        .padding(border * 0.5)
                }
            }
        }
        .frame(width: w, height: h)
        .background(Color.white)
    }

    // MARK: - 杂志（照片偏上 + 大标题 + 细副标题）

    private func magazineLayout(w: CGFloat, h: CGFloat) -> some View {
        let photoH = h * 0.58
        return VStack(spacing: 0) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: w, height: photoH)
                .clipped()

            VStack(alignment: .leading, spacing: w * 0.03) {
                Text("\(content.emoji) \(content.subtitle)")
                    .font(.system(size: w * 0.038, weight: .light, design: .serif))
                    .foregroundStyle(Color.milensTextSecondary)
                    .tracking(w * 0.008)

                Text(content.title)
                    .font(.custom("LXGWWenKai-Regular", size: w * 0.12))
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Spacer(minLength: 0)

                Text(content.dateLine)
                    .font(.system(size: w * 0.034, weight: .regular, design: .serif))
                    .foregroundStyle(Color.milensTextSecondary)
            }
            .padding(w * 0.08)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.milensBackground)
            .overlay(alignment: .bottomTrailing) {
                if includeWatermark {
                    Text("MiLens")
                        .font(.system(size: w * 0.028, weight: .medium, design: .serif))
                        .foregroundStyle(Color.milensTextTertiary)
                        .padding(w * 0.05)
                }
            }
        }
        .frame(width: w, height: h)
    }

    // MARK: - 极简（纯照片 + 右下角小字）

    private func minimalLayout(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: w, height: h)
                .clipped()

            // 极轻微底部渐变保证文字可读
            LinearGradient(
                colors: [Color.black.opacity(0.45), Color.black.opacity(0.0)],
                startPoint: .bottom, endPoint: .top
            )
            .frame(height: h * 0.22)
            .frame(maxHeight: .infinity, alignment: .bottom)

            VStack(alignment: .trailing, spacing: w * 0.012) {
                Text("\(content.emoji) \(content.title)")
                    .font(.system(size: w * 0.04, weight: .medium, design: .default))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(content.dateLine)
                    .font(.system(size: w * 0.028, weight: .regular, design: .default))
                    .foregroundStyle(.white.opacity(0.65))
                if includeWatermark {
                    Text("MiLens")
                        .font(.system(size: w * 0.024, weight: .medium, design: .default))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(w * 0.06)
            .padding(.bottom, w * 0.03)
        }
    }

    // MARK: - 水印辅助（仅 classic 用）

    @ViewBuilder
    private func watermarkOverlay(w: CGFloat) -> some View {
        if includeWatermark {
            Text("MiLens")
                .font(.system(size: w * 0.03, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .padding(w * 0.05)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
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
