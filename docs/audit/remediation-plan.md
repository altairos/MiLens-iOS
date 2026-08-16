# MiLens 审计整改计划

配套 [architecture-review.md](architecture-review.md)（2026-08-14 审计）。优先级按「阻塞上架 → 一致性 → 债务清理」排序；每项含验收标准，完成后回写 PLAN.md。

> **进度（2026-08-16）**：✅ P0-1、✅ P0-2、✅ P1-2（本链，25 轮 CI 修复至 run 31900122759 首绿，详见 [verification-recovery-report.md](verification-recovery-report.md)）；✅ P1-1、✅ P1-3、✅ P3-1（08-14 Windows 整改批次）；✅ P1-4、✅ P1-5、✅ P2-1、✅ P2-2（08-16 audit-6 §4 批次，明细见 PLAN.md 状态摘要：App 新增 49 单测 + UI 冒烟 2→6；三守卫全绿 + WSL2 Kit 1113 零回归；App/UI 测试已 CI 验证：[run 31905505907](https://github.com/altairos/MiLens-iOS/actions/runs/31905505907) 全绿，2062 用例 0 failed，基线回调 18/18/0）。待做：P2-3（真机验证轮）、P3-2、P3-3。

---

## P0 — 立即（阻塞全部后续验收）

### P0-1 Mac 编译 + 全量 XCTest（消除 R1）⭐ 第一优先级 ✅ 完成（2026-08-15）

- **动作**：Mac 侧 `xcodegen generate` → `xcodebuild build` → 全量测试（App + Kit + UI）+ WSL2 `swift test`（Kit，Windows 侧可先行）。修复暴露的编译/并发/测试失败。
- **验收**：三端全绿退出码 0；DEVELOPMENT.md §2 验证快照更新为本次实测数字（用例数 + run 链接）；README/DESIGN 的「1198+」同步替换。
- **实际**：以 CI 代偿 Mac（仓库转 public 后额度无限），25 轮修复链；run 31900122759 全绿（Kit 1113 Linux + App 894 + UI 2）。
- **预估**：半天~1 天（视失败量）。

### P0-2 覆盖率基线首次实测校准（消除 R4）✅ 完成（2026-08-15）

- **动作**：在 P0-1 的 xcresult 上跑 `check-coverage.sh`，读真实加权数值；把基线从占位值校准为「实测值 - 2~3pp 缓冲」，写回脚本默认值与 DEVELOPMENT.md §1.2/§2.2。
- **验收**：CI app 作业门禁对真实数据 PASS；基线数字有 xcresult 依据（注明快照日期与 run）。
- **依赖**：P0-1。
- **实际**：基线 13/13/0（快照 run 31898839674，App 加权 line 16.2%/function ~15.7% - 3pp）；Kit 因 xccov SPM 归属不稳定改为信息性口径，恢复条件见 check-coverage.sh 头注释。

## P1 — 本周（守卫与一致性）

### P1-1 ZipBackupService 拆分至 <600 行（消除 R2 + R8）

- **动作**：按职责拆三文件——主服务（协议实现/编排）、`StreamProgressCounter` + `ExportSizeGuard`（独立工具文件）、分卷/快照编解码逻辑可下沉 MiLensKit（纯逻辑，WSL2 可测）。拆分时给 `@unchecked Sendable` 补就地理由注释（R8）。
- **验收**：所有文件 <600 行；`swift test` 全绿（Kit 部分含新增用例）；行为零变更（现有 1089 行测试守护）。

### P1-2 文档数字统一刷新（消除 R5）✅ 完成（2026-08-15，提交 e66a772）

- **动作**：以 P0-1 实测为准，统一 README.md:7、DESIGN.md:3/214、DEVELOPMENT.md:3/§1.2 的用例数与「最后核对」日期；后续约定：每轮 Mac 验证后同提交更新（AGENTS.md §6 已有此要求，落实到每次验证动作）。
- **验收**：`grep` 三文档数字一致且与最新验证快照吻合。
- **实际**：四文档统一为 CI 实测 2009（Kit 1113 + App 894 + UI 2）；历史快照与审计证据记录按日期锚定原则保留。

### P1-3 守卫自动化（根治簇 B：R2/R3 复发）

- **动作**：CI lint 作业加两个轻量脚本——①行数守卫（>600/800 报错，白名单需 ADR）；②Views/Services 层 `import Photos` 审计（Views 禁 PHAsset/PHPhotoLibrary；Services 白名单外禁直接 import Photos）。
- **验收**：故意提交超标文件/越界 import 时 CI 失败；现有代码（除已豁免项）全绿。

## P2 — 上架前（V1.0 提审门槛）

### P2-1 BeadExportService 收敛到 PhotoLibraryAccess（消除 R3 + R7 之半）✅ 完成（2026-08-16）

- **动作**：`PhotoLibraryAccess` 协议补 `save(imageData:as:)` 能力（若缺）；BeadExportService 改走协议注入；MockPhotoLibraryAccess 补实现；App 单测补保存路径（成功/失败/权限拒绝三分支）。
- **验收**：BeadExportService 无 `import Photos`；新增 ≥3 用例；`PrintService` 若无法脱离 UIWindow 依赖则登记为「真机验证项」并注明原因。
- **实际**：协议补 `save`、`IOSPhotoLibraryAccess` 真实实现 + Mock 补齐，`BeadExportService` 改协议注入并移除 `import Photos`；`BeadExportServiceSaveTests` 4 用例；check-imports `FILE_EXEMPTIONS` 清零 + [ADR-0011](../adr/0011-ci-guards-and-photos-exemption.md) §2.2/§5 关闭回写。App XCTest 已 CI 验证（run 31905505907，App 943 用例 0 failed）。

### P2-2 UI 冒烟清单扩展（收敛 R6）✅ 完成（2026-08-16，audit-6 §4 收口口径）

- **动作**：MiLensUITests 从 2 用例扩到核心流程冒烟（Tab 切换 / 扫描入口 / 建档 / 付费墙展示 / 设置备份入口，5~8 条），复用既有 accessibilityIdentifier；截图产出脚本（12 页 RC 页面浅/深色 + iPhone/iPad 关键尺寸）接入 P5 上架流水线。
- **验收**：CI 本地跑通；截图资产入 `fastlane`/`deliver` 目录结构。
- **实际**：冒烟 2→6 条（+创作页→相册扫描入口 / 建档 sheet 开合 / 设置备份入口可见性 / 非 Pro 备份导出弹付费墙并可关闭），按 audit-6 §4 口径「清单扩展 5~8 条（R6）」收口；scheme 已含 UI 测试 target，CI 自动执行，无需改 ci.yml。**截图脚本未做**：属 P5 上架流水线（需 macOS + fastlane/deliver 目录），PLAN.md P5 已挂锚点，不阻塞本项收口。

### P2-3 真机验证轮（R10 的可执行部分）

- **动作**：按 docs/P2-真机验证备忘.md 执行——AI 推理质量（CLIP 归属/RTMPose 关键点）、通知真调度、备份导出/恢复端到端、红包封面导出规格、性能基准（Instruments）。
- **验收**：备忘清单全项打勾并记入 PLAN.md 状态摘要。

## P3 — V1.0 后（低风险技术债）

- **P3-1**（R9）：RecapView fallback 改为失败即返回占位图/nil + 上报诊断，不走全尺寸解码。
- **P3-2**（R10）：6 个首发语言翻译启动（xcstrings export → 翻译 → import → check）。
- **P3-3**：Swift 6 迁移前置项收口（HomeView static DateFormatter 等 DESIGN.md §10 登记 项），目标 `strict-concurrency=complete` 零警告常态化。

---

## 依赖关系

```
P0-1 ──→ P0-2 ──→ P1-2
  │
  └────→ P1-1（独立可先行：纯代码拆分，WSL2 可验证）
P1-3（独立，Windows 可完成）
P2-1/P2-2/P2-3 ──→ 依赖 P0-1 的可编译基线
```

## 责任假设

单人双机工作流：Windows 侧负责 P1-1 前半/P1-3/P3-1/P3-2 的代码与脚本；Mac 侧（本机或 CI）承担 P0-1/P0-2/P2-3 的执行验证。每项完成后在 PLAN.md 状态摘要记一行。
