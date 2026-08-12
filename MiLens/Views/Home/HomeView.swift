//  HomeView —— 编辑式首页（对照 Figma「01·首页」#319:1026）。
//
//  出血 Hero 大图 + 暗部文楷大标题 + 宠物身份条 + 即将到来的日子区块。
//  HomeViewModel（@Observable）驱动：选片、问候、回忆和纪念日倒计时。

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
        .background(Color.milensBackground)
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
                    // Hero 区
                    if let photo = model.heroPhoto {
                        NavigationLink(value: Route.photoView(photoID: photo.id)) {
                            HomeHero(photo: photo, model: model)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "a11y.home.openPhoto \(model.heroCaption)"))
                    }

                    // 即将到来的日子
                    if let upcoming = model.upcomingDay {
                        UpcomingDaySection(upcoming: upcoming)
                            .padding(.horizontal, Spacing.pagePad)
                            .padding(.top, Spacing.lg)
                    }

                    // 历史回忆（保留原有编辑式回忆行）
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

// MARK: - Hero 大图区

/// 出血 Hero：大图 + 渐变 + 品牌名 + 日期 + 通知按钮 + 宠物身份条。
/// 对照 Figma #319:1027-1051。
private struct HomeHero: View {
    let photo: Photo
    let model: HomeViewModel

    var body: some View {
        ZStack(alignment: .top) {
            // 大图
            ThumbnailImage(path: photo.thumbnailPath.isEmpty ? photo.uri : photo.thumbnailPath)
                .frame(maxWidth: .infinity)
                .frame(height: 589)
                .clipped()

            // 底部渐变（对照 Hero Gradient #319:1028）
            LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    Color(red: 0.04, green: 0.03, blue: 0.03).opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 311)
            .frame(maxHeight: .infinity, alignment: .bottom)

            // 内容层
            VStack(alignment: .leading, spacing: 0) {
                // 顶部行：品牌名 + 日期 + 通知按钮
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MiLens")
                            .font(.custom("Fraunces-Semibold", size: 24))
                            .foregroundStyle(.white)
                        Text(heroDateString)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    Spacer()
                    // 通知按钮（装饰性，Tab 切换需用户手动点底部 Tab）
                    Image(systemName: "bell")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }

                Spacer()

                // 底部标题区
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // 宠物身份条（对照 Pet Identity #319:1037-1047）
                    if let pet = photo.pet {
                        NavigationLink(value: Route.petProfile(petID: pet.id)) {
                            petIdentityBar(pet)
                        }
                        .buttonStyle(.plain)
                    }

                    // 小标签
                    Text(String(localized: "home.hero.todayLabel"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)

                    // 文楷大标题（对照 #319:1036，37pt 文楷）
                    Text(String(localized: "home.hero.title"))
                        .font(.custom("LXGWWenKai-Regular", size: 37, relativeTo: .largeTitle))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 23)
            .padding(.top, 53)
            .padding(.bottom, 28)
        }
        .frame(height: 589)
        .clipped()
    }

    /// 宠物身份条：珊瑚竖线 + 名字年龄 + 切角箭头按钮。
    private func petIdentityBar(_ pet: Pet) -> some View {
        HStack(spacing: 8) {
            // 珊瑚竖线 3pt（对照 Pet Identity Index #319:1046）
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3, height: 32)

            // 名字 · 年龄
            Text(petIdentityText(pet))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            // 切角按钮（对照 Hero Cut Corner Key #319:1048-1051）
            ZStack {
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 36, height: 36)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func petIdentityText(_ pet: Pet) -> String {
        if let birthday = pet.birthday {
            let cal = Calendar.current
            let now = Date()
            let comps = cal.dateComponents([.year, .month], from: birthday, to: now)
            let years = comps.year ?? 0
            let months = comps.month ?? 0
            return "\(pet.name) · \(years)岁\(months)个月"
        }
        return pet.name
    }

    /// 日期格式：「8月10日 · 星期一」（对照 #319:1030）。
    private var heroDateString: String {
        let now = Date()
        let cal = Calendar.current
        let month = cal.component(.month, from: now)
        let day = cal.component(.day, from: now)
        let weekdayIdx = cal.component(.weekday, from: now) - 1
        let weekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        return "\(month)月\(day)日 · \(weekdays[weekdayIdx])"
    }
}

// MARK: - 即将到来的日子

/// 即将到来的纪念日区块：珊瑚竖线 + 标题 + 倒计时 + 缩略图。
/// 对照 Figma #319:1039-1053。
private struct UpcomingDaySection: View {
    let upcoming: HomeViewModel.UpcomingDay

    var body: some View {
        NavigationLink(value: Route.petProfile(petID: upcoming.petID)) {
            HStack(spacing: 0) {
                // 左侧珊瑚竖线 4pt（对照 Section Accent #319:1039）
                Rectangle()
                    .fill(Color.milensPrimary)
                    .frame(width: 4)
                    .cornerRadius(2)

                // 文案区
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(String(localized: "home.upcoming.sectionLabel"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.milensTextSecondary)

                    Text(upcoming.title)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.milensTextPrimary)

                    Text(String(localized: "home.upcoming.days \(upcoming.daysUntil) \(upcoming.daysTogether)"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.milensTextSecondary)

                    Text(String(localized: "home.upcoming.lookBack"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.milensActionPrimary)
                }
                .padding(.leading, 21)
                .padding(.vertical, 4)

                Spacer(minLength: Spacing.md)

                // 右侧缩略图 + 底部珊瑚 divider
                VStack(spacing: 0) {
                    if let thumbPath = upcoming.thumbnailPath {
                        ThumbnailImage(path: thumbPath)
                            .frame(width: 96, height: 126)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.milensGrouped)
                            .frame(width: 96, height: 126)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(Color.milensTextTertiary)
                            )
                    }
                    // 底部珊瑚 divider（对照 Upcoming Caption Divider #319:1053）
                    Rectangle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 96, height: 4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 历史回忆行（保留原有编辑式行）

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
                Text(item.entry.subtitle.isEmpty ? String(localized: "home.memoryTitle") : item.entry.subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
                Text(item.entry.title)
                    .font(.editorialSection)
                    .foregroundStyle(Color.milensTextPrimary)
                    .lineLimit(2)
                Text(String(localized: "home.memoryOpen"))
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

// MARK: - 空态 / 错误态

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
            Button(String(localized: "home.retry"), action: retry)
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
