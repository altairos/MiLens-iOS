//  HelpView —— 使用帮助（Settings 支持分组入口）。
//
//  条目只描述 V1 已实现能力（扫描/导入/归档、拼豆图纸、导出），
//  不写未上线功能（P0-1/P0-4 诚实性纪律）。

import SwiftUI

struct HelpView: View {

    private struct QA: Identifiable {
        let id: Int
        let question: String
        let answer: String
    }

    private var items: [QA] {
        [
            QA(
                id: 1,
                question: String(localized: "help.q1"),
                answer: String(localized: "help.a1")
            ),
            QA(
                id: 2,
                question: String(localized: "help.q2"),
                answer: String(localized: "help.a2")
            ),
            QA(
                id: 3,
                question: String(localized: "help.q3"),
                answer: String(localized: "help.a3")
            ),
            QA(
                id: 4,
                question: String(localized: "help.q4"),
                answer: String(localized: "help.a4")
            )
        ]
    }

    var body: some View {
        List(items) { item in
            Section {
                Text(item.answer)
                    .font(.bodySecondary)
                    .foregroundStyle(Color.milensTextSecondary)
            } header: {
                Text(item.question)
                    .font(.bodyPrimary)
                    .foregroundStyle(Color.milensTextPrimary)
                    .textCase(nil)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.milensBackground)
        .navigationTitle(String(localized: "settings.support.help"))
    }
}
