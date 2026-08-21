# MiLens 全球本地化计划

> **首发范围变更（2026-08-22）**：首发支持 6 种语言：zh-Hans、zh-Hant、ja、en、fr、de。韩文（ko）延期，不纳入首发翻译、商店资产、隐私政策、截图和验收；文档中保留的韩国市场内容仅作为后续版本备忘。

最后更新：2026-08-22（全量法文本地化 100% 完成：全部 1245 个 key 注入 String Catalog，遵循 compagnon / perles à repasser 术语规范，0 缺译、0 占位符漂移、0 格式问题；2026-08-21 全量英文本地化 100% 完成：全部 1239 个 key 注入 String Catalog，遵循 pal/pals 术语规范，0 缺译、0 占位符漂移、0 格式问题；2026-08-17 回退 1c623e9 误入主 catalog 的 117 条 en 初译，修复 commit b3b0a79，CI 全绿 run 31961932575——红线教训见 §5.4：翻译完整导入前 catalog 只能含源语言；2026-08-16 MiLensWidget 接入 String Catalog，工具链支持多 catalog × 多源码根与 Excel sheet 去歧义；2026-08-15 CI 缺译门禁过渡期降级 `--allow-missing-translations`；2026-08-10 定案首发 7 语言：zh-Hans / zh-Hant / ja / ko / en / fr / de）

> 本文档是 MiLens 全球首发本地化工作的唯一事实来源：语言矩阵、各国市场注意要点、翻译工作流、质量门禁、ASO 关键词策略与时间线。工具与命令见 [DEVELOPMENT.md](../DEVELOPMENT.md) §4.5，商店文案见 [AppStore-metadata.md](AppStore-metadata.md)，商业决策见 [ADR-0010](adr/0010-commercialization-and-emotion-triggers.md)。

## 1. 目标与原则

### 1.1 目标

首发即覆盖 7 种语言，对应全球主要宠物消费市场，实现"一份代码、一套资源、多语言上架"。多语言不是"上线后补"，而是首发的一部分——因为：

- 拼豆是覆盖全部首发市场的全球性手工艺品类（日本 Perler / 欧美 Hama / 韩台 DIY）；
- 隐私优先（照片不离开设备）的定位在德/日/法市场是付费理由本身；
- 开发者本身是本地化专业出身，多语言边际成本接近零，但构成竞品难以短期复制的壁垒。

### 1.2 原则

| 原则 | 说明 |
|---|---|
| 源语言唯一 | 简中（zh-Hans）是唯一事实来源，英文作为**第二参照语言**（用于校验译义漂移） |
| 工具链驱动 | 全部走 `tools/localization.py`（export/import/check）+ CI 门禁，不手工改 `.xcstrings` |
| 术语一致性 | 核心术语表（§8）先行定稿，6 语言对照，避免一义多译 |
| 诚实标注 | "计划加入"的能力不得在任一语言中写成已交付（沿用 ADR-0009 规则） |

### 1.3 发布分层与降级策略

首发语言分为两个发布层级，避免把所有语言绑成一个不可降级的总门槛：

| 层级 | 语言 | 发布要求 |
|---|---|---|
| P0 | zh-Hans、en、ja | App 内文案、商店元数据、截图、隐私政策和审核备注全部完成并验收 |
| P1 | zh-Hant、de、fr | 首发候选；若某一语言未达到发布门槛，必须明确选择延期该语言，或临时复用英文商店素材，不得让 App 内出现简中漏出 |

- 开发阶段允许目标语言缺译时回退到源语言，正式发布包不允许出现未审校译文或 `needs_review` 状态。
- 每种语言独立记录“翻译完成”“UI 验收完成”“商店资产完成”“隐私政策上线”四个状态；不能用总完成度代替单语言验收。
- 语言延期时，App Store Connect、App 内语言列表、截图和隐私政策 URL 必须保持一致，避免商店宣称支持但 App 实际未完成。
| 文化适配优先于直译 | 各国市场注意要点（§4）逐条落实，不满足于"读得通" |
| 动态文案全覆盖 | 复数、日期/数字、无障碍、通知、错误、空状态、订阅失败等**运行时文案**与静态文案同权进入翻译管线（范围见 §3.6） |

---

## 2. 语言覆盖矩阵

| 语言代码 | 覆盖区域 | 市场级别 | 优先级 | 首发 | 备注 |
|---|---|---|---|---|---|
| zh-Hans | 中国大陆 | 基本盘（源语言）| P0 | ✅ | 现有文案，需按 §4.7 校验 |
| en | 美/英/澳/加/新等 | S 级（体量最大）| P0 | ✅ | App 内统一美式英语 |
| ja | 日本 | S 级（拼豆文化原点）| P0 | ✅ | 最吃本地化质量的市场 |
| zh-Hant | 台湾、香港 | B 级（稳定）| P1 | ✅ | 以台湾用语为准，香港差异记录 |
| de | 德国/奥地利/瑞士 | S 级（隐私杀手锏）| P1 | ✅ | 文案长度预算最大 |
| fr | 法国/魁北克/比利时 | A 级（低成本高回报）| P1 | ✅ | 以法国法语（fr-FR）为准 |

> 后续扩展候选（V1.x，工具链零改动）：es、pt、it、ru、id、th、vi。

### 2.1 新增语言的标准操作

```bash
# 1. project.yml knownRegions 追加语言代码（如 "ja"）
# 2. 导出待翻译 Excel（可一次导出多语言列）
python tools/localization.py export \
    MiLens/Resources/Localizable.xcstrings \
    MiLens/Resources/InfoPlist.xcstrings \
    MiLensWidget/Localizable.xcstrings \
    build/loc.xlsx --lang en,ja,zh-Hant,de,fr

# 3. 翻译后逐语言导入回写
python tools/localization.py import build/loc.xlsx \
    MiLens/Resources/Localizable.xcstrings --lang ja

# 4. 校验（基础门禁：0 缺 key / 0 占位符漂移；发布门禁 --strict：0 缺译 / 0 待审）
python tools/localization.py check \
    MiLens/Resources/Localizable.xcstrings \
    MiLens/Resources/InfoPlist.xcstrings \
    MiLensWidget/Localizable.xcstrings \
    --project-yml project.yml --source-root MiLens --source-root MiLensWidget

# CI 过渡期命令额外带 --allow-missing-translations（非源语言缺译降为警告；
# 7 语言翻译完成后移除，恢复缺译阻断）。--strict 发布门禁不受该参数影响。
#
# key 引用提取口径（tools/localization.py extract_code_keys）：
# - 显式 API 全收：String(localized:)/NSLocalizedString + WidgetKit/AppIntents
#   配置面（configurationDisplayName/.description/IntentDescription/
#   @Parameter(title:)/LocalizedStringResource 等赋值——参数类型即 key）；
# - 模糊形态按 dotted key 过滤：Text("...") 与 `.case: "..."` 字典条目
#   （LocalizedStringKey 运行时查表），switch-case SF Symbol 映射排除；
# 本地带 --hardcoded 做中文硬编码检测（D 类清收后纳入 CI 口径）。
```

---

## 3. 本地化范围清单（6 类资产）

| # | 资产 | 位置 | 说明 | 状态 |
|---|---|---|---|---|
| 1 | App UI 文案 | `Localizable.xcstrings`（260 key）| 统一由 String Catalog 管理；代码使用 `String(localized:)` 或 SwiftUI `LocalizedStringKey` API，结构已支持任意语言 | 待翻译 |
| 2 | 权限说明 + App 显示名 | `InfoPlist.xcstrings`（3 key）| 权限文案需按各国法规语感撰写，App 显示名按语言本地化 | 待翻译 |
| 3 | App Store 元数据 | [AppStore-metadata.md](AppStore-metadata.md) | 名称/副标题/描述/关键词/推广文本/审核备注，每语言一份 | zh-Hans + en-US 草案，截图与 ASC 录入待完成 |
| 4 | 订阅产品本地化 | App Store Connect | 订阅组 + 3 个产品的本地化描述（§3.4）| 待录入 |
| 5 | 隐私政策网页 | `docs/privacy-policy.html` | 中文草稿已存在，需提供多语言版本并完成线上 URL 验收（建议按语言 URL 或 `?lang=`）| 中文草稿，部署待验收 |
| 6 | 截图/预览素材 | App Store Connect | 每语言 3-5 张截图 + 文案覆盖层 | 待制作 |

### 3.1 App 显示名（CFBundleDisplayName）按语言建议

| 语言 | 建议显示名 | 说明 |
|---|---|---|
| zh-Hans | 咪Lens - 宠物照片整理与拼豆创作 | 现有 |
| zh-Hant | 咪Lens - 寵物照片整理與拼豆創作 | 保留品牌，本地化用词 |
| en | MiLens - Pet Photos & Bead Art | 简洁，突出双卖点 |
| ja | MiLens - ペット写真整理とアイロンビーズ図案 | 品牌保留，用品类词 |
| ko | MiLens - 반려동물 사진 정리와 비즈 도안 | 品牌保留 |
| de | MiLens - Haustierfotos | 控制在 30 字符内，用品类词放入副标题/关键词 |
| fr | MiLens - Photos animaux | 控制在 30 字符内，用品类词放入副标题/关键词 |

### 3.2 副标题（App Store 30 字符限制，每语言）

| 语言 | 建议副标题 |
|---|---|
| zh-Hans | 拾回散落的每一张照片，记住你与爱宠共度的一生（现有）|
| zh-Hant | 拾回散落的每一張照片，記住你與毛小孩共度的一生 |
| en | Pet photos & bead patterns |
| ja | ペットの写真を整理して、アイロンビーズの図案に |
| ko | 반려동물 사진 정리와 비즈 도안 만들기 |
| de | Haustierfotos & Bügelperlen |
| fr | Photos d’animaux & perles |

> 以上为方向性草案，均按 30 字符上限做过初步压缩；定稿前仍需以 App Store Connect 实际校验和 ASO 复核为准（§7）。

### 3.3 描述/推广文本/审核备注

- 描述：zh-Hans + en-US 初稿已整理在 `AppStore-metadata.md` §2，每语言控制在 4000 字符内；其余首发语言按同一事实版本翻译；
- 推广文本（170 字符）：每语言按市场热点可随时更新（App Store 无需审核）；
- 审核备注：**用英文撰写一份全球通用版**，另为 ja/ko/zh-Hant 各准备一份当地语言版（审核员阅读效率 = 过审速度）。

### 3.4 订阅产品本地化描述（App Store Connect 必填）

每个产品（月/年/永久）每种语言都要填写本地化描述与显示名。直接录入字段以 [AppStore-metadata.md](AppStore-metadata.md) §7.3 中英文短字段为准，§7.3.1 仅作长版权益说明，翻译时注意：

- 订阅权益描述按语言惯例调整（如日语加"自動更新はいつでも解除できます"）；
- 价格文案不写死金额（由 ASC 层级自动显示）；
- 永久版描述强调"一回購入、ずっと使える"式的本地化表达。

### 3.5 隐私政策多语言

- 策略：`privacy-policy.html` 增加语言切换（同页 `?lang=ja` 或独立子页），至少提供 en/ja/de（审核常见语言）+ 全部首发语言；
- 德语版需符合 GDPR 透明度习惯用语；日语版遵循日本個人情報保護法语境；
- 托管在现有 GitHub Pages（miovelle.cn）即可，无额外成本。

### 3.6 动态文案与运行时本地化覆盖范围（增补）

> 静态文案（§3 六类资产）之外，还有一类**运行时才拼接/格式化产生**的用户可见文案。它们散落在纯逻辑层与视图层，是漏译高发区——不在 Excel 工作簿里出现、check 也不拦。本节把它们全部收口进翻译管线。

| # | 类型 | 代码位置（盘点 2026-08-10）| 现状（✅=已收口，见下方收口进度表）| 处理方式 |
|---|---|---|---|---|
| 1 | **复数（Plural）** | `paywall.cta.trial`（免费试用 %d 天）、`paywall.trial.hint`（前 %d 天免费）| ✅ 已收口 | 工具链升级支持 plural（工作项 #7.5）；en/de/fr 用 one/other，zh/ja/ko 无复数形态只填 other 单条 |
| 2 | **日期 / 数字格式** | HomeView `Text("第 \(count.formatted()) 张")`；TimelineExportLogic `dateRangeText`（"2024-01 — 2026-08"）；PetDisplayLogic `ageText`（"3岁2个月"）| ✅ 已收口 | 一律 `Date.FormatStyle` / `Number.FormatStyle` + locale（§4.8 已定原则，落代码）；纯逻辑层返回结构化数据或注入 formatter；固定 locale 快照测试（复用 utcCalendar 确定性测试模式）|
| 3 | **无障碍标签** | 22 处 `accessibilityLabel`（TimelineView/OnboardingView/EditorView/EditorToolPanels/GalleryView/HomeView 等），含插值（"第 \(step) 步，共 \(count) 步"、"颜色 \(hex)"）| ✅ 已收口 | 全部核对并迁移（工作项 #7.6）；插值标签用 format 键；VoiceOver 每语言抽查读屏（§9）|
| 4 | **系统权限文案** | `InfoPlist.xcstrings`（NSPhotoLibraryAdd/Usage 2 key）+ `settings.notifications.denied.*`（3 key）| 已有 5 key | 按各国法规语感翻译（GDPR/PIPA/個資法，§4.8）；权限弹窗文案与实际行为一致性核对（审核要点）；通知权限弹窗为系统模板无需文案 |
| 5 | **错误提示** | paywall 失败系列（已收口 7 key）；StateView `"档案加载失败"`；MiLensApp `"未知错误"` 启动错误 | ✅ 已收口 | 三段式规范：发生了什么 / 原因 / 怎么办；错误码与内部标识脱敏（沿用 AppErrorHandler.redactIdentifier）；不直接展示 StoreKit/Vision 原始错误（工作项 #7.8 盘点收口，含 editor 抠图四态与名片保存失败）|
| 6 | **通知内容** | AnniversaryLogic `buildAnniversaryNotificationText`/`buildTimeMachineText`（6 个模板，"N年前的今天"系列）；NotifyService `notificationNote`（"\(petName)的生日"）| ✅ 已收口 | 逻辑层用 `String(localized:)`（App target）或注入文案提供者；通知 title ≤ 1 行、body ≤ 2-3 行长预算；语气按市场规范（日区て形+絵文字适度、韩区 합니다体、德区正式礼貌，§4）；"N年前的今天"是插值+复数复合点 |
| 7 | **空状态** | StateView 组件（title/action 参数由调用方传字面量）："还没有照片"、"还没有伙伴档案"、"还没有成长记录"、"没有符合条件的照片" 等 | ✅ 已收口 | 系统性盘点每个空状态场景（相册/时间线/拼豆/宠物列表/搜索结果/通知权限）并核对 catalog 覆盖（工作项 #7.8）；规范：说明现状 + 行动指引（CTA）|
| 8 | **订阅失败路径** | `paywall.purchase.failed/pending`、`paywall.restore.*`、`paywall.load.failed`（8 key）| 已收口 | StoreKit 错误分类映射表：用户取消（静默）/ 网络不可用 / 账单问题 / ask-to-buy 待处理 / 家长控制受限 / 系统错误——每类对应本地化文案，不直显系统英文错误；试用到期与续费失败提示文案 |
| 9 | **宠物卡片 / 档案动态文案** | PetCardLogic（"这一天"、"值得记住的一天"、"来到家 N 天"）；PetDisplayLogic `speciesDisplayName`（"喵星人"等）与 `ageText` | ✅ 已收口 | 年龄文案复数化（en "3 yrs 2 mo"、ja "3歳2ヶ月"）；物种名市场适配（"喵星人"为中文网络语，ja 用 にゃんこ/ねこ、en 用 kitty/cat、ko 用 냥이/고양이）；宠物代词策略：英文统一单数 they（避免 he/she 性别假设），de/fr 用避免性别的句式（§4.3/§4.5）|
| 10 | **导出水印与分享文案** | TimelineExportCanvas `Text("由 MiLens 制作")`（时间线水印）；SharePreviewSheet `"免费版导出带 MiLens 水印，升级 Pro 可去除"` | ✅ 已收口 | 水印是品牌传播载体（其他用户看到后搜索下载），必须本地化（en "Made with MiLens" 等）；分享默认 caption 与导出文件名（"拼豆图纸_20260810"）的日期格式一并本地化 |

**收口进度（2026-08-10）**

| # | 状态 | 说明 |
|---|---|---|
| 1 | ✅ 已收口 | 工具链 plural 支持（export 拆行 `key[one]/[other]` / import 合并回写 / check 变体+占位符校验 / GUI 与资产工作簿同步，端到端测试通过）；`paywall.cta.trial`/`paywall.trial.hint` 已转 plural |
| 2 | ✅ 已收口 | HomeView 照片计数（`home.photoCount %lld` plural）与「今天 HH:mm」前缀（`Date.FormatStyle` + locale + `home.todayTime %@`）；TimelineExportLogic `dateRangeText`（locale 注入 + `timeline.export.dateRange %@ %@`）；PetDisplayLogic `ageText`（复数 key + locale 注入）。杂志竖排日期保留固定装饰格式（纯数字无语言依赖，注释说明）|
| 3 | ✅ 已收口 | 22 处 accessibilityLabel 全部核对迁移 + catalog 补 25 个 `a11y.*` key（zh-Hans translated）；插值标签用 `%@`/`%lld` key |
| 4 | 待翻译 | 5 key 已就位（InfoPlist 2 + settings.notifications.denied 3），翻译阶段处理 |
| 5 | ✅ 已收口 | 启动错误（`startup.unknownError`）、档案加载失败（`pet.profile.loadFailed`，PetEditViewModel/StateView/PetProfileView）、首页加载错误（`home.loadError`）、时间线导出错误（`timeline.renderFailed`/`timeline.exportFailedDetail`）、启动恢复界面全套（`recovery.*` + `common.ok/cancel/back`）；editor 抠图四态（`editor.cutout.action.*`）与名片保存失败（`businessCard.saveFailed`）随 #7.8 收口 |
| 6 | ✅ 已收口 | AnniversaryLogic 6 模板 + NotifyService `notificationNote` 全部 `String(localized:locale:)`（插值+复数复合） |
| 7 | ✅ 已收口（#7.8）| 19 处硬编码迁移：`gallery.empty.*`、`pets.empty.title/cta`、`home.empty.*`、`recovery.title/body/rebuildConfirmBody`、`gallery.scan.permissionDenied`、`editor.cutout.action.*`、`businessCard.saveFailed`；Onboarding 编辑式文案（~19 处）已随 #7.13 收口 |
| 8 | ✅ 已收口 | paywall 失败/恢复/加载 8 key + 错误分类映射 |
| 9 | ✅ 已收口 | PetCardLogic（「这一天」/「来到家 N 天」plural）+ PetDisplayLogic（物种/性别/年龄复数 key）locale 注入 |
| 10 | ✅ 已收口 | 时间线水印（`timeline.export.watermark`）、分享面板标题/副标题/4 平台名/更多/水印提示（`share.*`）；分享文件名保持英文内部标识（不含日期，无日期格式可本地化） |

**处理原则（动态文案专属）**

- **纯逻辑层本地化策略**：App target 的 ViewModel/Service 可直接 `String(localized:)`（保持可测性——测试注入固定 `Locale`）；MiLensKit 纯逻辑不持有用户可见文案，需要时由调用方注入文案或返回结构化占位（保持包体平台无关）；
- **复数语言差异**：zh/ja/ko 无复数形态（CLDR 仅 other），不创建 plural 结构；en one/other，de one/other，fr zero/one/other——翻译时按语言实际规则填；
- **插值完整性**：`%d`/`%@`/`\n` 与 plural 参数由升级后的 `localization.py check` 守护（§6）；
- **动态文案也进 Excel 工作簿**：工具链支持 plural 后，export 将 plural key 拆行导出（`key[one]` / `key[other]`），import 时合并回写，翻译人员在 Excel 中与静态文案同流程处理（工作项 #7.5）；
- **固定 locale 快照测试**：日期/数字/复数/通知模板各语言用一个固定 locale（如 en_US / de_DE / ja_JP）断言输出快照，纳入现有纯逻辑测试（复用 utcCalendar 注入模式），避免只在模拟器人工发现。

### 3.7 装饰性英文文案规范（2026-08-16 增补）

> 「编辑风」设计语言中存在大量英文装饰文案（editorial overline / 档案编号 / 元数据标签，如 `FIRST LIGHT · 欢迎`、`ARCHIVE 001`、`PATTERN PARAMETERS`）。**zh 源语言允许英文装饰**（它们是排版元素而非待翻译语义，zh 值保持原装饰形态不改写）；但硬编码会原样漏入 EN 等非源语言构建——翻译阶段无法覆盖。本节定义其收口与翻译规范。

**规范**

- **必须 key 化**：装饰文案一律走 `String(localized:)` 进 catalog；Swift 代码中不得新增硬编码英文装饰；
- **非源语言必须给真实译文**：en/ja/ko 等翻译**禁止照抄英文原值**——按语义译出（如 `EMPTY ARCHIVE / 00` → en "Empty Archive / 00"）；大小写随目标语言排版习惯：显示层已有 `.textCase(.uppercase)` 的组件 en 值用自然大小写（Title Case），无 textCase 的直接 `Text` 保持视觉风格仍用 Title Case 译文；
- **品牌词与徽标例外（全语言通用，不进 catalog）**：MiLens / MiLens Pro / M / MILENS 品牌词；PRO 徽标 ×3（WorkshopComponents / EditorDecorationPanelView / BeadResultComponents，用户裁定全语言通用）；MILENS 复合导出水印（`MILENS · LIFE ARCHIVE` / `MILENS PET PROFILE`，PetCardArtwork / BusinessCardArtwork，已入检测整串白名单）；
- **门禁**：`localization.py check --hardcoded` 对「UI 文案 API 首参纯拉丁 + 含全大写词（≥2 连续大写字母）」输出 warning 级 `[英文装饰]` 提示，白名单（词级 PRO/PDF/A4/ID/AI/MiLens 系 + 上述水印整串）放过，已在 catalog（精确或插值归一化）命中的不报，见 §6。

**既有 C 类 key（12 个，本批前已 key 化；en 翻译不得照抄原值）**

| key | zh 值（装饰原样保留） | en 译文方向 |
|---|---|---|
| `businesscard.overline` | HORIZONTAL NAMECARD | Horizontal Namecard |
| `create.studio.overline` | CREATION DARKROOM | Creation Darkroom |
| `growthcompare.overline` | GROWTH COMPARE | Growth Compare |
| `petcard.overline` | PET CARD | Pet Card |
| `redpacket.overline` | WECHAT RED ENVELOPES | WeChat Red Envelopes |
| `redpacket.export.sceneOverline` | SCENE PREVIEW | Scene Preview |
| `redpacket.quality.overline` | QUALITY | Quality |
| `share.preview.overline` | READY TO KEEP | Ready to Keep |
| `pet.profile.eyebrow` | LIFE LONG ARCHIVE | A Lifetime Archive |
| `pet.profile.pinned.section` | 置顶记忆 · PAGE 01 | Pinned Memories · Page 01 |
| `create.bead.a4pdf` | Pro 版 · A4 PDF | Pro · A4 PDF（技术词保留）|
| `bead.generating.step3` | 匹配 MARD 色卡 | Matching the MARD palette（MARD 技术词保留）|

**本批收口（2026-08-16）**：25 处硬编码英文装饰迁移 `String(localized:)` + 25 key 落库（zh=translated 原样 / en=needs_review 初译，含 plural `pet.profile.lifeMark %lld`），Onboarding 全流程 overline 统一走 `OnboardingViewModel.stepOverline`（7 个 step 视图消除重复副本）；明细见工作项 #7.11。

**en 译文落地（2026-08-22）**：C 类 12 key 与收口 25 key 中 en 值照抄全大写装饰的 35 key 已全部按 Title Case 方向修正（含 `pet.profile.lifeMark %lld`）；zh/zh-Hant 源装饰原样保留。复检：en 全大写照抄清单已清零（`build/loc-verify.txt`）。

---

## 4. 各国市场注意要点（重点）

> 本节是本地化工作的核心质量要求。每条都需要在翻译与截图阶段逐项落实，并在 §9 验收时逐条打勾。

### 4.1 日本（ja）— S 级

**市场特征**
- 拼豆（アイロンビーズ / パーラービーズ）是昭和—平成世代集体记忆，手作市场成熟，付费意愿高；
- 猫文化极强，「猫の日 2/22」是天然营销节点；宠物 App 在日本商店有专属流量入口；
- iPhone 市占率全球最高梯队，iOS 付费习惯成熟；
- **对机翻零容忍**：一个不自然的表达就可能导致一星差评，本地化质量直接决定评分与榜单位置。

**语言与文案**
- 一律使用丁寧語（です/ます 体），禁用简体（だ/である）与过度亲密口语；
- 全角标点（。、「」、！？）必须正确；数字用半角；
- 日文汉字与中文汉字含义不同（手紙=信、娘=女儿、勉強=学习），**不得从中文直接替换汉字**；
- 长音（ー）、拗音小字、送假名细节要校对。

**产品与术语**
- 品类词用「アイロンビーズ」（熨烫珠），图纸用「図案 / デザイン」，生成用「作成」；
- 拼豆工作室 → ビーズスタジオ；成长时间线 → 成長タイムライン；
- 隐私叙事："写真は端末から出ません"（照片不离开设备）在日区是强卖点，必须出现在描述与付费墙；
- 彩虹桥（虹の橋）在日本宠物文化中非常普遍，可直接使用；
- 通知时间 09:00 合适；通知文案需要亲切（て形 + 絵文字适度，日区接受度高，但克制）。

**ASO 方向**
- 高价值词：ペット写真 / アイロンビーズ / パーラービーズ / 写真整理 / 猫 / 犬 / ペットアルバム；
- 「写真整理」竞争高，「アイロンビーズ」中等——是突破口；
- 截图上日文文案必须地道（日本用户会截图放大看文字）。

### 4.2 美国 / 英文区（en）— S 级

**市场特征**
- 全球最大市场，竞争也最激烈；Perler Beads / Melty Beads 是 Millennial 怀旧品类，Etsy/Pinterest 有海量 UGC；
- 订阅+买断混合模式接受度高，$24.99 永久版处于冲动购买区间；
- Family Sharing 在美区利用率高（已配置 ✅）。

**语言与文案**
- App 内统一美式英语（color / favorite / organize）；元数据可另备 en-GB 版本（colour / favourite），优先级低；
- 日期 MM/DD/YYYY，金额 $ 符号，千分位逗号；
- 语气：温暖但不油腻，避免过度营销化形容词（"adorable" 用在宠物语境可以，"revolutionary" 不行）；
- **产品文案禁用 pet（2026-08-22 裁定）**：UI 与产品文案一律用 **pal / companion（伙伴）**，不得使用 pet（与 §8 「pal profile（禁用 pet）」一致）；ASO 关键词与 App 显示名中的 "pet photos" 等仅为用户搜索词，不属于产品用语；zh-Hans 源的存量「宠物」（41 处）已于 2026-08-22 全量收口为「伙伴／伙伴档案」（40 key + zh-Hant 残留 2 处；四点裁定：档案统一「伙伴档案」、`photo.assign.empty` 改「还没有伙伴，先去登记」、隐私叙事用「哪位伙伴」、petFresh 模板名改「茸茸清新」）。en/fr 原已 pal／compagnon 化零改动；de/ja/ko 该批 key 均缺译，将来按新源翻译（`build/locpal-report.txt`：残留 0）。

**产品与术语**
- 图纸术语：bead pattern（通用）、perler pattern（用户搜索习惯词，可用于 ASO）；
- 隐私叙事："All photos stay on your device" 是 iOS 用户强感知卖点，放描述第二段；
- 彩虹桥（Rainbow Bridge）在英语宠物社区是常见正面概念，宠物卡片/纪念文案可直接用；
- 导出尺寸：A4 可用；美区可后续评估 Letter 适配（低优先级）。

**ASO 方向**
- 高价值词：pet photos / pet album / perler beads / bead pattern / photo organizer / cat / dog；
- "perler" 是品牌词，用 "perler beads" 长尾更安全；
- 关键词 100 字符限额，按搜索量×竞争度精选。

### 4.3 德语区（de）— S 级

**市场特征**
- GDPR 发源地，隐私敏感度全球最高——"照片不离开设备"在这里不是加分项而是**购买理由本身**；
- Hama Beads（丹麦品牌）在德语区是主流手工艺，Bügelperlen 认知度高；
- 德语区用户重视透明与细节，期望落差直接转化为差评。

**语言与文案**
- **德语复合词极长**：UI 必须预留 30-40% 长度空间，Tab、按钮、卡片逐项做截断测试；
- 术语：品类词必须是 **Bügelperlen**（熨烫珠）；Steckperlen 是另一种工艺（插珠），**不可混用**；图纸 = Vorlage / Muster；
- 称呼：消费级 App 惯例用 du（informal），但全文必须一致（设置页与弹窗不得混用 du/Sie）；
- 名词首字母大写规则必须正确；标点使用德式引号（„…"）；
- 动物名词词性：der Hund / die Katze——文案避免依赖性别表述，或统一用 Haustier（宠物）；
- 日期 DD.MM.YYYY，小数点用逗号（€14,99）。

**产品与术语**
- 隐私叙事：**德语版描述建议专门加一段**，用具体措辞（"Alle Fotos und Analysen bleiben auf Ihrem Gerät. Keine Cloud, kein Upload."）；
- 年度订阅（€14.99 级）必须突出节省比例（"über 55% sparen"），德语用户对价格透明敏感；
- 订阅取消条款写清楚（"jederzeit kündbar"），符合德国消费者习惯；
- 通知 09:00 合适；德语通知文案保持正式礼貌。

**ASO 方向**
- 高价值词：Bügelperlen / Bügelperlen Vorlagen / Haustier / Hund / Katze / Fotoalbum / Fotos sortieren；
- "Bügelperlen Vorlagen"（熨烫珠图纸）是强购买意图词，优先拿下。

### 4.4 韩国市场（延期，不纳入首发）

**市场特征**
- 반려동물（伴侣动物）文化快速兴起，宠物经济高速增长；
- iPhone 市占率较高，iOS 付费习惯好；DIY/手工（비즈공예）在女性用户中流行。

**语言与文案（后续版本备忘，不参与首发）**
- **必须用 반려동물（伴侣动物），禁用 애완동물（玩赏动物）**——后者被视为过时甚至冒犯，这是韩国市场的红线；
- 敬语：建议统一 합니다体（服务类 App 惯例，正式得体）；选定后全文一致，不得混用 해요体；
- 韩文单词间有空格（与中文不同），标点用韩式（마침표/쉼표 与西文同形）；
- 常用词：강아지（小狗）、고양이（猫）、반려동물 앨범（宠物相册）；멍냥이 等网络口语慎用（保持服务语气）。

**产品与术语**
- 拼豆术语：비즈 도안（珠子图纸）或 아이론 비즈 도안（熨烫珠图纸音译），建议统一 비즈 도안；
- 隐私叙事：韩区用户对数据收集敏感（PIPA 法律环境），"모든 분석은 기기에서 처리됩니다"（所有分析在设备上处理）是有效表述；
- 宠物离世话题较敏感：彩虹桥等纪念功能文案用词温和，避免直接殡葬化表达。

**ASO 方向**
- 高价值词：반려동물 / 강아지 / 고양이 / 비즈 도안 / 사진 정리 / 반려동물 앨범；
- 竞争度中等，반려동물 前缀词族是流量入口。

### 4.5 法国 / 法语区（fr）— A 级

**市场特征**
- 法国宠物数量欧洲第一（约 3000 万只）；perles à repasser 认知良好；
- 法国用户对 App 设计感与文字质量要求高，文案质量差会直接掉分。

**语言与文案**
- **阴阳性**：UI 文案避免依赖词性变化的结构（如孤立形容词 "Nouveau!"），改用中性句式（"Nouveau contenu disponible" 或动词结构）；
- **法语通常比英文长 20-30%**：所有文案按 +30% 长度预算设计，关键 UI 实测不截断；
- 标点：法语句末冒号/问号/感叹号前有窄空格（espace insécable）——App 内由系统排版处理，**网页与商店元数据必须手动处理**；
- 数字：1 234,56（空格千分位 + 逗号小数）；
- 魁北克（fr-CA）用词差异（courriel vs email 等）首发以 fr-FR 为准，差异记录在案待 V1.x 评估。

**产品与术语**
- 品类词：perles à repasser（熨烫珠）；图纸 = modèle / plan；
- 隐私叙事："Traitement 100 % local"（全本地处理）是法语区强表述；
- 通用表达：animal de compagnie（宠物）、chat / chien。

**ASO 方向**
- 高价值词：perles à repasser / photos animaux / album chat / album chien；
- 法语关键词竞争度低——低成本高回报市场，值得做满 100 字符。

### 4.6 台湾 / 香港繁中（zh-Hant）— B 级

**市场特征**
- 台湾宠物约 250 万只，"毛小孩"文化成熟；拼豆在文创市集/手作圈认知良好；
- 香港宠物家庭渗透率高，但人口规模小。

**语言与文案**
- **繁中不是简中的字符转换**：词汇差异必须逐条处理（範本/模板、儲存/保存、相片/照片、資訊/信息、刪除/删除）；
- 首发以台湾用语为准：毛小孩、浪浪（流浪动物）、領養、相簿；
- 香港差异记录（如量词与部分用词），暂不做第二套繁中；
- 全角标点正确使用。

**产品与术语**
- 拼豆术语：台灣普遍稱「拼豆」「拼拼豆豆」，图纸 = 拼豆圖稿（2026-08-22 裁定，全文統一，不用「拼豆圖紙」）；
- 彩虹橋概念在台湾宠物界普遍，纪念文案可直接使用；
- 隐私叙事：台湾用户对個資（个资）敏感，"照片不會離開手機"表述有效。

**ASO 方向**
- 高价值词：寵物照片 / 寵物相簿 / 拼豆 / 拼豆圖稿 / 毛小孩 / 貓咪 / 狗狗（寵物照片/相簿為搜尋詞，產品文案稱呼統一「毛小孩」，見 §8）；
- 繁中区竞争低，长尾词易拿排名。

### 4.7 中国大陆（zh-Hans）— 源语言 / 基本盘

- 保持现有文案与术语（拼豆图纸、伙伴档案（原「宠物档案」，2026-08-22 §4.2 收口）、成长时间线、往日回忆、时光机）；源文案存量「宠物」（41 处）已全量伙伴化（§4.2，`build/locpal-report.txt`：残留 0）；
- 校验现有文案中无"拟上架但未交付"的能力描述（ADR-0009 诚实原则，已由 App Store 文案去重收口）；
- 国内称呼多样（拼豆/拼拼豆豆/豆豆画/熨豆），产品内统一"拼豆"建立品牌一致性。

### 4.8 跨市场通用注意（技术 + 文化）

**技术**
- 日期/数字/日历：UI 展示一律走系统 locale（`Date.FormatStyle` / `Number.FormatStyle`），禁止硬编码格式串（现有 `utcCalendar` 纯逻辑仅用于测试确定性，展示路径不受影响）；
- 时区：通知、纪念日全部按用户本地时区调度（现有实现已满足）；
- **字体策略**：标题字体判断已下沉到区域差异化模型 `MarketProfile.displayFontFamily`（`MiLens/ViewModels/MarketProfile.swift`）：zh-Hans 使用霞鹜文楷 GB，zh-Hant-TW 使用霞鶩文楷 TC，zh-Hant-HK 使用芫茜雅楷，ja 使用 Klee One，en/fr/de 使用带 Latin Extended 的 Fraunces；正文/UI 仍使用系统字体。字体文件均在 `MiLens/Resources/Fonts/` 按当前本地化文案子集化，首发前需逐语言模拟器走查，确认混排、缺字和 Dynamic Type 表现；
- 长度预算：UI 按德语/法语最坏情况预留 30-40%，每语言在模拟器走查 Tab 标题、按钮、卡片、付费墙；
- 换行规则：CJK 逐字换行 vs 西文断词，长文本测试；
- 订阅价格：由 App Store Connect 价格层级按地区自动生效，App 内不硬编码金额文案（现有实现已满足）。

**文化**
- 节日营销节点（通知/推广文本可复用）：日本猫の日 2/22、日本犬の日 11/1、国际宠物日、各国圣诞/新年/感恩节；
- 宠物照片审美差异：日韩偏好可爱系、欧美偏好纪实与自然光——**截图素材选择按市场调整**，不要一套截图换语言就上。区域差异化的代码基础设施已落地（`MarketProfile` 模型 + `@Environment(\.marketProfile)` 注入），当前承载字体策略与隐私叙事强度两个维度，未来可按需追加审美方向等维度；
- 法律合规：GDPR（欧盟/德法）、PIPA（韩国）、个保法（中国）、個資法（台湾）——在"不收集数据"的产品定位下合规负担很轻，但**隐私政策需按市场法律语境撰写**，不是机械翻译；
- 宠物离世（彩虹桥）文化接受度：英语区/日本/台湾普遍正面，韩国需更谨慎措辞，中国大陆以温和表达为主。

### 4.9 跨市场安全与事实核对

- **功能承诺必须可追溯**："AI 自动找出宠物照片"、"所有分析在设备本地完成"、"照片不会离开设备"等表述，发布前逐条对照当前构建、Core ML/Vision 调用、StoreKit、崩溃日志和系统备份行为；不能把产品定位写成超出实现范围的法律或安全保证。
- **隐私措辞要覆盖例外**：如果编辑产物可随用户启用的系统备份保存，相关语言的隐私政策、付费墙和商店描述不得使用绝对化的"任何数据都不会离开设备"。
- **商标词单独管理**：`Perler`、`Hama` 等品牌词只能按 ASO 和法律审阅后的规则使用；通用 UI 术语优先使用 `bead pattern`、`Bügelperlen`、`アイロンビーズ` 等非品牌表达。
- **市场研究结论标记来源**：搜索量、竞争度、用户偏好、付费意愿和节日机会标记为“已验证事实”“产品决策”或“待验证假设”，不要与系统限制、字符限制混写。
- **敏感内容二次审阅**：宠物离世、彩虹桥、纪念日、通知推送和付费墙文案需由对应语言审校人确认语气，韩国等市场不得直接套用英语或中文表达。
- **地区变体明确记录**：首发采用 `en-US`、`fr-FR`、台湾用语的 `zh-Hant` 等方案时，记录覆盖区域、已知词汇差异和暂不支持的变体，避免把语言代码误当成完整地区本地化。

---

## 5. 翻译工作流

### 5.1 流程

```
术语表定稿（§8）→ knownRegions 追加 → 生成资产工作簿（§5.4）
  → 在 Excel 中按语言分批翻译（开发者自主，质量最高）→ import 回写
  → check 门禁（0 缺译 / 0 多余 / 格式）→ 模拟器截图走查
  → 商店元数据 / 截图 / 隐私政策 / 订阅描述 并行
```

### 5.4 Excel 资产工作簿（与工具链配套）

`docs/localization/global-localization.xlsx` 是唯一的人工翻译/资产管理入口，由 `tools/localization-assets.py` 生成（幂等，重新生成不覆盖 `.xcstrings` 中已有译文）：

```
python tools/localization-assets.py        # 重新生成工作簿
python tools/localization.py import docs/localization/global-localization.xlsx MiLens/Resources/Localizable.xcstrings --lang en
python tools/localization.py import docs/localization/global-localization.xlsx MiLens/Resources/InfoPlist.xcstrings --lang ja
python tools/localization.py import docs/localization/global-localization.xlsx MiLensWidget/Localizable.xcstrings --lang ja
```

工作簿 10 个 sheet：

| sheet | 内容 | 与工具链关系 |
|---|---|---|
| `Resources.Localizable`（App）| 全部 key × 6 语言（列结构与 `localization.py export` 一致）| 可直接 `import` 回写 `.xcstrings`；其他 sheet 不影响 import（按 sheet 名匹配）|
| `InfoPlist` | 同上 |
| `MiLensWidget.Localizable`（Widget Extension，47 个 `widget.*` key）| 同上 |
| `状态总览` | 6 类资产 × 6 语言完成度 | 人工维护 |
| `AppStore元数据` | 名称/副标题/描述/关键词/推广文本/审核备注 | 录入 ASC 时人工搬运 |
| `订阅产品描述` | 3 产品 × 显示名/描述 | 同上 |
| `隐私政策` | 章节级译文 | 同步到 `privacy-policy.html` |
| `截图素材` | 每设备 3-5 张截图 × 画面说明/叠加文案 | 制作截图时人工搬运 |
| `ASO关键词` | 每语言关键词 + 竞争度/长尾备注 | 录入 ASC 时人工搬运 |
| `术语表` | §8 核心术语 × 6 语言 | 翻译时参照 |

**state 列语义**（工具链原生约定）：初译由脚本以 `needs_review` 状态写入（当前工作簿 en 列 150 条已就位，尚未回写到 `.xcstrings`）；人工审校后**清空该语言 state 列**再 `import`，工具即按 `translated` 落库。数值/占位符/换行符在 Excel 中保持不变。当前 `check` 会拦截缺失、空值和 `new`，但不会拦截 `needs_review`；发布门禁需补充这一规则。

> **红线（2026-08-17 事件教训）**：翻译完整导入前，`.xcstrings` 只能含源语言 zh-Hans。catalog 一旦出现某语言的任何条目，该语言即进入 bundle 可用语言表，对应偏好的模拟器/设备上其余 key 缺译时 `String(localized:)` 会返回 key 本身而非回退源语言——1c623e9 曾混入 117 条 en 初译，en 模拟器上 AnniversaryTimeMachineLogicTests 等 15+ 例断言拿到 key 本身，App 作业 exit 65（run 31961031119）；b3b0a79 回退后全绿（run 31961932575）。批量回写必须走 `import --lang <L>`，且译文已人工审校。

> 不想碰命令行时可用桌面 GUI：`python tools/localization-gui.py`（tkinter 工作台，见 DEVELOPMENT.md §4.5）——语言进度总览、缺译清单、一键导出/导入/check/生成工作簿；无显示环境用 `--self-check` 自检。

### 5.2 翻译顺序（按市场优先级）

| 批次 | 语言 | 理由 |
|---|---|---|
| 批次 0 | en | 第二参照语言，锁定术语的英文形态，其他语言翻译时对照 |
| 批次 1 | ja、zh-Hant | 两个高价值东亚市场，与中文语法结构接近度高 |
| 批次 2 | de、fr | 剩余首发市场，de/fr 需要长度与词性专项处理 |

### 5.3 翻译质量要求

- 每语言翻译完成后通读一遍（开发者专业能力直接兑现）；
- 对照 en 版复查译义漂移（源语言简中 + 参照 en 双校验）；
- 付费墙、订阅说明、权限文案是**最高优先级质量对象**（直接关系转化与审核）；
- 数值/占位符/换行符完整性由 `localization.py check` 守护，翻译时勿改动 `%`、`{placeholder}`、`\n`。

### 5.5 翻译上下文与版本维护

- Excel 中每条译文应附带页面/功能、控件类型、字符预算、语气、是否允许换行、占位符说明和截图上下文；只给 key 和源文案不足以保证准确翻译。
- 术语表除推荐译法外，增加“禁用表达/风险”和“适用场景”列；按钮、通知、错误提示、付费墙和纪念文案不能默认共用同一语气。
- 中文源文案新增或修改后，所有受影响译文自动标记为 `needs_review`；删除 key 前先检查代码、通知、网页和商店素材引用。
- 每次导入记录源文案版本、译文审校人、审校日期和影响语言；版本发布时生成本地化变更清单。
- 初译、自审、母语终审分开记录。开发者自审可作为初译完成，不替代日/韩/德/法等高风险语言的母语级终审。

---

## 6. 质量保证与门禁

| 门禁 | 工具 | 触发时机 | 通过标准 |
|---|---|---|---|
| key 完整性 | `localization.py check` | CI Lint 作业 + 本地 | 代码缺 key 阻断；多余 key 警告（不阻断） |
| 缺译检测 + 每语言计数 | `localization.py check` | 同上 | 阻断缺失/空值/`new`；输出每语言进度统计表；`--strict` 把 `needs_review` 升级为阻断。过渡期（2026-08-15 起）：CI 带 `--allow-missing-translations` 把缺译降为警告，翻译完成后移除 |
| 占位符漂移 | `localization.py check` | 同上 | 普通条目译文 `%d`/`%@` 占位符集合与源一致（默认阻断）；复数条目由 plural 校验 |
| 译文长度 | `localization.py check --length-rules` | 每语言导入后 | 按 `tools/loc-length-rules.example.json` 规则校验超限（精确 key > comment `[len:N]` > 最长前缀 > default）|
| 硬编码文案 | `localization.py check --hardcoded` | 翻译前 + CI | 无 SwiftUI 文案 API（Text/Label/Button/navigationTitle 等）首参含 CJK 且不在 catalog 的硬编码 |
| 英文装饰文案 | `localization.py check --hardcoded` | 翻译前 + CI | UI 文案 API 首参纯拉丁且含全大写词（warning 级 `[英文装饰]`，不阻断）；品牌词/技术缩写/水印整串白名单放过；已 key 化（catalog 命中）不报（§3.7）|
| 动态文案完整性 | `localization.py check`（plural 支持已落地）+ 固定 locale 快照测试 | 每语言导入后 | plural 键完整（en/de/fr one/other，zh/ja/ko 单条）；`%d`/`%@`/`\n` 占位符与代码引用一致（§3.6）|
| 术语一致性 | 术语表人工走查 | 每语言翻译完成 | 核心术语逐条对照 §8 |
| 长度/截断（视觉） | 模拟器截图走查 | 每语言导入后 | 无截断、无溢出、无重叠（de/fr 必查）|
| 字体缺字 | 模拟器截图走查 | zh-Hant/ja/ko 导入后 | display 字体回退正确（§4.8 技术项）|
| 商店文案一致性 | 人工核对 | 上架前 | 描述/截图/审核备注与实际功能一致（诚实原则）|
| 隐私政策可访问 | 人工核对 | 上架前 | 各语言 URL 可访问、内容与 App 行为一致 |

> check 增强（2026-08-12）：每语言缺译计数、占位符漂移（默认阻断）、`--strict`（needs_review 阻断）、`--length-rules`、`--hardcoded` 均已落地，单测见 `tools/test_localization.py`。CI 接入 `--strict` 即可作发布门禁；多余 key 与格式不一致（非 Xcode 风格）仍仅告警。
> check 增强（2026-08-16）：`--hardcoded` 新增英文装饰检测（warning 级，§3.7）；Swift 字符串 Unicode 转义（`\u{XXXX}`）还原后再比对，单测增至 25 用例。
> check 增强（2026-08-16，多 catalog）：MiLensWidget 接入第三个 catalog（47 个 `widget.*` key）；`--source-root` 可重复，每个 Localizable catalog 与其路径祖先源码根的代码配对比对（App 与 Widget 互不误报）；App 与 Widget 同名 catalog 导出 Excel 时 sheet 名以父目录去歧义（`Resources.Localizable` / `MiLensWidget.Localizable`），import 兼容旧表裸 stem；单测增至 34 用例。
>
> 缺译降级（2026-08-15）：7 语言 knownRegions 已定而 6 语言翻译未开始，缺译阻断使 CI lint 必挂并连带跳过 app 作业（`needs: [kit, lint]`）。过渡期 CI 命令带 `--allow-missing-translations`：非源语言缺译降为警告（聚合输出）不阻断；`--strict` 发布门禁下缺译仍阻断。全部语言翻译完成后移除该参数，恢复默认缺译阻断。

### 6.1 自动化检查与伪本地化

正式翻译前先用伪本地化暴露布局问题，真实翻译后再做语言验收：

- 生成英文扩展约 30% 的伪本地化文本，检查 Tab、按钮、付费墙、卡片和错误弹窗是否截断、溢出或重叠；
- 自动检查 key 完整性、占位符集合、换行符、plural 分支、`needs_review`、多余 key、格式规范化和源文案意外漏出；
- 每种语言至少覆盖 iPhone 小/大尺寸、iPad、深色模式、Dynamic Type 最大字号和 VoiceOver；
- 对长宠物名、长文件名、空状态、通知锁屏、分享预览和 StoreKit 失败路径做固定回归样例；
- 记录每次模拟器走查的语言、设备、系统版本、页面、截图和问题编号，避免只保留“人工看过”的口头结论。

---

## 7. ASO 关键词策略（每语言）

| 语言 | 核心词族 | 长尾机会 | 竞争度 |
|---|---|---|---|
| zh-Hans | 宠物照片、宠物相册、拼豆、拼豆图纸 | 拼豆图纸（低竞争高意图）| 中 |
| zh-Hant | 寵物照片、拼豆、毛小孩、貓咪 | 拼豆圖紙、寵物相簿 | 低 |
| ja | ペット写真、アイロンビーズ、写真整理 | アイロンビーズ図案 | 中（ビーズ词族低）|
| ko | 반려동물、강아지、고양이、비즈 도안 | 비즈 도안、반려동물 앨범 | 中 |
| en | pet photos、perler beads、bead pattern | perler bead pattern（长尾）| 高 |
| fr | perles à repasser、photos animaux | album chat、perles à repasser modèle | 低 |
| de | Bügelperlen、Haustier、Fotoalbum | Bügelperlen Vorlagen | 低-中 |

**ASO 执行规则**
- 每语言 100 字符限额内做满，词间用逗号（App Store 语法）；
- 品牌词（MiLens/咪Lens）不占关键词位置；
- 首发后 2 周按搜索量数据调整一次，之后每月复查；
- 每个市场至少 5 条关键词覆盖"品类词 + 场景词 + 长尾意图词"。

### 7.1 商店元数据独立验收

App Store 元数据与 App 内翻译分别验收，提交 ASC 前逐语言核对：

- App 名、副标题、关键词、描述和推广文本的字符限制；
- 关键词重复、品牌词、商标词和地区用词；
- App 名、截图、付费墙、订阅产品描述中的权益、价格、试用期和自动续费说明一致；
- 审核备注只描述当前构建已交付的能力，测试步骤、权限流程和购买流程与实际版本一致；
- 截图中的功能、按钮和隐私承诺必须能在对应语言的当前构建中复现；
- 每个语言/地区保留最终提交文本和 ASC 截图，便于后续复盘和快速修订。

---

## 8. 核心术语表（草案，翻译前定稿）

> 以下为方向性草案，实际定稿需在批次 0 翻译时锁定；一经定稿全文统一，不再改动。

| 中文（源）| en | ja | ko | de | fr | zh-Hant |
|---|---|---|---|---|---|---|
| 拼豆图纸 | bead pattern | アイロンビーズ図案 | 비즈 도안 | Bügelperlen-Vorlage | modèle de perles à repasser | 拼豆圖稿 |
| 拼豆工作室 | bead studio | ビーズスタジオ | 비즈 스튜디오 | Bead-Studio | studio de perles | 拼豆工作室 |
| 伙伴档案（原宠物档案，2026-08-22 收口） | pal profile（禁用 pet，一律 pal/companion） | ペットのプロフィール | 반려동물 프로필 | Haustierprofil | profil du compagnon | 生命檔案／毛小孩檔案 |
| 伙伴（产品称呼，原「宠物」已收口） | pal / companion（禁用 pet） | ペット（日语中性，可用） | 반려동물 | Haustier / Freund | compagnon | 毛小孩（2026-08-22 统一，不用「毛孩」） |
| 成长时间线 | growth timeline | 成長タイムライン | 성장 타임라인 | Wachstumszeitleiste | chronologie de croissance | 成長時間軸 |
| 往日回忆 | memories | 思い出 | 추억 | Erinnerungen | souvenirs | 往日回憶 |
| 时光机 | time machine | タイムマシン | 타임머신 | Zeitmaschine | machine à remonter le temps | 時光機 |
| 照片不离开设备 | photos stay on device | 写真は端末から出ません | 모든 분석은 기기에서 처리됩니다 | Alle Fotos bleiben auf Ihrem Gerät | traitement 100 % local | 照片不會離開手機 |

术语表定稿时同时补充以下字段：

| 字段 | 用途 |
|---|---|
| 适用场景 | 区分按钮、标题、通知、付费墙、隐私政策和商店文案 |
| 禁用表达/风险 | 记录商标误用、文化风险、过时称呼和容易误解的直译 |
| 语气/语法要求 | 记录敬语、正式度、性别、复数、标点和地区差异 |
| 审校状态 | 初译、开发者自审、母语终审、已锁定 |
| 最后变更 | 记录变更日期、原因和受影响页面 |

---

## 9. 验收标准（首发前逐条打勾）

- [ ] `project.yml` knownRegions 含 6 语言，CI 构建通过；`ko` 不纳入首发目标
- [ ] 每种语言分别记录翻译、UI 验收、商店资产、隐私政策上线四项状态；P0/P1 降级策略已明确
- [ ] 全部 String Catalog key（App `Localizable` / `InfoPlist` / Widget `Localizable`，随 key 化批次增长）× 6 种非源语言全部翻译完成，`localization.py check` 0 缺译，且无 `needs_review`
- [ ] MarketProfile 区域差异化已落地（标题字体策略 + 隐私叙事强度），并完成 6 语言模拟器走查（zh-Hans/zh-Hant/ja 区域标题字体不缺字，fr/de Latin Extended 字符不缺字；GDPR 区 PrivacyInfoView 4 条承诺不截断）
- [ ] de/fr 长度专项走查：Tab/按钮/付费墙/卡片无截断溢出
- [ ] 术语表定稿且全文一致（§8 清单）
- [ ] App Store 元数据 6 语言录入（名称/副标题/描述/关键词/推广文本/审核备注）
- [ ] 商店元数据独立完成字符限制、关键词/商标、权益价格、截图和审核备注一致性验收
- [ ] 订阅产品 3 个 × 6 语言本地化描述录入
- [ ] 截图 6 语言（或至少 en/ja/zh-Hans + 其余复用英文，后续补齐）文案覆盖层走查
- [ ] 隐私政策 6 语言可访问且与 App 行为一致
- [ ] 审核备注：英文通用版 + ja/ko/zh-Hant 当地语言版
- [ ] 动态文案 10 类覆盖清单（§3.6）逐类走查，无遗漏硬编码用户可见文案
- [ ] 伪本地化扩展测试、长文本/Dynamic Type/深色模式/iPad/VoiceOver 回归完成并留存证据
- [ ] plural 翻译完整（en/de/fr one/other，zh/ja/ko 单条），`localization.py check` plural 校验通过
- [ ] accessibilityLabel 全部核对迁移完成，VoiceOver 每语言抽查（Tab/编辑器工具/拼豆操作路径）
- [ ] 通知/水印/宠物卡片动态文案本地化完成，固定 locale 快照测试通过（en_US/de_DE/ja_JP 等）
- [ ] 各国注意要点 §4 逐条落实
- [ ] 功能承诺、隐私措辞、备份例外、商标词和市场假设完成事实核对；高风险语言完成母语级终审
- [ ] 源文案版本、译文审校人/日期、变更影响和发布版本记录完整

---

## 10. 工作项清单（落地顺序）

| # | 工作项 | 依赖 | 预计 |
|---|---|---|---|
| 1 | knownRegions 追加 6 语言 | — | ✅ 已完成 |
| 2 | Typography locale 感知字体回退 | #1 | ✅ 已完成 |
| 2.1 | **MarketProfile 区域差异化基础设施**：`MarketProfile` 模型 + `@Environment(\.marketProfile)` 注入 + Typography 委托 + PrivacyInfoView 隐私叙事强度（GDPR 区第 4 条强化声明）+ `PrivacyNarrativeLogic` 纯逻辑 + 22 单测；5 处硬编码 `zh_CN` 清理 | #2 | ✅ 已完成（2026-08-13）|
| 2.5 | Excel 资产工作簿（`localization-assets.py` + 9 sheet，en 初译 150 条）| #1 | ✅ 已完成 |
| 3 | 术语表定稿（批次 0 前）| — | 0.5 天 |
| 4 | en 全量审校 + 导入 + check | #3 | ✅ 已完成（2026-08-21，1239 key 100% 注入，0 缺译，pal 规范落地）|
| 5 | ja + zh-Hant 翻译 | #4 | 1-2 天 |
| 6 | ko + de + fr 翻译（de/fr 长度专项）| #4 | fr ✅ 100% 完成（2026-08-22，全部 1245 key 注入）；ko/de 待完成 |
| 7 | `localization.py check` 增强：每语言统计 + `needs_review`(`--strict`)/占位符漂移(默认阻断)/长度规则(`--length-rules`)/硬编码检测(`--hardcoded`)；单测 `tools/test_localization.py` | #4 | ✅ 已完成（2026-08-12）|
| 7.5 | 工具链 plural 支持（export 拆行 `key[one]/[other]` / import 合并回写 / check 完整性 / GUI 与资产工作簿同步）| #7 | ✅ 已完成（端到端测试通过）|
| 7.6 | accessibilityLabel 等 UI 字面量核对与迁移（22 处 → `String(localized:)` 或 catalog 补 key）| #7 | ✅ 已完成（25 个 `a11y.*` key）|
| 7.7 | 纯逻辑层动态文案本地化（通知 6 模板 / 宠物卡片 / 物种名 / 年龄 / 时间线导出 / 水印 / 分享 / 首页 / 启动错误）| #7.6 | ✅ 已完成（代码部分；快照测试 → #7.7b）|
| 7.7b | 动态文案固定 locale 快照测试（en_US/de_DE/ja_JP 断言，复用 utcCalendar 注入模式）| #7.7 | ✅ 已完成（2026-08-16 `DynamicCopyLocaleSnapshotTests`：zh-Hans 全量精确快照（通知/档案/卡片/导出）+ en_US/de_DE/ja_JP 回退等值层；`String(localized:locale:)` 不切换查表语言，各语言精确快照随 #4–#6 翻译导入升级）|
| 7.8 | 空状态与错误提示盘点收口（全部调用点核对、三段式规范、StoreKit 错误映射）| #7 | ✅ 已完成（2026-08-16：盘点 74 相关 key（69 used / 5 预留未接线——`picker.redPacket.*` 红包入口实际走 workshop 流程、`redpacket.export.saveFailed`/`redpacket.quality.badge|level.error` 预留）；迁移 19 处硬编码（相册/伙伴/首页空态、扫描权限提示、启动恢复三段、editor 抠图四态、名片保存失败）+18 key；清理 18 条 Xcode 自动提取空壳。遗留：Onboarding 编辑式文案（~19 处）已随 #7.13 收口；MiLensKit 侧 `availableTags`→`availableTagKeys`（12 key）与 `RedPacketQualityItem.detail`→`detailKey`+`detailArgs`（26 分支）已 key 化（2026-08-16，+38 manual key，草稿改存 key 旧值宽容保留），剩余 `cutoutStatusText`（Kit 层中文、有 Kit 测试锚定））|
| 7.9 | 工作簿补充翻译上下文、禁用表达、审校人/日期和源文案版本字段 | #3 | 0.5 天 |
| 7.10 | 页面级 key 化批次（按页迁移裸中文 → `String(localized:)`）：PetEditView 整页 | #7.8 | ✅ 已完成（2026-08-16：View 19 处 + PetEditViewModel 6 处（错误/特征注册提示）+ 纯逻辑层 3 处（PetFormLogic 备忘校验、PetProfileLogic 名字必填，`locale: Locale = .current` 注入模式）；catalog +40 key（38 个 `pet.edit.*` + `common.delete` + `pet.form.name.required`，zh-Hans 与原裸中文逐字一致，既有中文断言测试不动）；清理 5 条无引用空壳（“保存”保留——EditorView 仍字面量引用）；check（CI 同款 `--allow-missing-translations`）0 阻断、无缺 key、无多余新 key，`--hardcoded` 中本页 4 文件清零。遗留：EditorView 等其余页面同批次推进；Onboarding 已随 #7.13 收口）|
| 7.11 | 装饰性英文文案 key 化收口（25 处硬编码 → `String(localized:)` + 25 key 落库 zh 原样/en 初译 needs_review；OnboardingViewModel.stepOverline 统一 7 个 step 视图 overline 消重复；`--hardcoded` 增英文装饰 warning 检测 + 词级白名单与 MILENS 水印整串白名单；§3.7 规范增补）| #7.10 | ✅ 已完成（2026-08-16：含 plural `pet.profile.lifeMark %lld`；`OnboardingViewModelTests` 断言改 catalog 同表查取防语言环境 flaky；资产工作簿再生成 en 初译 181 条。遗留登记（随 #7.10 页面级批次推进）：BeadResultComponents:24 副标题中文、PetProfileComponents:107-141 样例卡中文叙事、BusinessCardArtwork 中文 fieldLabel、PetsView:230-243 生日彩蛋、Onboarding 编辑式正文中文 ~19 处（已随 #7.13 收口）；`NEXT LEAF · 2026.06` 等假日期数据改真数据另走产品决策）|
| 7.12 | Widget Extension 本地化接入（`MiLensWidget/Localizable.xcstrings`；7 个 Widget Swift 文件硬编码迁移 `String(localized:)` `widget.*` 语义 key；`check` 多 catalog × 多源码根配对；Excel sheet 去歧义 + GUI/资产工作簿/CI lint 同步）| #7 | ✅ 已完成（2026-08-16：47 key = intents 13 / lifeArchive 7 / upcoming 7 / common 5 / lockscreen 5 / photoEcho 5 / stale 2 / entity 2 / empty 1；catalog 经 XcodeGen 整目录（`sources: [MiLensWidget]`）编入 Widget target，Extension 内 `String(localized:)` 默认查自身 `.appex` bundle；check 验证 Widget catalog 0 缺 key / 0 多余 key，单测 34 用例。同日提取器形态扩展收盲区：配置面 API（configurationDisplayName/.description/IntentDescription/@Parameter(title:)/LocalizedStringResource 赋值）+ Text/字典 dotted key 模糊形态（switch-case SF Symbol 映射排除），widget 49 refs 全命中 0 缺 key，单测增至 38 用例。遗留：非源语言译文随 #4–#6 翻译批次导入，Widget 桌面/锁屏渲染文案同步进入走查 #8）|
| 7.13 | Onboarding 引导流程整页 key 化（7 个 step 视图 + OnboardingViewModel + PetProfileLogic 数量校验；裸中文 → `String(localized:)`）| #7.10 | ✅ 已完成（2026-08-16：Welcome/Privacy/CreateArchive/FeatureRegister/FullScan/Candidates/Import 7 视图 113 处 + ViewModel 6 处（扫描进度/保存失败/张数上下限/注册结果）+ `checkPetCountLimit`（`pet.form.countLimit %lld`，locale 注入）；catalog +137 key（脚本插入 120 zh-Hans manual + 人工补录 17 含 en needs_review 初译：`onboarding.overline.*`×10 + mark/baseline/onDevice 装饰 7），zh value 与原裸中文逐字一致（`...`/`…`/`–`/`—` 逐字符保真，保证既有中文断言测试零改动）；物种 chip 复用 `PetDisplayLogic.speciesDisplayName`；三处 stageRow isDone 改「同 locale 解析结果相等」比较；check（CI 同款 `--allow-missing-translations`）0 阻断、无缺 key、无多余新 key。遗留：120 个新 key 仅 zh-Hans，en 等非源语言随 #4–#6 翻译批次导入）|
| 8 | 伪本地化 + 模拟器走查 × 7 语言（长度/字体/截断/Dynamic Type/iPad/VoiceOver）| #5 #6 | 1-2 天 |
| 9 | 商店元数据 7 语言 + 订阅描述 + 审核备注 + 独立一致性验收 | #5 #6 | 1-2 天 |
| 10 | 截图素材本地化（文案覆盖层）| #9 | 1-2 天 |
| 11 | 隐私政策多语言 + 法律语境审阅 + 部署和 URL 验收 | #9 | 1-2 天 |
| 12 | 首发后 2 周 ASO 复查 + 用户反馈迭代 | 上线 | 持续 |

> 合计约 13-18 个工作日（含 §3.6 动态文案、伪本地化、元数据独立验收和隐私政策部署；开发者自主翻译，外包/并行可压缩；截图与 ASC 录入可在等待翻译期间并行）。
