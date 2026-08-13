//  OnboardingCandidatesStep —— 首次启动 04 候选确认（对照 Figma #123:74）。
//  EditorialSection（"似乎有熟悉的伙伴" + 候选说明 + 短线）+
//  Candidate Tabs（全部 N/已选 M/待确认 K）+
//  Candidate Evidence Register 网格（3 列卡片：照片 + Selection Seal + 编号 + 已选/待确认 footer）。
//  ContactProofButton"确认将这 M 张照片写入「名字」的档案"。
//  候选数据来自 viewModel.candidateURIs；缩略图复用 CandidateThumbnail（系统库异步加载）。

import SwiftUI

struct OnboardingCandidatesStep: View {
    @Bindable var viewModel: OnboardingViewModel

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
        .onAppear {
            viewModel.prepareCandidates()
        }
    }

    // MARK: - Section Header（对照 #123:74 Title Stack）

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("似乎有熟悉的伙伴")
                .font(.editorialSection)
                .foregroundStyle(Color.milensTextPrimary)
            Text("这些只是与\(viewModel.petName)特征基准相近的候选；请逐张确认。")
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

    // MARK: - Candidate Tabs（对照 #123:74 Candidate Tabs）

    private var candidateTabs: some View {
        let total = viewModel.candidateURIs.count
        let selected = viewModel.selectedCandidateIDs.count
        let pending = total - selected
        return HStack(spacing: 24) {
            Text("全部 \(total)")
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextPrimary)
            Text("已选 \(selected)")
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensActionPrimary)
            Text("待确认 \(pending)")
                .font(.editorialMetadata)
                .foregroundStyle(Color.milensTextTertiary)
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
    }

    // MARK: - 候选网格（对照 #123:74 Candidate Evidence Register）

    private var candidateGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(viewModel.candidateURIs.enumerated()), id: \.element) { index, uri in
                candidateCard(uri: uri, index: index + 1)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
    }

    private func candidateCard(uri: String, index: Int) -> some View {
        let isSelected = viewModel.selectedCandidateIDs.contains(uri)
        return Button {
            viewModel.toggleCandidate(uri)
        } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    CandidateThumbnail(identifier: uri)
                        .frame(height: 122)
                        .clipped()

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

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(String(format: "%02d", index))
                            .font(.custom("Fraunces-Bold", size: 12))
                            .foregroundStyle(Color.milensActionPrimary)
                        Text(isSelected ? "已选" : "待确认")
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

    // MARK: - 底部 Action（对照 #123:74 Contact Proof）

    private var bottomActionBar: some View {
        let selected = viewModel.selectedCandidateIDs.count
        return ContactProofButton(
            label: "确认将这 \(selected) 张照片写入\(viewModel.petName)的档案",
            isEnabled: !viewModel.selectedCandidateIDs.isEmpty
        ) {
            viewModel.importConfirmedCandidates()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
        .background(Color.milensBackground)
    }
}
