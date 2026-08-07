# MiLens iOS 迁移计划

最后核对：2026-08-07（P0 进行中）

> 里程碑与任务清单。架构见 [DESIGN.md](DESIGN.md)，映射与范围见 [MIGRATION_ASSESSMENT.md](MIGRATION_ASSESSMENT.md)，约束见 [AGENTS.md](AGENTS.md)。

## 里程碑总览

| 阶段 | 名称 | 目标 | 状态 |
|---|---|---|---|
| **P0** | Harness 与规划 | 文档骨架、约束、目录结构、XcodeGen 声明、范围对齐 | 🔄 进行中 |
| **P1** | 地基 + 算法核心 | Xcode 工程可编译、SwiftData schema、拼豆 Swift 核心（黄金规格通过）、AI 路线定案 | ⬜ |
| **P2** | 相册 MVP | 扫描发现 + 手动导入 + 相册网格 + 大图查看 | ⬜ |
| **P3** | 宠物档案 | 档案 CRUD + 成长时间线 + 纪念提醒 | ⬜ |
| **P4** | 创作入口 | 拼豆图纸完整流程（选图→生成→预览→A4 导出） | ⬜ |
| **P5** | 首页/我的 + 商业化 | 首页回忆/提醒、设置、StoreKit 订阅、App Store 提审 | ⬜ |

---

## P0 — Harness 与规划（当前）

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
- [ ] **待确认**：范围裁剪与产品对齐（编辑器简化程度、备份是否 V1.0、AI 写真是否 V1.0）

### 验收标准

- 6 份顶层文档齐全且互相链接一致
- `project.yml` 在 Mac 上 `xcodegen generate` 可生成可编译空工程
- 范围「待确认」项有明确结论（产品签字或显式延后）

---

## P1 — 地基 + 算法核心

### P1.1 工程地基

- [x] 在 Mac 上 `xcodegen generate` 生成 `.xcodeproj`，编译空 App 启动（P0 已在 CI 验证 BUILD SUCCEEDED）
- [x] `MiLensApp`（`@main`）组合根 + `scenePhase` 生命周期骨架；`ModelContainer` 待 P1.2 SwiftData `@Model` 接入
- [x] TabView 壳（首页/宠物/创作/我的）+ 路由枚举 `Route` + `AppTab`（`@AppStorage` 持久化选中项）
- [x] 主题 token 翻译：Asset Catalog 语义色（`AccentColor` 品牌色 `#FD8663` + 背景/卡片/文字，含深色 Appearance）+ `Theme.swift`（Spacing/Radius/Size/Motion）；Typography 沿用系统字体（源端无自定义字体文件）
- [x] 本地化 `.strings`（简体中文）；App Icon / 占位图待源端资源整理后补

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

- [ ] `PhotoLibraryAccess`（Photos/PhotosUI）+ mock
- [ ] `FileStorage`（FileManager）+ mock
- [ ] `VisionService`（Vision 分类/主体分割）+ mock
- [ ] XCTest：4 个 mock 基础行为（对应源端 `AdapterContract`）

### P1.5 AI 推理路线定案（关键决策）

- [ ] 调研 Vision 宠物分类能力覆盖（`VNClassifyImageRequest` 动物标签）
- [ ] 调研 Vision 主体分割（`VNGenerateForegroundInstanceMask`，iOS 17）
- [ ] 调研 CLIP → Core ML 转换可行性（coremltools）+ 精度校验方法
- [ ] 评估 PetMatcher 是否必须依赖 CLIP embedding（决定方案 A/B/C）
- [ ] **产出 ADR**：AI 推理框架最终方案（Vision / Core ML / 混合）

### 验收标准

- 工程编译通过，空 App + TabView 可在 iPhone 模拟器启动 ✅（CI run 31187548565）
- SwiftData schema v1 + Repository 测试通过（待 CI 验证）
- MiLensKit 拼豆核心对源端 225 + parity 全绿
- AI 路线 ADR 定案

---

## P2 — 相册 MVP

### 任务

- [ ] `ScanService`：Photos 全库扫描 + 宠物识别（按 P1.5 ADR 实现）+ 取消支持
- [ ] `ScanFlowViewModel`（纯决策）+ `ScanFlowView`：扫描进度/发现/完成文案（翻译源端 `ScanFlowViewModel`）
- [ ] `ImportService`：用户主动导入 → 复制沙盒 → 缩略图 → 宠物匹配关联 → 入库
- [ ] `GalleryView`：网格（LazyVGrid 虚拟化）+ 分页 + 宠物归属筛选 + 多选
- [ ] `GalleryPageState`（纯决策）翻译
- [ ] `PhotoViewView`：大图查看 + 手势（翻译 `PhotoViewGestureMath`）
- [ ] 引导流程：欢迎 → 权限说明 → 扫描 → 创建第一份档案（设计稿首次启动）
- [ ] XCTest：ScanFlow/Import/Gallery 决策逻辑

### 验收标准

- 首次启动完整走通：授权 → 扫描发现宠物 → 建档 → 相册可见
- 相册支持分页、筛选、多选、大图查看
- 扫描可取消，不提交过期结果

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
- 2026-08-07：**P1.2 数据层落地**——SwiftData `@Model`（Pet/Photo/PetEvent，UUID 标识，V1.0 裁剪字段）+ `SchemaV1` + `MiLensMigrationPlan` + Repository 协议/实现（`@MainActor`，EnvironmentKey 注入）+ `MiLensApp` 组合根接入 ModelContainer + Repository 测试（22 用例，含关系删除规则 cascade/nullify + 扫描/导入边界）。待 CI 验证。
- 待办：范围裁剪与产品对齐；P1.3 拼豆核心（并行进行中）；P1.4 平台适配层。
