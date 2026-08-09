# MiLens iOS

咪Lens iOS 版 —— 宠物家庭的数字生命档案。从 HarmonyOS（MiPhoto2）完整重写迁移而来。

## 当前阶段

**P0–P5 实现完成，上架准备中**。文档骨架、约束、目录结构、XcodeGen 声明、范围对齐全部就位；SwiftData schema、拼豆 Swift 核心（黄金规格通过）、相册 MVP、宠物档案、创作入口 + 完整图片编辑器、首页/设置/StoreKit 订阅/付费墙均已实现。本机 macOS 编译通过、**1198+ XCTest 用例全绿**（MiLensKit 594 + App 604 + UI 2），严格并发 `complete` 下编译通过。剩真机验证、性能基准、App Store 上架实测。详见 [PLAN.md](PLAN.md)。

## 快速开始（Mac）

```bash
brew install xcodegen
# 在仓库根目录
tools/fetch-models.sh     # 下载生产模型（CLIP int8 + RTMPose fp16，GitHub Release + SHA256 校验）
xcodegen generate
open MiLens.xcodeproj
```

> 顺序约束：必须先下载模型再 `xcodegen generate`（XcodeGen 生成工程时模型须已存在，否则 `.mlpackage` 不进 Resources Build Phase，正式包会静默降级到 Vision）。

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
- **拼豆算法 Swift 重写**：源端 C++/ArkTS 纯逻辑翻译，XCTest 守护（源端 225 用例 + parity）
- **AI 推理（已定案）**：方案 A 全转换（CLIP + RTMPose → Core ML，INT8 量化）+ Vision 原生分割，详见 [ADR-0007](docs/adr/0007-ios-ai-inference-route.md)
- **V1.0 范围**：完整图片编辑器 + 质量评分 + 重复分组进 V1.0；备份/AI 写真后置，详见 [ADR-0008](docs/adr/0008-v1-scope-decision.md)
- **Pro 权益**：免费版 1 宠物档案/50 张照片/每日 5 次拼豆/最近一年时间线/导出带水印；Pro 版 20 档案/不限照片/完整历史/无水印；详见 [ADR-0009](docs/adr/0009-pro-entitlement-rules.md) + [ADR-0010](docs/adr/0010-commercialization-and-emotion-triggers.md)

## 工程结构

- `MiLens/` —— App target（Views/Components/ViewModels/Services/Persistence/Theme/Utilities）
- `MiLensKit/` —— 本地 Swift Package（拼豆算法 + 编辑器纯逻辑 + 诊断，对应源端 `shared` HSP）
- `project.yml` —— XcodeGen 声明（`.xcodeproj` 由其生成，已 gitignore）

完整结构见 [DESIGN.md](DESIGN.md) §3。

## 迁移背景

源 HarmonyOS 工程为 `MiPhoto2`（API 23 / DB v16），迁移上下文与模块映射见 [MIGRATION_ASSESSMENT.md](MIGRATION_ASSESSMENT.md)。
