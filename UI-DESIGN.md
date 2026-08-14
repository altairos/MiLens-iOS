# MiLens iOS UI Rework 设计规范

最后核对：2026-08-13（Image Workshop 贴纸/相框操作态与纪念作品注释编辑态）

> 本文是 MiLens iOS 视觉、交互和页面规格的唯一事实来源。产品范围以 [ADR-0008](docs/adr/0008-v1-scope-decision.md) 为准，技术架构见 [DESIGN.md](DESIGN.md)，本轮审计结论见 [docs/UI_REWORK_AUDIT.md](docs/UI_REWORK_AUDIT.md)。旧页面原型只保留产品叙事，不再作为布局或功能范围依据。
>
> 本文描述下一轮目标状态，不表示当前 SwiftUI 或 Asset Catalog 已完成。现有 v1 token 与页面代码需要在实施 Phase B/D 按本文迁移。

## 0. 设计结论

MiLens 的界面不应是“伙伴元素装饰过的照片工具”，而应是一个以照片为证据、以时间为结构、以伙伴为主角的私人生命档案。

本轮保留三件事：

- 中性画廊底色，让照片提供主要色彩。
- 暖珊瑚作为品牌记忆点。
- “找回被遗忘的身影，保存属于你们的一生”的情感主线。

本轮废止四件事：

- 用大号爪印、Emoji 和成排圆角卡片代替品牌设计。
- 把霞鹜文楷用于所有页面标题、再混用 Fraunces 和系统字体。
- 在 V1 页面或付费墙承诺 AI 写真、回忆视频等未纳入范围的能力。
- 只描述氛围，不定义布局、状态、响应式和验收方式。

## 1. 产品体验模型

### 1.1 三层价值

1. **找到**：在本机照片中发现可能含伙伴的内容，用户确认后导入。
2. **保存**：归入伙伴档案，以日期、纪念日和备注形成生命时间线。
3. **再创造**：从已有照片进入拼豆、卡片或图片编辑，不打断档案主线。

V1 的 AI 能力必须描述为“帮助发现可能含伙伴的照片”，不得表达为“认识每一位伙伴”或“自动建立完整档案”，除非对应模型和真机结果已达到验收门槛。

### 1.2 信息架构

底部维持四个一级入口：

| Tab | 用户问题 | 主要内容 | 禁止放入 |
|---|---|---|---|
| 首页 | 今天有什么值得回看？ | 今日照片、往年今日、临近纪念日、一个创作入口 | 功能宫格、设置项 |
| 伙伴 | 他/她的一生保存得怎样？ | 伙伴列表、档案、照片分组、成长时间线 | 全局扫描进度、商业广告 |
| 创作 | 我能用这些照片做什么？ | 拼豆图纸、纪念卡片（含成长对比）、伙伴名片、红包封面；从作品选择照片 | AI 写真、回忆视频占位入口 |
| 我的 | 数据和购买由我怎样控制？ | Pro 状态、隐私、通知、外观、帮助、关于 | 假头像、账号等级、社交数据 |

图片编辑器是照片详情的上下文工具，不作为一级入口。相册是跨域内容库，从首页与伙伴档案进入，不占用新的 Tab。伙伴档案不是照片列表的包装，而是一个可被用户确认、补写、置顶和回看的长期对象，详细模型见 [伙伴生命档案设计](docs/Life-Archive-Design.md)。

### 1.3 两条核心闭环

首次价值闭环：

```text
欢迎 → 本地处理说明 → 请求照片权限 → 扫描候选
→ 用户确认并选择伙伴/新建档案 → 导入完成 → 打开第一份档案
```

日常回访闭环：

```text
首页回忆/提醒 → 照片详情 → 补充备注或进入创作 → 回到档案
```

扫描结果不等于导入成功。引导结束前必须让用户清楚知道哪些照片会进入 MiLens，并完成至少一次用户确认；拒绝权限时提供“稍后设置”和 PHPicker 手动选图路径。

## 2. 视觉方向：Quiet Archive

关键词：安静、真实、时间感、私密、精确。

- **照片是真正的品牌资产**：有照片时不使用大号通用插画或爪印抢占首屏。
- **时间是视觉骨架**：日期、年份、时间线圆点和短横线组成“档案标记”语言。
- **珊瑚色是动作，不是背景**：只用于关键动作、选中态和少量时间节点。
- **卡片不是默认容器**：优先用留白、对齐和细分隔；只有可独立点击或需要表面分层的内容才使用卡片。
- **不伪装成儿童产品**：不使用 Emoji 作为图标或占位；物种占位用首字或线描剪影，保持 Quiet Archive 的克制感。

### 2.1 品牌识别元素

统一使用“记忆标记”而非重复爪印：一个 6pt 珊瑚圆点、1pt 时间线和紧邻的日期标签。它可出现在首页分节、时间线、扫描完成和付费墙，但每屏不超过三组。

App 图标、空态插画与商店截图需要单独产出；未有品牌插画前，使用照片、SF Symbols 与排版完成页面，不用大型 SF Symbol 假装品牌插画。

## 3. 色彩系统

### 3.1 纠正后的语义色

原品牌珊瑚 `#FD8663` 与白色文字对比度约 2.40:1，不能作为白字主按钮背景；它与浅色页面背景的对比度也不足以承载小字或关键状态。因此拆分“品牌色”和“动作色”。

| Token | Light | OKLCh (Light) | Dark | OKLCh (Dark) | 用途 |
|---|---|---|---|---|---|
| `SurfaceCanvas` | `#FAF8F5` | `oklch(0.980 0.005 78.3)` | `#161311` | `oklch(0.190 0.006 56.0)` | 页面画布 |
| `SurfacePrimary` | `#FFFFFF` | `oklch(1.000 0.000 89.9)` | `#221E1A` | `oklch(0.238 0.010 67.3)` | 独立内容表面 |
| `SurfaceSecondary` | `#F2EFEA` | `oklch(0.953 0.007 80.7)` | `#1C1916` | `oklch(0.216 0.007 67.4)` | 输入、分组、占位骨架 |
| `SurfaceElevated` | `#FFFFFF` | `oklch(1.000 0.000 89.9)` | `#2C2722` | `oklch(0.276 0.012 67.3)` | Sheet、浮层、吸底栏 |
| `TextPrimary` | `#1F1B18` | `oklch(0.226 0.008 59.2)` | `#F2EBE3` | `oklch(0.943 0.013 71.3)` | 主文字 |
| `TextSecondary` | `#6B625B` | `oklch(0.502 0.016 60.3)` | `#B5A89C` | `oklch(0.739 0.023 65.2)` | 次文字 |
| `TextMuted` | `#776D65` | `oklch(0.542 0.018 61.1)` | `#91857A` | `oklch(0.624 0.022 65.0)` | 辅助文字；仍需逐场景检查 |
| `BrandCoral` | `#FD8663` | `oklch(0.746 0.153 37.2)` | `#FD9A79` | `oklch(0.781 0.128 39.2)` | Logo、装饰点、非文字品牌瞬间 |
| `ActionPrimary` | `#BC4727` | `oklch(0.553 0.158 35.9)` | `#E8845F` | `oklch(0.714 0.133 40.8)` | 主按钮、选中态、可交互图标 |
| `OnActionPrimary` | `#FFFFFF` | `oklch(1.000 0.000 89.9)` | `#161311` | `oklch(0.190 0.006 56.0)` | 主按钮文字 |
| `AccentSoft` | `#FCE8DF` | `oklch(0.945 0.025 45.9)` | `#3A241C` | `oklch(0.286 0.037 40.8)` | 轻选中底色 |
| `BorderSubtle` | `#E5DFD8` | `oklch(0.906 0.012 71.9)` | `#383129` | `oklch(0.318 0.017 70.9)` | 0.5–1pt 边界 |
| `Separator` | `#ECE7E1` | `oklch(0.930 0.010 72.7)` | `#2E2823` | `oklch(0.282 0.013 62.1)` | 非交互分隔 |
| `Success` | `#2F7D57` | `oklch(0.531 0.098 159.0)` | `#72C998` | `oklch(0.768 0.111 157.7)` | 成功 |
| `Warning` | `#9A5B00` | `oklch(0.531 0.119 65.1)` | `#F0B85A` | `oklch(0.816 0.128 78.2)` | 警告 |
| `Danger` | `#B33A36` | `oklch(0.524 0.158 26.0)` | `#EF7D76` | `oklch(0.717 0.141 24.9)` | 删除、失败 |

实施规则：

- `ActionPrimary` Light 上使用白字，Dark 上使用暖黑字。
- `BrandCoral` 不承载正文、小图标、按钮文字或唯一状态差异。
- 正文目标对比度不低于 4.5:1；大字和关键非文字控件不低于 3:1。
- 为 Increase Contrast 补充高对比 Appearance；Reduce Transparency 下不得依赖材质模糊保持可读。
- 深色照片缩略图不统一加滤镜；只有大面积纯白照片在全屏查看时允许轻微降低周围画布亮度。

## 4. 字体与内容层级

### 4.1 字体策略

系统字体负责所有操作性内容。自定义字体只负责少量情感表达。

| 层级 | 字体 | 基准样式 | 用途 |
|---|---|---|---|
| `heroTitle` | 霞鹜文楷 Regular | 32pt / largeTitle | 首页问候、伙伴名字；每屏最多一次 |
| `storyTitle` | 霞鹜文楷 Regular | 24pt / title2 | “一年前的今天”“相伴的故事” |
| `navTitle` | 系统字体 Semibold | title2/largeTitle | 导航与工具页面标题 |
| `sectionTitle` | 系统字体 Semibold | title3 | 功能分节 |
| `body` | 系统字体 Regular | body | 正文 |
| `supporting` | 系统字体 Regular | subheadline | 说明 |
| `caption` | 系统字体 Regular | caption | 日期、元信息 |
| `metric` | SF Rounded Semibold | title2 | 照片数、年数、统计 |
| `button` | 系统字体 Semibold | body | 按钮 |

Fraunces 不进入常规 App 界面；仅可用于英文营销物料或最终 wordmark。这样常规页面最多出现系统字体与一套中文情感字体，避免三种视觉声线竞争。

**Figma UI 文本样式 → iOS 字体映射（已知替换）。** Figma 中名为 `MiLens/UI/Title`、`MiLens/UI/Body Strong`、`MiLens/UI/Overline`、`MiLens/UI/Metadata` 等 UI 文本样式标注字体为 **Noto Sans SC Medium**，iOS 实现统一回退**系统字体**（简体中文 PingFang SC / 拉丁 SF Pro），对应 `Typography` 的 `uiTitle` / `uiBodyStrong` / `editorialOverline` / `editorialMetadata` token。理由：零包体积、保持原生字体感、Dynamic Type 全程参与缩放。Figma 节点引用（如 `458:1145`、`422:845`）保留原文「Noto Sans SC Medium」作为设计稿出处，映射规则集中在本节——iOS 不打包 Noto Sans SC 是有意的产品决策，非缺陷。

字体选择由区域差异化模型 `MarketProfile.usesWenKaiDisplay` 控制（`MiLens/ViewModels/MarketProfile.swift`）：仅 zh-Hans 使用霞鹜文楷，zh-Hant/ja/ko 等语言回退系统衬线字体——文楷子集仅覆盖 GB2312 简体字符，其他语言使用会缺字。详见 [docs/Localization-Plan.md](docs/Localization-Plan.md) §4.8。

所有样式必须基于 Dynamic Type；最大辅助字号时允许标题换行、横向按钮改为纵向、统计行改为两列或单列。自定义字体缺字时回退系统字体，不显示方框字。

Figma 紧凑画板的可读性下限按内容职责区分：正文、说明、表单值和交互标签不得小于 11pt，常规正文仍以 15–17pt 为主；10pt 只用于 overline、色号、极短技术标识或状态圆内部的纯装饰字形，任何可见文字不得低于 10pt，交互控件命中区不得小于 44×44pt。代码不得把这些静态 pt 值硬编码为 Dynamic Type 上限，仍需使用语义字体并在辅助功能字号下重排。

### 4.2 文案语气

- 情感但不拟人过度：“一年前的今天”优于“AI 为你唤醒珍贵回忆”。
- 诚实具体：“在本机寻找可能含伙伴的照片”优于“AI 认识每一位伙伴”。
- 称呼规范：伙伴名字与代词绑定档案性别——`男孩子`/`女孩子`（性别未知时回避代词或重复名字，禁止用“它”）；物种显示为`喵星人`/`汪星人`/`其他伙伴`；界面不使用 Emoji 作为图标或占位（物种占位用首字或线描剪影）。
- 动作明确：“确认并导入 38 张”优于“看看它的一生”。
- 错误可恢复：说明发生了什么、数据是否安全、下一步能做什么。
- 不用“暂无数据”“网络开小差”“主人”等泛化模板。

## 5. 布局与组件

### 5.1 响应式网格

| 环境 | 内容宽度 | 页面边距 | 主结构 |
|---|---:|---:|---|
| iPhone compact | 全宽 | 20 | 单列；照片网格 3 列，最小单元 96 |
| iPhone landscape | 全宽 | 24 | 内容与工具可并排 |
| iPad portrait | 最大 786 | 24–32 | 居中单列或 2 栏；档案、工作室优先双栏 |
| iPad landscape | 最大 1180 | 40 | Sidebar/Content/Inspector 或 2 栏 |

间距采用 4pt 基线：`4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 48`。正文最大可读宽度 680pt；设置表单最大宽度 620pt；全屏照片与编辑器不受该限制。

### 5.2 圆角和深度

- 小控件 10pt，输入与次级容器 14pt，Hero/大卡片 20pt。
- 相册连续网格使用 2pt 间隙和 2–4pt 圆角，不把每张照片做成卡片。
- 普通内容不用阴影；浮层用 `0 8 24 / 10% black`，吸底栏用 `0 4 16 / 6% black`。
- 边框优先于阴影。深色模式边框必须可见，但不可形成发光描边。

### 5.3 核心组件清单

1. `PrimaryActionMaterial`：按场景使用 `Focus Dial`、`Contact Proof`、`Darkroom Pulse`，不得收敛成一个万能胶囊；加载时保留宽度与材质轮廓。
2. `SecondaryButton`：描边或无底色；不得与主按钮同权重。
3. `FilterChip`：44pt 最小触控区，选中时同时改变填充、文字/图标和 VoiceOver 状态。
4. `PhotoTile`：图片、选择状态、收藏状态、质量/重复标记；状态不可只靠颜色。
5. `MemoryHeader`：记忆标记 + 日期/标题 + 可选动作。
6. `PetPortrait`：真实头像优先；无头像时使用姓名首字/物种简化占位。
7. `ArchiveStat`：数值、单位、说明；大字号时可重排。
8. `TimelineNode`：时间线、节点、日期、标题、代表照片；无照片仍保持结构。
9. `StateView`：加载、空、拒绝权限、失败、离线/资源缺失五类，均提供明确下一步。
10. `BottomActionBar`：编辑器/导出等沉浸页使用，处理安全区和键盘。
11. `MemoryOrbitTabBar`：四项无文字底部导航，包含精确选中刻度、渐变记忆轨道、56pt 点击区与底部安全区。
12. `PreferenceRow`：54pt 高；布尔项使用 44×26pt 系统 Switch 语义，枚举项使用当前值 + Chevron；帮助与版本信息不复用该组件。

组件按行为定义适用状态：动作组件至少覆盖 Default、Pressed、Disabled；导航覆盖四个 Selected 变体；开关覆盖 On/Off；页面级 Loading、Error 不得硬塞入原子控件。全部组件仍需验证 Dark、High Contrast、Dynamic Type 与 Reduce Motion（如有动效）。

### 5.4 底部主导航：Memory Orbit

- 四项固定为首页、宠物、创作、我的；视觉只显示矢量图标，不显示文字标签，但每项必须保留本地化 VoiceOver 名称、Selected 状态与稳定 accessibility identifier。
- 导航改为与屏幕底边连续的材质平面，不再使用 350×70pt 悬浮胶囊。iPhone 内容区从底部向上占 86pt：图标触控区为 56×56pt，图标内容结束于底部安全区之前；Home Indicator 所在区域只延续背景，不承载操作。iPad 使用同一语法的底栏或 Sidebar 变体，不把 iPhone 宽度硬编码到大屏。
- 选中态由两层组成：图标上方一条 20pt 左右的**精确深铜红短刻度**，以及开放的「记忆轨道」+ 端点。短刻度不使用渐变、不参与动画；轨道以右侧端点为视觉重心，从右向左同时降低颜色深度、透明度与线宽，即右侧深而粗、左侧浅而细。实现上使用三层精确矢量弧叠加形成连续锥度，不使用手绘曲线。端点使用深铜色；未选中图形与记忆点使用 TextSecondary；浅/深色均从 Asset Catalog token 取值。
- 选择变化时只播放图标内部的短动效：三层轨道在约 0.34–0.38s 内依次完成 path trim，端点在约 0.16–0.38s 内淡入并轻微缩放。开启 Reduce Motion 时直接显示最终态；不循环播放，不给页面内容附加位移，不在 Tab 切换上增加触感。
- 图标必须使用固定矢量路径，不用 Emoji、文字轮廓或不同系统版本可能漂移的 SF Symbol。Tab 切换仍由 `TabView` 管理页面生命周期，品牌导航只负责外观、点击入口与选中反馈。
- 使用 `safeAreaInset(edge: .bottom)` 或等价环境安全区实现；页面主要控件不得进入 Home Indicator 区域，也不能靠固定 padding 猜测设备底部高度。

### 5.5 容器微语法：Precision, Fold, Material

- 胶囊只保留给筛选、分段选择和极短状态；横向主行动采用同一材质体系下的三种场景变体，不再使用统一的“书脊端片 + 装订点”模板：
  - `Focus Dial`：默认主行动。独立按钮高度 52–58pt，珊瑚行动面与右侧圆形镜头拨盘一体成形；拨盘按语义承载加号、对勾或前进图形，不能退化为与主体割裂的圆形尾块。用于加入记忆、保存记忆等全局确认动作。
  - `Contact Proof`：只用于扫描/导入照片。以深色胶片框、克制的齿孔和右侧取景门形成“照片接触印样”隐喻；不得泛化到普通保存、确认或导航按钮。
  - `Darkroom Pulse`：用于拼豆生成、高清导出等沉浸式创作动作。使用暖黑行动面、从弱到强的精确珊瑚曝光边、微型直方图与动作图形；独立按钮高度 52pt，结果页紧凑导出位可用 44pt，但触控区不得小于 44×44pt。
- 三种变体共享 12–14pt 收敛圆角、精确矢量几何、明确的主次对比和动作专属图形；禁止回退到全圆胶囊、缺角大按钮、无语义尾块、装订点或手绘装饰线。
- 大圆角容器不得连续堆叠同一种填充。通过照片面、纸张面、低对比描边面、开放分隔线和少量深色面建立层级；同屏最多一个主视觉容器使用 20pt 以上圆角。
- 页面不使用手绘波浪线、手绘圈、随意铰接线或仿手绘描边。必要分隔与选中标记采用 1–2pt 精确直线、规则曲线或边框，并依靠颜色、粗细和留白建立层级。
- 折页只用于一处重点内容或纸张隐喻，尺寸约 14–16pt；不在每张卡片重复，也不把主按钮切成缺角形。
- 不用无业务意义的 `01/02/03` 编号制造“编辑感”。编号只在确有顺序、进度或可引用条目时出现。
- 设置页把可调整偏好与帮助、关于、版本信息分组；布尔项使用可识别的系统 Switch，枚举项使用当前值 + Chevron，不以装饰圈或下划线冒充控件状态。

### 5.6 Figma 可复用组件契约（2026-08-12）

Figma 核心组件集中在 [12 · Design System · Components](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=253-272)，图片编辑/创作扩展组件位于 [15 · Image Workshop · Editing & Keepsakes](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-801) 的 Component Source，基础变量与样式仍以 [11 · Design System · Foundations](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=252-272) 为唯一来源。产品页面必须使用实例，不再复制矢量散件。

| Figma 组件 | Node | 变体/属性 | SwiftUI 落实边界 |
|---|---|---|---|
| `Action/Focus Dial` | [`259:344`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=259-344) | `Intent=Add/Save` × `State=Default/Pressed/Disabled`；Add/Save 文案可覆盖 | `PrimaryActionMaterialStyle.focusDial`；加入记忆、保存档案 |
| `Action/Contact Proof` | [`262:314`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=262-314) | `State=Default/Pressed/Disabled`；文案可覆盖 | `.contactProof`；仅扫描/导入照片 |
| `Action/Darkroom Pulse` | [`263:368`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=263-368) | `Context=Generate/Export` × 三态；两类文案可覆盖 | `.darkroomPulse`；拼豆生成与高清导出 |
| `Navigation/Memory Orbit` | [`272:582`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=272-582) | `Active=Home/Pets/Create/Settings` | `MemoryOrbitTabBar`；390pt 稿高 105pt，其中 86pt 导航内容 + 34pt 重叠安全区洗白，代码必须读取真实 safe area，不能硬编码 390pt |
| `Control/Preference Row` | [`275:522`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=275-522) | `Mode=Toggle On/Toggle Off/Disclosure`；索引、标签、当前值可覆盖 | `PreferenceRow`；Toggle 仍使用 SwiftUI 原生行为，Disclosure 使用 Button/NavigationLink 语义 |
| `Control/Studio Size Selector` | [`285:597`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=285-597) | `Active=15/29/52/78` | `BeadSettingsPanelView` 固定四档尺寸 Picker；不得伪装成任意连续尺寸 |
| `Control/Studio Effect Proof` | [`309:777`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=309-777) | `State=Selected/Default`；名称、说明与推荐标记可覆盖 | `StudioEffectProof`；效果选择使用色珠接触校样和精确顶部索引，不回退到同质胶囊/卡片 |
| `Control/Studio View Mode` | [`286:564`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=286-564) | `Active=Color/Letter` | `BeadPatternResultView` 彩色/字母编号 Picker；只改变显示方式 |
| `Control/Studio Range` | [`287:574`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=287-574) | `Value=Min/Default/Max` | `BeadPatternResultView` 连续预览 Slider；减号/加号具备独立 44pt 命中区，不改变导出分辨率 |
| `Data/Archive Stat` | [`295:587`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=295-587) | `Value`、`Label` 文本属性；宽度可按统计带等分 | `ArchiveStatView`；保持开放报表排版，不把每个读数包装成小卡 |
| `Surface/Archive Panel` | [`296:629`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=296-629) | 档案引言、置顶记忆、时间线入口等文本属性；嵌套 `Archive Stat`，照片由实例覆盖 | `ArchivePanel`；统计、记忆与近期照片属于同一张连续档案纸，不拆成同质圆角容器 |
| `Surface/Identity Strip` | [`299:615`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=299-615) | `Context=Source/Recipe`；`Label`、`Meta`、`Action` 可覆盖，照片由实例覆盖 | `IdentityStrip`；用于拼豆原图与方案上下文，保留接触印、铜色登记轨和 12pt 精确折角，不泛化为普通设置行 |
| `Navigation/Editor Group Dock` | [`458:1145`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=458-1145) | `Active=Adjust/Smart/Decorate` | 一一映射 `EditorDockView` 的一级分组；iPhone 参考态为 342×54pt 浅色连续导航面，三等分目标，三个中文标签统一为 Noto Sans SC Medium 12pt、32pt 文本框，禁止回退到 Inter 导致裁字；选中项使用深铜红图标、文字与 48×2pt 短刻度，未选项使用 `color/text/secondary`；不使用暗房底、悬浮胶囊或卡片阴影 |
| `Navigation/Editor Tool Row` | [`459:1158`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=459-1158) | `Group=Adjust/Smart/Decorate` × `Active=Crop/Rotate/Adjust/Cutout/Text/Sticker/Frame` | 一一映射 `EditorGroupToolRow`；342×40pt 横向滚动，常驻于激活工具面板标题下方作为二级模式切换。Adjust 为裁剪/旋转/调色/翻转，Smart 为主体抠图/智能消除/背景虚化，Decorate **只保留**文字/贴纸/相框；选中项用深铜红文字与 40×2pt 短刻度，刻度顶边与文字底边相距 5pt，不贴行底。贴纸、相框的交互稿不代表代码和素材已交付，能力开放必须受 catalog 与 feature flag 控制 |
| `Control/Workshop Value Rail` | [`460:1133`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=460-1133) | `State=Default/Changed/Disabled`；`Label` 可覆盖 | `EditorAdjustPanelView` 的 342×36pt 连续 Slider 行；03 调色页将亮度、对比度、饱和度、色温、锐化放入 342×85pt 纵向滚动视口，行间距 2pt，不显示易错位的右侧数字，轨道位置由真实 `Double` 值驱动。**iOS 端增强**：调色面板顶部新增 6 款预设滤镜横滚条（原图/鲜明/暖阳/冷调/柔和/黑白，54×54 缩略图 + 名称，选中态铜色描边），预设即一组 `EditorColorAdjustments` 参数复用 CIFilter 管线；手动 5 滑块默认折叠于「手动调整」入口（点开才显示），预设在 MiLensKit `EditorFilterPresets` 维护（纯逻辑 + 单测），偏离预设时高亮自动取消 |
| `Picker/Decoration Asset Cell` | [`552:1084`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=552-1084) | `State=Default/Selected/Locked`；素材预览由实例内容覆盖 | `DecorationCatalog` 的贴纸/相框资源单元；Selected 使用深铜红登记框，Locked 显示 Pro，60×56pt 单元组成横向滚动素材轨。空 catalog 必须显示真实空态，不注入演示素材冒充可用资产 |
| `Picker/Photo Proof Cell` | [`462:1164`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=462-1164) | `Selection=Default/Selected` × `Role=None/Earlier/Recent`；标签、日期和照片可覆盖 | `GrowthComparePhotoPickerView` 双选校样；选择状态与早期/近期业务角色独立表达，不再混入 Primary/Secondary |
| `Control/Creation Template Tab` | [`463:1149`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=463-1149) | `State=Default/Selected/Locked`；`Index`、`Label` 可覆盖 | `PetCardView` / `BusinessCardView` 模板轨；编号属于模板顺序而非状态，Locked 进入真实 Pro 门控 |
| `Field/Keepsake Annotation Register` | [`554:1086`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=554-1086) | `State=Display/Editing`；`Label`、`Value` 可覆盖 | 伙伴卡与成长对比共用的一行注释输入；Display 提供“编辑”，Editing 显示深铜红聚焦刻度与“完成”。SwiftUI 使用单行 `TextField`，建议上限 36 个中文字符；空值回退到模板默认句，输入状态纳入作品草稿 |
| `Action/Creation Output Register` | [`466:1171`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=466-1171) | `State=Default/Pressed/Loading/Disabled`；左右文案可覆盖 | 创作页保存/分享与 `SharePreviewSheet`；异步保存期间必须显示 Loading 或 Disabled |
| `Action/Editor Panel Register` | [`466:1197`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=466-1197) | `State=Default/Pressed/Loading/Disabled`；左右文案可覆盖 | 裁剪、文字、抠图面板的取消/确认动作；不得用于成长对比选择或成品分享 |

上述核心组件与 9 组 Image Workshop 扩展组件均绑定 `MiLens · Semantic` / `MiLens · Metrics` 变量，并已用实例回写 Release Candidate、Dark Mode、Applied、Core Flow、Image Workshop 或 iPad Adaptive Layout 中的适用页面；新增贴纸、相框和注释编辑态仍保持组件连接，未 detached。旧 `Control/Editor Tool Dock` 与 `Action/Output Register` 已退役。Figma 的 `Pressed`、`Min/Default/Max` 等变体只记录视觉验收态；SwiftUI 还需实现弹簧、路径描边、连续 Slider 值、取消与 Reduce Motion。Code Connect 只在代码侧形成一一对应组件后添加，禁止把多个页面私有 View 强行映射到同一 Figma 组件。

### 5.7 重点流程精修与字号验收（2026-08-12）

- [`Paywall` 58:25](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=58-25) / [`Dark 79:712`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=79-712)：下半区改为连续生命档案纸，权益使用开放登记轨，套餐使用票据层级，购买动作保留独立确认印记；不再堆叠通用权益卡片。
- [`Bead Studio / Generating` 91:366](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=91-366) / [`Dark 84:365`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=84-365)：以照片、曝光门、逐步显影的色珠矩阵和开放式显影记录表达真实生成过程；状态、取消和进度不再使用同质圆角卡片。
- [`Core Flow Precision / Add Memory` 211:340](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=211-340) / [`Dark 79:380`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=79-380)：类型切换使用精确分段轨，日期与照片证据收拢到一张连续档案纸；标题、长记忆和保存动作分别使用登记轨、折页纸面与 `Focus Dial`，保持清晰的输入层级。
- Release Candidate 已按 `01–12` 建立完整目录并进入 `FINAL`：首页、伙伴档案、时间线、图库、创作、Paywall、我的、照片详情、添加记忆、拼豆结果、拼豆设置与拼豆生成共 12 张主稿。`Light / Bead Studio / Setup` 与 `Navigation / Memory Orbit / Create · Release Instance` 已重新校正顶部/底部安全区；四个 `Memory Orbit` 实例采用底部约束，交互命中止于 `y=810pt`，不侵入 34pt Home Indicator 参考区。
- 本轮对 Release Candidate、Dark Mode、iPad、Foundations 和 Components 范围共 743 个文本节点做了字号审计并将原 9pt 完成符号提升到 10pt；正文和交互文字均不小于 11pt。最终 12 张 390×844pt 主稿另做逐节点复核：224 个文本节点无缺失字体、截断、越界或禁用字体，顶部关键内容退出 47pt 状态栏参考区，底部交互退出 34pt Home Indicator 参考区，顶部独立操作控件不小于 44×44pt。SwiftUI 实现仍必须读取设备实时 safe area，并在真机复核 Dynamic Type。
- [`15 · Image Workshop · Editing & Keepsakes` 422:801](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-801) 保留 12 张 390×844pt 主页面，并补充 4 张操作态：[`Sticker` 555:1075](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=555-1075)、[`Frame` 558:1152](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=558-1152)、[`Pet Card · Annotation Editing` 563:1149](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=563-1149)、[`Growth Compare · Annotation Editing` 563:1217](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=563-1217)。贴纸/相框采用横向分类轨 + 横向素材轨，07/08 则在成品上下文中提供 Display/Editing 注释登记行。02、07–11 的页面实际填充与变量绑定统一到 `color/surface/canvas`；扩展稿可读文字不小于 10pt，正文/交互不小于 11pt，可见内容不侵入顶部 47pt 或底部 34pt 安全区。`catalog.json` 当前为空，作品注释也尚无业务状态，因此这 4 张是待实现规格，不是已上线声明。

## 6. 关键页面规格

### 6.1 首次启动

分为五段，进度指示不显示“1/4”式任务压力，可用四个安静短线；权限系统弹窗只在用户点击明确按钮后出现。

1. **欢迎**：一张高质量伙伴照片或品牌静帧，标题“把相伴的一生，留在这里”，说明三项真实价值。隐私政策是可点击链接，不用强制勾选冒充法律同意。
2. **本地处理说明**：用“照片不离开设备 / 分析在本机完成 / 由你决定导入什么”三条短说明建立信任。
3. **照片权限**：主按钮“选择访问照片”，次按钮“先手动选几张”；拒绝后显示前往设置与继续体验。
4. **扫描与确认**：扫描中展示阶段而非夸张数字；结果页以网格展示候选，让用户取消误识别，并显示“仅选中的照片会导入”。
5. **建立档案**：输入名字、选择物种（喵星人/汪星人/其他），把候选照片归入档案；完成后直接打开伙伴档案，以真实内容作为情绪峰值。

无权限、没有候选、扫描失败、用户跳过都能进入 App；首页改为对应的可恢复空态。

### 6.2 首页

首页不是入口宫格。内容优先级固定：问候/日期 → 一张主回忆 → 往年今日或临近纪念日 → 一个“去创作”动作。

内容态：

- `newUser`：展示继续导入或建立档案，不伪造回忆。
- `hasPhotosNoToday`：Hero 回退最近一张，标注真实日期。
- `hasToday`：选今日质量较高且非重复的照片。
- `hasAnniversary`：纪念内容提升到 Hero，但保持用户备注原文优先。
- `multiplePets`：显示伙伴归属，允许从名字进入档案。

Hero 比例 iPhone 为 4:5 或 3:4，iPad 最大高度 560pt；用图像焦点信息避免裁掉伙伴的脸。图片上不叠长文，标题与日期放在图外。首页只允许一个实心品牌按钮。

### 6.3 相册与扫描

- 顶部按伙伴、收藏、待整理筛选；扫描作为工具栏动作，不占用永久大卡片。
- 照片按日期分组，网格 iPhone 3 列、iPad 4–6 列；间隙 2pt。
- 多选后出现吸底操作栏：归档到伙伴、收藏、删除；删除必须二次确认并说明是否删除沙盒副本，绝不暗示删除系统相册原图。
- 重复组显示叠片标记，进入比较页后再建议保留最佳；不可自动删除。
- 低质量标记是建议，不是错误。质量分数不直接展示给普通用户。
- 扫描页显示“已检查 / 可能含伙伴 / 等待确认”，支持取消和后台恢复；结束后先确认再导入。

### 6.4 伙伴列表与档案

伙伴列表优先展示真实肖像与一句状态（照片数、最近更新），避免每个字段都挤在卡片上。iPad 使用 Sidebar 列表 + 档案详情。

档案页：

```text
肖像 Hero（约首屏 38%）
名字 / 年龄 / 相处时间
档案摘要：照片 / 记录 / 重要日子
置顶记忆 / 档案起点
最近记忆
全部照片 / 待整理 / 作品
时间线节点 + 代表照片
添加一条记忆
```

名字可叠在肖像底部渐变上，但必须满足对比并提供无照片布局。编辑档案放导航栏；删除放编辑页底部，不在主档案页作为显眼动作。分类只显示有可靠来源的维度，V1 未验证的“幼年/玩耍/睡觉”不以自动分类名义出现。档案允许用户补写标题、日期、备注和关联照片；系统整理内容必须标注“根据日期生成”“照片回忆”等来源，不代替用户编写生命故事。照片详情的档案相关动作优先是“加入记忆”，作品需要回链来源照片或记忆。详见 [伙伴生命档案设计](docs/Life-Archive-Design.md) §2–§4。

### 6.5 成长时间线

- 时间为纵向主轴，年份是大分节；时间线由相处章节、重要日子、照片记忆组、用户记录和作品记录组成，不是无限滚动的单条事件流。
- 档案同时表达日历时间、相处时间和记忆时间：日期是证据，相处天数是关系指标，用户备注和置顶记忆表达意义。
- 生日、领养日、用户备注、照片回忆和作品记录在形状、内容结构和标签上区分，不只靠颜色。
- 事件允许补充标题和代表照片；系统推导事件标注“根据日期生成”，避免与用户记录混淆。
- 支持伙伴筛选与内容类型筛选；单伙伴档案优先提供“全部 / 照片 / 重要日子 / 备注 / 作品”。大字号时筛选改为 Menu，不保留挤压的横向 chips。
- 从档案、时间线和照片详情均可进入“添加一条记忆”，最小表单为标题、日期或日期范围、备注、可选照片和可选置顶。
- 纪念提醒和首页回忆支持进入年度回看，并允许补充今年的照片与一句话；不承诺生成式视频或 AI 代写故事。

### 6.6 创作首页

只展示 V1 可用项目，每项使用“原图 → 成品”的示例视觉，而非图标功能列表。图片编辑器从照片详情进入。当前项目清单：

Figma 实现参考 [`01 · Creation / Studio Index` 422:805](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-805)：拼豆使用单一影像 Hero，伙伴卡使用 4:5 纸样，成长对比与名片使用开放式登记面，红包封面使用独立珊瑚/铜色面；禁止把五个入口再次做成等尺寸、等圆角、等权重的卡片宫格。

伙伴卡与成长对比的成品页均提供一行可编辑注释：默认展示模板句，点击“编辑”后原位进入聚焦态并由系统键盘输入，点击“完成”提交到作品草稿。注释建议限制为 36 个中文字符，导出画面与编辑登记行引用同一状态；空值回退到模板默认句，不允许只改预览文字而不持久化。Figma 主页面与编辑态分别见 [`07` 422:829](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-829) / [`07A` 563:1149](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=563-1149) 和 [`08` 422:833](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-833) / [`08A` 563:1217](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=563-1217)。

| 项目 | 定位 | 免费路径 | Pro 门控 |
|---|---|---|---|
| 拼豆图纸 | 照片 → 可动手完成的像素图案 | 每日 5 次，带水印 | 不限次数、无水印 |
| 伙伴卡片 | 单张照片 + 宠物信息情感纪念卡 | 经典模板，带水印 | 全部模板、无水印 |
| 成长对比 | 同一宠物早期与现在照片并排 | 可预览，带水印 | 高清无水印导出 |
| 宠物名片 | 信息导向社交名片（头像 + 身份 + 性格标签 + 简介） | 标准模板，带水印 | 全部模板、无水印 |
| 红包封面 | 微信红包封面素材（957×1278）+ 4 场景预览 | 拆红包页预览，带水印导出 | 全部 4 场景、无水印 |

红包封面只生成符合微信平台规格的素材与场景预览，不介入发布流程（发布需用户自行登录微信红包封面开放平台，有注册门槛 + 审核 + 付费）。

未实现能力不显示灰色入口、不写“敬请期待”、不放入 Pro 权益。未来能力上线时按独立产品评审加入。

### 6.7 拼豆工作室

- iPhone：预览在上、参数 Sheet 在下；iPad：预览 2/3、Inspector 1/3。
- 参数按“尺寸 / 色板 / 细节”三组分层，默认只露出最常用项。
- 生成必须显示可取消进度；参数变更采用 250–400ms 防抖，不在每个滑块像素都重算。
- 完成采用一次轻成功触感和 250ms 清晰揭示；Reduce Motion 时直接替换。
- 导出页明确分为“保存图片”“分享”“打印图纸”；格式和分辨率按真实实现与 Pro 权益动态展示。

### 6.8 图片编辑器

编辑器服务于档案照片，不复制桌面软件。底部一级分组限定为“调整 / 智能 / 装饰”；现有代码能力为裁切、旋转、调色、文字、抠图，Figma 另为装饰组定义贴纸与相框的后续实现规格。装饰组不包含未设计的“留白”或“签名”；撤销/重做与保存常驻。

相框与贴纸的数据契约、素材批次、实现顺序和验收门禁见 [docs/Frame-Sticker-Development-Plan.md](docs/Frame-Sticker-Development-Plan.md)。

- iPhone 底部工具轨 + 单层面板；iPad 右侧 Inspector。
- iPhone 编辑器使用三层但不重叠的 `EditorPanelArea`：当前参数纸内依次是二级标题、342×40pt 横向滚动 `EditorGroupToolRow`、工具专属参数；342×54pt `EditorDockView` 作为一级分组坞贴在其下方常驻。二级工具轨负责同组模式切换，参数区只承载当前模式内容；必须通过固定高度、裁切和滚动避免三层侵占编辑画布。
- 保存前说明“更新当前照片”或“保存副本”，默认选择可恢复方式。
- 抠图失败明确说明未改变原图；不得用中心裁切作为“抠图成功”的视觉降级。
- 工具切换保留未提交状态时必须确认或自动生成可撤销历史。
- Figma 状态页：[`Adjust` 422:813](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-813)、[`Crop` 422:817](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-817)、[`Text` 422:821](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-821)、[`Cutout` 422:825](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-825)、[`Sticker` 555:1075](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=555-1075)、[`Frame` 558:1152](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=558-1152)。六页共用画布与纸面控制层，但保留各自真实信息：调整以纵向滑动访问五项连续参数且不显示右端数字；裁切显示 3:4 网格、比例、旋转与翻转；文字显示图层、输入、字体、字号、颜色和描边；抠图显示主体轮廓、设备端处理阶段、重试与应用；贴纸显示选中图层的拖动/双指缩放旋转/删除，并以横向分类轨和素材轨选择资源；相框以整画布图层、自动适配比例、移除、横向分类轨和相框缩略图表达。
- 05/05A/05B 的参数纸标题行只显示“文字图层 / 贴纸图层 / 相框图层”和右侧图标动作，不在标题右侧并列图层名、手势说明或“删除/移除”文字；详细操作由画布直接操控、可访问性标签和首次提示承担。
- 390×844pt Figma 参考稿中，03–06 的编辑画布统一为 `x=24 / y=109 / 342×489pt`，参数纸从 `y=606pt` 起，一级 Group Dock 保持 `x=24 / y=767 / 342×54pt`。画布底到参数纸铜红线为 8pt，铜红线底到二级标题顶为 9pt；二级工具轨统一为 `x=24 / y=640 / 342×40pt`。这些数值用于校验页面节奏，不是 SwiftUI 硬编码值；实际布局必须根据 safe area、键盘和可用高度收缩 Inspector。
- 编辑面板不得继续堆同质圆角卡片；使用一张连续控制纸、开放分隔线、精确刻度与少量铜色校准记号。Group Dock 使用与主 Tab 同源的浅色连续导航语法，仅保留顶部细分隔和选中短刻度；图标、标签、指示与命中区域必须相对实时 bottom safe area 布局。
- Image Workshop 页面背景、参数纸和 Group Dock 统一绑定主稿使用的 `color/surface/canvas`；暗房材质只保留在照片留黑、透明预览等画布内部和少数强调动作，不再用于页面背景、Group Dock 或分享页。
- 二级工具行和一级分组坞使用 SF Symbols 语义对应的单体 SVG Vector Group；禁止用多条独立 `Line` 拼图标，也禁止保留零宽符号字符占位。
- Workshop 的选中、轨道、轮廓和行动强调统一绑定 `color/action/brand`（深铜红）。`color/material/studio/copper` 不再用于产品页面或可复用组件实例。
- 带返回导航的 Workshop 页面统一使用 44×44pt 白色圆形 `Navigation / Back` 与深色 `chevron.left` 矢量，位置和主稿导航基线一致。
- Workshop 顶部栏以 [`11 · Red Packet / Upload Guide` 422:845](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-845) 为唯一几何样板：390×844pt 参考稿中返回控件为 `x=18 / y=57 / 44×44pt`，24pt `chevron.left` 在控件内 `10pt` 居中；标题使用 `MiLens/UI/Title`（Noto Sans SC Medium 20/24）、`color/text/primary`，起点为 `x=72 / y=64`；右侧页级动作与标题垂直居中并保持 24pt 右边距。该数值只用于 Figma 参考稿，SwiftUI 必须用真实 top safe area 推导相同关系，不能硬编码 47pt 状态栏高度。
- `01 · Creation / Studio Index` 是带品牌字标的 Tab 根页，不添加返回控件；02–12 的计数、撤销/重做、状态、预览、完成与关闭属于页级 trailing action，统一基线但保留各自语义。顶部栏下方首个内容块至少留出 8pt 光学间隔，不允许与返回圆阴影相接。
- 02 的双时态交换图标使用 20×20pt 单体矢量，中心固定在两张 158pt 校样之间的 `x=195pt` 与照片区域垂直中心 `y=270pt`；12 的 AirDrop、微信、信息和更多均使用 24×24pt 可编辑矢量，不使用 `⌁ / 微 / 信 / •••` 等字符占位。

### 6.9 我的

页面顺序：Pro 状态 → 数据与隐私 → 通知 → 外观 → 支持 → 关于。无账号系统时不显示用户头像、昵称或“登录”。

隐私页必须可看到：本地处理承诺、照片权限状态、通知权限状态、导出数据、清理缓存、删除 App 数据说明。清理缓存与删除档案严格分离。

### 6.10 付费墙

付费墙只在用户触发受限能力时出现，或在完成首次档案后以非阻断卡片介绍一次；首次启动前半段不弹。

- 标题围绕用户当前动作，例如“导出更清晰的图纸”，不使用空泛的“让回忆继续成长”。
- 权益来自唯一产品配置，且必须是已经实现、可验证的能力。
- 价格、试用期和折扣全部读取 StoreKit，不在设计稿或代码硬编码。
- 必须提供恢复购买、自动续订说明、隐私政策、服务条款和关闭按钮。
- 不默认勾选、不制造虚假倒计时、不用未上线能力抬高价值。

### 6.11 WidgetKit 小组件

小组件是长期生命档案在桌面与锁屏上的轻量延伸，不是快捷功能宫格。首批只包含「相片回声」「纪念日」「档案年轮」和两枚锁屏组件；完整 family、空态、隐私态、数据快照、深链与刷新契约见 [`docs/WidgetKit-Design.md`](docs/WidgetKit-Design.md)。

Figma 视觉定稿位于 [`14 · WidgetKit · Life Archive Glances`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=371-691)：评审板 `371:693`，可复用组件源区 `371:694`。共 12 个命名组件，覆盖 7 个桌面尺寸、2 个锁屏尺寸与 empty/redacted/stale 三种韧性状态。

- 桌面组件沿用连续档案纸、照片出血、铜色登记轨与开放年轮，不在系统 Widget 圆角内部重复堆叠大圆角卡片或胶囊标签。
- 锁屏组件必须适配系统单色/强调色渲染，不能依赖品牌色表达选中、进度或含义。
- 照片、伙伴名和用户备注属于隐私敏感内容；redacted/placeholder 状态改用档案纸纹理、日期骨架和真实布局，不显示用户数据。
- 组件只读取本地 App Group 的有界投影与降采样缩略图，不直接打开主 App SwiftData store，不请求网络，不承诺云同步或 AI 内容。
- 点击只进入照片详情、伙伴档案、时间线或拼豆结果；编辑、删除、批量导入和购买继续在 App 内完成。

## 7. 导航、动效与触感

- Tab 切换使用系统行为，不给每次切换叠加自定义位移动画或触感。
- 照片打开优先使用系统 zoom transition；iOS 17 用 matched geometry 或普通 push/fade，不能为转场破坏导航状态。
- 关闭照片支持下滑仅作为补充，系统返回手势始终可用。
- Chip、收藏、选择可使用轻触感；扫描循环、滚动和 Tab 切换不触发触感。
- 成功触感只在导入、保存、导出真正完成后触发。
- 尊重 Reduce Motion：禁用视差、粒子、模糊揭示与大范围缩放；以淡入或即时更新替代。

动画 token：即时状态 120–160ms，页面局部变化 200–260ms，Hero 320–420ms。弹簧只用于直接操控的控件，不用于长列表自动跳动。

## 8. iPad 与多窗口策略

V1 的 iPad 目标不是把 iPhone 页面拉宽：

Figma 参考画板集中在 [13 · Adaptive Layout · iPad](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=306-669)：834×1194pt 只作为 portrait 验收基准，顶部预留 24pt、底部预留 20pt 系统安全区；SwiftUI 必须读取实时 safe area，不能硬编码这些参考值。档案页使用肖像/档案纸双栏；拼豆设置使用来源工作区/参数检查器；拼豆结果使用大画布/导出检查器，并提供同结构深色稿验证语义变量。

- 伙伴与设置采用 Sidebar + Detail。
- 相册采用可变列网格，详情可在右侧打开。
- 拼豆与编辑器采用 Canvas + Inspector。
- 主 Tab 在 portrait 可使用全宽贴底材质面内居中的 `Memory Orbit`；可用宽度不足或进入多窗口窄态时回到 compact 布局，不把 390pt 组件横向拉伸。
- Modal 表单限制最大宽度，不全屏铺开；键盘出现后主操作仍可见。
- 支持横竖屏、Split View 和 Stage Manager 的可变窗口宽度；以 size class 与实际宽度决策，不按设备型号判断。

## 9. 无障碍、隐私与本地化

- 最小触控区域 44×44pt；重要图标有可读 label，装饰图隐藏于 VoiceOver。
- PhotoTile 的 VoiceOver 顺序为“伙伴/日期/收藏/重复状态/选择状态”。照片备注可作为辅助描述，不能自动声称识别出具体伙伴。
- 支持 Dynamic Type 全区间、Bold Text、Increase Contrast、Differentiate Without Color、Reduce Transparency、Reduce Motion。
- 日期、数字、价格、复数与单位走 Formatter/String Catalog，不拼接固定中文顺序。
- 简中为源语言；英文布局至少预留 30% 文案增长，按钮不得依赖固定宽度。
- 全库访问前解释用途；Limited Photos 状态始终可见并提供管理入口。
- UI 不显示模型置信度假装确定性；AI 结论必须允许用户纠正。

参考基线：

- [Apple Human Interface Guidelines — Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Apple Human Interface Guidelines — Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Apple Human Interface Guidelines — Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)
- [WCAG 2.2 Contrast Minimum](https://www.w3.org/TR/WCAG22/#contrast-minimum)

## 10. 交付顺序

### Phase A — 体验骨架

1. 冻结真实能力与 Pro 权益矩阵。
2. 完成两条核心闭环和各自失败路径。
3. 建立低保真 iPhone/iPad 原型，先验证信息架构与任务完成率。

### Phase B — 设计系统

1. 更新动作色、高对比色和字体使用边界。
2. 完成十个核心组件及全部状态。
3. 建立真实伙伴照片测试集：浅/深、横/竖、单/多伙伴、低质量、无头像。

### Phase C — 页面视觉

按“引导 → 相册/确认 → 伙伴档案 → 首页 → 创作 → 我的/付费墙”顺序制作高保真稿。首页必须在真实档案数据可用后定稿，避免用假 Hero 掩盖数据规则缺失。

### Phase D — 实现与验收

每页完成组件映射、状态清单、埋点需求和验收截图后再进入 SwiftUI。先做 iPhone compact，再做 iPad，而不是最后补适配。

## 11. 设计验收门禁

一个页面只有同时满足下列条件才算“设计完成”：

- 主任务、次任务和退出路径明确，首屏没有同权重 CTA 竞争。
- Loading、Empty、Error、Permission Denied、Partial Data、Offline/Resource Missing 状态齐全。
- iPhone SE/标准 Pro/Pro Max 与 iPad portrait/landscape 有明确布局。
- 默认字号与最大辅助字号不截断关键内容。
- Light、Dark、Increase Contrast、Reduce Motion 有设计结果。
- 所有正文/按钮对比度达标，状态不只靠颜色表达。
- 页面文案不超出已实现能力或 V1 范围。
- 删除、覆盖、导入、保存、订阅均说明影响和可恢复性。
- 使用真实照片压力测试裁切、文字对比和网格密度。
- 产品、设计、iOS、QA 对同一验收稿签字，不以单张“看起来不错”的主状态图代替完整交付。
