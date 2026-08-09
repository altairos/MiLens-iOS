# MiLens iOS 迁移计划

最后核对：2026-08-09（P0–P4 状态全量同步；P5 首页/设置/订阅/付费墙/元数据已实现 + 上架流水线代码落地待实测；评审高优先级+中优先级修复全部落地；严格并发开启 + ViewModelFactory 分层收敛 + 评审阻塞修复（编辑产物备份分区 / Photos 取消桥接 / 权益注册表取消墓碑 / View 注入全收敛 / UI Test+measure / 本地化规范化）落地，见状态摘要；剩性能基准、截图、iPad/深色检查与真机验收，见 [P2-待办清单](docs/P2-待办清单.md)）

> 里程碑与任务清单。架构见 [DESIGN.md](DESIGN.md)，映射与范围见 [MIGRATION_ASSESSMENT.md](MIGRATION_ASSESSMENT.md)，约束见 [AGENTS.md](AGENTS.md)。

## 里程碑总览

| 阶段 | 名称 | 目标 | 状态 |
|---|---|---|---|
| **P0** | Harness 与规划 | 文档骨架、约束、目录结构、XcodeGen 声明、范围对齐 | ✅ 已完成 |
| **P1** | 地基 + 算法核心 | Xcode 工程可编译、SwiftData schema、拼豆 Swift 核心（黄金规格通过）、AI 路线定案 | ✅ 已完成（含 2026-08-09 可靠性收口） |
| **P2** | 相册 MVP | 扫描发现（+质量评分/重复分组）+ 手动导入 + 相册网格 + 大图查看 | 🟡 实现完成，真机/性能验收待做 |
| **P3** | 宠物档案 | 档案 CRUD + 成长时间线 + 纪念提醒 | ✅ 已完成（含档案内照片分类 2026-08-09） |
| **P4** | 创作入口 + 编辑器 | 拼豆图纸完整流程 + 完整图片编辑器（裁切/滤镜/标注） | 🟡 实现完成（含宠物卡片生成），剩真机验收 |
| **P5** | 首页/我的 + 商业化 | 首页回忆/提醒、设置、StoreKit 订阅、App Store 提审 | 🟡 首页/设置/订阅/付费墙/元数据已实现，剩性能基准、截图与上架实测 |

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
- [x] v1 主题 token 已代码化；[UI Rework v2.0](UI-DESIGN.md) 已重新审计并修订动作色、字体边界、响应式和组件规格。**v2 迁移已落地（2026-08-09）**：v2 token（`ActionPrimary`/`AccentSoft`/`Border` 等）已代码化进 `Color+Theme.swift`，首页/创作/设置/引导页均按 v2 重构（git bea5b2f/bf23ce2/f85e22f），操作层用系统字体、文楷仅作稀缺情感标题
- [x] 本地化 String Catalog（`Localizable.xcstrings` + `InfoPlist.xcstrings`，源语言简中，结构支持任意语言；`String(localized:)` API）；`tools/localization.py` 导出/导入/校验工具；App Icon / 占位图待源端资源整理后补

### P1.2 数据层

- [x] SwiftData `@Model`：`Pet` / `Photo` / `PetEvent`（参照评估报告 §3 + 源端 ER，UUID 业务标识）
- [x] `VersionedSchema` v1 + 空 `SchemaMigrationPlan`
- [x] Repository 协议 + 实现（`PetRepositoryProtocol` / `PhotoRepositoryProtocol` + SwiftData 实现，`@MainActor`）
- [x] 扫描/导入边界设计：`getAllPhotoURIs()` 去重 + `insertPhoto()` 唯一入库路径（沿用源端约束）
- [x] `MiLensApp` 接入 `ModelContainer` + Repository `.environment` 注入
- [x] XCTest：Repository CRUD + 分页查询 + 关系删除规则 + 扫描/导入边界（22 用例）

### P1.3 拼豆算法核心（MiLensKit） ✅

按源端 `shared` 黄金规格逐模块翻译，**每个模块的源端测试先翻译成 XCTest 作为规格**：

- [x] 色彩空间：`BeadColorSpace`（rgbToLab/labToRgb/deltaE76/findNearestBeadColor/precomputePaletteLab）
- [x] 色板：`BeadPalette` + `BeadPaletteMard`（MARD 色卡源）
- [x] 生成管线：`BeadPatternService`（裁切/缩放/量化/抖动/去噪）— 主入口纯 Swift 单路径，去掉 Native/ArkTS 双路径（DESIGN.md §8）
- [x] 风格化草稿：`StylizedDraftGenerator` + `DraftToBeadMapper` + `DraftFeatureProtector`（含 finalizeNativePattern）
- [x] 评分：`BeadScoring`（TriScore）
- [x] 语义引导：`BeadSemanticGuide`
- [x] 渲染/导出：`BeadRenderer` + `BeadExportService`（A4）
- [x] 诊断工具：`AppErrorHandler`（错误分类/脱敏）+ `TaskLogger`（结构化任务日志）+ `DiagnosticsCollector`（诊断报表）
- [x] **验收**：源端用例 + parity 在 Swift 侧全绿 — 225 用例 0 失败（含主入口 16 用例 + DraftFeatureProtector 3 + BeadPatternStructure finalizeNativePattern 2 + AppErrorHandler 33 + TaskLogger 27 + DiagnosticsCollector 24）

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

- [x] `tools/convert_clip_coreml.py`（Torch → Core ML + INT8/FP16 量化 + 精度校验）→ `CLIPVisionEncoder_fp16.mlpackage`（168 MB）/ `_int8`（84 MB）
- [x] `tools/convert_rtmpose_coreml.py`（ONNX → PyTorch → Core ML + 校验）→ `RTMPoseTPetFace_fp16.mlpackage`（6.0 MB）/ `_int8`（3.1 MB）
- [x] `tools/prepare_text_embeddings.py`（f32 格式校验 + Swift 加载代码生成）
- [x] 模型资产加入 `Resources/Models/` + `project.yml` 注册（`pet_text_embeddings.f32` 已提交；4 个 `.mlpackage` 已实跑生成并验证精度，被 .gitignore 忽略不入库，Mac 转换命令见 [DEVELOPMENT.md](DEVELOPMENT.md) §4.3）
- [x] **实跑验证**：CLIP INT8/FP16 cosine >0.999（PASS）；RTMPose shape [1,5,384] 契约校验通过（精度需真实宠物脸图片）
- [x] `IOSVisionService` / `CoreMLInferenceEngine` 真实实现（P2 扫描 MVP，协议骨架 P1.4 已有）→ 已落地：`IOSVisionService`（VNClassifyImageRequest + VNGenerateForegroundInstanceMask）+ `CoreMLInferenceEngine`（MLModel + MLMultiArray）+ `ClipInferenceService`（推理编排）+ `AiInferenceLogic`/`ClipPreprocess`/`PetTextEmbeddings` 配套纯逻辑。编译通过 + 28 用例单测全绿；推理质量/精度/资源待真机验证（见 [P2-真机验证备忘](docs/P2-真机验证备忘.md) §2.2）

### P1 可靠性收口（2026-08-09）

P1 核心可靠性与性能六项修复全部落地（实现记录见状态摘要 P2 进度 2026-08-09 条）：

- [x] **模型交付**：`tools/model-manifest.json`（内嵌 SHA256）+ `tools/fetch-models.sh`（下载 → `shasum -a 256` 校验 → 解包，幂等，失败绝不带病构建）；`project.yml` excludes 实验模型（CLIP fp16 / RTMPose int8），App 体积 ~87MB 而非 261MB；发布到 GitHub Release（tag `models-v1`）
- [x] **像素计算移出主线程**：`AnalysisExecutor`（actor，utility 优先级，受限并发 2）+ `QualityScorer`/`ScanService` 两阶段重构，全部 CPU 密集段经后台执行器，进度回调次数保持按照片数
- [x] **媒体生命周期**：`MediaLifecycleService`（事务回滚 / 编辑旧文件清理 / 删除联动 / 孤儿审计）+ `refreshPetPhotoCounts` 补上生产链路 + 4 场景单测
- [x] **SwiftData 启动恢复**：SchemaV1 注释冻结 + `AppDependencies.make(isTesting:)` 工厂 + `DatabaseRecoveryView`（重试/导出诊断/重建本地数据），不再 `try!` 崩溃
- [x] **通知真调度**：`NotificationPosting.schedule`（`UNCalendarNotificationTrigger`）+ `NotifyService` 幂等重调度（Pet 生日/领养日年度 09:00 + 时光机每日 09:00）+ 设置开关（默认关闭，授权放开关路径）+ 宠物编辑/删除局部更新
- [x] **CI 覆盖 App**：PR 也跑 macOS app 作业（构建 + 测试 + 覆盖率），新增 `fetch-models.sh` 步骤 + `actions/cache` 缓存模型

### 验收标准

- 工程编译通过，空 App + TabView 可在 iPhone 模拟器启动 ✅（CI run 31187548565）
- SwiftData schema v1 + Repository 测试通过 ✅（CI run 31193790682）
- 平台适配层 4 协议 + mock + 测试 ✅（CI run 31196033240）
- MiLensKit 拼豆核心对源端 225 + parity 全绿 ✅（DraftFeatureProtector/finalizeNativePattern/utils 三件套已补齐）
- AI 路线 ADR 定案 ✅（[ADR-0007](docs/adr/0007-ios-ai-inference-route.md)，方案 A 全转换 + Vision 分割）

---

## P2 — 相册 MVP

### 任务

- [x] 纯决策逻辑翻译（6 模块）：`GalleryPageState`/`ScanFlowLogic`/`ScanControlMath`/`ImportFlowLogic`/`PhotoMetadataLogic`/`PhotoViewGestureMath`
- [x] XCTest：纯决策逻辑全覆盖（~84 用例，对应源端黄金规格）
- [x] `ScanService`：Photos 全库扫描 + 宠物识别（VisionService）+ 取消支持（Task.cancel）
- [x] `ImportService`：用户主动导入 → 复制沙盒 → 缩略图 → 入库（DESIGN.md §7 唯一入库路径）
- [x] ScanService/ImportService 测试（~15 用例，in-memory SwiftData + mock）
- [x] 扫描增强（[ADR-0008](docs/adr/0008-v1-scope-decision.md) 扩范围）：质量评分（翻译源端 QualityScorer → `Photo.qualityScore` / `sharpness`）
- [x] 扫描增强：重复分组（pHash 视觉哈希 → `Photo.duplicateOf` / `isBest`）
- [x] 扫描增强：多宠物自动归属——`PetMatcher`（注册 8–15 张照片特征 → CLIP embedding 聚合 PMF1 blob + 14 维颜色签名；`matchFromEmbedding` top1 ≥ 阈值 + top2 margin + 颜色距离三重判定）+ `PetFeatureCodec`/`ColorSignatureMath`/`PetMatcherScoring` 配套，CLIP 失败降级手工特征（阈值放宽 0.85，仅匹配不作分类），像素计算经 `AnalysisExecutor` 后台执行（git 3a4aca6）
- [x] `GalleryViewModel`（@Observable）：分页 + 筛选 + 扫描/导入编排 + 多选（含按日分组 `GallerySectionLogic`、宠物筛选 `GalleryFilterLogic`、上下文菜单，git 4f62f65/86088ea/843bdf1）
- [x] `GalleryView`：LazyVGrid 虚拟化 + 分页加载 + 扫描入口 + 完成弹窗
- [x] `PhotoViewView`：大图查看 + 手势（PhotoViewGestureMath 纯函数驱动）
- [x] `HomeView`：相册入口 + 扫描入口（NavigationLink → Gallery）
- [x] RootTabView 路由串联（navigationDestination for Route）
- [x] 引导流程：首次启动 → 权限说明 → 扫描 → 建档（`OnboardingView` + 4 步骤 + `OnboardingViewModel`，13 用例测试；真机授权弹窗待 P2 真机验证）
- [x] P0 修复：`IOSFileStorage`（FileManager 真实实现）注入组合根，替代内存 Mock——导入/编辑产物真正落盘，重启不丢
- [x] P0 修复：去重字段改 `Photo.originalURI`（Photos localIdentifier，`@Attribute(.unique)` 约束）+ 仓储 `getPhotoByOriginalURI`/`getAllOriginalURIs` + ScanService/ImportService 按 originalURI 去重（含批次内重复 identifier）
- [x] P0 修复：`ScanCursorStore`（UserDefaults）持久化上次成功扫描时刻，增量扫描不再用 `Date()` 截止；dateAdded 以 creationDate 近似并诚实标注（iOS 无公开「加入相册时间」API）
- [x] P0 修复：CLIP Phase 2 精筛接入扫描（`ClipInference` 协议 + 失败降级），App Store 文案去除「按宠物分别归类」不实描述
- [x] P0 修复：**SwiftData 测试进程崩溃根因修复**（ModelContainer 悬垂）——`container.mainContext` 不持有 container，测试 helper 局部 container 返回后释放，repo fetch 触发 SwiftData 内部 SIGTRAP（此前 XCTSkipIf 掩盖，CI/本地间歇崩溃）。修复：测试 helper 返回并持有 container（ImportServiceTests/ScanServiceTests/QualityScorerTests 全部调用点）；`RepositoryEnvironment` fallback 改 static 缓存容器。恢复 QualityScorerTests 运行（移除 XCTSkipIf）。本机完整 XCTest 400/400 通过
- [ ] 真机验证：Photos 权限 + Vision/Core ML 推理 + 分页性能 + PhotoView 下滑手势（需 Mac + iPhone，详见 [P2-真机验证备忘](docs/P2-真机验证备忘.md)）
- [x] P1 可靠性遗留 3 项收口：引导扫描游标（OnboardingViewModel 仅 `completedSuccessfully` 保存）、数据库重建后的沙盒媒体语义（恢复界面文案明确清除范围）、编辑旧文件清理失败策略（引用查询失败保守保留）——实现与单测已落地，详见 [P2-待办清单](docs/P2-待办清单.md)

### 验收标准

- 首次启动流程已实现：授权 → 扫描发现宠物 → 建档 → 相册可见；真机授权与真实照片走查待做 🟡
- 相册支持分页、筛选、多选、大图查看 ✅
- 扫描可取消，不提交过期结果 ✅
- CI/本机编译 + 测试全绿 ✅（本机 2026-08-09 最新：严格并发 `complete` 下 BUILD SUCCEEDED；App 604 passed / 0 failed、MiLensKit 594 / 0 failed、UI 2 冒烟、本地化 144+3 key 校验通过；CI 仍需下一次 PR 运行确认模型 Release 下载链路）
- 真机验证（待 Mac + iPhone）—— 待办清单见 [P2-真机验证备忘](docs/P2-真机验证备忘.md)

---

## P3 — 宠物档案

### 任务

**纯决策逻辑 + ViewModel（可 WSL2/CI 编译测试）✅**

- [x] 纯决策逻辑翻译（3 模块）：`PetProfileLogic`（物种 Emoji / 名称校验 / 数量上限 / 彩蛋）/ `PetFormLogic`（表单状态 / 备注解析格式化校验 / 未保存判定 / 注册常量）/ `TimelineLogic`（时间线条目构建 / 过滤 / 分组 / 索引查找）
- [x] XCTest：纯决策逻辑全覆盖（84 用例，对应源端 `PetProfileViewModel.test` + `PetFormViewModel.test` + `TimelineViewModel.test` 黄金规格逐条翻译 + iOS 边界增强）
- [x] `PetProfileViewModel`（@Observable）：宠物列表 / 建档（名称校验 + 数量上限 + 彩蛋触发）/ 删除
- [x] `PetEditViewModel`（@Observable）：档案加载 / 表单编辑 / 备注增删 / 未保存判定 / 校验保存
- [x] `TimelineViewModel`（@Observable）：加载宠物+事件+照片 → 构建时间线 → 按宠物筛选

**View + 提醒（需 Mac）**

- [x] `PetsView`：宠物列表 Tab（替换占位）——卡片（头像/名称/物种·年龄·性别/照片数·相处天数）+ 建档 Sheet + 彩蛋弹窗 + 长按删除（对应源端 PetProfilePage 列表部分）
- [x] `PetProfileView`：单只宠物详情（route .petProfile）——头像/名称/物种/年龄 + 统计行（照片数/相处天数/年龄）+ 最近照片网格 + 备忘列表 + 编辑/时间线入口
- [x] `PetEditView`：档案编辑（route .petEdit，翻译 PetEditViewModel）——名称/物种/性别/生日/领养日/备忘条目编辑 + 保存 + 删除 + 未保存确认
- [x] `TimelineView`：成长时间线（route .timeline）——按年月分组 + 宠物筛选 + 条目点击进大图
- [x] `AddPetSheet` 复用组件（建档表单：名称/物种/性别/生日/领养日）
- [x] `PetDisplayLogic` 纯函数（年龄/物种名/性别名/相处天数格式化）+ 15 用例 XCTest（翻译源端 DateUtils.test + Pet getSpeciesName/getGenderName）
- [x] Route 枚举扩展 `.timeline` + RootTabView 路由串联
- [x] 纪念提醒：`UNUserNotificationCenter`（生日/领养日）→ `NotifyService` 每日检查编排（纪念日同日事件 + 时光机随机一张 + 每日去重 + 撤销），平台层 `NotificationPosting` 协议隔离，15 用例全绿
- [x] 档案内照片分类（全部照片/待整理/作品三分段，UI-DESIGN.md §6.4）——`PetPhotoCategoryLogic` 纯逻辑（可靠维度：全部=宠物照片 / 待整理=未归属照片 / 作品=编辑产物 `Photo.category==edited`）+ `PhotoRepository.getUnassignedPhotos` + `PetProfileView` 分段 chips（含计数）+ 编辑保存自动打「作品」标记 + 8 用例 XCTest（纯逻辑 6 + SwiftData 查询 2）。V1 不做自动「幼年/玩耍/睡觉」分类（无可靠模型来源，诚实标注原则）

### 验收标准

- 宠物档案 CRUD 完整
- 时间线按事件聚合展示
- 纪念提醒可调度且可撤销 ✅（NotifyService + 15 用例；347 passed, 23 skipped, 0 failed）

---

## P4 — 创作入口 + 图片编辑器

> 完整图片编辑器进 V1.0（[ADR-0008](docs/adr/0008-v1-scope-decision.md)）。编辑器与拼豆图纸并行推进。

### 任务 — 拼豆图纸

- [x] `BeadPatternView`：选图 → 预设选择 → 生成预览 → 调参（CreateView 已导入照片网格 + BeadPatternView/BeadSettingsPanelView/BeadPatternResultView 三件套）
- [x] 接入 MiLensKit 生成管线（P1.3）+ 渲染（BeadViewModel 编排源端 doGenerate 全流程，preview 按 canvasScale 重绘）
- [x] A4 图纸导出（PNG）+ 系统分享（BeadExportService：A4 渲染 → 存相册 / 分享缓存 → UIActivityViewController）
- [x] 宠物卡片生成（创作 Tab 第二项目，UI-DESIGN.md §6.6）——`PetCardLogic` 纯逻辑（文案组装：名字/物种·年龄/「来到家 N 天」/拍摄日期回退）+ `PetCardView`（预览=导出同源 `PetCardArtwork`，ImageRenderer 渲染 1080×1350 4:5 纪念卡，保存相册/系统分享）+ `PetCardPhotoPickerView` 选照片页 + CreateView 入口 + Route 扩展。iOS 自研 MVP（源端 3D 手办不在 V1 范围），按 ADR-0009 保持免费，Pro 仅门控拼豆工作室与完整图片编辑器 + 8 用例 XCTest
- [x] 主体/bbox 保护接入（bbox + mask 已接入；pose 已随抠图分支接入：`PoseInferenceService` 两阶段 coarse-to-fine + `PoseSimccDecoder` SimCC 解码 + `adjustPoseForCrop` 写入 subject.pose，2026-08-09）
- [x] XCTest：Bead 生成 ViewModel 决策（BeadFlowLogicTests 26 用例，对应源端黄金规格）

### 任务 — 图片编辑器（[ADR-0008](docs/adr/0008-v1-scope-decision.md)）

**Phase 1：纯逻辑迁移到 MiLensKit（可 WSL2 编译测试）✅**

- [x] `EditorColorAdjust` — 调色参数建模 + 结构化 filter 因子（源端 CSS filter → iOS CIFilter 因子）
- [x] `EditorSharpnessKernel` — 锐化卷积核构造 + RGBA 卷积
- [x] `EditorCropMath` — 裁切 AABB 相交计算
- [x] `EditorLayerModels` — 图层类型定义（去掉 PixelMap 依赖，App 层 ViewModel 持有 CGImage）
- [x] `EditorLayerGeometry` — 图层几何（hitTest / scale clamp / 选择框 / 导出区域）
- [x] `EditorExifPolicy` — EXIF 日期/GPS 解析 + 保存策略
- [x] XCTest：编辑器纯决策逻辑（31 用例）

**Phase 2：文档/历史/序列化（可 WSL2 编译测试）✅**

- [x] `EditorDocument` + 序列化（源端 EditorDocument + LayerSerializer 合并，去掉 PixelMap 恢复回调，用 JSONEncoder/Decoder）
- [x] `EditorHistory` — 泛型撤销/重做栈 + 手势合并（coalescing）
- [x] XCTest：文档/历史/序列化（22 用例）

**Phase 2.5：编辑器 ViewModel 纯逻辑迁移到 MiLensKit（可 WSL2/CI 编译测试）✅**

- [x] `EditorToolLogic` — 工具切换/宽高比约束/文字图层默认值/裁剪比例选择/裁剪框初始化/工具组双层状态（源端 EditorToolViewModel 263 行）
- [x] `EditorCropOverlay` — 裁剪框覆盖层几何：遮罩/九宫格/角手柄/clamp（源端 EditorCropViewModel 137 行）
- [x] `EditorCanvasLogic` — 画布状态查询：工具激活/可保存/交互态/就绪（源端 EditorCanvasViewModel 36 行）
- [x] `EditorAdjustLogic` — 调色面板组装/中性判断/滑块手势合并/锐化异步卷积触发决策（源端 EditorAdjustViewModel 159 行）
- [x] `EditorCutoutLogic` — 抠图四态机/竞态守卫/结果验收（成功/降级/失败/过期）（源端 EditorCutoutViewModel 166 行）
- [x] `EditorSaveLogic` — 保存前置条件/返回动作/格式决策（PNG/JPEG）/文件名构造（源端 EditorSaveViewModel 115 行）
- [x] `EditorTextToolLogic` — 文字工具激活/输入校验/编辑面板可见性/图层编辑组装（源端 EditorTextToolViewModel 76 行）
- [x] XCTest：编辑器 ViewModel 纯逻辑（~152 用例，对应源端 7 个黄金规格测试逐条翻译）

**Phase 3：App 层 Controller + View（需 Mac）**

- [x] 编辑器骨架：`Views/Editor/` + `EditorViewModel` + 撤销/重做绑定
- [x] 裁切/旋转/翻转 UI + 手势（EditorCropMath / LayerGeometry / CropOverlay 驱动）
- [x] 滤镜面板（CIFilter + EditorColorAdjust 因子）
- [x] 文字 + 抠图（调研确认源端 `editor/` 无马赛克/标注差异；抠图走 Vision 真实语义分割，失败即 error 无降级）
- [x] 编辑产物回写沙盒（沿用 DESIGN.md §7 唯一入库路径）
- [x] XCTest：编辑器 ViewModel 决策

### 验收标准

- 从相册选图到拼豆图纸导出完整走通（拼豆图纸并行推进中）
- 行为与源端 BeadPatternPage 一致（对照源端用例）
- 图片编辑器裁切/滤镜/文字/抠图可用，产物正确入库（Phase 3 完成：编辑产物走 `Documents/MiPhotos` + Photo 就地更新）

---

## P5 — 首页/我的 + 商业化

### 任务

- [x] `HomeView`：杂志式首页（设计稿 Tab 1）——hero 大图 + 「往日回忆」+ 空态已按 v2 编辑式布局落地（`HomeViewModel` + `HomeHeroLogic`/`HomeMemoryLogic`/`HomeGreetingLogic` 纯逻辑 + HomeLogicTests，git d6e9ec5/f85e22f）；**成长提醒区块待补**，创作 CTA 已切换至创作 Tab
- [x] 回忆逻辑纯决策：「一年前的今天」（翻译 `TimeMachineService` + `NotifyScheduler` + `PhotoQueryLogic` 日期逻辑 → `AnniversaryLogic` + `TimeMachineLogic`，38 用例 XCTest）
- [x] `SettingsView`：主题/隐私设置/帮助/关于（设计稿 Tab 4）——`SettingsView` + `SettingsLogic`/`SettingsViewModel`（设置项/Pro 权益展示/通知开关）+ `AboutView`/`HelpView`/`PrivacyInfoView`（git bea5b2f）
- [x] StoreKit 2 订阅：MiLens Pro 产品配置（`Products.storekit`：月 ¥18 / 年 ¥98 / 永久 ¥298）+ `StoreKit2StoreService`（`Transaction` 监听）+ `ProEntitlementStore`（应用级权益唯一消费方）+ 付费墙 UI `PaywallView` + `PaywallLogic`/`PaywallViewModel`（git 61abdeb/a22ddba/078482e/310222c）——StoreKit Testing + 权益/付费墙逻辑均有 XCTest；StoreKit Testing 与真机购买验证待 Mac
- [x] App Store 截图/描述/ASO 关键词——文案已定稿（[docs/AppStore-metadata.md](docs/AppStore-metadata.md)：描述/关键词/订阅产品/审核备注/隐私问卷，2026-08-08）；**截图制作待 Mac**
- [ ] 性能基准：大图库（5000+）滚动/内存
- [ ] iPhone/iPad 适配（[ADR-0008](docs/adr/0008-v1-scope-decision.md)：iPad 为 V1.0 目标）+ 深色模式 + Dynamic Type 检查

### 上架（免 Mac 云端一条龙）

编译/签名/上传全部在 GitHub Actions macOS runner 完成，无需本机 Mac：

- [x] 在 `.github/workflows/ci.yml` 新增 `release` 作业（手动触发 `workflow_dispatch`）：`xcodebuild archive` → `xcodebuild -exportArchive`（签名）→ `xcrun altool` 上传 App Store Connect——已实现（2026-08-09，含 version/buildNumber/upload 输入与 `needs [kit, app]` 门禁；待 Secrets 配置后实测）
- [x] 证书/描述文件用 **App Store Connect API Key（.p8）** 注入 GitHub Secret（不用钥匙串）——Secrets 约定已落地（`ASC_API_KEY`/`ASC_API_KEY_ID`/`ASC_API_ISSUER_ID`/`ASC_TEAM_ID`），`.p8` 生成与配置见 [DEVELOPMENT.md](../DEVELOPMENT.md) §2.2
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

## V1.0 范围定案（[ADR-0008](docs/adr/0008-v1-scope-decision.md)）

| 项 | 结论 | 影响 |
|---|---|---|
| 完整图片编辑器 | ✅ 进 V1.0 | P4 新增编辑器模块（源端 `editor/` ~30 文件） |
| 质量评分 | ✅ 进 V1.0 | P2 扫描扩展（QualityAnalyzer → `Photo.qualityScore`） |
| 重复分组 | ✅ 进 V1.0 | P2 扫描扩展（embedding 相似度 → `Photo.duplicateOf`） |
| 家庭局域网备份 | ❌ 后置 V1.x | V1.0 不建 `Services/Backup/` |
| AI 写真 / 回忆视频 | ❌ V1.0 不做 | 不引入云服务依赖 |
| iPad 适配 | ✅ V1.0 支持 | SwiftUI 自适应，跨 P2–P5 |

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
- 2026-08-08：**UI Rework 系统审计完成**——旧规范判定为“方向可保留、执行规格不合格”。重写 [UI-DESIGN.md](UI-DESIGN.md) 为 v2.0：修复品牌珊瑚白字对比度问题，拆分 Brand/Action 色；系统字体负责操作层、文楷仅作稀缺情感标题、Fraunces 退出常规 UI；补齐首次导入闭环、真实 V1 能力边界、iPad 结构、组件状态与设计验收门禁。审计见 [docs/UI_REWORK_AUDIT.md](docs/UI_REWORK_AUDIT.md)。现有 SwiftUI 与 v1 token 不计入 v2 视觉完成度，待后续重做。
- 2026-08-07：**本地化工具链 + 文档校正落地**——新增 `tools/localization.py`（任意语言 String Catalog 导出/导入/check + Excel 工作流）与 `tools/requirements.txt`；同步工作区至 HEAD 的 String Catalog 与 `String(localized:)` API；文档校正：反映 commit 6b48453 的 `.strings` → `.xcstrings` 迁移（AGENTS/PLAN/DEVELOPMENT/DESIGN）+ 新增 DEVELOPMENT.md §4.4 本地化工作流。本地验证通过，App 编译待 CI。
- 2026-08-07：**P1.4 平台适配层落地**——4 协议（`PhotoLibraryAccess`/`FileStorage`/`VisionService`/`InferenceEngine`）+ 4 mock + `PlatformEnvironment` 注入 + 15 用例（对应源端 `AdapterContract`）。真实实现待 P1.5 AI 路线 ADR。另修复 SwiftData 测试环境（`MiLensApp.init` 检测 `XCTestConfigurationFilePath` 切 in-memory）。**CI 验证通过**（编译 + 测试全绿，run 31196033240）。
- 2026-08-08：**P1.5 AI 推理路线定案**——完成源端 AI 链路调研（CLIP 167.66 MB / RTMPose 5.90 MB / VisionKit 分割 / 两阶段检测管线 + 多级降级）、iOS Vision 能力评估（VNClassifyImageRequest 系统分类 + VNGenerateForegroundInstanceMask iOS 17+）、CLIP→Core ML 转换可行性分析。产品决策选**方案 A 全转换**（CLIP + RTMPose 转 Core ML，INT8 量化后包体积 ~45 MB；分割用 iOS 原生 Vision）。产出 [ADR-0007](docs/adr/0007-ios-ai-inference-route.md)，含转换管线、精度校验基准、包体积预算、落地任务拆解。后续转换工具链 + 真实实现随 P2 扫描 MVP 推进。
- 2026-08-08：**P1.5 续 AI 模型转换工具链落地**——新增 3 个 Python 脚本（`convert_clip_coreml.py` / `convert_rtmpose_coreml.py` / `prepare_text_embeddings.py`）+ `tools/requirements-models.txt`。CLIP INT8/FP16 量化 + 精度校验（cosine >0.999）；RTMPose SimCC 输出 + <2px 校验；text embeddings f32 格式验证通过。转换实跑需 macOS（coremltools 依赖）。
- 2026-08-08：**P0 收口**——V1.0 范围定案（[ADR-0008](docs/adr/0008-v1-scope-decision.md)）：完整图片编辑器 + 质量评分 + 重复分组进 V1.0；家庭局域网备份 / AI 写真后置或不做；iPad V1.0 支持。P0 全部任务完成，里程碑标记 ✅。下游影响：P2 扫描增强、P4 新增编辑器模块。
- 2026-08-08：**P1.3 拼豆算法核心完成**——最后一个大模块 `BeadPatternService.swift` 主入口落地（514 行）：同步 `generateBeadPattern` / 异步 `generateBeadPatternAsync`（Task.checkCancellation 取消）/ 自动模式 `generateBeadPatternAuto` + 异步版（色数 × 风格矩阵 + TriScore 选优）。架构差异：源端 Native C++ + ArkTS fallback 双路径 → iOS 纯 Swift 单路径；源端 TaskPool + jobId 取消表 → async/await + Task.cancel()。扩展 `BeadPattern` 结构体（补 protectMask/faceRoi/diagnostics/triScore/autoColorHint 字段）+ 新增 `getColorLimitBySize`。XCTest 16 用例（翻译源端 6 个可靠性用例 + 新增输入校验/auto/异步取消）。
- 2026-08-08：**P4 图片编辑器 Phase 1-2 落地**——源端 `editor/` 纯逻辑+文档+历史翻译到 MiLensKit（8 文件 / ~1180 行）：Phase 1 纯逻辑 6 模块（ColorAdjust/SharpnessKernel/CropMath/LayerModels/LayerGeometry/ExifPolicy）；Phase 2 文档+序列化+历史（EditorDocument 含 JSON 序列化，EditorHistory 泛型撤销/重做+手势合并）。XCTest 53 用例。架构差异：源端 CSS Canvas filter → iOS CIFilter 结构化因子；源端 PixelMap 运行时资源 → App ViewModel 持有 CGImage；源端 LayerSerializer PixelMap 恢复回调 → iOS JSONEncoder/Decoder 无回调。本地 swift build 待 WSL2 恢复后验证。
- 2026-08-08：**P4 图片编辑器 Phase 2.5 ViewModel 纯逻辑落地**——源端 `viewmodels/Editor*ViewModel.ets` 7 个纯逻辑文件翻译到 MiLensKit（7 文件 / ~825 行）：EditorToolLogic（工具切换/宽高比/裁剪比例/工具组双层状态 263 行→273 行）、EditorCropOverlay（裁剪框覆盖层遮罩/九宫格/角手柄/clamp 137 行→140 行）、EditorCanvasLogic（画布状态查询 36 行→49 行）、EditorAdjustLogic（调色面板/滑块手势合并/锐化异步卷积决策 159 行→144 行）、EditorCutoutLogic（抠图四态机/竞态守卫/结果验收 166 行→151 行）、EditorSaveLogic（保存/返回/格式决策 115 行→106 行）、EditorTextToolLogic（文字工具决策 76 行→62 行）。XCTest ~152 用例（对应源端 7 个黄金规格测试逐条翻译）。架构差异：源端 EditorToolMode/Group 字符串联合类型 → iOS String enum；源端 EditorCanvasViewModel 重复定义 `EditorTool` → iOS 统一到 `EditorToolMode`；源端 `guard` 参数名（JS 合法）→ iOS `guard_`（Swift 关键字）；源端 timestamp 为 number → iOS Int64；源端 resolveSaveFileNameHint/WithDecision 两函数 → iOS 函数重载。
- 2026-08-08：**P4 拼豆图纸 App 层落地**——分层推进：①MiLensKit `BeadFlowLogic`（生成编排/结果展示/导出决策纯逻辑）+ 26 用例 XCTest（对应源端 BeadFlowLogicTests 黄金规格）；Sendable 补齐（`BeadPattern`/`BeadDrawOptions`/`BeadExportOpts`/`BeadGenerateOptions`）；②App 层 `BeadViewModel`（@Observable 编排源端 doGenerate：解码 2048 上限 → `detectPets` 归一化 bbox 转像素 → CLIP 语义缓存 → 可选抠图（iOS mask bbox 局部坐标平铺全图 + `cropMaskToSquare` + `adjustSubjectForCrop`）→ `resolveBeadGeneration` + `applySemanticPaletteSteering` → detached Task 生成 + 取消；`refreshPreview` 按 canvasScale 重绘（上限 2560 控内存）；`export`/`prepareShareFile` detached 渲染）；③三件套视图 `BeadPatternView`（三态切换 + toast + 查看原图）/ `BeadSettingsPanelView`（5 风格/4 尺寸/摘要/高级设置折叠）/ `BeadPatternResultView`（统计行/彩色与字母模式切换/缩放/保存/分享/材料清单，`ShareItem` 包装 URL 供 `sheet(item:)`）；④入口接线：CreateView 已导入照片网格 + PhotoViewView toolbar 拼豆入口 + RootTabView `beadPattern` 路由。架构差异：iOS `DetectionBox` 归一化 → 像素换算；`SegmentationResult.mask` bbox 局部 → 全图平铺；iOS 无 pose（`subject.pose` 留 nil）；源端 PNG 字节序经 `makeImage` 统一处理。**验证**：MiLensKit 520 用例 WSL2 全绿（含 Sendable 改动）；swift-format lint 8 个 App 层文件 0 error；App 层语义编译待 CI（需 Mac，本地 Windows 无法编译 UIKit）。
- 2026-08-08：**P4 图片编辑器 Phase 3 完成**——App 层 Controller + View 全部落地（`Views/Editor/` 5 文件 + `ViewModels/Editor/EditorViewModel` + `Services/Editor/` 保存/图像处理）：骨架（Route.editor + 撤销/重做 + 返回确认）、裁切面板（比例 chips + 确认=像素级重置历史）、旋转/翻转（像素级 vs 属性级）、调色面板（5 滑杆，锐化仅 end/click 触发卷积，`renderedSharpness` 记录上次渲染强度）、文字（添加/选中编辑/删除/撤销重做）、抠图（Vision 真实语义分割，失败即 error 无降级）、编辑产物回写 `Documents/MiPhotos` + Photo 就地更新（thumbnailPath 置空回退 uri）。iOS 差异：像素级操作（裁切确认/旋转 90°/抠图应用）不可撤销；CIFilter 用名称式 API（iOS 17 兼容）；字体 token 是 `extension Font`（无 Typography）。EditorViewModelTests 24 用例全绿；全量 371 tests / 0 failures。架构差异：源端 Canvas 滤镜/异步卷积 → iOS CIFilter 同步渲染（决策层已把锐化收敛为 end/click 单次卷积）。
- 待办：CLIP/RTMPose Core ML 推理质量真机验证（实现已完成，见 [P2-真机验证备忘](docs/P2-真机验证备忘.md) §2.2）；App Store 上架准备（Secrets 配置 + release 实测 + 截图 + ASC 元数据录入）。

### P2 进度

- 2026-08-09：**审计收口 M2-M4 + 低优先级 L1-L5 全部落地**——①**M2 编辑器 ViewModel 拆分**：`EditorViewModel` 573 行拆为编排层 + `EditorDocumentController`（文档状态/历史/owner 注入）+ 4 个面板 VM（`EditorCropPanelVM`/`EditorAdjustPanelVM`/`EditorTextPanelVM`/`EditorCutoutPanelVM`，各自 <200 行，600/800 守卫恢复），owner API 经 `EditorOwnerProtocol` 协议化，面板独立测试；②**M3 MiLensKit 严格并发**：`Package.swift` 开启 `-strict-concurrency=complete`（保持 Swift 5 语言模式），修复 6 处并发违规（`TaskLoggerState` 锁化 + `@unchecked Sendable`、`BEAD_EFFECT_PRESETS` 全局锁化、`_editorLayerIdCounter` 锁化、`ErrorCategoryEntry`/`ErrorLogLevel`/`TaskKind`/`TaskOutcome`/`BeadSizePresetValue`/`BeadColorPresetValue` 显式 `Sendable`），本地 Swift 6.1.3 零警告；③**M4 无障碍**：相册网格缩略图（照片+月日+已选择+已收藏组合文案）、时间线代表照片、宠物卡片头像补 `accessibilityElement(children: .ignore)` + `accessibilityLabel`；④**L1 隐私清单**：新增 `PrivacyInfo.xcprivacy`（NSPrivacyTracking=false；CollectedDataTypes=Photos/AppFunctionality 均 Linked=false/Tracking=false；AccessedAPITypes=UserDefaults CA92.1），project.yml 目录 glob 自动纳入；⑤**L2 导入分批提交**：`PhotoRepository.insertPhotos` 批量单次 save，`MediaLifecycleService.commitImportBatch`（入库失败回滚本批文件），`ImportService` 攒批 32 张 flush（尾批含取消中断不丢文件），自动归属仅对成功入库执行，+2 批量用例；⑥**L3 孤儿审计后台化**：启动延迟 3s + `auditOrphans` 文件遍历/删除移入 `Task.detached(priority: .utility)`（`FileStorage: Sendable` 可安全捕获），不占启动关键路径；⑦**L4 classifyError iOS NSError domain**：`ErrorInput` 增 `domain` 字段，`classifyError` 优先判定 `NSPOSIXErrorDomain`/`NSCocoaErrorDomain`（516/640/642 存储、3072 取消、4/260 文件、513/257 权限、134000-134199 数据库）/`PHPhotosErrorDomain`/`NSURLErrorDomain`/`SwiftDataErrorDomain`，未命中回落原 code/message 规则（向后兼容），`withCatch`/`withCatchSync` 透传 domain，+4 用例；⑧**L5 日志 localIdentifier 脱敏**：`AppErrorHandler.redactIdentifier`（前缀 10 + …）+ `sanitizeForLog` 新增第 10 条 `[PHID]` 规则（UUID/L 格式），`PhotoLibraryError.errorDescription` 与 `ScanService`/`ImportService` 共 6 处日志改为脱敏输出，+3 用例。**验证**：WSL2 Ubuntu-24.04 + Swift 6.1.3 `swift build` 零警告 + `swift test --parallel` 全绿（578 + 新增用例）；App 层 6 个改动文件 `swiftc -parse` 全过；App 编译/App 层测试待 CI（Windows 无 iOS SDK，未执行）。

- 2026-08-09：**审计复核（同日）**——逐项核对 M2–M4/L1–L5 后补两处加固：①**M3 再加固**：`BEAD_EFFECT_PRESETS` public 读写路径此前绕过锁（`nonisolated(unsafe)` 承诺未完全兑现），现 getter/setter 全部加锁，锁内代码改用私有 `_effectPresets`（NSLock 不可重入，避免死锁）；②**L4 区间扩大**：Core Data 错误区间由 134030-134099 扩大为 134000-134199（原区间漏 134000-134012 存储类型与 134100+ 版本哈希/元数据），并补区间下/上边界与区间外（133999/134200）断言。L5 全库复核结论：TaskLogger 全链路输出均经 `sanitizeForLog`（含 [PHID] 规则）、`ScanProgress.currentIdentifier` 仅进 UI 回调不落日志、`photoID`/`petID` 均为库内 UUID 非照片 localIdentifier。**重跑验证**：`swift build` 零警告（10.69s）+ `swift test` 585/585 全绿；`git diff --check` 干净；App 编译/App 层测试仍待 CI。

- 2026-08-09：**可观测性 + 规模治理收口（H1/H4/H3/M1/H2）**——①**H1 诊断链路接入**：`AppLogBackend`（Apple 平台 os.Logger / Linux 空实现，`#if canImport(os)`）+ `AppErrorHandler` debug/info/warn/error 全量接入后端（消息与错误明细先经 `sanitizeForLog` 脱敏），`ScanService`/`ImportService` 接入 `TaskLogger` 结构化任务日志（beginTask/stage/progress/complete/cancel/fail 全路径，失败带 ErrorInput）；②**H4 导入失败可观测性**：`ImportResult` 新增 `failed` 计数，`importPhotos` 单张失败累加 + `logger.error` 明细，`resolveImportSummary` 失败文案（`有 N 张照片导入失败`），弹窗条件改 `imported > 0 || failed > 0`；新增 `MockPhotoLibraryAccess.imageDataErrors` 失败注入 + 2 用例（部分失败/全失败）；③**H3 CI 覆盖率门禁**：`tools/check-coverage.sh`（bash + 内嵌 python3 解析 `xcrun xccov view --report --json`，按目标 MiLens/MiLensKit 匹配，line/function 取文件级均值、branch 精确汇总，基线环境变量可覆盖；默认 App 30/25/30、Kit 47/50/44 为占位值待首次实测校准）+ ci.yml 测试步骤 `-resultBundlePath` + 「Check coverage gate」步骤 + `TestResult.xcresult` artifact 上传（always）；④**M1 权限文案收敛**：`InfoPlist.xcstrings` 定为唯一事实来源（Xcode 15+ 自动注入），`project.yml` info.properties 与 `Info.plist` 移除重复的 CFBundleDisplayName/NSPhotoLibraryUsageDescription/NSPhotoLibraryAddUsageDescription，并清除自动提取的 CFBundleName 冗余条目；⑤**H2 Repository 全表加载分页化**：`PhotoRepository` 新增 `countAllPhotos`（`fetchCount`），`getAllOriginalURIs`/`getAllPhotoURIs`/`getDuplicateCandidates` 用 `propertiesToFetch` 只取所需列（避免整行物化），`GalleryViewModel.totalPhotoCount` 改用计数查询；mock/测试同步（InMemory/Failing 转发）+ 2 用例。**验证**：WSL2 Ubuntu-24.04 + Swift 6.1.3 `swift build` 零警告 + `swift test` 578/578 全绿（含 TaskLogger/AppErrorHandler 用例）。

- 2026-08-09：**多宠物自动归属落地**——`PetMatcher`（对应源端 PetMatcher.ets）：`registerPetFeatures`（8–15 张照片 → CLIP embedding 聚合均值向量 + 代表性样本 + 14 维颜色签名，编码 PMF1 blob 存 `Pet.featureData`）+ `matchFromEmbedding`（top1 ≥ 阈值 + top2 margin + 颜色距离不冲突三重判定）+ `extractMatchColorSignature`（tiebreaker）；CLIP 失败降级手工特征 embedding（仅匹配不作分类，阈值放宽 0.85），像素计算经 `AnalysisExecutor` 后台执行。配套 `PetFeatureCodec`/`PetMatcherScoring`/`ColorSignatureMath` 纯逻辑 + 测试（git 3a4aca6）。引导建档与宠物编辑页接特征注册入口（`OnboardingViewModel.registerCreatedPetFeature`）。

- 2026-08-09：**P2 可靠性遗留 3 项收口**——三项遗留经核实已在前期提交落地（ba434c4/b60749c/9cfdf20），本次同步待办清单与本文档状态：①引导扫描游标：`OnboardingViewModel.startScan` 收尾仅在 `ScanResult.completedSuccessfully` 时 `saveLastSuccessfulScan`（失败/取消/`skipScan` 均不推进增量基线），测试 `testScanSuccessSavesCursor` / `testScanFailureShowsErrorAndDoesNotComplete`；②「重建本地数据」沙盒副本语义定案：`DatabaseRecoveryView` 主文案与二次确认弹窗均明确「同时删除沙盒中已保存的照片副本（导入/编辑产物）」，`AppDependencies.destroyPersistentStore` 注释同步孤儿审计行为；③编辑清理保守策略：`MediaLifecycleService.saveEditedPhoto` 引用查询（`getPhotoByURI`）失败时 `stillReferenced = true` 保守保留旧文件，测试 `testSaveEditedPhotoKeepsOldFileWhenReferenceQueryFails`。

- 2026-08-09：**P1 核心可靠性收口（六项全部落地）**——①**模型交付**：`tools/model-manifest.json` + `tools/fetch-models.sh`（GitHub Release 下载 + SHA256 校验 + 解包，幂等；`MILENS_MODEL_BASE_URL` 可覆盖做本地/镜像测试），生产模型 = CLIP int8（84MB）+ RTMPose fp16（6MB），`project.yml` excludes 两个实验模型（App ~87MB 而非 261MB），fetch-models.sh 三条路径实跑验证（幂等跳过 ✅ / 下载校验解包 ✅ / 篡改 sha256 拒绝 ✅，修复 macOS bash 3.2 在 UTF-8 locale 下 `$VAR`+全角标点解析缺陷）；②**后台执行器**：`AnalysisExecutor`（actor + utility 优先级 + 受限并发 2，in-flight 计数 + continuation 队列），`QualityScorer` 像素计算（解码/Laplacian/pHash）与 O(n²) 重复分组移入执行器，`ScanService` 两阶段重构（阶段 1 MainActor 轻量过滤收集候选，阶段 2 分批后台分析回 MainActor 汇总），测试注入串行执行器保证确定性；③**媒体生命周期**：`MediaLifecycleService` 接管导入/编辑/删除（DB 失败回滚文件、编辑成功清理旧文件、删除联动媒体 + 刷新 photoCount、启动孤儿审计），ImportService/EditorSaveService 委托 + MiLensApp 注入 + 4 场景单测；④**SwiftData 启动恢复**：SchemaV1 注释冻结（后续字段必须 SchemaV2 + MigrationStage），`MiLensApp` `try!` → `@State` 启动状态机 + `DatabaseRecoveryView`（可读错误/重试/导出诊断 Documents/Diagnostics/重建本地数据二次确认），依赖组装收口 `AppDependencies.make(isTesting:)`；⑤**通知真调度**：`NotificationPosting.post` → `schedule(dateComponents:repeats:)`（`UNCalendarNotificationTrigger`），`NotifyService.rescheduleAllReminders` 幂等（Pet 生日/领养日年度重复 + 时光机每日 09:00），设置开关默认关闭（授权放开关路径，拒绝回弹），RootTabView 移除自动授权，宠物编辑/删除接局部更新；⑥**CI**：app job 去掉 `if: pull_request` 限制（PR 也构建 + 测试 + 覆盖率），新增模型下载步骤 + `actions/cache` 缓存 `MiLens/Resources/Models`。**本机验证：全套 App 测试 400/400 通过 0 失败**（含 ScanService 15 / NotifyService 10 / MediaLifecycleService 4 / NotifyCheckLogic 2），23 项模拟器跳过已全部恢复（30/30 通过）。

- 2026-08-09：**P0 续：扫描状态化 + 数据一致性收口**——①`ScanResult` 增加 `error`/`completedSuccessfully` 状态：仓储读取失败、照片计数失败、流式遍历中断均返回 error（不再伪装成空结果），`GalleryViewModel` 只在 `completedSuccessfully` 时保存增量游标（失败/取消不保存，避免下次增量跳过未扫照片），失败弹窗显示「扫描未完成」+ 错误信息；②Schema 迁移策略正式化：产品未发布，V1 即首发基线（含 originalURI unique），旧开发库首发前清库重装（SwiftData 对「新增唯一约束」无 lightweight migration），首发后 schema 变更必须递增版本号（见 SchemaVersion.swift 文件头 + DESIGN.md §7）；③导入文件名由短哈希改为 UUID（与 Photo.id 一致，避免碰撞覆盖已有文件）；④`MediaLifecycleService` 落地（写文件+入库事务段，DB 失败回滚文件；编辑保存失败恢复记录旧属性并删新文件、成功清理旧版本文件；删除联动媒体文件；启动孤儿审计）。新增/适配 XCTest：ScanService 失败路径 3 用例 + GalleryViewModelTests 3 用例（游标保存条件）+ MediaLifecycleServiceTests（事务回滚）+ 导入 UUID 文件名 1 用例。
- 2026-08-08：**P0 扫描/导入数据闭环修复（iOS）**——①`IOSFileStorage`（FileManager 真实实现）落地并注入组合根，生产环境不再用内存 Mock（导入/编辑产物持久化到沙盒，重启不丢）；②去重字段改为 `Photo.originalURI`（Photos localIdentifier，`@Attribute(.unique)` 约束），仓储新增 `getPhotoByOriginalURI`/`getAllOriginalURIs`，ScanService/ImportService 按 originalURI 去重（含批次内重复 identifier）；③新增 `ScanCursorStore`（UserDefaults 持久化上次成功扫描时刻），GalleryViewModel/OnboardingViewModel 增量扫描改用游标替代 `Date()` 截止，dateAdded 以 creationDate 近似并诚实标注（iOS 无公开「加入相册时间」API，老照片导入相册不会被增量发现）；④CLIP Phase 2 精筛接入扫描链路（`ClipInference` 协议 + ScanService.confirmPetWithClipIfAvailable，失败降级），App Store 文案去除「按宠物分别归类」不实描述。schema 变更（originalURI unique）需删除旧开发数据重装。新增/适配 XCTest：IOSFileStorage 8 用例 + ScanCursorStore 3 用例 + CLIP 精筛 4 用例 + 去重回归 4 用例。
- 2026-08-08：**P2 纯决策逻辑 + Service + View 层落地**——翻译源端 6 个纯决策模块为 Swift（`GalleryPageState`/`ScanFlowLogic`/`ScanControlMath`/`ImportFlowLogic`/`PhotoMetadataLogic`/`PhotoViewGestureMath`）+ ~84 用例 XCTest（对应源端黄金规格逐条翻译）；`ScanService`（Photos 全库扫描 + VisionService 检测 + Task 取消）+ `ImportService`（复制沙盒 → 入库，DESIGN.md §7 唯一入库路径）+ ~15 用例（in-memory SwiftData + mock）；`GalleryViewModel`（@Observable，分页/筛选/扫描/导入/多选）+ `GalleryView`（LazyVGrid + 分页加载 + 扫描进度条 + 完成弹窗）+ `PhotoViewView`（大图 + PhotoViewGestureMath 驱动的捏合缩放/平移/双击）+ `HomeView`（相册/扫描入口）。扩展 `PhotoLibraryAccess`（`loadImageData` + `dateAdded`）。**CI 验证待推送**。
- 2026-08-08：**P2 扫描增强落地（质量评分 + 重复分组）**——翻译源端 `QualityScorer.ets` + `ImageUtils.computeQualityScore` + `pHash.ets` 为 Swift：①纯逻辑三模块（`QualityScoringLogic` 质量公式 / `PerceptualHashLogic` 哈希运算 / `DuplicateGroupingLogic` Union-Find 分组）+ 9 用例 XCTest（翻译源端 `MorePureLogic` + `QualityScorer` 黄金规格 + iOS 边界增强）；②`ImageAnalyzer` 协议 + `CoreImageAnalyzer` 实现（Laplacian 方差清晰度 + 8×8 均值哈希，Core Graphics）+ mock；③`QualityScorer` 编排服务（`computeAllQualityScores` + `findDuplicates` + `runPostScanAnalysis`）+ 8 用例 XCTest（in-memory SwiftData + mock，与 ScanServiceTests 同类跳过待 Mac 真机）；④Schema 扩展：`Photo` 加 `phash`/`sharpness`/`qualityScore`/`duplicateOf`/`isBest` 字段，`PhotoRepository` 加 4 个查询/更新方法；⑤集成：`GalleryViewModel` 扫描/导入完成后 fire-and-forget 触发质量分析（对应源端 ScanController 后处理链）。重复分组当前用 pHash，不依赖 CLIP Core ML；待模型就绪后可增强为 embedding 相似度。**CI 验证待推送**。
- 2026-08-08：**CLIP/Vision/CoreML 真实实现落地**——ADR-0007 §7 落地任务收尾：①`AiInferenceLogic`（纯决策：cosineSimilarity/l2Normalize/classifyImageEmbedding/selectOutputEmbedding，对应源端 AiInferenceLogic.ets）；②`ClipPreprocess`（纯逻辑：bilinearResizeAndNormalize RGBA/NCHW + computeHandcraftedFeatures 512 维降级，对应源端 ClipPreprocess.ets）；③`PetTextEmbeddings`（从 bundle 加载 pet_text_embeddings.f32，解码为 pet/nonPet 两组字典）；④`CoreMLInferenceEngine`（InferenceEngine 真实实现：MLModel + MLMultiArray + memcpy 拷贝 + C-order contiguous 判断，对应源端 ModelRunner.ets）；⑤`IOSVisionService`（VisionService 真实实现：VNClassifyImageRequest 宠物预筛 + VNGenerateForegroundInstanceMask iOS 17+ 主体分割，对应源端 VisionKitImpl.ets）；⑥`ClipInferenceService`（推理编排：解码→预处理→predict→selectOutput→classify，对应源端 AiService.ets）；⑦MiLensApp 接线（注入 IOSVisionService + ClipInferenceService，测试环境跳过模型加载）。编译通过 + 28 用例单测全绿（AiInferenceLogicTests 17 + ClipPreprocessTests 11）。**推理质量/精度/资源待真机验证**——详细清单见 [P2-真机验证备忘](docs/P2-真机验证备忘.md) §2.2/§5.3.1。

### P3 进度

- 2026-08-08：**P3 纯决策逻辑 + ViewModel 落地**——翻译源端 3 个宠物档案纯决策模块为 Swift（`PetProfileLogic` / `PetFormLogic` / `TimelineLogic`）+ 84 用例 XCTest（对应源端 `PetProfileViewModel.test` + `PetFormViewModel.test` + `TimelineViewModel.test` 黄金规格逐条翻译 + iOS 边界增强）；3 个 `@Observable` ViewModel（`PetProfileViewModel` 列表/建档/删除 + 彩蛋触发 / `PetEditViewModel` 档案加载/表单编辑/备注增删/未保存判定/校验保存 / `TimelineViewModel` 加载宠物+事件+照片→构建时间线→按宠物筛选）。架构差异：源端 petId/photoId 为整数+`-1` 哨兵 → iOS `UUID?`+`nil`；源端 birthday 为 ISO 字符串 + `substring` 比较彩蛋 → iOS `Date?` + `Calendar` 提取 MM-DD；源端彩蛋/物种 Emoji 在 `PetFormViewModel`/`PetProfileViewModel` 两处重复 → iOS 收敛到 `PetProfileLogic` 单一来源；源端 `new Date(y,month0,d)` → iOS 固定 UTC `Calendar`+`DateComponents` 保证跨环境可复现。**CI 验证待推送**。
- 2026-08-08：**P5 回忆/通知纯逻辑落地**——翻译源端 `PhotoQueryLogic.ets` 日期格式化 + `TimeMachineService.ets` 选片/文案 + `NotifyScheduler.ets` 纪念日逻辑为 Swift 纯函数：①`AnniversaryLogic`（`formatAnniversaryMonthDay` / `computeYearsAgo` / `isHistoricalPhoto` / `buildAnniversaryNotificationText` / `buildTimeMachineText` 4 模板 / `timeMachineNotificationID` 公式 parity）；②`TimeMachineLogic`（`selectTimeMachinePhoto` 随机选片参数化 + `buildTimeMachineResult` 端到端结果构建 + `buildAnniversaryNotifications` 批量纪念日通知）。38 用例 XCTest（日期格式化 5 + 年份差 5 + 历史筛选 4 + 文案 parity 9 + ID 公式 2 + 选片 4 + 结果构建 6 + 批量通知 4）。架构差异：源端 `Math.random()` → iOS `randomIndex` 参数化可测；源端 `new Date(string).getFullYear()` → iOS `utcCalendar` 固定时区可复现。**CI 验证待推送**。
- 2026-08-08：**P3 View 层落地（宠物档案四页面）**——①`PetsView` 替换占位为宠物列表 Tab（卡片：头像/名称/物种·年龄·性别/照片数·相处天数 + 建档 Sheet + 彩蛋弹窗 + 长按删除，对应源端 PetProfilePage 列表部分）；②`PetProfileView`（route .petProfile）单宠详情：头像/统计行（照片数/相处天数/年龄）+ 最近照片网格 + 备忘列表 + 编辑/时间线入口；③`PetEditView`（route .petEdit）档案编辑：名称/物种/性别/生日/领养日/备忘条目 + 保存/删除/未保存确认（翻译 PetEditViewModel）；④`TimelineView`（route .timeline）成长时间线：按年月分组 + 宠物筛选 chips + 条目点击进大图（翻译 TimelineViewModel + TimelineLogic）；⑤`AddPetSheet` 复用组件；⑥`PetDisplayLogic` 纯函数（年龄/物种名/性别名/相处天数/日期格式化）+ 15 用例 XCTest（翻译源端 DateUtils.test + Pet getSpeciesName/getGenderName）；⑦Route 枚举扩展 `.timeline` + RootTabView 路由串联。架构差异：源端 FAB + 页面级 Sheet → iOS toolbar/按钮 + SwiftUI `.sheet`；源端日期字符串 → iOS `DatePicker` 直接绑定 `Date?`。头像裁切/视觉特征注册后置 V1.x（依赖图片编辑器 + CLIP 模型）。**编译通过 + 296 用例全绿（新增 PetDisplayLogicTests 15 个）**。

### P3/P4 进度（2026-08-09 收口）

- 2026-08-09：**P3 档案内照片分类 + P4 宠物卡片生成落地**——①**P3 照片分类**：`PetPhotoCategory`（全部照片/待整理/作品，UI-DESIGN.md §6.4 可靠维度）+ `PetPhotoCategoryLogic` 纯逻辑（全部=宠物照片 / 待整理=未归属照片 / 作品=编辑产物）；`PhotoRepository.getUnassignedPhotos`（pet==nil 谓词 + 拍摄时间倒序 + limit）；`MediaLifecycleService.saveEditedPhoto` 自动打 `Photo.category=edited`「作品」标记（编辑产物分类唯一来源）；`PetProfileView` 照片区改分段 chips（FilterChip 新共享组件，含计数 + 作品角标 + 空态文案）；`ImportService` 分类字面量收敛到 `PhotoCategory.petPhoto` 枚举。新增 8 用例（PetPhotoCategoryLogicTests 6 + MediaLifecycleServiceTests 编辑标记断言 1 + 仓储查询 2 合并计入）。V1 不做自动「幼年/玩耍/睡觉」分类（无可靠模型来源）。②**P4 宠物卡片生成**：`PetCardLogic` 纯逻辑（文案组装：宠物名/物种·年龄/「来到家 N 天」优先、拍摄日期回退、无宠物通用文案 + 4:5 模板参数）+ 8 用例 XCTest；`PetCardView`（预览=导出同源 `PetCardArtwork` 排版，ImageRenderer 渲染 1080×1350 PNG，保存相册/系统分享）+ `PetCardPhotoPickerView` 选照片页 + CreateView 入口 + Route `.petCardPhotoPicker`/`.petCard` + RootTabView 路由串联。源端无对应功能（3D 手办不在 V1 范围），iOS 自研 MVP。**本机验证：xcodegen + xcodebuild 编译通过；完整 XCTest 见下方汇总**。

### P5 进度

- 2026-08-09：**严格并发开启 + 分层收敛（ViewModelFactory）**——①**SWIFT_STRICT_CONCURRENCY=complete**：`project.yml` 开启完整并发诊断（Swift 5 语言模式）；`ThumbnailImage` 的 `Task.detached` 改捕获 path 值（String, Sendable）不再捕获非 Sendable 的 self；审计确认 `@unchecked Sendable` 8 处均为平台适配/mock 且附理由注释、`static var` 仅剩 EnvironmentKey 注入点与 Schema 元数据。②**ViewModelFactory 组合工厂**：新增 `MiLens/App/ViewModelFactory.swift`（@MainActor，随组合根注入 `\.viewModelFactory`），9 个 View（Home/Gallery/Editor/PetEdit/PetProfile/BeadPhotoPicker/PetCardPhotoPicker/PetCard/PhotoView）改为经工厂取 VM 或轻量数据（photoList/photo/pet/photosByPet/unassignedPhotos），View 层不再持有任何 Repository 依赖；`sandboxDir` 拼装与编辑器 in-memory 兜底从 View 移入工厂（语义不变）；`GalleryViewModel`/`HomeViewModel`/`EditorViewModel`/`PetEditViewModel` 构造点全部收敛到工厂；`FallbackContainer` 提升为 internal 供工厂默认值复用。**验证**：本机（Windows）无法编译 iOS，首次开启 complete 需 macOS CI 编译验证；预留遗留清单——`BeadViewModel` 4 处 `Task.detached`（@MainActor VM 内 detached 调用实例方法，用户改动完成后收敛，CI 错误清单跟踪）、`HomeView` 2 处 `static let DateFormatter`（Swift 5.9 complete 不检查，SE-0412 于 5.10 生效，列为 Swift 6 语言模式迁移前置项）；未动用户进行中的 Pro 门控宠物数量改动（BeadPatternView/CreateView/PetsView/TimelineView 下批收敛）。

- 2026-08-09：**评审阻塞修复全部落地（编辑产物备份分区 / Photos 取消桥接 / 权益注册表取消墓碑 / View 注入全收敛 / UI Test+measure / 本地化规范化）**——①**编辑产物备份分区（backup01）**：`IOSFileStorage` 按可重建性分区——`Documents/MiPhotos/` 导入副本可重建，继续排除备份；`Documents/MiPhotos/Edits/` 编辑产物不可重建，**取消备份排除**（允许 iCloud/iTunes 备份），避免设备恢复后「数据库记录仍在、图片文件缺失」；`auditOrphans`/`destroyPersistentStore` 覆盖两目录 + 2 用例。②**Photos 取消桥接竞态（photo02）**：`IOSPhotoLibraryAccess` 改为注入 `PHImageRequesting` 适配协议（测试注入 mock）；`RequestIDBox` 锁保护原子状态（cancelled/completed/requestID），`set()` 记录取消墓碑——取消先于 request ID 写入到达时立即取消新 ID，`didResume` 加锁；`requestImage`/`requestImageDataAndOrientation` 的 cancelled/error/degraded/continuation 单次恢复路径完整覆盖；新增桥接测试。③**权益监听注册表取消墓碑（entitle03）**：`ProEntitlementStore.ListenerRegistry`（actor）保存取消墓碑 `cancelledIDs` + `activeCount`——cancel 先于 register 到达时后续注册立即取消，已结束任务不再被重新写入注册表（消除残留）；`MockStoreService.finishUpdates()` 供测试终止流；新增 4 个生命周期用例（取消移除已注册任务 / 取消先于注册取消迟到注册 / 立即释放清空注册表 / 流立即结束清空注册表）。④**View 注入全收敛（view04）**：上条预留的 BeadPatternView/CreateView/PetsView/TimelineView 下批收敛完成——`BeadViewModel` 的 clipService/poseService 改窄协议 `(any ClipInference)?`/`(any PoseInference)?`，`ViewModelFactory` 新增 poseService + `makeBeadViewModel`/`makePetProfileViewModel`/`makeTimelineViewModel`/`allPets`，`AppDependencies` 传入 poseService；View 层 Repository 环境注入清零（Grep 确认无 `\.photoRepository`/`\.petRepository` 残留），非 Repository 的 `\.proEntitlement`/`\.notifyService` 仍由页面读取（与 Settings/Paywall 一致）。⑤**UI Test target + measure 基准（uitest05）**：新增 `MiLensUITests`（bundle.ui-testing，TEST_TARGET_NAME=MiLens，bundle id com.milens.app.uitests）——4 Tab 冒烟 + 宠物/创作空状态导航用例，`launchEnvironment["XCTestConfigurationFilePath"]` 注入触发 App isTesting 路径（in-memory + 跳过 onboarding）；新增 `MeasureBaselineTests` 2 个 measure 基准（drawBeadPattern 29×29→232×232、cropPixelsToSquare 1080²→900²，首次运行无基线不失败）；`project.yml` scheme test targets 加 MiLensUITests，MiLensTests 加 MiLensKit package 依赖。⑥**本地化规范化（i18n06）**：`Localizable.xcstrings`/`InfoPlist.xcstrings` 规范化 + 删除 33 个真死 key（17 完全无引用 + 14 插值形式残留 + 3 注释/无引用，含 `paywall.benefit.create/export`）；`localization.py` check 新增 `extract_literal_texts` 字面量识别（`\n`/`\"` 转义还原），消除 Text 字面量与动态 key 误报；**check 全绿：Localizable 144 key + InfoPlist 3 key，0 格式问题 / 0 缺 key / 0 多余 key**。**验证**：WSL2 Swift 6.1.3 `swift test` **594/594 全绿**；App 层 170 个 .swift 文件（含 MiLensUITests/MeasureBaselineTests）`swiftc -parse` 全过；`localization.py check` exit 0（Localizable 144 + InfoPlist 3）；`git diff --check` 干净；UI Test/measure 执行与 App 编译需 macOS Xcode（本机 Windows 无 iOS SDK，未执行）；DESIGN.md §4.1/§7 已同步。

- 2026-08-09：**评审高优先级+中优先级修复全部落地（App Store 发布准备）**——①**App Icon**：`AppIcon.appiconset` 补齐 1024×1024 PNG（此前只有 Contents.json 声明，Archive/提审无法形成合格图标资产）；②**CI 模型顺序**：app/release 两作业均改为「缓存/下载模型 → 校验 → xcodegen generate」并新增 `tools/assert-built-models.sh` 构建产物断言（`xcodegen` 在模型存在前生成工程会导致 `.mlpackage` 不进 Resources Build Phase，正式包静默降级 Vision）；③**覆盖率门禁单位修复**：`check-coverage.sh` 此前拿 xccov 的 0…1 小数直接与 30/25/30 基线比较导致恒失败，改为乘 100 统一百分比并新增 `--selftest` 固定 fixture 自测（等于基线 PASS / 低于基线 FAIL 双向守护）；④**隐私声明与 Apple 定义对齐**：`PrivacyInfo.xcprivacy` 移除 `NSPrivacyCollectedDataTypes`（照片仅本机处理不算「收集」、StoreKit/崩溃日志由系统处理无需披露），`docs/AppStore-metadata.md` 问卷改为「不收集数据」，并确认无自建崩溃上报服务；⑤**SwiftData 事务封装**：新增 `ModelContext.saveOrRollback()`（save 失败即 rollback 清理 pending changes 并重抛），`PhotoRepository`/`PetRepository` 全部写路径接入，`MediaLifecycleService.saveEditedPhoto` 失败恢复完整旧属性（含 `category`），新增磁盘 store 唯一约束冲突回归测试（冲突后下一批导入继续成功）；⑥**Pro 权益保活环解除**：`ProEntitlementStore` 监听任务改 `[weak self]` + 每次迭代短暂持有，静态任务注册表 actor 化（`ListenerRegistry`，消除 deinit 数据竞争与「静态字典 → Task → self」保活环）；⑦**Photos 适配器完整桥接**：`IOSPhotoLibraryAccess` 去 KVC（文件名改 `PHAssetResource.originalFilename`），`requestImage`/`requestImageDataAndOrientation` 全量接入 degraded 忽略、cancelled/error 识别、continuation 单次恢复、`withTaskCancellationHandler` + `cancelImageRequest`（扫描取消后 iCloud 下载请求随之停止）；⑧**备份排除**：`IOSFileStorage` 对 `Documents/` 下媒体副本设置 `isExcludedFromBackup`（可重建大媒体排除 iCloud/iTunes 备份，逐文件设置不阻断写入）+ 2 用例；⑨**localization.py UTF-8**：入口内置 stdout 重配置，Windows GBK 控制台无需 `PYTHONUTF8=1` 即可输出 `−` 等字符（本机验证 exit 0）。**验证**：本机无法编译 iOS App（Windows 无 iOS SDK，App 层编译/测试待 CI）；`tools/check-coverage.sh`/`tools/fetch-models.sh`/`tools/assert-built-models.sh` 为 bash 脚本需 macOS runner 实测；SwiftData 回归测试（PhotoRepositoryTests/PetRepositoryTests/MediaLifecycleServiceTests 增补）与 RouteTests 待 CI 执行。

- 2026-08-09：**Pro 权益规则收口（ADR-0009）**——免费版 1 个宠物档案/每日 5 次拼豆/最近一年时间线，Pro 版 20 个档案/不限拼豆/完整历史；基础图片编辑器与宠物卡片保持免费，高级模板和高清导出标为 V1.0 计划，新增配额与时间线门控测试。
- 2026-08-09：**内购服务 + Pro 权益门控 + 首页/设置/引导 v2 UI 落地**——①**StoreKit 2 服务**：`StoreService` 协议 + `StoreKit2StoreService`（`Transaction.updates` 监听/购买/恢复）+ `MockStoreService`；`ProEntitlementStore`（应用级权益唯一消费方，RootTabView 冷启动 `refresh()` 校准，`deinit` 经静态注册表取消订阅 Task）+ `ProStatus`；`PaywallLogic`/`PaywallViewModel` + `PaywallView`（三档产品展示/购买/恢复）+ `StoreKitConfigurationTests`/`PaywallLogicTests`/`PaywallViewModelTests`/`ProEntitlementStoreTests`（git 078482e/310222c，产品文案 `Products.storekit`）。②**首页 v2 编辑式布局**：`HomeView`（hero 大图 + 往日回忆 + 空态，杂志式排版）+ 拼豆工作室视觉优化（git f85e22f）。③**UI v2 重构**：创作页/设置页组件（bea5b2f）+ 引导页视觉（bf23ce2）按 UI-DESIGN.md v2.0 迁移，v2 token 全部代码化（`Color+Theme.swift`）。④**App Store 元数据**：`docs/AppStore-metadata.md` 定稿（描述/关键词/订阅产品/审核备注/隐私问卷），隐私政策草稿 `docs/privacy-policy.html`（git 61abdeb/a22ddba/2d5cf9c）。
- 2026-08-08：**首页逻辑层落地**——`HomeViewModel` + `HomeHeroLogic`（选片/今日判定/文案）+ `HomeMemoryLogic`（往日回忆选片）+ `HomeGreetingLogic`（时段问候）纯逻辑与测试（git d6e9ec5，MiLensKit 支持 macOS 平台 e2c00c3 同期）。

- 2026-08-09：**上架流水线代码落地（release 作业）**——`.github/workflows/ci.yml` 新增 `release` 作业：`workflow_dispatch` 手动触发（inputs：`version`=MARKETING_VERSION / `buildNumber`=CURRENT_PROJECT_VERSION / `upload`=是否上传 ASC），`needs [kit, app]` 质量门禁；流程 = xcodegen → `fetch-models.sh`（模型缓存复用）→ `.p8` 写入 `~/private_keys` → `xcodebuild archive`（`-authenticationKey*` API Key 自动签名 + `-allowProvisioningUpdates`，无需钥匙串）→ `-exportArchive`（app-store ExportOptions，uploadSymbols）→ `xcrun altool --upload-app`（iOS 不需要 notarytool 公证）→ artifact 留存 IPA + xcarchive。Secrets 约定：`ASC_API_KEY`/`ASC_API_KEY_ID`/`ASC_API_ISSUER_ID`/`ASC_TEAM_ID`，`.p8` 生成与配置说明见 [DEVELOPMENT.md](DEVELOPMENT.md) §2.2。**未实测**：本月 CI 额度用完，需配置 Secrets 后手动触发（建议先 `upload=false` 验证签名 IPA，再正式上传）。

- 2026-08-09：**本机 macOS 全量验证（高优先级修复前基准）**——`xcodegen generate` + `xcodebuild build`（`SWIFT_STRICT_CONCURRENCY=complete`）**BUILD SUCCEEDED**；MiLensKit `swift test` **594/594 全绿**；MiLens App `xcodebuild test` **604/604 全绿、0 失败**（含修复 `ProEntitlementStoreTests.testStreamPushStillUpdatesStatus` flaky——独立 `ListenerRegistry` 隔离 `ObjectIdentifier` 复用致取消墓碑误杀）；MiLensUITests 2 冒烟用例；`localization.py check` 全绿（Localizable 150 + InfoPlist 3）。该快照早于 2026-08-10 高优先级修复，不能替代当前 HEAD 的 macOS 验证。

- 2026-08-10：**高优先级缺陷修复**——5 项代码修复 + 测试补充（详见 DEVELOPMENT.md 验证快照）：①ImportService 重复照片误算配额→候选列表优先去重再算配额；②ProEntitlementStore 墓碑误杀→UUID 令牌 + 条件墓碑；③BeadViewModel `Task.detached` 读取 `self.isPro`→提前捕获 Bool；④GalleryView/CreateView 缩略图陈旧→`.task(id: path)` + 清除旧图；⑤SharePreviewSheet 3 处字面色→品牌色 token。`check-ui-tokens.py` / `localization.py check` 本地全绿；App 编译与测试待 macOS CI 验证（未执行）。

- 2026-08-09：**并发遗留收口确认（审计复核）**——P5 严格并发条目预留的 `BeadViewModel` 4 处 `Task.detached` 遗留经审计核实**已收敛**：4 处 detached（生成/导出/分享/PDF）均已改为以捕获 `Sendable` 局部值（`renderer`/`pattern`/`photoData`/`opts`）的方式传参，闭包内调用全局生成/渲染函数（`generateBeadPatternAsync`/`generateBeadPatternAutoAsync`/`BeadExportService.render*`），不捕获非 Sendable 的 `self`。验证：`SWIFT_STRICT_CONCURRENCY=complete` 下 `xcodebuild` BUILD SUCCEEDED。文档同步：DESIGN.md §9.1 与 DEVELOPMENT.md §4.2 的「已知遗留」描述已更新为「并发遗留收口」，仅剩 `HomeView` 2 处 `static let DateFormatter` 作为 Swift 6 语言模式迁移前置项。

### P5 进度（ADR-0010 商业化强化）

- 2026-08-10：**商业化强化与情感触点规划落地（ADR-0010）**——产出 [ADR-0010](docs/adr/0010-commercialization-and-emotion-triggers.md)，系统性扩展权益矩阵、定价、水印、分享、情感触点、编辑器装饰、离线备份、相簿模式、实体打印 9 大模块。

  **已实现（P0 全部）**：①**照片导入配额**（免费 50 张 / Pro 不限）：`CommercialRules.swift` 新增配额常量 + `allowedImportCount` 纯函数；`ImportService` 导入前配额检查 + `quotaBlocked` 计数；`GalleryViewModel` 配额拦截弹付费墙；`GalleryView` 注入 Pro 状态 + 同步；6 个边界用例。②**导出水印**（免费带水印 / Pro 无水印）：MiLensKit `BeadExportService.renderA4Export` 增 `includeWatermark` 参数（A4 页脚 ASCII 位图字体，水印文本 `Made with MiLens | milens.app`）；App `BeadExportService` 贯穿 PNG/PDF；`BeadViewModel` 导出传 `!isPro`；`PetCardArtwork` 底部渐变区水印条件渲染。③**买断定价** ¥298→¥168：`Products.storekit` displayPrice 同步。④**分享增强**：新建 `SharePreviewSheet`（引导式分享预览面板，平台图标横排 + 「更多平台」→ 系统 ShareSheet），接入 `BeadPatternResultView` + `PetCardView`。

  **已实现（P0-e/f）**：⑤**宠物卡片多模板**：MiLensKit `PetCardTemplate` 枚举（经典免费 / 拍立得 / 杂志 / 极简 Pro）+ `isUsable(isPro:)` / `resolve(_:isPro:)` 门控；`PetCardArtwork` 重构为 4 个独立排版分支；`PetCardView` 底部模板选择器（水平滚动 + 缩略图 + Pro 锁标）+ `@AppStorage` 持久化。⑥**时间线导出分享**（Pro 专属）：`TimelineExportLogic` 纯函数（从 months 构建导出数据）+ `TimelineExportCanvas`（1080px 离屏渲染视图，头部 + 按月分组 + 时间线节点）+ `TimelineView` 导航栏「分享」按钮 + Pro 门控。

  **接口预留（数据模型锁定）**：⑦**编辑器装饰**：MiLensKit `DecorationCatalog`（边框/贴纸资源目录 + Pro 门控元数据，复用已有 `EditorLayerType.frame/.sticker`）。⑧**实体打印**：`MiLens/Services/Print/PrintService.swift`（协议 + `PrintProductType`/`PrintProductSpec`/`PrintQuote`/`PrintOrder` 数据模型 + `UnavailablePrintService` 占位）。⑨**离线备份**：`MiLens/Services/Backup/BackupService.swift`（协议 + `BackupManifest`/`BackupMetadata`/`PetSnapshot`/`PhotoSnapshot` 数据模型 + ZIP 打包格式定义 + `UnavailableBackupService` 占位；方案选定 A（ZIP + ShareSheet）核心 + B（iTunes File Sharing）补充，排除 C（系统相册丢元数据）和 D（iCloud 违背不联网约束））。⑩**相簿浏览模式**：MiLensKit `GalleryMode` 枚举（网格免费 / 剪贴簿 / 拍立得散页 / 杂志 Pro）。

  **Pro 权益扩展**：`ProFeature` 新增 `.photoStorage` / `.watermarkFreeExport` / `.cardTemplates` / `.timelineExport` / `.offlineBackup` / `.albumModes` 6 个权益项 + 对应本地化字符串。
