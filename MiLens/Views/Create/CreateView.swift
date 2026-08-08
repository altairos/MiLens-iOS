//  CreateView —— 创作（Tab 3）。
//
//  创作页只呈现当前真正可用的项目；未实现能力不再以占位卡片占据页面。
//  页面语言是「照片 → 作品」的档案式入口，而不是功能宫格。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "Create")

struct CreateView: View {
    @Environment(\.photoRepository) private var photoRepo
    @Environment(\.proEntitlement) private var entitlement

    @State private var photos: [Photo] = []
    @State private var isLoading = true
    @State private var showPaywall = false

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
        .navigationTitle(String(localized: "tab.create"))
        .navigationBarTitleDisplayMode(.large)
        .task { await loadPhotos() }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ArchiveMarker(label: "创作")
                    .padding(.top, Spacing.sm)

                Text("让照片继续有去处。")
                    .font(.displayMedium)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.top, Spacing.lg)

                Text("从已经保存的照片开始，做一份真正属于它的作品。")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.sm)

                ArchiveSectionHeader(
                    title: "可以开始的作品",
                    supporting: photos.isEmpty ? nil : "选择一张照片"
                )
                .padding(.top, Spacing.xxl)

                if photos.isEmpty {
                    emptyState
                } else {
                    beadEntry
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.pagePad)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    private var beadEntry: some View {
        Group {
            if entitlement.isPro {
                NavigationLink(value: Route.beadPhotoPicker) {
                    beadProjectRow
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showPaywall = true
                } label: {
                    beadProjectRow
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityLabel("拼豆图纸，选择照片开始")
    }

    private var beadProjectRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.lg) {
                BeadExampleVisual(path: photos.first.map {
                    $0.thumbnailPath.isEmpty ? $0.uri : $0.thumbnailPath
                } ?? "")
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        Text("拼豆图纸")
                            .font(.titleStandard)
                            .foregroundStyle(Color.milensTextPrimary)
                        if !entitlement.isPro {
                            Text("Pro")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.milensActionPrimary)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(Color.milensAccentSoft)
                                .clipShape(Capsule())
                        }
                    }

                    Text("把一张照片变成可动手完成的图案，附配色方案与材料清单。")
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Spacing.sm)

                Image(systemName: "chevron.right")
                    .font(.system(size: Sizing.iconSm, weight: .semibold))
                    .foregroundStyle(Color.milensTextTertiary)
                    .frame(width: Sizing.touchTarget, height: Sizing.touchTarget)
            }
            .padding(.vertical, Spacing.lg)

            ArchiveDivider()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("先保存一张照片")
                .font(.bodyPrimary.weight(.semibold))
                .foregroundStyle(Color.milensTextPrimary)
            Text("从相册导入照片后，就可以从这里开始创作。")
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)

            NavigationLink(value: Route.gallery) {
                HStack(spacing: Spacing.sm) {
                    Text("去相册添加")
                        .font(.buttonLabel)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: Sizing.iconSm, weight: .semibold))
                }
                .foregroundStyle(Color.milensActionPrimary)
                .frame(minHeight: Sizing.touchTarget)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Spacing.lg)
    }

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

/// 使用第一张真实照片作为「原图 → 拼豆」的入口预览；失败时保持中性表面。
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
                    .font(.system(size: 28, weight: .light))
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

#Preview {
    NavigationStack {
        CreateView()
    }
}
