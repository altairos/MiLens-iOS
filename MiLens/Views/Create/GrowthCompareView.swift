//  GrowthCompareView —— 成长对比卡片生成页（ADR-0010 §3.3，Stage 2）。
//
//  两张照片并排（早期上 / 近期下）+ 时间标签 + 间隔 + 宠物名。
//  预览与导出共用 GrowthCompareArtwork（同一排版，导出用 ImageRenderer 固定 1080×1350）。
//  保存相册走 PHPhotoLibrary（复用 BeadExportService），分享走系统分享。
//  Pro 门控：免费版带水印，Pro 无水印（ADR-0010 §2.3）。

import SwiftUI
import UIKit
import Photos
import MiLensKit
import os

private let logger = Logger(subsystem: "com.milens.app", category: "GrowthCompare")

struct GrowthCompareView: View {
    let earlyPhotoID: UUID
    let latePhotoID: UUID
    let petID: UUID?

    @Environment(\.viewModelFactory) private var factory
    @Environment(\.proEntitlement) private var entitlement

    @State private var earlyImage: UIImage?
    @State private var lateImage: UIImage?
    @State private var petName = ""
    @State private var birthday: Date?
    @State private var result: GrowthCompareResult?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var shareItem: ShareItem?
    @State private var saveError: String?
    @State private var sharePreview: (image: UIImage, url: URL)?
    /// 保存到相册的统一成功/失败反馈（顶部胶囊 + 触感）。
    @State private var exportToast: ExportToastMessage?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Color.milensActionPrimary)
            } else if let earlyImage, let lateImage, let result {
                previewStack(early: earlyImage, late: lateImage, result: result)
            } else {
                loadFailedView
            }
        }
        .background(Color.milensBackground)
        .navigationTitle(String(localized: "create.growthCompare.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await saveToLibrary() }
                } label: {
                    Label(String(localized: "common.save"), systemImage: "square.and.arrow.down")
                }
                .disabled(isSaving)

                Button {
                    share()
                } label: {
                    Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
                }
                .disabled(isSaving)
            }
        }
        .exportToast($exportToast)
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
        .alert(String(localized: "create.save.failed"), isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .task { await load() }
    }

    // MARK: - 预览

    private func previewStack(early: UIImage, late: UIImage, result: GrowthCompareResult) -> some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                GrowthCompareArtwork(
                    earlyImage: early,
                    lateImage: late,
                    result: result,
                    petName: petName,
                    includeWatermark: !entitlement.isPro
                )
                    .frame(maxWidth: 480)
                    .aspectRatio(
                        Double(GrowthCompareLogic.exportWidth) / Double(GrowthCompareLogic.exportHeight),
                        contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                            .stroke(Color.milensBorder, lineWidth: 0.5)
                    }

                Text(String(localized: "create.growthCompare.hint"))
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

    private func renderCard() -> UIImage? {
        guard let earlyImage, let lateImage, let result else { return nil }
        let w = GrowthCompareLogic.exportWidth
        let h = GrowthCompareLogic.exportHeight
        let artwork = GrowthCompareArtwork(
            earlyImage: earlyImage,
            lateImage: lateImage,
            result: result,
            petName: petName,
            includeWatermark: !entitlement.isPro
        )
            .frame(width: CGFloat(w), height: CGFloat(h))
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 1
        return renderer.uiImage
    }

    private func saveToLibrary() async {
        guard let rendered = renderCard() else {
            exportToast = .failure(String(localized: "create.render.failed"))
            return
        }
        let quality = ExportQuality.standard.resolved(isPro: entitlement.isPro)
        guard let jpeg = rendered.jpegData(compressionQuality: quality.jpegCompressionQuality) else {
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
        guard let rendered = renderCard() else { return }
        let quality = ExportQuality.standard.resolved(isPro: entitlement.isPro)
        guard let jpeg = rendered.jpegData(compressionQuality: quality.jpegCompressionQuality) else { return }
        do {
            let url = try BeadExportService().writeShareCache(data: jpeg, filename: "growth_compare_share.jpg")
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
            guard let earlyPhoto = try factory.photo(id: earlyPhotoID),
                  let latePhoto = try factory.photo(id: latePhotoID) else { return }

            let earlyProj = GrowthComparePhoto(id: earlyPhoto.id, takenAt: earlyPhoto.takenAt)
            let lateProj = GrowthComparePhoto(id: latePhoto.id, takenAt: latePhoto.takenAt)

            // 宠物信息：优先用 petID，回退照片归属（SwiftData @Relationship 已加载）
            var pet = earlyPhoto.pet ?? latePhoto.pet
            if let petID, let resolved = try factory.pet(id: petID) { pet = resolved }
            petName = pet?.name ?? ""
            birthday = pet?.birthday

            result = GrowthCompareLogic.buildResult(
                early: earlyProj, late: lateProj, birthday: birthday)

            // 按 result 的早/晚顺序加载图片
            let earlyPath = earlyPhoto.thumbnailPath.isEmpty ? earlyPhoto.uri : earlyPhoto.thumbnailPath
            let latePath = latePhoto.thumbnailPath.isEmpty ? latePhoto.uri : latePhoto.thumbnailPath
            let pathMap: [UUID: String] = [earlyPhoto.id: earlyPath, latePhoto.id: latePath]
            async let earlyLoad = loadImage(at: pathMap[result!.earlyPhotoID] ?? "")
            async let lateLoad = loadImage(at: pathMap[result!.latePhotoID] ?? "")
            earlyImage = await earlyLoad
            lateImage = await lateLoad
        } catch {
            logger.error("load: 读取照片失败（\(error.localizedDescription)）")
        }
    }

    private func loadImage(at path: String) async -> UIImage? {
        guard !path.isEmpty else { return nil }
        return await Task.detached(priority: .utility) {
            UIImage(contentsOfFile: path)
        }.value
    }
}

// MARK: - 双图版式（预览与导出共用）

/// 成长对比版式：早期照片上 + 近期照片下 + 时间标签 + 间隔 + 宠物名。
/// 字号与间距按画布宽度比例缩放（预览与 1080px 导出同源）。
struct GrowthCompareArtwork: View {
    let earlyImage: UIImage
    let lateImage: UIImage
    let result: GrowthCompareResult
    var petName: String = ""
    var includeWatermark: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let photoH = h * 0.42
            let footerH = h * 0.16
            VStack(spacing: 0) {
                photoBlock(earlyImage, label: result.earlyLabel, height: photoH, w: w)

                // 中间间隔标签条
                ZStack {
                    Color.black
                    Text(result.gapLabel.isEmpty ? "成长对比" : result.gapLabel)
                        .font(.custom("LXGWWenKai-Regular", size: w * 0.05))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .frame(width: w, height: h * 0.04)

                photoBlock(lateImage, label: result.lateLabel, height: photoH, w: w)

                // 底部签名区
                footerBlock(w: w, h: footerH)
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(
            Double(GrowthCompareLogic.exportWidth) / Double(GrowthCompareLogic.exportHeight),
            contentMode: .fit)
    }

    @ViewBuilder
    private func photoBlock(_ image: UIImage, label: String, height: CGFloat, w: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: w, height: height)
                .clipped()

            LinearGradient(
                colors: [Color.black.opacity(0.6), Color.black.opacity(0.0)],
                startPoint: .bottom, endPoint: .top
            )
            .frame(height: height * 0.35)
            .frame(maxHeight: .infinity, alignment: .bottom)

            Text(label)
                .font(.system(size: w * 0.038, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, w * 0.06)
                .padding(.bottom, w * 0.03)
        }
        .frame(width: w, height: height)
        .clipped()
    }

    @ViewBuilder
    private func footerBlock(w: CGFloat, h: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: w * 0.015) {
                Text(petName.isEmpty ? "成长对比" : petName)
                    .font(.custom("LXGWWenKai-Regular", size: w * 0.06))
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("成长对比")
                    .font(.system(size: w * 0.028, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.milensTextTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.milensBackground)

            if includeWatermark {
                Text("MiLens")
                    .font(.system(size: w * 0.026, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.milensTextTertiary)
                    .padding(w * 0.04)
            }
        }
        .frame(width: w, height: h)
    }
}

#Preview {
    NavigationStack {
        GrowthCompareView(
            earlyPhotoID: UUID(),
            latePhotoID: UUID(),
            petID: nil
        )
    }
}
