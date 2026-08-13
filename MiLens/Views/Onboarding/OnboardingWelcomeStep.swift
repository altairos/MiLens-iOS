//  OnboardingWelcomeStep —— 首次启动 01 欢迎 / 空态（对照 Figma #47:6）。
//  品牌瞬间：FIRST LIGHT overline + "MiLens" 品牌名 + 文楷 Hero「把相伴的一生，留在这里」。
//  Empty Archive Surface 卡片：虚线轨道 + 品牌印章 + 「等待第一位伙伴」+ Register 标记。
//  3 waypoint（本机整理/由你确认/随时可删）+ Divider + 隐私政策行。
//  底部 FocusDialButton「建立第一份档案」（未同意隐私政策时 disabled）。

import SwiftUI

struct OnboardingWelcomeStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: overline + 品牌名 + Hero
                Text("FIRST LIGHT · 欢迎")
                    .font(.editorialOverline)
                    .tracking(0.1)
                    .foregroundStyle(Color.milensTextSecondary)
                    .textCase(.uppercase)

                Text("MiLens")
                    .font(.displayLargeEN)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.top, 8)

                Text("把相伴的一生，\n留在这里")
                    .font(.editorialHero)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.top, 6)
                    .accessibilityAddTraits(.isHeader)

                // MARK: Empty Archive Surface 卡片
                emptyArchiveCard
                    .padding(.top, 18)

                // MARK: 3 waypoint
                WaypointRow(items: ["本机整理", "由你确认", "随时可删"])
                    .padding(.top, Spacing.xxl)

                // MARK: Divider
                Rectangle()
                    .fill(Color.milensSeparator)
                    .frame(height: 1)
                    .padding(.top, Spacing.xl)

                // MARK: 隐私政策行
                privacyRow
                    .padding(.top, Spacing.md)

                // MARK: Focus Dial
                FocusDialButton(
                    label: "建立第一份档案",
                    systemImage: "plus",
                    isEnabled: viewModel.privacyAgreed
                ) {
                    viewModel.goToNextStep()
                }
                .padding(.top, Spacing.xxl)
            }
            .padding(.horizontal, Spacing.pagePad)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Empty Archive Surface 卡片（对照 #47:6 Empty Archive）

    private var emptyArchiveCard: some View {
        EditorialCard {
            VStack(alignment: .leading, spacing: 0) {
                // EMPTY ARCHIVE / 00 caption
                Text("EMPTY ARCHIVE / 00")
                    .font(.editorialMetadata)
                    .foregroundStyle(Color.milensTextTertiary)
                    .padding(.top, 22)
                    .padding(.leading, 22)

                // 品牌印章 + 虚线轨道
                ZStack {
                    // Brand Orbit 开放轨道圆（对照 #94:30：stroke #7C3F30 2px 实线）
                    Circle()
                        .stroke(Color.milensDialSurface, lineWidth: 2)
                        .frame(width: 132, height: 132)
                        .padding(.trailing, 8)

                    // 品牌印章（App Icon 资源，对照 #94:32：64×64 圆角 60 ≈ 圆形）
                    Image("BrandSeal")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .padding(.trailing, 8)

                    // 端点圆点
                    Circle()
                        .fill(Color.milensActionPrimary)
                        .frame(width: 9, height: 9)
                        .offset(x: 70, y: -60)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .padding(.top, 16)

                // 「等待一位伙伴」
                Text("等待第一位伙伴")
                    .font(.uiTitle)
                    .foregroundStyle(Color.milensTextPrimary)
                    .padding(.top, 4)
                    .padding(.leading, 22)

                Text("档案现在是空的。\n从第一段相伴开始。")
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextSecondary)
                    .padding(.top, 4)
                    .padding(.leading, 22)

                // Register 标记
                RegisterMark(leadWidth: 46, tailWidth: 180)
                    .padding(.top, 14)
                    .padding(.leading, 22)
                    .padding(.trailing, 16)

                // 底部说明
                Text("照片留在设备上，记录由你命名。")
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextTertiary)
                    .padding(.top, 6)
                    .padding(.leading, 22)
                    .padding(.bottom, 22)
            }
        }
    }

    // MARK: - 隐私政策行（对照 #47:6 Privacy / Read Policy）

    private var privacyRow: some View {
        HStack(spacing: 0) {
            // Active Rail（已同意时显示珊瑚竖线）
            Rectangle()
                .fill(viewModel.privacyAgreed ? Color.milensActionPrimary : Color.clear)
                .frame(width: 3, height: 22)
                .cornerRadius(Radius.accentRail)

            Toggle(isOn: Binding(
                get: { viewModel.privacyAgreed },
                set: { viewModel.privacyAgreed = $0 }
            )) {
                HStack(spacing: 4) {
                    Text("我已阅读并同意")
                        .font(.bodyPrimary)
                        .foregroundStyle(Color.milensTextSecondary)
                    if let url = URL(string: SettingsLogic.Links.privacyPolicy) {
                        Link("《隐私政策》", destination: url)
                            .font(.bodyPrimary)
                            .foregroundStyle(Color.milensActionPrimary)
                    }
                }
            }
            .toggleStyle(.plain)
            .labelsHidden()
            .padding(.leading, 11)

            Spacer()

            // → 箭头
            Text("\u{2192}")
                .font(.uiBodyStrong)
                .foregroundStyle(Color.milensActionPrimary)
                .opacity(viewModel.privacyAgreed ? 1 : 0.3)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.privacyAgreed.toggle()
        }
    }
}
