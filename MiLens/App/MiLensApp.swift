import SwiftUI
import SwiftData
import MiLensKit

// P0 占位入口。组合根、TabView 壳、ModelContainer、Environment 注入将在 P1 实现。
// 详见 DESIGN.md §2/§4。

@main
struct MiLensApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 48))
            Text("咪Lens")
                .font(.title)
            Text("MiLensKit \(MiLensKit.version)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
