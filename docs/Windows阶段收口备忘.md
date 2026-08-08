# Windows 阶段收口备忘

最后更新：2026-08-08（Windows 阶段收口，转云 Mac）

> 本文档记录在 Windows 开发机上完成的全部工作、CI 状态、WSL2 环境问题，以及转云 Mac 前的准备清单。架构见 [DESIGN.md](../DESIGN.md)，计划见 [PLAN.md](../PLAN.md)。

---

## 1. Windows 阶段完成范围

### 1.1 可编译验证工作（通过 WSL2 / GitHub Actions CI）

| 层 | 内容 | 用例数 | 状态 |
|---|---|---|---|
| **MiLensKit** 拼豆算法核心 | 色彩/色板/管线/草稿/评分/渲染/导出/诊断（对应源端 `shared` C++ 3,665 行 + ArkTS 9,012 行） | 225+ | ✅ |
| **MiLensKit** 编辑器纯逻辑 Phase 1-2 | 调色/锐化/裁切/图层/几何/EXIF/文档/历史（对应源端 `editor/` 纯逻辑） | 53 | ✅ |
| **App 层** P2 纯决策+Service | 相册/扫描/导入/质量评分/重复分组（6 决策模块 + ScanService + ImportService + QualityScorer） | ~84+15+13 | ✅ |
| **App 层** P3 纯决策+ViewModel | 宠物档案/表单/时间线（3 决策模块 + 3 ViewModel） | 84 | ✅ |
| **App 层** P5 回忆/通知纯逻辑 | TimeMachineLogic / AnniversaryLogic / NotificationScheduleLogic | 待补 | 🔄 |

### 1.2 文档与工程骨架

- 6 份顶层文档齐全（AGENTS / DESIGN / PLAN / MIGRATION_ASSESSMENT / DEVELOPMENT / README）
- UI 设计规范定稿（[UI-DESIGN.md](../UI-DESIGN.md)）+ 设计系统 token 全部代码化（18 colorset + Typography + 字体子集化 3.31 MB）
- XcodeGen `project.yml` + MiLensKit 本地 Swift Package + 目录骨架
- 云端 CI（`.github/workflows/ci.yml`）：Linux MiLensKit + macOS App 双作业
- AI 路线 ADR 定案（[ADR-0007](adr/0007-ios-ai-inference-route.md)，方案 A 全转换）
- V1.0 范围定案（[ADR-0008](adr/0008-v1-scope-decision.md)）
- 本地化工具链（`tools/localization.py`，任意语言 String Catalog 导出/导入/check）
- AI 模型转换工具链（3 个 Python 脚本，转换实跑需 macOS）

---

## 2. CI 状态

最新 CI run [31240187728](https://github.com/altairos/MiLens-iOS/actions/runs/31240187728)：**全绿 ✓**

- MiLensKit (Linux)：Build + Test 通过（~1m22s）
- MiLens App (macOS)：Build + Test 通过（~6m30s）

### 收口前修复的两个 CI 失败

提交 `78e5d4b` 引入两处问题（已在 `1dabff5` + `fd38942` 修复）：

| 问题 | 根因 | 修复 |
|---|---|---|
| `TaskLoggerTests` 21 处编译错误 | `complete`/`cancel` 方法签名是 `(_ taskId: Int, summary: String? = nil)`，测试用位置参数调用缺 `summary:` 标签 | 补齐 21 处参数标签 |
| `BeadSettingsLogicTests` 断言失败 | 测试断言 illustration_v1 尺寸 58 映射为 `"large"`，但源端逻辑 `size <= 52 → large, else jumbo`，58 > 52 正确结果为 `"jumbo"`。源端原始测试只检查 `length > 0`，iOS 测试断言推理写错了 | 修正断言为 `"jumbo"` |

---

## 3. WSL2 环境状态

### 3.1 已知问题

WSL2 虚拟机平台可能因系统更新/重启后未自动恢复，报错：

```
HCS_E_HYPERV_NOT_INSTALLED
```

三个发行版（`Ubuntu-MiLens` / `Ubuntu-24.04` / `docker-desktop`）均 Stopped。

### 3.2 修复方法（管理员权限 + 重启）

```powershell
# 管理员 PowerShell
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
# 然后重启电脑
# 如果仍不行，检查 BIOS 中 CPU 虚拟化 (VT-x / AMD-V) 是否开启
```

恢复后验证：

```bash
wsl -d Ubuntu-24.04
cd /mnt/e/iOSprojects/MiLens/MiLensKit
swift build && swift test --parallel
```

> WSL2 环境搭建详见 [DEVELOPMENT.md](../DEVELOPMENT.md) §2.1 和记忆 `WSL2 Ubuntu-24.04 Swift编译环境`。

---

## 4. 转云 Mac 前准备清单

### 4.1 必须在 Mac 上做的工作

| 优先级 | 工作项 | 说明 | 预估 |
|---|---|---|---|
| **P0** | `xcodegen generate` 生成工程 + 确认编译 | 首次在真 Mac 上打开工程 | 0.5h |
| **P0** | 调试 30 个跳过的 SwiftData 集成测试 | `ScanServiceTests`(7) + `ImportServiceTests`(8) + `QualityScorerTests`(8) + `StylizedDraftGenerator`(1)，模拟器 CI 中 `Early unexpected exit` 崩溃 | 2-4h |
| **P1** | Core ML 模型转换 | `convert_clip_coreml.py`（CLIP ~42 MB INT8） + `convert_rtmpose_coreml.py`（~3 MB），coremltools 仅 macOS | 2-4h（含精度校验） |
| **P1** | 真实平台实现 | `IOSPhotoLibraryAccess`(Photos) / `IOSVisionService`(Vision) / `CoreMLInferenceEngine`(Core ML) / `IOSFileStorage`(FileManager) | 1-2d |
| **P2** | P3 宠物档案 View 层 | `PetProfileView` / `PetEditView` / `TimelineView` + `UNUserNotificationCenter` | 1d |
| **P2** | P4 编辑器 Phase 3 App 层 | `Views/Editor/` + `EditorViewModel` + 裁切/滤镜/标注 UI | 2-3d |
| **P3** | P5 首页/我的 + StoreKit | `HomeView`(回忆) / `SettingsView` / StoreKit 2 订阅 + 付费墙 | 1-2d |
| **P3** | 真机验证 | Photos 权限 + Vision/Core ML 推理 + 分页性能（清单见 [P2-真机验证备忘](P2-真机验证备忘.md)） | 0.5-1d |
| **P4** | App Store 签名/上架 | `release` workflow（archive → export → altool 上传） | 1d |

### 4.2 账号与凭证准备

- [ ] Apple Developer 账号（$99/年）已激活
- [ ] App Store Connect API Key（`.p8`）生成，准备注入 GitHub Secret（用于云端签名上传）
- [ ] Bundle Identifier 确定并在 Apple Developer Portal 注册（如 `com.milens.app`）
- [ ] 在 `project.yml` 中填入 Team ID

### 4.3 代码与 CI 确认

- [x] 代码已推送 GitHub（`altairos/MiLens-iOS`，main 分支）
- [x] CI 全绿（MiLensKit + App 编译测试通过）
- [ ] 确认 `project.yml` 中 Bundle ID / 版本号 / Team ID 已填
- [ ] 准备 App Store 元数据（App 名/副标题/描述/关键词/截图尺寸规格）

### 4.4 模型资产准备

- [ ] 准备校准图片集（~100 张宠物照片）用于 CLIP INT8 量化校准
- [ ] 源端 `rtmpose_t_pet_face.onnx` 路径确认（`e:\HarmonyProjects\MiPhoto2\rtmpose_t_pet_face.onnx`）
- [x] `pet_text_embeddings.f32` 已在 `Resources/Models/`（40 KB，已校验）

### 4.5 云 Mac 环境

- [ ] Xcode 15+ + iOS 17 SDK
- [ ] `brew install xcodegen`
- [ ] `git clone https://github.com/altairos/MiLens-iOS.git` + `xcodegen generate` 能成功
- [ ] 模型转换环境：`python3 -m venv .venv-models && pip install -r tools/requirements-models.txt`

### 4.6 iPhone 真机（如要调试 Photos/Vision/Core ML）

- [ ] iOS 17+ 的 iPhone，通过 USB 连接云 Mac（或云 Mac 提供的远程真机服务）
- [ ] 开发者证书 + Provisioning Profile 配置

---

## 5. 优先策略建议

云 Mac 时间分配建议（按价值密度排序）：

1. **Core ML 模型转换**（2-4h）——解锁 AI 推理链路，是扫描/拼豆/编辑器的共同依赖
2. **调试 30 个跳过的 SwiftData 集成测试**（2-4h）——解锁 SwiftData 集成验证，ScanService/ImportService/QualityScorer 全链路
3. **真实平台实现**（1-2d）——`IOSPhotoLibraryAccess` / `IOSVisionService` / `CoreMLInferenceEngine`，从 mock 到真实
4. **P3/P4 View 层**（2-3d）——SwiftUI 页面，模拟器即可
5. **真机走查 + 上架**（1-2d）——发布前质量门禁

> UI 编写（P3/P4 View）可以在模拟器上做，真机走查放最后。模型转换和 SwiftData 测试调试是 Mac 时间的最高价值用途。
