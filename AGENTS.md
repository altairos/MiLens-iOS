# AGENTS.md

本文件适用于 `MiLens` iOS 工程根目录及全部子目录，供自动化编码代理和协作者使用。

源 HarmonyOS 工程位于 `e:\HarmonyProjects\MiPhoto2`，迁移上下文见 [MIGRATION_ASSESSMENT.md](MIGRATION_ASSESSMENT.md)。本文件只覆盖 iOS 工程边界。

## 1. 开始前

1. 先阅读 [DESIGN.md](DESIGN.md) 了解目标架构，再阅读 [PLAN.md](PLAN.md) 确认优先级；构建与验证遵循 [DEVELOPMENT.md](DEVELOPMENT.md)；迁移范围与映射决策见 [MIGRATION_ASSESSMENT.md](MIGRATION_ASSESSMENT.md)。
2. 执行 `git status --short`。工作区可能包含未提交改动，禁止覆盖、回退、格式化或顺手修复无关文件。
3. 修改前定位调用链和测试。优先使用 `rg` / `rg --files`，不要依据文件名猜测功能状态。
4. 任务事实与文档冲突时，以当前代码、构建配置和可复现测试结果为准，并同步更新受影响文档。
5. 迁移鸿蒙功能时，先核对源端对应模块的实现与测试（源端路径见评估报告 §2），把测试作为行为规格翻译，不要凭名字臆测。

## 2. 不可破坏的边界

- 不提交 Apple Developer 签名私钥、`.p12`/`.cer`/` Provisioning Profile`、App Store Connect API Key、IAP 共享密钥。
- 不在版本控制中写入本机绝对路径、签名密码、证书路径。签名通过 `xcconfig`（已 gitignore）或 Xcode GUI 配置。
- 不编辑 `DerivedData/`、`.build/`、`*.xcodeproj/project.xcworkspace/`、`*.xcodeproj/xcuserdata/` 和其他生成产物，除非任务明确要求更新受版本控制的生成文件。
- 不把用户照片、真实宠物数据、个人数据库提交进仓库。
- 不清空数据库、不删除媒体、不重置 Git 历史。
- 不把穿戴端（watchOS）能力重新引入 V1.0。iOS V1.0 明确砍掉手表，相关代码不应出现在本工程。
- 不引入跨平台桥接层（React Native/Flutter/RNBridge）。本项目策略是 **Swift/SwiftUI 完整重写**。
- 保留源端的安全语义：照片不离开设备、AI 分析本地完成（除非产品明确批准的云功能）；不绕过用户隐私确认；导出/分享走系统标准能力。
- 不降低源端已建立的资源生命周期纪律：异步任务可取消、图像解码缓冲有上限、PixelMap/CGImageSource/文件句柄/模型会话必须成对释放。

## 3. 架构规则

- **目标**：iOS 17+，Swift 5.9+，SwiftUI 为主，SwiftData 持久化，`@Observable` 宏状态管理。详见 [DESIGN.md](DESIGN.md)。
- **分层**：View（`Views/`）→ ViewModel（`ViewModels/`，`@Observable`）→ Service（`Services/`）→ Repository（`Persistence/`，SwiftData `@Model`）。决策逻辑下沉为可单测的纯结构/纯函数。
- **模块边界**：拼豆算法/工具/类型收敛到本地 Swift Package `MiLensKit`，用 `public` API 控制导出面（对应源端 `shared/Index.ets`）。App target 不引用 `MiLensKit` 内部符号。
- **平台隔离**：系统框架（Photos/Vision/Core ML/FileManager/StoreKit）通过 Swift `protocol` 抽象，真实实现与 mock 分离（对应源端 `adapters/`）。业务层不直接依赖具体系统类型。
- **DI**：`@main App` 作为组合根，通过 SwiftUI `Environment` 值注入 service/repository。ViewModel 不持有全局单例入口；用窄协议声明依赖。
- **导航**：`NavigationStack` + 类型安全路由枚举（`NavigationLink(value:)`），不复刻源端 URL 路由字符串。
- **资源**：`Assets.xcassets` 集中管理图片（@2x/@3x）、颜色（Any/Dark Appearance）、App Icon；本地化用 String Catalog（`MiLens/Resources/Localizable.xcstrings` 管 UI 文案、`InfoPlist.xcstrings` 管权限说明与 App 名），源语言简中，结构支持任意语言；代码用 `String(localized:)`（不用 `NSLocalizedString`）。新增语言在 `project.yml` 的 `knownRegions` 追加，导出/导入见 `tools/localization.py`。
- **规模**：参照源端 600/800 行守卫思路。单文件超 600 行（编辑器/算法核心 800 行）须拆分，不留长期豁免。

## 4. 实现规则

- 保持 Swift 强类型，避免 `Any`、`AnyObject` 滥用和强制解包（`!`），不吞掉错误。错误类型实现 `Error` 协议，用 `throws` + `do-catch`。
- 异步用 `async/await` + `Task`；注意 `Sendable` 约束与 Actor 隔离。长任务必须支持取消（`Task.cancel()` / `Task.checkCancellation()`）。
- 值类型优先：数据模型用 `struct` + `Codable`；SwiftData 持久化实体用 `@Model class`。UI 简单状态用 `@State`，跨视图共享的可观察模型用 `@Observable`。
- 异步资源成对释放：`CGImageSource`、文件句柄、Core ML 模型会话、`URLSession` task、定时器在 `defer` / `Task.cancel()` / 视图销毁路径统一清理。
- 大图库走分页/分批/流式：`PHFetchOptions` 分页、缩略图异步加载、`LazyVStack`/`Grid` 虚拟化；不在内存无界加载全尺寸原图。
- 数据模型变更同时更新：SwiftData `@Model`、迁移计划（`VersionedSchema`/`SchemaMigrationPlan`）、Repository、测试。
- UI 使用 Asset Catalog 主题 token，处理安全区、深色模式、Dynamic Type 与 iPhone/iPad 适配；不引入 Web 动画库。
- AI 推理失败必须可诊断并安全降级。不得把 Vision 通用识别或中心裁切描述为已完成的自定义宠物语义模型（沿用源端诚实标注原则）。
- 拼豆算法 Swift 重写时，以源端 225 用例 + ArkTS/C++ parity 测试为黄金规格逐条翻译，行为一致性由 XCTest 守护。
- StoreKit 2 实现订阅/购买，订阅状态通过 `Transaction` 监听；不硬编码产品价格。
- 用户可见文字优先为简体中文，保持产品名「咪Lens/MiLens」和术语与源端一致。

## 5. 验证规则

最小验证取决于改动范围：

| 改动 | 最少验证 |
|---|---|
| 纯文档 | 链接、路径、日期、命令与代码现状核对；`git diff --check` |
| Swift 业务/工具 | 对应 XCTest；可行时运行完整测试套件 |
| 拼豆算法 | `MiLensKit` 对应用例的 XCTest，并对照源端 parity |
| SwiftData | 单元测试 + schema 变更的真机/模拟器验证 |
| UI | 编译 + iPhone/iPad 关键尺寸预览/模拟器检查 |
| AI/Vision/Core ML | 单元测试不能替代真机验证；需在 iPhone 真机跑推理与降级路径 |
| StoreKit | StoreKit Testing（本地）+ 沙盒环境验证 |

不要只报告 `BUILD SUCCEEDED`；还要检查 XCTest 汇总、覆盖率以及测试最终退出码。若未执行某项验证，要明确写「未执行」和原因。

覆盖率门禁已接入 CI（`tools/check-coverage.sh`，解析 `TestResult.xcresult` 与基线比较）：MiLens (App) 默认 30/25/30、MiLensKit 默认 47/50/44（lines/functions/branches %）。当前为对齐源端的占位值，首次 CI 实测后校准（见脚本头注释）；基线可用 `APP_*_MIN`/`KIT_*_MIN` 环境变量覆盖。

## 6. 文档维护

- `MIGRATION_ASSESSMENT.md`：源项目盘点、模块/API 映射、范围边界、风险登记（迁移期事实来源）。
- `DESIGN.md`：目标 iOS 架构、技术栈、数据流、设计决策和已知限制。
- `PLAN.md`：未完成工作、里程碑、优先级、验收标准；完成后移入状态摘要。
- `DEVELOPMENT.md`：环境、命令、开发约定、可复现验证快照。
- `docs/`：算法、UI、迁移专题等细节。

避免在多份文档复制大段实现细节；使用相对链接指向唯一事实来源。技术栈、最低版本、签名状态或质量门禁变化时，同一提交内更新对应文档。
