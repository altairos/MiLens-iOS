# MiLens iOS 迁移计划

最后核对：2026-08-16（相框贴纸 M0/M1 收口：素材缺失诊断 + App 渲染级单测 + 文档状态刷新；PLAN 待办收缩并整合用户 V1.0/V1.X 清单；CI 全绿基线 run 31931944133 四作业 2062 用例；此前 2026-08-12：Figma 12 页 Release Candidate 设计稿落地推进中：07·我的、03·生命时间线、01·首页 三页已落地 Ledger 编辑式设计语言，含 PetEvent SchemaV2 扩展 + TimelineLogic 文本记忆/作品记录类型 + 首页纪念日倒计时；Windows 环境代码就绪，编译/UI/真机验证待 Mac；其余状态同前：情感触点系统 Stage 1–3 + 创作 Tab 新增「宠物名片」「红包封面」两个项目落地；纯决策逻辑全量下沉 MiLensKit，WSL2 `swift test` 全绿（MiLensKit 823 用例）；规模守卫审计拆分落地（6 个超标 View 全部降至 <600 行：TimelineView 1126→539 / PetProfileView 717→584 / GalleryView 704→437 / SettingsView 702→576 / BusinessCardView 687→392 / BeadPatternResultView 607→488，新增 8 个组件文件 + Date+Epoch 共享常量 + ShareItem/ShareSheet 通用组件归位 Components/），编译验证待 Mac；App 层渲染与集成代码已随 CI 编译验证（四作业全绿，run 31931944133），真机/视觉走查项详见 [docs/情感触点-Mac待办备忘.md](docs/情感触点-Mac待办备忘.md)；P0–P4 状态全量同步；P5 首页/设置/订阅/付费墙/元数据已实现 + 上架流水线代码落地待实测；评审高优先级+中优先级修复全部落地；严格并发开启 + ViewModelFactory 分层收敛 + 评审阻塞修复落地；Figma Direction D「Memory Orbit」底部导航已接入真实 SwiftUI；本地化：工具链 plural + 动态文案 10 类收口 8 类，catalog 269+3 key，源语言检查全绿，其他 6 个首发语言仍待翻译；剩性能基准、截图、iPad/深色检查与真机验收，见 [P2-待办清单](docs/P2-待办清单.md)；本地导出功能体验补强落地（备份导出预预估+确认/阶段进度文案/isAvailable兑底/.milensbackup UTType 限定 + 作品保存统一成功反馈 ExportToast + 创作/设置页硬编码文案迁移 xcstrings 50 key，详见 P5 进度 ADR-0010 条 2026-08-12）

> 里程碑与任务清单。架构见 [DESIGN.md](DESIGN.md)，映射与范围见 [MIGRATION_ASSESSMENT.md](MIGRATION_ASSESSMENT.md)，约束见 [AGENTS.md](AGENTS.md)。

## 里程碑总览

| 阶段 | 名称 | 目标 | 状态 |
|---|---|---|---|
| **P0** | Harness 与规划 | 文档骨架、约束、目录结构、XcodeGen 声明、范围对齐 | ✅ 已完成 |
| **P1** | 地基 + 算法核心 | Xcode 工程可编译、SwiftData schema、拼豆 Swift 核心（黄金规格通过）、AI 路线定案 | ✅ 已完成（含 2026-08-09 可靠性收口） |
| **P2** | 相册 MVP | 扫描发现（+质量评分/重复分组）+ 手动导入 + 相册网格 + 大图查看 | 🟡 实现完成，真机/性能验收待做 |
| **P3** | 宠物档案 | 档案 CRUD + 成长时间线 + 纪念提醒 | 🟡 基础能力已完成；生命档案增强设计已冻结，待实现 |
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
- [x] Figma Direction D「Memory Orbit」底部导航落地：350×70 浮层、四套固定矢量路径、无可见文字、浅/深色 token、VoiceOver Selected 状态与稳定 UI Test 标识；页面生命周期仍由系统 `TabView` 管理
- [x] Figma 可复用组件库定稿（2026-08-12）：主行动、`Navigation/Memory Orbit`、偏好行、拼豆控件，以及 `Data/Archive Stat`、`Surface/Archive Panel`、`Surface/Identity Strip` 共 12 组组件已建立变量、变体、可编辑属性和使用边界，并以实例回写 Release Candidate / Dark Mode / Applied / Core Flow / iPad Adaptive Layout；节点与代码映射见 [UI-DESIGN.md §5.6](UI-DESIGN.md#56-figma-可复用组件契约2026-08-12)
- [x] Figma iPad 自适应参考稿完成（2026-08-12）：[`13 · Adaptive Layout · iPad`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=306-669) 包含档案双栏、拼豆设置双栏、拼豆结果检查器及结果深色稿；834×1194pt 画板均显式保留顶部 24pt / 底部 20pt 参考安全区，组件与内容无越界。代码仍须使用实时 safe area、size class 与可用宽度决策
- [x] **iPad 自适应布局代码实装完成（2026-08-12）**：基于节点 306:669 为 3 个核心页面落地 `horizontalSizeClass == .regular` 门控的双栏分栏——①`PetProfileView` 左肖像列（376pt）+ 右档案列（390pt），新增 `continuityNote` 与 `timelineContinuation`；②`BeadPatternView` + `BeadSettingsPanelView` 左源工作区（408pt）+ 右参数检查器（354pt），`BeadSettingsPanelView` 拆出 `sourceContent`/`inspectorContent` 供双栏复用；③`BeadPatternResultView` 左画布列（408pt）+ 右导出检查器列（354pt），新增 `outputFormatsPanel`。`Theme.swift` 新增 `AdaptiveColumn` 列宽 token。compact（iPhone）单列布局与交互完全不变；拼豆工作室保持 `.dark` 暗房隐喻。色值已全量 token 化，暗色模式自动适配
- [x] Figma 12 页 Release Candidate 定稿与字号审计完成（2026-08-12）：目录 `01–12` 已覆盖首页、伙伴档案、时间线、图库、创作、Paywall、我的、照片详情、添加记忆、拼豆结果、拼豆设置与拼豆生成；重点流程的浅/深色稿已统一为生命档案纸、显影记录和精确输入轨语法。交付范围 743 个文本节点均不小于 10pt，正文/交互文字不小于 11pt；最终 12 张主稿的 224 个文本节点无缺失字体、截断或越界，顶部 47pt、底部 34pt iPhone 参考安全区及 44×44pt 顶部操作控件已校正，四个 `Memory Orbit` 实例的命中区域止于 Home Indicator 参考区上沿。节点与实现边界见 [UI-DESIGN.md §5.7](UI-DESIGN.md#57-重点流程精修与字号验收2026-08-12)
- [x] 按 2026-08-12 Figma 组件 [`Navigation/Memory Orbit`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=272-582) 更新 `MemoryOrbitTabBar`：悬浮胶囊改为贴底安全区材质平面（`.bar` 背景）；选中短刻度改为精确深铜红直线（20×2.5pt）；圆形轨道以三层矢量弧（`orbitLayer1/2/3`）实现右深粗、左浅细的锥度和约 0.34–0.38s path trim 动效；Reduce Motion 直接显示最终态。RootTabView 同步移除 capsule padding。**未执行**：iPhone/iPad、浅/深色截图测试（需 Mac）
- [x] 按 2026-08-12 Figma Action 组件实现 `PrimaryActionMaterialStyle` 及三种语义变体：`FocusDialButton`（已有，加入记忆/保存）+ `ContactProofButton`（已有，扫描/导入）+ **`DarkroomPulseButton`**（新建，暖黑动作面 + 珊瑚曝光边 + 微型直方图 + Generate/Export 两语义）+ **`PrimaryActionMaterial`** 统一分发器；BeadSettingsPanelView 生成按钮已切换到 `DarkroomPulseButton`。**未执行**：浅/深色、Reduce Motion、iPhone/iPad 截图测试（需 Mac）
- [x] 将设置页 01–02 落实为 `PreferenceRow`（Toggle On/Off、Disclosure）：新增 `PreferenceRow` 组件（Figma `Control/Preference Row` #275:522），`PreferenceRowMode` 枚举映射 Toggle On/Off/Disclosure；Toggle 使用 SwiftUI 原生行为与 `.tint(milensActionPrimary)`，Disclosure 用 Button/NavigationLink 语义；SettingsView 已有 LedgerRow 调用模式与之兼容
- [x] 按控 Figma Studio 控件组件校准 `BeadSettingsPanelView`：内联 identityStrip 已切换到可复用 `IdentityStrip` 组件（#299:615 契约）；生成按钮已切换到 `DarkroomPulseButton`；尺寸保持 15/29/52/78 固定四档不变。`BeadPatternResultView` 保留现有 Identity Strip 结构。**未执行**：浅/深色、Dynamic Type、VoiceOver 和 44pt 命中区截图/交互测试（需 Mac）
- [x] 按 Figma Surface/Media 组件落实 `ArchiveStatView`、`ArchivePanel` 与 `IdentityStrip`：新增 3 个可复用组件到 `ArchiveComponents.swift`（对照 #295:587 / #296:629 / #299:615）；`ArchiveStatItem` 已收敛到 `ArchiveStatView`；`BeadSettingsPanelView` identityStrip 已复用 `IdentityStrip`。`ArchivePanel` 作为连续档案纸容器已就绪供 PetProfileView 后续使用。图片走可访问性标签与异步缩略图，文字支持 Dynamic Type。**未执行**：iPad 按可用宽度重排真机验证（需 Mac）
- [x] v1 主题 token 已代码化；[UI Rework v2.0](UI-DESIGN.md) 已重新审计并修订动作色、字体边界、响应式和组件规格。**v2 迁移已落地（2026-08-09）**：v2 token（`ActionPrimary`/`AccentSoft`/`Border` 等）已代码化进 `Color+Theme.swift`，首页/创作/设置/引导页均按 v2 重构（git bea5b2f/bf23ce2/f85e22f），操作层用系统字体、文楷仅作稀缺情感标题
- [x] 本地化 String Catalog（`Localizable.xcstrings` + `InfoPlist.xcstrings`，源语言简中，结构支持任意语言；`String(localized:)` API）；`tools/localization.py` 导出/导入/校验工具；App Icon / 占位图待源端资源整理后补

### P1.2 数据层

- [x] SwiftData `@Model`：`Pet` / `Photo` / `PetEvent`（参照评估报告 §3 + 源端 ER，UUID 业务标识）
- [x] `VersionedSchema` v1 + 空 `SchemaMigrationPlan`
- [x] SchemaV2 扩展（2026-08-12）：PetEvent 新增 `body`/`sourceType`/`isPinned`/`relatedPhotoID` 四字段（Life-Archive-Design.md P0），lightweight migration 自动处理；`SchemaV1`→`SchemaV2` 迁移 stage 接入 `MiLensMigrationPlan`，App 与 Fallback 容器切换到 V2
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
- [x] **通知真调度**：`NotificationPosting.schedule`（`UNCalendarNotificationTrigger`）+ `NotifyService` 幂等重调度（生日/成为家人的日子年度 09:00 + 100/365/730/1000 天里程碑单次提醒 + 时光机每日 09:00）+ 设置开关（默认关闭，授权放开关路径）+ 宠物编辑/删除局部更新
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
- [x] **引导流程「First Archive」重构（2026-08-12）**：基于 Figma [相册扫描与配额付费墙原型](https://www.figma.com/design/AIvvJIkGKl3celR6H8TxPg) node 47:2「Onboarding · First Launch」11 画板，将旧 4 步引导重构为 10 step / 4 大阶段编辑式流程：欢迎(空态→隐私摘要) → 建立档案 → 特征注册(选图→处理→完成) → 全面扫描 → 候选确认 → 导入中 → 导入成功。流程顺序关键变更：**先建档→特征注册→再扫描**（让扫描有特征基准可比对）。新建 `OnboardingEditorial.swift` 共享组件库（`FocusDialButton` 机械拨盘式主 CTA / `ContactProofButton` / `EditorialSection` / `EditorialCard` / `RegisterMark` / `WaypointRow`）；重写 `OnboardingViewModel`（10 step 枚举 + `majorStage` 进度映射 + `OnboardingImportExecutor` 闭包注入导入编排）；7 个 step 视图（Welcome/Privacy/CreateArchive/FeatureRegister 3 子状态/FullScan/Candidates/Import 2 子状态）；`AppDependencies` 注入导入执行器（复用 ImportService + assignPhoto 链路）；新增 `BrandSeal.imageset` 品牌印章资源；测试重写 18 用例。Focus Dial 为 SwiftUI 近似还原（铜红 surface + 拨盘圆 + 三段刻度弧 + glyph），非逐像素 SVG。**未执行**：App 编译/XCTest/Xcode Preview/真机授权弹窗验证需 Mac；像素级偏差见 [docs/Figma页面与素材交付备忘.md](docs/Figma页面与素材交付备忘.md) §4.1 核查记录
- [x] P0 修复：`IOSFileStorage`（FileManager 真实实现）注入组合根，替代内存 Mock——导入/编辑产物真正落盘，重启不丢
- [x] P0 修复：去重字段改 `Photo.originalURI`（Photos localIdentifier，`@Attribute(.unique)` 约束）+ 仓储 `getPhotoByOriginalURI`/`getAllOriginalURIs` + ScanService/ImportService 按 originalURI 去重（含批次内重复 identifier）
- [x] P0 修复：`ScanCursorStore`（UserDefaults）持久化上次成功扫描时刻，增量扫描不再用 `Date()` 截止；dateAdded 以 creationDate 近似并诚实标注（iOS 无公开「加入相册时间」API）
- [x] P0 修复：CLIP Phase 2 精筛接入扫描（`ClipInference` 协议 + 失败降级），App Store 文案去除「按宠物分别归类」不实描述
- [x] P0 修复：**SwiftData 测试进程崩溃根因修复**（ModelContainer 悬垂）——`container.mainContext` 不持有 container，测试 helper 局部 container 返回后释放，repo fetch 触发 SwiftData 内部 SIGTRAP（此前 XCTSkipIf 掩盖，CI/本地间歇崩溃）。修复：测试 helper 返回并持有 container（ImportServiceTests/ScanServiceTests/QualityScorerTests 全部调用点）；`RepositoryEnvironment` fallback 改 static 缓存容器。恢复 QualityScorerTests 运行（移除 XCTSkipIf）。本机完整 XCTest 400/400 通过
- [ ] 真机验证：Photos 权限 + Vision/Core ML 推理 + 分页性能 + PhotoView 下滑手势（需 Mac + iPhone，详见 [P2-真机验证备忘](docs/P2-真机验证备忘.md)）
- [x] **扫描导入流程重设计（2026-08-12）**：基于 Figma [相册扫描与配额付费墙原型](https://www.figma.com/design/AIvvJIkGKl3celR6H8TxPg) 实装完整的多步骤扫描导入流程——新建 `AlbumScanFlowView`（fullScreenCover 容器）驱动 6 阶段状态机（扫描→候选→选择宠物→导入→成功/额度用尽），内含 6 个新视图：`AlbumScanStageView`（01/04 扫描/导入中，暗房画布 + 扫描线动画 + 步骤列表）、`AlbumCandidateListView`（02/06 候选网格 + 选择状态 + 额度提示条）、`AlbumPetSelectView`（03 Evidence Register + 宠物行列表 + Import Register）、`AlbumImportSuccessView`（05 归档卡片 + 本地隐私证明）、`AlbumQuotaExhaustedView`（07 Quota Card + Resilience Register 3 行保证）。`GalleryViewModel` 扩展 `candidateURIs`/`scanProgressPercent`/`importProgressPercent`/`importCandidates(identifiers:targetPetID:)` 接口；`ViewModelFactory` 新增 `loadCandidateThumbnail`（系统缩略图加载）；`PaywallView` 对齐 Figma #37 更新权益文案与方案价格显示。`GalleryView` 空状态扫描入口改为触发 fullScreenCover。ScanService / ImportService 核心逻辑零改动
- [x] P1 可靠性遗留 3 项收口：引导扫描游标（OnboardingViewModel 仅 `completedSuccessfully` 保存）、数据库重建后的沙盒媒体语义（恢复界面文案明确清除范围）、编辑旧文件清理失败策略（引用查询失败保守保留）——实现与单测已落地，详见 [P2-待办清单](docs/P2-待办清单.md)

### 验收标准

- 首次启动流程已实现（First Archive 重构）：建档 → 特征注册 → 扫描 → 候选确认 → 导入 → 相册可见；真机授权与真实照片走查待做 🟡
- 相册支持分页、筛选、多选、大图查看 ✅
- 扫描可取消，不提交过期结果 ✅
- CI/本机编译 + 测试全绿 ✅（CI 首次全绿 [run 31900122759](https://github.com/altairos/MiLens-iOS/actions/runs/31900122759)（2026-08-15）；最新 [run 31905505907](https://github.com/altairos/MiLens-iOS/actions/runs/31905505907)（2026-08-16，P1-4/P2-2 批次后）：严格并发下 macOS runner BUILD SUCCEEDED；MiLensKit 1113（Linux）+ App 943（模拟器）+ UI 6 = 2062 用例 0 failed；lint 四项全过；覆盖率门禁基线回调 18/18/0（App 加权 line/function 21.3%）后 PASS）
- 真机验证（待 Mac + iPhone）—— 待办清单见 [P2-真机验证备忘](docs/P2-真机验证备忘.md)

---

## P3 — 宠物档案

### P3.6 生命档案增强（设计已冻结，待实现）

产品设计与页面目录原型已沉淀到 [docs/Life-Archive-Design.md](docs/Life-Archive-Design.md)，核心方向是把“宠物详情 + 照片列表 + 日期事件列表”升级为可确认、可补写、可回看的长期档案。

- [x] 扩展 `PetEvent`（复用现有 `title`）：增加用户记录正文、日期/日期范围、来源类型、置顶状态、代表照片/关联照片。**✅ 已完成（2026-08-12）**：`body`/`sourceType`/`isPinned`/`relatedPhotoID` 四字段 + SchemaV2 lightweight migration。`sourceType="user" && body` 非空 → TimelineLogic 构建为 `.textNote` 条目（4 用例 XCTest）。
- [x] 从 `PetProfileView`、`TimelineView`、`PhotoViewView` 进入统一的“添加一条记忆”流程；沿用窄协议 ViewModel + Repository 注入。**已完成（2026-08-12）**：TimelineView 悬浮添加按钮 + 完整表单（`AddMemorySheet`）已落地；`PetProfileView` archivePanel 新增“添加一条记忆”入口（`showAddMemorySheet` + `factory.makeTimelineViewModel()`）；`PhotoViewView` CTA 从导航 timeline 改为直接弹出 `AddMemorySheet`（预填充 `prefilledPhotoID` 为当前照片）。`AddMemorySheet` 从 private 提升为 internal 以支持多处复用。
- [x] 档案首页增加记录数、重要日子数、置顶记忆/档案起点和「继续记录」入口。**已完成（2026-08-13）**：PetProfileView 统计行新增 `importantDayCount`（生日+领养日+用户事件）；Eyebrow/Intro 区新增 `archiveOriginDate`（最早事件/照片日期）；新增 `continueRecordingEntry`（Focus Dial 风格 CTA）；`TimelineLogic` 新增 `computeArchiveStats`/`selectPinnedMemory` 纯函数。+4 简中本地化 key。
- [x] 时间线增加照片记忆组、用户记录、作品记录、内容类型筛选和来源标签；节点区分形状/内容结构，不只依赖颜色。**✅ 已完成（2026-08-12）**：TimelineView 重构为 Ledger 编辑式设计（年份选择器 + 章节标记 + 照片记忆大图卡 + 文本记忆浅粉卡 + 作品记录卡），三种条目类型区分形状与内容结构。作品记录已接入真实数据（`sourceType="work"` → `.workRecord` 条目，经 `relatedPhotoID` 回链来源照片缩略图；无来源时回退占位网格）+ 作品记录类型标签。
- [ ] 支持用户命名的相处章节；未命名章节只显示日期范围，不自动臆测宠物生命阶段。**部分完成**：章节标题自动推导（「一起生活的第N年」），`buildDateRangeChapters` 纯函数支持 `customNames: [Int: String]` 参数传入自定义名；UI 层自定义命名输入属 P1。
- [x] 照片详情支持加入已有记忆/新建记忆/补充备注。**已完成（2026-08-12）**：`PhotoViewView` 的拨盘式 CTA 直接弹出 `AddMemorySheet`，预填充当前照片为关联照片。作品保存回链待 V1.x。
- [x] 首页与纪念提醒进入年度回看，支持添加当前年份照片和一句话；不引入 AI 写真或回忆视频承诺。**已完成（2026-08-12）**：首页「即将到来的日子」区块 + 「年度回忆」入口卡片 → `Route.recap` → `RecapView`（年份选择器 + 月度精选网格 + Pro 导出）；`MemoryRecapLogic` 纯逻辑选片。
- [x] 为上述决策逻辑补 XCTest：来源标签、置顶/档案起点、事件关联、日期范围分组、年度回看回链、删除/取消关联边界。**已完成（2026-08-13）**：`TimelineLogicTests` 新增 18 用例——`computeArchiveStats` 4（全字段统计/相伴天数/回退起点/空输入）+ `selectPinnedMemory` 4（优先置顶/回退用户记录/无候选/多候选取最近）+ `buildDateRangeChapters` 4（按年分组/自定义名/自动推导/空输入）+ `buildYearlyRecap` 3（按年过滤/月度代表/空年）+ `importantDayCountAfterRemoval` 2（删除递减/不存在 ID 不变）。

验收基准见 [docs/Life-Archive-Design.md](docs/Life-Archive-Design.md) §6。当前 P3 已实现的 CRUD、基础时间线、提醒和照片分类仍有效，本节是下一阶段增量，不回退现有能力。

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
- [x] 纪念提醒：`UNUserNotificationCenter`（生日/成为家人的日子/相处里程碑）→ `NotifyService` 真调度（年度重复 + 里程碑单次 + 时光机窗口 + 稳定 ID 撤销），平台层 `NotificationPosting` 协议隔离，文案与调度测试已同步
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
- [x] Image Workshop 第一批视觉重做（2026-08-13）：对照 Figma 422:801，编辑器从全黑沉浸式重做为浅色编辑式语言（铜索引条 + WorkshopValueRail 数值滑杆 + 校准线 + Transform Rail）；创作首页改为浅色编号网格；分享预览改为编辑式全屏页 + 系统分享面板。新增 `WorkshopComponents.swift` 组件库与 `.flip` 工具模式。
- [x] Image Workshop 第二批成品系列（2026-08-13）：对照 Figma 422:801 第二批，重做 02 Picker（A/B 角色双选）、07–10 四个成品页（Source 条 + TemplateRail + FieldRow + CreationActionBar）+ 11 上传指引新页（时间线步骤）。新增 `WorkshopNavHeader`/`WorkshopSourceBar`/`WorkshopTemplateTab`/`WorkshopFieldRow`/`WorkshopTimelineStep` 共享组件。12 页全部落地。
- [x] 调色预设滤镜（iOS 端增强，2026-08-13）：调色面板顶部新增 6 款预设滤镜横滚条（原图/鲜明/暖阳/冷调/柔和/黑白），复用 `EditorColorAdjustments` + CIFilter 管线（零新增渲染）；手动 5 滑块默认折叠于「手动调整」入口。预设数据下沉 MiLensKit `EditorFilterPresets`（纯逻辑 + 单测），`matchPresetFilter` 精确匹配回算高亮（手动微调偏离预设自动取消选中）。

**Phase 4：相框与贴纸（M0+M1 代码已落地，素材待补）**

- [x] **M0+M1 代码落地（2026-08-15，[开发计划](docs/Frame-Sticker-Development-Plan.md) §7 M0/M1）**：8 个阻塞项全部修复——装饰图层快照（`EditorLayerSnapshot` 扩展 `resourcePath`/`visible`，旧 JSON 容错）、画布重映射（`remapLayersForCanvas`：frame 重铺满/贴纸归一化迁移 + 钳制）、预览与导出一致（共用 `orderedRenderLayers` 稳定序 photo→frame→sticker→text 与 `resolveDecorationResource`（DecorationAssetResolver.swift）三 fitMode 解析）、命中排除相框（`selectLayer` 仅 sticker/text）；MiLensKit 新增 `DecorationComposition`（贴纸钳制 8%–70% 短边 + 上限 `STICKER_LAYER_LIMIT=20`）、装饰默认几何（frame 铺满/贴纸 22% 短边右上偏移 + 堆叠落点）与分组稳定 ID `DecorationGroupIds`（recommended 恒首位）；M1 交互：`EditorDecorationPanelVM`（分组浏览按类别记忆/相框单选替换整体一次 push/Pro 锁定触发付费墙）+ `EditorDecorationPanelView`（60×56pt 三态素材单元 + 真实空态）+ 工具入口门禁（`hasFrameItems`/`hasStickerItems`）+ 本地化 14 key + `frame_import.py` 分组 ID 校验。MiLensKit 测试 WSL2 全绿（1104 用例）；App 测试 `EditorViewModelTests` +9 用例**未执行**（Windows 无 Mac，待 CI/Mac 验证）。2026-08-15 复核：8 阻塞项与交互链路全部属实；遗留缺口——①素材错误诊断未达开发计划 §7.2（导出素材缺失静默跳过仍报成功）；②App 渲染级单测未写（现有为 VM 级），均已建待办跟踪。
- [x] **M2 质量项：拖动吸附/参考线/可访问性（2026-08-15，[开发计划](docs/Frame-Sticker-Development-Plan.md) §8 M2）**：①MiLensKit `DecorationComposition` 新增 `snapAndClampLayerCenter` + `LAYER_SNAP_THRESHOLD=6pt`（进入阈值吸附画布中心线、离开立即释放无滞后、两轴独立；吸附优先于边缘 clamp；中心钳在 [0,W]×[0,H] 保留半幅可拖回）+ `StickerSnapGuideTests` 9 用例；②修复拖动缺陷：`EditorCanvasView` 原把 DragGesture 累计 translation 当增量传增量语义的 `moveActiveLayer`，越拖越快漂移，改 `layerDragLast` 差值增量；③`moveActiveLayer` 应用吸附/钳制（`EditorDocumentController` 返回 `LayerSnapResult`，画布无效退化纯增量）+ `EditorViewModel.showsSnapGuideX/Y` 瞬态参考线（手势结束复位）；④参考线为铜色虚线 Path 瞬时切换（无动画 → Reduce Motion 天然满足「不播放吸附回弹」）+ 面板 toast 按 `accessibilityReduceMotion` 禁用动画；⑤VoiceOver 动态 key 修复：分组名/素材名原 `String.LocalizationValue` 插值归一为 `decoration.group.%@` 查表失败（VoiceOver 读 key 原文），改 `NSLocalizedString` 动态查找（xcstrings 已有 7 个分组 key，素材名 key 由导入流程维护）。App `EditorViewModelTests` +6 用例（增量语义守护/入阈值双轴吸附/离开立即释放/中心 clamp/无活动图层静默）。验证：MiLensKit WSL2 全量 1113 用例零回归；**未执行**：App XCTest（Windows 无 iOS SDK，待 CI/Mac）。
- [ ] 装饰素材错误诊断收口（M0 遗留，2026-08-15 复核发现，违背[开发计划](docs/Frame-Sticker-Development-Plan.md) §7.2/§9.2）：导出前预解码当前文档引用的全部装饰素材，必需素材缺失时中止保存并给出含素材 ID 的可诊断错误（当前 `makeDecorationProvider` 返回 nil 时 `renderExport` 静默跳过该层、保存仍报成功）；面板单元解码失败显示不可用状态；补 §9.2「preview/export 一致 + 缺素材不产『成功』作品」App 渲染单测（需 Mac）。
- [ ] 素材交付：首批 6 相框 + 6 贴纸 PNG 经 `tools/frame_import.py add` 入库。当前 catalog 为空 → decorate 组按门禁自动隐藏贴纸/相框入口（无假入口），素材后补后入口自动出现。
- [ ] 完成 App 编译/XCTest（Mac/CI）、五类画布比例导出、iPhone/iPad 与真机性能验收后解除功能开关。

### 验收标准

- 从相册选图到拼豆图纸导出完整走通（拼豆图纸并行推进中）
- 行为与源端 BeadPatternPage 一致（对照源端用例）
- 图片编辑器裁切/滤镜/文字/抠图可用，产物正确入库（Phase 3 完成：编辑产物走 `Documents/MiPhotos` + Photo 就地更新）
- 相框/贴纸在 Phase 4 完成前保持 catalog/功能开关控制；开放后预览与导出一致，撤销/重做与画布比例变化不丢素材、不漂移

---

## P5 — 首页/我的 + 商业化

### 任务

- [x] `HomeView`：编辑式首页（设计稿 Tab 1）——hero 大图 + 「往日回忆」+ 空态已按 v2 编辑式布局落地；**Figma「01·首页」#319:1026 落地（2026-08-12）**：出血 Hero（589pt）+ 底部渐变 + 宠物身份条（珊瑚竖线+年龄+切角按钮）+ 文楷大标题（37pt）+ 即将到来的日子区块（纪念日倒计时+缩略图）+ 通知按钮。`HomeViewModel` 新增 `upcomingDay` 计算属性（遍历 birthday/adoptionDay/PetEvent 取最近纪念日）；**纪念日文案语义区分**（`UpcomingDay.Kind`：birthday→「出生至今 N 天」/ adoption→「已陪伴 N 天」/ memorial→「已记录 N 天」）；**Hero 选片策略细化**（今日最新 → 质量分 top池随机 → nil，`HomeHeroPhoto` 加 `qualityScore`，`HomeViewModel` 在 `load()` 时固定 `heroRandomIndex` 避免重绘跳图）；创作 CTA 已切换至创作 Tab
- [x] **首页铃铛 → 回忆提醒中心（2026-08-13）**：铃铛从装饰性改为「待看的回忆」入口（`Route.memoryReminders`），作为系统推送通知的应用内兜底回看（不依赖通知权限、不丢失）。新建纯逻辑 `RemindersLogic`（今日命中：生日/成为家人的日子/里程碑/往日回忆 + 全部倒计时，复用 `NotifyCheckLogic`/`MilestoneLogic`）+ `MemoryRemindersViewModel`（状态投影）+ `MemoryRemindersView`（三段式：今日/即将到来/往日回忆 + 空态）。铃铛不做红点角标，改用温和摇晃动效（±6°，1.2s）+ `Haptics.light()` 提示今日有命中；`HomeViewModel.hasTodayContent` 驱动动效。24 用例 XCTest。文案见 [Notification-Copy-Design.md §9.7](docs/Notification-Copy-Design.md#97-回忆提醒中心应用内回看入口)。
- [x] 回忆逻辑纯决策：「一年前的今天」（翻译 `TimeMachineService` + `NotifyScheduler` + `PhotoQueryLogic` 日期逻辑 → `AnniversaryLogic` + `TimeMachineLogic`，38 用例 XCTest）
- [x] WidgetKit 小组件视觉定稿（P5，2026-08-12）：设计与实现契约见 [`docs/WidgetKit-Design.md`](docs/WidgetKit-Design.md)；Figma [`14 · WidgetKit · Life Archive Glances`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=371-691) 已交付「相片回声」Small/Medium/Large、「纪念日」Small/Medium、「档案年轮」Medium/Large、Accessory Circular/Rectangular，以及 empty/redacted/stale 状态。评审板 `371:693` 全部由组件实例组成，组件源区 `371:694` 共 12 个命名组件；节点审计无小于 10pt 文字、缺失字体、越界或残留 placeholder。
- [x] WidgetKit 工程落地（2026-08-12）：独立 Widget Extension（`MiLensWidget/`）+ App Group（`group.com.milens.app`）+ App Intents（`SelectPetIntent` / `PhotoEchoConfigIntent`）+ 深链（`milens://photo/{id}` 等 → `WidgetDeepLink` → `Route`）；MiLensKit 共享数据模型与纯逻辑（`WidgetSnapshot` / `WidgetSelectionLogic` / `WidgetTimelineLogic`，33 用例 WSL2 全绿）；主 App `WidgetSnapshotWriter` 写入 App Group JSON 快照 + 降采样缩略图 + `WidgetCenter.reloadAllTimelines`；`NotificationCenter` 解耦的数据变更触发（导入/CRUD/记忆添加后自动 reload）；五种 Widget 视图（相片回声 S/M/L、纪念日 S/M、档案年轮 M/L、锁屏 Circular/Rectangular）含 content/empty/redacted/stale 四状态矩阵。**未执行**：App/Widget Extension 编译、Xcode Preview、真机验证需 Mac。
- [x] `SettingsView`：主题/隐私设置/帮助/关于（设计稿 Tab 4）——`SettingsView` + `SettingsLogic`/`SettingsViewModel`（设置项/Pro 权益展示/通知开关）+ `AboutView`/`HelpView`/`PrivacyInfoView`（git bea5b2f）；**Figma「07·我的」#140:415 落地（2026-08-12）**：重构为 Ledger 账本式设计（珊瑚竖线 rail + Fraunces 编号 + 虚线引导线 + 暖黑 Pro 卡 + 隐私徽章卡 + 居中页脚）。新增 `SettingsLedger.swift` 7 个可复用组件（LedgerSection/LedgerRow/DottedLeader/SettingsSectionLabel/ProHeroCard/PrivacyBadgeCard/SettingsFooter）。ProHeroCard 支持 isPro 双态文案切换。
- [x] StoreKit 2 订阅：MiLens Pro 产品配置（`Products.storekit`：月 ¥18 / 年 ¥98 / 永久 ¥298）+ `StoreKit2StoreService`（`Transaction` 监听）+ `ProEntitlementStore`（应用级权益唯一消费方）+ 付费墙 UI `PaywallView` + `PaywallLogic`/`PaywallViewModel`（git 61abdeb/a22ddba/078482e/310222c）——StoreKit Testing + 权益/付费墙逻辑均有 XCTest；StoreKit Testing 与真机购买验证待 Mac
- [x] App Store 截图/描述/ASO 关键词——文案已定稿（[docs/AppStore-metadata.md](docs/AppStore-metadata.md)：描述/关键词/订阅产品/审核备注/隐私问卷，2026-08-08）；**截图制作待 Mac**
- [ ] 性能基准：大图库（5000+）滚动/内存
- [ ] iPhone/iPad 适配（[ADR-0008](docs/adr/0008-v1-scope-decision.md)：iPad 为 V1.0 目标）+ 深色模式 + Dynamic Type 检查
- [ ] **全球首发多语言（7 语言：zh-Hans/zh-Hant/ja/ko/en/fr/de）**——计划与各国市场注意要点见 [docs/Localization-Plan.md](docs/Localization-Plan.md)：knownRegions 追加 + **区域差异化基础设施已落地**（`MarketProfile` 模型 + `@Environment(\.marketProfile)` 注入，承载字体策略与 GDPR 区隐私叙事强度；5 处硬编码 `zh_CN` 已清理）+ 260+3 key × 6 语言翻译（动态文案 10 类已收口 8 类，见 §3.6 收口进度；固定 locale 快照测试待补 #7.7b）+ 术语表定稿 + 商店元数据/订阅描述/审核备注/隐私政策多语言 + 截图本地化；`localization.py check` 补每语言缺译断言并接入 CI
- [ ] **UI 测试扩展（发布前质量门禁）**——`MiLensUITests` 冒烟已扩至 **6 条**（2026-08-16 audit-6 §4 P2-2：冷启动 4 Tab + 空态导航 + 创作页→相册扫描入口 / 建档 sheet 开合 / 设置备份入口 / 非 Pro 弹付费墙并可关闭，待 CI 首轮跑通），但核心用户路径与错误态仍未覆盖。目标用例：
  - **导入流程**：Onboarding 扫描发现 → 手动导入 → 入库后图库渲染（验证照片出现在网格 + 计数更新）
  - **编辑器**：照片进入编辑 → 裁切/标注等关键操作 → 保存回写（验证编辑产物标记 `category=="edited"` + 出现在「作品」分类）
  - **备份导出/恢复**：设置页导出入口 → 预估确认 → ShareSheet 出现；恢复入口 → 文件选择 → 版本校验 → 成功态（数据出现）/ 失败态（版本不兼容/格式无效错误提示）
  - **错误态**：付费墙触发（Pro 功能入口未解锁）、配额降级锁定蒙层（第 51 张照片锁定不可进大图）、导入失败提示、空库引导文案渲染
  - **基础设施前置**：现有 `launchApp()` 已注入 `XCTestConfigurationFilePath` 走 in-memory 容器 + 跳过 onboarding + mock Store；导入/编辑/备份用例需扩展 mock 数据注入（预置宠物/照片/事件）——可能需新增 launchEnvironment 开关或 test scheme 配置
  - **环境约束**：依赖 iOS 模拟器，无法在 Windows 验证；建议 Mac 环境按「先补 mock 数据注入基础设施 → 逐路径补用例」推进

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

- 2026-08-10：**本地化动态文案收口**——工具链 plural 支持（export 拆行 / import 合并 / check 完整性，端到端测试通过）+ 动态文案 10 类收口 8 类（详见 [docs/Localization-Plan.md](docs/Localization-Plan.md) §3.6 收口进度与 DEVELOPMENT.md P2 快照）：a11y 22 处迁移 + 25 个 `a11y.*` key；通知 6 模板 / 宠物卡片 / 物种名 / 年龄（locale 注入）；时间线导出 / 水印 / 分享面板；首页（计数 plural / `Date.FormatStyle`）；启动错误与恢复界面、档案加载失败（`startup.*`/`recovery.*`/`pet.profile.loadFailed`/`common.*`）。`Localizable.xcstrings` 增至 **260 key**（zh-Hans translated）+ InfoPlist 3 key，`localization.py check` 全绿；固定 locale 快照测试待补（工作项 7.7b）；App 编译/测试依赖 iOS SDK，待 macOS CI（未执行）。

- 2026-08-10：**高优先级缺陷修复**——5 项代码修复 + 测试补充（详见 DEVELOPMENT.md 验证快照）：①ImportService 重复照片误算配额→候选列表优先去重再算配额；②ProEntitlementStore 墓碑误杀→UUID 令牌 + 条件墓碑；③BeadViewModel `Task.detached` 读取 `self.isPro`→提前捕获 Bool；④GalleryView/CreateView 缩略图陈旧→`.task(id: path)` + 清除旧图；⑤SharePreviewSheet 3 处字面色→品牌色 token。`check-ui-tokens.py` / `localization.py check` 本地全绿；App 编译与测试待 macOS CI 验证（未执行）。

- 2026-08-09：**并发遗留收口确认（审计复核）**——P5 严格并发条目预留的 `BeadViewModel` 4 处 `Task.detached` 遗留经审计核实**已收敛**：4 处 detached（生成/导出/分享/PDF）均已改为以捕获 `Sendable` 局部值（`renderer`/`pattern`/`photoData`/`opts`）的方式传参，闭包内调用全局生成/渲染函数（`generateBeadPatternAsync`/`generateBeadPatternAutoAsync`/`BeadExportService.render*`），不捕获非 Sendable 的 `self`。验证：`SWIFT_STRICT_CONCURRENCY=complete` 下 `xcodebuild` BUILD SUCCEEDED。文档同步：DESIGN.md §9.1 与 DEVELOPMENT.md §4.2 的「已知遗留」描述已更新为「并发遗留收口」，仅剩 `HomeView` 2 处 `static let DateFormatter` 作为 Swift 6 语言模式迁移前置项（**后经复核已消解**：`timeFormatter` 随 2026-08-10 本地化收口、`dateFormatter` 随 2026-08-12 首页重构（`fe6f2be`）删除；2026-08-16 复核全仓库 `static let` + `DateFormatter` 零残留，`HomeSections.weekdaySymbols` 为 Sendable `[String]` 静态缓存、闭包内局部 formatter 不构成 SE-0412 违规，Swift 6 语言模式迁移无 formatter 前置项）。

### P5 进度（ADR-0010 商业化强化）

- 2026-08-10：**商业化强化与情感触点规划落地（ADR-0010）**——产出 [ADR-0010](docs/adr/0010-commercialization-and-emotion-triggers.md)，系统性扩展权益矩阵、定价、水印、分享、情感触点、编辑器装饰、离线备份、相簿模式、实体打印 9 大模块。

  **已实现（P0 全部）**：①**照片导入配额**（免费 50 张 / Pro 不限）：`CommercialRules.swift` 新增配额常量 + `allowedImportCount` 纯函数；`ImportService` 导入前配额检查 + `quotaBlocked` 计数；`GalleryViewModel` 配额拦截弹付费墙；`GalleryView` 注入 Pro 状态 + 同步；6 个边界用例。②**导出水印**（免费带水印 / Pro 无水印）：MiLensKit `BeadExportService.renderA4Export` 增 `includeWatermark` 参数（A4 页脚 ASCII 位图字体，水印文本 `Made with MiLens | milens.app`）；App `BeadExportService` 贯穿 PNG/PDF；`BeadViewModel` 导出传 `!isPro`；`PetCardArtwork` 底部渐变区水印条件渲染。③**买断定价** ¥298→¥168：`Products.storekit` displayPrice 同步。④**分享增强**：新建 `SharePreviewSheet`（引导式分享预览面板，平台图标横排 + 「更多平台」→ 系统 ShareSheet），接入 `BeadPatternResultView` + `PetCardView`。

  **已实现（P0-e/f）**：⑤**宠物卡片多模板**：MiLensKit `PetCardTemplate` 枚举（经典免费 / 拍立得 / 杂志 / 极简 Pro）+ `isUsable(isPro:)` / `resolve(_:isPro:)` 门控；`PetCardArtwork` 重构为 4 个独立排版分支；`PetCardView` 底部模板选择器（水平滚动 + 缩略图 + Pro 锁标）+ `@AppStorage` 持久化。⑥**时间线导出分享**（Pro 专属）：`TimelineExportLogic` 纯函数（从 months 构建导出数据）+ `TimelineExportCanvas`（1080px 离屏渲染视图，头部 + 按月分组 + 时间线节点）+ `TimelineView` 导航栏「分享」按钮 + Pro 门控。

- 2026-08-15：**成长时间线 / 年度回忆册手机分享模板 V1**——废止高度随内容增长的单张超级长图，统一为 390×1260pt、3× 输出的 JPEG 图片组；`ArchiveSharePagination` 纯函数负责时间线高度分页和年度回忆册 2/3 月分页，`ArchiveShareTemplate` 复用封面、月标题、真实缩略图、月度条与页脚，`ArchiveShareRendering` 按页降采样和释放资源，`SharePreviewSheet` 支持多页预览与整组系统分享。时间线与回忆册原有 `guard entitlement.isPro` 门控保持不变。Figma 首套可复用组件与 4 张成品页已放入 `Timeline` 页面 `776:1318`；iPad 专用模板后置。

  **接口预留（数据模型锁定）**：⑦**编辑器装饰**：MiLensKit `DecorationCatalog`（边框/贴纸资源目录 + Pro 门控元数据，复用已有 `EditorLayerType.frame/.sticker`）。⑧**实体打印**：`MiLens/Services/Print/PrintService.swift`（协议 + `PrintProductType`/`PrintProductSpec`/`PrintQuote`/`PrintOrder` 数据模型 + `UnavailablePrintService` 占位）。**⚠️ 延后处理（2026-08-12）**：产品决策将实体打印移出 V1.0，仅保留架构预留，不投入开发资源，不展示入口。后续版本视供应链与运营资源再行评估。⑨**离线备份**：`MiLens/Services/Backup/BackupService.swift`（协议 + `BackupManifest`/`BackupMetadata`/`PetSnapshot`/`PhotoSnapshot` 数据模型 + ZIP 打包格式定义 + `UnavailableBackupService` 占位；方案选定 A（ZIP + ShareSheet）核心 + B（iTunes File Sharing）补充，排除 C（系统相册丢元数据）和 D（iCloud 违背不联网约束））。⑩**相簿浏览模式**：MiLensKit `GalleryMode` 枚举（网格免费 / 剪贴簿 / 拍立得散页 / 杂志 Pro）。

  **Pro 权益扩展**：`ProFeature` 新增 `.photoStorage` / `.watermarkFreeExport` / `.cardTemplates` / `.timelineExport` / `.offlineBackup` / `.albumModes` 6 个权益项 + 对应本地化字符串。

- 2026-08-12：**情感触点系统 Stage 1–3 + 创作 Tab 两个新项目落地**——本轮分两批推进 ADR-0010 §3 情感触点系统与创作 Tab 扩展。架构原则贯穿：纯决策逻辑下沉 MiLensKit（可 WSL2 `swift test` 全绿），App 层渲染与集成需 Mac。详见 [docs/情感触点-Mac待办备忘.md](docs/情感触点-Mac待办备忘.md)。

  **批次一：情感触点系统 Stage 1–3 纯逻辑（MiLensKit，79 用例全绿）**：①**Stage 1 纪念日卡片强化 + 里程碑**——`MemoryCardKind`（6 种卡片类型统一枚举，ADR-0010 §10.11）+ `MilestoneLogic`（相处 100/365/730/1000 天里程碑命中/下一个/日期计算/批量窗口/文案，33 用例）；`PetCardLogic`/`PetCardView`/`Route.petCard` 增加 `kind` 参数（向后兼容，kind=nil 行为不变）+ 3 个 kind 驱动测试。②**Stage 2 成长对比卡片**——`GrowthCompareLogic`（双照片排序/年龄标签/间隔标签/结果构建，20 用例）+ App 层 `GrowthComparePhotoPickerView`（双选）+ `GrowthCompareView`/`GrowthCompareArtwork`（上下分屏双图 + 时间标签 + 间隔条 + Pro 门控）+ CreateView 入口 + Route。③**Stage 3 月度精选/年度回忆册**——`MemoryRecapLogic`（按月/年筛选 + qualityScore 排序 + isBest 去重 + 里程碑穿插，18 用例）+ `ExportQuality`（standard 1080px / high 2400px 画质门控 + 尺寸缩放，8 用例）。④**横切**——`MetricsRecorder`（ADR-0010 §3.4 本地匿名指标计数，11 事件 enum，无联网/无 PII，5 用例）。

  **批次二：创作 Tab 两个新项目**：⑤**宠物名片卡（信息导向）**——`BusinessCardTemplate`（standard 免费 / elegant / playful / minimal Pro）+ `PetBusinessCardLogic`（数据投影/组装/标签规范化（去空白去重保序截断）/长度校验/副标题/主人行，30 用例）；App 层 `BusinessCardPickerView`（选宠物）+ `BusinessCardView`（4 套排版 + 标签编辑 + 简介/主人称呼 + `FlowLayout` 自定义流式布局 + UserDefaults 草稿按 petID 缓存不扩 SwiftData schema + Pro 门控）。⑥**微信红包封面（规格导出 + 场景预览）**——`WeChatRedPacketSpec`（微信平台硬规格常量：957×1278 / ≤500KB / 750×1250 故事图 / 200×200 logo / 8 字简称 / 安全区比例）+ `RedPacketCoverLogic`（简称截断/三类规格校验/上传引导 5 步/文件名，24 用例）；App 层 `RedPacketCoverPickerView`（选照片）+ `RedPacketCoverView`/`RedPacketCoverArtwork`（957×1278 排版 + 封面简称编辑 + PNG→JPEG 大小降级链满足 ≤500KB）+ `WeChatRedPacketMockView`（拆红包页/发红包页/消息气泡/详情页 4 场景中性 UI 预览，不复刻微信商标）+ 上传引导 sheet（含注册门槛提示）。边界：App 只生成素材与预览，不介入发布（发布需用户登录 cover.weixin.qq.com，有注册门槛 + 审核 + 付费）。

  **Route 与入口**：`Route` 新增 `growthCompare`/`businessCard`/`redPacketCover` 共 6 个 case + RootTabView 分发；`CreateView` 创作 Tab 项目清单从 2 个扩展到 5 个（拼豆图纸/伙伴卡片/成长对比/宠物名片/红包封面），入口视觉沿用「原图→成品」示例模式。

  **验证**：WSL2 Swift 6.1.3 `swift test` **761/761 通过**（本轮新增 138 用例全绿，零回归；预存 2 个 Linux 专属失败为 DecorationCatalog JSON 字段名测试，macOS 上全绿）。App 层编译/渲染/真机验证需 Mac（见 [docs/情感触点-Mac待办备忘.md](docs/情感触点-Mac待办备忘.md)）。附带修复：`DecorationCatalogCodableTests.swift:116` `.utf8` → `String.Encoding.utf8`（解锁 WSL2/Linux 测试编译）。UI-DESIGN.md §1.2/§6.6 创作 Tab 项目清单已同步更新。

  **待完成——2026-08-16 收口复核**：①~⑤已全部落地并经 CI 验证（①App 编译/类型/并发自 [run 31900122759](https://github.com/altairos/MiLens-iOS/actions/runs/31900122759) 起四作业全绿代偿；②本地化 key、③里程碑通知调度（MilestoneLogic.upcomingMilestones 预排）、④RecapView + TimelineExportCanvas ExportQuality 扩展、⑤指标埋点见[情感触点备忘](docs/情感触点-Mac待办备忘.md) §2–§5，2026-08-13 落地随 CI 跑绿）。仅剩真机项：⑥红包封面真机验证（导出 PNG 上传 cover.weixin.qq.com 规格校验 + PNG→JPEG 降级链）+ 备忘 §7 备份提醒通知真机送达。

- 2026-08-13：**测试质量三项缺口修复（覆盖率加权 + 备份事件字段 + 恢复回滚）**——针对「UI 测试仅 2 冒烟用例」「ZipBackupServiceTests 缺部分失败回滚/事件字段完整性/孤儿文件清理」「check-coverage.sh 等权平均高估覆盖率」三项评审发现推进。

  **① 覆盖率脚本权重修正**（`tools/check-coverage.sh`，WSL2 `--selftest` 验证通过）：line 覆盖率从「文件级等权算术平均」改为「行数加权」（`Σ已覆盖行 / Σ可执行行`，用 `coveredLines`/`uncoveredLines`）——修复「2000 行低覆盖文件与 10 行高覆盖文件权重相同、整体被稀释高估」问题；xccov 未提供行数时回退算术平均并打印 `[note]`。新增倒数 5 个最差文件报告（可执行行 ≥ `FILE_MIN_LINES`，默认 50）+ 可选单文件行覆盖下限（`APP_FILE_MIN`/`KIT_FILE_MIN`，默认 0=关闭）。selftest fixture 现含行数数据，断言「加权 0.30 ≠ 算术 0.5667」，防加权误回退算术。CI 调用契约不变（`--selftest` + 解析 xcresult + 退出码）。[DEVELOPMENT.md](DEVELOPMENT.md) §1.2/§2.2 同步更新。

  **② 备份事件字段完整性**（`PetEventSnapshot` + `ZipBackupService`）：`PetEventSnapshot` 从 5 字段扩展为 9 字段（补 `notify`/`body`/`sourceType`/`isPinned`/`relatedPhotoID`），自定义 `init(from:)` 用 `decodeIfPresent` 向后兼容旧版备份包（缺省回退 `PetEvent` 默认值）。修复用户置顶的记忆正文 `body`、来源标签、关联照片经备份往返后静默丢失缺陷。测试守护：`testRoundTripPreservesPetEventAllFields`（全字段往返）+ `testOldBackupWithoutNewFieldsDecodesWithDefaults`（旧包向后兼容）。

  **③ 恢复回滚 + 孤儿文件清理**（`ZipBackupService.importBackup`/`applyImport`）：`importBackup` 跟踪 `writtenPaths`，任意阶段失败时 catch 清理已写文件（防孤儿）；`applyImport` 跟踪 `insertedPets`/`insertedPhotos`，失败时 catch `deletePhoto`/`deletePet` 回滚已入库记录（防半成品）；多处 `Task.isCancelled` 支持取消。测试守护：`testRestoreCleansUpFilesOnDBFailure`（文件清理）+ `testRestoreRollsBackInsertedRecordsOnLateFailure`（`PartiallyThrowingPetRepository` insertPet 成功/updatePet 抛错，覆盖「部分入库后回滚」分支——`ThrowingPetRepository` 立即抛错无法触达）。

  **验证**：WSL2 Swift 6.1.3 MiLensKit `swift test` **894/894 全绿**（零回归）；覆盖率脚本 `--selftest` PASS（行数加权生效 + App=基线 PASS / Kit<基线 FAIL）；行数缺失回退分支单测通过。**未执行**：App target XCTest（含新增 3 用例）需 Mac（依赖 iOS SDK）；真实 xcresult 加权数值待首次 CI 实测校准基线。UI 测试扩展已记入 P5 待办。

- 2026-08-13：**备份包跨平台友好化 + Windows 解压提示**——针对「species/gender 存数字字符串跨平台不可读」「Windows 电脑不识别 .milensbackup 后缀」两项发现，完成格式语义化与用户提示。备份包现在是跨平台就绪状态：标准 ZIP + JSON + 语义化枚举 + 平台标识。

  **枚举语义化**：`PetSnapshot.species/gender` 从数字字符串（`"1"`/`"2"`）改为语义字符串（`"cat"`/`"dog"`/`"unknown"`、`"male"`/`"female"`/`"unknown"`）。导出端 `semanticSpecies`/`semanticGender` 转语义；恢复端 `parseSpecies`/`parseGender` 向后兼容（优先语义解析，回退数字字符串），旧版备份包仍可正常恢复。

  **平台标识**：`BackupManifest` 新增 `platform: String?`（导出端写 `"ios"`，旧版包解码为 nil 按 ios 处理）。供未来跨平台转换器路由（鸿蒙/安卓导入时据此判断来源格式）。

  **Windows 解压提示**：`BackupConfirmSheet`（导出前确认）与 `BackupShareSheet`（导出完成分享）均新增 `settings.backup.zipHint` 提示行（caption2 tertiary 色）：「备份包是标准 ZIP 格式。在 Windows 电脑上把后缀 .milensbackup 改成 .zip 即可解压查看照片与元数据。」

  **验证**：WSL2 Swift 6.1.3 `swift test` **894/894 全绿**（零回归）；xcstrings 673 key JSON 合法 + `localization.py check` 通过；`ZipBackupServiceTests` 篡改 manifest 用例已同步补 `platform` 参数。**未执行**：App 编译/UI 预览/真机验证（依赖 iOS SDK，待 Mac）。

- 2026-08-13：**离线备份引导体系补齐（ADR-0010 §8 引导增强）**——针对「操作内引导充分，主动触达缺失」的评估结论，完成 4 级引导触达（P0–P3）。文案一律避开「换机丢失」表述，转而强调记忆的珍贵与完整保存。决策逻辑下沉 MiLensKit（WSL2 852/852 全绿），App 层渲染集成待 Mac。

  **P0 上次备份时间感知**：`BackupViewModel` 导出成功后持久化 `lastBackupDate`（UserDefaults，key 与首页横幅 / 定期通知共享）；`SettingsView` 导出入口副标题已解锁 Pro 时展示「上次备份 X 月 X 日」或「尚未备份，把记忆完整留存」温柔引导（新增 `settings.backup.lastBackup %@` / `settings.backup.neverBackup`）。

  **P1 Onboarding 首次引导**：`OnboardingImportStep.successView` 在「本地隐私证明」与页脚间新增情感化备份留存卡片（`MEMORY SAFEKEEPING · 把这份珍贵的回忆好好留存」），种下「备份功能存在」的认知，文案强调「无论时光怎样流转，温暖的瞬间都不会走散」。

  **P2 首页数据量增长提醒横幅**：`HomeViewModel` 增加 `shouldShowBackupBanner`（决策下沉 `BackupReminderLogic.shouldShowHomeBanner`，照片≥20 + 30 天未备份/从未备份触发）+ 会话级关闭；`HomeView` Hero 下方新增 `BackupReminderBanner`（珊瑚竖线卡片 + × 关闭 +「去导出备份」CTA）；跨 Tab 跳转经 `backupExportRequested` @AppStorage 通道（RootTabView 切「我的」Tab + SettingsView `onAppear`/`onChange` 兑底触发导出/付费墙）。

  **P3 定期备份提醒通知**：`NotifyService` 注入 `lastBackupDateProvider` 闭包 + `rescheduleAllReminders` 调用 `scheduleBackupReminder`（`shouldScheduleBackupReminder` 判断 60 天未备份/从未备份 → 先撤销旧通知再调度「次日 09:00」单次通知；刚备份过则仅清理）；通知 tap 经 `NotificationDeepLink.isBackupReminder` 识别 → `AppDelegate.pendingBackupTap` → MiLensApp 设 `backupExportRequested` 跳转设置备份区。

  **文案修正**：将设置页常驻提示与导出完成分享面板文案中的「防止换机或丢机时数据丢失」改为情感化表述（「让珍贵的记忆多一份守护」/「让温暖的故事无论何时都在」），避免暗示换机丢数据、质疑 App 功能性。

  **纯逻辑**：`MiLensKit/Sources/MiLensKit/Backup/BackupReminderLogic.swift`（阈值常量 bannerStaleDays=30 / bannerMinPhotos=20 / reminderStaleDays=60 + daysSinceLastBackup / shouldShowHomeBanner / shouldScheduleBackupReminder 纯函数，13 用例）。**验证**：WSL2 Swift 6.1.3 `swift test` **852/852 全绿**（新增 13 用例零回归）；xcstrings 665 key JSON 合法 + `localization.py check` 通过。**未执行**：App 编译/UI 预览/真机验证（依赖 iOS SDK，待 Mac）。

- 2026-08-12：**本地导出功能体验补强（ADR-0010 §8 落地增强 + 创作页反馈一致性）**——针对备份导出与作品导出两条链路体验缺口，完成 6 项修复（Windows 本地代码就绪，编译/测试待 Mac）。

  **备份导出 4 项（ADR-0010 §8）**：①**导出前预估 + 确认**——`BackupService` 协议新增 `estimateBackup(petIDs:) -> BackupEstimate`（预估能力，不打包）；`ZipBackupService` 实现（与 `collectExportBundle` 同 petIDs 过滤语义，保证预估与实际一致）；`BackupViewModel` 拆为两步流程（`prepareExport()` → `.readyToExport` 状态 → 用户确认 → `exportBackup()`）；新增 `BackupConfirmSheet`（导出前展示「宠物档案 N 个 / 照片 M 张」+ 打包说明 + 「开始导出」，避免大库无声产出巨大 ZIP）。②**导出中阶段文案**——`ExportState.inProgress` 现携带 `BackupPhase`（`RestoreState` 同步携带 `RestorePhase`）；新增 `ExportProgressOverlay`（半透明遮罩 + 进度转圈 + 「65% · 复制照片文件」实时阶段文案，解决长任务用户不知道「卡在哪一步」）。③**入口 isAvailable 兑底**——备份导出/恢复入口均读取 `backupVM.isServiceAvailable`，不可用时禁用并显示「即将上线」副标题，对齐协议注释「UI 层据此禁用」承诺（之前注释说但未实现）。④**恢复限定文件格式**——`project.yml` `UTExportedTypeDeclarations` 完善 conformance（`public.zip-archive`+`public.data`+MIME）；`fileImporter` 从 `.item` 改为 `[UTType(exportedAs:"com.milens.backup"), .item]`（减少误选任意文件直到解析失败才报错）。+4 预估用例（全量/与实际导出一致不变量/petIDs 过滤/空库）。

  **作品导出 2 项**：⑤**统一保存成功反馈**——新增 `Components/ExportToast.swift`（`ExportToastMessage` + `.exportToast` 修饰器：胶囊图标+文案 + 成功/失败触感，2.5s 自动消失）；`PetCardView`/`GrowthCompareView` 保存相册从「静默无提示」改为显示「✅ 已保存到相册」+触感（失败也用 toast 替代部分 alert），与拼豆页（自带 `BeadToastMessage` 体系）体验一致。⑥**硬编码文案迁移**——5 个创作/导出页（CreateView/PetCardView/GrowthCompareView/BeadPatternResultView/TimelineView 导出按钮）的硬编码中文全部迁移到 `String(localized:)`；`Localizable.xcstrings` 新增 50 key（`common.save`/`common.share` + `create.*` 系列 38 + `settings.backup.confirm*`/`phase.*` 系列 10）。

  **附带知识沉淀**：发现 `project.yml` `info.properties` 是 Info.plist 唯一事实源（`xcodegen generate` 会覆盖手改），已记录为项目记忆；UTType/文件类型/权限开关类变更必须改 project.yml，不直接改 Info.plist。

  **验证（Windows 本地）**：xcstrings JSON 合法（401 key，源语言 zh-Hans `ok=401 missing=0`）；`localization.py check` 无占位符/格式告警；project.yml YAML 合法；145 处 `String(localized:)` 字面量引用 100% 命中 xcstrings。**未执行**：App 编译/XCTest/UI 预览/真机验证（依赖 iOS SDK，待 Mac）。

- 2026-08-12：**WidgetKit 小组件与锁屏设计稿落地（Figma `371-693` 评审板 / [WidgetKit-Design.md](docs/WidgetKit-Design.md)）**——五阶段落地，纯逻辑 WSL2 验证，App/Widget Extension 编译待 Mac。

  **Phase 1 MiLensKit 共享模型与纯逻辑（33 用例 WSL2 全绿）**：①`WidgetSnapshot` + `PetProjection`/`PhotoProjection`/`UpcomingDayProjection`/`ArchiveStats`（Codable+Sendable 快照模型，App 写入 / Widget 读取）；`WidgetSharedConfig`（App Group ID / 文件名 / 深链 scheme / schema 版本 / stale 阈值常量）。②`WidgetSelectionLogic`——相片回声选片（今日/往日同日/最近作品三级策略 + 伙伴过滤 + 质量分 top池随机）、纪念日排序（下一个最近纪念日 + daysUntil/daysTogether）、档案统计、状态判定（content/empty/redacted/stale 四状态矩阵）。③`WidgetTimelineLogic`——相片回声跨日刷新、纪念日双 entry（23:59 + 00:01 保证倒计时不滞后）、档案年轮 4h 低频刷新。④33 用例 XCTest（选片 8 + 纪念日 4 + 统计 2 + 状态 9 + Codable 2 + Timeline 8）。

  **Phase 2 project.yml 配置**：新增 `MiLensWidget` app-extension target（`com.milens.app.widget`）+ 依赖 MiLensKit + MiLens；entitlements 两 target 声明 App Group（`group.com.milens.app`）；主 App info.properties 新增 `CFBundleURLTypes`（`milens://` scheme）；Scheme build targets 加入 MiLensWidget。

  **Phase 3-4 Widget Extension（8 文件）**：①`MiLensWidgetBundle`（@main 入口，注册 5 种 Widget）；②`WidgetIntents`（`PetEntity` + `PetEntityQuery` 从快照读取宠物列表 + `SelectPetIntent` + `PhotoEchoConfigIntent` + `PhotoEchoSourceAppEnum`）；③`WidgetSnapshotReader`（App Group JSON 读取 + ImageIO 降采样缩略图加载，≤300pt 控内存）；④`WidgetDesignSystem`（内联色值/字体 token + `CopperRail` 铜色登记轨 + `PhotoBleedView` 照片出血 + empty/stale 占位视图 + 深链工具 + 本地日历）；⑤`PhotoEchoWidget`（S/M/L：照片全出血+微型登记头 / 左照片+右档案纸+登记轨 / 上照片+下档案纸+三个月份刻度）；⑥`UpcomingDayWidget`（S/M：大号倒计时+照片证据+登记轨 / 照片+倒计时并列+开放时间轨「已陪伴N天→还有N天」+当天改为「今天」）；⑦`LifeArchiveWidget`（M/L：右重铜色登记线+三项统计 / 增加年份节点+代表照片）；⑧`LockScreenWidgets`（Circular：天数+极简开放轨弧线，单色渲染；Rectangular：最多两行正文，不展示照片缩略图）。

  **Phase 5 主 App 集成**：①`WidgetSnapshotWriter`（@MainActor，从 Repository 读取→投影→JSON 写入 App Group + detached task 降采样缩略图复制 + `WidgetCenter.reloadAllTimelines`）；②`WidgetDeepLink`（`milens://photo/{id}` 等 → `Route` 纯逻辑 + 9 用例 XCTest）；③`WidgetReload`（NotificationCenter 解耦，ViewModel 不持 writer）；④`MiLensApp` 注入 writer + `.onOpenURL` 深链处理 + `.onReceive(widgetDataChanged)` 自动 reload；`RootTabView` 接 `pendingWidgetRoute` Binding + `homePath` 导航；⑤5 个 ViewModel 数据变更点触发 reload（`GalleryViewModel` 导入后 / `PetProfileViewModel` 宠物 CRUD / `PetEditViewModel` 编辑+删除 / `TimelineViewModel` 添加记忆）。

  **验证**：WSL2 Swift 6.1.3 MiLensKit `swift test` 808 用例，本次新增 33 个 Widget 纯逻辑用例全绿，零回归（2 个预存 `DecorationCatalogCodableTests` Linux 专属失败不变，macOS 全绿）。**未执行**：App/Widget Extension 编译（需 iOS SDK，Windows 无法验证）、Xcode Preview、真机验证（共享快照刷新、隐私遮罩、跨日倒计时、配置切换）——需 Mac + iPhone。

- 2026-08-12：**配额降级清理场景落地（ADR-0010 §10.1.1）**——修复原 P0-a 配额拦截只管「导入时」，不管「降级后已存储超额照片」的僵尸数据缺陷。用户在 Pro 期导入 200 张、订阅到期后，这 200 张此前既无法查看也无法删除。

  **策略：超额照片「可见但锁定」**（始终让用户看见回忆——情感产品红线；超额部分加锁标蒙层，可删除但不可进大图/创作）。最新 50 张按 `takenAt` 倒序可见可操作，第 51 张起锁定。

  **新增文件 3 个**：①`QuotaGatingLogic.swift`——纯函数集（`overLimitCount` / `lockedPhotoIDs` / `shouldPromptDowngrade` / `promptShouldReset`），依赖 `CommercialRules.freePhotoLimit` 不重复硬编码；②`QuotaGatingLogicTests.swift`——16 用例（边界：未超额/恰好 50/51 张锁 1/Pro 全不锁/降级四条件组合/续费重置）；③`QuotaDowngradeSheet.swift`——降级提示 sheet（双 CTA：续费恢复 / 管理存储）。

  **修改文件 7 个**：④`GalleryViewModel`——新增 `lockedPhotoIDs`（运行时计算，不入 SwiftData）+ `isLocked` / `deleteSelected` / `updateProStatus` / `enterStorageManageMode`；在 load/delete/Pro 变更后重算。⑤`GalleryView`——`LockedPhotoThumbnailCell`（半透明蒙层 + 锁标 + Pro 角标）+ 多选删除按钮 + 超额横幅 + 存储管理模式入口监听。⑥`GalleryBatchBar`——增加删除按钮（与归属按钮并列）。⑦`RootTabView`——降级检测（冷启动 `task` + `onChange(of: entitlement.isPro)`）持久化 `lastKnownIsPro` + `quotaDowngradePromptPending`（防重复；续费后自动重置）+ 付费墙 `NotificationCenter` 监听 + 跨 Tab 存储管理路由。⑧`SettingsView`——「照片存储」入口行（N/50 张，超额珊瑚色高亮）。⑨`Localizable.xcstrings` +⑩`localization-assets.py`——新增 11 个简中 key + 对应英文翻译。

  **扩展测试**：`GalleryViewModelTests` 新增 7 用例（锁定重算/Pro 切换重算/批量删除联动 DB+文件+计数+锁定重算/管理模式横幅/超额自动退出多选）。

  **验证（Windows 本地）**：xcstrings JSON 合法（`json.load` 验证）；`localization-assets.py` 语法合法（`ast.parse` 验证）。**未执行**：App 编译 + XCTest（需 iOS SDK，待 macOS CI）+ 锁定蒙层/sheet 视觉效果（需模拟器/真机）。跨 Tab 协调用 `@AppStorage("storageManageRequested")` + `Route.gallery` push；不自动删除任何照片（仅用户主动操作）。

- 2026-08-12：**生命档案 P3.6 增强 + 情感触点 App 层集成 + 实体打印延后标注**——本轮收口 3 项系统梳理缺口。

  **C. 生命档案增强 P3.6 缺口收口**：①`AddMemorySheet` 从 `TimelineView.swift` 的 private struct 提升为 internal，支持多处复用；新增 `prefilledPhotoID: UUID? = nil` 参数，从照片详情页进入时预填充关联照片。②`PetProfileView` archivePanel 新增「添加一条记忆」入口（`showAddMemorySheet` + `@Environment(\.proEntitlement)` + `timelineAccessStore` + `factory.makeTimelineViewModel()`）。③`PhotoViewView` 拨盘式 CTA 从 `NavigationLink(value: Route.timeline)` 改为 `Button { showAddMemorySheet = true }`，直接弹出 `AddMemorySheet`（预填充 `prefilledPhotoID`），实现「照片详情 → 加入记忆」一步到位。

  **D. 情感触点系统 App 层集成**：④**新建 `RecapView`**（`Views/Create/RecapView.swift`，370 行）—— 月度精选 / 年度回忆册 UI：年份选择器 + 年度统计 + 月度代表照片网格（`MemoryRecapLogic` 纯逻辑选片）+ Pro 导出（`RecapExportCanvas` 离屏渲染，`ExportQuality.high` 门控，复用 `SharePreviewSheet`）。⑤**`TimelineExportCanvas` 扩展 `ExportQuality`**（修复编译 bug：`entryIconColor` 缺 `.textNote`/`.workRecord` case）+ 尺寸按画质宽度等比缩放（standard 1080 / high 2400）。⑥**`MetricsRecorder` 埋点接入 6 触点**：`PaywallView`→`.paywallShown`、`PetCardView`→`.memoryCardPreviewed`、`GrowthCompareView`→`.growthComparePreviewed`、`SharePreviewSheet`→`.shareSheetOpened`、`RecapView`/`TimelineView` 导出→`.exportStarted`/`.exportCompleted`。⑦`Route` 新增 `.recap(year: Int?)` + `RootTabView` 分发；`HomeView` 新增「年度回忆」入口卡片（`YearlyRecapEntry`）。⑧本地化补充 13 个简中 key（`recap.*` 10 + `home.yearlyRecap.*` 2 + `pet.profile.addMemory` 1）。

  **实体打印延后标注**：产品决策（2026-08-12）将实体打印移出 V1.0。`PrintService.swift` 文件头新增「⚠️ 延后处理」注释；PLAN.md ADR-0010 条目标注延后。

  **Figma 12 页进度校正**：核实全部 12 页 Release Candidate 设计稿均已落地（04 图库 / 05 创作 / 06 Paywall / 08-12 照片详情/添加记忆/拼豆三件套均已有对应视图），PLAN.md 进度表从 4/12 → 12/12。

- 2026-08-12：**源端三技术债迁移：LRU 缩略图缓存 / 扫描 pause/resume / 头像裁切**——收口「已知差距」表中 3 项与源端鸿沟。

  **① LRU 缩略图缓存**（对应源端 `ThumbnailCache.ets`）：新增 `Components/ThumbnailCache.swift`（178 行）—— UIImage 内存 LRU（默认 100 条，淘汰 20 条触发磁盘清理）+ `NSLock` 线程安全 + `UIApplication.didReceiveMemoryWarning` 自动清空 + 磁盘目录 LRU 清理（100MB 上限）；`PlatformEnvironment` 新增 `thumbnailCache` EnvironmentKey + `SharedThumbnailCache.shared`（磁盘目录 = Caches/thumbnails）；`GalleryView.ThumbnailImage` 从「每次现读」改为「先查缓存 → 未命中后台解码 → 写入缓存」。

  **② 扫描 pause/resume**（对应源端 `PhotoScanner.handlePauseResume`/`prepareResume`/`resetScanState`）：`ScanService` 新增完整状态机（`shouldPause`/`shouldCancel`/`isPaused`/`lastScannedIdentifier`/`savedPetPhotosFound`/`savedMatchedCount`）+ `pauseScan()`/`cancelScan()`/`prepareResume()`/`resetScanState()` 公开方法 + `hasResumableState` 属性；阶段 1 `streamPhotos` consumer 与阶段 2 批处理循环头部新增 pause/cancel 检查点；resume 时复用 `ScanControlMath.updateResumePoint` 跳过断点前照片；暂停保留断点，完成/取消清除断点。`ScanResult` 已支持 `completedSuccessfully` 判定（暂停不保存增量游标）。

  **③ 头像裁切**（对应源端 `AvatarCropPage.ets`）：①`MiLensKit/Gallery/AvatarCropMath.swift`（119 行）—— `clampOffset`（偏移钳制，确保裁剪圆被图片覆盖）+ `computeCropRect`（坐标转换：容器 VP → 源像素坐标系）+ `cropAndResize`（UIKit extension，`CGImage.cropping` + `UIGraphicsImageRenderer`）；②`Views/Pets/AvatarCropSheet.swift`（232 行）—— 全屏暗色背景 + 图片预览（缩放/平移手势）+ 中心圆形裁剪框（双图层 destinationOut 遮罩）+ 确定 → 裁切 → 256×256 JPEG 保存到 `Documents/MiPhotos/Avatars`；③`PetEditView.avatarSection` 从占位改为接入 `PhotosPicker`（单选）→ 加载 → `AvatarCropSheet` → `updateAvatarPath`，显示头像预览（有头像显示 UIImage，无头像用物种 Emoji）；④`PetEditViewModel.avatarPath` 从 private 提升为 `private(set)` 以供 View 读取预览；⑤`AvatarCropMathTests`（11 用例，clampOffset 5 + computeCropRect 6，覆盖默认中心/scale2 缩小/偏移移位/边界钳制/零值回退/正方形）。

  **本地化**：新增 3 个简中 key（`avatar.crop.failed`/`avatar.crop.hint`/`common.confirm`）。

  **视觉特征注册**：确认 `PetEditViewModel.registerFeature` + `PetMatcher.registerPetFeatures` + `PetEditView` PhotosPicker UI 已在前期实现，本轮无代码改动。

  **验证（Windows 本地）**：MiLensKit `AvatarCropMathTests` 11 用例纯逻辑可在 WSL2 `swift test` 验证（待执行）。**未执行**：App 编译 + ThumbnailCache/ScanService pause/resume 真机验证（需 iOS SDK + 真实照片库，待 macOS CI + iPhone）。

- 2026-08-14：**系统架构审计 + Windows 侧整改（remediation-plan P1-1/P3-1/P1-3）**——产出审计三件套 [docs/audit/](docs/audit/)（architecture-review 风险登记 R1–R10 / risk-map 依赖图 / remediation-plan 分批整改），随即完成 Windows 本地可执行的整改三项。**P1-1 拆分 ZipBackupService（R2+R8）**：1227 行主文件拆为三文件——`ZipBackupService.swift`（447，协议实现/导出编排）+ `ZipBackupService+Restore.swift`（505，恢复链路 extension）+ `ZipBackupSupport.swift`（327，快照转换/分卷配置/计数器等支撑类型）；跨文件 extension 访问需要已把 4 个仓储属性与 encoder/decoder internal 化（`@testable import` 下测试不受影响）；`@unchecked Sendable` 就地理由注释补齐（R8）。**决策偏差**：remediation-plan 原设「分卷/快照编解码下沉 MiLensKit」，实际改为 App 层内三文件拆分——13 个快照类型全部定义在 App 层 `BackupService.swift`，下沉需连带移动接口与数据模型，与本批「行为零变更」目标冲突，下沉作为后续独立重构再评估。**P3-1 RecapView 降级修正（R9）**：`loadDownsampled` 两处 `UIImage(contentsOfFile:)` 全尺寸解码 fallback 改为 `return nil`（渲染端画占位块），消除导出路径内存峰值源。**P1-3 守卫自动化（R2/R3 根治）**：新增 `tools/check-file-size.py`（600/800 行规模守卫，Kit 与 Editor 目录 800）+ `tools/check-imports.py`（平台隔离：Views 禁 import Photos 与 PH 符号、Services 仅 Platform/ 与 ADR 豁免）接入 CI lint 作业（[ADR-0011](docs/adr/0011-ci-guards-and-photos-exemption.md)）；顺带删除 4 个 View 的冗余 `import Photos`（零符号使用）；守卫首跑发现 5 个存量超标文件（TimelineLogic 665 / RedPacketExportView 651 / HomeView 648 / SettingsView 633 / PetProfileView 604），按「冻结语义」登记 ADR-0011 §2.4（只许缩小，拆分后删条目），拆分批次待排。**验证（Windows 本地）**：守卫脚本正/负路径自测（超标 fixture、越界 import、冻结突破均 exit 1 拦截；清理后全绿 exit 0）+ WSL2 MiLensKit `swift test` 1041 用例零回归（SWIFT_EXIT=0，本批未触碰 Kit）+ ci.yml YAML 解析有效。**未执行**：App target XCTest（含 1089 行 ZipBackupServiceTests 行为守护）与编译验证——依赖 iOS SDK，待 Mac/CI（remediation-plan P0-1）。

- 2026-08-15：**未推送批次审计 + 问题修复 + 本地化门禁过渡期降级**——审计 6 个未推送提交（相框贴纸 d757f68 / 备份重构 1ea942d / 红包工作台三连 b62ac57+7970d46+854f7a8 / 扫描动效 f894619），确认可推送；MiLensKit WSL2 实跑 1104 用例零回归。随后修复审计发现的全部问题（8 文件，+82/-36）。

  **红包工作台修复（RedPacketInspectorView / RedPacketQualityReportView）**：①「拖动」变换控件原为空 action 的死按钮，改为静态手势指示徽章（`transformBadge`，按钮与指示共用视觉）；②「换图」按钮原为空实现，接入 `dismiss()`（与更多菜单「换图」同语义：退出工作台回照片选择）；③SF Symbol 名拼写错误 `"plus magnifyingglass"`（带空格，渲染为空白）改为 `"plus.magnifyingglass"`；④`Text("QUALITY")` 硬编码改走 `redpacket.quality.overline` 本地化 key；⑤删除空 `.overlay { VStack {} }` 死代码。

  **本地化 key 一致性修复（1 缺 key + 2 处运行时 key 不匹配缺陷）**：①`a11y.editor.removeFrame`（相框面板「移除相框」a11y 标签，d757f68 引入）代码引用但 catalog 缺失，补录简中；②OnboardingView a11y「第 X 步共 N 步」标签插值内写死字面量 `4`，运行时 key 归一为 `a11y.onboarding.step %lld 4` 与 catalog 的 `%lld %lld` 不匹配（VoiceOver 会读 key 原文），改为 `OnboardingViewModel.majorStageCount` 常量；③AddMemorySheet CTA 插值内 `?? ""` 的字面量引号截断 `localization.py` 的 key 提取，外提 `petName` 变量，catalog key 同步改名 `memory.saveToPet` → `memory.saveToPet %@`（原 key 不含 `%@` 而 value 含，运行时永远匹配不上）。

  **CI lint 必挂修复（origin/main 已处于失败状态）**：7 语言 knownRegions 与 Check localization 门禁均已推送，但 6 个非源语言 858 key 全部缺译 → lint 作业 5148 阻断必挂，且 `app` 作业 `needs: [kit, lint]` 导致 App 编译/测试/覆盖率全链路被跳过。`localization.py check` 新增 `--allow-missing-translations`：非源语言缺译降为警告并聚合输出；`--strict` 发布门禁下缺译仍阻断不可绕过；GUI `run_check` 经 getattr 兜底行为不变。CI 命令带该参数（翻译完成后移除，见 Localization-Plan §6）；DEVELOPMENT.md §2.2/§4.5 与 Localization-Plan 头部/§2.1/§6 已同步。

  **验证（Windows 本地）**：`localization.py check` 带参数 EXIT=0（5339 警告 = 5148 缺译降级 + 原有 191；阻断清零、缺 key 清零）；`--strict --allow-missing-translations` EXIT=1（发布门禁优先级正确）；`tools/test_localization.py` 17/17 通过。**未执行**：App target 编译 + XCTest（Swift 改动 5 文件，依赖 iOS SDK）——推送后需盯首轮 CI 的 app 作业（此前因 lint 必挂，本批代码从未在 CI 编译过）。

- 2026-08-15：**相框贴纸 M2 质量项：拖动中心吸附 + 参考线 + 可访问性**——落地开发计划 §4.3 拖动质量行为并修复两处存量缺陷（详见 P4 Phase 4 任务区条目）：吸附决策下沉 MiLensKit（`snapAndClampLayerCenter` + `LAYER_SNAP_THRESHOLD=6pt`，9 用例）；拖动累计 translation 缺陷（越拖越快漂移）改 `layerDragLast` 差值增量；画布铜色虚线中心参考线瞬时切换（无动画，Reduce Motion 天然兼容）+ toast 动画按开关禁用；VoiceOver 动态 key（`String.LocalizationValue` 插值归一 `decoration.group.%@` 查表失败）改 `NSLocalizedString` 动态查找。App `EditorViewModelTests` +6 用例。**验证（Windows 本地）**：MiLensKit WSL2 `swift test` 全量 1113 用例 0 失败（含新增 9）。**未执行**：App target XCTest（需 iOS SDK，待 CI/Mac，推送后盯首轮 app 作业）。

- 2026-08-15：**相框贴纸 M0+M1/阻塞项全量复核（纯文档改动）**——对照[开发计划](docs/Frame-Sticker-Development-Plan.md)逐项核对 §3.2 八个阻塞项与 §8 M0/M1 的代码证据：阻塞项全部修复属实（快照字段/相框中心/ratioSet 同源解析/ninePatch 分块预览/稳定排序/命中排除相框/画布重映射/分组稳定 ID，各有 Kit 纯函数 + 用例）；M1 交互链路完整（面板三态/相框替换/贴纸手势/历史/保存/付费墙）。发现两处此前未跟踪的缺口并回写文档：①素材错误诊断未达 §7.2——导出端素材缺失静默跳过且保存仍报成功（M0 第 3 项部分未完成）；②App 渲染级单测未写（§9.2 逐像素一致/透明通道/缺素材用例，现有为 VM 级）。另确认 `catalog.json` 实为空目录（素材导入未开始，M1 第 3 项），入口按 §10 门禁自动隐藏。M0/M1 复选框补落地注记（保持未勾，待 Mac/CI）；Phase 4 新增诊断收口待办。

- 2026-08-15：**CI 首次全绿 + 审计收口（audit-4/5/6）**——仓库转 public 后额度无限，以 CI 代偿 Mac 验证完成 remediation-plan P0-1/P0-2：**25 轮修复链**（编译恢复 r1-8 → 严格并发/测试 target r9-17 → 运行时 r18-19 → 覆盖率门禁 r20-25）终结于 [run 31900122759](https://github.com/altairos/MiLens-iOS/actions/runs/31900122759) 四作业全绿：Kit 1113（Linux）+ App 894（模拟器）+ UI 2 = **2009 用例 0 failed**，lint 四项全过（含 08-14 接入的规模/隔离守卫），覆盖率门禁首次对真实数据 PASS（App 加权 line 16.2% ≥ 基线 13%，实测校准消除 R4）。audit-5：README/DESIGN/PLAN/DEVELOPMENT 测试数字统一为 CI 实测 2009（消除 R5）。audit-6：产出 [verification-recovery-report.md](docs/audit/verification-recovery-report.md)（R1 实证链 + 风险表状态：R1-R5/R8/R9 六项消除，新增 N1 App 覆盖 0% 大文件清单 P1-4）；remediation-plan 进度注记同步。**未执行**：真机验证与性能基准（P2-3，需 iPhone）。

- 2026-08-16：**audit-6 §4 剩余项逐项修复（P1-4/P1-5/P2-1/P2-2）**——①**P1-4**（N1 覆盖 0% 大文件补测）：5 个 0% 超大视图的决策逻辑下沉为纯 struct（`ViewModels/` 下 `TimelineChapterLogic`/`PhotoViewDisplayLogic`/`RedPacketCoverEncodeLogic`/`BeadPreviewLayoutLogic`/`BeadResultDisplayLogic`），回改 5 个调用方（TimelineView/PhotoViewView/RedPacketUploadGuideView/BeadViewModel/BeadPatternResultView），新增 5 个 XCTest 文件 **45 用例**；②**P1-5**：[ADR-0011](docs/adr/0011-ci-guards-and-photos-exemption.md) §2.4 冻结超标文件实际已全部拆分完毕，状态表回写关闭（audit-6 表述过时已澄清）；③**P2-1**：`PhotoLibraryAccess` 协议补 `save(imageData:as:)`（`IOSPhotoLibraryAccess` 真实实现 + Mock），`BeadExportService` 改协议注入并移除 `import Photos`，check-imports `FILE_EXEMPTIONS` 清零（ADR-0011 §2.2/§5 同步关闭），`BeadExportServiceSaveTests` 4 用例；④**P2-2**：UI 冒烟 2→6 条（audit-6 §4「5~8 条」口径达成；付费墙断言避开设置页 ProHeroCard 与付费墙 hero 同名 "MiLens Pro" 的恒真陷阱，改用付费墙独有 hero 文案；不点「开始扫描」防真实相册授权弹窗阻塞用例）；截图脚本属 P5 上架流水线（Mac 侧）不在此轮。**验证（Windows 本地）**：三守卫全绿（check-imports 222 文件 0 越界 / check-file-size / check-ui-tokens 均 exit 0）；WSL2 MiLensKit `swift test` **1113/1113 全绿**（零回归，本轮 Kit 无改动）。**未执行**：App 单测（+49）与 UI 测试（6 条）需 iOS SDK，scheme 已含 UI target，推送后 CI 自动执行，盯首轮 app 作业。**CI 已验证（同日补充）**：[run 31905505907](https://github.com/altairos/MiLens-iOS/actions/runs/31905505907) 四作业全绿，App 943 + UI 6（总计 2062，含 2eb0e02 付费墙断言修复与 cd6fe98 PaywallView 可访问性微调）0 failed；gate PASS（App 加权 line/function 21.3% ≥ 13/13/0），基线据此回调 18/18/0。

---

## 数据安全与跨设备迁移（2026-08-12 规划）

### 背景

MiLens 是纯本地 App，照片副本与档案数据存于沙盒，对用户具有极强情感意义。换机、丢机、删 App 场景下，若用户未开启系统 iCloud 备份，数据将永久丢失且应用内无自救手段。审计确认 [ADR-0010 §8](docs/adr/0010-commercialization-and-emotion-triggers.md) 规划的 `BackupService` 仅为接口占位（`UnavailableBackupService`），实际打包/恢复逻辑未实现——这是换机数据安全的唯一重大缺口。

### 风险评估

| 场景 | 现状 | 风险 |
|---|---|---|
| 应用更新 | SwiftData Schema 迁移框架就绪（V1 冻结 + `MiLensMigrationPlan`） | 低 ✅ |
| 换机（开启 iCloud 备份） | 数据库 + Edits + 游标可恢复；导入副本被 `isExcludedFromBackup` 排除（设计假设可从系统相册重建） | 中（依赖相册原图仍在 + 同 Apple ID） |
| 换机（未开启 iCloud 备份） | 数据库 + 编辑产物 + 游标全部丢失，应用内无自救 | **高** ❌ |
| 删 App / 手机丢失 | 同上 | **高** ❌ |

### 任务

1. **实现 `BackupService` 导出/恢复（本次实施）**：将照片原图 + 编辑产物 + 完整元数据（Pet/Photo/PetEvent 的 Codable 快照）打包为 `.milensbackup`（ZIP），通过 ShareSheet 导出到 Files/iCloud Drive/AirDrop；恢复经 DocumentPicker 选择备份文件，校验 `manifest.schemaVersion` 后合并导入（同 ID 跳过，不覆盖现有数据）。
   - ZIP 能力：MiLensKit 新增纯 Swift `ZIPArchive`（store 模式，无三方依赖，可在 WSL2 测试）。
   - 实现 `ZipBackupService` 替换 `UnavailableBackupService`；接入 `AppDependencies` 依赖图。
   - Pro 门控：导出为 Pro 专属（`ProFeature.offlineBackup`）；恢复对所有用户开放。
   - **导出体验补强（2026-08-12）**：①`estimateBackup` 预估能力（协议级）+ `BackupConfirmSheet` 确认对话框（导出前展示「N 个档案 / M 张照片」规模，用户确认后再打包）；②`ExportState.inProgress` 携带 `BackupPhase`，`ExportProgressOverlay` 浮层展示「65% · 复制照片文件」实时阶段文案；③入口用 `isServiceAvailable` 兑底（不可用时禁用并提示「即将上线」，对齐协议注释承诺）；④`fileImporter` 限定 `com.milens.backup` UTType（project.yml 声明 `UTExportedTypeDeclarations`，conforms `public.zip-archive`+`public.data`+MIME）。+4 预估用例（含预估与实际导出一致不变量）。

2. **引导用户开启备份/主动导出**：在设置页「数据与隐私」分区增加备份导出/恢复入口；首选项或引导流提示「为防止换机/丢机丢失，建议开启 iCloud 备份或定期导出 `.milensbackup`」。不强制、不联网、不读取账户信息。

3. **导入副本排除备份策略的用户可控性**：当前 `Documents/MiPhotos/` 导入副本被 `isExcludedFromBackup` 主动排除（设计假设可从系统相册重建）。考虑增加用户开关（云空间优先 vs. 数据安全优先），或导出备份时强制包含导入副本，避免「系统相册已清/换 Apple ID」时出现「DB 记录在、图片文件永久缺失」。此项为后续增强，V1 先以任务 1 的完整备份兜底。

### 验收标准

- [x] 任务 1：`ZIPArchive` 纯逻辑测试（WSL2 12/12 全绿）+ `ZipBackupService` 服务测试（代码就绪，待 Mac）。
- [x] 任务 1：设置页备份导出/恢复入口可用（ShareSheet 导出 + DocumentPicker 导入）。
- [x] 任务 2：引导提示文案与入口就位（设置页「数据与隐私」分区：数据安全提示 + .milensbackup 使用引导）。
- [x] 任务 3：用户可控开关已实现（`PhotoBackupMode` 枚举 + `@AppStorage("photoBackupMode")` + `IOSFileStorage.reapplyBackupExclusion` 切换后立即重标记已有文件 + 5 纯逻辑用例）。
- [x] 任务 1 增量（2026-08-12）：导出预估+确认/阶段进度浮层/isAvailable兑底/UTType 限定 全部落地；`estimateBackup` +4 用例（Windows 本地 xcstrings JSON + YAML 合法性 + key 引用全命中校验通过；App 编译/测试待 Mac）。
- [ ] 真机验证：完整导出 → 删 App → 重装 → 恢复，数据（宠物档案 + 照片 + 编辑产物 + 事件）完整还原。

---

## Figma 12 页 Release Candidate 设计稿落地（2026-08-12 启动）

### 背景

Figma 文件 `WnT7DCK1XCyPwnS38SE87p`（MiLens iOS Release Candidate · FINAL）含 12 张定稿页面。设计语言为 **Ledger 编辑式**：珊瑚竖线 rail + Fraunces 编号 + 虚线引导线 + 文楷情感标题 + 暖黑产品卡片。各页对照 Figma nodeId 落地到 SwiftUI，保留全部现有业务逻辑（Pro 门控/导出/导航/数据绑定），仅替换视觉层。

### 进度

| # | 页面 | Figma nodeId | 状态 | 说明 |
|---|---|---|---|---|
| 01 | 首页（ROOT TAB） | `319:1026` | ✅ 已落地 | 出血 Hero + 宠物身份条 + 即将到来的日子 + 通知按钮 |
| 02 | 伙伴档案（ROOT TAB） | `319:1095` | ✅ 已落地 | 出血肖像 Hero + Archive Panel + 四列统计 + 置顶记忆 + 最近照片 + 时间线入口 |
| 03 | 生命时间线（PUSH） | `140:348` | ✅ 已落地 | 年份选择器 + 章节标记 + 三种记忆卡片 + 悬浮添加 |
| 04 | 图库（PUSH） | — | ✅ 已落地 | GalleryView（扫描/导入/分页/筛选/多选/配额锁定） |
| 05 | 创作（ROOT TAB） | `58:15` | ✅ 已落地 | CreateView（拼豆/卡片/成长对比/名片/红包封面五项目） |
| 06 | MiLens Pro（MODAL） | `58:25` | ✅ 已落地 | PaywallView（StoreKit 2 三档产品 + 权益展示 + 购买/恢复） |
| 07 | 我的（ROOT TAB） | `140:415` | ✅ 已落地 | Ledger 账本式设计 + 暖黑 Pro 卡 + 隐私徽章卡 |
| 08 | 照片详情（PUSH） | — | ✅ 已落地 | PhotoViewView（全屏暗色 + 手势 + 底部信息 Sheet + 添加记忆入口） |
| 09 | 添加记忆（SHEET） | — | ✅ 已落地 | AddMemorySheet（类型 tab + Evidence Register + 标题/正文 + CTA） |
| 10 | 拼豆结果（PUSH） | — | ✅ 已落地 | BeadPatternResultView（统计/彩色字母/缩放/保存/分享） |
| 11 | 拼豆设置（PUSH） | — | ✅ 已落地 | BeadSettingsPanelView（5 风格/4 尺寸/高级设置） |
| 12 | 拼豆生成（PROCESS） | — | ✅ 已落地 | BeadPatternView（选图/生成预览/调参/导出） |

### 已知限制（本次落地引入）

以下限制不阻断功能，但影响视觉完成度或数据完整性，需后续迭代收口：

1. **相处章节不支持自定义命名**：章节标题用公式自动推导（「一起生活的第N年」），用户自定义命名属 P1 功能。
2. **首页通知按钮是装饰性**：设计稿的 bell icon 暂不跳路由（Tab 切换无法通过 NavigationLink 实现），后续可改用 `@State` 切 Tab 或 badge 红点。
3. **首页 heroDateString 固定中文星期**：weekday 数组硬编码中文（「星期一」…），未来本地化需改为 `DateFormatter.weekdaySymbols`。**已修复（2026-08-15）**：`HomeHero` 改用 App 匹配语言的 `DateFormatter.weekdaySymbols` 取星期名，日期格式下沉 `home.hero.date %lld %lld %@` 本地化 key。
4. **年份选择器无滚动定位**：当前只做视觉选择，ScrollView 滚动到选中年份的自动定位待优化。**已修复（2026-08-15）**：TimelineView / RecapView 选择器加 `ScrollViewReader`，出现与切换时 `scrollTo` 居中定位选中年份（同时修复 TimelineView `yearSelector` guard 缺 return 的编译错误，`AnyView` 改 `@ViewBuilder`）。
5. **设置页 ProFeature 列表样式**：设计稿未展示多行功能列表，当前用轻量行（图标+标题）而非 LedgerRow 编号样式。
6. **Figma SVG 切图未下载**：MCP 图片目录只读权限导致 SVG 下载失败，全部图标改用 SF Symbol（lock.fill/chevron.right/bell/plus 等），与设计稿矢量一致性可能有细微差异。（注：已决定不再需要设计稿矢量图）
7. **伙伴档案置顶记忆回退策略为随机照片**：无置顶事件/用户记录时，`pinnedMemory` 从全部照片中随机选一张展示（每次进入页面不同，增加新鲜感）。当前随机发生在 SwiftUI 计算属性内，每次 body 重算都会重新随机，可能导致频繁切换；后续可改为 `@State` 固定一张（进入页面时选定）或在 ViewModel 层缓存。**已修复（2026-08-15）**：新增 `@State pinnedRandomIndex` 在 `load()` 内固定随机索引，`PinnedMemory.pick`（拆分至 PetProfilePinnedMemory.swift）改为按索引取片，body 重算不再换图，下次进入页面重新随机。
8. **伙伴档案 Archive Panel 浮起效果**：用 `.padding(.top, -25)` 实现 Hero 底部覆盖，在 ScrollView 内可能因安全区/状态栏交互导致位置偏移，需模拟器视觉验证。
9. **伙伴档案生日日期格式**：`birthday.formatted(.iso8601...)` 产出 `2024.05.16` 格式，与设计稿一致，但未来本地化需验证 locale 行为。
10. **添加记忆入口仅 TimelineView**：`AddMemorySheet` 完整表单已落地，但 `PetProfileView`、`PhotoViewView` 的入口待实现（Life-Archive-Design.md P0）。
11. **置顶记忆/档案起点 UI 展示待实现**：数据字段（`isPinned`/`relatedPhotoID`）和写入已支持，档案首页的置顶记忆首屏展示和档案起点功能待实现。
12. **Windows 环境限制**：所有改动仅经过代码审查与 JSON 校验，**Swift 编译、XCTest、UI 预览、真机验证均未执行**，需在 macOS 环境完成最终验证。

### 待办

- [x] 剩余 8 页设计稿落地（04/05/06/08-12）——全部 12 页均已落地
- [x] macOS 编译验证（全部 Figma 落地改动的类型/并发/资源检查）——已由 CI 代偿（[run 31900122759](https://github.com/altairos/MiLens-iOS/actions/runs/31900122759) 起四作业全绿，最新 [run 31931944133](https://github.com/altairos/MiLens-iOS/actions/runs/31931944133)）
- [x] XCTest 验证（TimelineLogicTests textNote 用例）：4 条主路径（生成/空 body 回落/system 跳过/排序）已随 [run 31931944133](https://github.com/altairos/MiLens-iOS/actions/runs/31931944133) 回归通过；2026-08-16 补充空标题回退默认标签 + relatedPhotoID 回链来源照片 2 条边界用例（共 6 条，随下个 CI run 验证）
- [ ] UI 预览验证（深色模式 + Dynamic Type + iPhone/iPad 尺寸）
- [ ] 真机视觉验收（设计稿一致性 + 交互流畅度）
- [ ] Figma SVG 资源补充（如需精确还原图标，手动导出后放入 Assets.xcassets）

---

## V1.0 发布前待办（用户清单，2026-08-16 整合）

用户自查待办，逐项标注现有代码基础与关联文档：

1. **红包模版（+祝福语具体样式）**：基于现有红包工作室四层架构，为 `newYearRed`/`fortuneGold`/`floralSpring`/`petFresh` 四套模板制作并接入可交付的背景、前景、配饰资源；保留现有模板切换、草稿和导出逻辑，验证 957×1278 导出（`RedPacketCoverLogic`/`RedPacketCoverArtwork` 排版与降级链已就绪，缺素材；关联 [红包封面开发计划](docs/红包封面开发计划.md)）。
2. **纪念式相框 6 种**：以纪念式相框为主（加深情感意义，强化分享冲动）；`DecorationCatalog` + 九宫格缩放/中心参考线/渲染管线已就绪，`catalog.json` 素材未导入（关联 [Frame-Sticker-Development-Plan](docs/Frame-Sticker-Development-Plan.md) §8 M2）。
3. **贴纸 6 种起步、可批量制作**：同上走 `DecorationCatalog` 素材管线（`tools/frame_import.py` 批量导入 + §6 素材制作契约）。
4. **红包封面预览页拟真化**：微信真机截图对照，画矢量实现（现有 `WeChatRedPacketMockView` 4 场景为中性 UI 预览，不复刻微信商标）。
5. **Pro 用户 MiLens 水印开关**：允许 Pro 版用户自行选择水印开关；`ProFeature.watermarkFreeExport` 权益项已预留（2026-08-12），需补用户侧开关 UI。
6. **英文装饰文字多语言方案**：规划英文装饰文字在其他语言版本中的实现方式（Fraunces/英文 label 的语言回退策略，关联 [Localization-Plan](docs/Localization-Plan.md)）。
7. **相处章节自定义命名 UI**：`TimelineLogic` 纯函数已支持 `customNames` 参数，UI 输入未实现（Figma 已知限制 #1）。
8. **App Icon 重做**：猫耳、背景色、背景散落的相片；矢量化（现有 1024×1024 PNG 为占位）。（2026/8/16完成）
9. **引导页缺口饼形与 icon 重做**。
10. **占位文字清查**：确认无残留硬编码（如「小橘」不再硬编码，改用宠物名变量/本地化 key）。

## V1.X 待办（用户清单）

1. **月度/年度精选模版精修**（V1.1，可能增加版式选择；`MemoryRecapLogic` + RecapView 基础已落地）。
2. **相簿浏览模式**（V1.1；MiLensKit `GalleryMode` 枚举已预留：网格免费 / 剪贴簿 / 拍立得散页 / 杂志 Pro）。
3. **彩虹桥 - 触发强化**：时光机推送带缩略图、生日 Hero 替换、时间线门控倒计时条（关联[情感触点备忘](docs/情感触点-Mac待办备忘.md) §6 Stage 4）。
4. **官网从 Cloudflare Pages 迁移到 GitHub 仓库**。
5. **官网精修 + 产品图**。
