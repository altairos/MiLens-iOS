//  首页（Tab 1）—— P2 实现：相册入口 + 扫描入口。
//  P5 完善：今日照片 / 历史回忆（一年前的今天） / 成长提醒 / 快速创作入口。

import SwiftUI

struct HomeView: View {
    @Environment(\.photoRepository) private var photoRepo

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroSection
                actionsSection
            }
            .padding()
        }
    }

    private var heroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.milensPrimary)
            Text("咪Lens")
                .font(.displayLarge)
            Text("你的宠物数字生命档案")
                .font(.bodyPrimary)
                .foregroundStyle(Color.milensTextSecondary)
        }
        .padding(.top, 40)
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            NavigationLink(value: Route.gallery) {
                actionCard(
                    icon: "photo.stack.fill",
                    title: "相册",
                    subtitle: "浏览所有宠物照片"
                )
            }
            NavigationLink(value: Route.gallery) {
                actionCard(
                    icon: "magnifyingglass",
                    title: "扫描发现",
                    subtitle: "自动识别相册中的宠物"
                )
            }
        }
    }

    private func actionCard(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.milensPrimary)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.titleStandard)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(Color.milensTextSecondary)
        }
        .padding(16)
        .background(Color.milensCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium))
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
