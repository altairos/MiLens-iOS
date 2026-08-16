//  AlbumCandidateListView —— 候选照片列表页（对照 Figma 02·候选列表 #27:4 / 06·50/50 #34:14）。
//  Section Header（文楷 + Caption + 珊瑚短线）+ Candidate Tabs + 候选网格（3 列卡片）+
//  额度提示条（50/50 场景）+ 底部 Contact Proof Action。
//  候选数据来自 vm.candidateURIs（unassigned + matched），每项可切换选中态。

import SwiftUI

struct AlbumCandidateListView: View {
    @Bindable var vm: GalleryViewModel
    @Binding var selectedIdentifiers: Set<String>
    let onContinue: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader
                    candidateTabs
                    candidateGrid
                }
                .padding(.bottom, 80)
            }

            bottomActionBar
        }
    }

    // MARK: - Section Header（对照 #30:10-12）

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "album.candidates.title"))
                .font(.custom("LXGWWenKai-Regular", size: 28, relativeTo: .title2))
                .foregroundStyle(Color.milensTextPrimary)
            Text(String(localized: "album.candidates.subtitle"))
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 174, height: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.xl)
    }

    // MARK: - Candidate Tabs（对照 #30:13-16）

    private var candidateTabs: some View {
        let total = vm.candidateURIs.count
        let selected = selectedIdentifiers.count
        let pending = total - selected
        return HStack(spacing: 24) {
            Text(String(localized: "album.candidates.tabAll \(total)"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextPrimary)
            Text(String(localized: "album.candidates.tabSelected \(selected)"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensActionPrimary)
            Text(String(localized: "album.candidates.tabPending \(pending)"))
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextTertiary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
    }

    // MARK: - 候选网格（对照 #30:17 Candidate Evidence Register）

    private var candidateGrid: some View {
        VStack(spacing: 0) {
            // 额度提示条（仅 50/50 场景，对照 #34:105）
            if vm.totalPhotoCount >= CommercialRules.freePhotoLimit {
                quotaHintBar
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(vm.candidateURIs.enumerated()), id: \.element) { index, uri in
                    candidateCard(uri: uri, index: index + 1)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
        }
    }

    // MARK: - 候选卡片（对照 #30:18 Candidate / 01）

    private func candidateCard(uri: String, index: Int) -> some View {
        let isSelected = selectedIdentifiers.contains(uri)
        return Button {
            if selectedIdentifiers.contains(uri) {
                selectedIdentifiers.remove(uri)
            } else {
                selectedIdentifiers.insert(uri)
            }
        } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    // 照片缩略图
                    CandidateThumbnail(identifier: uri)
                        .frame(height: 122)
                        .clipped()

                    // Selection Seal（对照 #30:24）
                    if isSelected {
                        ZStack {
                            Circle()
                                .fill(Color.milensActionPrimary)
                                .frame(width: 20, height: 20)
                            Text("\u{2713}")
                                .font(.editorialMetadata)
                                .foregroundStyle(.white)
                        }
                        .padding(8)
                    }
                }

                // Footer 白底（对照 #30:20）
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(String(format: "%02d", index))
                            .font(.custom("Fraunces-Bold", size: 12))
                            .foregroundStyle(Color.milensActionPrimary)
                        Text(isSelected ? String(localized: "album.candidates.cardSelected") : String(localized: "album.candidates.cardPending"))
                            .font(.editorialMetadata)
                            .foregroundStyle(isSelected ? Color.milensActionPrimary : Color.milensTextSecondary)
                    }
                    .padding(.leading, 8)
                    Spacer()
                }
                .frame(height: 36)
                .background(Color.milensCard)
            }
            .background(Color.milensCard)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.milensBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 额度提示条（对照 #34:105-109）

    private var quotaHintBar: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "gallery.import.freeArchiveMark"))
                    .font(.custom("JacquesFrancois-Regular", size: 10))
                    .tracking(0.4)
                    .foregroundStyle(Color.milensActionPrimary)
                Text("50 / 50")
                    .font(.uiTitle)
                    .foregroundStyle(Color.milensTextPrimary)
            }
            Spacer()
            Text(String(localized: "album.candidates.quotaHint"))
                .font(.buttonLabel)
                .foregroundStyle(Color.milensActionPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(14)
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 底部 Action（对照 #30:87 Contact Proof）

    private var bottomActionBar: some View {
        Button(action: onContinue) {
            HStack {
                Text(String(localized: "album.candidates.continue \(selectedIdentifiers.count)"))
                    .font(.buttonLabel)
                    .foregroundStyle(Color.milensActionPrimary)
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.milensActionPrimary, lineWidth: 1)
                        .frame(width: 42, height: 32)
                    Text("\u{2192}")
                        .font(.system(size: 20)) // ui-token:ok 装饰箭头字符
                        .foregroundStyle(Color.milensActionPrimary)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 5)
            .frame(height: 54)
            .background(Color.milensAccentWash)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(selectedIdentifiers.isEmpty)
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
        .background(Color.milensBackground)
    }
}

// MARK: - 候选缩略图（系统库异步加载）

/// 通过 PhotoLibraryAccess.loadImageData 加载缩略图。
/// 候选照片尚未导入沙盒，直接从系统相册加载低分辨率数据。
struct CandidateThumbnail: View {
    let identifier: String
    @Environment(\.viewModelFactory) private var factory
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.milensGrouped)
                    .overlay(ProgressView().scaleEffect(0.5))
            }
        }
        .task(id: identifier) {
            guard image == nil else { return }
            // 候选缩略图通过 GalleryViewModel 的 photoLibrary 间接加载；
            // 此处用轻量方式加载小尺寸数据（256px 缩略图）。
            let loaded = await factory.loadCandidateThumbnail(identifier: identifier)
            await MainActor.run { self.image = loaded }
        }
    }
}
