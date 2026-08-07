# MiLens iOS 开发说明

最后核对：2026-08-07（P0 harness 搭建中）

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

### 4.3 模拟器 vs 真机

- 单元测试、纯逻辑、SwiftData schema：模拟器即可。
- Photos 权限、Vision/Core ML 推理、相机、推送、后台：**必须真机**（iPhone，iOS 17+）。
- StoreKit：用 StoreKit Testing（本地 `.storekit` 文件）+ 沙盒账号。

## 5. 验证快照

（每个阶段完成后在此记录可复现的验证命令 + 结果。）

### P0

- 2026-08-07：harness 文档搭建完成。本地编译闭环验证通过——WSL2 **Ubuntu-24.04** + Swift 6.1.3（/opt/swift），`swift build` 与 `swift test` MiLensKit 全绿（1 用例，0 失败），增量编译 ~1.1s。
- 2026-08-07：项目推送 GitHub（`altairos/MiLens-iOS`，私有）。**云端编译闭环验证通过**——`MiLensKit (Linux)` 51s + `MiLens App (macOS)` 4m7s 全绿（`BUILD SUCCEEDED` + 测试通过）。首次运行修复 Asset Catalog 缺 `AppIcon.appiconset` 一处。
- 2026-08-07：**P1.1 工程地基**——新增 `MiLensApp` 组合根、`RootTabView`（4 Tab）、`Route`/`AppTab`、主题 token（5 个 Asset Catalog 语义色含深色 + `Theme.swift`）、简中 `Localizable.strings`、AppTab/Route 测试（8 用例）。**CI 验证通过**（编译 + 测试全绿，run 31187548565）。

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
