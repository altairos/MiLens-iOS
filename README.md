# MiLens iOS

咪Lens iOS 版 —— 宠物家庭的数字生命档案。从 HarmonyOS（[MiPhoto2](../../../HarmonyProjects/MiPhoto2)）完整重写迁移而来。

## 当前阶段

**P0 — Harness 与规划**。文档骨架、约束、目录结构与 XcodeGen 声明已就位，等待 Mac 环境 `xcodegen generate` 验证编译。详见 [PLAN.md](PLAN.md)。

## 快速开始（Mac）

```bash
brew install xcodegen
cd E:\iOSprojects\MiLens   # 实际为 Mac 上的克隆路径
xcodegen generate
open MiLens.xcodeproj
```

环境与命令详见 [DEVELOPMENT.md](DEVELOPMENT.md)。

## 文档导航

| 文档 | 内容 |
|---|---|
| [AGENTS.md](AGENTS.md) | 工程约束（不可破坏的边界/架构/实现/验证规则） |
| [DESIGN.md](DESIGN.md) | 目标 iOS 架构（技术栈/分层/目录/状态/DI/数据） |
| [UI-DESIGN.md](UI-DESIGN.md) | UI 设计规范（色彩/字体/间距/动效/页面视觉） |
| [PLAN.md](PLAN.md) | 迁移里程碑（P0–P5）与任务清单 |
| [MIGRATION_ASSESSMENT.md](MIGRATION_ASSESSMENT.md) | 源项目盘点、模块/API 映射、范围边界、风险 |
| [DEVELOPMENT.md](DEVELOPMENT.md) | 环境、构建命令、开发约定、验证快照 |
| [docs/](docs/) | 产品设计稿与专题 |

## 关键决策

- **iOS 17+**：SwiftData + `@Observable` 宏 + NavigationStack
- **完整重写**：Swift/SwiftUI，不做跨平台桥接
- **拼豆算法 Swift 重写**：源端 C++/ArkTS 纯逻辑翻译，XCTest 守护
- **AI 推理**：Vision 首选，Core ML 待 P1 调研定案

## 工程结构

- `MiLens/` —— App target（Views/Components/ViewModels/Services/Persistence/Theme/Utilities）
- `MiLensKit/` —— 本地 Swift Package（拼豆算法，对应源端 `shared` HSP）
- `project.yml` —— XcodeGen 声明（`.xcodeproj` 由其生成，已 gitignore）

完整结构见 [DESIGN.md](DESIGN.md) §3。

## 迁移背景

源 HarmonyOS 工程：`e:\HarmonyProjects\MiPhoto2`（API 23 / DB v16）。迁移上下文与模块映射见 [MIGRATION_ASSESSMENT.md](MIGRATION_ASSESSMENT.md)。
