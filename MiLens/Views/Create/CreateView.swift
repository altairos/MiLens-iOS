//  CreateView —— 创作（Tab 3）。
//
//  Workshop 编辑式浅色设计（对照 Figma「01 · Creation / Studio Index」#422:805）：
//  浅色背景 + Fraunces 品牌标 + 编辑式小标 + 编号项目不等大网格。
//  5 个创作项目按杂志式非对称排列（大卡 + 双栏 + 横条），不做等权卡片宫格。
//  页面语言是「照片 → 作品」的档案式入口。

import SwiftUI
import os

private let logger = Logger(subsystem: "com.milens.app", category: "Create")

struct CreateView: View {
    @Environment(\.viewModelFactory) private var factory
    @Environment(\.proEntitlement) private var entitlement

    @State private var photos: [Photo] = []
    @State private var isLoading = true

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
        .task { await loadPhotos() }
    }

    // MARK: - 主内容

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, 52)
                    .padding(.bottom, Spacing.lg)

                if photos.isEmpty {
                    emptyState
                        .padding(.horizontal, Spacing.pagePad)
                } else {
                    projectGrid
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.bottom, Spacing.xxl)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 头部（对照 Figma 422:805 顶部）

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MiLens")
                .font(.displayLargeEN)
                .foregroundStyle(Color.milensTextPrimary)

            EditorialOverline(text: String(localized: "create.studio.overline"))
                .padding(.top, Spacing.xs)

            Text(String(localized: "create.studio.title"))
                .font(.editorialSection)
                .foregroundStyle(Color.milensTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Spacing.sm)
        }
    }

    // MARK: - 项目网格（杂志式非对称布局）

    /// 对照 Figma 422:805 项目区：
    /// - 01 拼豆工作室：342×202 暗色大卡（满宽）
    /// - 左 02 伙伴卡片 158×222 + 右 [03 成长对比 166×102 + 04 名片 166×102]
    /// - 05 红包封面：342×78 珊瑚横条（满宽）
    private var projectGrid: some View {
        VStack(spacing: 16) {
            beadEntry
            HStack(alignment: .top, spacing: 16) {
                petCardEntry
                VStack(spacing: 18) {
                    growthCompareEntry
                    businessCardEntry
                }
            }
            redPacketEntry
        }
    }

    // MARK: - 01 拼豆工作室（暗色大卡）

    private var beadEntry: some View {
        NavigationLink(value: Route.beadPhotoPicker) {
            beadCard
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "a11y.create.beadEntry"))
    }

    private var beadCard: some View {
        ZStack(alignment: .bottomLeading) {
            BeadExampleVisual(path: photos.first.map {
                $0.thumbnailPath.isEmpty ? $0.uri : $0.thumbnailPath
            } ?? "")
            .clipped()

            // 底部渐变
            LinearGradient(
                colors: [Color.black.opacity(0.08), Color.black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .accessibilityHidden(true)

            // 编号
            Text("01")
                .font(.editorialNumberIndex)
                .foregroundStyle(.white)
                .padding(.leading, 18)
                .padding(.top, 16)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            // 底部文案
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "create.bead.title"))
                    .font(.uiTitle)
                    .foregroundStyle(.white)
                Text(String(localized: "create.project.bead.desc"))
                    .font(.editorialMetadata)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.leading, 18)
            .padding(.bottom, 16)

            // 右上箭头
            Text("↗")
                .font(.uiTitle)
                .foregroundStyle(.white)
                .padding(.trailing, 18)
                .padding(.top, 16)
                .frame(maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(width: 342, height: 202)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - 02 伙伴卡片（竖版白卡）

    private var petCardEntry: some View {
        NavigationLink(value: Route.petCardPhotoPicker) {
            petCardCard
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "a11y.create.petCardEntry"))
    }

    private var petCardCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            PetCardExampleVisual(path: photos.first.map {
                $0.thumbnailPath.isEmpty ? $0.uri : $0.thumbnailPath
            } ?? "")
            .frame(width: 138, height: 142)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(10)

            HStack(spacing: 9) {
                Text("02")
                    .font(.editorialNumberIndex)
                    .foregroundStyle(Color.milensActionPrimary)
                Text(String(localized: "create.petCard.title"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
            }
            .padding(.leading, 10)

            Text(String(localized: "create.project.petCard.desc"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextSecondary)
                .padding(.leading, 10)
                .padding(.top, 2)
        }
        .frame(width: 158, height: 222)
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.milensSeparator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - 03 成长对比（珊瑚竖条白卡）

    private var growthCompareEntry: some View {
        NavigationLink(value: Route.growthComparePhotoPicker) {
            growthCompareCard
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "create.growthCompare.title"))
    }

    private var growthCompareCard: some View {
        HStack(alignment: .top, spacing: 0) {
            // 左侧珊瑚竖条
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 4, height: 102)

            VStack(alignment: .leading, spacing: 2) {
                Text("03")
                    .font(.editorialNumberIndex)
                    .foregroundStyle(Color.milensActionPrimary)
                Text(String(localized: "create.growthCompare.title"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                Text(String(localized: "create.project.growthCompare.desc"))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
            }
            .padding(.leading, 12)
            .padding(.top, 13)

            Spacer()
        }
        .frame(width: 166, height: 102)
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.milensSeparator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // MARK: - 04 名片（浅灰竖条白卡）

    private var businessCardEntry: some View {
        NavigationLink(value: Route.businessCardPicker) {
            businessCardCard
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "create.businessCard.title"))
    }

    private var businessCardCard: some View {
        HStack(alignment: .top, spacing: 0) {
            // 左侧浅灰竖条
            Rectangle()
                .fill(Color.milensSeparator)
                .frame(width: 4, height: 102)

            VStack(alignment: .leading, spacing: 2) {
                Text("04")
                    .font(.editorialNumberIndex)
                    .foregroundStyle(Color.milensActionPrimary)
                Text(String(localized: "create.businessCard.title"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                Text(String(localized: "create.project.businessCard.desc"))
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
            }
            .padding(.leading, 12)
            .padding(.top, 13)

            Spacer()
        }
        .frame(width: 166, height: 102)
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.milensSeparator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // MARK: - 05 红包封面（珊瑚横条）

    private var redPacketEntry: some View {
        NavigationLink(value: Route.redPacketCoverPicker) {
            redPacketCard
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "create.redPacket.title"))
    }

    private var redPacketCard: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("05")
                .font(.editorialNumberIndex)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "create.redPacket.title"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(.white)
                Text(String(localized: "create.project.redPacket.desc"))
                    .font(.editorialMetadata)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.leading, 20)

            Spacer()
            Text("↗")
                .font(.uiTitle)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .frame(width: 342, height: 78)
        .background(Color.milensActionPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(String(localized: "create.empty.title"))
                .font(.bodyPrimary.weight(.semibold))
                .foregroundStyle(Color.milensTextPrimary)
            Text(String(localized: "create.empty.body"))
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)

            NavigationLink(value: Route.gallery) {
                HStack(spacing: Spacing.sm) {
                    Text(String(localized: "create.empty.cta"))
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

    // MARK: - 数据加载

    @MainActor
    private func loadPhotos() async {
        defer { isLoading = false }
        do {
            photos = try factory.photoList(limit: 200)
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
            Color.milensSealSurface
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
            guard !path.isEmpty else { return }
            image = nil
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

// MARK: - 宠物卡片示意视觉

/// 使用第一张真实照片渲染「卡片效果」预览（照片 + 底部渐变 + 爪印），
/// 失败时保持中性表面（与 BeadExampleVisual 同一模式）。
private struct PetCardExampleVisual: View {
    let path: String
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.milensGrouped
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo.artframe")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.milensTextTertiary)
            }
            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0.0)],
                startPoint: .bottom, endPoint: .top
            )
            .frame(height: 56)
            .frame(maxHeight: .infinity, alignment: .bottom)

            Text("\u{1F43E}")
                .font(.system(size: 18))
                .padding(.leading, Spacing.md)
                .padding(.bottom, Spacing.sm)
        }
        .task(id: path) {
            guard !path.isEmpty else { return }
            image = nil
            image = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: path)
            }.value
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        CreateView()
    }
}
