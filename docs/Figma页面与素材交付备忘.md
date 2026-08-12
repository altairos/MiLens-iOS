# MiLens Figma 页面与素材交付备忘

> 核对日期：2026-08-13（12 张 Release Candidate 定稿、12 张 Image Workshop 主页面 + 4 张操作态、12 组核心组件 + 9 组创作扩展组件、iPad 自适应与字号/安全区审计）
> 用途：作为 Figma 高保真设计、页面拆帧、视觉素材制作和 iOS 交付排期的工作清单。  
> 事实来源：当前 SwiftUI 路由与页面代码、`UI-DESIGN.md`、`DESIGN.md`、`PLAN.md`、ADR-0008/0010。  
> 状态口径：**已有** = 当前代码已有可运行页面或交互骨架；**待打磨** = 页面/能力存在，但还需要高保真视觉和完整状态设计；**待交付** = 只有规划、协议或算法接口，尚未形成可用页面/素材。

> Figma 框架进度（2026-08-13）：连接文件已收敛到 `MiLens V1 · Product Screens` 页面，以编号 Section 管理主页面、Applied、Core Flow、探索稿和 Design System。`Release Candidate · FINAL` 已按 `01–12` 收齐首页、伙伴档案、时间线、图库、创作、Paywall、我的、照片详情、添加记忆、拼豆结果、拼豆设置与拼豆生成。`11 · Design System · Foundations` / `12 · Design System · Components` 已建立；主行动、底部导航、偏好行、拼豆控件、档案面板、档案读数和身份条共 12 组核心组件已定稿。`13 · Adaptive Layout · iPad` 已补核心双栏；`14 · WidgetKit` 已交付小组件设计；[`15 · Image Workshop · Editing & Keepsakes` 422:801](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-801) 现含 12 张图片编辑/创作主页面、贴纸/相框操作态、07/08 注释编辑态与 9 组扩展组件。新增状态均保持组件连接；当前仍缺完整异常状态、深色/iPad 扩展稿和逐页 SwiftUI 视觉回写，不等同于 iOS 已交付。

> 2026-08-12 视觉定稿节点：[08 · Applied Refinement · Micro Grammar](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=140-292) 与 [09 · Core Flow · Precision Continuity](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=211-240)。功能代码落地以这两个节点和 [UI-DESIGN.md §5.4–§5.5](../UI-DESIGN.md#54-底部主导航memory-orbit) 为准；横向主行动采用 `Focus Dial`（加入/保存记忆）、`Contact Proof`（仅照片扫描/导入）和 `Darkroom Pulse`（拼豆生成/高清导出）三种语义变体，不再参考旧的 `Archive Spine Action`、悬浮 Tab、全圆胶囊、缺角主按钮、装订点、手绘装饰线或文本化 Core Flow 探索稿。

> 主行动取舍与备选稿保留在 [Primary Action Studies](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=222-272)；最终五个实例均位于 Core Flow 节点。既有主页面没有需要强行套用横向主按钮的入口，时间线圆形新增记忆按钮及其他快捷动作继续使用各自的紧凑控件语法。

> 可复用组件节点：[`Action/Focus Dial` 259:344](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=259-344)、[`Action/Contact Proof` 262:314](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=262-314)、[`Action/Darkroom Pulse` 263:368](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=263-368)、[`Navigation/Memory Orbit` 272:582](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=272-582)、[`Control/Preference Row` 275:522](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=275-522)、[`Control/Studio Effect Proof` 309:777](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=309-777)、[`Control/Studio Size Selector` 285:597](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=285-597)、[`Control/Studio View Mode` 286:564](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=286-564)、[`Control/Studio Range` 287:574](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=287-574)、[`Data/Archive Stat` 295:587](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=295-587)、[`Surface/Archive Panel` 296:629](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=296-629)、[`Surface/Identity Strip` 299:615](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=299-615)。iPad 参考画板见 [`13 · Adaptive Layout · iPad` 306:669](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=306-669)；组件变体、尺寸 token、动效和 SwiftUI 映射以 [UI-DESIGN.md §5.6](../UI-DESIGN.md#56-figma-可复用组件契约2026-08-12) 为唯一说明。

> 重点精修节点：[`Paywall` 58:25](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=58-25)、[`Bead Studio / Generating` 91:366](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=91-366)、[`Core Flow Precision / Add Memory` 211:340](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=211-340)，对应深色节点为 `79:712`、`84:365`、`79:380`。本轮审计 Release Candidate、Dark Mode、iPad、Foundations 与 Components 共 743 个文本节点，全部不小于 10pt，正文/交互文字不小于 11pt；最终 12 张主稿的 224 个文本节点无缺失字体、禁用字体、截断或越界，顶部 47pt、底部 34pt iPhone 参考安全区与 44×44pt 顶部操作控件已校正，四个 `Memory Orbit` 实例的命中区域止于 `y=810pt`。详细规则见 [UI-DESIGN.md §4.1 与 §5.7](../UI-DESIGN.md#57-重点流程精修与字号验收2026-08-12)。

## 1. 先记住的边界

- Figma 的执行规格以 [`UI-DESIGN.md`](../UI-DESIGN.md) 为准；旧版页面原型只保留叙事背景，不再作为布局和能力承诺依据。
- V1 的一级导航只有四个 Tab：**首页、伙伴、创作、我的**。相册、照片详情、编辑器、时间线和创作流程是二级页面，不新增 Tab。
- V1 创作首页只展示目前能真实完成的五项：**拼豆图纸、伙伴卡片、成长对比、宠物名片、红包封面**。AI 写真、回忆视频、商城、社区、账号和手表不应进入 V1 Figma 主流程。
- 设计稿不能只交一张“正常状态图”。每个页面至少要覆盖：Loading、Empty、Error、Permission Denied、Partial Data、Offline/Resource Missing；适用时还要有 Selected、Pressed、Disabled、Paywall、Dark Mode、High Contrast、Dynamic Type 和 iPad 版。
- 当前仓库的 `Assets.xcassets` 主要是颜色 token 和 App Icon，已有两套字体（霞鹜文楷、Fraunces）；**品牌插画、伙伴示例图、装饰素材、相框、贴纸、相簿皮肤目前都没有作为正式资源交付**。

## 2. Figma 文件建议结构

建议按下面的 Page 建立文件，便于逐页精修和交接：

1. `00 · Cover & Status`：版本、范围、状态图例、变更记录。
2. `01 · Foundations`：颜色、字体、间距、圆角、图标、按钮、表面、照片裁切规则。
3. `02 · Components`：PhotoTile、记忆标记、FilterChip、状态页、底部操作栏、分享预览、Pro 标记等。
4. `03 · Onboarding`：首次启动四步及全部中断/权限状态。
5. `04 · Home`：首页及首页分支状态。
6. `05 · Gallery & Photo`：相册、扫描、确认导入、照片详情、编辑器。
7. `06 · Pets & Timeline`：伙伴列表、档案、编辑档案、时间线、时间线导出。
8. `07 · Create`：创作首页、拼豆、伙伴卡片、成长对比、宠物名片、红包封面与分享/导出流程。
9. `08 · Settings & Pro`：我的、隐私、通知、外观、帮助、关于、付费墙。
10. `09 · Future Assets`：月度精选、年度回忆册、相簿皮肤、相框、贴纸、打印等待交付能力，统一标注 `FUTURE / NOT V1 READY`。
11. `10 · Prototype Map`：关键用户路径、页面跳转、弹层和返回关系。
12. `11 · Export & Handoff`：App Store 截图、App Icon、导出规格、资源命名和开发标注。

## 3. 页面总览

| 编号 | 页面/流程 | 当前代码状态 | Figma 交付优先级 |
|---|---|---|---|
| O-01–04 | 首次启动：欢迎、照片权限、扫描、创建档案 | 已有 | P0 |
| T-01 | 四 Tab 根壳与导航状态 | 已有 | P0 |
| H-01 | 首页 Home | 已有，需按真实数据分支打磨 | P0 |
| G-01–04 | 相册：网格、筛选/选择、扫描进度、导入确认 | 已有骨架，部分状态需补稿 | P0 |
| P-01–04 | 伙伴列表、档案、编辑档案、添加伙伴 | 已有 | P0 |
| TL-01–02 | 成长时间线、时间线导出/分享 | 已有时间线，导出链路需核验 | P1 |
| PH-01 | 照片大图详情 | 已有 | P0 |
| E-01–06 | 图片编辑器及裁切/调整/文字/抠图/旋转翻转 | 已实现；Figma 四个关键工具态已交付 | P0 ✅ |
| C-01–03 | 五项目创作首页、空态、作品入口 | 已有；Figma 完整索引已交付 | P0 ✅ |
| B-01–04 | 拼豆选图、设置、工作室、结果导出/分享 | 已有 | P0 |
| PC-01–04 | 伙伴卡片选图、多模板、预览、分享/导出 | 主流程已实现；Figma 创作页、注释显示/编辑态与输出页已交付，注释业务状态待代码落地 | P0 ✅ / 注释待实现 |
| GC-01–02 | 成长对比双选、预览、保存/分享 | 主流程已实现；Figma 注释显示/编辑态已交付，注释业务状态待代码落地 | P0 ✅ / 注释待实现 |
| BC-01 | 宠物名片模板、信息编辑、草稿/分享 | 已实现；Figma 已交付 | P0 ✅ |
| RP-01–02 | 红包封面、四场景预览、上传指引 | 已实现；Figma 已交付 | P0 ✅ |
| S-01–07 | 我的、Pro、隐私、通知、外观、帮助、关于 | 已有 | P0 |
| R-01 | 数据库恢复/本地数据无法加载 | 已有恢复页 | P1 |
| M-01–04 | 纪念卡、月度精选、年度回忆册、相簿模式 | 规划/接口预留 | FUTURE |
| D-01–02 | 编辑器相框、贴纸资源选择器 | Figma 操作态与复用资源单元已交付；代码只有类型/目录接口，正式 catalog 与素材仍为空 | FUTURE / 设计已交付 |
| PR-01 | 实体打印产品选择/报价/订单 | 只有服务接口 | FUTURE |

---

## 4. 逐页 Figma 清单

### 4.1 首次启动 Onboarding（First Archive）

对应代码：`MiLens/Views/Onboarding/`、`OnboardingViewModel`、`MiLens/Components/OnboardingEditorial.swift`。
对照 Figma node 47:2「Onboarding · First Launch」11 画板（2026-08-12 重构）。

**流程（10 step / 4 大阶段）**：欢迎(空态→隐私摘要) → 建立档案 → 特征注册(选图→处理→完成) → 全面扫描 → 候选确认 → 导入中 → 导入成功。顺序关键变更：先建档→特征注册→再扫描（让扫描有特征基准可比对）。

| Frame | 画板 | 对应代码 |
|---|---|---|
| #47:6 | 01 欢迎 / 空态（Hero + Empty Archive + Waypoint + 隐私行） | `OnboardingWelcomeStep` |
| #47:7 | 01 欢迎 / 隐私摘要（On Device + Rules 3 行） | `OnboardingPrivacyStep` |
| #47:10 | 02 建立档案（Empty Identity + 名字 + species chips + Honest Note） | `OnboardingCreateArchiveStep` |
| #47:8 | 03 特征注册 / 说明与选图（Contact Sheet + Guidance） | `OnboardingFeatureRegisterStep` featureIntro |
| #47:11 | 03 特征注册 / 已选 N 张（Photo Grid + Ready Note） | `OnboardingFeatureRegisterStep` featureIntro |
| #117:50 | 03 特征注册 / 本机处理（Lens + Progress Track + Stages） | `OnboardingFeatureRegisterStep` featureProcessing |
| #117:100 | 03 特征注册 / 基准已建立（Feature Seal + Next） | `OnboardingFeatureRegisterStep` featureDone |
| #47:9 | 04 全面扫描（Viewfinder 扫描线 + Candidate Ledger） | `OnboardingFullScanStep` |
| #123:74 | 04 候选确认（Evidence Register 网格 + Tabs） | `OnboardingCandidatesStep` |
| #123:161 | 04 导入中（Lens + Stages） | `OnboardingImportStep` importing |
| #123:198 | 04 导入成功（Archive Entry + Local Archive Proof） | `OnboardingImportStep` success |

**共享组件（`OnboardingEditorial.swift`）**：`FocusDialButton`（机械拨盘式主 CTA，SwiftUI 近似还原）/ `ContactProofButton`（相册入口次级 CTA）/ `EditorialSection`（overline + 文楷标题 + 正文）/ `EditorialCard`（铜色竖 rail + 描边容器）/ `RegisterMark`（lead 浅灰 + tail 铜色 + 珊瑚端点）/ `WaypointRow`。

#### 像素级复刻核查记录（2026-08-12）

**已对齐 Figma 精确数值的项**：
- 背景色 #FAF8F5、卡片白底、描边 #E5DFD8、分隔线 #ECE7E1 → 均走语义 token（milensBackground/milensCard/milensBorder/milensSeparator）
- overline caption 12pt #6B625B、文楷 Hero 40pt、文楷 Section 28pt、Title 20pt Medium、Body 16pt → 字号/字色对齐
- Register 标记三段色：lead #E5DFD8（milensBorder）/ tail #7C3F30（milensDialSurface）/ marker #BC4727（milensActionPrimary）——已修正初始实现色值反转问题
- EditorialCard 竖 rail #7C3F30（milensDialSurface，对照 Spine #94:28）
- 阶段编号「01–04」Fraunces Bold 28pt（对照 style_c7adb578）
- Focus Dial：58pt 高、54pt 拨盘、surface #BC4727、拨盘 #7C3F30、文字 #F1D8CA、disabled opacity 0.36
- Brand Orbit 实线 2px #7C3F30（已从 dash:[1] 修正为实线）；Brand Seal 圆角 30（接近 Figma 60 的圆形效果）

**已知偏差（非逐像素，需 Mac 真机/Preview 验证后微调）**：
- Focus Dial 机械拨盘的精密刻度弧为 SwiftUI Circle.trim 近似（三段不同 opacity），非 Figma 原始 SVG 路径几何——视觉接近但不完全一致
- 各画板内间距/padding 用语义 Spacing token（pagePad=24/lg=16 等）近似 Figma 绝对坐标，整体节奏一致但局部可能有 ±2pt 偏差
- 候选网格卡片宽度走 LazyVGrid 自适应（3 列 flexible），Figma 固定 110pt 宽 + 8pt gap——在不同屏宽下等比缩放，iPhone 15（390pt）下接近一致
- FocusDialButton overlay 描边用 milensDarkroomText.opacity(0.25)，Figma 是 milensDarkroomText (#F1D8CA) 作为 Brand outline stroke 1px——视觉一致
- 隐私政策行用 SwiftUI Toggle + 手势实现，Figma 是纯 Button 行（rail + 文字 + →）——语义一致，视觉细节略有差异
- 导入中/成功页的 Archive Entry Card 照片区用纯色占位（Figma 是真实归档照片）——需真机首次导入后填充

**结论**：整体视觉语言（编辑式排版、铜色/珊瑚色系、文楷标题、Rail/Register/Focus Dial 语法）已完整还原；Focus Dial 为近似还原（非 SVG 资产）；局部间距/圆角可能需 Mac Preview 对照微调。严格意义上**不是逐像素级复刻**，属于「高保真近似」。要达到像素级，建议后续由设计师导出 Focus Dial 的 SVG/PDF 资产嵌入，并逐画板在 Xcode Preview 中叠 Figma 截图核对。

### 4.2 根壳与首页

对应代码：`RootTabView`、`AppTab`、`HomeView`、`HomeViewModel`。

| Frame | 必须制作的画面 |
|---|---|
| T-01 四 Tab | 首页/伙伴/创作/我的选中与未选中；导航栏标题；iPhone；iPad Sidebar/Detail 变体；深色模式 |
| H-01 有今日照片 | 问候/日期；一张主回忆 Hero；照片外的日期和伙伴归属；往年今日或纪念日；唯一主动作“去创作” |
| H-02 无今日照片 | 回退到最近照片；真实拍摄日期；无照片时进入相册的动作 |
| H-03 临近纪念日 | 纪念内容提升；生日/领养日文案；生成纪念卡片 CTA（若该能力尚未上线，稿中标注 Future，不放进 V1 主原型） |
| H-04 多位伙伴 | Hero 及回忆内容包含伙伴归属；进入对应档案 |
| H-05 空态/失败 | 没有照片、无档案、权限不足、读取失败、离线资源缺失 |

### 4.3 相册与扫描确认

对应代码：`GalleryView`、`GalleryViewModel`、`ScanService`、`ImportService`。

| Frame | 必须制作的画面 |
|---|---|
| G-01 相册内容 | 连续照片网格；照片质量标记；重复分组标记；收藏；伙伴筛选；待整理筛选；工具栏扫描入口 |
| G-02 相册空态 | 还没有照片；扫描系统相册；手动选择照片；Limited Photos 提示 |
| G-03 多选 | 选中态；全选/取消；吸底操作栏：归档到伙伴、收藏、删除；删除二次确认并说明只处理 App 沙盒副本 |
| G-04 扫描工具页 | 扫描中、暂停、取消、完成、失败、可恢复；“可能含伙伴”而不是确定识别文案 |
| G-05 导入确认 | 候选照片预览；选择伙伴/新建档案；导入中；导入完成；配额超限/Pro 付费墙 |
| G-06 质量与重复 | 低质量提醒；重复组展开/收起；保留最佳；部分分析失败；重新分析 |

### 4.4 伙伴列表、档案和编辑

对应代码：`PetsView`、`PetProfileView`、`PetEditView`、`AddPetSheet`。

| Frame | 必须制作的画面 |
|---|---|
| P-01 伙伴列表 | 有档案；头像/肖像；照片数；最近更新；进入档案；新增伙伴；空态；加载/失败 |
| P-02 伙伴档案 | 肖像 Hero；名字、物种（喵星人/汪星人/其他）、生日、领养日；照片分组；成长时间线入口；编辑入口；创作入口 |
| P-03 档案照片 | 全部/已编辑/未归属筛选；照片网格；照片详情；空筛选结果 |
| P-04 编辑档案 | 名字、物种、生日、领养日、备注/肖像；保存中；校验失败；删除档案二次确认；纪念提醒联动说明 |
| P-05 添加伙伴 | Sheet/页面形式；字段为空、保存、取消、保存失败 |

### 4.5 时间线与纪念结构

对应代码：`TimelineView`、`TimelineViewModel`、`TimelineExportCanvas`、`TimelineExportLogic`。

| Frame | 必须制作的画面 |
|---|---|
| TL-01 时间线 | 按年月分组；生日/领养日/照片事件；伙伴筛选；时间线为空；无事件；大字号改用 Menu |
| TL-02 事件详情 | 事件照片、日期、备注；照片进入大图；编辑档案入口 |
| TL-03 导出预览 | 长图/时间线预览；生成中；取消；失败；标准导出水印；Pro 高清无水印；系统分享 |

### 4.6 照片大图与编辑器

对应代码：`PhotoViewView`、`EditorView`、`EditorToolPanels`、`EditorCanvasView`。

| Frame | 必须制作的画面 |
|---|---|
| PH-01 大图 | 沉浸式照片；缩放/拖拽；返回；编辑；分享；照片元数据/伙伴归属；加载/文件缺失 |
| PH-02 照片操作 | 编辑、导出、分享、归档/删除；删除确认；编辑保存失败 |
| E-01 编辑器默认 | 黑色沉浸画布；原图；底部工具栏；撤销/重做；保存；未保存退出确认 |
| E-02 裁切/旋转 | 比例选择；自由裁切；左旋/右旋；水平/垂直翻转；拖动中/完成 |
| E-03 调整 | 亮度、对比度、饱和度、色温、锐化滑杆；重置；滑动中/已修改 |
| E-04 文字 | 输入；字号；颜色预设；描边；添加到图片；选中文字图层；删除图层 |
| E-05 抠图 | 空闲、识别中、成功、失败、重试；透明背景提示 |
| E-06 编辑结果 | 保存中、保存成功、保存失败、文件缺失；回到照片详情 |
| E-07 Future 装饰工具 | 贴纸：选中图层、拖动、双指缩放/旋转、删除、横向分类与素材轨；相框：整画布图层、比例自动适配、移除、横向分类与缩略图轨。稿件作为实现规格，代码开放仍受 catalog/feature flag 控制 |

当前高保真节点：[`Adjust` 422:813](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-813)、[`Crop` 422:817](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-817)、[`Text` 422:821](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-821)、[`Cutout` 422:825](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-825)、[`Sticker` 555:1075](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=555-1075)、[`Frame` 558:1152](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=558-1152)。Decorate 组只保留文字/贴纸/相框，不包含“留白”“签名”。03–06 基础态与 05A/05B 操作态共用 342×40pt 横向滚动二级工具轨；贴纸/相框虽已有可执行的设计规格，仍属于 Future 代码能力，不得在 catalog 为空时伪装为可用。保存/分享统一进入 `Output / Share Preview`，不额外伪造一级工具。

### 4.7 创作与拼豆

对应代码：`CreateView`、`BeadPhotoPickerView`、`BeadSettingsPanelView`、`BeadPatternView`、`BeadPatternResultView`、`GrowthCompareView`、`BusinessCardView`、`RedPacketCoverView`。

| Frame | 必须制作的画面 |
|---|---|
| C-01 创作首页 | “让照片继续有去处”叙事；五个真实项目入口；不同项目使用不同成品几何，不做等权卡片宫格；没有照片时去相册 |
| B-01 选照片 | 照片网格；选中；无照片；筛选/取消；进入设置 |
| B-02 拼豆设置 | 画布/网格尺寸；色板；风格/细节；主体保护；免费次数/Pro 状态；生成按钮；参数错误 |
| B-03 生成中 | 进度；取消；资源/模型缺失；失败重试 |
| B-04 拼豆工作室 | 图纸预览；缩放；色板与材料清单；质量评分；重新生成；导出/分享 |
| B-05 导出 | PNG/A4/PDF；标准带水印；Pro 高清无水印；系统分享；保存失败/取消 |

### 4.8 伙伴卡片

对应代码：`PetCardPhotoPickerView`、`PetCardView`、`PetCardTemplate`、`PetCardLogic`、`SharePreviewSheet`。

| Frame | 必须制作的画面 |
|---|---|
| PC-01 选照片 | 照片选择；伙伴信息预览；无照片；取消/确认 |
| PC-02 默认卡片 | 4:5 竖版；照片；名字；领养纪念日/来到家 N 天；一行注释预览与编辑入口；底部渐变；MiLens 水印；节点 [`422:829`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-829) |
| PC-02A 注释编辑 | 在成品上下文中原位聚焦单行输入；36 个中文字符上限；完成/空值回退；预览和导出共用同一草稿状态；节点 [`563:1149`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=563-1149) |
| PC-03 模板选择 | 经典、拍立得、杂志、极简四模板缩略图；免费/Pro 标记；选中态；锁定态；模板缺资源 |
| PC-04 分享预览 | 卡片预览；保存到照片；系统分享；免费水印；Pro 无水印高清；购买/恢复购买 |
| PC-05 Future 纪念卡 | 生日、领养日、100/365/730/1000 天里程碑；仅作为下一阶段稿件，和当前单模板卡片分开 |

### 4.9 成长对比、宠物名片与红包封面

| Frame | 必须制作的画面 |
|---|---|
| GC-01 双照片选择 | A/B 早期与近期照片；日期；交换；图库选择；清空/继续；节点 [`422:809`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-809) |
| GC-02 成长对比 | 上下双图；真实日期；自动时间差；宠物名字；一行注释预览与编辑入口；保存/分享；节点 [`422:833`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-833) |
| GC-02A 注释编辑 | 在成长对比成品上下文中原位聚焦输入；36 个中文字符上限；完成/空值回退；节点 [`563:1217`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=563-1217) |
| BC-01 宠物名片 | 档案头像；横向名片；standard/elegant/playful/minimal；简介、主人称呼、标签；草稿/分享；节点 [`422:837`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-837) |
| RP-01 红包封面 | 957×1278 固定规格；封面标题；拆红包/发送/气泡/详情四场景；免费水印与 Pro 锁；节点 [`422:841`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-841) |
| RP-02 上传指引 | 导出规格检查；四个真实上传步骤；明确 MiLens 不介入微信发布/审核；节点 [`422:845`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-845) |
| EX-01 保存/分享 | 成品预览；文件名、像素、格式、大小；系统分享目标；本地生成隐私说明；节点 [`422:849`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-849) |

### 4.10 我的、隐私和 Pro

对应代码：`SettingsView`、`PrivacyInfoView`、`PaywallView`、`HelpView`、`AboutView`。

| Frame | 必须制作的画面 |
|---|---|
| S-01 我的 | Pro 状态；数据与隐私；通知；外观；支持；关于；无账号头像/登录入口 |
| S-02 Pro | 触发式付费墙；月度/年度/永久方案；价格来自 StoreKit；试用/购买中/成功/失败/待处理/恢复购买 |
| S-03 隐私 | 本地处理承诺；照片权限；通知权限；导出数据；清理缓存；删除 App 数据说明；权限跳转 |
| S-04 通知 | 纪念提醒开关；授权中；已授权；拒绝后回弹；生日/领养日/时光机说明 |
| S-05 外观 | 跟随系统/浅色/深色；字体可读性；预览 |
| S-06 帮助 | 常见问题；照片导入、扫描、导出、隐私、恢复数据 |
| S-07 关于 | 版本、品牌、许可、隐私政策、支持入口 |
| R-01 数据恢复 | 本地数据无法加载；查看诊断；重试；导出诊断；重建本地数据二次确认 |

---

## 5. 尚未交付的素材与内容资产

### 5.1 P0：Figma 和首版上线必须先补齐

| 素材包 | 需要交付 | 交付规格/备注 |
|---|---|---|
| App Icon | 正式图标全尺寸和深色/着色变体（如采用） | 当前仓库只有一个 AppIcon PNG，需确认是否为最终品牌稿 |
| 首屏品牌视觉 | 欢迎页主照片/品牌静帧 2–3 张；浅色/深色安全裁切 | 不要用大型 SF Symbol 代替品牌插画；照片应有明确焦点 |
| 伙伴示例图 | 喵星人/汪星人、横/竖、单/多伙伴、浅/深背景、低质量、无头像 | 用于 Home Hero、Create 示例、相册和编辑器测试；必须有可授权来源 |
| 拼豆示例 | 原图→拼豆成品对照；不同尺寸/色板；A4 结果页 | 当前入口会用真实用户照片生成示意，不等于正式营销素材 |
| 伙伴卡片示例 | 默认模板至少 3 组真实示例；名字/日期长短变化 | 覆盖无领养日、长名字、多语言/大字号、深色照片 |
| 空态/错误插画 | 欢迎、无照片、无伙伴、扫描失败、文件缺失、数据库恢复 | 按 Quiet Archive 方向做克制的线稿/照片型插画；不使用 Emoji（用首字或线描剪影占位） |
| App Store 截图素材 | iPhone 6.7/6.5、iPad 12.9 的关键页面截图 | 需真实数据、真实文案、隐私承诺准确；排除未交付 AI 写真/回忆视频 |
| 图标与图形 | Tab 图标策略、工具栏图标、状态图标、质量/重复/收藏图标 | 优先 SF Symbols + 自定义少量品牌图形；状态不能只靠颜色 |

### 5.2 P1：当前有产品决策，但页面/内容仍不完整

| 素材包 | 需要交付 | 当前事实 |
|---|---|---|
| 伙伴卡片多模板 | 经典、拍立得、杂志、极简模板的封面、版式、字体、配色、缩略图、Pro 标记 | Figma 选择轨与经典成品页已交付；其余三套仍需逐模板成品稿与真机验收 |
| 纪念日/里程碑卡 | 生日、领养日、相处 100/365/730/1000 天的模板、文案规则、日期格式、预览封面 | ADR-0010 纳入 V1；当前不是独立可交付页面 |
| 成长对比卡 | 早期/现在双照片布局、时间标签、差异文案、长图导出模板 | A/B 选图与成品 Figma 已交付；仍需代码对照、长名字/缺日期/裁切边界验收 |
| 月度精选 | 月份封面、照片排序/质量规则的视觉呈现、摘要卡、空月状态 | 规划为本地按需生成；页面与封面素材未交付 |
| 年度回忆册 | 封面、目录、章节页、照片页、里程碑页、结尾页、长图导出规格 | 规划为 Pro 情感价值；需先做样章和内容密度测试 |
| 时间线视觉资产 | 生日/领养/照片备注/里程碑事件图标和标记；不同事件连接线 | 时间线代码已有，品牌化事件资产未正式交付 |
| 分享预览 | 拼豆、伙伴卡、成长对比、时间线/年度回忆册四类预览背景、导出规格和水印位置 | 通用成品保存/分享页已交付；仍需补拼豆、时间线/回忆册的内容变体 |

### 5.3 P2/Future：已有接口或规划，不能当作当前 V1 交付

| 素材包 | 需要交付 | 当前状态 |
|---|---|---|
| 编辑器相框 | 基础相框、高级相框、节日相框、透明边界、缩略图、分类、Pro 标记 | `EditorLayerType.frame` 与 `DecorationCatalog` 已预留；Figma 选择/操作态与复用单元已交付，正式资源、catalog 内容和代码面板未实施 |
| 编辑器贴纸 | 爪印、日期、爱心、食物、玩具、节日、彩虹桥等；PNG/SVG、边界、缩略图、分类、Pro 标记 | `EditorLayerType.sticker` 已预留；Figma 选择/变换/删除操作态已交付，正式资源、catalog 内容和代码面板未实施 |
| 贴纸文字/字体包 | 可商用字体、手写字、日期数字、中文长文案适配 | 当前编辑器只有文字工具和固定颜色预设，没有贴纸字体包 |
| 相簿浏览模式 | 复古翻页、拍立得散页、杂志版式的背景、纸张、装订、翻页动效 | `GalleryMode` 已有类型接口；Pro 模式尚未实现页面 |
| 实体打印 | 相册、明信片套装、拼豆材料包、周边的商品图、包装、尺寸和价格展示 | `PrintService` 只有接口/占位模型；真实订单为 V1.x |
| 离线备份 | 备份文件图标、导出/恢复引导、进度/失败/版本不兼容状态 | `BackupService` 有协议和数据模型；页面和最终流程待交付 |
| 彩虹桥/离世纪念 | 纪念模式、时间线封面、安静的纪念视觉、隐私提示 | ADR-0010 列为待实施，不进入当前 V1 主流程 |

### 5.4 明确不做或暂不制作

- AI 写真、回忆视频及其宣传插画/页面：不属于当前 iOS V1 范围。
- 社区、商城、家庭账号、社交关系、用户头像等级体系：不属于当前范围。
- watchOS/穿戴端页面和素材：iOS V1 明确不迁移。
- “AI 认识每一位伙伴”“自动建立完整档案”等确定性宣传文案：当前能力只能表达为帮助发现可能含伙伴的照片。

## 6. 设计交付时每页必须附带的状态与标注

每个 Figma 页面建议使用同一套 Frame 命名：

`[页面编号] / [状态] / [设备] / [外观] / [字号]`

例如：`G-01 / Content / iPhone 6.7 / Light / Default Type`。

交付检查项：

- 正常、加载、空、错误、权限拒绝、部分数据、离线/资源缺失。
- 默认、按下、禁用、选中、处理中、成功、失败、取消、二次确认。
- iPhone compact、iPhone 6.7、iPad；横竖屏只在页面确实支持时制作。
- Light、Dark、High Contrast、Reduce Motion 说明；Dynamic Type 至少检查大字号。
- 文案与当前能力一致；付费能力必须有“预览 → 付费墙 → 购买/恢复 → 导出/分享”完整路径。
- 照片必须注明来源/授权；不把真实用户照片、真实伙伴数据或个人数据库放入仓库。
- 对开发标注照片裁切焦点、最小尺寸、透明边界、导出像素、资源命名和本地化可变长度。

## 7. 建议制作顺序

1. **先定 Foundations + Components**：颜色、字体、记忆标记、PhotoTile、状态页、按钮、分享预览。
2. **完成首次闭环**：O-01–04 → H-01/H-02 → G-01/G-05 → P-02，先让“发现照片—确认—建档—看到档案”成为可演示原型。
3. **完成高频内容页**：相册、照片详情、编辑器、伙伴档案、时间线。
4. **完成创作闭环**：创作首页 → 拼豆/伙伴卡/成长对比/名片/红包封面 → 分享/导出 → Pro。
5. **完成设置与异常状态**：我的、隐私、通知、外观、帮助、关于、数据库恢复。
6. **再做情感资产**：多模板伙伴卡、纪念卡、成长对比、月度精选、年度回忆册。
7. **最后做商业化增强素材**：相框、贴纸、相簿皮肤、实体打印；每一类先完成 1 个可用主题，再扩充数量。

## 8. Release Candidate 已定稿的 12 张主稿

[`MiLens · Release Candidate · FINAL`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=58-2) 目前包含：

1. [`01 · 首页`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=319-1026)
2. [`02 · 伙伴档案`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=319-1095)
3. [`03 · 时间线`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=140-348)
4. [`04 · 图库`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=211-243)
5. [`05 · 创作`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=58-15)
6. [`06 · MiLens Pro`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=58-25)
7. [`07 · 我的`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=140-415)
8. [`08 · 照片详情`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=211-306)
9. [`09 · 添加记忆`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=211-340)
10. [`10 · 拼豆结果`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=211-492)
11. [`11 · 拼豆设置`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=91-248)
12. [`12 · 拼豆生成`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=91-366)

这 12 张已经完成正常态的统一视觉、安全区与字号验收；后续优先沿真实功能补加载、空、失败、权限拒绝、取消和购买恢复等状态分支，不批量制作尚无代码或资源支撑的“未来功能宫格”。

## 9. Image Workshop 已交付的 12 张主稿与 4 张操作态

[`15 · Image Workshop · Editing & Keepsakes`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-801) 包含：

1. [`01 · Creation / Studio Index` 422:805](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-805)
2. [`02 · Picker / Source Pair` 422:809](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-809)
3. [`03 · Editor / Adjust` 422:813](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-813)
4. [`04 · Editor / Crop` 422:817](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-817)
5. [`05 · Editor / Text` 422:821](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-821)
6. [`06 · Editor / Cutout` 422:825](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-825)
7. [`07 · Keepsake / Pet Card` 422:829](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-829)
8. [`08 · Keepsake / Growth Compare` 422:833](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-833)
9. [`09 · Keepsake / Business Card` 422:837](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-837)
10. [`10 · Keepsake / Red Packet` 422:841](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-841)
11. [`11 · Red Packet / Upload Guide` 422:845](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-845)
12. [`12 · Output / Share Preview` 422:849](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-849)

补充操作态：

1. [`05A · Editor / Sticker` 555:1075](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=555-1075)
2. [`05B · Editor / Frame` 558:1152](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=558-1152)
3. [`07A · Keepsake / Pet Card · Annotation Editing` 563:1149](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=563-1149)
4. [`08A · Keepsake / Growth Compare · Annotation Editing` 563:1217](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=563-1217)

扩展组件（2026-08-13 组件级对齐后）：[`Navigation/Editor Group Dock` 458:1145](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=458-1145)、[`Navigation/Editor Tool Row` 459:1158](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=459-1158)、[`Control/Workshop Value Rail` 460:1133](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=460-1133)、[`Picker/Decoration Asset Cell` 552:1084](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=552-1084)、[`Picker/Photo Proof Cell` 462:1164](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=462-1164)、[`Control/Creation Template Tab` 463:1149](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=463-1149)、[`Field/Keepsake Annotation Register` 554:1086](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=554-1086)、[`Action/Creation Output Register` 466:1171](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=466-1171)、[`Action/Editor Panel Register` 466:1197](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=466-1197)。旧 `Control/Editor Tool Dock` 与 `Action/Output Register` 已退役，不再作为实现依据。

本轮返修统一了 12 张扩展稿的 `color/surface/canvas` 背景与 44pt 通用返回控件；其中 02、07–11 还同步校正了实际回退填充，避免变量已绑定而画面仍为纯白。编辑器图标已从散线/字符占位替换为单体 SVG Vector Group；所有 `studio/copper` 绑定替换为主系统的 `color/action/brand` 深铜红。03/04/05/06 已按紧凑三层 `EditorPanelArea` 重排：参数纸内依次是二级标题、342×40pt 横向滚动 Tool Row 和当前参数，一级 Group Dock 常驻；调色页的五条 342×36pt Slider 收入 342×85pt 纵向滚动视口，行间距 2pt且不显示右侧数字。四张编辑画布统一为 `x=24 / y=109 / 342×489pt`，参数纸从 `y=606pt` 起；画布底到铜红线 8pt，线底到二级标题顶 9pt。Group Dock 保持用户确认的 `x=24 / y=767 / 342×54pt` 浅色连续导航面，三等分按钮，选中项使用 `color/action/brand` 图标、文字与 48×2pt 短刻度，未选项使用 `color/text/secondary`，不再使用暗房底、悬浮胶囊或卡片阴影。SwiftUI 实现须从实时 safe area 推导底部位置，不复制参考稿绝对 y 值。

2026-08-13 装饰与注释补充：Decorate 二级轨收敛为文字/贴纸/相框。贴纸操作态提供选中层、拖动、双指缩放/旋转、删除、横向分类轨与横向素材轨；相框操作态提供整画布图层、3:4 自动适配、移除、横向分类轨与相框缩略图。素材单元包含 Default/Selected/Locked 三态与 Pro 语义。07/08 主页面新增注释 Display 行，07A/08A 使用 Editing 变体原位输入；建议 36 个中文字符上限，预览与导出引用同一草稿状态。当前仓库的装饰 catalog 为空，且两类作品暂无注释业务状态，因此这些页面是代码落实依据，不能写成已上线能力。

2026-08-13 最终精修：12 的 AirDrop、微信、信息、更多由字符占位替换为 24×24pt 可编辑矢量并绑定语义色；05A/05B 的 Dock 中文统一为 Noto Sans SC Medium 12pt 与 32pt 文本框，消除“调整/装饰”裁字；05/05A/05B 图层标题右侧的图层名、手势提示及删除/移除文字被移除，只保留 28×28pt 图标动作；六张编辑态的二级选中刻度从行底收紧到文字下方 5pt；02 的 20×20pt 双时态交换矢量中心校正到 `(195, 270)`。对 12 张主页面与 4 张操作态完成最终截图和结构审计：全部为 390×844pt、绑定 `color/surface/canvas`、可见字号不小于 10pt、无缺失字体、无 detached 实例。

2026-08-13 顶部栏复核：以 [`11 · Red Packet / Upload Guide` 422:845](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=422-845) 为样板，02–12 共 11 张带返回页面已统一为 `18 / 57 / 44×44pt` 返回圆、圆内 `10pt` 居中的 24pt 矢量，以及 `72 / 64` 起点的 `MiLens/UI/Title`（20/24、`color/text/primary`）。03–06 与 12 的旧暗房浅色小标题已归并到同一导航标题层级；07–10 的首个内容区下移 8pt 恢复阴影后的呼吸距离。`01 · Creation / Studio Index` 作为 Tab 根页保留品牌头，不添加返回。最终节点审计通过：11 张顶部栏几何、文字样式与颜色绑定一致，12 张页面无顶部/底部安全区越界、可见字号低于 10pt或缺失字体。

### 9.1 Image Workshop 第一批代码落地（2026-08-13）

✅ 已落地页面：

| # | 页面 | Figma 节点 | 代码文件 | 状态 |
|---|---|---|---|---|
| 01 | Creation / Studio Index | 422:805 | `Views/Create/CreateView.swift` | ✅ 已落地：浅色编号网格 |
| 03 | Editor / Adjust | 422:813 | `Views/Editor/EditorToolPanels.swift` | ✅ 已落地：铜索引头 + WorkshopValueRail |
| 04 | Editor / Crop | 422:817 | `Views/Editor/EditorToolPanels.swift` | ✅ 已落地：构图比例 + Transform Rail |
| 05 | Editor / Text | 422:821 | `Views/Editor/EditorToolPanels.swift` | ✅ 已落地：文字图层 + 墨色调色板 |
| 06 | Editor / Cutout | 422:825 | `Views/Editor/EditorToolPanels.swift` | ✅ 已落地：主体抠图 + 双格信息 |
| 12 | Output / Share Preview | 422:849 | `Components/SharePreviewSheet.swift` | ✅ 已落地：编辑式预览 + 系统分享面板 |

✅ 新增组件库：`Components/WorkshopComponents.swift`（CopperIndexBar / WorkshopValueRail / CreationActionBar / EditorialOverline / WorkshopPanelHeader / EditorTransformRail）。

✅ 编辑器架构变更：`EditorToolMode` 新增 `.flip`（独立翻转入口），调整组工具行 = 裁剪/旋转/调色/翻转。

⬚ 待落地页面（第二批）：02 Picker/Source Pair、07–11 Keepsake 系列成品页。

### 9.2 Image Workshop 第二批代码落地（2026-08-13）

✅ 已落地页面：

| # | 页面 | Figma 节点 | 代码文件 | 状态 |
|---|---|---|---|---|
| 02 | Picker / Source Pair | 422:809 | `Views/Create/GrowthComparePhotoPickerView.swift` | ✅ 已落地：A/B 角色双选 + 筛选 + CreationActionBar |
| 07 | Keepsake / Pet Card | 422:829 | `Views/Create/PetCardView.swift` | ✅ 已落地：Source 条 + TemplateRail + 注释行 |
| 08 | Keepsake / Growth Compare | 422:833 | `Views/Create/GrowthCompareView.swift` | ✅ 已落地：Paired Sources + 注释行 |
| 09 | Keepsake / Business Card | 422:837 | `Views/Create/BusinessCard/BusinessCardView.swift` | ✅ 已落地：SourceBar + FieldRow + TemplateRail |
| 10 | Keepsake / Red Packet | 422:841 | `Views/Create/RedPacket/RedPacketCoverView.swift` | ✅ 已落地：SourceBar + Workshop 暗卡 + 上传指引入口 |
| 11 | Red Packet / Upload Guide | 422:845 | `Views/Create/RedPacket/RedPacketUploadGuideView.swift` | ✅ 已落地：新页，时间线步骤 + Platform Note |

✅ 新增共享组件：`WorkshopNavHeader`/`WorkshopSourceBar`/`WorkshopTemplateTab`/`WorkshopFieldRow`/`WorkshopTimelineStep`（追加到 `Components/WorkshopComponents.swift`）。

✅ 路由变更：`Route` 新增 `.redPacketUploadGuide(photoID:petID:)`。

Image Workshop 12 页全部落地完成。

## 10. 维护规则

- 页面或素材完成后，在本备忘录对应表格增加 `✅ 已交付`、日期和 Figma 链接；不要只改口头状态。
- 代码范围、商业化规则或 V1 边界变化时，同步检查 [`DESIGN.md`](../DESIGN.md)、[`PLAN.md`](../PLAN.md)、[`UI-DESIGN.md`](../UI-DESIGN.md) 和 ADR-0010，避免 Figma 继续承诺已砍掉的能力。
- Figma 交付不等于 iOS 交付：页面需要代码实现、真实照片/模型验证、无障碍/深色模式验收后，才能从“设计完成”变成“产品已交付”。
