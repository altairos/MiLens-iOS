// swift-tools-version: 5.9
// MiLensKit —— 拼豆算法/色彩/工具本地 Swift Package
// 对应源端 shared HSP（e:\HarmonyProjects\MiPhoto2\shared），用 public API 控制导出边界。
// 详见 DESIGN.md §8 与 MIGRATION_ASSESSMENT.md §3。

import PackageDescription

let package = Package(
    name: "MiLensKit",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "MiLensKit", targets: ["MiLensKit"])
    ],
    targets: [
        .target(
            name: "MiLensKit",
            path: "Sources/MiLensKit"
        ),
        .testTarget(
            name: "MiLensKitTests",
            dependencies: ["MiLensKit"],
            path: "Tests/MiLensKitTests"
        )
    ]
)
