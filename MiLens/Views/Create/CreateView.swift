//  创作（Tab 3）—— 大卡片入口（UI-DESIGN.md §6.6）。
//  「拼豆图纸」大卡片 → 选照片（BeadPhotoPickerView）→ 拼豆工作室；
//  「宠物卡片」功能未实现（PLAN.md P4 遗留，依赖 AI 方案定案），
//  按计划 §8 留禁用态占位并诚实标注，不做成看似可用的假入口。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "Create")

struct CreateView: View {
    @Environment(\.photoRepository) private var photoRepo

    @State private var photos: [Photo] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Color.milensPrimary)
            } else if photos.isEmpty {
                emptyState
            } else {
                cardList
            }
        }
        .background(Color.milensBackground)
        .navigationTitle(String(localized: "tab.create"))
        .navigationBarTitleDisplayMode(.large)
        .task { await loadPhotos() }
    }

    // MARK: - 大卡片列表

    private var cardList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("选一张照片，把它变成可以动手做的作品。")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.top, Spacing.xs)

                beadEntryCard
                petCardPlaceholder
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    /// 拼豆图纸入口：真实照片像素化示意 + displayMedium 标题。
    private var beadEntryCard: some View {
        NavigationLink(value: Route.beadPhotoPicker) {
            VStack(alignment: .leading, spacing: 0) {
                BeadExampleVisual(path: photos.first.map {
                    $0.thumbnailPath.isEmpty ? $0.uri : $0.thumbnailPath
                } ?? "")
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()

                HStack(alignment: .center, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("拼豆图纸")
                            .font(.displayMedium)
                            .foregroundStyle(Color.milensTextPrimary)
                        Text("把照片变成一格一格的拼豆图案，附配色方案与材料清单")
                            .font(.bodySecondary)
                            .foregroundStyle(Color.milensTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: Sizing.iconSm, weight: .semibold))
                        .foregroundStyle(Color.milensTextOnActionPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color.milensActionPrimary)
                        .clipShape(Circle())
                }
                .padding(Spacing.lg)
            }
            .background(Color.milensCard)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(Color.milensBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("拼豆图纸，选择照片开始")
    }

    /// 宠物卡片占位：功能未实现，禁用态 + 诚实标注（不用品牌色、不可点击）。
    private var petCardPlaceholder: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Text("宠物卡片")
                    .font(.displayMedium)
                    .foregroundStyle(Color.milensTextPrimary)
                Text("待设计稿定案")
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.milensGrouped)
                    .clipShape(Capsule())
            }
            Text("把它的照片做成一张可以保存和分享的档案卡片。这张卡片的样子还在设计中，定稿前不会开放入口。")
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(Color.milensCard)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("宠物卡片，待设计稿定案，暂不可用")
    }

    // MARK: - 空态

    private var emptyState: some View {
        ContentUnavailableView(
            "还没有照片",
            systemImage: "photo.on.rectangle.angled",
            description: Text("先到相册导入照片，再回来生成拼豆图纸")
        )
    }

    // MARK: - 数据

    @MainActor
    private func loadPhotos() async {
        defer { isLoading = false }
        do {
            photos = try photoRepo.getPhotosPage(offset: 0, limit: 200)
        } catch {
            logger.error("loadPhotos: 读取照片列表失败（\(error.localizedDescription)）")
            photos = []
        }
    }
}

// MARK: - 拼豆示意视觉

/// 用第一张真实照片做像素化处理，作为「原图 → 拼豆」的示例视觉；
/// 加载失败时回退为中性表面（不伪造品牌插画）。
private struct BeadExampleVisual: View {
    let path: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.milensGrouped
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "circle.grid.3x3.fill")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.milensTextTertiary)
            }
        }
        .task(id: path) {
            guard image == nil, !path.isEmpty else { return }
            image = await Self.loadPixelated(path: path)
        }
        .accessibilityHidden(true)
    }

    private static func loadPixelated(path: String) async -> UIImage? {
        await Task.detached(priority: .utility) {
            guard let source = UIImage(contentsOfFile: path),
                  let cgImage = source.cgImage else { return nil }
            let ciImage = CIImage(cgImage: cgImage)
            guard let filter = CIFilter(name: "CIPixellate") else { return nil }
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(max(ciImage.extent.width, ciImage.extent.height) / 36,
                            forKey: kCIInputScaleKey)
            guard let output = filter.outputImage,
                  let outCG = CIContext().createCGImage(output, from: ciImage.extent) else { return nil }
            return UIImage(cgImage: outCG)
        }.value
    }
}
