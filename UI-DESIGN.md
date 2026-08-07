# MiLens iOS UI 设计规范

最后核对：2026-08-07（P1.1 主题 token 已落地，本规范指导后续视觉实现）

> 本文是 iOS 版视觉与交互的**唯一事实来源**。架构见 [DESIGN.md](DESIGN.md)，产品叙事与页面原型见 `docs/MiLens_iOS_V1.0_页面原型与交互流程设计稿.md`，迁移映射见 [MIGRATION_ASSESSMENT.md](MIGRATION_ASSESSMENT.md)，约束见 [AGENTS.md](AGENTS.md)。源端 HarmonyOS 主题 token（`baseColors.ets`/`themeColors.ets`/`AppTheme.ets`）仅作色值翻译参照，不照搬视觉风格。

---

## 0. 设计哲学

MiLens 不是工具，是宠物家庭的数字生命档案。UI 必须支撑「找回被遗忘的它，保存属于你们的一生」这句叙事。三条不可妥协的原则：

### 0.1 照片是主角，UI 是配角

源端用暖米背景（`#FEF6EE`）+ 暖棕文字（`#533422`），整体偏奶咖色——这在鸿蒙小屏上有亲和力，但**大量暖色背景会与宠物照片争抢注意力**。iOS 版反过来：界面退后，照片前进。中性背景 + 纯净卡片，让宠物照片成为屏幕上唯一的暖色源。

### 0.2 情感优先于功能堆砌

配合设计稿「正在寻找它的身影...」这种文案基调。首页不是功能面板，是时间剧场；档案不是列表，是数字传记。每一步交互传递「陪伴感」而非「操作感」。

### 0.3 克制与精致并存

对标 Things 3、Halide、Procreate、Bear。它们的共同点：留白慷慨、动效克制但精准、每个细节都打磨过。不用炫技动画，用「感觉对」的微交互。付费墙用户第一眼就决定值不值。

---

## 1. 色彩系统

### 1.1 设计决策：从「暖色铺底」转向「中性画廊 + 暖色点睛」

| 层级 | 源端值 | iOS 定稿 | 理由 |
|---|---|---|---|
| 背景浅 | `#FEF6EE` 暖米 | `#FAF8F5` 暖白（克制） | 退后一步，保留极淡温度，不与照片争暖 |
| 背景深 | `#1C1B2E` 紫调暗 | `#161311` 暖黑 | 深色保留品牌温度，不用冷紫（画廊逻辑） |
| 卡片浅 | `#FEFBF8` | `#FFFFFF` 纯白 | 干净卡片才能衬托照片 |
| 卡片深 | `#2A2940` | `#221E1A` 暖深灰 | 暖黑体系下的表面分层 |
| 文字主浅 | `#533422` 深棕 | `#1F1B18` 深暖黑 | 提高对比度与高级感 |
| 文字主深 | `#F0E8E0` | `#F2EBE3` 暖白 | 不刺眼，带温度 |
| 文字次 | `#BBA597` 暖灰 | `#6B625B`（浅）/ `#B5A89C`（深） | 降低暖度，更中性克制 |
| 品牌主色 | `#FD8663` 珊瑚 | **保留** `#FD8663` | 品牌资产，只在 CTA/选中态/品牌瞬间出现 |

**核心策略**：背景与文字推向中性，只让宠物照片和品牌色提供温暖。这是 Apple Photos、Journal app 的做法。

### 1.2 完整色值表（Asset Catalog colorset 名）

> 每个 colorset 在 `Assets.xcassets` 内配置 Any Appearance + Dark Appearance，业务层只引用语义名。

#### 表面 Surface

| 语义名 | 浅色 hex (RGB) | 深色 hex (RGB) | 用途 |
|---|---|---|---|
| `SurfaceBackground` | `#FAF8F5` (250,248,245) | `#161311` (22,19,17) | 页面底色 |
| `SurfaceCard` | `#FFFFFF` (255,255,255) | `#221E1A` (34,30,26) | 卡片/单元格背景 |
| `SurfaceElevated` | `#FFFFFF` (255,255,255) | `#2C2722` (44,39,34) | 悬浮元素/FAB/弹层 |
| `SurfaceGrouped` | `#F2EFEA` (242,239,234) | `#1C1916` (28,25,22) | 分组背景/输入框底 |

#### 文字 Text

| 语义名 | 浅色 (RGB) | 深色 (RGB) | 用途 |
|---|---|---|---|
| `TextPrimary` | `#1F1B18` (31,27,24) | `#F2EBE3` (242,235,227) | 标题/正文主色 |
| `TextSecondary` | `#6B625B` (107,98,91) | `#B5A89C` (181,168,156) | 说明/副标题 |
| `TextTertiary` | `#A89F97` (168,159,151) | `#7A6F64` (122,111,100) | 占位/时间戳/最弱信息 |
| `TextOnAccent` | `#FFFFFF` (255,255,255) | `#FFFFFF` (255,255,255) | 品牌色按钮上的文字 |

#### 品牌与强调 Accent

| 语义名 | 浅色 (RGB) | 深色 (RGB) | 用途 |
|---|---|---|---|
| `AccentColor` | `#FD8663` (253,134,99) | `#E8845F` (232,132,95) | 品牌 CTA/选中态/品牌瞬间 |
| `AccentSoft` | `#FDEEE6` (253,238,230) | `#3A241C` (58,36,28) | 品牌色浅底（选中卡片底/标签底） |
| `AccentGradientEnd` | `#FE8764` (254,135,100) | `#D9704A` (217,112,74) | 品牌渐变终点 |

#### 语义功能 Functional

| 语义名 | 浅色 (RGB) | 深色 (RGB) | 用途 |
|---|---|---|---|
| `Success` | `#4CAF7D` (76,175,125) | `#5BBF8A` (91,191,138) | 成功状态 |
| `Warning` | `#E8A33D` (232,163,61) | `#E8B454` (232,180,84) | 警告 |
| `Danger` | `#D9534F` (217,83,79) | `#E06863` (224,104,99) | 删除/错误 |
| `CatAccent` | `#FD8663` | `#E8845F` | 猫咪主题色（同品牌） |
| `DogAccent` | `#57A5E3` (87,165,227) | `#5B96D0` (91,150,208) | 狗狗主题色 |

#### 分隔与边界 Separator

| 语义名 | 浅色 (RGB) | 深色 (RGB) | 用途 |
|---|---|---|---|
| `Separator` | `#ECE7E1` (236,231,225) | `#2E2823` (46,40,35) | 分隔线/细分割 |
| `Border` | `#E5DFD8` (229,223,216) | `#383129` (56,49,41) | 卡片描边/输入框边 |

### 1.3 品牌色用法纪律

品牌色 `#FD8663` 是稀缺资源，**禁止滥用**。只允许出现在：

- ✅ 主 CTA 按钮（保存/导出/试用 Pro/建档）
- ✅ 选中态（筛选 chip 激活、Tab tint、单选选中）
- ✅ 品牌瞬间（首次启动 logo、付费墙标题强调、空态插画点缀）
- ✅ 进度条/加载关键节点
- ❌ 不用于正文文字、不用于普通图标、不用于大面积背景

源端把 `accentBg`（浅品牌底）铺在多处背景，iOS 版收敛——大面积背景一律中性，品牌色只做点睛。

### 1.4 与现有 token 的对应

当前 `Color+Theme.swift` 已定义 5 个语义色（P1.1）。需按上表**扩展并校准色值**：

- `milensPrimary` → `AccentColor`（色值不变，保留）
- `milensBackground` → `SurfaceBackground`（值从源端暖米改为 `#FAF8F5`）
- `milensCard` → `SurfaceCard`（值改为纯白）
- `milensTextPrimary` → `TextPrimary`（值改为 `#1F1B18`）
- `milensTextSecondary` → `TextSecondary`（值改为 `#6B625B`）
- **新增**：`TextTertiary`/`SurfaceElevated`/`SurfaceGrouped`/`AccentSoft`/`Separator`/`Border`/各功能色

> 落地步骤见 §9。

---

## 2. 字体系统

### 2.1 字体选型与许可

| 用途 | 字体 | 许可 | 说明 |
|---|---|---|---|
| 中文标题/情感文案 | **霞鹜文楷 LXGW WenKai** | SIL OFL 1.1（可商用、可嵌入 App） | 楷体手写感，带「档案/手札」温度，区别于所有用 PingFang 的工具 App |
| 英文 display 标题 | **Fraunces**（主选） | SIL OFL 1.1 | 可变字体，表现力强，与文楷温润感形成中西呼应；备选 Source Serif 4（更克制编辑感）、Newsreader（文学感） |
| 正文 / UI | SF Pro + PingFang SC（系统默认） | 系统自带 | 保持原生感，零体积成本 |
| 数字 / 统计 | SF Pro Rounded（`design: .rounded`） | 系统自带 | 「3280张」「3岁2个月」等数字用圆体更柔和 |

**为什么衬线**：MiLens 核心是「保存一生」。衬线体天然带「档案感、编辑感、时间感」。首页大标题用衬线「今天的小橘」，瞬间区别于工具类 App。

**字体许可合规要点**（AGENTS.md 边界）：
- 霞鹜文楷与 Fraunces 均 SIL OFL 1.1，可嵌入 App 分发，**禁止单独出售字体文件**。
- 制作衍生字体（如合并中英文）**禁用保留名称**「LXGW」「霞鹜」「Fraunces」；App 内需保留各字体的 `OFL.txt` 与来源说明（可放「关于」页）。
- App 字体声明走 Asset Catalog / Bundle 资源，不在代码中硬编码外部下载。

### 2.2 字体层级（Typography）

建议新增 `Typography.swift`，集中定义层级，`relativeTo` 适配 Dynamic Type：

| 层级 | 字体 | 字号 / 字重 | 用途示例 |
|---|---|---|---|
| `displayLarge` | 霞鹜文楷 / Fraunces | 34 / bold（`.largeTitle`） | 首页问候「晚上好」、档案名字 |
| `displayMedium` | 霞鹜文楷 / Fraunces | 24 / semibold（`.title2`） | 区块标题「它的故事」「一年前的今天」 |
| `titleStandard` | SF Pro + PingFang | 20 / semibold | 导航栏标题、卡片标题 |
| `bodyPrimary` | SF Pro + PingFang | 17 / regular | 正文 |
| `bodySecondary` | SF Pro + PingFang | 15 / regular | 说明文字 |
| `caption` | SF Pro + PingFang | 13 / regular | 时间戳、辅助信息 |
| `numberStat` | SF Pro Rounded | 22 / bold | 「3280」「3岁2个月」统计数字 |
| `buttonLabel` | SF Pro + PingFang | 17 / semibold | 按钮文字 |

```swift
// 示例：混合栈优先中文文楷，回退英文 Fraunces，最后系统
extension Font {
    static let displayLarge = Font.custom("LXGWWenKai-Bold", size: 34, relativeTo: .largeTitle)
    static let displayLargeEN = Font.custom("Fraunces-Bold", size: 34, relativeTo: .largeTitle)
    static let numberStat = Font.system(size: 22, weight: .bold, design: .rounded)
}
```

> 实操：中文文案用文楷栈，纯英文/数字混排时用 Fraunces/Rounded 栈。SwiftUI 不支持自动按字符切栈，需在文案处按语言约定选择。

### 2.3 字体体积控制（关键约束）

霞鹜文楷完整 TTF 约 **12MB+**，直接嵌入显著增加包体积。策略（按优先级）：

1. **子集化（首选）**：用 `pyftsubset`（fonttools）只保留 GB2312 常用 3755 字 + 标点 + 拉丁 + App 专用词，可压到 **2–3MB**。构建脚本纳入 `tools/`。
2. **屏幕版**：用 LXGW WenKai Screen（屏幕阅读优化版，字形适配 Retina），体积略小。
3. **按需加载（次选）**：iOS 16+ 支持 `CTFontDescriptor` 后台按需下载，但增加复杂度，V1.0 不建议。
4. **监测**：每次新增/更新字体后，在 PR 中报告 `.app` 体积变化；单 HAP/App target 不超目标阈值。

> 字体文件放 `Resources/Fonts/`，在 `Info.plist` 注册 `UIAppFonts`（XcodeGen 在 `project.yml` 声明），Asset Catalog 不管理字体。

---

## 3. 间距、圆角、深度

### 3.1 间距 Spacing

在现有 `Spacing` 基础上调整——付费 App 需更慷慨的左右内边距：

| token | 值 | 用途 |
|---|---|---|
| `xs` | 4 | 图标与文字微间距 |
| `sm` | 8 | 紧凑元素间距 |
| `md` | 12 | 列表行内间距 |
| `lg` | 16 | 卡片内边距 |
| `xl` | 20 | 元素组间距 |
| `xxl` | 24 | 区块间距 |
| **`pagePad`** | **24**（从 20 上调） | **页面统一左右内边距** |
| `pagePadCompact` | 16 | 横屏/紧凑宽度 |

### 3.2 圆角 Radius

建立三档清晰圆角（当前值基本可用，统一命名）：

| token | 值 | 用途 |
|---|---|---|
| `small` | 10 | chip / 小按钮 / tag |
| `medium` | 14 | 中等元素 / 输入框 / 次级卡片 |
| `large` | 20 | 大卡片 / hero 照片 / 主卡片 |
| `thumb` | 12 | 缩略图 |
| `pill` | `.infinity`（胶囊） | 筛选 chip / 主 CTA 大按钮 |

> hero 照片与大内容卡片统一 20pt，营造「画廊画框」感。

### 3.3 深度与分隔

**克制使用阴影**——这是付费 App 与业余 App 的分水岭：

- **默认不分层**：用表面色分层（`Background` → `Card` → `Elevated`）。
- **卡片**：不用阴影，用 `Border`（`Color("Border")`，0.5pt）或直接靠表面色差区分。
- **悬浮元素**（FAB、吸底操作栏、弹层）：才用柔和阴影。统一阴影 token：
  - `elevationSoft`：`color: .black.opacity(0.06), radius: 12, x: 0, y: 4`
  - `elevationMedium`：`color: .black.opacity(0.10), radius: 20, x: 0, y: 8`（FAB/弹层）
  - `elevationAccent`：`color: .milensPrimary.opacity(0.18), radius: 16, y: 6`（品牌色按钮，仅在需要强调时）

---

## 4. 动效与触感

iOS 差异化武器。动效服务于情感反馈，不炫技。

| 场景 | 动效 | 触感 Haptic |
|---|---|---|
| Tab 切换 | 内容淡入淡出 + 轻微位移 | `.light` |
| 照片点开 | hero animation 从网格放大到全屏 | 无 |
| 照片关闭 | 下滑手势缩小回网格位置 | `.light` |
| 长按照片 | context menu 弹出 + 缩放 | `.medium` |
| 拼豆生成完成 | 从模糊到清晰的揭示动画 | `.success` |
| 选中筛选 chip | 胶囊填充 + spring | `.soft` |
| 下拉刷新回忆 | 自定义拉拽动画 | `.rigid` |
| 付费成功 | 对勾绘制 + 粒子 | `.notification(.success)` |
| 建档完成 | 卡片上浮 + 品牌色脉冲 | `.notification(.success)` |

**动画时长 token**（沿用 `Motion`）：
- `fast` 0.15s（即时反馈：点击态、chip 切换）
- `normal` 0.25s（默认转场）
- `slow` 0.4s（hero、揭示）

照片 hero animation 是最值得打磨的微交互——用户每天触发几十次，是「精致感」的核心来源。

---

## 5. 关键页面规范

### 5.1 首页（hero 照片方案 —— 已确认）

**不要做成**「今日照片 + 回忆列表 + 快捷入口」的功能堆叠。做成随时间/内容变化的情感首屏：

```
┌─────────────────────────────┐
│  晚上好                      │ ← 按时段问候，displayLarge 衬线
│                              │
│  ┌────────────────────────┐  │
│  │                        │  │
│  │   [今日最佳宠物照片]    │  │ ← 全宽 hero 卡片，圆角 20
│  │   全出血，无文字遮挡    │  │   点击 hero 进入大图
│  │                        │  │
│  └────────────────────────┘  │
│  今天 · 小橘                  │ ← 极简标注，caption
│  ─────────────                │ ← 分段符，非卡片分组
│  一年前的今天                 │ ← displayMedium 衬线
│  ┌──────┐  ┌──────┐          │
│  │回忆1 │  │回忆2 │           │ ← 横滑卡片
│  └──────┘  └──────┘          │
│  ─────────────                │
│  [为它创作]                   │ ← 唯一 CTA，品牌色
└─────────────────────────────┘
```

要点：
- **hero 是情绪核心**：够大、出血、圆角 20、无文字遮挡；底部可加极淡渐变（透明 → 背景）增强深度。
- **时间线分段符**（`─────`）替代卡片分组，更安静。
- **快捷创作收敛成一个按钮**，不做 4 个并列入口（创作详情进 Tab 3）。
- **空态**：用插画 + 衬线引导文案，而非「暂无数据」。
- **hero 内容来源**：今日最新/最佳照片；无今日照片时回退到最近一张。

### 5.2 相册（杂志式网格）

- **对齐网格（V1.0 先做）**：LazyVGrid 等比方块，2/3 列自适应，照片间 2–3pt 极小间隙，营造连成一片的回忆感。
- **masonry（后续升级）**：照片按原比例展示，竖图高、横图宽，更有呼吸感。
- **按日期分组**：每天一个小标题（`8月7日 · 周三`），displayMedium 衬线。
- **筛选 chip**：顶部悬浮胶囊（全部/小橘/旺财），选中态品牌色填充 + `.soft` 触感。
- **长按 context menu**：收藏 / 创作拼豆 / 设为档案头像 / 删除。
- **hero 打开**：点按照片从网格位置放大到全屏 PhotoView（`matchedGeometryEffect` 或 `.navigationTransition(.zoom)` iOS 18+）。

### 5.3 宠物档案（数字传记）

分屏式传记页，非列表：

```
┌─────────────────────────────┐
│  ┌────────────────────────┐  │
│  │                        │  │
│  │  [宠物肖像大图]         │  │ ← 顶部 ~40% 高度，出血
│  │  渐变到底部             │  │
│  │      小橘               │  │ ← 名字浮在图上，displayLarge
│  │  3岁2个月 · 3280张      │  │   numberStat 数字
│  └────────────────────────┘  │
│  它的故事                    │ ← displayMedium
│  ┌────────────────────────┐  │
│  │ 2021 · 来到家           │  │ ← 时间线卡片，左竖线 + 圆点节点
│  │ [第一张照片缩略图]       │  │
│  ├────────────────────────┤  │
│  │ 2022 · 第一次生日       │  │
│  └────────────────────────┘  │
│  [全部照片] [创作作品]        │ ← 底部 segmented
└─────────────────────────────┘
```

要点：肖像区出血大图 + 底部渐变（透明 → `SurfaceBackground`），名字浮上；时间线用左侧竖线 + 圆点节点，像传记；每节点配代表照片，非纯文字。

### 5.4 创作 / 拼豆（工作室）

商业化核心，不做功能列表：

- **入口页**：大尺寸全宽卡片（每个创作类型一张），配示例效果图，displayMedium 标题。
- **拼豆流程**（工作室界面）：
  - 上半屏实时预览（照片 → 拼豆图纸）。
  - 下半屏参数控制（尺寸滑块、色板、抖动开关），参数变化实时渲染 + spring。
  - 渲染完成用 `.success` 触感 + 模糊到清晰揭示动画。
- **导出**：全屏预览 + 三按钮（保存到相册 / 分享 / 导出 A4 PDF）。

### 5.5 付费墙（情感化，非交易化）

设计稿原则「不要首次启动收费，在情感连接后出现」。UI 延续情感：

```
┌─────────────────────────────┐
│  让这份回忆继续成长          │ ← displayLarge 衬线，不写「升级 Pro」
│  ┌────────────────────────┐  │
│  │  MiLens Pro            │  │
│  │  ✓ 无限宠物档案         │  │
│  │  ✓ AI 成长视频          │  │
│  │  ✓ 高级创作模板         │  │
│  │  ✓ 高清导出             │  │
│  └────────────────────────┘  │
│  ¥38/月   ¥198/年(省46%)     │ ← 年费高亮（描边/更大），numberStat
│  [免费试用 7 天]             │ ← 品牌色大按钮，胶囊
│  随时取消 · 自动续订说明      │ ← caption，诚实写明（审核要求）
└─────────────────────────────┘
```

要点：标题用情感文案；价格用圆体数字；年费方案视觉更突出；底部诚实写续订条款（苹果审核要求）。

---

## 6. 深色模式（暖黑，已确认）

- 背景用**暖黑** `#161311`（R>G>B，偏黄/橙），不用冷紫或纯黑。保留品牌温度。
- 照片在暖黑背景上更「发光」——画廊逻辑。
- 首页 hero、档案肖像在暖黑下尤其惊艳。
- 衬线字体在暖黑背景上更有质感。
- **跟随系统**，不强制深色（宠物 App 偏温暖日常）。
- 所有色值已在 §1.2 给出 Dark Appearance，Asset Catalog 配 Any + Dark 双外观即可。

---

## 7. iOS 平台特性利用

这些是 iOS 用户判断「是不是个好 App」的暗线标准，按优先级：

| 特性 | 优先级 | 用途 |
|---|---|---|
| **hero transition**（`matchedGeometryEffect` / `.navigationTransition(.zoom)`） | P2 高 | 照片点开/关闭，精致感核心 |
| **Context Menu** | P2 高 | 照片/档案长按菜单，符合 iOS 肌肉记忆 |
| **Dynamic Type 全适配** | 全程 | 字体随系统放大，不能断版 |
| **SF Symbols** | 全程 | 图标用 SF Symbols 保持原生感 |
| **`.scrollTargetBehavior`**（iOS 17） | P2 中 | 相册滚动对齐，丝滑 |
| **Interactive Widget** | P5 中 | 桌面/锁屏「今日照片」「一年前的今天」 |
| **Live Activity / Dynamic Island** | P2 后期 | 扫描几千张照片时显示进度 |
| **TabView `.sidebarAdaptable`**（iOS 18+） | P5 | iPad 自适应 Sidebar |
| **TipKit** | P5 | 新功能系统级引导，不自造浮层 |

---

## 8. 与源端的关系（迁移约束）

- **不照搬视觉**：源端暖色铺底风格不迁移；只翻译色彩 token 的**语义**与必要品牌色值。
- **保留品牌**：`#FD8663` 品牌主色是跨平台品牌资产，iOS 保留，但降使用频率。
- **诚实标注**：沿用源端 AGENTS.md 原则——AI 推理、主体分割等能力如实呈现，UI 不得夸大（不把通用识别描述为自定义宠物语义模型）。
- **隐私一致**：UI 文案延续「照片不离开设备」「AI 分析本地完成」承诺（见设计稿 §Step 2）。

---

## 9. 落地路线

### 阶段 A：设计系统先行（P2 前，避免返工）

1. **校准 Asset Catalog**：按 §1.2 扩展 colorset（新增 `TextTertiary`/`SurfaceElevated`/`SurfaceGrouped`/`AccentSoft`/`Separator`/`Border`/功能色），更新 5 个已有 colorset 的色值。
2. **更新 `Color+Theme.swift`**：补全语义色扩展，校准色值。
3. **更新 `Theme.swift`**：`pagePad` → 24；圆角统一三档；新增 `Elevation` token。
4. **新增 `Typography.swift`**：定义 §2.2 字体层级。
5. **字体资源**：下载霞鹜文楷 + Fraunces（OFL），子集化后放 `Resources/Fonts/`，`project.yml` 注册 `UIAppFonts`，保留两份 `OFL.txt` 与来源说明。
6. **体积报告**：记录字体引入前后 App 体积。

### 阶段 B：随页面实现逐个打磨（P2–P5）

7. 相册（P2）：对齐网格 → hero transition → 后续升级 masonry。
8. 宠物档案（P3）：传记式时间线 + 出血肖像。
9. 拼豆（P4）：工作室实时预览 + 触感。
10. 首页 hero（P5）：重点打磨 hero 照片 + 衬线标题。
11. 付费墙（P5）：单独高质量设计。

### 暂缓

- masonry 瀑布流（复杂度高，先对齐网格）。
- Live Activity（需扫描流程稳定后再加）。
- 自定义 SF Symbols（先验证交互，再定制图标）。
- 字体按需加载（V1.0 子集化足够）。

---

## 10. 验证清单

每次视觉改动最小验证：

| 改动 | 验证 |
|---|---|
| 色值 / token | 浅色 + 暖黑深色双外观核对；对比度达 WCAG AA（文字 ≥ 4.5:1） |
| 字体 | Dynamic Type 最大字号不断版；字体体积记录 |
| 间距 / 圆角 | iPhone SE（最小）+ iPhone Pro Max（最大）+ iPad 关键尺寸 |
| 动效 / 触感 | 真机验证（模拟器无触感） |
| 深色模式 | 全页面暖黑外观人工检查 |
| hero / 照片 | 真机验证手势与转场（模拟器手势不准确） |

> UI 验证需 Mac + 模拟器/真机（见 [PLAN.md](PLAN.md) P5 备注）。Windows 端只能做 token / 代码层改动，视觉验收必须在 Mac 完成。
