# MiLens iOS 工程系统审计报告

- **审计日期**：2026-08-14
- **审计快照**：main 分支（HEAD `e2a91c4`），工作区干净
- **审计方法**：静态代码取证（Grep/行数统计/注解扫描）+ 文档交叉核对（DESIGN/PLAN/DEVELOPMENT/README/AGENTS/project.yml/ci.yml/ADR）+ CI 门禁脚本审读。全部发现附证据引用；未执行 Mac 编译与 XCTest（Windows 环境，与 R1 同源限制）。
- **产出物**：本报告 + [risk-map.dot](risk-map.dot)（风险热图源码）+ [remediation-plan.md](remediation-plan.md)（整改计划）

---

## 1. 总体结论

**架构与工程纪律健康，验证链路存在断层。**

分层架构（View → ViewModel → Service → Repository + 平台协议隔离 + MiLensKit 纯逻辑下沉）执行质量显著高于同类迁移项目：Views 层 0 处越界、18 个真 ViewModel 100% 合规、纯逻辑下沉彻底、代码卫生近零瑕疵。**核心风险不在代码本身，而在「最近 3 天 8+ 个提交全部未经 Mac 编译与 XCTest 验证」的流程断层**——README 宣称的「1198+ 全绿」只覆盖到 2026-08-09，此后的红包封面、备份增强、引导体系、Widget、iPad 自适应等大批量改动（App 层 60+ 文件）验证状态为「未知」。这是上架前必须首先消除的 P0 风险。

| 维度 | 评级 | 摘要 |
|---|---|---|
| 架构健康度 | 🟢 良好 | 分层/模块边界/DI 纪律执行到位，1 处平台隔离偏差 |
| 代码质量 | 🟢 良好 | 卫生近零瑕疵；1 处规模守卫违规（1227 行） |
| 技术债务 | 🟡 可控 | Swift 6 前置项已登记；@unchecked Sendable 25 处大多有注释 |
| 测试覆盖 | 🟡 结构优/门禁弱 | 1916 用例分布合理，但覆盖率基线为占位值从未校准；UI 测试仅 2 冒烟 |
| 文档一致性 | 🟡 漂移 | 三处测试数字互不一致且滞后（1198 vs 1916） |
| 验证链路 | 🔴 断层 | 08-10 起提交均未编译验证，阻塞全部后续验收 |

---

## 2. 风险发现表

严重度 = likelihood × impact；置信度基于直接证据强度。

| ID | 严重度 | 置信度 | 发现 | 证据 |
|---|---|---|---|---|
| R1 | 🔴 P0 高 | high | **验证断层**：2026-08-10~13 全部提交（红包封面 8 连发、备份增强、引导体系、Widget、iPad 自适应）为 Windows 环境产出，App 层未编译、未跑 XCTest、未 UI 预览。README「1198+ 全绿」宣称仅对 08-09 及之前代码有效 | PLAN.md 已知限制第 12 条自认；git log 最近 8 提交均为红包功能；DEVELOPMENT.md:3 快照停在 08-12 |
| R2 | 🟠 P1 中 | high | **规模守卫违规**：`ZipBackupService.swift` 1227 行，超 AGENTS.md §3 的 600 行守卫一倍，含 3 个类（主服务/StreamProgressCounter/ExportSizeGuard），「不留长期豁免」条款被突破 | `wc -l` 实测；文件 34/1182/1210 行三个 class 声明 |
| R3 | 🟠 P1 中 | high | **平台隔离偏差**：`BeadExportService` 直接 `import Photos` + `PHPhotoLibrary.shared().performChanges`（:8/:56），绕过 `PhotoLibraryAccess` 协议抽象，违反 DESIGN.md「业务层不直接依赖具体系统类型」；与 R7 测试缺口同根 | BeadExportService.swift:8,56；对照 Services/Platform/PhotoLibraryAccess.swift 协议在位 |
| R4 | 🟠 P1 中 | high | **覆盖率门禁未校准**：基线 App 30/25/30、Kit 47/50/44 为「对齐源端占位值」，从未被真实 xcresult 校准；行数加权口径 08-13 刚改，首次实测数值未知，门禁当前保护力存疑（过松则漏放行，过严则 CI 恒红） | check-coverage.sh:11-12 头注释自认「首次实测后校准」；DEVELOPMENT.md §2.2 同 |
| R5 | 🟡 P2 中低 | high | **文档漂移**：测试数字三处互不一致——README/DESIGN「1198+（594+604+2）」= 08-09 快照、DEVELOPMENT §1.2「全量 594 用例」、PLAN「894/894」= 08-13 WSL2 快照，而当前静态统计 1916（Kit 1041 + App 875）。宣称「全绿」对新代码不成立，有误导贡献者风险 | README.md:7、DESIGN.md:3,214、DEVELOPMENT.md:3,32,37 vs `func test` 静态计数 |
| R6 | 🟡 P2 中 | high | **UI 测试薄弱**：仅 2 个冒烟用例（MiLensUITests.swift），12 页 RC 设计稿与核心流程（扫描→导入→建档→付费墙→备份）无 UI 回归守护；上架必需的截图产出也未就绪 | MiLensUITests 目录仅 1 文件；PLAN P5 待办自认 |
| R7 | 🟡 P2 低 | high | **平台胶水测试缺口**：`BeadExportService`、`PrintService` 在 MiLensTests 中 0 引用（其余 10 个服务目录均有对应测试） | Grep `BeadExportService|PrintService` 于 MiLensTests = 0 匹配 |
| R8 | 🟢 P3 低 | high | **并发注释纪律缺口**：`ZipBackupService:34` 的 `@unchecked Sendable` 无就地理由注释（DESIGN.md §9.1 要求）；全局 25 处中大多有注释，文件头 1-13 行有并发设计说明，算部分满足 | ZipBackupService.swift:34 vs 文件头注释 |
| R9 | 🟢 P3 低 | high | **解码 fallback 偏差**：`RecapView.loadDownsampled` 2 处失败路径 fallback `UIImage(contentsOfFile:)` 全尺寸解码，与「解码缓冲有上限」纪律存在边缘偏差（仅 CGImageSource 失败时触发） | RecapView.swift:363-374 |
| R10 | 🟢 P3 观察 | high | **上架依赖项未启动**（已知范围汇总）：6 个首发语言翻译未开始、真机验证/性能基准/iPad+深色检查未做、AI 推理质量待真机实测、release 作业未实跑。非新发现，供排期决策 | PLAN.md 里程碑 🟡 状态与 Figma 落地已知限制 12 项 |

## 3. 健康项确认（正面发现）

| ID | 发现 | 证据 |
|---|---|---|
| H1 | **分层纪律优秀**：Views 层 0 处 `import MiLensKit`、0 处直接 `PHAsset/PHPhotoLibrary` 调用；25+ 纯逻辑 struct/enum 下沉（`*Logic`/`*Math`/`*Codec`），符合「决策逻辑下沉为可单测纯函数」 | Grep 全 Views 目录 |
| H2 | **ViewModel 纪律 100%**：18 个真 ViewModel（class + @Observable）全部带 `@MainActor`；拆分文件注释明确「存储属性留主文件（@Observable 宏要求），此处只放行为」 | 注解扫描 52 文件；RedPacketWorkshopViewModel+Cutout.swift:6 |
| H3 | **资源生命周期纪律到位**：全局 7 处 `CGImageSourceCreate` 全部配 `kCGImageSourceThumbnailMaxPixelSize` 降采样；EditorViewModel:475 注释直接引用 DESIGN.md §3 纪律 | Grep CGImageSourceCreate 全工程 |
| H4 | **代码卫生近零瑕疵**：0 `try!`/`as!`、0 密钥/token 硬编码、0 `XCTSkip`、0 真实 TODO/FIXME/HACK（唯一匹配为 URL 格式注释误报） | Grep 多模式扫描 |
| H5 | **红线边界完好**：无 watchOS 代码、无跨平台桥接层；隐私语义在位（本地 AI 推理 ADR-0007、备份不联网、导出走系统 ShareSheet） | 全工程 Grep + ADR-0007 |
| H6 | **工程质量意识高**：check-coverage.sh 自带 `--selftest` 守护加权口径回归（fixture 断言加权 0.30 ≠ 算术 0.5667）；备份恢复具备回滚 + 孤儿清理 + 旧包向后兼容测试；模型交付 SHA256 校验 + 失败绝不带病构建 | check-coverage.sh:66-87、PLAN 2026-08-13 条、tools/fetch-models.sh |
| H7 | **规模守卫历史上执行严格**：此前 6 个超标 View 已全部拆分（TimelineView 1126→539 等），R2 是守卫启动以来首例未拆分超标 | PLAN.md 头部快照 |

## 4. 风险簇分析

### 簇 A：验证链路断层（R1 → R5/R6 → 上架阻塞）

根因是双机协作模式（Windows 写码 + Mac/CI 验证）在 08-10 后 Mac 侧缺位。连锁效应：新代码编译状态未知（R1）→ 覆盖率门禁首次实测被推迟（R4 无法校准）→ 文档只能引用旧快照（R5）→ UI 验证全部积压（R6/R10）。**该簇不消除，其余整改的验收都无法闭环。**

### 簇 B：架构债务（R2 + R3 + R7 + R8 同根）

`ZipBackupService`（超规 + 注释缺口）与 `BeadExportService`（绕协议 + 无测试）都是 08-12~13 快速迭代期的产物：功能正确性优先、边界纪律滞后。共性根因是「交付压力下守卫未自动化」——行数守卫与协议依赖检查目前靠人工自觉，无 CI 拦截。

### 簇 C：质量门禁有效性（R4 + R6）

结构上测试资产优秀（1916 用例、模块对应完整、Kit 可跨平台跑），但门禁两端都弱：覆盖率基线是占位值（下限未校准），UI 端只有 2 冒烟用例（上限无守护）。中间的单测层是唯一有效防线。

## 5. 与 AGENTS.md 契约对照

| 契约条款 | 状态 |
|---|---|
| §2 不提交签名私钥/密钥 | ✅ 通过（H4） |
| §2 不引入 watchOS/跨平台桥接 | ✅ 通过（H5） |
| §2 资源生命周期纪律 | ✅ 基本通过（R9 边缘偏差） |
| §3 分层/模块边界/平台隔离 | ⚠️ 1 处偏差（R3） |
| §3 规模守卫 600/800 行 | ❌ 1 处违规（R2） |
| §3 严格并发纪律 | ✅ 基本通过（R8 注释缺口） |
| §5 验证规则（不只报 BUILD SUCCEEDED） | ❌ 流程断层（R1）——文档自认「未执行」是诚实的，但积累 3 天未消除 |
| §6 文档同步更新 | ⚠️ 漂移（R5） |

## 6. 审计局限

- 静态审计，未执行编译/测试/运行时验证（与 R1 同源限制，Windows 无 iOS SDK）
- 用例数为静态 `func test` 计数，与运行时统计可能有小幅差异（参数化/跳过）
- 未审计 MiLensKit 内部算法实现质量（源端 parity 由 1041 用例守护，属既定信任基线）
- 未审计 Figma 设计稿与实现的像素级一致性（需 Mac 截图，属 R10 范围）
