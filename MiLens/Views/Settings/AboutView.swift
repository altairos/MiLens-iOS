//  AboutView —— 关于页（Settings 关于分组入口）。
//
//  版本号 + 字体来源与 SIL OFL 1.1 许可声明（UI-DESIGN.md §2.1 合规要求；
//  字体数据以 SettingsLogic.fontCredits 为唯一来源，与 Resources/Fonts/README.md 对齐）。

import SwiftUI

struct AboutView: View {
    let marketing: String
    let build: String

    var body: some View {
        List {
            Section {
                HStack {
                    Text(String(localized: "settings.about.version"))
                    Spacer()
                    Text("\(marketing) (\(build))")
                        .foregroundStyle(Color.milensTextSecondary)
                }
            }

            Section {
                ForEach(SettingsLogic.fontCredits, id: \.name) { credit in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(credit.name)
                            .font(.bodyPrimary)
                            .foregroundStyle(Color.milensTextPrimary)
                        Text(credit.author)
                            .font(.bodySecondary)
                            .foregroundStyle(Color.milensTextSecondary)
                        Text(credit.licenseName)
                            .font(.caption)
                            .foregroundStyle(Color.milensTextTertiary)
                        if let url = URL(string: credit.sourceURL) {
                            Link(credit.sourceURL, destination: url)
                                .font(.caption)
                                .foregroundStyle(Color.milensActionPrimary)
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
                Text(String(localized: "about.fonts.note"))
                    .font(.caption)
                    .foregroundStyle(Color.milensTextSecondary)
            } header: {
                Text(String(localized: "about.fonts.title"))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.milensBackground)
        .navigationTitle(String(localized: "settings.about.entry"))
    }
}
