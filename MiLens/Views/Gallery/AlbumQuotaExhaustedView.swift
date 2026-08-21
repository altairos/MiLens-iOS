//  AlbumQuotaExhaustedView —— 免费额度用尽页（对照 Figma 07·免费额度已用完 #27:9 / #35）。
//  Quota Archive Card（50/50 大数字 + Timeline 进度条）+ 标题 + 说明 + Resilience Register
//  （3 行保证）+ "暂不升级"文字 + "查看 MiLens Pro" Action。

import SwiftUI

struct AlbumQuotaExhaustedView: View {
    @Bindable var vm: GalleryViewModel
    let onDismiss: () -> Void
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                quotaArchiveCard
                titleSection
                    .padding(.top, 24)
                resilienceRegister
                    .padding(.top, 24)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
        }
    }

    // MARK: - Quota Archive Card（对照 #35:26-37）

    private var quotaArchiveCard: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "album.quota.mark"))
                    .font(.custom("JacquesFrancois-Regular", size: 10))
                    .tracking(0.4)
                    .foregroundStyle(Color.milensActionPrimary)
                    .padding(.top, 18)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(CommercialRules.freePhotoLimit)")
                        .font(.localeDisplayFont(size: 40, relativeTo: .largeTitle))
                        .foregroundStyle(Color.milensTextPrimary)
                    Text("/ \(CommercialRules.freePhotoLimit)")
                        .font(.uiTitle)
                        .foregroundStyle(Color.milensTextSecondary)
                }
                .padding(.top, 18)

                Text(String(localized: "album.quota.usedUp"))
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.top, 18)

                Text(String(localized: "album.quota.existingKept"))
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.top, 2)

                // Quota Timeline（对照 #35:35-37）
                quotaTimeline
                    .padding(.top, 22)
                    .padding(.bottom, 18)
            }
            .padding(.leading, 13)
            .padding(.trailing, 16)
        }
        .background(Color.milensCard)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.milensBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, Spacing.lg)
    }

    // MARK: - Quota Timeline（对照 #35:35-37）

    private var quotaTimeline: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.milensBorder)
                    .frame(height: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
                Rectangle()
                    .fill(Color.milensActionPrimary)
                    .frame(width: geo.size.width, height: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 10, height: 10)
                }
            }
        }
        .frame(height: 10)
    }

    // MARK: - 标题区（对照 #35:38-39）

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "album.quota.title \(CommercialRules.freePhotoLimit)"))
                        .font(.localeDisplayFont(size: 28, relativeTo: .title2))
                .foregroundStyle(Color.milensTextPrimary)
            Text(String(localized: "album.quota.subtitle"))
                .font(.bodySecondary)
                .foregroundStyle(Color.milensTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Resilience Register（对照 #35:40-53）

    private var resilienceRegister: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "gallery.quota.resilienceMark"))
                .font(.custom("JacquesFrancois-Regular", size: 10))
                .tracking(0.4)
                .foregroundStyle(Color.milensActionPrimary)

            // Baseline
            Rectangle()
                .fill(Color.milensActionPrimary)
                .frame(width: 226, height: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))
                .padding(.top, 10)

            resilienceRow(
                index: "01",
                title: String(localized: "album.quota.resilience1.title"),
                desc: String(localized: "album.quota.resilience1.desc")
            )
            divider

            resilienceRow(
                index: "02",
                title: String(localized: "album.quota.resilience2.title"),
                desc: String(localized: "album.quota.resilience2.desc")
            )
            divider

            resilienceRow(
                index: "03",
                title: String(localized: "album.quota.resilience3.title"),
                desc: String(localized: "album.quota.resilience3.desc")
            )
        }
    }

    private func resilienceRow(index: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 25) {
            Text(index)
                .font(.custom("Fraunces-Bold", size: 12))
                .foregroundStyle(Color.milensActionPrimary)
                .frame(width: 20, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.uiBodyStrong)
                    .foregroundStyle(Color.milensTextPrimary)
                Text(desc)
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextSecondary)
            }
        }
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.milensBorder)
            .frame(height: 1)
            .padding(.leading, 45)
    }

    // MARK: - 底部操作区

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Button {
                showPaywall = true
            } label: {
                HStack {
                    Text(String(localized: "album.quota.viewPro"))
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

            Button(String(localized: "album.quota.later")) {
                onDismiss()
            }
            .font(.bodySecondary)
            .foregroundStyle(Color.milensTextTertiary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
        .background(Color.milensBackground)
    }
}
