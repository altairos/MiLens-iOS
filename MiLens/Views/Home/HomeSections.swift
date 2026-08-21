//  HomeSections —— 首页分区视图集合，从 HomeView.swift 拆出（ADR-0011 §5 规模守卫拆分批次）。
//  含：出血 Hero 大图区、即将到来的日子、历史回忆行、空态/错误态、
//  年度回看入口卡片、备份提醒横幅。状态与回调经构造参数注入，不含页面级逻辑。

import SwiftUI
import MiLensKit

// MARK: - Hero 大图区

/// 出血 Hero：大图 + 渐变 + 品牌名 + 日期 + 通知按钮 + 宠物身份条。
/// 对照 Figma #319:1027-1051。
struct HomeHero: View {
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
                    // 铃铛：有提醒时轻弹一次（wiggle 为 iOS 18 效果，iOS 17 用 bounce），点击按触发原因分流（回忆中心/确认窗/选择菜单）
                    Button {
                        Haptics.light()
                        bellAnimating = false
                        onBellTap()
                    } label: {
                        Image(systemName: "bell")
                            .font(.system(size: Sizing.iconMd))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .symbolEffect(.bounce, value: bellAnimating)
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
                        .font(.localeDisplayFont(size: 37, relativeTo: .largeTitle))
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

    /// 星期名按 App 匹配语言取 `DateFormatter.weekdaySymbols`（当前仅简中翻译，
    /// 新增语言后自动跟随切换），不再硬编码中文数组。
    private static let weekdaySymbols: [String] = {
        let formatter = DateFormatter()
        let preferred = Bundle.main.preferredLocalizations.first(where: { $0 != "Base" }) ?? "zh-Hans"
        formatter.locale = Locale(identifier: preferred)
        return formatter.weekdaySymbols ?? []
    }()

    /// 日期格式：「8月10日 · 星期一」（对照 #319:1030）。
    private var heroDateString: String {
        let now = Date()
        let cal = Calendar.current
        let month = cal.component(.month, from: now)
        let day = cal.component(.day, from: now)
        // Calendar.weekday 从 1（周日）起算，weekdaySymbols 下标从 0（周日）起算，减一对齐。
        let idx = cal.component(.weekday, from: now) - 1
        let symbols = Self.weekdaySymbols
        let weekday = symbols.indices.contains(idx) ? symbols[idx] : ""
        return String(localized: "home.hero.date \(month) \(day) \(weekday)")
    }
}

// MARK: - 即将到来的日子

/// 即将到来的纪念日区块：珊瑚竖线 + 标题 + 倒计时 + 缩略图。
/// 对照 Figma #319:1039-1053。
struct UpcomingDaySection: View {
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

struct MemoryEditorialRow: View {
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

struct HomeEmptyState: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Text("MiLens")
                .font(.displayLargeEN)
                .foregroundStyle(Color.milensTextPrimary)
            Text(String(localized: "home.empty.title"))
                .font(.editorialSection)
                .foregroundStyle(Color.milensTextPrimary)
            Text(String(localized: "home.empty.body"))
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)
            NavigationLink(value: Route.gallery) {
                Text(String(localized: "home.empty.cta"))
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

struct HomeRecoverableState: View {
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
struct YearlyRecapEntry: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "home.yearlyRecap.title"))
                        .font(.localeDisplayFont(size: 17, relativeTo: .headline))
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
struct BackupReminderBanner: View {
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
