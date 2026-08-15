# R1 验证断层收口报告（audit-6 终报）

- **日期**：2026-08-15
- **快照**：main `e66a772`；CI 首绿 [run 31900122759](https://github.com/altairos/MiLens-iOS/actions/runs/31900122759)（success，13m3s）
- **前置**：[architecture-review.md](architecture-review.md)（2026-08-14 审计，R1-R10）+ [remediation-plan.md](remediation-plan.md)
- **结论**：**六项风险已消除**——R1/R4/R5 由本链消除，R2/R8/R9 已于 08-14 Windows 整改批次消除（拆分 ZipBackupService、守卫自动化、RecapView 降级修正）。CI 四作业全绿（Kit ✓ / Lint ✓ / App+gate ✓），**2009 用例 0 failed**（Kit 1113 Linux + App 894 macOS 模拟器 + UI 2），覆盖率门禁首次对真实数据 PASS（App 16.2%/16.2%/100% ≥ 13/13/0）。原审计判断「该簇不消除，其余整改的验收都无法闭环」被 25 轮修复链完整验证。

---

## 1. R1 实证链：25 轮 CI 修复（2026-08-14 ~ 08-15）

08-14 审计时 R1 的表述是「3 天 8+ 提交未编译验证，验证状态未知」。恢复过程的实际代价与形态如下——这是「Windows 写码 + CI 代偿验证」模式的完整剖面，供后续流程设计参考：

| 阶段 | 轮次 | 修复内容 | 代表提交 |
|---|---|---|---|
| 一、App 编译恢复 | r1-r8 | 语法错、MainActor 隔离、14+4 条编译错误、FileHandle 新旧 API 混用、显式 return、ToggleStyle | `b885f0e` `fb81072` |
| 二、严格并发 + 测试 target | r9-r17 | species 投影、nonisolated 解码、@escaping、mock 补齐、Test target 编译、**PowerShell 注入字面量 \r\n**（r14 引入 r17 清除） | `f954861` `6afd5ec` |
| 三、运行时修复 | r18-r19 | 13 条运行时断言；ImportService 局部容器提前释放致 SIGTRAP | `d0dc974` `51eaaa5` |
| 四、覆盖率门禁 | r20-r25 | xccov JSON 顶层形状 → import 顺序确定性 → Xcode 16.4 新格式 → Kit 数据混入分离 → basename 对照 → Kit 信息性 + 基线实测校准 | `d80ea25` `d38366b` `5ca322b` |

关键失败 run：31875337701（14 编译错）→ 31891073771（13 断言）→ 31897080607/31897830212（Kit 数据混入 App）→ 31898839674（Kit 完全缺席）→ **31900122759 success**。

**流程教训（已沉淀为经验）**：
- 断层期代码并非全坏——2009 用例一次通过，说明问题集中在「无编译器的环境里写不出可编译的并发胶水」与「门禁脚本从未跑过真实数据」两类，而非业务逻辑。
- Windows 工具链三坑：pwsh 管道会把字面 `\r\n` 注入源文件（r14→r17 花一轮清偿）；`$?` 是布尔非退出码；CI 日志中文被编码切碎，定位需用英文特征串。修源文件禁用 shell 管道写入，改走专用文件工具。

## 2. 本次修复链新增发现

### N1 🟠 P1：App 覆盖率实测 16.2%，0% 大文件集中在断层期功能

门禁 PASS ≠ 覆盖健康。13/13/0 是「实测 - 3pp 缓冲」的诚实下限，非质量背书。run 31900122759 gate 最差文件报告（App-only，行数加权 16.2% = 9907/60997 行）：

| 文件 | 可执行行 | 覆盖 |
|---|---|---|
| TimelineView.swift | 1171 | 0% |
| PhotoViewView.swift | 870 | 0% |
| RedPacketUploadGuideView.swift | 617 | 0% |
| TimelineMemoryCards.swift | 527 | 0% |
| BeadViewModel.swift | 434 | 0% |

全部是 08-10 后快速迭代的功能（红包封面、时间线、照片查看、拼豆入口）——与 R1 断层期完全重合：功能测试通过了（靠集成面），但自身无单测守护。**修复方向**：为上述 ViewModel/决策逻辑补测（参照 `*Logic` 下沉惯例），覆盖提升后把 App 基线从 13/13 分步回调至源端占位值 30/25/30。BeadPatternResultView.swift（1143 行，0%）等同类文件一并纳入。

### N2 🟡 决策记录：MiLensKit 覆盖口径为信息性

xccov 对 SPM 包的 target 归属不稳定（run 31897080607/31897830212 中 Kit 源文件混入 MiLens.app target，31898839674 中完全缺席），脚本无法依赖该数据源。**现行口径**：Kit 数据缺失时跳过、存在时 `[INFO]` 展示不判罚；Kit 质量由 Linux kit 作业（`swift test` 1113 用例全量）守护。**恢复判罚条件**：CI 引入独立 Kit scheme 测试产出稳定 xcresult 后，回调 47/50/44（见 check-coverage.sh 头注释「Kit 口径」）。

### N3 🟢 观察：静态计数与运行时用例数差异

08-14 审计静态 `func test` 计数 1916，CI 运行时实测 2009（差 ~5%，参数化/生成用例所致）。文档口径已统一为运行时实测（audit-5，`e66a772`）。

## 3. 风险表状态更新（R1-R10 → 2026-08-15）

| ID | 原严重度 | 现状 | 说明 |
|---|---|---|---|
| R1 验证断层 | 🔴 P0 | ✅ **消除** | run 31900122759 全绿；文档数字同步（audit-5） |
| R2 ZipBackupService 超规 | 🟠 P1 | ✅ **消除**（08-14） | 拆为 447+505+327 三文件；守卫首跑另发现 5 个存量超标文件按冻结语义登记 ADR-0011 §2.4（见 §4 P1-5） |
| R3 BeadExportService 越协议 | 🟠 P1 | ⬜ 未修 | P2-1；守卫（check-imports）已在 CI 拦复发 |
| R4 覆盖率门禁未校准 | 🟠 P1 | ✅ **消除** | 13/13/0 实测校准（快照 run 31898839674），但见 N1 覆盖本身仍低 |
| R5 文档漂移 | 🟡 P2 | ✅ **消除** | 四文档统一为 CI 实测 2009（`e66a772`） |
| R6 UI 测试薄弱 | 🟡 P2 | ⬜ 未修 | 仍 2 冒烟用例（P2-2） |
| R7 平台胶水测试缺口 | 🟡 P2 | ⬜ 未修 | P2-1 一并处理 |
| R8 并发注释缺口 | 🟢 P3 | ✅ **消除**（08-14） | ZipBackupService 拆分时就地补齐 |
| R9 解码 fallback 偏差 | 🟢 P3 | ✅ **消除**（08-14） | 改 return nil 渲染占位块 |
| R10 上架依赖项 | 🟢 P3 | ⬜ 未变 | 真机/翻译/性能（P2-3/P3-2） |

**新增**：N1（App 覆盖 16.2% + 0% 大文件，🟠 P1，建议列为 P1-4）。

## 4. 后续优先级（更新版）

已完成：P0-1/P0-2（本链）、P1-1/P1-3/P3-1（08-14 批次）、P1-2（audit-5）。剩余按序：

1. **P1-4（新）** N1：0% 大文件补测（TimelineView/PhotoViewView/RedPacketUploadGuideView/TimelineMemoryCards/BeadViewModel + BeadPatternResultView 等）→ 覆盖提升后基线分步回调 30/25/30
2. **P1-5（新）** ADR-0011 §2.4 冻结的 5 个超标文件存量拆分：TimelineLogic 665 / RedPacketExportView 651 / HomeView 648 / SettingsView 633 / PetProfileView 604（只许缩小，拆分后删条目）
3. **P2-1** BeadExportService 收敛到 PhotoLibraryAccess 协议（R3+R7）
4. **P2-2** UI 冒烟清单扩展 5~8 条（R6）
5. **P2-3** 真机验证轮（R10 可执行部分，清单 docs/P2-真机验证备忘.md）
6. **P3-2** 6 语言翻译 / **P3-3** Swift 6 前置项收口（严格并发 complete 编译已过，需零警告常态化）

---

*审计链完结：architecture-review（08-14 快照）→ 25 轮修复 → 本收口报告。后续风险跟踪回归 PLAN.md 状态摘要。*
