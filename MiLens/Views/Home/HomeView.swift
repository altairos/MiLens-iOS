//  HomeView —— 编辑式首页。
//
//  参考视觉稿：整张记忆 Hero + 暗部大标题 + 竖排日期 + 一条编辑式回忆记录。
//  首页不再把问候、照片和动作拆成普通卡片堆叠。

import SwiftUI

struct HomeView: View {
    @Environment(\.viewModelFactory) private var factory
    @State private var viewModel: HomeViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView()
                    .tint(Color.milensActionPrimary)
            }
        }
        .background(Color.milensPaper)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard viewModel == nil else { return }
            let model = factory.makeHomeViewModel()
            model.load()
            viewModel = model
        }
    }

    @ViewBuilder
    private func content(_ model: HomeViewModel) -> some View {
        if model.isLoading {
            ProgressView()
                .tint(Color.milensActionPrimary)
        } else if let error = model.loadError {
            HomeRecoverableState(message: error) { model.load() }
        } else if model.photos.isEmpty {
            HomeEmptyState()
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    if let photo = model.heroPhoto {
                        NavigationLink(value: Route.photoView(photoID: photo.id)) {
                            MagazineHero(photo: photo, model: model)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("打开照片，\(model.heroCaption)")
                    }

                    if let memory = model.memoryItems.first {
                        NavigationLink(value: Route.photoView(photoID: memory.photo.id)) {
                            MemoryEditorialRow(item: memory)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.xxl)
                    }
                }
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct MagazineHero: View {
    let photo: Photo
    let model: HomeViewModel

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.12),
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.74)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 0) {
                    Text("MiLens")
                        .font(.displayLargeEN)
                        .foregroundStyle(.white)
                    Text("和它一起的每一天")
                        .font(.bodySecondary)
                        .foregroundStyle(.white.opacity(0.92))

                    Spacer()

                    Text("第 \(model.photos.count.formatted()) 张")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.bottom, Spacing.sm)

                    Text("今晚，留一会儿给\n它")
                        .font(.editorialHero)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(heroCaption)
                        .font(.bodySecondary.weight(.medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.top, Spacing.md)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.xxl)
                .padding(.bottom, Spacing.xxl)

                Text(heroDate)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .tracking(4)
                    .rotationEffect(.degrees(90))
                    .position(x: proxy.size.width - 30, y: proxy.size.height * 0.28)
            }
        }
        .frame(height: 600)
        .clipped()
    }

    private var heroCaption: String {
        if let pet = photo.pet?.name {
            return "\(pet) · \(photoTime)"
        }
        return "\(model.heroCaption) · \(photoTime)"
    }

    private var photoTime: String {
        guard let date = photo.takenAt else { return "今天" }
        return Self.timeFormatter.string(from: date)
    }

    private var heroDate: String {
        guard let date = photo.takenAt else { return "今天" }
        return Self.dateFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "今天 HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM · dd · yyyy"
        return formatter
    }()
}

private struct MemoryEditorialRow: View {
    let item: HomeViewModel.MemoryItem

    var body: some View {
        HStack(spacing: Spacing.lg) {
            Text(monthNumber)
                .font(.editorialNumber)
                .foregroundStyle(Color.milensCopper)
                .frame(width: 48, alignment: .leading)

            Rectangle()
                .fill(Color.milensBorder)
                .frame(width: 1, height: 76)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.entry.subtitle.isEmpty ? "最近回忆" : item.entry.subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
                Text(item.entry.title)
                    .font(.editorialSection)
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(2)
                Text("查看这段回忆")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
            }

            Spacer(minLength: Spacing.sm)

            ThumbnailImage(path: item.photo.thumbnailPath.isEmpty ? item.photo.uri : item.photo.thumbnailPath)
                .frame(width: 72, height: 96)
                .aspectRatio(contentMode: .fill)
                .clipped()

            Image(systemName: "chevron.right")
                .font(.system(size: Sizing.iconSm, weight: .semibold))
                .foregroundStyle(Color.milensCopper)
        }
        .padding(.vertical, Spacing.md)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.milensSeparator)
                .frame(height: 1)
        }
    }

    private var monthNumber: String {
        guard let date = item.photo.takenAt else { return "01" }
        return String(format: "%02d", Calendar.current.component(.month, from: date))
    }
}

private struct HomeEmptyState: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Text("MiLens")
                .font(.displayLargeEN)
                .foregroundStyle(Color.milensTextPrimary)
            Text("先留下一张照片")
                .font(.editorialSection)
                .foregroundStyle(Color.milensTextPrimary)
            Text("从相册里选几张和它有关的照片，\n我们会把每一天整理好。")
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)
            NavigationLink(value: Route.gallery) {
                Text("添加照片")
                    .font(.buttonLabel)
                    .foregroundStyle(Color.milensTextOnActionPrimary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.milensActionPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.pagePad)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HomeRecoverableState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Text("MiLens")
                .font(.displayLargeEN)
                .foregroundStyle(Color.milensTextPrimary)
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
