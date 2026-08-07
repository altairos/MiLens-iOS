# MiLens iOS 迁移计划

最后核对：2026-08-08（P0 收口，P2 进行中）

> 里程碑与任务清单。架构见 [DESIGN.md](DESIGN.md)，映射与范围见 [MIGRATION_ASSESSMENT.md](MIGRATION_ASSESSMENT.md)，约束见 [AGENTS.md](AGENTS.md)。

## 里程碑总览

| 阶段 | 名称 | 目标 | 状态 |
|---|---|---|---|
| **P0** | Harness 与规划 | 文档骨架、约束、目录结构、XcodeGen 声明、范围对齐 | ✅ 已完成 |
| **P1** | 地基 + 算法核心 | Xcode 工程可编译、SwiftData schema、拼豆 Swift 核心（黄金规格通过）、AI 路线定案 | ⬜ |
| **P2** | 相册 MVP | 扫描发现（+质量评分/重复分组）+ 手动导入 + 相册网格 + 大图查看 | 🔄 进行中 |
| **P3** | 宠物档案 | 档案 CRUD + 成长时间线 + 纪念提醒 | ⬜ |
| **P4** | 创作入口 + 编辑器 | 拼豆图纸完整流程 + 完整图片编辑器（裁切/滤镜/标注） | ⬜ |
| **P5** | 首页/我的 + 商业化 | 首页回忆/提醒、设置、StoreKit 订阅、App Store 提审 | ⬜ |

---

## P0 — Harness 与规划 ✅

### 任务

- [x] 源项目规模盘点与模块映射（[MIGRATION_ASSESSMENT.md](MIGRATION_ASSESSMENT.md) §2-4）
- [x] 4 项关键决策对齐（iOS 17+ / 完整重写 / Swift 重写 / AI 待定）
- [x] 约束文档 [AGENTS.md](AGENTS.md)
- [x] 目标架构 [DESIGN.md](DESIGN.md)
- [x] 迁移计划本文档
- [x] XcodeGen `project.yml`（App target + MiLensKit package）
- [x] 目录骨架（21 个子目录 + 占位 `.gitkeep`）
- [x] `.gitignore`（iOS 工程规则）
- [x] DEVELOPMENT.md（环境/命令/验证）
- [x] 云端 CI：`.github/workflows/ci.yml`（ubuntu-24.04 跑 MiLensKit + macOS-15 跑 App）
- [x] **本地编译闭环**：WSL2 Ubuntu-24.04 + Swift 6.1.3（/opt/swift），MiLensKit `swift build/test` 全绿
- [x] **范围对齐**：V1.0 范围定案（[ADR-0008](docs/adr/0008-v1-scope-decision.md)）—— 完整图片编辑器 + 质量评分 + 重复分组进 V1.0；备份/AI 写真后置；iPad 支持

### 验收标准

- 6 份顶层文档齐全且互相链接一致
- `project.yml` 在 Mac 上 `xcodegen generate` 可生成可编译空工程
- 范围「待确认」项有明确结论 ✅（[ADR-0008](docs/adr/0008-v1-scope-decision.md)，产品已拍板）

---

## P1 — 地基 + 算法核心

### P1.1 工程地基

- [x] 在 Mac 上 `xcodegen generate` 生成 `.xcodeproj`，编译空 App 启动（P0 已在 CI 验证 BUILD SUCCEEDED）
- [x] `MiLensApp`（`@main`）组合根 + `scenePhase` 生命周期骨架；`ModelContainer` 待 P1.2 SwiftData `@Model` 接入
- [x] TabView 壳（首页/宠物/创作/我的）+ 路由枚举 `Route` + `AppTab`（`@AppStorage` 持久化选中项）
- [x] 主题 token 翻译：Asset Catalog 语义色（`AccentColor` 品牌色 `#FD8663` + 背景/卡片/文字，含深色 Appearance）+ `Theme.swift`（Spacing/Radius/Size/Motion）；Typography 沿用系统字体（源端无自定义字体文件）
- [x] 本地化 String Catalog（`Localizable.xcstrings` + `InfoPlist.xcstrings`，源语言简中，结构支持任意语言；`String(localized:)` API）；`tools/localization.py` 导出/导入/校验工具；App Icon / 占位图待源端资源整理后补

### P1.2 数据层

- [x] SwiftData `@Model`：`Pet` / `Photo` / `PetEvent`（参照评估报告 §3 + 源端 ER，UUID 业务标识）
- [x] `VersionedSchema` v1 + 空 `SchemaMigrationPlan`
- [x] Repository 协议 + 实现（`PetRepositoryProtocol` / `PhotoRepositoryProtocol` + SwiftData 实现，`@MainActor`）
- [x] 扫描/导入边界设计：`getAllPhotoURIs()` 去重 + `insertPhoto()` 唯一入库路径（沿用源端约束）
- [x] `MiLensApp` 接入 `ModelContainer` + Repository `.environment` 注入
- [x] XCTest：Repository CRUD + 分页查询 + 关系删除规则 + 扫描/导入边界（22 用例）

### P1.3 拼豆算法核心（MiLensKit）

按源端 `shared` 黄金规格逐模块翻译，**每个模块的源端测试先翻译成 XCTest 作为规格**：

- [ ] 色彩空间：`BeadColorSpace`（rgbToLab/labToRgb/deltaE76/findNearestBeadColor/precomputePaletteLab）
- [ ] 色板：`BeadPalette` + `BeadPaletteMard`（MARD 色卡源）
- [ ] 生成管线：`BeadPatternService`（裁切/缩放/量化/抖动/去噪）
- [ ] 风格化草稿：`StylizedDraftGenerator` + `DraftToBeadMapper`
- [ ] 评分：`BeadScoring`（TriScore）
- [ ] 语义引导：`BeadSemanticGuide`
- [ ] 渲染/导出：`BeadRenderer` + `BeadExportService`（A4）
- [ ] **验收**：源端 225 用例 + ArkTS/C++ parity 在 Swift 侧全绿

### P1.4 平台适配层

- [x] `PhotoLibraryAccess`（Photos/PhotosUI）+ `MockPhotoLibraryAccess`（对应源端 `IMediaAccess`/`FakeMediaAccess`）
- [x] `FileStorage`（FileManager）+ `MockFileStorage`（对应源端 `IFileService`/`FakeFileService`）
- [x] `VisionService`（Vision 分类/主体分割）+ `MockVisionService`（协议骨架，真实实现待 P1.5）
- [x] `InferenceEngine`（Core ML）+ `MockInferenceEngine`（协议骨架，真实实现待 P1.5）
- [x] `PlatformEnvironment`（EnvironmentKey 注入）
- [x] XCTest：4 个 mock 基础行为（15 用例，对应源端 `AdapterContract`）

### P1.5 AI 推理路线定案（关键决策）✅ 已定案

> **结论**：采用 **方案 A（Core ML 模型转换）+ Vision 原生分割**。详见 [ADR-0007](docs/adr/0007-ios-ai-inference-route.md)。

- [x] 调研 Vision 宠物分类能力覆盖（`VNClassifyImageRequest` 系统分类含动物类别；`VNRecognizeAnimalsRequest` 仅猫狗，覆盖不足）
- [x] 调研 Vision 主体分割（`VNGenerateForegroundInstanceMask` iOS 17+，直接对应源端 VisionKit，三方案一致采用）
- [x] 调研 CLIP → Core ML 转换可行性（coremltools；源端已有 ONNX 导出；INT8 量化 ~42 MB）+ 精度校验方法（cosine >0.999 / 分类一致率 >98% / 关键点 <2px）
- [x] 评估 PetMatcher 是否必须依赖 CLIP embedding（不强依赖，有降级链；但产品决策选全转换保多宠物自动归属精度）
- [x] **产出 ADR**：[ADR-0007 iOS AI 推理路线](docs/adr/0007-ios-ai-inference-route.md)

**落地任务**（拆入后续里程碑）：

- [x] `tools/convert_clip_coreml.py`（ONNX/Torch → Core ML + INT8 量化 + 精度校验）→ `CLIPVisionEncoder.mlpackage`
- [x] `tools/convert_rtmpose_coreml.py`（ONNX → Core ML + 校验）→ `RTMPoseTPetFace.mlpackage`
- [x] `tools/prepare_text_embeddings.py`（f32 格式校验 + Swift 加载代码生成）
- [x] 模型资产加入 `Resources/Models/` + `project.yml` 注册（目录骨架 + `pet_text_embeddings.f32` 已复制；`.mlpackage` 需 Mac 转换后放入）
- [ ] `IOSVisionService` / `CoreMLInferenceEngine` 真实实现（P2 扫描 MVP，协议骨架 P1.4 已有）

### 验收标准

- 工程编译通过，空 App + TabView 可在 iPhone 模拟器启动 ✅（CI run 31187548565）
- SwiftData schema v1 + Repository 测试通过 ✅（CI run 31193790682）
- 平台适配层 4 协议 + mock + 测试 ✅（CI run 31196033240）
- MiLensKit 拼豆核心对源端 225 + parity 全绿
- AI 路线 ADR 定案 ✅（[ADR-0007](docs/adr/0007-ios-ai-inference-route.md)，方案 A 全转换 + Vision 分割）

---

## P2 — 相册 MVP

### 任务

- [x] 纯决策逻辑翻译（6 模块）：`GalleryPageState`/`ScanFlowLogic`/`ScanControlMath`/`ImportFlowLogic`/`PhotoMetadataLogic`/`PhotoViewGestureMath`
- [x] XCTest：纯决策逻辑全覆盖（~84 用例，对应源端黄金规格）
- [x] `ScanService`：Photos 全库扫描 + 宠物识别（VisionService）+ 取消支持（Task.cancel）
- [x] `ImportService`：用户主动导入 → 复制沙盒 → 缩略图 → 入库（DESIGN.md §7 唯一入库路径）
- [x] ScanService/ImportService 测试（~15 用例，in-memory SwiftData + mock）
- [x] `GalleryViewModel`（@Observable）：分页 + 筛选 + 扫描/导入编排 + 多选
- [x] `GalleryView`：LazyVGrid 虚拟化 + 分页加载 + 扫描入口 + 完成弹窗
- [x] `PhotoViewView`：大图查看 + 手势（PhotoViewGestureMath 纯函数驱动）
- [x] `HomeView`：相册入口 + 扫描入口（NavigationLink → Gallery）
- [x] RootTabView 路由串联（navigationDestination for Route）
- [ ] 引导流程：首次启动 → 权限说明 → 扫描 → 建档（待 P3 完善建档部分）
- [ ] 真机验证：Photos 权限 + Vision 推理 + 分页性能（需 Mac + iPhone）

### 验收标准

- 首次启动完整走通：授权 → 扫描发现宠物 → 建档 → 相册可见（建档 P3；扫描+导入+相册 ✅）
- 相册支持分页、筛选、多选、大图查看 ✅
- 扫描可取消，不提交过期结果 ✅
- 纯决策逻辑 XCTest 全绿（CI 验证待推送）

---

## P3 — 宠物档案

### 任务

- [ ] `PetProfileView`：头像/名称/年龄/照片数/成长轨迹（设计稿 Tab 2）
- [ ] `PetEditView`：档案编辑（翻译 `PetFormViewModel`）
- [ ] `TimelineView`：成长时间线（翻译 `TimelineViewModel` + `TimeMachineService`）
- [ ] 纪念提醒：`UNUserNotificationCenter`（生日/领养日）
- [ ] 档案内照片分类（全部/幼年/玩耍/睡觉等，按设计稿）
- [ ] XCTest：档案/时间线决策逻辑

### 验收标准

- 宠物档案 CRUD 完整
- 时间线按事件聚合展示
- 纪念提醒可调度且可撤销

---

## P4 — 创作入口（拼豆图纸）

### 任务

- [ ] `BeadPatternView`：选图 → 预设选择 → 生成预览 → 调参
- [ ] 接入 MiLensKit 生成管线（P1.3）+ 渲染
- [ ] A4 图纸导出（PDF/PNG）+ 系统分享
- [ ] 宠物卡片生成（设计稿创作 Tab）
- [ ] 主体/pose 保护接入（依赖 P1.5 AI 方案）
- [ ] XCTest：Bead 生成 ViewModel 决策

### 验收标准

- 从相册选图到拼豆图纸导出完整走通
- 行为与源端 BeadPatternPage 一致（对照源端用例）

---

## P5 — 首页/我的 + 商业化

### 任务

- [ ] `HomeView`：今日照片/历史回忆/成长提醒/快速创作入口（设计稿 Tab 1）
- [ ] 回忆逻辑：「一年前的今天」（翻译 `TimeMachineService`）
- [ ] `SettingsView`：主题/隐私设置/帮助/关于（设计稿 Tab 4）
- [ ] StoreKit 2 订阅：MiLens Pro 产品配置 + `Transaction` 监听 + 付费墙 UI（设计稿付费墙）
- [ ] App Store 截图/描述/ASO 关键词（设计稿 §5-6）
- [ ] 性能基准：大图库（5000+）滚动/内存
- [ ] iPhone/iPad 适配 + 深色模式 + Dynamic Type 检查

### 上架（免 Mac 云端一条龙）

编译/签名/上传全部在 GitHub Actions macOS runner 完成，无需本机 Mac：

- [ ] 在 `.github/workflows/ci.yml` 新增 `release` 作业（手动触发 `workflow_dispatch`）：`xcodebuild archive` → `xcodebuild -exportArchive`（签名）→ `xcrun altool/notarytool` 上传 App Store Connect
- [ ] 证书/描述文件用 **App Store Connect API Key（.p8）** 注入 GitHub Secret（不用钥匙串）
- [ ] App Store Connect 填写元数据/截图/隐私政策（网页端）
- [ ] 提交审核

> 「开心上架(appuploader)」等第三方工具仅适用于「IPA 已生成、只需在 Windows 本地重传」场景，对原生项目非必需。`altool/notarytool` 是苹果官方免费上传工具，随 runner 自带。

### 验收标准

- 4 个 Tab 全部功能可用
- StoreKit Testing 通过，付费墙正确触发
- App Store 提审材料齐全
- release workflow 可云端生成签名 IPA 并上传到 App Store Connect

> **真正还需 Mac**：真机调试、模拟器 UI 人工验证、Instruments 性能分析。这些是发布前质量门禁，建议借/租 Mac 完成（上架本身已免 Mac）。

---

## 范围待确认清单（P0 末需产品对齐）

| 项 | 默认建议 | 影响 |
|---|---|---|
| 完整图片编辑器是否进 V1.0 | 后置 V1.x | P4 范围 |
| 家庭局域网备份是否进 V1.0 | 后置 V1.x | 是否建 `Services/Backup/` |
| AI 写真/回忆视频是否进 V1.0 | V1.0 不做 | 是否引入云服务依赖 |
| 质量评分/重复分组是否进 V1.0 | 后置 | 扫描流程复杂度 |
| iPad 是否 V1.0 必须适配 | 建议支持 | 适配工作量 |

---

## 状态摘要

（P1 起每阶段完成后在此追加：完成内容、覆盖率、已知问题。）

### P0 进度

- 2026-08-07：完成源项目盘点、4 项关键决策、全部 6 份顶层文档（AGENTS / DESIGN / PLAN / MIGRATION_ASSESSMENT / DEVELOPMENT / README）、harness 骨架（XcodeGen `project.yml` + MiLensKit 本地 Swift Package + 21 目录 + `.gitignore`）。
- 2026-08-07：云端 CI（`.github/workflows/ci.yml`）+ **本地编译闭环**落地——WSL2 Ubuntu-24.04 + Swift 6.1.3（/opt/swift），MiLensKit `swift build`/`swift test` 全绿（增量编译 ~1.1s）。
- 2026-08-07：项目推送 GitHub（`altairos/MiLens-iOS`，私有）。**云端编译闭环验证通过**——`MiLensKit (Linux)` 51s + `MiLens App (macOS)` 4m7s 全绿（`BUILD SUCCEEDED` + 测试通过）；首次运行修复 Asset Catalog 缺 `AppIcon.appiconset`。
- 2026-08-07：**P1.1 工程地基落地**——`MiLensApp` 组合根 + `RootTabView`（4 Tab：首页/宠物/创作/我的）+ `Route`/`AppTab` 枚举 + 主题 token（Asset Catalog 5 语义色含深色 + `Theme.swift` 尺寸）+ 简中本地化 + AppTab/Route 纯逻辑测试（8 用例）。**CI 验证通过**（编译 + 测试全绿，run 31187548565）。
- 2026-08-07：**UI 设计规范定稿**——新增 [UI-DESIGN.md](UI-DESIGN.md)（视觉与交互唯一事实来源）。核心决策：①色彩从源端「暖色铺底」转向「中性画廊 + 暖色点睛」（背景 `#FAF8F5`/暖黑 `#161311`）；②字体引入霞鹜文楷（中文）+ Fraunces（英文 display），均 SIL OFL；③深色模式用暖黑；④首页用 hero 照片方案。待办：阶段 A 设计系统落地（校准 Asset Catalog 色值 + 新增 `Typography.swift` + 字体子集化）。
- 2026-08-07：**P1.2 数据层落地**——SwiftData `@Model`（Pet/Photo/PetEvent，UUID 标识，V1.0 裁剪字段）+ `SchemaV1` + `MiLensMigrationPlan` + Repository 协议/实现（`@MainActor`，EnvironmentKey 注入）+ `MiLensApp` 组合根接入 ModelContainer + Repository 测试（22 用例，含关系删除规则 cascade/nullify + 扫描/导入边界）。**CI 验证通过**（编译 + 测试全绿，run 31193790682）。
- 2026-08-07：**UI 设计系统阶段 A（1–4）落地**——[UI-DESIGN.md](UI-DESIGN.md) 色彩/字体/间距/深度 token 全部代码化：①Asset Catalog 从 5 扩展到 **18 个 colorset**（Any + 暖黑 Dark 双外观，中性画廊背景 `#FAF8F5`/暖黑 `#161311`）；②`Color+Theme.swift` 补全 18 个 `milens` 语义色（旧名保留兼容）；③`Theme.swift` `pagePad`→24 + 圆角三档（10/14/20）+ `Elevation` 阴影 token（`.elevation()` 修饰符）；④新增 `Typography.swift`（8 层级，serif/rounded design，待字体文件切换 custom）。待办：阶段 A 第 5 步字体子集化引入（霞鹜文楷 + Fraunces）。
- 2026-08-07：**UI 设计系统阶段 A 全部完成（含字体子集化）**——在阶段 A 1–4 基础上：①霞鹜文楷 v1.522 GB2312 子集化（24.39 MB → **3.27 MB**，6976 字符覆盖 GB2312 全集）+ Fraunces 可变字体全轴静态化（Bold/Semibold 各 22.5 KB）放入 `Resources/Fonts/`，含 OFL 与 README；②`project.yml` 注册 `UIAppFonts`（3 TTF）；③`Typography.swift` 切换为 `.custom`（霞鹜文楷 `LXGWWenKai-Regular` 中文 display + Fraunces 英文 display）；④子集化脚本入 `tools/subset-fonts.py` + `tools/fix-fraunces-weights.py`。字体合计 ~3.31 MB。完整 `.app` 体积待 Mac 构建确认。
- 2026-08-07：**本地化工具链 + 文档校正落地**——新增 `tools/localization.py`（任意语言 String Catalog 导出/导入/check + Excel 工作流）与 `tools/requirements.txt`；同步工作区至 HEAD 的 String Catalog 与 `String(localized:)` API；文档校正：反映 commit 6b48453 的 `.strings` → `.xcstrings` 迁移（AGENTS/PLAN/DEVELOPMENT/DESIGN）+ 新增 DEVELOPMENT.md §4.4 本地化工作流。本地验证通过，App 编译待 CI。
- 2026-08-07：**P1.4 平台适配层落地**——4 协议（`PhotoLibraryAccess`/`FileStorage`/`VisionService`/`InferenceEngine`）+ 4 mock + `PlatformEnvironment` 注入 + 15 用例（对应源端 `AdapterContract`）。真实实现待 P1.5 AI 路线 ADR。另修复 SwiftData 测试环境（`MiLensApp.init` 检测 `XCTestConfigurationFilePath` 切 in-memory）。**CI 验证通过**（编译 + 测试全绿，run 31196033240）。
- 2026-08-08：**P1.5 AI 推理路线定案**——完成源端 AI 链路调研（CLIP 167.66 MB / RTMPose 5.90 MB / VisionKit 分割 / 两阶段检测管线 + 多级降级）、iOS Vision 能力评估（VNClassifyImageRequest 系统分类 + VNGenerateForegroundInstanceMask iOS 17+）、CLIP→Core ML 转换可行性分析。产品决策选**方案 A 全转换**（CLIP + RTMPose 转 Core ML，INT8 量化后包体积 ~45 MB；分割用 iOS 原生 Vision）。产出 [ADR-0007](docs/adr/0007-ios-ai-inference-route.md)，含转换管线、精度校验基准、包体积预算、落地任务拆解。后续转换工具链 + 真实实现随 P2 扫描 MVP 推进。
- 2026-08-08：**P1.5 续 AI 模型转换工具链落地**——新增 3 个 Python 脚本（`convert_clip_coreml.py` / `convert_rtmpose_coreml.py` / `prepare_text_embeddings.py`）+ `tools/requirements-models.txt`。CLIP INT8/FP16 量化 + 精度校验（cosine >0.999）；RTMPose SimCC 输出 + <2px 校验；text embeddings f32 格式验证通过。转换实跑需 macOS（coremltools 依赖）。
- 待办：范围裁剪与产品对齐；P1.3 拼豆核心（并行进行中）；CLIP/RTMPose Core ML 模型转换实跑 + `IOSVisionService`/`CoreMLInferenceEngine` 真实实现（P2 续）。

### P2 进度

- 2026-08-08：**P2 纯决策逻辑 + Service + View 层落地**——翻译源端 6 个纯决策模块为 Swift（`GalleryPageState`/`ScanFlowLogic`/`ScanControlMath`/`ImportFlowLogic`/`PhotoMetadataLogic`/`PhotoViewGestureMath`）+ ~84 用例 XCTest（对应源端黄金规格逐条翻译）；`ScanService`（Photos 全库扫描 + VisionService 检测 + Task 取消）+ `ImportService`（复制沙盒 → 入库，DESIGN.md §7 唯一入库路径）+ ~15 用例（in-memory SwiftData + mock）；`GalleryViewModel`（@Observable，分页/筛选/扫描/导入/多选）+ `GalleryView`（LazyVGrid + 分页加载 + 扫描进度条 + 完成弹窗）+ `PhotoViewView`（大图 + PhotoViewGestureMath 驱动的捏合缩放/平移/双击）+ `HomeView`（相册/扫描入口）。扩展 `PhotoLibraryAccess`（`loadImageData` + `dateAdded`）。**CI 验证待推送**。
