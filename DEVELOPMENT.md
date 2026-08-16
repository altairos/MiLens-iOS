# MiLens iOS 开发说明

最后核对：2026-08-17（质量复评 N1-N8 修复收口：N1 两处 Onboarding stageRow 编译错误（CI 红灯根因）；N7 Swift 6 严格并发警告源码层清理（App/Widget/Kit 17 文件）+ PetEditView 头像按钮三元分支语义修正；N6 UI 测试 11 处中文文案断言迁移 accessibilityIdentifier（identifier = loc key 约定，6 个视图文件同步标注）；N8 token lint 143 处 INFO 复评维持不判罚（docs/UI-Rework计划.md 批次 A）；N2 main 分支保护落地（见 §2.2）；收口 CI 全绿 run 31961932575（N1-N8 修复 2cdb662 + 本地化回退 b3b0a79）：Kit 1116（Linux）+ App 965（模拟器）+ UI 6 = 2087 用例全绿，覆盖率门禁通过（App line/function 加权均 21.9%，基线 18/18/0）；其间排查并回退 1c623e9 误入主 catalog 的 117 条 en 初译——en 模拟器 preferred localization 变为 en 后其余 key 缺译返回 key 本身，App Test exit 65，en 初译仍以 xlsx 为唯一事实来源（红线见 docs/Localization-Plan.md §5.4）；此前 2026-08-16：P0–P5 实现完成；CI 全绿 run 31905505907：Kit 1113（Linux）+ App 943（模拟器）+ UI 6 = 2062 用例全绿，覆盖率门禁基线回调 18/18/0（App 加权 line/function 21.3%）；真机与性能验收待做，清单见 docs/P2-待办清单.md）

> 环境、命令、开发约定、可复现验证快照。架构见 [DESIGN.md](DESIGN.md)，计划见 [PLAN.md](PLAN.md)，约束见 [AGENTS.md](AGENTS.md)。

## 1. 环境要求

| 组件 | 要求 |
|---|---|
| macOS | 13+（Xcode 15 要求） |
| Xcode | 15.0+（iOS 17 SDK + SwiftData + `@Observable`） |
| Swift | 5.9+ |
| iOS 部署目标 | 17.0 |
| XcodeGen | 2.40+（项目文件生成） |
| Cocoapods / SPM | 优先 SPM；`MiLensKit` 为本地 Swift Package |

> **多机协作的分层方案**：iOS App（SwiftUI/SwiftData/Photos/Vision）绑定 iOS SDK + Xcode。但本项目结构天然分层，本地可覆盖最高频的算法迭代，App 层可走云端 CI（当前主开发环境为 macOS，本节同时保留 Windows/WSL2 与云端方案供多机协作）：
>
> | 层 | 编译位置 | 命令 | 说明 |
> |---|---|---|---|
> | **MiLensKit**（纯 Swift 拼豆算法包） | 本地 WSL2 Ubuntu | `swift build` / `swift test` | 纯 Foundation + XCTest，不需 iOS SDK。这是翻译 3665 行 C++ + 9012 行 ArkTS 的高频 TDD 核心 |
> | **MiLens App**（SwiftUI/SwiftData 等） | GitHub Actions macOS runner | push 自动触发 `xcodegen` + `xcodebuild` | 见 `.github/workflows/ci.yml`。无法本地编译/真机调试 |
> | 真机调试 / 签名上架 | 借/租 Mac | Xcode + 真机 | 仅上架与真机联调时需要 |
>
> 真机、模拟器 UI、签名打包仍需 Mac + Xcode；可用云 Mac 租赁（MacinCloud/MacStadium）按需获取。

## 2. 常用命令

### 2.1 本地：MiLensKit 纯算法包（Mac 或 WSL2 Ubuntu-24.04，最高频）

**Mac 直接跑（推荐）**：包已声明 `.macOS(.v13)`，全量 1113 用例可在 macOS 上独立验证，无需 iOS 模拟器：

```bash
cd MiLensKit
swift build              # 编译拼豆包
swift test               # 全量 XCTest（1113 用例）
```

> 注意：macOS 上 Quickdraw（经 XCTest→AppKit 传递导入）与包内 `RGBColor` 同名，
> 用到该类型的测试文件已用 `import struct MiLensKit.RGBColor` 显式绑定，勿删除。

**WSL2 Ubuntu-24.04**：

> ⚠️ **必须用 Ubuntu 24.04 发行版**，不能用 26.04：Swift 6.1.3 为 24.04 编译，依赖的 `libxml2.so.2` / `libpython3.12` 在 26.04 上 soname 已变（`.so.16` / Python 3.14），ABI 不兼容，apt 也无法解决。已安装发行版名 `Ubuntu-24.04`（root 用户，apt 无需密码）。

Swift 工具链装在 `/opt/swift`（Swift 6.1.3），PATH 已写入 `/etc/profile.d/swift.sh` + `/root/.bashrc`，新 shell 自动可用。

```bash
# 进入 24.04 发行版
wsl -d Ubuntu-24.04
# 已有 swift 在 PATH（无需手动 export）
cd /mnt/e/iOSprojects/MiLens/MiLensKit
swift --version          # Swift version 6.1.3
swift build              # 编译拼豆包
swift test --parallel    # 跑 XCTest（源端 225 用例翻译后在此守护）
```

VS Code 用 **Remote-WSL** 扩展打开 `\\wsl$\Ubuntu-24.04\mnt\e\iOSprojects\MiLens`，选 Ubuntu-24.04，即获得 sourcekit-lsp 跳转/补全（LSP 已随工具链提供）。

#### 一次性环境搭建（已在 P0 完成，备记录）

```bash
# 在 Ubuntu-24.04（root）内，一次性执行过：
apt-get update
apt-get install -y --no-install-recommends \
  build-essential libxml2 libxml2-dev libcurl4-openssl-dev \
  libsqlite3-0 libsqlite3-dev libpython3-dev libpython3.12 \
  libncurses-dev binutils zlib1g-dev pkg-config wget ca-certificates
# Swift 6.1.3 工具链已解压到 /opt/swift
```

### 2.2 云端：App 全量编译 + 上架（GitHub Actions）

仓库 https://github.com/altairos/MiLens-iOS（私有）。推送即触发 `.github/workflows/ci.yml`（PR 与 main/master push 均运行三个作业）：

1. `MiLensKit (Linux)`——ubuntu-24.04 上 `swift build/test`，约 50s。
2. `Lint (tokens + size + isolation + i18n)`——ubuntu-24.04 上 `check-ui-tokens.py`（色值硬门禁）+ `check-file-size.py`（600/800 行规模守卫，白名单豁免挂 ADR 且冻结行数，[ADR-0011](docs/adr/0011-ci-guards-and-photos-exemption.md)）+ `check-imports.py`（Photos 平台隔离：Views 禁 import/符号，Services 仅 Platform/ 与 ADR 豁免）+ `localization.py check`（key 完整性 + 占位符门禁；CI 带 `--allow-missing-translations` 把非源语言缺译降为警告——7 语言翻译过渡期放行，避免 lint 挂掉连带跳过 app 作业，翻译完成后移除），约 10s。
3. `MiLens App (macOS)`——macos-15 runner 上 `tools/fetch-models.sh`（从 Release 下载生产模型 + SHA256 校验，`actions/cache` 缓存 `MiLens/Resources/Models`，命中则幂等跳过）→ **再** `xcodegen generate`（顺序约束：XcodeGen 生成工程时模型必须已存在，否则 `.mlpackage` 不会进入 Resources Build Phase，正式包会静默降级到 Vision）→ `xcodebuild build` → **产物断言**（`tools/assert-built-models.sh` 校验 `.app` 内含编译后 `.mlmodelc`，防静默降级）→ `xcodebuild test`（含覆盖率，`-resultBundlePath build/TestResult.xcresult`）→ **覆盖率门禁**（`tools/check-coverage.sh --selftest` 固定 fixture 自测 + 解析 xcresult，line 覆盖率按行数加权（非等权平均，避免大文件低覆盖被小高覆盖文件稀释高估），按 MiLens/MiLensKit 目标与基线比较，任一指标不达标即失败；基线为占位值，首次实测后校准，见脚本头注释），约 4-5 分钟（依赖 MiLensKit + Lint 作业通过）。

查看：`gh run list --repo altairos/MiLens-iOS` 或 https://github.com/altairos/MiLens-iOS/actions。

**分支保护（2026-08-17 配置）**：`main` 已启用温和版保护——三个 CI check（`MiLensKit (Linux)` / `Lint (tokens + size + isolation + i18n)` / `MiLens App (macOS)`）设为 required，禁止 force push 与删除分支；`enforce_admins=false` 刻意保留单人直推工作流（直推不被拦截，CI 不绿仅标记红叉，靠 run 盯梢收敛）；PR 合并须等三检查通过。调整走 `gh api -X PUT repos/altairos/MiLens-iOS/branches/main/protection`（布尔参数必须用 `-F` 传类型化值，`-f` 传字符串会 422）。

#### 上架路径（免 Mac 一条龙）

编译、签名、上传 App Store 全部可在同一个 macOS runner 完成，无需本机 Mac：

```
macos-15 runner
  ├─ xcodegen + xcodebuild build          ← 已验证
  ├─ xcodebuild archive                   ← release 作业（已实现）
  ├─ xcodebuild -exportArchive            ← release 作业（已实现，.p8 App Store Connect API Key 自动签名）
  └─ xcrun altool upload                  ← release 作业（已实现，苹果官方上传，免费）
```

`release` 作业（`.github/workflows/ci.yml`）由 `workflow_dispatch` 手动触发，质量门禁为 kit + lint + app 作业全绿后才运行。触发时填写：`version`（MARKETING_VERSION）、`buildNumber`（CURRENT_PROJECT_VERSION，须大于 App Store Connect 已有值）、`upload`（false = 仅生成签名 IPA 供人工验证，不上传）。

**Secrets 配置**（仓库 Settings → Secrets and variables → Actions，一次性）：

| Secret | 值 |
|---|---|
| `ASC_API_KEY` | App Store Connect API Key 的 `.p8` 私钥文件**内容**（含 `-----BEGIN PRIVATE KEY-----` 两行） |
| `ASC_API_KEY_ID` | ASC「用户与访问 → 集成 → App Store Connect API」的 Key ID |
| `ASC_API_ISSUER_ID` | 同页面的 Issuer ID（UUID） |
| `ASC_TEAM_ID` | Apple Developer Team ID（10 位字母数字，archive/export 的 `DEVELOPMENT_TEAM`） |

`.p8` 生成：App Store Connect → 用户与访问 → 集成 → App Store Connect API → 生成密钥（需 Account Holder 权限，仅显示一次，下载后立即存入 Secret，**不入库**）。签名走 `xcodebuild -authenticationKey*` 自动签名（无需钥匙串/证书私钥），上传走 `xcrun altool --upload-app`——iOS App 不需要 notarytool（那是 macOS 公证工具）。`appuploader`/「开心上架」等第三方工具适用于「IPA 已生成、只需在 Windows 本地重传」场景，对原生项目非必需（IPA 本身仍需 macOS runner 产出）。

> **免费额度**：公开仓库 macOS runner 无限免费；私有仓库 macOS 分钟按 10× 计费（每月 2000 免费分钟 ≈ 200 macOS 分钟，足够每日多次编译）。当前仓库为私有，可随时切公开获得无限额度。

**真正还需要 Mac 的只有**：真机调试、模拟器 UI 人工验证、Instruments 性能分析——这些是发布前质量门禁，无法云端替代。

### 2.3 Mac 本地（借/租 Mac 时）

```bash
# 生成 Xcode 工程（每次 project.yml 变更后执行）
brew install xcodegen          # 首次
xcodegen generate

# 打开
open MiLens.xcodeproj

# 命令行构建（模拟器）
xcodebuild -project MiLens.xcodeproj \
  -scheme MiLens \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build

# 运行测试
xcodebuild -project MiLens.xcodeproj \
  -scheme MiLens \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test

# 仅 MiLensKit 测试（拼豆算法）
xcodebuild -project MiLens.xcodeproj \
  -scheme MiLensKit \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test

# 测试覆盖率
xcodebuild ... test -enableCodeCoverage YES
# 结果在 DerivedData/.../*.xcresult，用 xcrun xcresulttool 或 Xcode Report Navigator 查看

# CI 覆盖率门禁（与 .github/workflows/ci.yml 同用法；基线可用环境变量覆盖）
# line 覆盖率为行数加权（Σ已覆盖行/Σ可执行行）；xccov 未提供行数时回退文件级算术
# 平均并打印 [note]。另打印倒数 5 个最差文件报告（可执行行 ≥ FILE_MIN_LINES）。
tools/check-coverage.sh build/TestResult.xcresult
#   APP_LINE_MIN/APP_FUNCTION_MIN/APP_BRANCH_MIN   MiLens (App) 基线，默认 18/18/0
#     （分步回调：2026-08-15 首次校准 13/13/0——App 加权 line 16.2%（9907/60997）
#      /function ~15.7%，快照 run 31898839674；2026-08-16 P1-4 补测后回调 18/18/0
#      ——加权 line/function 均 21.3%，快照 run 31905505907；均按「实测值 -3pp 缓冲」。
#      branch=0 因 xccov 新格式无 branches 数据，按 100% 计、未参与判罚）
#   KIT_LINE_MIN/KIT_FUNCTION_MIN/KIT_BRANCH_MIN   MiLensKit 基线（信息性不判罚：
#     xccov 对 SPM 包 target 归属不稳定——run 31897080607/31897830212 混入 App
#     target、run 31898839674 完全缺席——数据缺失时跳过、存在时仅展示；Kit 质量
#     由 Linux kit 作业 swift test 全量用例守护）
#   FILE_MIN_LINES    最差文件报告忽略小文件的阈值（可执行行，默认 50）
#   APP_FILE_MIN/KIT_FILE_MIN   可选单文件行覆盖下限（百分数，默认 0=关闭）
```

## 3. 项目结构约定

目录结构见 [DESIGN.md](DESIGN.md) §3。要点：

- `MiLens/` —— App target
- `MiLensKit/` —— 本地 Swift Package（拼豆算法，对应源端 `shared` HSP）
- `project.yml` —— XcodeGen 声明（**唯一受版本控制的项目配置**，`.xcodeproj` 由其生成，可 gitignore）
- **Info.plist 由 `project.yml` 生成**：`targets.MiLens.info.properties` 是 `MiLens/Resources/Info.plist` 内容的唯一事实源，`xcodegen generate` 会用这些 properties 重新生成 Info.plist。需要新增/修改 Info.plist 键（如 `UTExportedTypeDeclarations`/`UIFileSharingEnabled`/`CFBundleDocumentTypes` 等）时，**必须改 `project.yml` 对应 properties，不要直接改 Info.plist**（会被下次生成覆盖）。例外：本地化权限文案（`NSPhotoLibraryUsageDescription` 等）走 `InfoPlist.xcstrings`，Xcode 15+ 构建时自动注入，不在 project.yml 重复维护。
- GitHub 仓库：https://github.com/altairos/MiLens-iOS（私有）
- 资源统一在 `MiLens/Resources/Assets.xcassets`

## 4. 开发约定

### 4.1 从源端翻译代码

1. **先读源端测试**：迁移某模块前，先读 `e:\HarmonyProjects\MiPhoto2` 对应的 `.test.ets`，理解行为规格。
2. **测试先行**：把源端测试翻译为 XCTest（作为规格），再写 Swift 实现。
3. **纯逻辑优先**：源端纯逻辑 ViewModel/纯函数（无 IO/无 ArkUI 依赖）直接翻译为 Swift `struct`/纯函数，XCTest 完整覆盖。
4. **保留诚实标注**：源端对未完成功能（如 pose 占位、中心裁切分割）有明确降级说明，iOS 侧必须同等标注，不得夸大。

### 4.2 Swift 风格

- 值类型优先（`struct`），持久化用 `@Model class`。
- 错误用 `enum ConformError: Error` + `throws`，不吞异常、不滥用 `try?`。
- 异步用 `async/await` + `Task`，长任务支持 `Task.cancel()`。
- 避免强制解包 `!`（`@IBOutlet` 等 IBOutlet 除外，本项目以 SwiftUI 为主基本不用）。
- 访问控制：`MiLensKit` 内部类型默认 `internal`，仅导出面标 `public`。

**严格并发（2026-08-09 起 `SWIFT_STRICT_CONCURRENCY=complete`）**：

- 页面 ViewModel 一律 `@MainActor`；跨隔离边界只发送 `Sendable` 值，`Task.detached` 以捕获值传参，不捕获非 Sendable 的 `self`/View struct。
- 平台适配层/mock 的 `@unchecked Sendable` 必须附理由注释；禁止新增无说明的 `@unchecked Sendable`/`nonisolated(unsafe)`。
- 页面 ViewModel 统一经 `ViewModelFactory`（`\.viewModelFactory`）构造，View 不直接持有 Repository/Service（分层收敛，详见 DESIGN.md §4.1）。
- 并发遗留收口：`BeadViewModel` 4 处 `Task.detached` 已收敛（以捕获 `Sendable` 局部值方式传参，不捕获 `self`，complete 编译通过）；`HomeView` 2 处 `static let DateFormatter` 已随 2026-08-10/08-12 本地化与首页重构消解，2026-08-16 复核全仓库零残留（`HomeSections.weekdaySymbols` 为 Sendable `[String]` 静态缓存，不构成 SE-0412 违规），Swift 6 语言模式迁移无 formatter 前置项。

### 4.3 AI 模型转换工具链

将源端 CLIP / RTMPose 模型转换为 iOS Core ML 格式（`.mlpackage`）。方案详见 [ADR-0007](docs/adr/0007-ios-ai-inference-route.md)。

> **仅 macOS 可运行**：`coremltools` 依赖 macOS。转换产物 `.mlpackage` 加入 Xcode 工程后由 Xcode 自动编译为 `.mlmodelc`。

**环境搭建**（macOS，首次）

python.org 的 Python 3.12 不含 CA bundle，需 `truststore` 走系统 keychain；若 PyPI/HuggingFace 直连慢，用清华 PyPI 镜像 + hf-mirror（见下）
```bash
python3 -m venv .venv-models
source .venv-models/bin/activate
pip install -r tools/requirements-models.txt \
    -i https://pypi.tuna.tsinghua.edu.cn/simple \
    --trusted-host pypi.tuna.tsinghua.edu.cn
# truststore 自动 inject（sitecustomize.py）让 SSL 走 macOS keychain
```

**coremltools 8.x 要点**（实跑验证）

- coremltools 7.x 在 Python 3.12 / macOS 26 上从源码编译，native 后端加载失败；须用 **8.x**（`>=8.0,<9.0`）。
- 8.x **移除了 ONNX frontend**：RTMPose 需走 `ONNX → (patch Clip) → onnx2torch → PyTorch trace → Core ML` 桥接（已内置 `convert_rtmpose_coreml.py`）。
- `convert_to="mlprogram"`（7.x 的 `"ml-program""` 无效）；FP16 用 `compute_precision=ct.precision.FLOAT16`；INT8 用 `palettize_weights`（7.x 的 `op_palettizer`/`use_fp16storage` 已移除）。

**CLIP vision encoder → Core ML**（`tools/convert_clip_coreml.py`）：
```bash
# HuggingFace 不可达时，git clone / curl 到本地后用 --model-path
#   git clone --depth 1 https://hf-mirror.com/openai/clip-vit-base-patch32 /tmp/clip
#   curl -L -o /tmp/clip/pytorch_model.bin \
#       https://hf-mirror.com/openai/clip-vit-base-patch32/resolve/main/pytorch_model.bin
# FP16（~168 MB，精度最高）
python tools/convert_clip_coreml.py --model-path /tmp/clip \
    --quantization fp16 --output MiLens/Resources/Models/CLIPVisionEncoder_fp16.mlpackage

# INT8 weight-only palettize（~42 MB）
python tools/convert_clip_coreml.py --model-path /tmp/clip \
    --quantization int8 --output MiLens/Resources/Models/CLIPVisionEncoder_int8.mlpackage
```
输入为 MultiArray `1×3×224×224` NCHW float32（已 CLIP normalize）；预处理在 Swift 完成。校验门槛：512 维 embedding cosine >0.999（原始 torch vs Core ML）。

**RTMPose-t → Core ML**（`tools/convert_rtmpose_coreml.py`）：
```bash
python tools/convert_rtmpose_coreml.py \
    --onnx /path/to/rtmpose_t_pet_face.onnx \
    --quantization fp16 \
    --output MiLens/Resources/Models/RTMPoseTPetFace_fp16.mlpackage
```
管线：ONNX → (patch 空 Clip 输入) → onnx2torch → PyTorch trace → Core ML（coremltools 8.x 无 ONNX frontend）。输入 MultiArray `1×3×192×192` NCHW float32（已 ImageNet normalize）。校验门槛：5 关键点平均像素误差 <2px（ONNX Runtime vs Core ML，需真实宠物脸图片）。

**Text embeddings 校验/复制**（`tools/prepare_text_embeddings.py`）：
```bash
# 校验源端 f32 文件格式（任意平台可跑，不需 coremltools）
python tools/prepare_text_embeddings.py \
    --input /path/to/pet_text_embeddings.f32 --verify-only

# 复制到 iOS Resources 并打印 Swift 加载代码参考
python tools/prepare_text_embeddings.py \
    --input /path/to/pet_text_embeddings.f32 \
    --output MiLens/Resources/Models/pet_text_embeddings.f32 \
    --print-swift
```

**模型产物**（加入 `MiLens/Resources/Models/` 并在 `project.yml` 中注册打包）：

| 产物 | 体积（估算） | 进 App Bundle | 说明 |
|---|---|---|---|
| `CLIPVisionEncoder_int8.mlpackage` | ~84 MB | ✅ **生产模型** | 输入 224×224 RGB，输出 512 维 L2-normalized embedding；`CoreMLInferenceEngine` 默认加载名 |
| `RTMPoseTPetFace_fp16.mlpackage` | ~6 MB | ✅ **生产模型** | 输入 192×192 NCHW，输出 simcc_x [1,5,384] + simcc_y [1,5,384]；`PoseInferenceService.create` 默认加载（BeadViewModel 抠图分支 pose 检测，2026-08-09） |
| `CLIPVisionEncoder_fp16.mlpackage` | ~85 MB | ❌ excludes | 实验模型（仅本机转换/调试） |
| `RTMPoseTPetFace_int8.mlpackage` | ~3 MB | ❌ excludes | 实验模型（仅本机转换/调试） |
| `pet_text_embeddings.f32` | 0.04 MB | ✅ | 直接复用源端二进制文件 |

**生产模型交付（GitHub Release + SHA256 校验）**

生产模型（CLIP int8 + RTMPose fp16）以 tar 包发布到 Release（tag `models-v1`），清单 `tools/model-manifest.json` 内嵌 sha256，脚本 `tools/fetch-models.sh` 负责下载/校验/解包（幂等，`MILENS_MODEL_BASE_URL` 可覆盖基址做本地/镜像测试）。首次发布命令：

```bash
cd MiLens/Resources/Models
# 固定 mtime 保证 tar 包 SHA256 可复现（macOS bsdtar 无 --sort=name，用 touch 统一时间戳）
find CLIPVisionEncoder_int8.mlpackage RTMPoseTPetFace_fp16.mlpackage -exec touch -t 202608010000 {} +
tar -czf /tmp/models-v1.tar.gz CLIPVisionEncoder_int8.mlpackage RTMPoseTPetFace_fp16.mlpackage
shasum -a 256 /tmp/models-v1.tar.gz   # 将结果写入 tools/model-manifest.json 的 archive_sha256
cd <repo-root>
git tag models-v1 && git push origin models-v1 && git push origin --tags
gh release create models-v1 /tmp/models-v1.tar.gz --title "Model pack v1" --notes "CLIP int8 + RTMPose fp16"
```

> 发布后 CI 与本地共用同一下载路径；模型更新时递增 tag（如 `models-v2`）并同步 manifest。

### 4.4 模拟器 vs 真机

- 单元测试、纯逻辑、SwiftData schema：模拟器即可。
- Photos 权限、Vision/Core ML 推理、相机、推送、后台：**必须真机**（iPhone，iOS 17+）。
- StoreKit：用 StoreKit Testing（本地 `.storekit` 文件）+ 沙盒账号。

### 4.5 本地化（String Catalog）

UI 文案与 Info.plist 权限说明用 Apple String Catalog（`.xcstrings`）管理，源语言简中，结构支持任意语言：

- `MiLens/Resources/Localizable.xcstrings`——UI 文案（Tab 标题、占位说明等）。
- `MiLens/Resources/InfoPlist.xcstrings`——权限说明、App 显示名。
- `MiLensWidget/Localizable.xcstrings`——Widget Extension 文案（47 个 `widget.*` 语义 key；2026-08-16 接入，桌面/锁屏/PhotoEcho/年轮/倒数日五族 widget 与 Intents 配置）。
- 代码统一用 `String(localized: "key", comment: "...")`，不用 `NSLocalizedString`（Extension 内默认查自身 `.appex` bundle，无需显式 `bundle:`）。

**新增语言步骤**：
1. 在 `project.yml` 的 `knownRegions` 追加语言代码（如 `"en"`）。
2. 导出待翻译 Excel：`python tools/localization.py export MiLens/Resources/Localizable.xcstrings MiLens/Resources/InfoPlist.xcstrings MiLensWidget/Localizable.xcstrings build/loc.xlsx --lang en`。
3. 翻译人员填写 Excel 中的 `en` 列。
4. 导入回写（各 `.xcstrings` 分别执行）：`python tools/localization.py import build/loc.xlsx MiLens/Resources/Localizable.xcstrings --lang en`。
5. 校验：`python tools/localization.py check MiLens/Resources/Localizable.xcstrings MiLens/Resources/InfoPlist.xcstrings MiLensWidget/Localizable.xcstrings --project-yml project.yml --source-root MiLens --source-root MiLensWidget`。

> 依赖 `openpyxl`（`pip install -r tools/requirements.txt`）。工具支持任意语言，不限于英文；check 可接入 CI。脚本入口已内置 `stdout` UTF-8 重配置——Windows 默认 GBK 控制台无需 `PYTHONUTF8=1` 即可输出 `−` 等 Unicode 字符（2026-08-09 评审修复）。

> **复数（plural）key 支持（2026-08-10）**：`export` 按变体拆行（`key[one]` / `key[other]` 行，variation 列标注），`import` 合并回写 `variations.plural`，`check` 校验缺变体与占位符漂移（en/de/fr 需 one/other，zh/ja/ko 单条 other）。GUI 与资产工作簿已同步。复数 key 以 `%lld` 结尾（如 `paywall.cta.trial %lld`），代码侧以插值调用（`String(localized: "paywall.cta.trial \(days)")`）。

> **check 门禁增强（2026-08-12）**：`check` 现输出每语言进度统计表（total/ok/review/missing/完成度），并新增多项检测：
> - **默认阻断**：缺译（`new`/空值）、代码缺 key、**普通条目占位符漂移**（译文漏 `%@`/`%d` 会运行时崩或畸形）。
> - `--strict`：把 `needs_review` 初译待审也计为阻断（发布门禁用）；默认仅警告。多余 key 仍只警告。
> - `--length-rules <json>`：按 `tools/loc-length-rules.example.json` 格式校验译文长度（优先级：精确 key > comment `[len:N]` > 最长匹配前缀 > default），超限阻断。
> - `--hardcoded`：扫描 Swift 源码中疑似硬编码的用户可见文案（Text/Label/Button/navigationTitle 等首参含 CJK 且不在 catalog），是日期/年龄/性别等动态内容被写死的高发区检测。
>
> 核心统计语义（`LangStatus`/`scan_statuses`）已从 GUI 下沉到 `localization.py`，CLI 与 GUI 共用。单测：`python tools/test_localization.py`（纯 stdlib，不依赖 openpyxl）。

> **缺译降级放行（2026-08-15）**：`check` 新增 `--allow-missing-translations`——非源语言缺译降为警告并聚合输出（不逐行刷屏）。CI 已带此参数：7 语言 knownRegions 已定而 6 语言翻译未开始，缺译阻断会让 lint 作业挂掉并连带跳过 app 作业（`needs: [kit, lint]`）。`--strict`（发布门禁）下缺译仍阻断，不可被该参数绕过；翻译完成后从 CI 命令移除该参数（见 [Localization-Plan](docs/Localization-Plan.md) §6）。

> **多 catalog × 多源码根（2026-08-16）**：`--source-root` 可重复传多个（App 与 Widget Extension 各自根）；每个 `Localizable` catalog 按「路径是哪个源码根的后代」配对各自代码做缺 key/多余 key 比对（无祖先匹配时对全部根并集），`widget.*` key 不会与 App 代码互报。export/import 遇到 App 与 Widget 同名 `Localizable.xcstrings` 时 Excel sheet 自动去歧义（`Resources.Localizable` / `MiLensWidget.Localizable`）；import 优先匹配裸 `Localizable`（兼容旧工作簿）。CLI / GUI / 资产工作簿 / CI lint 已全部同步。

> **key 引用提取形态扩展（2026-08-16）**：`extract_code_keys` 在 `String(localized:)/NSLocalizedString` 之外新增两类口径——WidgetKit/AppIntents 配置面 API（`configurationDisplayName`/`.description`/`IntentDescription`/`@Parameter(title:)`/`LocalizedStringResource` 等赋值，参数类型即 key，无条件收）与 dotted key 形态的 `Text("...")`/`.case: "..."` 字典字面量（`LocalizedStringKey` 运行时查表，按 dotted 形态过滤防品牌/装饰文案误报；`switch` 映射 `case .xxx: "sf.symbol"` 是 SF Symbol 名，用 `(?<!case\s)` 排除）。消除 Widget catalog 缺 key 检测盲区，单测 38 用例；本地验证口径另带 `--hardcoded`（中文硬编码检测，D 类清收后纳入 CI）。

**桌面 GUI（可选）**：`python tools/localization-gui.py` 启动 tkinter 本地化工作台——语言进度总览（7 语种实时统计）、缺译清单（双击复制 key）、一键完整 check / 导出 / 导入 / 生成资产工作簿 / 打开工作簿；任务在后台线程执行不冻结界面。无显示环境可用 `python tools/localization-gui.py --self-check` 做结构自检。GUI 复用 `localization.py` 与 `localization-assets.py` 的全部逻辑，不引入额外依赖。

> **全球首发多语言计划（7 语言：zh-Hans/zh-Hant/ja/ko/en/fr/de）见 [docs/Localization-Plan.md](docs/Localization-Plan.md)**——含各国市场注意要点（日本丁寧語/韩国 반려동물 红线/德语 Bügelperlen 术语与长度预算/法语阴阳性等）、术语表、ASO 策略、翻译批次与验收标准。首次接入新语言前先读该文档，并按其中 §10 工作项顺序执行。
>
> **区域差异化（2026-08-13）**：文本翻译之外，按市场/地区的 UI 与逻辑差异由 `MarketProfile`（`MiLens/ViewModels/MarketProfile.swift`）承载，经 `@Environment(\.marketProfile)` 注入。当前落地两个维度：字体策略（zh-Hans 文楷 vs 系统衬线回退）与隐私叙事强度（GDPR 区 DE/FR 追加第 4 条强化声明，`PrivacyNarrativeLogic` 纯逻辑 + `PrivacyInfoView` 消费）。新增差异维度时在 `MarketProfile` 追加字段 + 纯逻辑 + 单测，不在 View 内散写 `if Locale` 判断。

## 5. 验证快照

（每个阶段完成后在此记录可复现的验证命令 + 结果。）

### P0

- 2026-08-07：harness 文档搭建完成。本地编译闭环验证通过——WSL2 **Ubuntu-24.04** + Swift 6.1.3（/opt/swift），`swift build` 与 `swift test` MiLensKit 全绿（1 用例，0 失败），增量编译 ~1.1s。
- 2026-08-07：项目推送 GitHub（`altairos/MiLens-iOS`，私有）。**云端编译闭环验证通过**——`MiLensKit (Linux)` 51s + `MiLens App (macOS)` 4m7s 全绿（`BUILD SUCCEEDED` + 测试通过）。首次运行修复 Asset Catalog 缺 `AppIcon.appiconset` 一处。
- 2026-08-07：**P1.1 工程地基**——新增 `MiLensApp` 组合根、`RootTabView`（4 Tab）、`Route`/`AppTab`、主题 token（5 个 Asset Catalog 语义色含深色 + `Theme.swift`）、简中 `Localizable.strings`、AppTab/Route 测试（8 用例）。**CI 验证通过**（编译 + 测试全绿，run 31187548565）。
- 2026-08-07：**P1.2 数据层**——SwiftData `@Model`（Pet/Photo/PetEvent，UUID 标识，V1.0 裁剪）+ `SchemaV1`/`MiLensMigrationPlan` + Repository 协议/实现（`@MainActor` + EnvironmentKey 注入）+ ModelContainer 接入。Repository 测试（22 用例：CRUD/分页/关系删除/扫描导入边界）。**CI 验证通过**（编译 + 测试全绿，run 31193790682）。
- 2026-08-07：**本地化工具链 + 文档校正**——新增 `tools/localization.py`（任意语言 String Catalog 导出/导入/check + Excel 工作流）与 `tools/requirements.txt`；同步工作区至 HEAD 的 String Catalog（`Localizable.xcstrings` 8 key + `InfoPlist.xcstrings` 3 key，源语言简中，结构支持任意语言）与 `String(localized:)` API；文档校正：反映 commit 6b48453 的 `.strings` → `.xcstrings` 迁移（AGENTS/PLAN/DEVELOPMENT/DESIGN）+ 新增 DEVELOPMENT.md §4.4 本地化工作流。本地验证：check 全绿、带值 round-trip 通过、回写格式 Xcode 兼容。App 编译待 CI 验证。

### P1

- 2026-08-11：**Memory Orbit 品牌底部导航落地（Windows/WSL 本地验证）**——系统 `TabView` 继续管理四个根页面与 `@AppStorage` 选中项，系统栏隐藏后由 `MemoryOrbitTabBar` 通过 `safeAreaInset` 展示；按 Figma Direction D 原始节点实现 4 套固定 `Path`、56pt 按钮、350×70 浮层、浅/深色语义 token，并保留本地化 VoiceOver 标签、Selected trait 与稳定 UI Test identifier。同步更新 AppTab 单测和 2 个 UI 冒烟测试。验证：WSL Swift 6.1.3 `swiftc -parse` 7 个改动 Swift 文件通过；`check-ui-tokens.py` 129 文件 **0 ERROR**；String Catalog 源语言/引用检查 269+3 key 通过；完整 7 语言检查仍因既有 6 语言未翻译报 1632 项，不是本次新增回归。App 编译、XCTest、模拟器浅/深色及 VoiceOver 实测依赖 macOS Xcode，**未执行**。

- 2026-08-08：**AI 模型转换工具链落地**——新增 3 个 Python 脚本 + `tools/requirements-models.txt`：①`tools/convert_clip_coreml.py`（CLIP ViT-B/32 vision encoder → Core ML `.mlpackage`，只导 image_features 512 维，支持 INT8/FP16 量化，精度校验 cosine >0.999）；②`tools/convert_rtmpose_coreml.py`（RTMPose-t ONNX → Core ML，SimCC 输出，精度校验 <2px）；③`tools/prepare_text_embeddings.py`（text embeddings f32 格式校验 + Swift 加载代码生成）。三个脚本 `py_compile` 全绿；`prepare_text_embeddings.py --verify-only` 对源端 `pet_text_embeddings.f32`（40960 bytes = 20×512×4）实跑通过，L2 范数全部正常。转换+量化实跑需 macOS（coremltools 依赖）。

### P2

- 2026-08-10：**本地化动态文案收口（Windows 本地验证）**——工具链 plural 支持（export 拆行 / import 合并 / check 完整性，端到端测试通过）+ 动态文案 10 类收口 8 类：a11y 22 处迁移 + 25 个 `a11y.*` key；通知 6 模板 / 宠物卡片 / 物种名 / 年龄（locale 注入）；时间线导出（`dateRangeText` locale 注入）、水印、分享面板（`timeline.*`/`share.*`）；首页（计数 plural / `Date.FormatStyle` / 回忆文案）；启动错误与恢复界面、档案加载失败（`startup.unknownError`/`recovery.*`/`pet.profile.loadFailed`/`common.*`）。`Localizable.xcstrings` 增至 **260 key**（zh-Hans translated）+ InfoPlist 3 key，`localization.py check` 全绿（无缺 key/多余 key/格式问题）；export 对 plural key 拆行验证通过。App 编译/测试依赖 iOS SDK，未执行，待 CI；固定 locale 快照测试待补（工作项 7.7b）。

- 2026-08-09：**本机 macOS 全量验证（高优先级修复前基准）**——`xcodegen generate` + `xcodebuild build`（`SWIFT_STRICT_CONCURRENCY=complete`）**BUILD SUCCEEDED**；MiLensKit `swift test` **594/594 全绿**；MiLens App `xcodebuild test` **604/604 全绿、0 失败**（含修复 `ProEntitlementStoreTests.testStreamPushStillUpdatesStatus` flaky——独立 `ListenerRegistry` 隔离 `ObjectIdentifier` 复用）；MiLensUITests 2 冒烟用例；`localization.py check` 全绿（Localizable 150 + InfoPlist 3）。该快照早于 2026-08-10 高优先级修复，不能替代当前 HEAD 的 macOS 验证。

- 2026-08-10：**高优先级缺陷修复（本地验证）**——5 项代码修复 + 1 项门禁修复 + 测试补充，均在 Windows 本地验证（App 编译/App 层测试依赖 iOS SDK，未执行）：①**ImportService 配额去重缺陷**：旧逻辑 `uniqueRequested` 只排除数据库已有项、未去重本次输入，导致免费用户传入重复 ID 被误算为超额导入弹出付费墙。改为先生成「有序去重→排除已有→限制批量」的候选列表再计算配额，批次截断不再错误归因为配额拦截。新增 3 个配额边界测试。②**ProEntitlementStore 墓碑误杀**：`cancel()` 无论是否找到任务都写入 `cancelledIDs`，对象释放后 `ObjectIdentifier` 可能复用导致新监听被误取消。改为 UUID 令牌（全局唯一不可复用）+ 条件墓碑（仅在 cancel 先于 register 的竞态时创建）。测试从 `ObjectIdentifier` 改为 `UUID`，新增墓碑不复杀用例。③**BeadViewModel 并发规则**：`export()` 的 `Task.detached` 闭包内读取 `self.isPro`（MainActor 隔离），改为在主 Actor 提前计算 `includeWatermark` 布尔值再捕获进闭包。④**GalleryView/CreateView 缩略图陈旧**：`ThumbnailImage` 使用不带 ID 的 `.task`，照片编辑后 URI 改变不重启加载；Create 页 `.task(id: path)` 因 `guard image == nil` 拒绝重载。统一改为 `.task(id: path)` + 路径变化时清除旧图。⑤**SharePreviewSheet 字面色**：3 处 `Color(red:)` 品牌色硬门禁违规，提取为 `Color.milensBrandWechat` / `milensBrandRedNote` token（Theme 目录豁免）。`check-ui-tokens.py` 0 ERROR、`localization.py check` 150+3 全绿。

- 2026-08-09：**审计收口 M2-M4 + L1-L5 本地验证（WSL2 Ubuntu-24.04 + Swift 6.1.3）**——`MiLensKit` 开启 `-strict-concurrency=complete` 后 `swift build` **零警告**，`swift test --parallel` 全绿（585/585，EXIT=0，含 L4 domain 判定 4 用例 + L5 脱敏 3 用例）；App 层 6 个改动文件（`MiLensApp`/`MediaLifecycleService`/`ScanService`/`ImportService`/`IOSPhotoLibraryAccess`/`MediaLifecycleServiceTests`）`swiftc -parse` 全过；App 编译/App 层测试依赖 iOS SDK，本机无法执行，待 CI（未执行）。

- 2026-08-09：**P1 核心可靠性收口——本机 Mac 模拟器全套验证通过**——①模型交付：`tools/fetch-models.sh` 三条路径实跑验证（幂等跳过 / 下载+SHA256 校验+解包 / 篡改 sha256 拒绝退出非零），`project.yml` excludes 实验模型（`xcodegen generate` 重新生成工程编译通过）；②后台执行器 + 两阶段扫描重构：ScanServiceTests 15/15、QualityScorer 相关全绿；③MediaLifecycleService 4 场景单测通过；④SwiftData 启动恢复：编译通过，测试环境 in-memory 快速路径保持；⑤通知真调度：NotifyServiceTests 10/10、NotifyCheckLogicTests 2/2；⑥CI：app job 移除 PR 限制 + 模型下载/缓存步骤。**全套 App 测试 400/400 通过、0 失败**（23 项模拟器跳过已恢复：ScanService/ImportService/QualityScorer 30/30）。模型 Release 创建后 PR 即可全绿。

- 2026-08-08：**P2 纯决策 + Service + View 层落地**——翻译源端 6 个纯决策模块（`GalleryPageState`/`ScanFlowLogic`/`ScanControlMath`/`ImportFlowLogic`/`PhotoMetadataLogic`/`PhotoViewGestureMath`）为 Swift 纯函数/struct + ~84 用例 XCTest（逐条对应源端黄金规格）；`ScanService`（Photos 全库扫描 + `VisionService` 检测 + `Task.cancel` 取消）+ `ImportService`（复制沙盒 → 入库）+ ~15 用例（in-memory SwiftData + mock 平台服务）；`GalleryViewModel`（@Observable）+ `GalleryView`（LazyVGrid 分页 + 扫描进度 + 完成弹窗）+ `PhotoViewView`（大图 + 手势）+ `HomeView`（相册/扫描入口）。
- 2026-08-08：**P2 CI 验证通过**（历史 run [31204194663](https://github.com/altairos/MiLens-iOS/actions/runs/31204194663)）——该次运行曾有 SwiftData 集成测试跳过；后续已在本机恢复并验证，当前状态以 2026-08-09 的 400/400、0 skipped 为准。**真机与性能待办见 [P2-待办清单](docs/P2-待办清单.md)**。
- 2026-08-08：**P2 扫描增强（质量评分 + 重复分组）**——纯逻辑三模块、`CoreImageAnalyzer`、`QualityScorer` 编排服务与 `Photo` 质量字段全部落地；此前的 SwiftData 集成测试跳过已恢复。当前仍需真实照片集校准清晰度/pHash 阈值，见 [P2-待办清单](docs/P2-待办清单.md)。
- 2026-08-08：**CLIP/Vision/CoreML 真实实现落地**——`IOSVisionService`（VNClassifyImageRequest + VNGenerateForegroundInstanceMask）+ `CoreMLInferenceEngine`（MLModel + MLMultiArray）+ `ClipInferenceService`（推理编排）+ `AiInferenceLogic`/`ClipPreprocess`/`PetTextEmbeddings` 纯逻辑。**本地验证通过**：`xcodebuild build` BUILD SUCCEEDED + `xcodebuild test` AiInferenceLogicTests 17 用例 + ClipPreprocessTests 11 用例全绿（28 passed, 0 failed）。编译修复 7 处错误（ClassificationResult 重名冲突 → ClipClassificationResult、Optional multiArrayConstraint 解包、MLModel.prediction async、compactMap 类型推断、Data.copyBytes 歧义、MLMultiArray 无 withUnsafeMutableBytes → memcpy、VNClassificationObservation 无 label → identifier）。**推理质量/精度/资源待真机验证**——详细清单见 [P2-真机验证备忘](docs/P2-真机验证备忘.md) §2.2。

### P4

- 2026-08-09：**RTMPose 加载链路补全（P4 拼豆 pose 保护）**——①`MiLensKit/PoseSimccDecoder`：翻译源端 `PoseInferenceMath.ets`（RGBA 平台变体：`preparePoseInput` 双线性裁切 + ImageNet NCHW 归一化 / `decodePoseOutputs` SimCC argmax + one-vs-rest softmax / `deriveFaceBoxFromPose` 脸框推导 / `hasStableFaceAnchors`），9 用例 XCTest；②App 层 `PoseInferenceService`：模型加载 + 输入契约验证 + 两阶段 coarse-to-fine 编排 + 按名输出绑定（不依赖数组顺序），7 用例 XCTest（mock 引擎注入，与 ClipInferenceService 测试纪律一致）；③`BeadViewModel` 抠图分支接入 pose 检测（失败静默跳过）→ `adjustPoseForCrop` 写入 `subject.pose`；④DI 链：`AppDependencies` → `\.poseInferenceService` EnvironmentKey → `BeadPatternView`。**WSL2 验证通过**：MiLensKit 编译零警告 + PoseSimccDecoderTests 9/9 全绿；App 层编译/测试依赖 iOS SDK，本机无法执行，待 CI（未执行）。模型 manifest 与文档同步更新（`model-manifest.json` loaded_by / Models README / PLAN / P2-真机验证备忘 §2.2.6）。

---

## 6. 源端参考资料

迁移时对照查阅（路径基于 `e:\HarmonyProjects\MiPhoto2`）：

| 内容 | 路径 |
|---|---|
| 源端架构 | `DESIGN.md` |
| 源端开发命令 | `DEVELOPMENT.md` |
| ADR 0001-0006 | `docs/adr/` |
| 拼豆算法备忘 | `docs/算法备忘.md` |
| 源端测试（黄金规格） | `entry/src/*test*` / `shared/src/*test*` |
| 主题 token | `entry/src/main/ets/theme/AppTheme.ets` |
| DB schema | `entry/src/main/ets/database/SchemaDef.ets` |
| 迁移技能参考 | `.qoder/skills/harmonyos-to-ios-migration/references/` |
