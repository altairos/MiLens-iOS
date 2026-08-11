//  CreateView —— 创作（Tab 3）。
//
//  创作页只呈现当前真正可用的项目；未实现能力不再以占位卡片占据页面。
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
        .background(Color.milensBackground)
        .navigationTitle(String(localized: "tab.create"))
        .navigationBarTitleDisplayMode(.large)
        .task { await loadPhotos() }
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
                    petCardEntry
                    growthCompareEntry
                    businessCardEntry
                    redPacketCoverEntry
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
            NavigationLink(value: Route.beadPhotoPicker) {
                    beadProjectRow
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel(String(localized: "a11y.create.beadEntry"))
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
                        if entitlement.isPro {
                            Text("不限次数")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.milensSuccess)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(Color.milensSuccess.opacity(0.12))
                                .clipShape(Capsule())
                        } else {
                            Text("每日 5 次")
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

    // MARK: - 宠物卡片入口（P4，按 ADR-0009 保持免费）

    private var petCardEntry: some View {
        NavigationLink(value: Route.petCardPhotoPicker) {
            petCardProjectRow
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "a11y.create.petCardEntry"))
    }

    // MARK: - 成长对比入口（ADR-0010 §3.3，Stage 2）

    private var growthCompareEntry: some View {
        NavigationLink(value: Route.growthComparePhotoPicker) {
            growthCompareProjectRow
        }
        .buttonStyle(.plain)
        .accessibilityLabel("成长对比")
    }

    private var growthCompareProjectRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.lg) {
                // 示例视觉：两张照片叠放示意（复用现有照片或占位）
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .fill(Color.milensGrouped)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Color.milensTextSecondary)
                }
                .frame(width: 104, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("成长对比")
                        .font(.titleStandard)
                        .foregroundStyle(Color.milensTextPrimary)

                    Text("选两张不同时期的照片，并排看到时间留下的变化。")
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

    private var petCardProjectRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.lg) {
                PetCardExampleVisual(path: photos.first.map {
                    $0.thumbnailPath.isEmpty ? $0.uri : $0.thumbnailPath
                } ?? "")
                .frame(width: 104, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("宠物卡片")
                        .font(.titleStandard)
                        .foregroundStyle(Color.milensTextPrimary)

                    Text("把一张照片做成竖版纪念卡，带上名字与领养纪念日。")
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

    // MARK: - 宠物名片入口（创作 Tab 新增项目，信息导向）

    private var businessCardEntry: some View {
        NavigationLink(value: Route.businessCardPicker) {
            businessCardProjectRow
        }
        .buttonStyle(.plain)
        .accessibilityLabel("宠物名片")
    }

    private var businessCardProjectRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .fill(Color.milensGrouped)
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Color.milensTextSecondary)
                }
                .frame(width: 104, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("宠物名片")
                        .font(.titleStandard)
                        .foregroundStyle(Color.milensTextPrimary)

                    Text("生成带有头像、性格标签和简介的社交名片卡。")
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

    // MARK: - 微信红包封面入口（创作 Tab 新增项目，节日/传播场景）

    private var redPacketCoverEntry: some View {
        NavigationLink(value: Route.redPacketCoverPicker) {
            redPacketCoverProjectRow
        }
        .buttonStyle(.plain)
        .accessibilityLabel("红包封面")
    }

    private var redPacketCoverProjectRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .fill(Color.milensGrouped)
                    VStack(spacing: 4) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(Color.milensCopper)
                        Text("红包")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.milensTextSecondary)
                    }
                }
                .frame(width: 104, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        Text("红包封面")
                            .font(.titleStandard)
                            .foregroundStyle(Color.milensTextPrimary)
                        Text("微信")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.milensTextSecondary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(Color.milensGrouped)
                            .clipShape(Capsule())
                    }

                    Text("生成微信红包封面素材（957×1278），预览红包 4 个场景。")
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
            // 分层收敛：轻量数据查询经工厂（View 不再直连 photoRepo）
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
            // 路径变化时清除旧图，避免照片编辑后 URI 改变仍显示旧缩略图。
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
            // 路径变化时清除旧图，避免照片编辑后 URI 改变仍显示旧缩略图。
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
