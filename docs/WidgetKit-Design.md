# MiLens WidgetKit 小组件设计规格

> 状态：Figma 视觉定稿 + 产品/实现契约 + 工程落地（2026-08-12）  
> 适用：iOS / iPadOS 17+，WidgetKit + App Intents  
> 视觉来源：[Figma `14 · WidgetKit · Life Archive Glances`](https://www.figma.com/design/WnT7DCK1XCyPwnS38SE87p/MiLens-iOS?node-id=371-691)、[`UI-DESIGN.md`](../UI-DESIGN.md) §5–§6  
> 数据边界：照片与档案只从本地 App Group 共享快照读取；不上传照片，不承诺云同步或生成式 AI 内容。

## 1. 产品定位

小组件不是功能入口宫格，而是「长期生命档案在桌面上的一页」。首批内容只回答三件事：

1. 今天有什么值得回看；
2. 下一个值得记住的日子是什么；
3. 这份档案已经积累了多久、多少照片和多少段记忆。

拼豆作品可以作为「相片回声」的可配置内容源，但不单独做成广告式“开始制作”卡片。组件不承担编辑、删除、批量导入或付费墙入口。

## 2. 首批组件矩阵

| Widget | Family | 主内容 | 点击目标 |
|---|---|---|---|
| **相片回声 Photo Echo** | Small / Medium / Large | 今日照片、往日同日或最近一张照片；可配置为最近拼豆作品 | 照片详情 / 拼豆结果 |
| **纪念日 Upcoming Day** | Small / Medium | 生日、领养日或用户纪念事件的倒计时与陪伴天数 | 对应伙伴档案 |
| **档案年轮 Life Archive** | Medium / Large | 照片数、记忆数、作品数、档案跨度与年份节点 | 生命时间线 |
| **锁屏·倒计时** | Accessory Circular | 距下个纪念日的天数 | 对应伙伴档案 |
| **锁屏·一段回忆** | Accessory Rectangular | 宠物名、回忆日期与一行标题 | 照片详情 |

桌面组件使用 `AppIntentConfiguration`：用户只配置「伙伴」与「内容类型」。没有伙伴时使用“全部伙伴”；内容不足时安全降级，不伪造回忆。

### 2.1 Figma 交付定位

| 内容 | nodeId |
|---|---|
| 完整 WidgetKit Section | `371:691` |
| 场景化评审板（全部使用组件实例） | `371:693` |
| 可复用组件源区 | `371:694` |
| 相片回声 Small / Medium / Large | `374:691` / `375:691` / `376:691` |
| 纪念日 Small / Medium | `377:691` / `378:691` |
| 档案年轮 Medium / Large | `381:691` / `382:691` |
| 锁屏 Circular / Rectangular | `383:691` / `383:697` |
| Empty / Redacted / Stale | `384:691` / `384:698` / `384:710` |

Figma 当前包含 12 个命名组件与 12 个场景实例。最终审计结果为：无小于 10pt 的文字、无缺失字体、无直接子节点越界、无残留 placeholder。Figma 尺寸用于视觉与层级验收；实现时以系统提供的 `WidgetFamily`、内容边距和 `displaySize` 为准。

## 3. 视觉语法

### 3.1 共同结构

- 系统负责外部 Widget 容器圆角；内部不再叠加一层通用大圆角卡片。
- 使用连续档案纸、照片出血、铜色登记轨、开放年轮和编辑式数字层级建立 MiLens 识别度；不使用手绘线条。
- 珊瑚橙只标记当下事件或可点击端点；深铜红用于登记线、时间刻度和数据编号，不大面积铺底。
- 组件内部最多保留一个强视觉焦点：照片、倒计时数字或档案年轮三者取一，避免把 App 首页压缩进小组件。
- Small 只保留 1 个标题、1 个关键数值或日期、1 个来源标识；Medium 才允许图文双栏；Large 才展示月份轨迹与两条次级记录。

### 3.2 相片回声

- **Small**：照片全出血；顶部为 `MiLens / 日期` 微型登记头，底部渐变承载伙伴名与「今天 / 一年前」来源。铜色细线从右侧清晰端点向左逐渐变细变淡，呼应 Memory Orbit，但不画手绘线。
- **Medium**：左侧照片占约 56%，右侧为连续奶油档案纸；使用 3pt 铜色登记轨连接日期、标题与伙伴身份，不使用独立胶囊标签。
- **Large**：上半部照片，下半部档案纸；加入最近三个月份刻度和一条用户真实备注。没有备注时不生成拟人文案。

### 3.3 纪念日

- **Small**：以大号倒计时数字为主，右侧嵌一张窄幅照片证据；事件名称和日期沿左侧登记轨排列。
- **Medium**：照片证据与倒计时并列，底部用一条开放时间轨表达「已陪伴 N 天 → 还有 N 天」。不使用进度环或百分比，避免把关系表达成任务完成度。
- 当天状态将倒计时改为「今天」，主动作语义为“回看”，不自动出现付费 CTA。

### 3.4 档案年轮

- **Medium**：以右重铜色登记线承接「照片 / 记忆 / 作品」三项统计；数值采用编辑式数字层级，标签为系统 UI 字体。
- **Large**：增加档案起始年份、当前年份、年份节点及一张代表照片；保持连续纸面，不拆成统计卡片宫格。
- 年轮只是时间与记录数量的可视化，不暗示健康、寿命或宠物识别准确度。

### 3.5 锁屏组件

- 采用系统单色/强调色渲染，品牌识别来自开放轨、端点、排版和内容，不依赖固定铜橙色。
- Accessory Circular 只显示天数与极简开放轨；Accessory Rectangular 最多两行正文。
- 锁屏上不展示照片缩略图，降低敏感内容暴露并保证 tinted/vibrant 模式可读。

## 4. 状态矩阵

每个桌面组件至少交付以下状态；锁屏组件至少交付 `content`、`empty`、`redacted`：

| State | 规则 |
|---|---|
| `content` | 展示用户选择伙伴的真实本地数据 |
| `empty` | 无伙伴时提示“先建立一份伙伴档案”；有伙伴无照片时提示“留下一张照片”，点击进入对应建档/相册流程 |
| `redacted` | 隐私或系统占位状态；照片替换为档案纸纹理与日期骨架，保留布局但不显示宠物名、照片或备注 |
| `stale` | 共享快照暂不可读时展示最后成功更新时间，不用假数据覆盖 |

照片、宠物名与用户备注在 Widget 视图中标记为隐私敏感内容。预览和占位数据使用明确的样例名称，不把样例写入用户档案。

## 5. 字体与可读性

- 中文情绪标题可使用霞鹜文楷；品牌名和数字使用 Fraunces；其余标签、英文字母和正文使用系统字体。
- 组件正文不小于 11pt，技术标识不小于 10pt；锁屏尺寸按系统 family 另行适配。
- Small 不放超过两行的可变正文；所有中文稿至少为英文、德文预留 30% 增长空间。
- 支持 Bold Text、Increase Contrast、Differentiate Without Color 与系统 tinted rendering；文字不能只靠照片暗部保证对比。

## 6. WidgetKit 数据与导航契约

### 6.1 共享快照

主 App 在以下事件后更新一个有上限的 App Group 快照，并调用 `WidgetCenter.reloadTimelines`：

- 导入、删除或重新归属照片；
- 新建/编辑伙伴档案与纪念事件；
- 添加记忆或生成新作品；
- 前台启动完成数据迁移后。

共享内容只包含 Widget 所需投影：UUID、伙伴显示名、日期、计数、最多一行标题、深链目标和经过降采样的缩略图。禁止让 Widget Extension 直接打开主 App 的 SwiftData store，也不复制全尺寸照片。

### 6.2 时间线

- 相片回声：跨日刷新；数据变更由主 App 主动 reload。
- 纪念日：为今天与次日边界生成 timeline entry，保证倒计时不滞后。
- 档案年轮：数据变更主动 reload；无变更时不高频刷新。
- Timeline provider 必须可取消并在读不到共享快照时返回 `stale/empty`，不得阻塞 Widget 渲染。

### 6.3 配置与深链

- `SelectPetIntent`：全部伙伴或指定伙伴。
- `PhotoEchoSource`：今日/往日回忆、最近照片、最近拼豆作品。
- 深链建议：`milens://photo/{id}`、`milens://pet/{id}`、`milens://timeline?pet={id}`、`milens://bead/{id}`。
- 主 App 统一解析 URL 并映射到类型安全 `Route`；无效、已删除或迁移后的 ID 回退到对应一级页面，不 crash。

## 7. 实现验收

- 使用独立 Widget Extension、App Group entitlement、App Intents 与 String Catalog；不把 Widget 代码塞入 App target。
- iPhone/iPad 的 Small/Medium/Large、浅色/深色、tinted、StandBy/锁屏相关 family 均做快照检查。
- 真机验证照片隐私、重启后共享快照、数据删除后的降级、跨日倒计时、深链、多个伙伴配置和大字体。
- 不用网络请求更新 Widget，不在组件内出现购买按钮，不记录照片内容、名称或 ID 到分析服务。

平台实现遵循 Apple 官方 [Widget HIG](https://developer.apple.com/design/human-interface-guidelines/widgets/) 与 [App Intent 可配置组件](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget) 文档；Figma 参考尺寸只用于视觉评审，SwiftUI 必须按 `WidgetFamily`、系统内容边距与实际 `displaySize` 自适应。
