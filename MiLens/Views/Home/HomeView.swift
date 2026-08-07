//  首页（Tab 1）—— P1.1 占位。
//  P2/P5 实现：今日照片 / 历史回忆（一年前的今天） / 成长提醒 / 快速创作入口。

import SwiftUI

struct HomeView: View {
    var body: some View {
        PlaceholderTabView(
            systemImage: "house.fill",
            title: String(localized: "tab.home"),
            subtitle: String(localized: "home.placeholder", comment: "首页占位说明")
        )
    }
}
