# 情感触点系统 — Mac 环境待办备忘

最后更新：2026-08-12（§4 RecapView/TimelineExportCanvas + §5 指标埋点接入 已落地）
关联：[ADR-0010](adr/0010-commercialization-and-emotion-triggers.md) §3 / [PLAN.md](../PLAN.md)

## 背景

情感触点系统 Stage 1–3 的**纯决策逻辑**已全部落地并通过 WSL2 `swift test` 验证（MiLensKit 707 tests，新增 84 个全绿）。但以下 App 层集成与真机验证必须在 **macOS + Xcode** 环境完成（Windows 无法编译 iOS target）。

已完成（纯逻辑层，无需 Mac）：

| 模块 | 位置 | 测试数 |
|---|---|---|
| MemoryCardKind | `MiLensKit/Sources/MiLensKit/Types/MemoryCardKind.swift` | 5 |
| MilestoneLogic | `MiLensKit/Sources/MiLensKit/Milestone/MilestoneLogic.swift` | 28 |
| GrowthCompareLogic | `MiLensKit/Sources/MiLensKit/GrowthCompare/GrowthCompareLogic.swift` | 20 |
| MemoryRecapLogic | `MiLensKit/Sources/MiLensKit/Recap/MemoryRecapLogic.swift` | 18 |
| ExportQuality | `MiLensKit/Sources/MiLensKit/Types/ExportQuality.swift` | 8 |
| MetricsRecorder | `MiLensKit/Sources/MiLensKit/Diagnostics/MetricsRecorder.swift` | 5 |
| BusinessCardTemplate | `MiLensKit/Sources/MiLensKit/Types/BusinessCardTemplate.swift` | 8 |
| PetBusinessCardLogic | `MiLensKit/Sources/MiLensKit/BusinessCard/PetBusinessCardLogic.swift` | 22 |
| WeChatRedPacketSpec + RedPacketCoverLogic | `MiLensKit/Sources/MiLensKit/RedPacket/` | 24 |

## 待办（需 Mac/Xcode）

### 1. App 编译验证 + 修复 [P0，阻塞一切]

Stage 1/2 + 名片卡 + 红包封面的 App 层集成代码在 Windows 上无法编译验证，需在 Xcode 打开工程做首轮编译，修复潜在的类型/并发问题：

- `MiLens/App/Route.swift` — `petCard` 增加 `kind` 参数；新增 `growthCompare`/`businessCard`/`redPacketCover` 路由 case
- `MiLens/App/RootTabView.swift` — 新增 5 个路由分发
- `MiLens/ViewModels/PetCardLogic.swift` — `content()`/`dateLine()` 增加 `kind` 参数
- `MiLens/Views/Create/PetCardView.swift` — 接受 `kind` 参数
- `MiLens/Views/Create/GrowthCompareView.swift`（新建）— 双图对比页
- `MiLens/Views/Create/GrowthComparePhotoPickerView.swift`（新建）— 双选照片
- `MiLens/Views/Create/BusinessCard/BusinessCardPickerView.swift`（新建）— 名片选宠物
- `MiLens/Views/Create/BusinessCard/BusinessCardView.swift`（新建）— 名片卡生成页 + 4 套排版 + FlowLayout
- `MiLens/Views/Create/RedPacket/RedPacketCoverPickerView.swift`（新建）— 红包封面选照片
- `MiLens/Views/Create/RedPacket/RedPacketCoverView.swift`（新建）— 红包封面生成页 + 957×1278 排版
- `MiLens/Views/Create/RedPacket/WeChatRedPacketMockView.swift`（新建）— 4 场景模拟预览
- `MiLens/Views/Create/CreateView.swift` — 创作 Tab 新增「成长对比」「宠物名片」「红包封面」三个入口
- `MiLensTests/PetCardLogicTests.swift` — 新增 3 个 kind 驱动测试

**验证**：`xcodebuild build` + `xcodebuild test`（App target + MiLensKit target）。

### 2. 新增本地化 key [P0，阻塞 UI 文案]

以下新增 key 需补到 `MiLens/Resources/Localizable.xcstrings`，并跑 `tools/localization.py check`：

- `pet.card.birthdayYears %lld` — 「N 岁生日」（PetCardLogic kind=.birthday）
- `memory.kind.*` — MemoryCardKind 6 个类型显示名
- `businessCard.template.*` — BusinessCardTemplate 4 个模板显示名
- `redpacket.guide.step1`…`step5` — 红包封面上传引导 5 步
- `redpacket.guide.eligibility` — 微信红包封面注册门槛提示
- 成长对比/名片卡/红包封面页相关字面量（「选择两张照片」「生成对比卡」「宠物名片」「红包封面」入口标题/描述等）

复数 key（`birthdayYears`、`daysHome`）的 en/de/fr 需补 one/other 变体。

### 2b. 红包封面真机验证要点 [P0，红包封面专属]

- 导出 957×1278 PNG 上传 cover.weixin.qq.com 能否通过规格校验（≤500KB 是硬门槛）
- 高细节照片 PNG 可能超限，需验证导出时的 PNG→JPEG 降级链是否满足大小约束
- 4 场景模拟预览的中性 UI 不复刻微信商标/外观（法理安全）

### 3. NotifyService 里程碑通知调度 [P1]

用 `MilestoneLogic.upcomingMilestones(from:now:daysAhead:)` 在 `MiLens/Services/Notifications` 的每日检查编排中预排近期里程碑通知（100/365/730/1000 天）。

- 复用 `AnniversaryLogic` 已有的每日去重 + 撤销逻辑
- 通知 tap → 路由到 `.petCard(photoID:kind:.milestone)`（需选一张该宠物代表照片）
- 通知 ID 命名空间需与周年通知区分（避免冲突）

**验证**：NotifyServiceTests + 真机通知触发走查。

### 4. RecapView + TimelineExportCanvas 扩展 [P1–P2] ✅ 已落地（2026-08-12）

月度精选 / 年度回忆册 UI 已全部落地：

- [x] 新建 `MiLens/Views/Create/RecapView.swift` — 年份选择器 + 月度精选网格 + Pro 导出（`RecapExportCanvas` 离屏渲染，`ExportQuality.high` 门控）
- [x] `MiLens/Views/Pets/TimelineExportCanvas.swift` — 接受 `ExportQuality` 参数（standard 1080 / high 2400，尺寸按宽度等比缩放）；修复编译 bug（`entryIconColor` 补全 `.textNote`/`.workRecord`）
- [x] 首页「年度回忆」入口卡片（`YearlyRecapEntry`）→ `Route.recap` → `RecapView`
- [x] 免费用户可预览全部代表照片缩略图，Pro 专属完整长图导出

**待真机**：长图渲染内存/尺寸校准（`ExportQuality.high` 长边 2400px 峰值内存）。

### 5. 指标埋点接入 [P1] ✅ 已落地（2026-08-12）

`MetricsRecorder` 已就绪并在以下触点接入：

- [x] `PetCardView.task` → `.memoryCardPreviewed`
- [x] `GrowthCompareView.task` → `.growthComparePreviewed`
- [x] `TimelineView` / `RecapView` 导出按钮 → `.exportStarted` / `.exportCompleted`
- [x] `PaywallView.onAppear` → `.paywallShown`
- [x] `SharePreviewSheet.onAppear` → `.shareSheetOpened`

### 6. Stage 4 — 触发强化与彩虹桥 [P2–P3，部分需产品评审]

- §3.1 强化：时光机推送带缩略图附件（iOS notification image attachment）；生日/领养日首页 Hero 替换 + CTA；时间线门控倒计时条
- 彩虹桥（P3，**需产品/设计评审后再做**）：
  - `Pet` 增加 `passedAwayDate: Date?`（SwiftData schema 迁移 + `SchemaVersion` + 迁移计划 + 测试）
  - 离世宠物时间线不受 365 天门控（完整免费）、档案页纪念态视觉、彩虹桥纪念卡模板
  - 通知/首页温柔触达（首年关键日期）

**验证**：schema 迁移测试 + 离世态 UI 真机走查。

## 附带修复（已在本轮完成）

- `MiLensKit/Tests/MiLensKitTests/DecorationCatalogCodableTests.swift:116` — `.utf8` → `String.Encoding.utf8`（解锁 WSL2/Linux 测试编译，macOS 行为不变）
