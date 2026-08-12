# ADR-0010：商业化强化与情感触发点规划

- 状态：Accepted
- 日期：2026-08-09
- 范围：付费墙权益、定价、水印、分享、情感触点、纪念卡/成长对比/年度回忆册、编辑器装饰资源、离线备份、相簿浏览模式、实体打印
- 关联：[ADR-0009](0009-pro-entitlement-rules.md)（本文扩展其权益矩阵）、[ADR-0008](0008-v1-scope-decision.md)

## 1. 背景

ADR-0009 定义的 Pro 权益（宠物档案数 / 拼豆配额 / 时间线窗口）存在感知价值偏弱的问题：免费版过于慷慨，付费触发点不足。商业化评估结论——核心问题是「功能付费」理由不强，需转向「情感付费」+「限制驱动」双轨，并增加病毒传播闭环。

鸿蒙源端规划了编辑器相框与贴纸能力（尚未实施），对付费吸引力重要，iOS 需预留接口。

本次商业化复评进一步确认：照片整理本身是低频需求，不能单独承担订阅理由；V1 必须把「找到照片」继续推进到「做成作品、纪念、分享、保管」。因此，以下高情感价值触点纳入 V1 实现，而不是仅保留为 V1.x 规划：

- 纪念日与“第一次”里程碑卡片；
- 同一宠物的成长对比卡片；
- 年度/月度精选回忆册与长图导出；
- 高清无水印作品导出；
- Pro 离线备份与恢复；
- 可分享的作品预览与轻量品牌传播。

这些触点共用现有的 Timeline、PetCard、ShareSheet、ImageRenderer、StoreKit 与本地文件生命周期，不引入云账号、云相册或照片上传服务。

## 2. 决策

### 2.1 权益矩阵扩展

| 能力 | 免费版 | MiLens Pro | 变更 |
|---|---|---|---|
| 宠物档案 | 1 个 | 最多 20 个 | 不变 |
| **照片保存** | **50 张** | **不限量** | **新增限制** |
| 拼豆图纸生成 | 每日 5 次 | 不限次数 | 不变 |
| 成长时间线 | 最近 365 天 | 全部历史 | 不变 |
| **纪念日/里程碑卡片** | **可生成经典模板，带水印** | **全部模板、高清无水印导出** | **V1 新增** |
| **成长对比卡片** | **可预览，不可无水印导出** | **高清长图/图片导出与分享** | **V1 新增** |
| **年度/月度回忆册** | **可浏览精选预览** | **完整回忆册、高清长图导出** | **V1 新增** |
| **时间线导出分享** | **不可用** | **长图导出 + 分享** | **新增 Pro 功能** |
| **高清导出** | **标准分辨率、带水印** | **高清分辨率、无水印** | **V1 新增** |
| 图片编辑器 | 无限使用（无相框/贴纸） | 无限使用（含高级相框/贴纸） | 未来扩展 |
| **导出水印** | **带 MiLens 水印** | **无水印** | **新增** |
| 宠物卡片 | 默认模板（带水印） | 全部模板 + 无水印 | **新增多模板** |
| **实体打印** | **预留接口** | **预留接口** | **未来增值服务** |
| **离线备份导出** | **不可用** | **一键打包备份 + 恢复** | **新增 Pro 功能** |
| **相簿浏览模式** | **网格模式** | **复古翻页 / 拍立得 / 杂志** | **新增 Pro 功能** |

权益判定仍由 `ProEntitlementStore.isPro` 统一提供；所有新增卡片和回忆册必须支持“先预览、后付费导出”的路径，避免用户在付费前看不到结果。免费版生成的预览可带 MiLens 水印，但不得把情感内容完全锁死。

### 2.2 定价调整

永久版从 ¥298 降至 ¥168（降幅 44%），降低一次性买断决策门槛。年度/月度不变。

| 产品 | 中国区 | 说明 |
|---|---|---|
| 月度 | ¥18/月 | 不变 |
| 年度 | ¥98/年 | 不变 |
| 永久 | ¥168（原 ¥298） | 锚定逻辑：比年度仅多 ¥70，不到两年回本 |

其他地区价格层级在 App Store Connect 按对应层级录入。

### 2.3 水印设计

- **拼豆 A4 图纸**：页脚区域追加「由 MiLens 制作 · milens.app」灰色低调文字（复用已有位图字体引擎）。
- **宠物卡片**：底部暖黑渐变末尾追加 12pt 半透明白字「MiLens」。
- **免费版导出带水印，Pro 导出无水印。**

水印规则：拼豆图纸水印加在 A4 页脚；宠物卡片水印加在底部渐变区。水印不遮挡主内容。

### 2.4 分享增强（病毒传播闭环）

不集成各平台 SDK（违背纯 Swift 原则、审核成本高），改用「引导式分享预览 + 系统 ShareSheet」：

```
生成作品 → 分享预览页（成品 + 平台图标横排）
    → 点击平台 → 系统 ShareSheet（自动含已安装平台）
    → 分享到小红书/朋友圈/抖音（带水印）
    → 其他用户看到水印 → 搜索下载 → 生成自己的作品
```

分享预览统一支持四类产物：拼豆图纸、宠物卡片、成长对比卡片、时间线/年度回忆册长图。分享链路必须保留系统 ShareSheet，不读取或上传用户社交平台账号；免费作品默认保留低调水印，Pro 作品去水印并允许高清导出。

## 3. 情感触发点系统规划

分为「已实现可强化」和「新增触发点」两类，按转化驱动力排序。

### 3.1 已实现 — 强化（P0–P1）

| 触发点 | 现状 | 强化方案 |
|---|---|---|
| 时光机每日推送 | NotifyService 预排 7 天 | 推送带缩略图附件；月度精选合集；超 365 天照片引导 Pro |
| 宠物生日/成为家人的日子 | 年度重复通知 | 当天首页 Hero 替换 + 「生成生日纪念卡片」CTA |
| 时间线门控 | 14 天体验 + 365 天窗口 | 首页倒计时条；时间线锁定区「还有 N 条更早回忆」 |

### 3.2 新增触发点（P1–P3）

| 触发点 | 优先级 | 方案 | 转化驱动 |
|---|---|---|---|
| 「第一次」纪念 | P1 | 来到家第 100/365/730/1000 天里程碑提醒 + 纪念卡片 | 传播（水印） |
| 成长对比 | P1 | 同一宠物不同时期照片并排，生成对比卡片 | 导出 Pro |
| 照片数量里程碑 | P2 | 50/100/500 张庆祝通知 + 卡片 | 触发 50 张限制 |
| 彩虹桥支持 | P3 | 宠物离世纪念模式，完整时间线不受限，不做付费墙 | 品牌口碑 |

### 3.3 V1 必须实现的情感付费触点

| 触点 | 用户看到的价值 | 免费路径 | Pro 付费点 | 复用能力 |
|---|---|---|---|---|
| 纪念日卡片 | 生日、成为家人的日子、相处 100/365/730/1000 天 | 生成经典模板预览/标准导出 | 高级模板、高清无水印导出 | `PetCardArtwork` + `PetCardTemplate` |
| 成长对比卡片 | 早期与现在的照片并排，直观看到变化 | 选择照片并预览 | 高清导出/分享 | `PetCardArtwork` + `SharePreviewSheet` |
| 月度精选 | 每月自动挑选高质量照片形成小回顾 | 浏览精选预览 | 完整长图导出 | `QualityScorer` + `TimelineExportCanvas` |
| 年度回忆册 | 一年中宠物的照片、事件和里程碑汇总 | 浏览摘要和前几页预览 | 完整回忆册、高清导出 | Timeline 数据 + `ImageRenderer` |
| 历史回忆解锁 | 找回 365 天以前的照片和故事 | 展示锁定数量与缩略预览 | 查看、导出全部历史 | 现有时间线门控 |
| 离线备份 | 保住整理结果、编辑成品和时间线 | 可恢复别人分享的备份 | 创建完整 `.milensbackup` | `BackupService` |
| 作品高清导出 | 打印或发布时不糊、不带水印 | 标准分辨率带水印 | 高清无水印 | 现有导出服务 + 水印参数 |

V1 触发原则：每个触点都必须在用户已经投入时间或产生情感结果后出现付费提示，不在首次启动或尚未看到结果时强制弹付费墙。付费墙文案优先描述“保存/分享这段回忆”，其次才描述“解锁功能”。

### 3.4 V1 事件与指标

为了验证“情感触点”是否真的带来收入，V1 只记录本地匿名计数，不记录或上传照片内容、文本、宠物名称或照片标识。至少记录：

| 事件 | 目的 |
|---|---|
| `scan_completed` | 衡量首次价值是否完成 |
| `first_bead_generated` | 衡量创作入口吸引力 |
| `memory_card_previewed` / `growth_compare_previewed` | 衡量情感触点消费量 |
| `export_started` / `export_completed` | 衡量是否产生可分享作品 |
| `paywall_shown` / `purchase_started` / `purchase_completed` | 衡量触点到付费的转化 |
| `backup_export_started` | 衡量长期保管需求 |
| `share_sheet_opened` | 衡量传播潜力 |

指标优先级为：首次扫描完成率 → 首次创作率 → 首次导出率 → 付费转化率 → 30/90 天回访率。V1 不把下载量单独当作商业成功标准。

### 3.5 触发点 × 付费转化矩阵

| 触发点 | 免费体验 | Pro 转化 | 传播 |
|---|---|---|---|
| 照片 50 张限制 | 够用 | ⭐⭐⭐⭐⭐ | — |
| 水印导出 | 带水印 | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| 时光机推送 | 近一年 | ⭐⭐⭐⭐ | — |
| 生日纪念卡片 | 生成免费 | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| 成长对比 | 可预览 | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| 彩虹桥 | 完整免费 | — | ⭐⭐⭐⭐⭐ |

## 4. 宠物卡片多模板系统

### 4.1 模板定义

当前 `PetCardArtwork` 为单一固定版式。引入 `PetCardTemplate` 枚举（MiLensKit），定义多套排版参数：

| 模板 | id | 免费可用 | 风格描述 |
|---|---|---|---|
| 经典 | `classic` | ✅ | 全屏照片 + 底部暖黑渐变 + 左下衬线名字（当前版式） |
| 拍立得 | `polaroid` | Pro | 白边相框 + 底部手写体文案区 |
| 杂志 | `magazine` | Pro | 照片偏上 + 大号 display 标题 + 细体副标题 |
| 极简 | `minimal` | Pro | 纯照片 + 右下角小字签名 |

### 4.2 门控规则

- 免费用户只能选择 `.classic` 模板，其他模板在模板选择器中可见但带锁标记，点击触发付费墙。
- 模板切换不影响水印逻辑（免费版任何模板都带水印）。
- 模板选择持久化到用户偏好，下次进入默认使用上次选择。

### 4.3 架构

- `PetCardTemplate`（MiLensKit）：模板枚举 + 元数据（displayName / isPremium / 本地化 key）。
- `PetCardArtwork`（App 层）：接收 `template` 参数，根据模板切换排版分支。
- `PetCardView`：底部水平滚动的模板选择器（带预览缩略图 + Pro 锁标）。

## 5. 成长时间线导出分享

### 5.1 场景

用户在时间线页面浏览宠物成长记录，希望将某段时间的成长故事导出为长图分享到社交平台。这是高情感价值的 Pro 专属功能。

### 5.2 设计

- 导出范围：当前筛选条件下的全部可见月份（受 365 天门控约束——免费用户导出按钮灰锁，Pro 用户导出全部历史）。
- 导出格式：长图 PNG（宽度 1080px，高度按内容自适应），通过 `ImageRenderer` 渲染。
- 长图结构：头部（宠物名 + 日期范围）→ 按月分组条目列表 → 底部「由 MiLens 制作」签名（Pro 无水印则无签名）。
- 分享：复用 `SharePreviewSheet` 引导式分享流程。

### 5.3 架构

- `TimelineExportLogic`（纯函数）：从 `TimelineMonth[]` 准备导出数据（标题、日期范围、条目裁剪），不依赖 SwiftUI。
- `TimelineExportCanvas`（SwiftUI View）：纯渲染视图，供 `ImageRenderer` 离屏生成图片。
- `TimelineView`：导航栏增加「分享」按钮，Pro 门控 → 点击弹导出预览面板。

## 6. 编辑器相框/贴纸接口预留

源端鸿蒙编辑器规划了相框（frame）与贴纸（sticker）能力但未实施。`EditorLayerModels.swift` 已定义 `EditorLayerType.frame` / `.sticker` 枚举值，`createImageLayer` 工厂已支持创建对应图层。

新增 `DecorationCatalog`（MiLensKit）作为资源目录抽象：

- `DecorationItem`：id / name / category / resourcePath / isPremium / previewPath
- `DecorationCatalog`：按类别查询可用装饰项（frame / sticker）
- Pro 门控：`isPremium` 标记的装饰项对免费用户可见但不可用，点击触发付费墙
- 序列化兼容：装饰图层复用现有 `EditorLayerSnapshot`（type 字段已支持 "frame"/"sticker"）

具体 UI 面板与素材资源在 V1.x 实施，本文只锁定数据模型与 Pro 门控接口。

## 7. 实体打印增值服务接口预留

### 7.1 场景

未来推出配套实体产品（照片相册、明信片、拼豆成品套装、文创周边等），用户在 App 内下单定制。V1 实现“作品导出后进入系统打印/文件分享”的无后端路径；真实商品目录、报价、支付和物流仍只预留接口，不在 V1 接入。

### 7.2 产品类型

| 产品 | id | 数据来源 | 说明 |
|---|---|---|---|
| 宠物相册 | `photoAlbum` | 照片库选择 | 精装印刷相册，可选模板 |
| 明信片套装 | `postcardSet` | 宠物卡片 | 基于卡片模板印刷 |
| 拼豆成品 | `beadKit` | 拼豆图纸 | 按图纸配好的珠子套装或成品 |
| 文创周边 | `merchandise` | 照片/卡片 | 手机壳、帆布画、马克杯等 |

### 7.3 架构

- `PrintService`（protocol）：打印订单服务抽象，定义产品目录查询、报价、下单、物流查询接口。
- `PrintProduct` / `PrintOrder` / `PrintQuote`：数据模型，Codable + Sendable。
- V1 提供占位实现 `UnavailablePrintService`（所有方法 throw `.serviceUnavailable`），UI 层在作品导出完成后显示“保存到相册/文件或分享”，打印商品入口显示「即将上线」而不制造不可用的购买流程。
- 后续接入真实后端时只需替换实现，不影响业务层。

## 8. 离线照片导出备份

### 8.1 背景与约束

MiLens 照片副本存在沙盒 `Documents/MiPhotos/`，其中导入副本被排除 iCloud/iTunes 备份（原图在系统相册可重建），但编辑成品允许备份（不可重建）。设备恢复或卸载后，用户会丢失：

1. **元数据**：宠物关联、收藏、标注、时间线事件
2. **编辑成品**：裁剪/滤镜后的照片（系统相册中没有）
3. **整理投入**：重新扫描 + AI 识别 + 质量评分需要重新跑

**硬约束：App 不会主动上传照片；编辑产物可能随用户启用的系统备份保存。** MiLens 的照片分析与编辑在设备本地完成。批量导出备份通过系统分享能力交给用户决定目标位置，不引入 App 自有云服务。

### 8.2 方案对比

| 方案 | 机制 | 是否联网 | 含元数据 | 推荐度 |
|---|---|---|---|---|
| **A. ZIP 打包 + ShareSheet** | 照片+元数据打包为 `.milensbackup`，系统分享面板导出 | 否（ShareSheet 不联网） | ✅ | ⭐⭐⭐⭐⭐ |
| B. iTunes File Sharing | `UIFileSharingEnabled`，Documents 暴露给 Finder | 否 | 手动拖文件 | ⭐⭐⭐⭐（补充） |
| C. 写入系统相册 | `PHPhotoLibrary` 写入到自定义相簿 | 否 | ❌ 丢失元数据 | ⭐⭐（不推荐） |
| D. iCloud Documents | 写入 iCloud Drive 容器 | 是（需要联网） | ✅ | ⭐⭐（违背不联网约束） |

**决策：方案 A 为核心，方案 B 为补充。**

- A 满足「本地生成 + 含元数据 + 用户可控」三大要求；ShareSheet 让用户自行决定存到哪里（Files App、iCloud Drive、AirDrop 到 Mac）。
- B 作为锦上添花：开启 `UIFileSharingEnabled` 后用户可 USB 连电脑直接拖拽 Documents 目录。
- **不选 C**：MiLens 的核心价值是从海量相册筛选出宠物照片，导回系统相册逻辑混乱，且元数据（宠物关联、标注）无法保留在 `PHAsset` 中。
- **不选 D**：由 App 直接写入 iCloud Documents 会把云端同步变成 App 自己的依赖，也会扩大数据处理和隐私说明范围；V1 只通过系统备份或用户主动分享导出。

### 8.3 备份包格式

```
MiLens-Backup-2026-08-10.milensbackup  (ZIP 压缩包)
├── manifest.json          # 版本信息、备份日期、Schema 版本、照片数、宠物数
├── metadata.json          # 完整数据库导出（宠物、照片、事件、收藏、标注）
├── photos/                # 全部照片原图（按 UUID 命名）
│   ├── {uuid}.jpg
│   └── ...
└── edits/                 # 编辑成品（系统相册中没有，不可重建）
    └── ...
```

`manifest.json` 包含 `schemaVersion`，恢复时据此决定是否需要迁移。

### 8.4 备份流程

```
设置页 → 「备份导出」（Pro 门控；isAvailable=false 时禁用并提示「即将上线」）
  → estimateBackup 预估规模（宠物数 + 照片数，不打包）
  → BackupConfirmSheet 确认对话框（展示预估规模 + 打包说明，用户确认）
  → 异步打包（阶段进度浮层：收集元数据 / 复制照片 / 压缩，带百分比）
  → ShareSheet（用户选择保存位置）
  → 完成
```

> **2026-08-12 实现增强**：V1 首版流程仅有「点击 → 异步打包 → 分享」三步。现拆为五步（入口兑底 → 预估 → 确认 → 带阶段的打包 → 分享），解决三个体验缺口：大库无声产出巨大 ZIP、长任务不知道卡在哪一步、服务不可用时点击直接报错而非入口禁用。

### 8.5 恢复流程

```
设置页 → 「备份恢复」
  → UIDocumentPicker 选择 .milensbackup 文件
  → 校验 manifest 版本 → 合并导入（不覆盖现有数据）
  → 照片文件复制到沙盒 → 元数据导入 SwiftData
```

### 8.6 架构

- `BackupService`（protocol）：备份导出/恢复服务抽象，定义打包、解包、校验、导入接口。**2026-08-12 新增** `estimateBackup(petIDs:) -> BackupEstimate` 预估能力（不打包，仅统计计数）与 `isAvailable` 属性（UI 层据此禁用/隐藏入口或显示「即将上线」，作为服务不可用时的第一道防线，throw `.serviceUnavailable` 为第二道）。
- `BackupEstimate` / `BackupManifest` / `BackupMetadata`：备份预估与备份包数据结构，Codable + Sendable。
- `ZipBackupService`：V1 实现（替代原始规划的 `IOSBackupService`），使用 MiLensKit 纯 Swift `ZIPArchive`（store 模式，无三方依赖，可在 WSL2 测试），而非 Foundation `ZIPFoundation` 或系统 Compression.framework（决策落地时的实现选择，保持纯 Swift 无三方依赖原则）。
- `BackupViewModel`（@Observable）：导出状态机携带 `BackupPhase`（收集/复制/压缩/完成），恢复状态机携带 `RestorePhase`；两步导出流程（`prepareExport()` 预估 → `.readyToExport` 待确认 → `exportBackup()` 打包）。
- Pro 门控：备份为 Pro 专属功能，恢复对免费用户开放（不限制恢复已获得的备份）。
- `project.yml`（Info.plist 唯一事实源）：开启 `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`；`UTExportedTypeDeclarations` 声明 `com.milens.backup`（conforms `public.zip-archive`+`public.data`，扩展名 `.milensbackup`，MIME `application/zip`）；`CFBundleDocumentTypes` 注册为 Viewer。`fileImporter` 限定该 UTType（`UTType(exportedAs:)`），`.item` 仅作旧版系统兑底。

## 9. 复古相簿浏览模式

### 9.1 场景

当前 Gallery 只有网格瀑布流一种浏览模式。用户付费后可切换到复古翻页式相簿浏览，提升情感浏览体验。这是一个高感知价值的 Pro 专属体验功能。

### 9.2 模式定义

| 模式 | id | 免费可用 | 风格描述 |
|---|---|---|---|
| 网格 | `grid` | ✅ | 当前默认，按日期分组的瀑布流网格 |
| 剪贴簿 | `scrapbook` | Pro | 纸质背景 + 胶带贴图 + 手写日期标注 + 3D 翻页动画 |
| 拍立得散页 | `polaroidScatter` | Pro | 拍立得白边照片散落排列，点击翻转看背面信息 |
| 杂志画册 | `magazine` | Pro | 全屏照片 + 大留白 + 衬线页码 + 横向滑动翻页 |

### 9.3 技术实现要点

- **3D 翻页**：`rotation3DEffect` + 自定义手势识别（拖拽弧度 → 翻页角度）。
- **纸质纹理**：Asset Catalog 图片或程序生成（Canvas + 噪点滤镜）。
- **散落排列**：预设布局模板 + 随机旋转角度（拍立得模式）。
- **性能**：`LazyVStack` / `TabView(.page)` 虚拟化，离屏页面释放缩略图。
- **每种模式独立的 SwiftUI View 组件**，通过 `GalleryMode` 枚举在 `GalleryView` 中切换。

### 9.4 架构

- `GalleryMode`（MiLensKit）：模式枚举 + 元数据 + Pro 门控。
- `GalleryView`：顶部模式切换器（水平 chip + 锁标）。
- `ScrapbookAlbumView` / `PolaroidScatterView` / `MagazineAlbumView`：各模式独立视图组件（V1.x 实施）。
- 模式选择持久化到 `@AppStorage("galleryMode")`。

## 10. 实现映射

### 10.1 照片限制（P0-a）

- `CommercialRules.swift`：新增 `freePhotoLimit = 50` / `proPhotoLimit = .max`
- `ImportService.swift`：导入前配额检查，返回 `.quotaExceeded(remaining:)`
- `GalleryViewModel.swift`：超额拦截到付费墙
- `ProFeature.swift`：新增 `.photoStorage` 权益
- `CommercialRulesTests.swift`：配额边界用例

### 10.2 水印（P0-b）

- `MiLensKit/.../BeadExportService.swift`：`renderA4Export` 增加 `includeWatermark` 参数
- `PetCardArtwork.swift`：底部水印条件渲染
- `BeadViewModel.swift`：导出传 `isPro` 标志
- `ProFeature.swift`：新增 `.watermarkFreeExport` 权益

### 10.3 定价（P0-c）

- `Products.storekit`：`displayPrice` 298 → 168
- `docs/AppStore-metadata.md`：§7.2 价格表 + 描述同步

### 10.4 分享增强（P0-d）

- `MiLens/Components/SharePreviewSheet.swift`（新建）：分享预览 + 平台图标行
- `BeadPatternResultView.swift` / `PetCardView.swift`：分享按钮改为弹出 SharePreviewSheet

### 10.5 宠物卡片多模板（P0-e）

- `MiLensKit/.../PetCardTemplate.swift`（新建）：模板枚举 + 元数据 + Pro 门控
- `PetCardArtwork`：根据模板参数渲染不同版式
- `PetCardView`：底部模板选择器 + 持久化

### 10.6 时间线导出分享（P0-f）

- `TimelineExportLogic.swift`（新建）：导出数据准备纯函数
- `TimelineExportCanvas.swift`（新建）：离屏渲染视图
- `TimelineView`：导航栏「分享」按钮 + Pro 门控

### 10.7 离线备份接口（预留）

- `MiLens/Services/Backup/BackupService.swift`（新建）：协议 + 数据模型 + 占位实现
- `Info.plist`：开启 `UIFileSharingEnabled`（预留）

### 10.8 相簿模式接口（预留）

- `MiLensKit/.../Types/GalleryMode.swift`（新建）：模式枚举 + 元数据 + Pro 门控

### 10.9 实体打印接口（预留）

- `MiLens/Services/Print/PrintService.swift`（新建）：协议 + 数据模型 + 占位实现

### 10.10 编辑器装饰接口（预留）

- `MiLensKit/.../DecorationCatalog.swift`（新建）：资源目录数据模型 + Pro 门控元数据

### 10.11 纪念日与里程碑卡片（V1）

- `MilestoneLogic`（MiLensKit）：根据 `adoptionDay` 计算 100/365/730/1000 天里程碑，纯函数 + XCTest；`NotifyService` 负责单次本地通知调度。
- `MemoryCardKind`：`birthday` / `adoptionDay` / `milestone` / `growthCompare` / `monthlyRecap` / `yearlyRecap`。
- `PetCardArtwork`：复用模板、文案和水印策略，支持纪念卡、成长对比卡和回忆册封面。
- `NotifyService`：仅在用户开启提醒后调度周年、相处里程碑和时光机通知；通知内容不含照片数据，点击后在本地生成预览。
- `SharePreviewSheet`：统一预览、保存、分享和付费墙入口。

### 10.12 月度精选与年度回忆册（V1）

- `MemoryRecapLogic`（MiLensKit）：按月份/年份筛选照片、事件和里程碑，使用质量分和去重结果选取代表照片。
- 月度精选为本地按需生成，不做后台上传；年度回忆册支持取消、进度反馈和尺寸上限。
- 免费用户可看到摘要/前几页预览；Pro 用户可完整查看和高清导出。
- 复用 `TimelineExportLogic` / `TimelineExportCanvas`，避免产生第二套长图渲染管线。

### 10.13 高清导出与作品规格（V1）

- `ExportQuality`：`standard` / `high`，统一由导出服务决定像素上限、JPEG/PNG 质量和内存保护。
- 免费版标准导出保留水印；Pro 版高清导出无水印。
- 所有高清导出必须经过尺寸上限、取消检查和临时文件清理，不能因商业化绕过资源生命周期规则。

### 10.14 V1 商业化验收

- 每个付费触点都能从“预览 → 付费墙 → 购买/恢复购买 → 导出/分享”走通。
- 免费用户可以完成一次完整情感体验：建立宠物 → 看到时间线 → 生成一张卡片或拼豆图纸 → 分享带水印作品。
- Pro 用户可以完成：历史查看、成长对比/回忆册高清导出、离线备份导出与恢复、无水印分享。
- 购买、恢复购买、退款/撤销权益后，所有触点使用同一 `ProEntitlementStore` 状态，不在页面内缓存独立的 Pro 布尔值。
- StoreKit Testing 覆盖月度、年度、永久、恢复购买和权益撤销；每类导出至少有标准/高清、水印/无水印、取消/失败用例。

## 11. 落地优先级

| 阶段 | 内容 | 状态 |
|---|---|---|
| **P0** | 照片限制 + 水印 + 价格 + 分享增强 | 已完成 |
| **P0-e** | 宠物卡片多模板系统 | 本次实施 |
| **P0-f** | 时间线导出分享（Pro） | 本次实施 |
| **V1-a** | 纪念日/里程碑卡片 + 成长对比卡片 | 纳入 V1 |
| **V1-b** | 月度精选 + 年度回忆册 + 高清导出 | 纳入 V1 |
| **V1-c** | 离线备份导出/恢复 | 纳入 V1 |
| **V1-d** | 一个高级相簿模式（推荐拍立得散页） | 纳入 V1；其余模式 V1.x |
| **V1-e** | 实体打印无后端导出入口与验证指标 | 纳入 V1；真实订单 V1.x |
| P2 | 照片数量里程碑、编辑器完整相框/贴纸素材、实体打印下单、更多相簿模式 | V1 后增强 |
| P3 | 彩虹桥支持 | 待实施 |
