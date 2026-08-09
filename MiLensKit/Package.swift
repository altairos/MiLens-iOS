// swift-tools-version: 5.9
// MiLensKit —— 拼豆算法/色彩/工具本地 Swift Package
// 对应源端 shared HSP（e:\HarmonyProjects\MiPhoto2\shared），用 public API 控制导出边界。
// 详见 DESIGN.md §8 与 MIGRATION_ASSESSMENT.md §3。

import PackageDescription

let package = Package(
    name: "MiLensKit",
    platforms: [
        .iOS(.v17),
        // 纯逻辑包在 macOS 上可独立 swift test（BeadFlowLogicTests 等 26 用例）。
        // Task.checkCancellation() 需要 macOS 10.15+，故显式声明部署目标。
        .macOS(.v13)
    ],
    products: [
        .library(name: "MiLensKit", targets: ["MiLensKit"])
    ],
    targets: [
        .target(
            name: "MiLensKit",
            path: "Sources/MiLensKit",
            swiftSettings: [
                // M3：严格并发检查（complete）；保持 Swift 5 语言模式，不引入 Swift 6 破坏性变更。
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),
        .testTarget(
            name: "MiLensKitTests",
            dependencies: ["MiLensKit"],
            path: "Tests/MiLensKitTests",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        )
    ]
)
