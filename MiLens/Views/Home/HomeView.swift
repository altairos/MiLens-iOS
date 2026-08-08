//  HomeView —— Quiet Archive 首页。
//  页面只保留一条主叙事：问候 → 一张照片 → 一段回忆 → 一个明确动作。

import SwiftUI

struct HomeView: View {
    @Environment(\.photoRepository) private var photoRepository
    @Environment(\.petRepository) private var petRepository
    @AppStorage("selectedTab") private var selectedTabRaw: Int = AppTab.home.rawValue
    @State private var viewModel: HomeViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView()
                    .tint(.milensPrimary)
            }
        }
        .background(Color.milensBackground)
        .onAppear {
            guard viewModel == nil else { return }
            let model = HomeViewModel(
                photoRepository: photoRepository,
                petRepository: petRepository
            )
            model.load()
            viewModel = model
        }
    }

    @ViewBuilder
    private func content(_ model: HomeViewModel) -> some View {
        if model.isLoading {
            ProgressView()
                .tint(.milensPrimary)
        } else if let error = model.loadError {
            HomeRecoverableState(message: error) {
                model.load()
            }
        } else if model.photos.isEmpty {
            HomeEmptyState()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    greetingHeader(model)
                    heroSection(model)
                    memorySection(model)
                    createAction
                }
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func greetingHeader(_ model: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(model.greeting)
                .font(.displayLarge)
                .foregroundStyle(Color.milensTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("和它一起的每一天")
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.xl)
    }

    private func heroSection(_ model: HomeViewModel) -> some View {
        let photo = model.heroPhoto
        return VStack(alignment: .leading, spacing: Spacing.md) {
            if let photo {
                NavigationLink(value: Route.photoView(photoID: photo.id)) {
                    HomeHeroImage(photo: photo)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开照片，\(model.heroCaption)")

                Text(model.heroCaption)
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.horizontal, Spacing.pagePad)
            }
        }
    }

    private func memorySection(_ model: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("留住的日子")
                    .font(.titleStandard)
                    .foregroundStyle(Color.milensTextPrimary)
                Spacer()
                Text(model.memoryItems.isEmpty ? "还没有更早的照片" : "向左看看")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextTertiary)
            }

            if model.memoryItems.isEmpty {
                Text("再多保存一些日子，这里会替你留下回看的入口。")
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.vertical, Spacing.md)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: Spacing.md) {
                        ForEach(model.memoryItems) { item in
                            NavigationLink(value: Route.photoView(photoID: item.photo.id)) {
                                MemoryCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, Spacing.xxl)
    }

    private var createAction: some View {
        Button {
            selectedTabRaw = AppTab.create.rawValue
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: Sizing.iconMd, weight: .semibold))
                Text("为它创作")
                    .font(.buttonLabel)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: Sizing.iconSm, weight: .semibold))
            }
            .foregroundStyle(Color.milensTextOnActionPrimary)
            .frame(minHeight: Sizing.touchTarget)
            .padding(.horizontal, Spacing.lg)
            .background(Color.milensActionPrimary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.pagePad)
        .padding(.top, Spacing.xxl)
        .accessibilityLabel("为它创作，打开相册")
    }
}

private struct HomeHeroImage: View {
    let photo: Photo

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 5, contentMode: .fit)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.18)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
        }
        .background(Color.milensGrouped)
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
    }
}

private struct MemoryCard: View {
    let item: HomeViewModel.MemoryItem

    var body: some View {
        HStack(spacing: Spacing.md) {
            ThumbnailImage(path: item.photo.thumbnailPath.isEmpty ? item.photo.uri : item.photo.thumbnailPath)
                .frame(width: 88, height: 88)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.entry.title)
                    .font(.titleStandard)
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(2)
                Text(item.entry.subtitle.isEmpty ? "查看这段回忆" : item.entry.subtitle)
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .lineLimit(2)
            }
            .frame(width: 132, alignment: .leading)
        }
        .padding(Spacing.sm)
        .background(Color.milensCard)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .frame(width: 252, height: 104)
    }
}

private struct HomeEmptyState: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.milensPrimary)
            Text("先留下一张照片")
                .font(.displayMedium)
                .foregroundStyle(Color.milensTextPrimary)
            Text("从相册里选几张和它有关的照片，\n我们会把每一天整理好。")
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)
            NavigationLink(value: Route.gallery) {
                Text("添加照片")
                    .font(.buttonLabel)
                    .foregroundStyle(Color.milensTextOnActionPrimary)
                    .frame(minWidth: 128, minHeight: Sizing.touchTarget)
                    .padding(.horizontal, Spacing.lg)
                    .background(Color.milensActionPrimary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.pagePad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HomeRecoverableState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.milensTextSecondary)
            Text(message)
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)
            Button("再试一次", action: retry)
                .font(.buttonLabel)
                .buttonStyle(.borderedProminent)
                .tint(Color.milensActionPrimary)
        }
        .padding(.horizontal, Spacing.pagePad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
