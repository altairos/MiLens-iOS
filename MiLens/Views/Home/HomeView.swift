//  HomeView —— 编辑式首页（对照 Figma「01·首页」#319:1026）。
//
//  出血 Hero 大图 + 暗部文楷大标题 + 宠物身份条 + 即将到来的日子区块。
//  HomeViewModel（@Observable）驱动：选片、问候、回忆和纪念日倒计时。

import SwiftUI
import MiLensKit

struct HomeView: View {
    @Environment(\.viewModelFactory) private var factory
    @State private var viewModel: HomeViewModel?
    /// 跨 Tab 请求进入设置页备份导出（与 RootTabView/SettingsView 共享）
    @AppStorage("backupExportRequested") private var backupExportRequested = false
    /// 跨 Tab 请求进入相册扫描流程（铃铛确认窗/选择菜单/推送 tap 共用）
    @AppStorage("newPhotoScanRequested") private var newPhotoScanRequested = false
    /// 铃铛晃动模式（设置页配置，四选一）
    @AppStorage("bellShakeMode") private var bellShakeModeRaw = BellShakeLogic.ShakeMode.all.rawValue

    /// 铃铛确认窗/选择菜单/回忆中心 push 状态
    @State private var showNewPhotoConfirm = false
    @State private var showBellChoiceMenu = false
    @State private var pushReminders = false

    private var bellShakeMode: BellShakeLogic.ShakeMode {
        BellShakeLogic.ShakeMode(rawValue: bellShakeModeRaw) ?? .all
    }

    /// 铃铛触发原因（经开关过滤后的最终状态）
    private var bellTriggerReason: BellShakeLogic.TriggerReason {
        guard let viewModel else { return .none }
        return BellShakeLogic.resolveReason(
            hasAnniversary: viewModel.hasTodayContent,
            hasNewPhoto: viewModel.hasNewPhotoReminder,
            mode: bellShakeMode)
    }

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
        .navigationDestination(isPresented: $pushReminders) {
            MemoryRemindersView()
        }
        // 新照片确认窗（仅 .newPhoto 触发）
        .alert(
            confirmAlertTitle,
            isPresented: $showNewPhotoConfirm
        ) {
            Button(String(localized: "bell.confirm.confirm")) {
                newPhotoScanRequested = true
            }
            Button(String(localized: "bell.confirm.cancel"), role: .cancel) {}
        } message: {
            Text(confirmAlertMessage)
        }
        // 选择菜单（仅 .both 触发）
        .confirmationDialog(
            String(localized: "bell.menu.title"),
            isPresented: $showBellChoiceMenu,
            titleVisibility: .visible
        ) {
            Button(String(localized: "bell.menu.memories")) {
                pushReminders = true
            }
            Button(String(localized: "bell.menu.newPhoto")) {
                newPhotoScanRequested = true
            }
            Button(String(localized: "bell.confirm.cancel"), role: .cancel) {}
        }
        .onAppear {
            guard viewModel == nil else { return }
            let model = factory.makeHomeViewModel()
            model.load()
            viewModel = model
        }
        .task {
            // load 后异步刷新新照片提醒（不阻塞首页主加载）
            await viewModel?.refreshNewPhotoReminder()
        }
    }

    // MARK: - 确认窗文案（按 ReminderKind 区分）

    private var confirmAlertTitle: String {
        guard let viewModel else { return "" }
        switch viewModel.newPhotoReminderKind {
        case .staleInput:
            return String(localized: "bell.confirm.title.stale")
        default:
            return String(localized: "bell.confirm.title.new")
        }
    }

    private var confirmAlertMessage: String {
        guard let viewModel else { return "" }
        switch viewModel.newPhotoReminderKind {
        case .staleInput:
            return String(localized: "bell.confirm.body.stale")
        default:
            return String(localized: "bell.confirm.body.new")
        }
    }

    // MARK: - 铃铛点击分流

    /// 按触发原因执行不同的点击行为。
    /// .none/.anniversary → 进回忆提醒中心；.newPhoto → 弹确认窗；.both → 弹选择菜单。
    private func handleBellTap() {
        switch bellTriggerReason {
        case .none, .anniversary:
            pushReminders = true
        case .newPhoto:
            showNewPhotoConfirm = true
        case .both:
            showBellChoiceMenu = true
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
                            HomeHero(
                                photo: photo,
                                model: model,
                                bellTriggerReason: bellTriggerReason,
                                onBellTap: { handleBellTap() }
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "a11y.home.openPhoto \(model.heroCaption)"))
                    }

                    // 备份提醒横幅（数据量达标且久未备份时展示）
                    if model.shouldShowBackupBanner {
                        BackupReminderBanner(photoCount: model.photoTotalCount) {
                            backupExportRequested = true
                        } onClose: {
                            model.dismissBackupBanner()
                        }
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.lg)
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

                    // 年度回看入口（情感触点系统 Stage 3）
                    if !model.photos.isEmpty {
                        NavigationLink(value: Route.recap(year: nil)) {
                            YearlyRecapEntry()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Spacing.pagePad)
                        .padding(.top, Spacing.lg)
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
    /// 铃铛触发原因（经开关过滤后的最终状态，决定晃动与否）。
    let bellTriggerReason: BellShakeLogic.TriggerReason
    /// 铃铛点击回调（由 HomeView 按 reason 分流处理）。
    let onBellTap: () -> Void

    /// 铃铛提醒动效状态：有提醒命中时触发一次系统 wiggle（symbolEffect 自动守 Reduce Motion）。
    @State private var bellAnimating = false

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
                    Color.milensHeroGradientEnd.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 311)
            .frame(maxHeight: .infinity, alignment: .bottom)

            // 内容层
            VStack(alignment: .leading, spacing: 0) {
                // 顶部行：品牌名 + 日期 + 通知按钮（对照 #319:1029-1032，x=32）
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MiLens")
                            .font(.custom("Fraunces-Semibold", size: 24))
                            .foregroundStyle(.white)
                        Text(heroDateString)
                            .font(.bodySecondary)
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    Spacer()
                    // 铃铛：有提醒时轻微 wiggle 一次，点击按触发原因分流（回忆中心/确认窗/选择菜单）
                    Button {
                        Haptics.light()
                        bellAnimating = false
                        onBellTap()
                    } label: {
                        Image(systemName: "bell")
                            .font(.system(size: Sizing.iconMd))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .symbolEffect(.wiggle, value: bellAnimating)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "a11y.home.bell"))
                }
                .padding(.leading, 32)
                .padding(.trailing, 23)

                Spacer()

                // 底部标题区（对照 #319:1035-1037，x=23）
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // 小标签
                    Text(String(localized: "home.hero.todayLabel"))
                        .font(.bodySecondary)
                        .foregroundStyle(.white)

                    // 文楷大标题（对照 #319:1036，37pt 文楷）
                    Text(String(localized: "home.hero.title"))
                        .font(.custom("LXGWWenKai-Regular", size: 37, relativeTo: .largeTitle))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    // 宠物身份条（对照 Pet Identity #319:1037-1047，Hero 最底部）
                    if let pet = photo.pet {
                        NavigationLink(value: Route.petProfile(petID: pet.id)) {
                            petIdentityBar(pet)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 23)
            }
            .padding(.top, 53)
            .padding(.bottom, 28)
        }
        .frame(height: 589)
        .clipped()
        .onAppear {
            bellAnimating = BellShakeLogic.shouldAnimate(bellTriggerReason)
        }
        .onChange(of: bellTriggerReason) { _, reason in
            bellAnimating = BellShakeLogic.shouldAnimate(reason)
        }
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
                .font(.bodySecondary)
                .foregroundStyle(.white)

            Spacer()

            // 切角按钮（对照 Hero Cut Corner Key #319:1048-1051）
            ZStack {
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: 36, height: 36)
                Image(systemName: "arrow.right")
                    .font(.system(size: Sizing.iconSm, weight: .semibold))
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
                    .cornerRadius(Radius.accentRail)

                // 文案区
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(String(localized: "home.upcoming.sectionLabel"))
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)

                    Text(upcoming.title)
                        .font(.uiTitle)
                        .foregroundStyle(Color.milensTextPrimary)

                    Text(daysTogetherText(upcoming))
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensTextSecondary)

                    Text(String(localized: "home.upcoming.lookBack"))
                        .font(.bodySecondary)
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

    /// 根据 kind 显示语义精确的天数文案。
    /// - birthday: 「还有 N 天 · 出生至今 M 天」
    /// - adoption: 「还有 N 天 · 已陪伴 M 天」
    /// - memorial: 「还有 N 天 · 已记录 M 天」
    private func daysTogetherText(_ upcoming: HomeViewModel.UpcomingDay) -> String {
        let daysUntil = upcoming.daysUntil
        let days = upcoming.daysTogether
        switch upcoming.kind {
        case .birthday:
            return String(localized: "home.upcoming.days.birthday \(daysUntil) \(days)")
        case .adoption:
            if days <= 180 {
                return String(localized: "home.upcoming.days.adoption.arrived \(daysUntil) \(days)")
            }
            if days <= 365 {
                return String(localized: "home.upcoming.days.adoption.together \(daysUntil) \(days)")
            }
            return String(localized: "home.upcoming.days.adoption.family \(upcoming.petName) \(daysUntil) \(days)")
        case .memorial:
            return String(localized: "home.upcoming.days.memorial \(daysUntil) \(days)")
        }
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

// MARK: - 年度回看入口卡片

/// 年度回忆册入口卡片：珊瑚竖线 + 文楷标题 + 副文 + 箭头。
private struct YearlyRecapEntry: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "home.yearlyRecap.title"))
                    .font(.custom("LXGWWenKai-Regular", size: 17, relativeTo: .headline))
                    .foregroundStyle(Color.milensTextPrimary)
                Text(String(localized: "home.yearlyRecap.body"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: Sizing.iconSm))
                .foregroundStyle(Color.milensTextSecondary)
        }
        .padding(16)
        .background(Color.milensCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }
}

// MARK: - 备份提醒横幅

/// 首页备份提醒横幅：数据量达标且久未备份时温柔引导用户导出备份。
/// 强调记忆的珍贵与完整保存，不使用「换机丢失」类表述。
/// 点击「去导出备份」触发跨 Tab 跳转（backupExportRequested）；× 关闭本次会话不再展示。
private struct BackupReminderBanner: View {
    let photoCount: Int
    let onTap: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.timemachine")
                        .font(.system(size: Sizing.iconSm))
                        .foregroundStyle(Color.milensActionPrimary)
                    Text(String(localized: "home.backup.banner.title"))
                        .font(.bodyPrimary)
                        .foregroundStyle(Color.milensTextPrimary)
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium)) // ui-token:ok SF Symbol 光学图标尺寸
                            .foregroundStyle(Color.milensTextTertiary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 14)

                Text(String(localized: "home.backup.banner.body \(photoCount)"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                Button {
                    onTap()
                } label: {
                    Text(String(localized: "home.backup.banner.action"))
                        .font(.bodySecondary)
                        .foregroundStyle(Color.milensActionPrimary)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
            .padding(.leading, 13)
            .padding(.trailing, 10)
        }
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
