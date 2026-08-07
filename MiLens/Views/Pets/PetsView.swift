//  宠物档案（Tab 2）—— P1.1 占位。
//  P3 实现：宠物头像/名称/年龄、档案 CRUD、成长时间线、纪念提醒。

import SwiftUI

struct PetsView: View {
    var body: some View {
        PlaceholderTabView(
            systemImage: "pawprint.fill",
            title: String(localized: "tab.pets"),
            subtitle: String(localized: "pets.placeholder", comment: "宠物页占位说明")
        )
    }
}
