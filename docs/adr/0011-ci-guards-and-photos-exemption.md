# ADR-0011：CI 守卫自动化与豁免登记（Photos / 存量行数）

- **状态**：Accepted
- **日期**：2026-08-14
- **决策者**：工程
- **关联**：[remediation-plan.md](../audit/remediation-plan.md) P1-3、[architecture-review.md](../audit/architecture-review.md) R2/R3、[DESIGN.md](../../DESIGN.md) 平台隔离、[AGENTS.md](../../AGENTS.md) §3
- **续接**：[ADR-0010](0010-commercialization-and-emotion-triggers.md)；本文为审计整改 P1-3 的守卫决策与首例豁免记录

---

## 1. 背景

审计发现规模守卫（R2：ZipBackupService 1227 行）与平台隔离（R3：BeadExportService 绕过 `PhotoLibraryAccess` 协议直接 `import Photos`）两处纪律突破，共性根因是「守卫未自动化，靠人工自觉」——见 architecture-review.md 簇 B。整改 P1-3 要求把两条规则接入 CI lint。

## 2. 决策

### 2.1 守卫自动化（tools/ 两个脚本，接入 CI lint 作业）

| 脚本 | 规则 |
|---|---|
| `check-file-size.py` | 默认上限 600 行；MiLensKit/Sources 与 App 层 Editor 目录（算法/编辑器核心）800 行；白名单逐文件登记且必须挂 ADR，脚本校验 ADR 存在，无 ADR 的豁免直接失败 |
| `check-imports.py` | Views 全层禁 `import Photos` 与 PH 框架符号；Services 仅 `Platform/`（适配器所在地）与 ADR 豁免文件可用；`import PhotosUI`（声明式 PhotosPicker 等系统 UI 组件）不属违规；注释行剥离后不匹配 |

行数分类依据：AGENTS.md §3「单文件超 600 行（编辑器/算法核心 800 行）须拆分」。Kit 整体视为算法核心（拼豆算法/工具收敛地）；App 层含 `Editor` 目录段的路径（Views/Editor、ViewModels/Editor、Services/Editor）视为编辑器核心。测试目录不在守卫范围（测试是行为规格载体，非产品代码）。

### 2.2 首例豁免：BeadExportService 的 `import Photos`

- **现状**：`MiLens/Services/BeadExportService.swift` 直接 `PHPhotoLibrary.shared().performChanges` 保存导出图（红包封面/拼豆/宠物卡片等共用），绕过 `PhotoLibraryAccess` 协议抽象。
- **豁免理由**：功能已被 2026-08-13 前的红包封面 8 连发提交广泛依赖（4 个 View 复用其保存能力），立即改协议注入需同步补 Mock 与测试（P2-1 范围），不宜与守卫上线混在一次变更。
- **期限与移除条件**：P2-1 完成（`PhotoLibraryAccess` 协议补 `save(imageData:as:)` + Mock 实现 + ≥3 用例）后，从 `check-imports.py` 的 `FILE_EXEMPTIONS` 删除本条目并关闭本节。
- **防复发**：豁免期间任何新增文件不得进入白名单，除非有新的 ADR。

### 2.3 顺带清理

4 个 View 的冗余 `import Photos`（RedPacketExportView/PetCardView/BusinessCardView/GrowthCompareView）——仅头注释提及 PHPhotoLibrary、代码零符号使用——直接删除，不开豁免。

### 2.4 存量超标文件登记（守卫首跑发现，冻结语义）——已全部关闭

`check-file-size.py` 首次全量运行（2026-08-14）发现 5 个既存超标文件，属审计 R2 同类存量（此前人工取证遗漏——这正是守卫自动化的直接价值）。

豁免不是免死金牌，而是**冻结**：登记当前行数，豁免期间继续增长直接失败，只许缩小；每项拆分至 <600 行后删除条目并关闭对应行。拆分批次记入 PLAN.md 待办。

**2026-08-15 拆分批次全部完成**，`FILE_EXEMPTIONS`/`FROZEN_LINES` 已清空（守卫复跑：312 个源文件全绿）：

| 文件 | 冻结行数 | 拆分后 | 拆出/说明 |
|---|---|---|---|
| `MiLens/ViewModels/TimelineLogic.swift` | 665 | 395 | → `TimelineArchiveLogic.swift`（278，Life-Archive P3.6 增强段） |
| `MiLens/Views/Create/RedPacket/RedPacketExportView.swift` | 651 | 313 | → `RedPacketScenePreview.swift`（183）+ 删除不可达死代码段（规格校验/水印状态/本地保存链） |
| `MiLens/Views/Home/HomeView.swift` | 648 | 202 | → `HomeSections.swift`（464） |
| `MiLens/Views/Settings/SettingsView.swift` | 633 | 516 | → `SettingsBackupFlow.swift`（142） |
| `MiLens/Views/Pets/PetProfileView.swift` | 604 | 506 | → `PetProfilePinnedMemory.swift`（117） |

## 3. 影响与落地

- CI lint 作业新增两步（`check-file-size.py` / `check-imports.py`），PR 与 main push 均拦截。
- 验收标准（remediation-plan P1-3）：故意提交超标文件/越界 import 时 CI 失败；现有代码（除 ADR 豁免项）全绿。
- 本 ADR 即 `FILE_EXEMPTIONS` 首条目引用的登记文件；后续每个新豁免项须续写新 ADR（或在本文件追加节并同步更新引用）。

## 4. 风险与权衡

- **误报**：符号级检查可能误伤字符串字面量中的 `PHAsset` 等字样（当前全库无此用法）；注释已剥离。若未来出现误报，优先改代码风格而非放宽规则。
- **行数分类简化**：以目录而非逐文件判定「算法/编辑器核心」，个别边界文件（如 Editor 目录下的轻量 View）获得 800 上限属可接受误差——守卫目标是拦截失控膨胀而非精确分类。
- **PhotosUI 放行**：`PhotosPicker` 是 SwiftUI 声明式系统组件，与 `ShareLink` 同级；若后续出现经 PhotosUI 间接使用 PHAsset 的路径，符号级检查仍会拦截。

## 5. 后续追踪

- P2-1 完成后回写本文件 §2.2 状态并删除脚本白名单条目。
- ~~§2.4 存量行数豁免随拆分批次逐项删除（先小后大：PetProfileView → SettingsView → HomeView → RedPacketExportView → TimelineLogic）~~ 已完成（2026-08-15，见 §2.4 表）。
- 守卫脚本自身变更（规则调整/白名单增删）须在本 ADR 追加记录。
