# MiLens iOS UI Rework 计划

最后核对：2026-08-08（方案定稿，Phase 3 首页首轮已开始执行）

> 本文是 UI rework 的**执行计划**（阶段划分、任务明细、验收方式）。视觉规范唯一事实来源为 [UI-DESIGN.md](../UI-DESIGN.md)（色彩/字体/间距/动效/页面视觉）；架构见 [DESIGN.md](../DESIGN.md)，里程碑见 [PLAN.md](../PLAN.md)。执行期间按本文 §7 同步勾选状态。

## 1. 背景与目标

设计系统基础 token 已存在，但原先页面仍停留在默认 SwiftUI 风格，与 UI-DESIGN.md §5 的关键页面规范存在系统性差距。本轮先按已确认的首页方案建立可运行闭环，再按 Phase 1 → 2 → 3 → 4 扩展。

目标：按 UI-DESIGN.md 逐页打磨至符合规范（含深色模式、Dynamic Type、iPhone/iPad 适配），并补齐 P5 中与视觉强相关的功能（Settings 页、付费墙、首页 hero 数据层），使 V1.0 具备可提审的视觉完成度。

## 2. 现状差距表（rework 对象）

| 页面 | 现状 | 与 UI-DESIGN.md 的差距 |
|---|---|---|
| HomeView | 首轮已落地：真实 hero、回忆横滑、无照片/读取失败状态、创作 CTA | 成长提醒、深色/Dynamic Type 走查仍待完成 |
| GalleryView | 对齐网格 ✅（2pt 间隙） | 无日期分组标题、无筛选 chip、无 context menu、无 hero 转场 |
| PetsView | 列表卡片 ✅ token 化良好 | 未做传记式设计；卡片视觉可打磨 |
| PetProfileView | 常规布局 | §5.3 出血肖像 + 名字浮图 + 时间线节点未做 |
| CreateView | 简单照片网格 | §5.4 大卡片入口未做 |
| SettingsView | 纯占位（PlaceholderTabView） | 功能 + 视觉均未做（归本计划 Phase 4） |
| PhotoViewView | 黑底大图 + 手势 ✅ | 无下滑关闭、无 hero 转场 |
| Onboarding | 4 步功能完整 | 视觉未按品牌瞬间打磨 |
| 拼豆三件套 | 功能完整 | §5.4 工作室布局（上预览下参数）未做 |
| 动效/触感 | 全部缺失 | §4 全部条目未做（hero/haptic/揭示动画） |

## 3. 关键决策（已确认，不再变更）

| 决策 | 结论 |
|---|---|
| 范围 | **连 P5 功能一起做**：SettingsView 功能实现 + 付费墙纳入本计划；完成后 4 Tab 全部可用且视觉统一 |
| 验收方式 | **Mac 本地**：模拟器（编译/测试/尺寸/深色/Dynamic Type）+ 真机（手势/触感/Photos/Vision/StoreKit/性能） |
| CI | **本月 GitHub Actions 额度已用完**：不依赖 push 触发 CI 验证；所有验证在 Mac 本地 `xcodebuild` 完成；推 GitHub 仅作备份/合流 |
| iOS 版本 | 最低 iOS 17：hero 转场用 `matchedGeometryEffect`（iOS 17 兼容写法），不引入 iOS 18-only 的 `.navigationTransition(.zoom)` |
| 字体 | 沿用阶段 A：中文 display 只引入文楷 Regular 一个字重，靠字号区分层级；中英文 display 手动切栈（`displayLarge` / `displayLargeEN`） |
| 暂缓（沿用 UI-DESIGN.md §9） | masonry 瀑布流、Live Activity、自定义 SF Symbols、字体按需加载 |

## 4. 阶段计划

> 每阶段结束满足 §6 质量门禁，并在 §7 勾选状态。阶段间独立可验收，可按可用 Mac 时间分次执行。

### Phase 1 — 高频页打磨（Gallery + PhotoView + RootTab）

收益最大：相册与大图是用户每天触发几十次的路径，是「精致感」的核心来源（UI-DESIGN.md §4）。

**1.1 GalleryView 日期分组**
- 按日期分组：每天一个小标题（「8月7日 · 周三」），`displayMedium` 衬线。
- 日期来源：优先 `Photo` 的 EXIF 日期（`PhotoMetadataLogic` 已有解析），无 EXIF 回退 uri/文件时间；**不改 schema**（现有字段够用）。
- 分组逻辑入纯函数 + XCTest（参照 `TimelineLogic` 模式），View 只渲染。
- ✅ 纯逻辑已落地：`MiLensKit/Sources/MiLensKit/Gallery/GallerySectionLogic.swift`（`GallerySectionLogic.groupPhotos`，组间日期倒序对齐源端 `taken_at DESC`、组内拍摄时间倒序、无日期照片归入末尾空标题组；`miLensUTCCalendar` 为 Home/Gallery 共享固定 UTC 日历）；`GallerySectionLogicTests` 12 用例，MiLensKit 全量 566 用例 WSL2 全绿。View 渲染 + 分页追加后重新分组留 Mac。

**1.2 GalleryView 筛选 chip**
- 顶部悬浮胶囊（全部 / 各宠物），选中态品牌色填充（`AccentColor`），切换 `spring` 动画 + `.soft` 触感（UI-DESIGN.md §4）。
- 沿用现有 `GalleryFilter` + `GalleryViewModel.filterSnapshot`，不动业务状态机。
- ✅ 纯逻辑已落地：`MiLensKit/Sources/MiLensKit/Gallery/GalleryFilterLogic.swift`（`buildChips` 生成「全部 + 各宠物」chip 与互斥选中态，对齐 App 层 `GalleryFilter.petID`（nil = 全部）零映射；`filterPhotos` 按宠物过滤照片，与 `groupPhotos` 链式使用）；`GalleryPhoto` 投影补充 `petID` 字段（对齐 `HomeHeroPhoto` 模式）；`GalleryFilterLogicTests` 12 用例，MiLensKit 全量 578 用例 WSL2 全绿。设计稿无「无归属」chip（源端有 -2 选项），未实现。chip 渲染 + 触感 + VM 桥接留 Mac。

**1.3 GalleryView context menu**
- 长按照片：收藏 / 创作拼豆 / 设为档案头像 / 删除（§5.2）。收藏与删除走现有 Repository/ViewModel 方法；「设为头像」若无对应 VM 方法，先接 Pets 的头像更新路径（`Pet.avatarPath`），无现成方法则本阶段只做收藏/拼豆/删除三项并注明。

**1.4 PhotoViewView 下滑关闭 + hero 转场**
- 下滑手势关闭（缩放缩小 + 平移回落），关闭完成 `.light` 触感（§4）。
- 网格 → 大图 `matchedGeometryEffect` hero 转场（§7 iOS 平台特性 P2 高）。
- 注意：`matchedGeometryEffect` 在 NavigationStack + TabView 下的 id 传递与转场收尾坑（转场结束需清理 geometryID 状态），实现时先在模拟器验证返回路径。

**1.5 RootTabView**
- Tab 切换内容淡入淡出 + 轻微位移，`.light` 触感（§4）。
- Tab 图标/选中态沿用 `tab.systemImage`，视觉统一走 `.tint(.milensPrimary)`。

**验收**：模拟器 iPhone 15 Pro 走通 相册→大图→下滑关闭→返回网格；hero 转场流畅无残影；深色模式双外观；Tab 切换有位移与触感。

### Phase 2 — 宠物档案传记化

**2.1 PetsView 卡片打磨**
- 卡片分层：默认不用阴影，用 `Border`（0.5pt）或表面色差区分（§3.3）；头像圆环（`AccentSoft` 底 + 照片裁切）；间距/圆角统一 token。
- 空态：插画 + 衬线引导文案（§5.1 空态原则），替换当前 pawprint 占位。

**2.2 PetProfileView 传记式改造**
- 顶部出血肖像大图（~40% 高度，全宽），底部渐变（透明 → `SurfaceBackground`），名字浮在图上（`displayLarge`）。
- 统计行：照片数 / 相处天数 / 年龄，数字用 `numberStat` 圆体（§5.3）。
- 肖像数据源：`Pet.avatarPath` 有值用头像，否则回退最近照片（`PetProfileViewModel` 已有照片数据）。

**2.3 TimelineView 节点化**
- 时间线条目：左侧竖线 + 圆点节点（§5.3），每节点配代表照片缩略图，非纯文字。
- 分组标题用 `displayMedium`。

**2.4 PetEditView / AddPetSheet / 彩蛋弹窗视觉统一**
- 表单/弹窗圆角、输入框底色（`SurfaceGrouped`）、按钮（主 CTA 品牌色胶囊）统一走 token。

**验收**：模拟器 iPhone 15 Pro 走通 档案→详情（肖像浮名）→时间线（节点线）；深色模式；Dynamic Type 最大字号不断版。

### Phase 3 — 首页 hero（先补数据层）

**3.1 HomeViewModel（@Observable）+ XCTest**
- ✅ **数据层纯逻辑已提前落地**（2026-08-08，Windows/WSL2 完成）：`MiLensKit/Sources/MiLensKit/Home/` 新增 `HomeGreetingLogic`（时段问候，5-11 早 / 12-17 午 / 18-4 晚）/ `HomeHeroLogic`（今日判定 + hero 选片「今日最新 → 回退最近一张」+ 「今天 · 小橘」标注）/ `HomeMemoryLogic`（一年前的今天：同月同日历史照片按年份倒序，空则回退最近历史照片，标题「最近回忆」）+ `HomeDateSupport`（固定 UTC Calendar）。`HomeLogicTests` 32 用例，MiLensKit 全量 578 用例全绿。
- ✅ **HomeViewModel（@Observable）编排层已落地**：`MiLens/ViewModels/HomeViewModel.swift` 负责 Repository 查询 → 投影组装 → 调用 Home 纯逻辑；首页只读取最近 500 张，避免无界加载。
- ⬜ 「一年前的今天」回忆横滑数据：复用 `HomeMemoryLogic`（已落地）+ Repository 查询。
- ✅ 时段问候语（「早上好/下午好/晚上好」）纯函数 + 测试（32 用例中的 4 用例）。
- ✅ 空态判定：无照片可恢复入口、读取失败可重试；没有往年同日照片时由纯逻辑回退最近历史照片，历史也为空时展示紧凑说明，不伪造回忆。

**3.2 hero 视觉**
- 全宽 hero 卡片：圆角 20、无文字遮挡、底部极淡渐变（透明 → 背景）增强深度；「今天 · 小橘」caption 极简标注；点击进大图（`Route.photoView`）。
- 时间线分段符（`─────`）替代卡片分组（§5.1）。
- 唯一 CTA「为它创作」品牌色胶囊 → `Route.gallery` 或创作 Tab（实现时按现有路由选最短路径并注明）。

**验收**：模拟器走通 hero 点击进大图、回忆横滑、CTA 跳转；空态文案；深色模式；时段问候正确。

### Phase 4 — 创作 + Onboarding + Settings/付费墙

**4.1 CreateView 大卡片入口**
- 大尺寸全宽创作卡片（拼豆图纸 + 宠物卡片占位，§5.4），每张配示例效果图 + `displayMedium` 标题；宠物卡片入口按「待设计稿定案」留占位并诚实标注。

**4.2 拼豆三件套工作室化**
- 上半屏实时预览 + 下半屏参数控制（§5.4）；参数变化实时渲染 + spring。
- 生成完成：模糊 → 清晰揭示动画 + `.success` 触感（§4）。
- 导出：全屏预览 + 三按钮（保存相册 / 分享 / A4 PDF）——A4 PDF 与现有 PNG 导出能力对齐后实现，若导出能力不足则保持现有三按钮（保存/分享）并注明。

**4.3 Onboarding 视觉打磨**
- 4 步（欢迎/权限/扫描/建档）统一视觉；品牌色只在品牌瞬间出现（logo、CTA）；深色模式检查。

**4.4 SettingsView 功能实现（P5）**
- 主题/隐私/帮助/关于/Pro 订阅入口（PLAN.md P5 任务），文案 `String(localized:)`，本地化同步 `Localizable.xcstrings`。
- 关于页注明字体来源与 OFL 许可（UI-DESIGN.md §2.1 合规要求）。

**4.5 付费墙（P5，§5.5）**
- 情感化标题「让这份回忆继续成长」（非「升级 Pro」）；年费方案视觉突出（描边/更大，`numberStat`）；底部诚实续订条款。
- StoreKit 2：`Product`/`Transaction`/`EntitlementTask` 接线 + StoreKit Testing 本地验证（DEVELOPMENT.md §4.4）。

**验收**：模拟器 4 Tab 全功能可用；拼豆工作室布局与揭示动画；付费墙 StoreKit Testing 通过；深色 + Dynamic Type。

## 5. 验证方式（Mac 本地，替代 CI）

### 5.1 每次改动后的最小验证

```bash
# 生成工程（project.yml 变更后）
xcodegen generate

# 编译 + 全量测试（模拟器）
xcodebuild -project MiLens.xcodeproj -scheme MiLens \
  -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild -project MiLens.xcodeproj -scheme MiLens \
  -destination 'platform=iOS Simulator,name=iPhone 15' test

# 拼豆包独立验证（可选，改动涉及 MiLensKit 时）
cd MiLensKit && swift test
```

### 5.2 每阶段收尾的验收（模拟器 + 真机）

| 项 | 方式 | 覆盖 |
|---|---|---|
| 编译 + 全量测试 | 模拟器 `xcodebuild test` | 逻辑回归（注意：ScanService/ImportService 15 用例在模拟器 SwiftData 集成崩溃，已跳过，归真机验证） |
| 尺寸适配 | 模拟器 iPhone SE / Pro Max + iPad | 间距/圆角/网格断版 |
| 深色模式 | 模拟器切换外观 | 全页面暖黑双外观 |
| Dynamic Type | 模拟器最大字号 | 字体不断版、不截断 |
| hero / 手势 / 触感 | **真机 iPhone** | 转场流畅度、下滑关闭、haptic |
| Photos / Vision / Core ML | **真机 iPhone** | 扫描/导入/推理降级（沿用 [P2-真机验证备忘](P2-真机验证备忘.md)） |
| StoreKit | StoreKit Testing + 沙盒 | 付费墙购买/恢复 |
| 性能 | 真机 Instruments | 相册滚动（5000+ 照片基线）、内存 |
| swift-format lint | 本地 | 改动文件 0 error |

## 6. 质量门禁（每阶段收尾强制）

1. 色值只用 `milensXxx` token，禁止硬编码色值；品牌色 `#FD8663` 遵守 §1.3 使用纪律（CTA/选中态/品牌瞬间）。
2. 间距/圆角/字体全部走 `Theme.swift` / `Typography.swift` token。
3. 深色模式双外观核对；Dynamic Type 最大字号不断版；iPhone SE / Pro Max / iPad 三尺寸检查。
4. 新增纯逻辑（日期分组、问候语、hero 选片）必须配 XCTest；View 层改动不动 ViewModel 业务状态。
5. `xcodebuild test` 全绿；swift-format lint 改动文件 0 error。
6. 文档同步：UI-DESIGN.md §9 阶段 B 勾选 + 本文 §7 状态 + PLAN.md 进度摘要。

## 7. 状态追踪

| 阶段 | 任务 | 状态 |
|---|---|---|
| Phase 1 | 1.1 Gallery 日期分组 | ✅ 纯逻辑 + View 渲染 + 分页重分组已落地 |
| Phase 1 | 1.2 Gallery 筛选 chip | ✅ 纯逻辑 + chip 渲染 + VM 桥接已落地 |
| Phase 1 | 1.3 Gallery context menu | ✅ 收藏 / 创作拼豆 / 移除 + 删除二次确认已落地 |
| Phase 1 | 1.4 PhotoView 下滑关闭 + hero | ✅ 下滑关闭、背景淡出、轻触感与相册→大图 matchedGeometry 转场已落地；真机手势待验收 |
| Phase 1 | 1.5 RootTab 动效触感 | ✅ 原生 TabView + 淡入动画 + selection 触感已落地 |
| Phase 2 | 2.1 Pets 卡片打磨 | ✅ 卡片 0.5pt 描边分层 + 空态衬线引导 + 彩蛋弹窗统一已落地 |
| Phase 2 | 2.2 PetProfile 传记式 | ✅ 出血肖像（~40% 屏高）+ 名字浮渐变 + 统计行已落地 |
| Phase 2 | 2.3 Timeline 节点化 | ✅ 节点竖线 + 圆点 + 照片缩略图 + displayMedium 分组标题已落地 |
| Phase 2 | 2.4 表单/弹窗视觉统一 | ✅ PetEditView / AddPetSheet / 彩蛋弹窗底色与胶囊 CTA 已落地 |
| Phase 3 | 3.1 HomeViewModel + 测试 | ✅ 纯逻辑（MiLensKit Home/ 32 用例）+ App 编排已落地 |
| Phase 3 | 3.2 hero 视觉 + 回忆 + CTA | 🔄 首轮已落地；待模拟器尺寸/深色/Dynamic Type 走查 |
| Phase 4 | 4.1 Create 大卡片入口 | ✅ 大卡片列表 + 拼豆入口（真实照片像素化示意）+ 宠物卡片诚实占位 + 选照片流程搬入 BeadPhotoPickerView |
| Phase 4 | 4.2 拼豆工作室化 | ✅ 上预览下参数 + 防抖实时重渲染 + 模糊→清晰揭示 + .success 触感 + 全屏导出三按钮（含 A4 PDF）；build/test 被并发 WIP 阻塞待复验 |
| Phase 4 | 4.3 Onboarding 打磨 | ✅ 四步视觉统一（安静步骤指示器/ActionPrimary 胶囊/品牌瞬间收敛为 3 处记忆标记点/文楷每屏一个）+ 修复 CTA 对比度缺陷；全量 511 用例 0 失败 |
| Phase 4 | 4.4 Settings 功能实现 | ✅ 六分区（Pro/隐私/通知/外观/支持/关于）+ SettingsLogic 纯函数 + 15 用例 + xcstrings 76 key 已落地 |
| Phase 4 | 4.5 付费墙 | ✅ 情感化标题 + 年度突出 + StoreKit 2 接线（含 Transaction 监听/恢复）+ 28 用例 + Products.storekit 重写为规范 v3；scheme 关联与购买链路走查待人工 |

### 本轮验证记录（2026-08-09，Phase 2 宠物档案传记化）

- `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 17' build CODE_SIGNING_ALLOWED=NO`：通过（首次增量编译 BeadViewModel 出现一过性失败，重跑即 BUILD SUCCEEDED，与本次改动文件无关）。
- `xcodebuild … test CODE_SIGNING_ALLOWED=NO`：**TEST SUCCEEDED，403 用例 0 失败**；上轮出现的「Early unexpected exit」环境问题本轮未复现。
- `cd MiLensKit && swift test`：578 个测试通过（纯 View 层改动，包未受影响）。
- swift-format lint：未执行（本机未安装 swift-format/swiftformat）。
- 模拟器尺寸/深色模式/Dynamic Type 走查与真机验收：未执行，留待阶段收尾统一走查。

### 本轮验证记录（2026-08-09，Phase 4.4/4.5 Settings + 付费墙）

- 改动：SettingsView 全量重写（Pro 状态/数据与隐私/通知/外观/支持/关于六分区，外观 @AppStorage + 根 preferredColorScheme）；新增 SettingsLogic/SettingsViewModel、PaywallView/PaywallLogic/PaywallViewModel、StoreService 协议 + StoreKit2/Mock 实现、AppDependencies 组合根；Products.storekit 重写为规范 v3 格式（月 ¥18 / 年 ¥98 各 7 天试用 + 永久 ¥298 非消耗品，价格仅 StoreKit Testing 配置，生产代码零硬编码）。
- 前提变化：并发会话已修复并提交 PetMatcher（`3a4aca6`），本轮拿到完整闭环。
- `xcodegen generate`、`git diff --check`：通过。
- `xcodebuild build`：BUILD SUCCEEDED，本次文件 0 error 0 warning。
- `xcodebuild test`（新增测试）：**43 用例 0 失败**（SettingsLogic 10 + SettingsViewModel 5 + PaywallLogic 13 + PaywallViewModel 13 + StoreKitConfiguration 2）。
- StoreKit 端到端购买链路：未验证——本机模拟器 StoreKit 测试守护进程环境错误（SKInternalErrorDomain Code=3），且 scheme 关联 .storekit 需 Xcode GUI 人工勾选；留人工走查 + 沙盒验证。
- 遗留：功能门控未接线（权益矩阵未冻结，ProStatus 已可从 Environment 读取）；服务条款用 Apple 标准 EULA 链接；隐私政策 miovelle.cn/privacy 待托管。
- swift-format lint：未执行（本机未安装）；深色/Dynamic Type/尺寸走查与真机验收留阶段收尾。

### 本轮验证记录（2026-08-09，Phase 4.3 Onboarding 打磨）

- 改动（仅 5 个 Onboarding 视图，VM/测试零触碰）：容器改短线步骤指示器 + 非对称淡入位移过渡 + ActionPrimary 胶囊主按钮（消除旧 BrandCoral 托白字 2.40:1 对比度问题）；欢迎步改记忆标记 wordmark + 文楷 Hero「把它的一生，留在这里」+ 价值文案诚实口径（移除「认识每一只宠物」）；权限步补第三条「由你决定导入什么」；扫描步状态图标中性化 + 发现数记忆标记；建档步修复「开始注册/开始使用」深底深字对比度缺陷 + 输入框底色/描边 token 化。
- 品牌纪律：四步珊瑚仅剩 3 处 6pt 记忆标记点；文楷每屏恰好一个标题。
- `xcodebuild build`：BUILD SUCCEEDED；`xcodebuild test` 全量：**TEST SUCCEEDED，511 用例 0 失败**（ImportServiceTests 2 例 signal trap 本轮未复现）。
- `git diff --check`：通过；swift-format lint：未执行（本机未安装）。
- 深色/Dynamic Type/尺寸走查未执行，留阶段收尾统一走查。

### 全量复验记录（2026-08-09，4.1/4.2 补闭环）

- 前提：并发会话已修复 PetMatcher 并提交 `3a4aca6`（照片自动归属匹配），此前阻塞全量 build 的 WIP 错误消除。
- `xcodebuild … test`：MiLensTests 套件 **333 用例执行 0 断言失败**，但 `ImportServiceTests.testImportAutoMatchSkipsWhenNoRegisteredPet` / `testImportAutoMatchFailsGracefullyOnExtractionError` 两例 **signal trap 崩溃**（TEST FAILED）。两者均为 `3a4aca6` 新增的自动归属匹配用例，属已知「模拟器 SwiftData 集成崩溃」遗留（ScanService/ImportService 归真机验证）在新增用例上的延续，与 UI rework 改动无关。
- 结论：4.1/4.2/4.4/4.5 改动在全量套件中无回归；ImportService 两例崩溃待真机验证。

### 本轮验证记录（2026-08-09，Phase 4.1/4.2 创作页）

- 改动：CreateView 重写为大卡片入口；新增 BeadPhotoPickerView（`xcodegen generate` 已入工程）；BeadPatternView 工作室布局；BeadSettingsPanelView 双态主按钮；BeadPatternResultView 全屏导出 + A4 PDF（`BeadExportService.renderA4PDF`，UIGraphicsPDFRenderer 单页 A4）。
- `xcodegen generate`、`git diff --check`：通过。
- `xcodebuild build`：**未通过，但与本次改动无关**——工作区被另一会话并发修改，未跟踪 WIP 文件 `MiLens/Services/Scanning/PetMatcher.swift:115-117` 有 3 处 optional 解包编译错误；本次触动的 9 个文件在完整构建日志中 0 error。`xcodebuild test` 因此被阻塞**未执行**，待 PetMatcher.swift 修复后需重跑 build + test 闭环。
- swift-format lint：未执行（本机未安装）。
- 揭示动画/防抖重渲染/A4 PDF 分享面板/深色模式走查与真机验收：未执行。

### 本轮验证记录（2026-08-09）

- `git diff --check`：通过。
- `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 17' build CODE_SIGNING_ALLOWED=NO`：通过。
- `cd MiLensKit && swift test`：578 个测试通过。
- iOS `xcodebuild test`：未完成测试汇总；测试进程在模拟器建立连接前被系统以 signal kill 终止（`Early unexpected exit`），不是首页编译错误。需在 Xcode/真机环境复核。

## 8. 风险与注意事项

- **CI 额度用完**：验证完全依赖 Mac 本地；推送 GitHub 仅备份/合流，不视为验证。
- **模拟器 SwiftData 崩溃**：ScanService/ImportService 15 用例已跳过待真机（PLAN.md P2 遗留），本计划不负责修复，但 Phase 1 涉及 Gallery 改动时注意不扩大该问题范围。
- **matchedGeometryEffect 与 NavigationStack/TabView 的坑**：id 必须稳定传递、转场结束清理状态，否则出现残影/错位；实现时模拟器重点验证返回路径。
- **中英文标题切栈**：中文标题用 `displayLarge`（文楷），纯英文标题手动用 `displayLargeEN`（Fraunces），不可依赖自动回退。
- **宠物卡片生成**（PLAN.md P4 遗留）与 UI 无关，不在本计划范围；CreateView 入口留占位并诚实标注。
