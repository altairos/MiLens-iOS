//  创作（Tab 3）—— P1.1 占位。
//  P4 实现：拼豆图纸（选图→生成→预览→A4 导出）、宠物卡片。

import SwiftUI

struct CreateView: View {
    var body: some View {
        PlaceholderTabView(
            systemImage: "square.and.pencil.fill",
            title: String(localized: "tab.create"),
            subtitle: String(localized: "create.placeholder", comment: "创作页占位说明")
        )
    }
}
