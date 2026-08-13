//  PlaceholderTabView —— Tab 占位内容（P1.1 阶段，各 Tab 视图尚未实现时的统一空态）。
//  随 P2+ 各 Tab 逐步替换为真实页面。

import SwiftUI

struct PlaceholderTabView: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 56)) // ui-token:ok 占位页装饰大图标
                .foregroundStyle(Color.milensPrimary)
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Color.milensTextPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.milensTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.milensBackground)
    }
}

#Preview {
    PlaceholderTabView(
        systemImage: "pawprint",
        title: "占位",
        subtitle: "示例副标题"
    )
}
