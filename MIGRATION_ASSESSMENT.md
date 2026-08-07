# MiLens iOS 迁移评估报告

最后核对：2026-08-07（基于 MiPhoto2 源端 API 23 / DB v16 快照）

> 本文档是 [PLAN.md](PLAN.md) 与 [DESIGN.md](DESIGN.md) 的事实基础，盘点源 HarmonyOS 项目并给出模块/API 映射决策。架构约束见 [AGENTS.md](AGENTS.md)。

## 1. 迁移决策摘要

| 决策项 | 选择 | 影响 |
|---|---|---|
| iOS 最低版本 | **iOS 17+** | 可用 SwiftData、`@Observable` 宏、NavigationStack 全套、Swift 5.9+ 宏 |
| 迁移策略 | **完整重写** | 不做跨平台桥接，从零用 SwiftUI 设计，充分利用平台优势 |
| 拼豆算法核心 | **Swift 重写** | C++ 3,665 行纯逻辑（色彩/量化/抖动/去噪）改写为 Swift，XCTest 完整覆盖，去掉 N-API 边界 |
| AI 推理框架 | **已定案：方案 A 全转换**（见 §6 / [ADR-0007](docs/adr/0007-ios-ai-inference-route.md)） | CLIP + RTMPose 转 Core ML，分割用 iOS 原生 Vision |

## 2. 源项目规模盘点（MiPhoto2，API 23）

| 模块 | 文件 | 行数 | iOS V1.0 处置 |
|---|---|---|---|
| `entry`（主产品 ArkTS） | 257 | 43,319 | 迁移（按 V1.0 范围裁剪） |
| `shared` HSP（拼豆 ArkTS） | 36 | 9,012 | Swift 重写为本地 Swift Package |
| `shared` C++ Native | 27 | ~3,665 | 合并进 Swift 重写（不保留 bridging） |
| `entry_wearable`（穿戴端） | 17 | 2,346 | **不迁移**（iOS V1.0 砍掉手表） |
| 测试（entry + shared） | 153 | ~24,000 | 作为行为规格参照，逐模块翻译为 XCTest |

生产代码合计约 **5.8 万行**，其中穿戴端 2,346 行不迁移。

### 2.1 `entry` 子目录结构（14 个子模块）

| 子目录 | 文件 | 职责 | iOS 对应 |
|---|---|---|---|
| `pages` | 13 | 页面入口 | `Views/` |
| `components` | 54 | 复用组件 | `Components/` |
| `editor` | 30 | 图片编辑器内部拆分（控制器/核心/纯逻辑） | `Features/Editor/` |
| `viewmodels` | 35 | 页面状态机与纯决策逻辑 | `ViewModels/` |
| `services` | 57 | AI/备份/扫描/导出/DI 用例层 | `Services/` |
| `database` | 12 | RDB schema/DAO/repository | `Persistence/` |
| `adapters` | 9 | 系统 Kit 接口隔离 + Fake | `Services/Platform/`（Swift protocol + mock） |
| `theme` | 4 | 设计 token/主题/响应式 | `Theme/`（Asset Catalog + Color 扩展） |
| `utils` | 33 | 工具/守卫/日志 | `Utilities/` |
| `models` / `repository` / `constants` / `entryability` / `entrybackupability` | — | 模型/仓储/常量/Ability | 见 §3 |

### 2.2 源端 13 个页面

`Index`（引导组合根）、`SplashPage`、`MainPage`（4 Tab 壳）、`GalleryPage`（相册）、`PetProfilePage`、`PetEditPage`、`TimelinePage`（成长时间线）、`PhotoViewPage`、`EditorPage`（编辑器）、`BeadPatternPage`（拼豆）、`PhotoCollagePage`（拼图）、`AvatarCropPage`、`SettingsPage`。

### 2.3 源端 57 个服务（按域分组）

- **AI 域（17）**：`AiService`/`AiRegistry`/`AiInferenceLogic`、`ClipPreprocess`/`ClipTensorUtils`、`PetMatcher`/`PetMatcherScoring`/`PetDiversityAnalysis`/`PetFeatureCodec`/`PetTextEmbeddings`、`PoseInferenceService`/`PoseInferenceMath`、`ImageSegmentService`/`AlphaMatteRefiner`、`QualityScorer`、`VisionClassifier`、`ColorSignatureMath`
- **备份域（12）**：`BackupServer`/`BackupSession`/`BackupSessionManager`、`BackupAuthEvaluator`/`BackupRouteRouter`/`BackupHttpHeaders`/`BackupPageMath`/`BackupPageBuilder`/`BackupContentServer`/`BackupZipStreamer`/`BackupNetworkMonitor`、`HttpRequestParser`
- **扫描/导入域（6）**：`PhotoScanner`/`ScanController`/`ScanSession`、`PhotoAssetMapper`/`PhotoImportFileUtils`/`PhotoImportMetadata`
- **导出域（3）**：`ExportService`/`ExportSession`/`CancellationToken`
- **DI 域（4）**：`AppServiceLocator`/`AppRegistry`/`AiRegistry`/`ShutdownCoordinator`（+ `ISession`）
- **其他（15）**：`GalleryAdapters`/`GalleryExportHandler`/`GalleryPhotoLoader`/`GalleryScanHandler`/`GallerySelectionHandler`、`PhotoViewCoordinator`、`MediaMonitor`、`CacheService`、`DiagnosticsService`、`NotifyScheduler`、`SlideshowService`、`ThemeManager`、`TimeMachineService`、`WearDailyDigestService`/`WearTransferService`（**穿戴相关不迁移**）

## 3. 模块映射决策

| 鸿蒙概念 | iOS 对应 | 说明 |
|---|---|---|
| `entry` HAP | App target | 主 App |
| `shared` HSP（`Index.ets` 导出边界） | 本地 Swift Package `MiLensKit` | 拼豆算法/工具/类型，用 `public` API 控制边界 |
| `entry_wearable` | — | 不迁移 |
| `EntryAbility`（UIAbility） | `@main App` + `scenePhase` | 生命周期入口 |
| `AppServiceLocator` 三级 DI | Swift `Environment` 值注入 / `@Observable` 容器 | 见 [DESIGN.md](DESIGN.md) §DI |
| `resources/base/` | `Assets.xcassets/` + `.lproj/` | 资源 + 本地化 |
| `module.json5` 权限 | `Info.plist` Usage Description + 运行时请求 | 权限体系 |
| `$r('app.*')` 资源引用 | `Image(_:)` / `NSLocalizedString` / `Color(_:)` | 资源引用方式 |

## 4. 系统能力 API 对照

| 鸿蒙 Kit | iOS 框架 | 迁移要点 |
|---|---|---|
| `@ohos.data.relationalStore` | **SwiftData**（iOS 17+） | 重新建模为 `@Model`；schema v16 需设计 SwiftData 迁移计划 |
| `@ohos.data.preferences` | `UserDefaults` / `@AppStorage` | |
| `@ohos.file.fs` | `FileManager` | 沙盒路径 `documents/library/caches/tmp` |
| `@ohos.multimedia.image` | `UIImage` / `PhotosUI` / `CGImageSource` | 缩略图/解码/编码用 ImageIO |
| `@ohos.net.http` | `URLSession` + async/await | |
| `@ohos.multimedia.photoAccessHelper` | `Photos` 框架（PHFetchOptions）或 `PHPicker` | 选图用 PHPicker（免权限），扫描全库需 Photos 权限 |
| `@ohos.sensor` | `CoreMotion` / `CoreLocation` | |
| `@ohos.notification` | `UserNotifications` | |
| `@ohos.backgroundTasksManager` | Background Modes + `BGTaskScheduler` | |
| `@kit.MindSporeLiteKit` | **Core ML**（待定，见 §6） | 模型需从 ONNX/MS 转换 |
| `@kit.CoreVisionKit`（分割/检测） | **Vision**（VNGenerateForegroundInstanceMask 等） | iOS 17 有主体分割 API |
| wearEngine P2P | — | 不迁移 |

## 5. 迁移范围边界（基于 iOS V1.0 设计稿）

依据 `docs/MiLens_iOS_V1.0_页面原型与交互流程设计稿.md`：

### 5.1 迁入 V1.0（核心）

- 首次启动：欢迎 → 权限说明 → 扫描发现宠物 → 创建第一份档案
- Tab 结构：首页（今日/回忆/提醒）｜宠物档案｜创作｜我的
- 相册：扫描发现 + 手动导入 + 宠物归属筛选
- 宠物档案：档案/成长时间线/纪念提醒
- 创作：**拼豆图纸**（源端核心，必迁）、宠物卡片
- 设置/我的：主题、隐私设置、帮助、关于
- 付费墙：MiLens Pro 订阅（**iOS 新增**，StoreKit 2）

### 5.2 V1.0 暂缓（源端有但 iOS 不迁或后置）

| 功能 | 处置 | 原因 |
|---|---|---|
| 穿戴端（手表） | **不迁** | V1.0 明确砍掉 |
| 健康档案/疫苗/体重 | 后置 | V1.0 砍掉，V2 考虑 |
| 社区/云账号/商城 | 不迁 | V1.0 砍掉 |
| 家庭局域网备份（12 个服务） | **后置到 V1.x** | 复杂度高且非核心叙事；V1.0 先用 AirDrop/iCloud 替代导出 |
| 完整图片编辑器（裁剪/调色/抠图/相框/文字/贴纸） | **简化** | V1.0 创作入口聚焦拼豆；编辑器能力按需后置 |
| AI 写真/回忆视频 | **iOS 新增，需新方案** | 源端无对应，需额外设计（可能依赖云服务，待产品决策） |
| 质量评分/重复分组 | 后置 | 非核心叙事，V1.x 再补 |

> ⚠️ 范围裁剪是产品决策，[PLAN.md](PLAN.md) 中标注为「待确认」的项需在 P0 阶段与产品对齐。

## 6. AI 推理路线（已定案 2026-08-08）

> 决策详见 [ADR-0007](docs/adr/0007-ios-ai-inference-route.md)。本节保留决策背景。

源端 AI 链路三件套：

1. **CLIP 视觉编码器**（`clip_vision_encoder.ms`，167.66 MB FP32，512 维特征）——宠物/非宠物零样本分类 + 视觉特征提取（PetMatcher）
2. **RTMPose-t 宠物脸**（`rtmpose_t_pet_face.ms`，5.90 MB，5 点 SimCC）——拼豆二次裁切锚点
3. **VisionKit 主体分割**——抠图 alpha

决策时评估的候选方案：

| 方案 | 适用 | 优势 | 风险 |
|---|---|---|---|
| **A. Core ML 全转换**（✅ 选定） | CLIP + RTMPose | 端侧可控，行为与源端一致，PetMatcher 保真 | 需 coremltools 转换 + 校验精度；包体积 +~45 MB（INT8 量化后） |
| B. Vision 高阶 API 为主 | 宠物识别 + 主体分割 | 零自带模型，集成最快，包体积小 | 宠物分类精度不可控；无法提取自定义特征做 PetMatcher，多宠物自动归属降级 |
| C. 混合（Vision 识别 + Core ML 特征） | 兼顾 | 灵活 | 复杂度最高，本质是 A 的渐进版 |

**最终决策**：采用 **方案 A**。CLIP vision encoder（只导 image_features，丢弃 12 层 attention）+ RTMPose-t 转 Core ML（INT8 量化），text embeddings（40 KB）直接复用。主体分割用 iOS 17+ `VNGenerateForegroundInstanceMask`（三方案一致）。预筛用 `VNClassifyImageRequest` / `VNRecognizeAnimalsRequest` 替代源端 CoreVisionKit。转换工具链 + 精度校验（cosine >0.999 / 分类一致率 >98% / 关键点 <2px）随 P2 前落地。

## 7. 风险登记

| 风险 | 等级 | 缓解 |
|---|---|---|
| CLIP 模型 Core ML 转换精度不达标 | 高 | P1 调研，准备 Vision 降级方案 |
| SwiftData 从零建模 + 迁移 16 版 schema 成本 | 中 | 不复刻历史迁移，按 V1.0 干净 schema 起步 |
| 拼豆 Swift 重写与 C++ 行为漂移 | 中 | 用源端 225 + parity 测试作黄金规格逐条翻译 |
| 完整重写无法分阶段上线 | 中 | 按 Tab 拆分里程碑，先相册+档案 MVP |
| iOS V1.0 新增功能（AI写真/回忆视频）无源端参照 | 中 | 单独立项，可能依赖云服务 |
| Windows 开发机无法跑 Xcode | 低 | 文档/规划在 Windows，编译/真机在 Mac |

## 8. 源端可复用资产

| 资产 | 复用方式 |
|---|---|
| 24,000 行测试 | 行为规格参照，翻译为 XCTest |
| 拼豆 225 用例 + ArkTS/C++ parity | 黄金规格，Swift 重写的验收基准 |
| DESIGN.md / ADR 0001-0006 | 架构决策背景，迁移时核对约束是否仍然成立 |
| DB schema v16 ER 图 | SwiftData 建模参照 |
| 主题 token（`AppTheme.ets`） | 翻译为 Asset Catalog + Color/Typography 扩展 |
