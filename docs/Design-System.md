# MiLens Design System — Ledger 编辑式视觉语法

> 基于 Figma 12 页 Release Candidate 与 12 页 Image Workshop 扩展稿（2026-08-12）提炼的产品视觉语法与可复用组件库。
> 唯一事实来源为代码实现 + Figma `WnT7DCK1XCyPwnS38SE87p`；本文档为开发参考。

---

## 1. 核心设计原则

| 原则 | 说明 |
|---|---|
| 照片是主角 | 真实照片优先于插画/Emoji；大图出血建立情绪 |
| 时间即结构 | 竖线 rail + 日期标签 + 年份编号构成贯穿全 App 的"记忆标记"语言 |
| 珊瑚稀缺 | `ActionPrimary #BC4727` 只用于 CTA / 选中态 / 品牌瞬间，禁止铺底 |
| 编辑式诚实 | 编号（01/02）、虚线引导线、Fraunces 衬线数字来自纸质档案的视觉记忆 |
| 中性画廊留白 | 默认不用阴影，用表面色分层（Background → Card → Grouped）+ 0.5pt border |

---

## 2. 色彩系统

### 2.1 语义 token（`Color+Theme.swift` → Asset Catalog）

| Token | 浅色 | 深色 | 用途 |
|---|---|---|---|
| `milensBackground` | `#FAF8F5` | `#161311` | 页面背景 |
| `milensCard` | `#FFFFFF` | `#221E1A` | 白色信息卡片 / Sheet 底 |
| `milensGrouped` | `#F2EFEA` | `#1C1916` | 分组容器 / 输入框底 / Grouped 表单 |
| `milensElevated` | `#FFFFFF` | `#2C2722` | FAB / 弹层 |
| `milensTextPrimary` | `#1F1B18` | `#F2EBE3` | 标题 / 正文主色 |
| `milensTextSecondary` | `#6B625B` | `#B5A89C` | 副标题 / 说明 |
| `milensTextTertiary` | `#A89F97` | `#7A6F64` | 占位 / 时间戳 / 最弱 |
| `milensPrimary` | `#FD8663` | `#E8845F` | 纯装饰（记忆圆点 / 收藏心 / 品牌瞬间） |
| `milensActionPrimary` | `#BC4727` | `#E8845F` | **所有交互强调**（按钮 / tint / 选中） |
| `milensAccentSoft` | `#FDEEE6` | `#3A241C` | 选中卡片底 / 标签底 |
| `milensAccentWash` | `#FCE8DF` | `#3A241C` | 珊瑚浅粉 wash（文本记忆卡 / 隐私徽章） |
| `milensBorder` | `#E5DFD8` | `#383129` | 卡片描边 / 输入框边 |
| `milensSeparator` | `#ECE7E1` | `#2E2823` | 分隔线 |

### 2.2 专用表面 token

| Token | 浅色 | 深色 | 用途 |
|---|---|---|---|
| `milensStudioBackground` | `#0D0B0A` | — | 拼豆工作室 / 创作暗色背景 |
| `milensStudioSurface` | `#15130F` | — | 暗色场景下的卡片表面 |
| `milensProCardDark` | `#14110F` | `#2A2520` | Pro Hero Card 背景 |
| `milensProBody` | `#B5A89C` | — | Pro 卡辅文暖灰 |
| `milensHeroGradientEnd` | `#060606` | — | 出血 Hero 底部渐变终点 |
| `milensRedPacketRed` | `#D1291E` | — | 微信红包封面品牌红 |

### 2.3 编辑式 palette（`Color+Theme.swift` 内联常量）

| Token | 色值 | 用途 |
|---|---|---|
| `milensPaper` | `#F4EFE5` | 奶油纸张底（创作浅色卡 / 档案浅色容器） |
| `milensInk` | `#1B1612` | 暖深棕文字（暗色按钮文字 / 图标） |
| `milensCopper` | `#B04125` | 铜橙强调（编辑式数字 / chevron / 旧版强调色） |

### 2.4 使用纪律

- **禁止** `Color.red` / `.orange` / `.systemGray` 等系统语义色当视觉色
- **禁止** `Color(red:green:blue:)` 硬编码；业务动态色（拼豆调色板）行尾加 `// ui-token:ok` 豁免
- 所有色值必须走 `milens*` token；`check-ui-tokens.py` 守护 0 ERROR
- `milensPrimary`（#FD8663）**不得**用于白字背景（对比度 2.40:1 不达标）；交互强调一律 `milensActionPrimary`

---

## 3. 字体系统（`Typography.swift`）

### 3.1 三声线分工

| 声线 | 字体 | 用途 | 每屏用量 |
|---|---|---|---|
| 文楷 display | `LXGWWenKai-Regular` | 中文 Hero 标题 / 情感标题 | 每屏最多 1 个 |
| Fraunces 衬线 | `Fraunces-Bold/Semibold` | 英文 wordmark / 编号数字 / 日期内联 | 编号不限 |
| 系统原生 | SF Pro + PingFang | 正文 / UI 控件 / 说明 | 全部常规 |

### 3.2 层级 token

| Token | 字号 | 用途 |
|---|---|---|
| `displayLarge` / `editorialHero` | 34-40pt 文楷 | 首页问候 / 档案名字 |
| `displayMedium` / `editorialSection` | 24-28pt 文楷 | 区块标题 / 空态标题 |
| `titleStandard` | title3 semibold | 导航栏 / 卡片标题 |
| `bodyPrimary` / `bodySecondary` | body / subheadline | 正文 / 说明 |
| `caption` | caption | 时间戳 / 辅助 |
| `editorialNumber` | 34pt Fraunces | 编辑式统计数字 |
| `numberStat` | title2 rounded bold | 统计数字（圆体） |

### 3.3 纪律

- 文楷每屏**恰好一个**标题；其余用系统字体

### 3.4 Workshop 顶部栏契约

- Figma 样板：[`11 · Red Packet / Upload Guide` 422:845](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-845)。
- 390×844pt 参考稿：`Navigation / Back` 为 `x=18 / y=57 / 44×44pt`，24pt 返回矢量在圆内 `10pt` 居中并复用 `MiLens/Elevation/Floating`；标题为 `MiLens/UI/Title`、`color/text/primary`，起点 `x=72 / y=64`。
- 右侧动作使用现有 UI 控件字级和 `color/action/brand`，与标题垂直居中；撤销/重做等多动作从右向左排列，但不得挤压标题的可读宽度。
- `01 · Creation / Studio Index` 保留 Tab 根页品牌头，不强行套返回栏。SwiftUI 通过 safe area 与 toolbar placement 还原相对关系，不硬编码 Figma 的 47pt 顶部参考安全区。
- Fraunces 只用于纯英文（品牌名 / 编号 / 日期），中文标题不可用 Fraunces
- 非 zh-Hans locale 文楷自动回退系统衬线（Typography.swift `usesWenKai` 守卫）

---

## 4. 间距 / 圆角 / 深度（`Theme.swift`）

| Token | 值 | 用途 |
|---|---|---|
| `Spacing.xs/sm/md/lg/xl/xxl` | 4/8/12/16/20/24 | 统一间距 |
| `Spacing.pagePad` | 24 | 页面左右内边距 |
| `Radius.small/medium/large` | 10/14/20 | chip / 卡片 / hero |
| `Radius.thumb` | 12 | 缩略图 |
| `Elevation.soft/medium` | shadow 12/20 | 吸底操作栏 / FAB |
| `Motion.fast/normal/slow` | 0.15/0.25/0.40s | 动效三档 |

**纪律**：默认不用阴影，用表面色分层或 0.5pt border。只有悬浮元素（FAB / 吸底操作栏 / 弹层）才用 `Elevation`。

---

## 5. 可复用组件库

### 5.1 通用编辑式组件（`Components/ArchiveComponents.swift`）

| 组件 | 用途 | 关键参数 |
|---|---|---|
| `ArchiveMarker(label:)` | 6pt 珊瑚圆点 + 小标签（品牌记忆标记） | label: String |
| `ArchiveSectionHeader(title:supporting:)` | 区块标题（14pt Bold + 可选说明） | title / supporting? |
| `ArchivePrimaryButton(isLoading:action:label:)` | 全宽胶囊 CTA（ActionPrimary 底 + Loading 态） | isLoading / action |
| `ArchiveDivider()` | 0.5pt 分隔线（displayScale 适配） | — |
| `FilterChip(title:isSelected:count:action:)` | 筛选 chip（选中珊瑚底白字） | title / isSelected / count? |

### 5.2 设置页 Ledger 组件（`Components/SettingsLedger.swift`）

| 组件 | 用途 |
|---|---|
| `LedgerSection { content }` | 左侧珊瑚 rail（3pt）+ 右侧内容列 |
| `LedgerRow(index:label:trailing:)` | 编号 + 标签 + 虚线引导线 + 控件 |
| `LedgerDisclosureRow(index:label:trailingText:)` | 带 chevron 的展示行 |
| `DottedLeader()` | 弹性虚线引导线（1pt dash [1,5]） |
| `SettingsSectionLabel(title:)` | 12pt Medium 分组标题 |
| `ProHeroCard(isPro:action:)` | 暖黑 Pro 卡片（4px 圆角 + Fraunces + Accent Rule） |
| `PrivacyBadgeCard()` | 隐私徽章卡（wash + rail + 锁图标 + chevron） |
| `SettingsFooter()` | 居中页脚（无联网 / 无收集 / 无注册） |

### 5.3 拼豆工作室组件（`Views/Create/`）

| 组件 | 用途 |
|---|---|
| `BeadExampleVisual(path:)` | 像素化预览（CIPixellate） |
| `PetCardExampleVisual(path:)` | 宠物卡片预览（渐变 + 爪印） |
| Effect Proof Card | 非对称圆角效果选择卡片（暗色预览区 + Badge） |
| Studio Size Selector | 四段尺寸选择器（珊瑚选中段） |
| Darkroom Pulse Button | 暗房材质 CTA（珊瑚底 + 拨盘圆） |

### 5.4 图片编辑 / 创作扩展组件

以下为 Figma 交付契约；SwiftUI 应优先复用现有 `EditorView`、`EditorToolPanels`、`SharePreviewSheet` 和各创作页状态，不为还原画面复制第二套业务状态机。

| Figma 组件 | Node | SwiftUI 映射 | 设计约束 |
|---|---|---|---|
| `Navigation/Editor Group Dock` | `458:1145` | `EditorDockView` | `Active=Adjust/Smart/Decorate`；342×54pt 浅色连续导航面，三等分目标；中文标签固定 Noto Sans SC Medium 12pt、32pt 文本宽度，避免 Inter 回退裁字；选中项为深铜红图标、文字与 48×2pt 短刻度，未选项为 `color/text/secondary`；不使用暗色材质、悬浮胶囊或阴影 |
| `Navigation/Editor Tool Row` | `459:1158` | `EditorGroupToolRow` | `Group` 与 `Active` 分离；342×40pt 横向滚动。Adjust：裁剪/旋转/调色/翻转；Smart：主体抠图/智能消除/背景虚化；Decorate 只保留文字/贴纸/相框。选中 40×2pt 刻度与标签底边保持 5pt 间距；贴纸、相框等未实现项须由 catalog 与能力标志禁用或标为 Future |
| `Control/Workshop Value Rail` | `460:1133` | `EditorAdjustPanelView` / 文字字号 Slider | 342×36pt 连续值，`State=Default/Changed/Disabled`；调色页使用 342×85pt 纵向滚动视口、2pt 行间距且不显示右侧数字；代码保留 VoiceOver 调整与撤销历史 |
| `Picker/Decoration Asset Cell` | `552:1084` | `DecorationCatalog` 资源选择单元 | `State=Default/Selected/Locked`；60×56pt，实际贴纸/相框预览由实例内容提供。横向素材轨必须保留 Selected 与 Pro 锁定语义；catalog 为空时显示空态，不生成假资源 |
| `Picker/Photo Proof Cell` | `462:1164` | `GrowthComparePhotoPickerView` | `Selection` 与 `Role=None/Earlier/Recent` 分离；选中勾选和时间角色均不可只靠颜色 |
| `Control/Creation Template Tab` | `463:1149` | 宠物卡 / 名片模板选择轨 | `Index`、`Label` 独立覆写；Selected 用铜色底槽，Locked 触发真实 Pro 门控 |
| `Field/Keepsake Annotation Register` | `554:1086` | 伙伴卡 / 成长对比注释输入 | `State=Display/Editing`；342×44pt 原位编辑登记行，聚焦态使用深铜红短刻度和“完成”。代码使用单行 `TextField`，建议 36 个中文字符上限，空值回退模板句并写入作品草稿 |
| `Action/Creation Output Register` | `466:1171` | 创作页保存 / 分享与 `SharePreviewSheet` | `Default/Pressed/Loading/Disabled` 四态；只承担成品输出 |
| `Action/Editor Panel Register` | `466:1197` | 裁剪 / 文字 / 抠图面板动作 | `Default/Pressed/Loading/Disabled` 四态；只承担编辑面板的取消/确认 |

Workshop 组件修正规则（2026-08-13）：组件内图标均为 SF Symbols 语义对应的单体 SVG Vector Group，不使用散线拼接或零宽字符；强调色统一使用 `color/action/brand` 深铜红，`color/material/studio/copper` 退出页面与组件实例。03–06 在当前参数纸内常驻横向滚动 Tool Row，并把当前工具参数紧凑排在其下；Group Dock 常驻且保持 342×54pt，不得被 Inspector 挤压。390×844pt 参考稿的画布底到铜红线为 8pt，线底到二级标题顶为 9pt。页面、参数纸与 Group Dock 均使用 `color/surface/canvas`；02、07–11 同时把实际回退填充校正为 `#FAF8F5`，避免只绑定变量却仍渲染纯白。Action、参数面板与 Group Dock 必须作为无重叠的纵向层，不能嵌入会裁切它们的容器。

最终精修规则（2026-08-13）：05/05A/05B 的图层标题行不并列说明文案，只保留标题和 28×28pt 图标动作；02 的双时态交换矢量精确位于两张校样中心；12 的 AirDrop、微信、信息和更多图标使用 24×24pt 可编辑 Vector Group，并分别绑定 `color/text/primary` 或 `color/text/on-action`，禁止使用单字或符号占位。

装饰操作态（2026-08-13）：[`05A · Sticker` 555:1075](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=555-1075) 在画布内显示可拖动、双指缩放/旋转和删除的选中贴纸图层，面板使用横向分类轨与横向素材轨；[`05B · Frame` 558:1152](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=558-1152) 使用整画布相框图层、比例自动适配、移除动作和相框缩略图轨。两者复用 `Decoration Asset Cell`，不新建普通大圆角卡片，也不包含“留白”“签名”入口。当前 `catalog.json` 为空，设计交付不等于功能与正式资产已交付。

创作页面只共用来源身份、模板轨与输出动作；成品本体保持不同几何：宠物卡为 4:5 纸样、成长对比为双时态长图、名片为横向信息层、红包为 957×1278 竖版及四场景预览。07/08 的作品注释复用同一登记行组件，但预览文字必须绑定各自作品草稿，不能只改静态文案。禁止把四类成品塞回同一种大圆角卡片。

### 5.5 其他共享组件

| 组件 | 文件 | 用途 |
|---|---|---|
| `StateView` | `Components/StateView.swift` | 统一空/错/权限/离线四态 |
| `MemoryOrbitTabBar` | `Components/MemoryOrbitTabBar.swift` | 底部导航（4 Tab + 轨道） |
| `ThumbnailImage(path:)` | `Views/Gallery/GalleryView.swift` | 本地文件缩略图异步加载 |
| `SharePreviewSheet` | `Components/SharePreviewSheet.swift` | 导出分享预览面板 |
| `ExportToast` | `Components/ExportToast.swift` | 导出成功 Toast |

---

## 6. 贯穿全 App 的视觉语法

### 6.1 竖线 Rail（记忆标记语言）

全 App 用**珊瑚竖线**作为分组锚点和时间轴标记：

- **3pt rail**：设置 LedgerSection / 隐私徽章 / Evidence Register
- **4pt rail**：宠物档案置顶记忆 / 首页即将到来的日子
- **2pt rail**：付费墙权益列表
- **1pt rail**：时间线主轴 / 年份选择器 baseline

### 6.2 编号系统

Fraunces Bold 编号用于行序标识（来自纸质档案的视觉记忆）：

- `01` `02` `03` `04`：设置页偏好 / 支持行
- `2026`：时间线年份 / 年份选择器
- `A6` `C2`：拼豆色板色号

### 6.3 拨盘式 CTA

暗底场景（照片详情 / 添加记忆）使用统一拨盘式按钮：
- 全宽珊瑚底（`ActionPrimary`）+ 12px 圆角
- 左侧 `#F1D8CA` 文字
- 右侧暗色拨盘圆（`#7C3F30` 底 + `#F1D8CA` 描边 + 图标）

### 6.4 Identity Strip

来源照片 / 方案摘要的统一容器（非对称圆角 `8px 0 18px 8px`）：
- 左侧珊瑚 Registration Rail（3pt）
- 缩略图（非对称圆角 `4px 10px 4px 10px`）
- 标签 + Meta + Action（含 baseline 短线）

### 6.5 效果 Proof 卡片

拼豆效果选择的统一卡片风格（非对称圆角 `8px 18px 8px 18px`）：
- 暗色预览区（88×44 `#100F0E` 底 + 10px 圆角）
- 选中态：浅粉底 + 珊瑚描边 1.5pt + Proof Index（22×2 珊瑚短线）
- Badge：珊瑚底白字胶囊

---

## 7. 守护工具

| 工具 | 命令 | 检查内容 |
|---|---|---|
| `check-ui-tokens.py` | `python tools/check-ui-tokens.py` | 硬编码色值（ERROR）+ 硬编码字号（INFO） |

当前状态：**144 文件 / 0 ERROR / 272 INFO**（INFO 为渐进收敛项）。
