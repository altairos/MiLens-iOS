# MiLens iOS 开发说明

最后核对：2026-08-08（P2 进行中，CLIP/Vision/CoreML 真实实现落地）

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

> **无 Mac 也能开发的分层方案**：iOS App（SwiftUI/SwiftData/Photos/Vision）绑定 iOS SDK + Xcode，**无法在 Windows/Linux 上编译**。但本项目结构天然分层，本地可覆盖最高频的算法迭代，App 层走云端 CI：
>
> | 层 | 编译位置 | 命令 | 说明 |
> |---|---|---|---|
> | **MiLensKit**（纯 Swift 拼豆算法包） | 本地 WSL2 Ubuntu | `swift build` / `swift test` | 纯 Foundation + XCTest，不需 iOS SDK。这是翻译 3665 行 C++ + 9012 行 ArkTS 的高频 TDD 核心 |
> | **MiLens App**（SwiftUI/SwiftData 等） | GitHub Actions macOS runner | push 自动触发 `xcodegen` + `xcodebuild` | 见 `.github/workflows/ci.yml`。无法本地编译/真机调试 |
> | 真机调试 / 签名上架 | 借/租 Mac | Xcode + 真机 | 仅上架与真机联调时需要 |
>
> 真机、模拟器 UI、签名打包仍需 Mac + Xcode；可用云 Mac 租赁（MacinCloud/MacStadium）按需获取。

## 2. 常用命令

### 2.1 本地：MiLensKit 纯算法包（WSL2 Ubuntu-24.04，最高频）

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

仓库 https://github.com/altairos/MiLens-iOS（私有）。推送即触发 `.github/workflows/ci.yml`：

1. `MiLensKit (Linux)`——ubuntu-24.04 上 `swift build/test`，约 50s。
2. `MiLens App (macOS)`——macos-15 runner 上 `xcodegen generate` → `xcodebuild build/test`，约 4 分钟（依赖 MiLensKit 作业通过）。

查看：`gh run list --repo altairos/MiLens-iOS` 或 https://github.com/altairos/MiLens-iOS/actions。

#### 上架路径（免 Mac 一条龙）

编译、签名、上传 App Store 全部可在同一个 macOS runner 完成，无需本机 Mac：

```
macos-15 runner
  ├─ xcodegen + xcodebuild build          ← 已验证
  ├─ xcodebuild archive                   ← P5 待加
  ├─ xcodebuild -exportArchive            ← P5 待加（签名，用 .p8 App Store Connect API Key）
  └─ xcrun altool / notarytool upload     ← P5 待加（苹果官方上传，免费）
```

证书/描述文件用 **App Store Connect API Key（.p8）** 注入 GitHub Secret，无需钥匙串。`appuploader`/「开心上架」等第三方工具适用于「IPA 已生成、只需在 Windows 本地重传」场景，对原生项目非必需（IPA 本身仍需 macOS runner 产出）。

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
```

## 3. 项目结构约定

目录结构见 [DESIGN.md](DESIGN.md) §3。要点：

- `MiLens/` —— App target
- `MiLensKit/` —— 本地 Swift Package（拼豆算法，对应源端 `shared` HSP）
- `project.yml` —— XcodeGen 声明（**唯一受版本控制的项目配置**，`.xcodeproj` 由其生成，可 gitignore）
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

| 产物 | 体积（估算） | 说明 |
|---|---|---|
| `CLIPVisionEncoder.mlpackage` | ~42 MB（INT8）/ ~85 MB（FP16） | 输入 224×224 RGB，输出 512 维 L2-normalized embedding |
| `RTMPoseTPetFace.mlpackage` | ~3 MB（INT8）/ ~6 MB（FP16） | 输入 192×192 NCHW，输出 simcc_x [1,5,384] + simcc_y [1,5,384] |
| `pet_text_embeddings.f32` | 0.04 MB | 直接复用源端二进制文件 |

### 4.4 模拟器 vs 真机

- 单元测试、纯逻辑、SwiftData schema：模拟器即可。
- Photos 权限、Vision/Core ML 推理、相机、推送、后台：**必须真机**（iPhone，iOS 17+）。
- StoreKit：用 StoreKit Testing（本地 `.storekit` 文件）+ 沙盒账号。

### 4.5 本地化（String Catalog）

UI 文案与 Info.plist 权限说明用 Apple String Catalog（`.xcstrings`）管理，源语言简中，结构支持任意语言：

- `MiLens/Resources/Localizable.xcstrings`——UI 文案（Tab 标题、占位说明等）。
- `MiLens/Resources/InfoPlist.xcstrings`——权限说明、App 显示名。
- 代码统一用 `String(localized: "key", comment: "...")`，不用 `NSLocalizedString`。

**新增语言步骤**：
1. 在 `project.yml` 的 `knownRegions` 追加语言代码（如 `"en"`）。
2. 导出待翻译 Excel：`python tools/localization.py export MiLens/Resources/Localizable.xcstrings MiLens/Resources/InfoPlist.xcstrings build/loc.xlsx --lang en`。
3. 翻译人员填写 Excel 中的 `en` 列。
4. 导入回写（各 `.xcstrings` 分别执行）：`python tools/localization.py import build/loc.xlsx MiLens/Resources/Localizable.xcstrings --lang en`。
5. 校验：`python tools/localization.py check MiLens/Resources/Localizable.xcstrings MiLens/Resources/InfoPlist.xcstrings --project-yml project.yml --source-root MiLens`。

> 依赖 `openpyxl`（`pip install -r tools/requirements.txt`）。工具支持任意语言，不限于英文；check 可接入 CI。

## 5. 验证快照

（每个阶段完成后在此记录可复现的验证命令 + 结果。）

### P0

- 2026-08-07：harness 文档搭建完成。本地编译闭环验证通过——WSL2 **Ubuntu-24.04** + Swift 6.1.3（/opt/swift），`swift build` 与 `swift test` MiLensKit 全绿（1 用例，0 失败），增量编译 ~1.1s。
- 2026-08-07：项目推送 GitHub（`altairos/MiLens-iOS`，私有）。**云端编译闭环验证通过**——`MiLensKit (Linux)` 51s + `MiLens App (macOS)` 4m7s 全绿（`BUILD SUCCEEDED` + 测试通过）。首次运行修复 Asset Catalog 缺 `AppIcon.appiconset` 一处。
- 2026-08-07：**P1.1 工程地基**——新增 `MiLensApp` 组合根、`RootTabView`（4 Tab）、`Route`/`AppTab`、主题 token（5 个 Asset Catalog 语义色含深色 + `Theme.swift`）、简中 `Localizable.strings`、AppTab/Route 测试（8 用例）。**CI 验证通过**（编译 + 测试全绿，run 31187548565）。
- 2026-08-07：**P1.2 数据层**——SwiftData `@Model`（Pet/Photo/PetEvent，UUID 标识，V1.0 裁剪）+ `SchemaV1`/`MiLensMigrationPlan` + Repository 协议/实现（`@MainActor` + EnvironmentKey 注入）+ ModelContainer 接入。Repository 测试（22 用例：CRUD/分页/关系删除/扫描导入边界）。**CI 验证通过**（编译 + 测试全绿，run 31193790682）。
- 2026-08-07：**本地化工具链 + 文档校正**——新增 `tools/localization.py`（任意语言 String Catalog 导出/导入/check + Excel 工作流）与 `tools/requirements.txt`；同步工作区至 HEAD 的 String Catalog（`Localizable.xcstrings` 8 key + `InfoPlist.xcstrings` 3 key，源语言简中，结构支持任意语言）与 `String(localized:)` API；文档校正：反映 commit 6b48453 的 `.strings` → `.xcstrings` 迁移（AGENTS/PLAN/DEVELOPMENT/DESIGN）+ 新增 DEVELOPMENT.md §4.4 本地化工作流。本地验证：check 全绿、带值 round-trip 通过、回写格式 Xcode 兼容。App 编译待 CI 验证。

### P1

- 2026-08-08：**AI 模型转换工具链落地**——新增 3 个 Python 脚本 + `tools/requirements-models.txt`：①`tools/convert_clip_coreml.py`（CLIP ViT-B/32 vision encoder → Core ML `.mlpackage`，只导 image_features 512 维，支持 INT8/FP16 量化，精度校验 cosine >0.999）；②`tools/convert_rtmpose_coreml.py`（RTMPose-t ONNX → Core ML，SimCC 输出，精度校验 <2px）；③`tools/prepare_text_embeddings.py`（text embeddings f32 格式校验 + Swift 加载代码生成）。三个脚本 `py_compile` 全绿；`prepare_text_embeddings.py --verify-only` 对源端 `pet_text_embeddings.f32`（40960 bytes = 20×512×4）实跑通过，L2 范数全部正常。转换+量化实跑需 macOS（coremltools 依赖）。

### P2

- 2026-08-08：**P2 纯决策 + Service + View 层落地**——翻译源端 6 个纯决策模块（`GalleryPageState`/`ScanFlowLogic`/`ScanControlMath`/`ImportFlowLogic`/`PhotoMetadataLogic`/`PhotoViewGestureMath`）为 Swift 纯函数/struct + ~84 用例 XCTest（逐条对应源端黄金规格）；`ScanService`（Photos 全库扫描 + `VisionService` 检测 + `Task.cancel` 取消）+ `ImportService`（复制沙盒 → 入库）+ ~15 用例（in-memory SwiftData + mock 平台服务）；`GalleryViewModel`（@Observable）+ `GalleryView`（LazyVGrid 分页 + 扫描进度 + 完成弹窗）+ `PhotoViewView`（大图 + 手势）+ `HomeView`（相册/扫描入口）。
- 2026-08-08：**P2 CI 验证通过**（run [31204194663](https://github.com/altairos/MiLens-iOS/actions/runs/31204194663)）——MiLensKit (Linux) 120 passed/1 skipped/0 failed + MiLens App (macOS) 134 passed/15 skipped/0 failed。修复 5 处编译错误（`StylizedDraftGenerator` 参数标签、`PhotoLibraryAccess` 花括号、主题 token API 名称、`BeadPresetResolver` min/max 遮蔽、`MagnifyGesture.Value.magnification`）+ 1 处测试参数顺序。ScanServiceTests/ImportServiceTests（15 用例）因模拟器 SwiftData 集成崩溃临时跳过，待真机调试。**真机验证待办清单见 [P2-真机验证备忘](docs/P2-真机验证备忘.md)**。
- 2026-08-08：**P2 扫描增强（质量评分 + 重复分组）**——纯逻辑三模块（`QualityScoringLogic` 质量公式 / `PerceptualHashLogic` 哈希运算 / `DuplicateGroupingLogic` Union-Find 分组）+ 9 用例 XCTest（翻译源端 `MorePureLogic` + `QualityScorer` 黄金规格 + iOS 边界）；`ImageAnalyzer` 协议 + `CoreImageAnalyzer` 实现（Core Graphics Laplacian 方差 + 8×8 均值哈希）+ mock；`QualityScorer` 编排服务（`computeAllQualityScores` + `findDuplicates` + `runPostScanAnalysis`）+ 8 用例（SwiftData 集成跳过待 Mac 真机）；`Photo` schema 加 `phash`/`sharpness`/`qualityScore`/`duplicateOf`/`isBest` 字段，`PhotoRepository` 加 4 方法；`GalleryViewModel` 扫描/导入后 fire-and-forget 触发。**CI 验证待推送**。
- 2026-08-08：**CLIP/Vision/CoreML 真实实现落地**——`IOSVisionService`（VNClassifyImageRequest + VNGenerateForegroundInstanceMask）+ `CoreMLInferenceEngine`（MLModel + MLMultiArray）+ `ClipInferenceService`（推理编排）+ `AiInferenceLogic`/`ClipPreprocess`/`PetTextEmbeddings` 纯逻辑。**本地验证通过**：`xcodebuild build` BUILD SUCCEEDED + `xcodebuild test` AiInferenceLogicTests 17 用例 + ClipPreprocessTests 11 用例全绿（28 passed, 0 failed）。编译修复 7 处错误（ClassificationResult 重名冲突 → ClipClassificationResult、Optional multiArrayConstraint 解包、MLModel.prediction async、compactMap 类型推断、Data.copyBytes 歧义、MLMultiArray 无 withUnsafeMutableBytes → memcpy、VNClassificationObservation 无 label → identifier）。**推理质量/精度/资源待真机验证**——详细清单见 [P2-真机验证备忘](docs/P2-真机验证备忘.md) §2.2。

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
