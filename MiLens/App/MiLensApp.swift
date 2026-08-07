//  组合根（DESIGN.md §4.1）。
//  应用级依赖（ModelContainer / Repository / 长生命周期 Service）在此构造并注入。
//  P1.1 暂不接 SwiftData（@Model 待 P1.2）；scenePhase 生命周期编排交由 RootTabView。
//  对应源端 EntryAbility（HarmonyOS UIAbility 生命周期入口）。

import SwiftUI

@main
struct MiLensApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
