//  我的（Tab 4）—— P1.1 占位。
//  P5 实现：主题/隐私设置、StoreKit Pro 订阅、帮助、关于。

import SwiftUI

struct SettingsView: View {
    var body: some View {
        PlaceholderTabView(
            systemImage: "person.fill",
            title: String(localized: "tab.settings"),
            subtitle: String(localized: "settings.placeholder", comment: "我的页占位说明")
        )
    }
}
