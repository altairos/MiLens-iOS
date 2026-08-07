# MiLens iOS 设计说明

最后核对：2026-08-07（迁移准备阶段，P0 harness 搭建中）

> 本文描述目标 iOS 架构。源 HarmonyOS 架构见 `e:\HarmonyProjects\MiPhoto2\DESIGN.md`，迁移映射见 [MIGRATION_ASSESSMENT.md](MIGRATION_ASSESSMENT.md)，约束见 [AGENTS.md](AGENTS.md)。**视觉与 UI 设计规范见 [UI-DESIGN.md](UI-DESIGN.md)**（色彩/字体/间距/动效/页面视觉的唯一事实来源）。

## 1. 产品定位与范围

MiLens（咪Lens）iOS 版是宠物家庭的数字生命档案。基于 `docs/MiLens_iOS_V1.0_页面原型与交互流程设计稿.md`，V1.0 聚焦：发现宠物照片 → 建立档案 → 日常回忆 → 创作变现。

V1.0 范围：首页（今日/回忆/提醒）、宠物档案、创作（拼豆图纸 + 宠物卡片）、我的（订阅/主题/隐私）。
V1.0 不含：手表、健康管理、社区、云账号、商城（详见评估报告 §5）。

## 2. 技术栈

| 维度 | 选型 | 说明 |
|---|---|---|
| 最低版本 | iOS 17.0 | SwiftData、`@Observable`、NavigationStack 全套、Vision 主体分割 |
| 语言 | Swift 5.9+ | 宏、async/await、Sendable |
| UI | SwiftUI | 为主，必要时 UIKit 互操作 |
| 持久化 | SwiftData | `@Model` + `ModelContainer` + `VersionedSchema` 迁移 |
| 状态管理 | `@Observable` 宏 | iOS 17 现代观察；跨视图共享走 `@Environment` |
| 导航 | NavigationStack + 路由枚举 | 类型安全，不复刻 URL 字符串 |
| AI 推理 | Vision（首选）+ Core ML（待定） | 见评估报告 §6 |
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
│   ├── Scanning/               # 扫描/导入（PhotoScanner→ScanService）
│   ├── AI/                     # AI 推理/匹配（AiService→PetRecognitionService 等）
│   ├── Export/                 # 导出/分享
│   └── Platform/               # 平台适配 protocol + impl + mock（对应源端 adapters/）
├── Persistence/                # SwiftData @Model + Repository（对应源端 database/+repository/）
├── Theme/                      # Asset Catalog + 设计 token 扩展（对应源端 theme/）
├── Utilities/                  # 工具/日志/守卫（对应源端 utils/）
├── Resources/                  # Assets.xcassets / .lproj / Info.plist
└── Tests/                      # XCTest 单元测试

MiLensKit/                      # 本地 Swift Package（对应源端 shared HSP）
├── Sources/MiLensKit/
│   ├── Bead/                   # 拼豆算法（生成/色板/渲染/色彩/评分/语义引导）
│   ├── ColorSpace/             # Lab/deltaE 纯逻辑
│   ├── Diagnostics/            # 错误分类/任务日志（对应源端 utils）
│   └── Types/                  # 共享类型
└── Tests/MiLensKitTests/       # 拼豆 XCTest（对照源端 225 + parity）

project.yml                     # XcodeGen 声明
docs/                           # 设计稿/专题
```

> 源端 `editor/`（30 文件）的完整编辑器在 V1.0 简化，按需后置，暂不单独建 `Features/Editor/`。

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
- **页面级**：`@State` ViewModel —— 视图拥有，销毁时随视图回收。

ViewModel 通过 `@Environment` 接收依赖协议，不引用具体实现或全局单例（沿用源端 P1.7/P1.9 DI 门禁精神）。

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

源端 `router.pushUrl({ url: 'pages/Detail' })` 全部改写为 `NavigationLink(value: Route.xxx)` 或 `path.append(Route.xxx)`。Tab 根用 `TabView`（对应源端 `MainPage` 的 `Tabs`）。

## 7. 数据设计

SwiftData 从 V1.0 干净 schema 起步（不复刻源端 16 版历史迁移）。参照源端 ER 模型：

- `Pet`（`@Model`）：name、species、featureData、createdAt、photoCount
- `Photo`（`@Model`）：uri、originalURI、thumbnailPath、embeddingData、qualityScore、duplicateOf、`@Relationship` to Pet
- `PetEvent`（`@Model`）：eventType、eventDate、`@Relationship` to Pet

变更须同步：`@Model` + `VersionedSchema`/`SchemaMigrationPlan` + Repository + 测试。

扫描/导入边界（沿用源端硬约束）：扫描只筛选不入库；入库唯一路径是用户主动「导入」。`MediaMonitor` 等价物（后台检测新增）不自动入库。

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
| `InferenceEngine`（待定） | Core ML | `IModelRunner` |

真实实现与 mock 分离，业务/ViewModel 只依赖协议，测试注入 mock（对应源端 `FakeMediaAccess` 等）。

## 10. 已知限制

- AI 推理框架（Vision vs Core ML）待 P1 调研定案（见评估报告 §6）。
- 完整编辑器、家庭局域网备份、质量评分/重复分组后置到 V1.x。
- iOS V1.0 新增的 AI 写真/回忆视频无源端参照，需独立产品+技术方案。
- SwiftData schema 从零设计，与源端数据无直接迁移路径（两平台数据不互通）。
- 当前在 Windows 搭建文档/harness，编译与真机验证需 Mac + Xcode。
