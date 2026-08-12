# MiLens iOS 设计说明

最后核对：2026-08-09（P1 核心可靠性收口 + 严格并发编译验证通过 + 并发遗留收口；1198+ XCTest 全绿）

> 本文描述目标 iOS 架构。源 HarmonyOS 架构见 `e:\HarmonyProjects\MiPhoto2\DESIGN.md`，迁移映射见 [MIGRATION_ASSESSMENT.md](MIGRATION_ASSESSMENT.md)，约束见 [AGENTS.md](AGENTS.md)。**视觉与 UI 设计规范见 [UI-DESIGN.md](UI-DESIGN.md)**（色彩/字体/间距/动效/页面视觉的唯一事实来源）。

## 1. 产品定位与范围

MiLens（咪Lens）iOS 版是宠物家庭的数字生命档案。基于 `docs/MiLens_iOS_V1.0_页面原型与交互流程设计稿.md`，V1.0 聚焦：发现宠物照片 → 建立档案 → 日常回忆 → 创作变现。

页面原型是早期叙事材料；当前 UI 执行规格以 [UI-DESIGN.md](UI-DESIGN.md) v2.0 为准。现有 SwiftUI 页面与 v1 token 不代表视觉完成度。

V1.0 范围：首页（今日/回忆/提醒）、宠物档案、创作（拼豆图纸 + 宠物卡片）、**完整图片编辑器**、扫描增强（质量评分 + 重复分组）、我的（订阅/主题/隐私）；适配 iPhone + iPad。范围详见 [ADR-0008](docs/adr/0008-v1-scope-decision.md)。
V1.0 不含：手表、健康管理、社区、云账号、商城、家庭局域网备份、AI 写真/回忆视频（详见评估报告 §5、[ADR-0008](docs/adr/0008-v1-scope-decision.md)）。

## 2. 技术栈

| 维度 | 选型 | 说明 |
|---|---|---|
| 最低版本 | iOS 17.0 | SwiftData、`@Observable`、NavigationStack 全套、Vision 主体分割 |
| 语言 | Swift 5.9+ | 宏、async/await、Sendable；MiLensKit 开启 `-strict-concurrency=complete`（M3，锁保护全局用 `nonisolated(unsafe)` + NSLock，保持 Swift 5 语言模式） |
| UI | SwiftUI | 为主，必要时 UIKit 互操作 |
| 持久化 | SwiftData | `@Model` + `ModelContainer` + `VersionedSchema` 迁移 |
| 状态管理 | `@Observable` 宏 | iOS 17 现代观察；跨视图共享走 `@Environment` |
| 导航 | NavigationStack + 路由枚举 | 类型安全，不复刻 URL 字符串 |
| AI 推理 | Core ML（CLIP + RTMPose 转换）+ Vision（分割） | 方案 A 全转换，见 [ADR-0007](docs/adr/0007-ios-ai-inference-route.md) |
| 订阅 | StoreKit 2 | `Product` / `Transaction` / `EntitlementTask` |
| 图片 | Photos / PhotosUI / ImageIO | PHPicker 选图、PHFetch 扫描、CGImageSource 解码 |
| 项目生成 | XcodeGen（`project.yml`） | 项目文件可声明、可版本控制，适配 Windows 规划 + Mac 编译 |

## 3. 工程结构

```
MiLens/                         # App target（@main、Views、App 入口）
├── App/                        # MiLensApp.swift（组合根）、路由枚举、EnvironmentKey
├── Views/                      # 页面（对应源端 pages/）
│   ├── Onboarding/             # 欢迎/权限/扫描/建档（源端 Index 引导）
│   ├── Home/                   # 首页 Tab
│   ├── Pets/                   # 宠物档案 Tab
│   ├── Create/                 # 创作 Tab（拼豆入口、卡片）
│   ├── Settings/               # 我的 Tab
│   ├── Gallery/                # 相册（源端 GalleryPage）
│   ├── PhotoView/              # 大图查看（源端 PhotoViewPage）
│   └── BeadPattern/            # 拼豆图纸（源端 BeadPatternPage）
├── Components/                 # 复用组件（对应源端 components/）
├── ViewModels/                 # @Observable 视图模型 + 纯决策（对应源端 viewmodels/）
├── Services/                   # 用例层（对应源端 services/）
│   ├── Scanning/               # 扫描/导入（PhotoScanner→ScanService）+ AnalysisExecutor 受限并发执行器
│   ├── Media/                  # 媒体生命周期（MediaLifecycleService：文件-记录事务/孤儿审计）
│   ├── AI/                     # AI 推理/匹配（AiService→PetRecognitionService 等）
│   ├── Export/                 # 导出/分享
│   ├── Notifications/          # 纪念/时光机提醒（NotifyService，对应源端 NotifyScheduler/TimeMachineService）
│   └── Platform/               # 平台适配 protocol + impl + mock（对应源端 adapters/）
├── Persistence/                # SwiftData @Model + Repository（对应源端 database/+repository/）
├── Theme/                      # Asset Catalog + 设计 token 扩展（对应源端 theme/）
├── Utilities/                  # 工具/日志/守卫（对应源端 utils/）
├── Resources/                  # Assets.xcassets / *.xcstrings（本地化）/ Info.plist
└── Tests/                      # XCTest 单元测试

MiLensKit/                      # 本地 Swift Package（对应源端 shared HSP）
├── Sources/MiLensKit/
│   ├── Bead/                   # 拼豆算法（生成/色板/渲染/色彩/评分/语义引导）
│   ├── ColorSpace/             # Lab/deltaE 纯逻辑
│   ├── Diagnostics/            # 错误分类/任务日志/诊断报表（AppErrorHandler/TaskLogger/DiagnosticsCollector，对应源端 utils）
│   └── Types/                  # 共享类型
└── Tests/MiLensKitTests/       # 拼豆 XCTest（对照源端 225 + parity）

project.yml                     # XcodeGen 声明
docs/                           # 设计稿/专题
```

> 源端 `editor/`（~30 文件）完整编辑器进 V1.0（[ADR-0008](docs/adr/0008-v1-scope-decision.md)），在 `Views/Editor/` + `ViewModels/Editor*` 落地，从相册/大图查看入口进入。

## 4. 分层与数据流

```
View ──> @Observable ViewModel ──> Service（用例）
                                   │
                                   ├──> Repository ──> SwiftData @Model
                                   ├──> Platform Protocol（Photos/Vision/Core ML/FileManager）
                                   └──> MiLensKit（拼豆算法）
```

- **View**：纯渲染 + 用户事件，持有 `@State`/`@Bindable`，不直接做 IO。
- **ViewModel**（`@Observable`）：页面状态机与决策。源端纯逻辑 ViewModel（`GalleryPageState`/`ScanFlowViewModel` 等）翻译为不可变 `struct` + 纯函数，XCTest 覆盖。
- **Service**：编排 IO + 异常处理 + 文案决策（对应源端 `GalleryActions` dataPort use case）。
- **Repository**：封装 SwiftData，业务层只见协议。
- **Platform Protocol**：系统框架抽象，mock 可注入（对应源端 `IFileService`/`IMediaAccess`/`IModelRunner`/`IVisionKit`）。

### 4.1 DI：Environment 值注入

源端 `AppServiceLocator` 三级所有权（应用级/任务级/页面级）在 iOS 映射为：

- **应用级**：`ModelContainer`、Repository、长生命周期 Service —— 在 `MiLensApp.init` 构造，通过 `.environment(...)` 注入。
- **任务级**：扫描/导出任务 —— Service 返回 `Task` 句柄，调用方在完成/取消时 `cancel()`（对应源端 `ScanSession`/`ExportSession`）。
- **页面级**：`@State` ViewModel —— 视图拥有，销毁时随视图回收；**统一经 `ViewModelFactory` 构造**（`MiLens/App/ViewModelFactory.swift`，随组合根注入 `\.viewModelFactory`）。

ViewModel 通过 `@Environment` 接收依赖协议，不引用具体实现或全局单例（沿用源端 P1.7/P1.9 DI 门禁精神）。

**分层收敛（ViewModelFactory）**：View 不直接通过 `@Environment` 持有 Repository/Service 来拼装 ViewModel（2026-08-09 前 GalleryView 持有 8 个依赖、EditorView 自带 in-memory 兜底逻辑、`sandboxDir` 拼装散落多处）。现改为：页面只依赖 `\.viewModelFactory`，由工厂组装 VM（`sandboxDir`/`editsDir` 拼装、编辑器 in-memory 兜底均收进工厂）；无 VM 的轻量页面（选照片/单照查看/档案详情）经工厂的 `photoList(limit:)`/`photo(id:)`/`pet(id:)`/`photosByPet(_:)`/`unassignedPhotos(limit:)`/`allPets()` 查询，View 层不再出现 Repository 类型。`GalleryViewModel`/`HomeViewModel`/`EditorViewModel`/`PetEditViewModel`/`BeadViewModel`/`PetProfileViewModel`/`TimelineViewModel` 的构造点全部收敛到工厂（2026-08-09 评审阻塞项：BeadPattern/Pets/Timeline/Create 四处 View 直连 Repository 已一并收敛）；VM 内部按既有规则通过窄协议声明依赖不变。非 Repository 的应用级状态（`\.proEntitlement` 权益、`\.notifyService` 提醒调度）仍由页面直接经环境值读取，与 Settings/Paywall 等页面一致。

## 5. 状态管理

| 源端 ArkUI | iOS SwiftUI（iOS 17+） |
|---|---|
| `@State` | `@State`（值类型）/ `@Observable`（引用类型） |
| `@Prop` / `@Link` | `@Bindable` + `@Binding` |
| `@Observed`/`@ObservedV2` | `@Observable` 宏 |
| `@Provide`/`@Consume` | `@Environment` / `@EnvironmentObject` |
| `@StorageLink` | `@AppStorage` |
| `@Watch` | `.onChange(of:)` |

⚠️ 陷阱：源端 `@State` 包装可变引用可直接改属性；SwiftUI `@State` 是值类型包装。复杂共享模型必须用 `@Observable`（见 [AGENTS.md](AGENTS.md) §4）。

## 6. 导航

`NavigationStack` + 类型安全路由枚举：

```swift
enum Route: Hashable {
    case photoView(photoID: UUID)
    case petProfile(petID: UUID)
    case beadPattern(photoID: UUID)
    case petEdit(petID: UUID)
}
```

源端 `router.pushUrl({ url: 'pages/Detail' })` 全部改写为 `NavigationLink(value: Route.xxx)` 或 `path.append(Route.xxx)`。Tab 根继续用 `TabView` 管理四个根页面和状态生命周期（对应源端 `MainPage` 的 `Tabs`）；系统 Tab Bar 隐藏后由 `MemoryOrbitTabBar` 通过 `safeAreaInset` 提供品牌化矢量导航。该组件只替换外观、点击入口与选中图标内部的短描边反馈，不自建路由栈，不给页面内容增加 Tab 切换位移或触感；选中轨道使用右深粗、左浅细的分层精确矢量弧，Reduce Motion 下直接呈现最终态。视觉规格见 [UI-DESIGN.md §5.4](UI-DESIGN.md#54-底部主导航memory-orbit)。

## 7. 数据设计

SwiftData 从 V1.0 干净 schema 起步（不复刻源端 16 版历史迁移）。参照源端 ER 模型：

- `Pet`（`@Model`）：name、species、featureData、createdAt、photoCount
- `Photo`（`@Model`）：uri、originalURI、thumbnailPath、phash、sharpness、qualityScore、duplicateOf、isBest、`@Relationship` to Pet（embeddingData 后置 V1.x）
- `PetEvent`（`@Model`）：eventType、eventDate、`@Relationship` to Pet

生命档案增强设计见 [docs/Life-Archive-Design.md](docs/Life-Archive-Design.md)：在不破坏现有生日/领养提醒语义的前提下，后续为 `PetEvent` 增加用户记录正文、来源类型、置顶/档案起点、日期范围和代表照片/关联照片能力；作品记录通过来源照片或原始记忆回链。schema 变更必须按现有 VersionedSchema/迁移规则执行，禁止直接把系统推导事件伪装成用户记录。

变更须同步：`@Model` + `VersionedSchema`/`SchemaMigrationPlan` + Repository + 测试。

**Schema 迁移策略**（正式决策）：产品尚未发布，V1 即首发基线（含 `originalURI` 唯一约束）；P0 修复前创建的开发库不支持自动升级（SwiftData 对「新增唯一约束」无 lightweight migration），首发前删除旧开发库重装。首发后任何 schema 变更必须递增版本号并追加 MigrationStage，禁止改动模型后保持版本号不变。详见 [SchemaVersion.swift](MiLens/Persistence/SchemaVersion.swift) 文件头。

扫描/导入边界（沿用源端硬约束）：扫描只筛选不入库；入库唯一路径是用户主动「导入」。`MediaMonitor` 等价物（后台检测新增）不自动入库。

**去重**：以 `Photo.originalURI`（Photos localIdentifier，稳定不变）为唯一键，`@Attribute(.unique)` 约束 + 仓储 `getPhotoByOriginalURI`/`getAllOriginalURIs` 查询；`uri` 是沙盒副本路径（每次导入变化，UUID 文件名），不参与去重。同一批次内重复 identifier 由 ImportService 的 `seenInBatch` 去重。

**增量扫描**：`ScanCursorStore`（UserDefaults）持久化上次成功扫描开始时刻作为游标，下次增量扫描以此为过滤基准（无游标 = 全量）。iOS 无公开「加入相册时间」API，以 `creationDate` 近似 `dateAdded`——老照片（早于游标）导入相册不会被增量发现，首次使用建议全量扫描。游标只在扫描**完整完成**（`ScanResult.completedSuccessfully`：未取消且无错误）时保存——仓储读取失败、计数失败或流式遍历中断时返回 `error` 状态，上层不保存游标，避免下次增量扫描跳过本次未扫到的照片。

**文件-记录事务性**：`MediaLifecycleService` 统一治理导入/编辑/删除的文件-记录一致性——`commitImport`/`commitImportBatch`（DB 失败回滚已写文件；批量入库一次 save 多张，`ImportService` 攒批 32 张 flush，尾批含取消中断不丢文件）、`saveEditedPhoto`（失败删新文件，成功清理旧版本文件）、`deletePhoto`（删除联动媒体文件）、`auditOrphans`（启动后延迟 3s 以 utility 优先级后台执行孤儿审计，文件遍历/删除在 `Task.detached` 内，不占启动关键路径）。DB 是事实源，媒体文件是派生资源。

**保存事务封装**：仓储层所有写路径统一经 `ModelContext.saveOrRollback()` 提交（[ModelContext+Transaction.swift](MiLens/Persistence/ModelContext+Transaction.swift)）——`context.save()` 失败不会自动回滚，失败的 insert/update/delete 会残留在 pending changes 中污染同一上下文的后续保存（如唯一约束冲突后下一次 save 继续失败，导入/编辑链路被卡死）；`saveOrRollback` 失败即 `rollback()` 并重抛，保证上下文回到调用前干净状态。编辑保存失败时 `MediaLifecycleService.saveEditedPhoto` 同时恢复记录全部旧属性（含 `category`，与「完整回滚」注释一致）。

**媒体备份策略**：`Documents/MiPhotos` 下按可重建性分区 + 用户可控（任务 3）：
- `Documents/MiPhotos/Edits/`（编辑产物，`ScanConfig.editsDirName`）：编辑成品只存沙盒且**不**同步回系统相册、无重建步骤（DB 只覆盖 URI），不可重建 —— **始终允许备份**。`EditorSaveService` 保存到 Edits 子目录（2026-08-09 评审阻塞项修复：此前全部排除备份，设备恢复后会出现「DB 记录仍在、图片文件缺失」）。
- `Documents/MiPhotos/`（导入副本）：默认**排除** iCloud/iTunes 备份（`isExcludedFromBackup`，原图在系统相册可重建，节省云空间）。用户可在设置页切换为 `dataSafe` 模式——`PhotoBackupMode` 枚举 + `@AppStorage("photoBackupMode")` + `IOSFileStorage` 闭包延迟求值；切换后 `reapplyBackupExclusion` 立即遍历已有文件重标记，避免「系统相册已清/换 Apple ID」时导入副本随系统备份恢复时缺失。
App 不会主动上传照片；编辑产物可能随用户启用的系统备份保存；离线备份导出（`.milensbackup`）始终包含全部照片（含导入副本），不受此设置影响。
`MediaLifecycleService.auditOrphans` 与 `AppDependencies.destroyPersistentStore` 提示文案均覆盖两个目录。

**离线备份/恢复**（[ADR-0010 §8](docs/adr/0010-commercialization-and-emotion-triggers.md)，2026-08-12 实施）：`BackupService` 将照片原图 + 编辑产物 + 完整元数据（Pet/Photo/PetEvent 的 Codable 快照）打包为 `.milensbackup`（ZIP，store 模式）。ZIP 能力由 MiLensKit `ZIPArchive`（纯 Swift，无第三方依赖）提供——决策不引入 ZIPFoundation 等三方库，保持项目完整 Swift 重写原则；store 模式对已压缩的 JPEG 几乎无体积惩罚且实现极简。导出经 ShareSheet 交给用户选择存储位置（Files/iCloud Drive/AirDrop），不联网；恢复经 DocumentPicker 选择备份文件，校验 `manifest.schemaVersion` 后合并导入（同 ID 跳过，不覆盖现有数据）。导出为 Pro 专属，恢复对所有用户开放。这是换机/丢机/删 App 场景下数据不丢失的**主路径**——系统 iCloud 备份是被动兜底，离线备份是用户主动的跨设备迁移与归档手段，不依赖用户是否开启系统备份。

**像素计算移出主线程**：CPU 密集段（JPEG 解码、Laplacian、pHash、VNRequest、CLIP 预处理、O(n²) 重复分组）统一经 `AnalysisExecutor`（actor，utility 优先级，受限并发 `maxConcurrent = 2`，内部 in-flight 计数 + continuation 队列）执行，只把 Sendable 结果回 MainActor 写库/更新 UI。`ScanService` 两阶段：阶段 1（MainActor 轻量）过滤已导入/过旧照片收集候选；阶段 2 候选分批（每批 `maxConcurrent` 个）后台分析，进度回调次数保持按照片数。扫描阶段对已注册宠物做只读预匹配（复用 CLIP 同一次推理的 embedding + 14 维颜色签名，`matchedCount`/`matchedUris` 真实反映归属判定），真正归属写入仍在导入时（`ImportService` → `assignPhoto`）——扫描不写库的硬约束不变。

**启动恢复**：`ModelContainer` 构造失败不再 `try!` 崩溃——`MiLensApp` 用 `@State` 启动状态机（正常容器 / `DatabaseRecoveryView`），失败时可查看可读错误、导出诊断（Documents/Diagnostics/ 日志文件）、重试，或重建本地数据（二次确认，清除相册记录不动系统相册原图）。依赖组装收口到 `AppDependencies.make(isTesting:)` 工厂，测试环境保持 in-memory 快速路径。

## 8. 拼豆子系统（MiLensKit）

源端 `shared` 的 ArkTS + C++ 双路径在 iOS 合并为纯 Swift 实现：

```
输入图像 → 裁切/缩放/预处理 → [主体/pose 保护] → 色板+MARD → Lab 映射+抖动
→ 连通去噪/特征保护/轮廓 → TriScore 评分 → 网格渲染/A4 导出
```

- 色彩空间（`rgbToLab`/`deltaE76`/`findNearestBeadColor`）、量化、抖动、去噪、风格化草稿全部纯 Swift，XCTest 完整覆盖。
- 源端 C++ Native 不可用回退 ArkTS 的双路径逻辑统一为单一 Swift 实现，去掉降级分支。
- MARD 色卡源变化时同步更新（对应源端 `tools/sync_mard_palette.py` 的等价校验）。
- 黄金规格：源端 225 用例 + ArkTS/C++ parity 测试逐条翻译为 `MiLensKitTests`。

## 9. 平台适配层（Services/Platform）

对应源端 `adapters/`，用 Swift protocol 隔离系统框架：

| 协议 | 系统 | 源端对应 |
|---|---|---|
| `PhotoLibraryAccess` | Photos / PhotosUI | `IMediaAccess` |
| `FileStorage` | FileManager | `IFileService` |
| `VisionService` | Vision（分类/主体分割） | `IVisionKit` |
| `NotificationPosting` | UserNotifications（UNUserNotificationCenter） | `NotifyScheduler`/`WorkScheduler` 的通知发布面 |
| `InferenceEngine` | Core ML（CLIP + RTMPose `.mlmodelc`） | `IModelRunner`（定案见 [ADR-0007](docs/adr/0007-ios-ai-inference-route.md)） |

真实实现与 mock 分离，业务/ViewModel 只依赖协议，测试注入 mock（对应源端 `FakeMediaAccess` 等）。

**通知调度语义**：`NotificationPosting` 提供 `schedule(title:body:identifier:dateComponents:repeats:)`（`UNCalendarNotificationTrigger` 真调度）而非一次性 post。`NotifyService.rescheduleAllReminders()` 幂等（先 `removeAllNotifications` 再全量调度）：Pet 生日/领养日 → 年度重复通知（月日组件 + 09:00，identifier `anniversary-<petID>-<kind>`）；时光机历史同日照片非空 → 每日 09:00（identifier `tm-daily`，内容由 `TimeMachineLogic` 调度时选定）。设置页「纪念提醒」开关（`@AppStorage`，默认关闭）是唯一授权入口：打开 → `requestAuthorization()` 成功才重调度，拒绝回弹；关闭 → 撤销全部。宠物编辑/删除走 `updateReminders`/`removeReminders` 局部更新。

### 9.1 并发纪律（SWIFT_STRICT_CONCURRENCY=complete）

2026-08-09 起 `project.yml` 开启 `SWIFT_STRICT_CONCURRENCY=complete`（Swift 5 语言模式下的完整并发诊断），后续新增代码按 complete 标准编写：

- 页面 ViewModel 一律 `@MainActor`；跨隔离边界（`Task.detached`、`async let`、协议值传递）只发送 `Sendable` 值，CPU 密集计算以捕获值的方式传入 detached 闭包，不捕获非 Sendable 的 `self`/View struct。
- 平台适配层与 mock 的 `@unchecked Sendable` 声明必须附理由注释（内部锁保护 / 只在 MainActor 调用方访问等），禁止无说明地抑制检查。
- 长监听任务（如 `ProEntitlementStore` 的订阅流）用 actor 隔离的注册表 + `[weak self]`，不留「静态容器 → Task → self」保活环。
- 并发遗留收口：`BeadViewModel` 4 处 `Task.detached`（生成/导出/分享/PDF）已收敛——均以捕获 `Sendable` 局部值（`renderer`/`pattern`/`photoData`/`opts`）的方式传参，调用全局生成/渲染函数，不捕获非 Sendable 的 `self`，complete 编译通过。仅剩 `HomeView` 2 处 `static let DateFormatter` 在 Swift 5.9 complete 下不触发诊断（SE-0412 于 5.10 生效），列为 Swift 6 语言模式迁移前置项（跟踪见 PLAN.md）。

## 10. 已知限制

- AI 推理框架已定案：方案 A 全转换（CLIP + RTMPose → Core ML，INT8 量化）+ Vision 原生分割。详见 [ADR-0007](docs/adr/0007-ios-ai-inference-route.md)。
- 质量评分（Laplacian 方差清晰度）+ 重复分组（pHash 视觉哈希）**已实现**（P2，[ADR-0008](docs/adr/0008-v1-scope-decision.md)）；完整图片编辑器**已实现**（P4，裁切/旋转/翻转/调色/锐化/文字/抠图）。CLIP embedding 相似度增强、RTMPose 精度需 iPhone 真机验证（模型已转换，推理质量待实测）。
- 家庭局域网备份后置 V1.x（离线备份接口已预留：ADR-0010 §8，`BackupService` 协议 + ZIP 打包 + ShareSheet，不联网）；AI 写真/回忆视频 V1.0 不做（无源端参照，需独立产品+技术方案），仅 V1.x 重新评估。
- 商业化强化方案见 [ADR-0010](docs/adr/0010-commercialization-and-emotion-triggers.md)：照片配额（含降级后「可见但锁定」场景 §10.1.1）、导出水印、买断降价、分享增强、卡片多模板、时间线导出已实现；离线备份、相簿模式、实体打印、编辑器装饰接口已预留。
- SwiftData schema 从零设计，与源端数据无直接迁移路径（两平台数据不互通）。
- 编译与单元测试已在本机 macOS 验证通过（严格并发 `complete` 下 BUILD SUCCEEDED，MiLensKit 594 + App 604 + UI 2 全绿）；真机调试、模拟器 UI 人工验证、Instruments 性能分析仍需 Mac + iPhone 真机。
