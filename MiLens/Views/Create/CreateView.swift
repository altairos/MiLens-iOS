//  CreateView —— 创作（Tab 3）。
//
//  Ledger 编辑式暗色设计（对照 Figma「05·创作」#58:15）：
//  暗色背景 + 文楷标题 + 大尺寸 Hero 卡片（照片铺底 + 珊瑚打开按钮）。
//  5 个创作项目全保留，按暗/浅交替排列。
//  页面语言是「照片 → 作品」的档案式入口，而不是功能宫格。

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
        .background(Color.milensStudioBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadPhotos() }
    }

    // MARK: - 主内容

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, Spacing.pagePad)
                    .padding(.top, 59)
                    .padding(.bottom, Spacing.xl)

                if photos.isEmpty {
                    emptyState
                        .padding(.horizontal, Spacing.pagePad)
                } else {
                    cardStack
                        .padding(.horizontal, Spacing.pagePad)
                }
            }
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 头部（对照 Figma #61:56-59）

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("MiLens")
                    .font(.custom("Fraunces-Semibold", size: 24))
                    .foregroundStyle(Color.milensPaper)
                Spacer()
                Text(String(localized: "tab.create"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.milensTextSecondary.opacity(0.7))
            }

            Text(String(localized: "create.header.title"))
                .font(.custom("LXGWWenKai-Regular", size: 34, relativeTo: .largeTitle))
                .foregroundStyle(Color.milensPaper)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Spacing.lg)

            Text(String(localized: "create.header.subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(Color.milensTextSecondary.opacity(0.7))
                .padding(.top, Spacing.md)
        }
    }

    // MARK: - 卡片堆栈

    private var cardStack: some View {
        VStack(spacing: 18) {
            beadEntry
            petCardEntry
            growthCompareEntry
            businessCardEntry
            redPacketCoverEntry
        }
    }

    // MARK: - 拼豆入口（262pt 暗色大卡，对照 Figma #61:60）

    private var beadEntry: some View {
        NavigationLink(value: Route.beadPhotoPicker) {
            beadCard
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "a11y.create.beadEntry"))
    }

    private var beadCard: some View {
        ZStack(alignment: .bottomLeading) {
            // 照片铺底 + 像素化
            BeadExampleVisual(path: photos.first.map {
                $0.thumbnailPath.isEmpty ? $0.uri : $0.thumbnailPath
            } ?? "")
            .clipped()

            // 底部渐变（对照 Bead Overlay #61:62）
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 146)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .accessibilityHidden(true)

            // Feature Badge（对照 #61:63）
            HStack {
                Text(String(localized: "create.bead.title"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 7)
                    .background(Color.milensPrimary)
                    .clipShape(Capsule())
                Spacer()
            }
            .padding(.leading, 20)
            .padding(.top, 18)
            .frame(maxHeight: .infinity, alignment: .top)

            // 底部文案 + 打开按钮
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "create.bead.desc"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text(String(localized: "create.subheadline"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.83, green: 0.80, blue: 0.77)) // #D4CBC4 ui-token:ok
                }
                Spacer()
                // 打开按钮（42pt 珊瑚圆）
                openButton(size: 42, iconSize: 16)
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .padding(.bottom, 20)
        }
        .frame(height: 262)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    // MARK: - 宠物卡片入口（194pt 浅底 + 右侧竖版照片，对照 Figma #61:70）

    private var petCardEntry: some View {
        NavigationLink(value: Route.petCardPhotoPicker) {
            petCardCard
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "a11y.create.petCardEntry"))
    }

    private var petCardCard: some View {
        HStack(spacing: 0) {
            // 左侧文案区
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("PET CARD")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.milensActionPrimary)
                    Text(String(localized: "create.petCard.title"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.milensInk)
                    Text(String(localized: "create.petCard.desc"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.milensTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    // 打开按钮（40pt 珊瑚圆）
                    openButton(size: 40, iconSize: 16)
                }
                Spacer()
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.top, 20)
            .padding(.bottom, 20)

            // 右侧竖版照片
            PetCardExampleVisual(path: photos.first.map {
                $0.thumbnailPath.isEmpty ? $0.uri : $0.thumbnailPath
            } ?? "")
            .frame(width: 156)
            .frame(maxHeight: .infinity)
            .clipped()
        }
        .frame(height: 194)
        .background(Color.milensPaper)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    // MARK: - 成长对比入口（194pt 暗色卡）

    private var growthCompareEntry: some View {
        NavigationLink(value: Route.growthComparePhotoPicker) {
            darkCard(
                title: String(localized: "create.growthCompare.title"),
                desc: String(localized: "create.growthCompare.desc"),
                icon: "arrow.left.arrow.right"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "create.growthCompare.title"))
    }

    // MARK: - 宠物名片入口（194pt 浅色卡）

    private var businessCardEntry: some View {
        NavigationLink(value: Route.businessCardPicker) {
            lightCard(
                title: String(localized: "create.businessCard.title"),
                desc: String(localized: "create.businessCard.desc"),
                icon: "person.crop.circle"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "create.businessCard.title"))
    }

    // MARK: - 微信红包封面入口（194pt 暗色卡）

    private var redPacketCoverEntry: some View {
        NavigationLink(value: Route.redPacketCoverPicker) {
            darkCard(
                title: String(localized: "create.redPacket.title"),
                desc: String(localized: "create.redPacket.desc"),
                icon: "gift.fill"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "create.redPacket.title"))
    }

    // MARK: - 可复用卡片组件

    /// 暗色卡片：#211C1A 底色，标题 + 描述 + 右下打开按钮。
    private func darkCard(title: String, desc: String, icon: String) -> some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Color.milensTextSecondary.opacity(0.5))
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.83, green: 0.80, blue: 0.77)) // #D4CBC4 ui-token:ok
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.leading, 20)
            .padding(.top, 20)
            .padding(.bottom, 20)
            .padding(.trailing, 70)

            openButton(size: 42, iconSize: 16)
                .padding(.trailing, 16)
                .padding(.bottom, 20)
        }
        .frame(height: 194)
        .background(Color.milensStudioSurface)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    /// 浅色卡片：#F2EFEA 底色，标题 + 描述 + 左下打开按钮。
    private func lightCard(title: String, desc: String, icon: String) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.milensTextSecondary)
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.milensInk)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.milensTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                openButton(size: 40, iconSize: 16)
            }
            Spacer()
        }
        .padding(.leading, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .padding(.trailing, 20)
        .frame(height: 194)
        .background(Color.milensPaper)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    /// 珊瑚色圆形打开按钮。
    private func openButton(size: CGFloat, iconSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.milensActionPrimary)
                .frame(width: size, height: size)
            Image(systemName: "arrow.right")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(String(localized: "create.empty.title"))
                .font(.bodyPrimary.weight(.semibold))
                .foregroundStyle(Color.milensPaper)
            Text(String(localized: "create.empty.body"))
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary.opacity(0.7))

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
            Color.milensStudioSurface
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
