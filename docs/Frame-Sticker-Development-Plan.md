# MiLens 相框与贴纸开发计划

最后核对：2026-08-24

> 本文定义图片编辑器「装饰」组中相框与贴纸的产品边界、交互、素材契约、工程实施顺序和验收标准。视觉与几何规格以 [UI-DESIGN.md §6.8](../UI-DESIGN.md#68-图片编辑器) 和 Figma `05A · Editor / Sticker`、`05B · Editor / Frame` 为准；编辑器架构与资源生命周期遵循 [DESIGN.md](../DESIGN.md)；里程碑状态见 [PLAN.md](../PLAN.md)。

## 1. 目标与边界

相框与贴纸是现有图片编辑器的增量能力，不新增独立创作流程：

- **相框**是整张照片的结构层，用于建立档案纸、胶片、纸样或节日边界；同一文档最多一个相框。
- **贴纸**是照片上的局部叙事层，用于补充身份、日常和纪念语义；同一文档可以有多个贴纸。
- 两者都必须参与撤销/重做、保存、导出和失败恢复，并保持预览与最终导出一致。
- 素材全部随 App 本地打包，选择、编辑与渲染不上传照片、不依赖网络。

本阶段不做：在线素材商城、用户上传自定义贴纸、动态贴纸、生成式贴纸、相框自由旋转/缩放、云端素材下载和跨设备草稿同步。

## 2. 对原始规划的修订

原始方向成立，但结合现有代码后需要做以下调整：

1. **Pro 按素材门控，不按贴纸数量门控。** `DecorationItem.isPremium` 已是现有商业化契约。免费用户可使用全部免费素材，技术上统一限制单文档最多 20 个贴纸，避免渲染和误操作失控；达到上限只提示精简画面，不触发付费墙。
2. **首批以 Figma 已定义素材为交付下限。** 第一批先交付 6 个相框和 6 个贴纸，确保完整链路可验收；第二批再把贴纸扩充到 12–18 个。不能用临时图形或占位图填充运行时目录。
3. **相框是单选替换，不是普通可变换图层。** 选择新相框应原位替换现有相框；相框只允许选择、替换和移除，不参与点选拖动、双指缩放或旋转。
4. **贴纸保持自由图层。** 贴纸支持添加多个、点选、拖动、双指缩放旋转和删除；一次连续手势合并为一条历史记录。
5. **不依赖“不要遮脸”的硬阻拦。** V1 不增加额外 Vision 推理。素材默认落点避开画面中心，用户仍可自由调整；后续若复用已有主体框，只提供温和参考线，不自动移动用户内容。
6. **层级采用稳定语义，而不是依赖添加顺序。** 导出和预览统一按「照片 → 相框 → 贴纸 → 文字」合成；同类贴纸内部再按 `zIndex` 排序。V1 不开放手动调层级。

## 3. 当前实现基线与开放前阻塞项

### 3.1 已具备

- `EditorLayerType` 已包含 `.frame` / `.sticker`，编辑器文档、命中测试和基础变换能力可以复用。
- `DecorationCatalog` 已定义类别、分组、排序、Pro 门控和素材路径。
- `FrameFitMode` 已支持 `stretch`、`ninePatch`、`ratioSet`，并有纯函数测试。
- `DecorationCatalogLoader` 已从 Bundle 加载 `MiLens/Resources/Decorations/catalog.json`；失败安全回退为空目录。
- `tools/frame_import.py` 与 `tools/frame-import-gui.py` 已能生成 imageset、合并目录并校验素材。
- `EditorImageProcessing.renderExport` 已有装饰渲染入口，支持透明度、翻转和九宫格绘制。
- Figma 已给出贴纸/相框面板、分类轨、素材轨、选中态和 Pro 锁定态。

### 3.2 必须先修复

| 阻塞项 | 当前风险 | 目标处理 |
|---|---|---|
| 历史快照缺少 `resourcePath` | 撤销/重做后装饰素材路径丢失，图层无法恢复 | 给 `EditorLayerSnapshot` 增加可选 `resourcePath` 与 `visible`，解码缺失字段时兼容旧快照 |
| 相框初始坐标为 `(0, 0)` | 编辑器坐标以图层中心为锚点，相框会偏到画布左上 | 相框创建于 `(canvasWidth/2, canvasHeight/2)`，尺寸铺满画布 |
| 预览未解析 `ratioSet` | 多比例相框在预览中可能缺图，或与导出素材不同 | 抽取共享 `DecorationAssetResolver`，预览和导出使用同一比例选择结果 |
| 预览把 `ninePatch` 直接拉伸 | 角部和边缘在预览中变形，保存后“跳变” | 预览使用可缩放九宫格实现，或先把目标尺寸离屏渲染后缓存显示 |
| 导出未按稳定类型层级排序 | 相框和贴纸视觉顺序受添加顺序影响 | 统一合成排序：photo、frame、sticker、text；贴纸内部按 `zIndex` |
| 相框会被普通命中测试选中 | 用户可能拖动或缩放整画布相框 | 画布命中和变换逻辑排除 `.frame`，面板负责选择与移除 |
| 画布尺寸变化只更新照片层 | 裁剪、旋转或 iPad 布局变化后相框和贴纸错位 | 引入画布重映射：相框重新铺满；贴纸和文字按旧/新画布比例映射中心点与尺寸 |
| 目录分组使用直接中文字符串 | 多语言下分组不可稳定本地化，字典分组顺序也不可靠 | `group` 改用稳定 ID，UI 映射 `decoration.group.*`；分类顺序由常量显式声明 |

以上项目完成前，贴纸与相框入口保持受 catalog/功能开关控制，不显示为已可用能力。

## 4. 产品与交互规格

### 4.1 共用面板

- 一级分组仍为「调整 / 智能 / 装饰」。
- 装饰二级工具只包含「文字 / 贴纸 / 相框」。
- 贴纸和相框面板均使用：标题行 → 横向分类轨 → 横向素材轨。
- 素材单元保持 Figma 的 `Default / Selected / Locked` 三态；Locked 仍展示真实预览和 `PRO` 标记。
- 目录为空、解析失败或全部资源缺失时显示真实空态「装饰资源暂未安装」，不注入演示素材。
- 标题行右侧只显示图标动作：贴纸为删除当前贴纸，相框为移除当前相框；必须提供完整 VoiceOver 标签。

### 4.2 相框行为

- 点击未锁定素材：若不存在相框则添加；若已有相框则在同一历史操作中替换。
- 点击当前已选相框：保持选中，不重复创建。
- 点击移除：删除相框并记录历史；无相框时动作禁用。
- 点击锁定素材：不修改文档，打开现有付费墙；购买成功后返回原位置并允许再次选择。
- 相框永远贴合当前有效画布，`rotation = 0`、`scale = 1`、`flipX/flipY = false`。
- 裁剪、旋转或画布宽高比变化后，重新选择 `ratioSet` 最接近的素材，并在一次 UI 更新内完成，不能短暂显示旧比例。

### 4.3 贴纸行为

- 点击素材即新增一个贴纸，并把新图层设为活动图层。
- 默认尺寸为画布短边的 22%；默认位置为画布中心向右上偏移约 18%，避免直接遮挡常见主体中心。位置必须 clamp 在画布内。
- 支持点选、拖动、双指缩放和旋转。建议视觉尺寸下限为画布短边的 8%，上限为 70%；底层仍使用纯函数约束，不能只在 View 中 clamp。
- 拖动时可显示水平/垂直中心参考线；吸附只在 6pt 内生效，离开阈值立即释放。Reduce Motion 下不播放吸附回弹。
- 删除当前贴纸后，活动图层回退到最近添加的贴纸；没有贴纸时清空活动选择，不选中照片或相框。
- 单文档最多 20 个贴纸。达到上限时保留当前文档并显示非阻断提示，不删除旧图层。

### 4.4 工具切换和历史

- 添加、替换、移除素材各产生一条历史。
- 一次连续拖动、缩放或旋转合并为一条历史，沿用 `beginGesture/endGesture`。
- 从贴纸切换到文字或相框时保留贴纸活动状态，但隐藏选择框；返回贴纸工具后恢复最近活动贴纸。
- 相框替换需要保存旧 `resourcePath`，撤销后恢复旧相框而不是只恢复空图层。
- 保存成功后继续沿用现有逻辑重置历史基线。

## 5. 素材目录与首批清单

### 5.1 稳定分组 ID

| 类别 | 分组 ID | 简中显示名 | 首批素材 |
|---|---|---|---|
| frame | `recommended` | 推荐 | Linen Register |
| frame | `film` | 胶片 | Polaroid、Film |
| frame | `paper` | 纸样 | Editorial、Ribbon |
| frame | `holiday` | 节日 | Holiday |
| sticker | `recommended` | 推荐 | Sun Paw |
| sticker | `paw` | 爪印 | Paw Mark |
| sticker | `daily` | 日常 | Heart、Bloom、Camera |
| sticker | `memorial` | 纪念 | Star |

「更多」不是 catalog 分组，而是素材数量超出当前视口时的产品入口；首批不接在线商店，不显示无去向的「更多」。若视觉稿保留该标签，点击后应进入同一轨道的本地扩展分组，而不是空页面。

### 5.2 免费与 Pro

首批建议保持“基础叙事完整、主题风格付费”：

- 免费：Linen Register、Polaroid、Film；Sun Paw、Paw Mark、Heart、Bloom、Camera。
- Pro：Editorial、Ribbon、Holiday；Star。
- Pro 素材必须可预览，但用户确认使用前不写入文档。
- 免费导出的全局水印规则继续由现有商业化逻辑决定，不在装饰素材中内嵌第二份水印。

第二批贴纸候选为档案藏印、食盆、玩具球、月亮睡眠、生日蛋糕、领养丝带。正式制作前需在 Figma 中完成同一笔触、颜色和缩略图可读性审查。

### 5.3 实装状态（2026-08-24）

catalog 现有 13 条 = 12 贴纸 + 1 相框，均已通过 `tools/frame_import.py validate`：

- **贴纸 12/12**：首批 6（Sun Paw、Paw Mark、Warm Heart、Bloom Flower、Retro Camera、Radiant Star）+ 第二批候选 5（档案藏印、食盆、月亮睡眠、生日蛋糕、领养丝带；玩具球未做）+ 规划外 Tandem Paws（爪印组）。全部 `stretch`、免费。
- **相框 1/6**：`frame_spring_botanical`（春日花叶，规划外新增，`paper` 组，`ratio_set` 仅 `3x4`——2026-08-24 用户批准的单比例交付，偏差记录见 §6.2）。首批规划的 Linen Register、Polaroid、Film、Editorial、Ribbon、Holiday 仍未制作。
- **已知缺口**：无。12 个贴纸的 `name` / a11y key（`decoration.sticker.*`）已全部录入 `Localizable.xcstrings`（包含 zh-Hans, zh-Hant, en, ja, ko, fr, de 7 国语言完整翻译），VoiceOver 读屏无障碍体验完整达标。

## 6. 素材制作与导入契约

### 6.1 通用要求

- 运行时素材使用透明 PNG，sRGB 色彩空间，禁止带未裁切的大面积透明边缘。
- 贴纸建议提供 1024×1024px 母版；非正方形贴纸保留真实宽高比，并正确填写 `native_aspect_ratio`。
- 相框按最大导出边长准备，边缘纹理在 2048px 长边导出时不得明显糊化；复杂相框优先 `ratio_set`，不要强行九宫格。
- 预览图必须独立检查 44×40pt 内容槽中的可辨识度，不能只缩小完整大图后直接交付。
- 单素材解码后内存和包体积需要进入素材评审；同一视觉不重复打包全尺寸副本。

### 6.2 相框模式选择

| 模式 | 适用素材 | 禁忌 |
|---|---|---|
| `stretch` | 纯色、规则渐变、无角部细节的边界 | 有文字、印章、角花或固定线宽的素材 |
| `nine_patch` | 线框、登记线、规则边角 | 中央有不可拉伸纹理或四边连续图案 |
| `ratio_set` | 拍立得、胶片、手工纸、复杂花纹 | 只提供一个比例后依赖拉伸兜底 |

首批 `ratio_set` 支持 `1x1`、`3x4`、`4x3`、`16x9`、`9x16`。比例缺失属于素材校验失败，不在运行时静默选择方向错误的图片。

> **已批准偏差（2026-08-24）**：`frame_spring_botanical` 仅交付 `3x4`（用户决策「此次只做 3:4」）。运行时 `resolveDecorationResource` 会在其他比例画布上解析到 `3x4` 素材并被整体非等比拉伸，植物装饰存在变形风险；后续补齐其余比例 PNG 后消除。导入工具 validate 不强制五比例齐备（只校验比例命名合法与 imageset 存在），五比例要求仍作为正式交付目标保留。

### 6.3 manifest 约定

沿用现有 snake_case manifest；显示名称和分组使用稳定本地化标识：

```json
{
  "id": "frame_polaroid_white",
  "name": "decoration.frame.polaroidWhite",
  "category": "frame",
  "fit_mode": "ratio_set",
  "is_premium": false,
  "group": "film",
  "sort_order": 20,
  "supported_ratios": ["1x1", "3x4", "4x3", "16x9", "9x16"],
  "preview_path": "frame_polaroid_white_preview"
}
```

导入流程：

```bash
python tools/frame_import.py add <素材源目录>
python tools/frame_import.py validate
python tools/frame_import.py list
```

导入工具需要继续保证：ID 唯一、PNG 存在、比例命名合法、nine-patch inset 合法、catalog 与 imageset 双向完整。建议补充校验：透明通道、像素尺寸、分组 ID、重复 `sortOrder` 警告和未使用 imageset 报告。

## 7. 工程拆分

### 7.1 MiLensKit 纯逻辑

- 扩展 `EditorLayerSnapshot`，持久化 `resourcePath` / `visible`，保持旧 JSON 可解码。
- 新增装饰文档操作：`replaceFrame`、`removeFrame`、`addSticker`、`removeSticker`、`activeSticker`。
- 新增稳定层级排序函数和 20 个贴纸上限决策。
- 新增画布尺寸变化重映射函数；输入旧/新尺寸和图层，输出确定性几何结果。
- 修正相框创建中心点；把贴纸默认位置、默认尺寸和尺寸 clamp 下沉为纯函数。
- 扩充 catalog 校验与稳定分组顺序，避免 UI 依赖 `Dictionary` 枚举顺序。

### 7.2 App ViewModel / Service

- 新建 `EditorDecorationPanelVM`，负责分类、选中、Pro 门控、添加/替换/删除和空态；不要把目录决策散落在 SwiftUI View。
- 抽取 `DecorationAssetResolver`，统一处理普通素材、`ratioSet` 选择和解码缓存。
- 将解码移出高频 SwiftUI `body`；缓存缩略图和当前画布素材，切换面板或释放编辑器时清理。
- 图片解码失败要记录素材 ID，并在面板单元显示不可用状态；不能让导出静默缺一层而仍提示成功。
- 购买成功后的权益变化沿用现有 `ProEntitlement`，不在装饰 VM 自建订阅状态。

### 7.3 SwiftUI

- `EditorGroupToolRow` 的 Decorate 列表开放 `.text / .sticker / .frame`，但只在目录对应类别非空且功能开关开启时显示贴纸/相框。
- 新建共用 `DecorationAssetCell`、`DecorationCategoryRail`，贴纸与相框只替换业务动作和预览宽高比。
- `EditorCanvasView` 的贴纸允许命中；相框只渲染、不命中。
- 选中框使用 `color/action/brand`，与 Figma 深铜红登记框一致；不继续使用当前默认蓝色选择框。
- iPad 使用右侧 Inspector，素材轨允许更宽但不改变单元状态和操作语义。

### 7.4 渲染与导出

- 预览和导出共享素材解析、比例选择和层级排序。
- 导出前预解码当前文档引用的素材；任何必需素材缺失时中止保存并给出可诊断错误。
- 九宫格渲染处理无效 inset 时可以安全降级，但 catalog 校验必须提前阻止正式素材进入该状态。
- JPEG 导出前以不透明底图合成；PNG 保留抠图产生的透明区域。相框/贴纸透明通道必须正确参与两种格式。

## 8. 实施里程碑

### M0：数据与渲染地基

- [ ] 修复快照字段、相框中心点、稳定合成顺序和画布重映射。（2026-08-15 代码落地：`EditorLayerSnapshot` 增可选 `resourcePath`/`visible` 且旧 JSON 容错、相框创建于画布中心并铺满、`orderedRenderLayers` 稳定序、`remapLayersForCanvas` 画布重映射；Kit 用例 WSL2 全绿，App VM 用例已写未跑，勾选待 Mac/CI XCTest）
- [ ] 完成共享素材解析器，使 preview/export 对 `ratioSet` 与 `ninePatch` 一致。（2026-08-15 代码落地：Kit `resolveDecorationResource` 为唯一比例选图入口，预览 `resolveDecorationSource` 与导出 `makeDecorationProvider` 同源调用，ninePatch 预览/导出共用 `computeNinePatchTiles` 分块；2026-08-16 补齐渲染级一致性测试：`EditorDecorationRenderTests` 以真实 `CoreImageEditorProcessing` 断导出像素，覆盖 §9.2 ①（stretch/ninePatch/ratioSet 各一）与 ②（透明贴纸 PNG/JPEG 边缘）；已写待 CI 跑绿）
- [ ] 补 catalog 分组 ID、本地化映射和素材错误诊断。（2026-08-15 分组稳定 ID `DecorationGroupIds` + `decoration.group.*` 本地化映射落地；2026-08-16 素材错误诊断达 §7.2/§7.4 规格，三层防线：导出预检（`save` 预解码必需素材，缺失即中止并报素材名）+ 渲染兕底（provider 返回 nil → `renderExport` 整体失败，不产出缺层成功品）+ 面板不可用态（预览解码失败上报 → 四态单元警示占位 + 添加/应用双保险门禁）；VM 用例 `testSaveAbortsWhenDecorationAssetMissing`/`testUnavailableDecorationBlockedFromDocument` 已写待 CI）
- [ ] MiLensKit 新增纯逻辑测试，App 层新增渲染单测。（Kit 侧已落地：`DecorationCompositionTests`/`DecorationCatalogGroupTests`/`DecorationAssetResolverTests` 等 WSL2 全绿；2026-08-16 App 渲染单测已补：`EditorDecorationRenderTests`（真实实现 + 像素断言）覆盖 §9.2 ①②③；④⑤ 由 `EditorViewModelTests`（手势合并 §9.2 ④ / Pro 门禁 §9.2 ⑤）守护，⑥ 作品分类回写由 `MediaLifecycleServiceTests` + VM 用例断言守护；已写待 CI）

### M1：可用交互与首批素材

- [ ] 实现共用素材单元、分类轨、空态和 Pro 锁定态。（2026-08-15 代码落地：`EditorDecorationPanelView` 三态素材单元 + 分组胶囊轨 + 真实空态 + Pro 锁定态与付费墙意图；2026-08-16 A1 扩为四态（Default/Selected/Locked/Unavailable，§7.2 面板不可用态）+ `a11y.editor.decoration.unavailable` 本地化 key；勾选待 Mac/CI XCTest）
- [ ] 实现相框单选替换/移除，以及贴纸添加/选择/手势/删除。（2026-08-15 代码落地：`EditorDecorationPanelVM` 相框同素材不重建/替换整体一次 push、贴纸上限 20 + 非阻断提示、点选/拖动/双指缩放旋转/头部删除动作；2026-08-16 补 §9.2 ④ 手势合并用例 `testDecorationGestureMergesIntoSingleUndoStep`；VM 用例已写未跑，勾选待 Mac/CI XCTest 与真机手势验收）
- [ ] 导入并校验 6 个相框、6 个贴纸；补齐简中源文案与其他已支持语言 key。（**未开始**：`catalog.json` 仍为空目录，入口按 §10 门禁自动隐藏贴纸/相框工具；待 Figma 素材交付后经 `tools/frame_import.py` 入库，本地化 key 随导入流程补齐）
- [ ] 接入撤销/重做、保存、返回未保存确认和付费墙。（2026-08-15 代码落地：面板操作恰好一次 push + 连续手势合并一条历史、保存成功 `resetHistory` 重置基线、`resolveBackAction` 未保存确认、`pendingPaywallItem` → 付费墙 sheet；勾选待 Mac/CI XCTest）

### M2：质量与扩充

- [ ] 贴纸扩展到 12–18 个，并完成主题一致性评审。
- [ ] 增加中心参考线、边界 clamp、VoiceOver 和 Reduce Motion 行为。（2026-08-15 代码落地：`snapAndClampLayerCenter` 6pt 吸附/离开立即释放/中心 clamp + 画布瞬时参考线 + 拖动累计 translation 缺陷修复 + 分组名/素材名动态 key VoiceOver 修复 + toast Reduce Motion；MiLensKit 9 用例 WSL2 全绿，App VM 6 用例已写未跑，勾选待 Mac/CI XCTest 与真机验收）
- [ ] 完成 iPhone/iPad、深色模式、Dynamic Type、低内存和多比例导出验收。
- [ ] 通过 Mac 模拟器、真机和 CI 质量门禁后再解除功能开关。

## 9. 测试与验收

### 9.1 MiLensKit XCTest

- 旧快照缺少新字段仍可解码；新快照往返后素材路径不丢失。
- 添加第二个相框替换第一个，撤销/重做能恢复正确素材。
- 相框中心点、尺寸、固定变换属性正确。
- 贴纸默认尺寸/位置、最大数量、缩放范围和边界 clamp 正确。
- 拖动中心吸附（6pt 阈值进入/离开立即释放、两轴独立）与中心 clamp、参考线决策正确。
- 画布横竖比变化后，相框铺满，贴纸和文字相对位置稳定。
- 稳定合成顺序不受添加顺序影响。
- 分组顺序、素材排序、Pro 可用性和空目录决策正确。
- `ratioSet` 精确、近似、缺失和非法比例路径有确定结果。

### 9.2 App 与渲染测试

- preview/export 对同一相框逐像素或快照基准一致，至少覆盖 `stretch`、`ninePatch`、`ratioSet` 各一项。
- 透明贴纸在 PNG/JPEG 导出中边缘无黑边、白边或错误预乘色。
- 素材缺失、catalog 解析失败、图片解码失败时不崩溃，也不生成缺层的“成功”作品。
- 连续拖动/缩放/旋转只增加一条撤销记录。
- 免费点击 Pro 素材只打开付费墙，不改变当前相框或新增贴纸。
- 保存后产物正确回写并进入「作品」分类。

### 9.3 人工与真机验收

- iPhone 390×844pt 参考节奏与 Figma 一致；小屏不压缩画布到不可编辑。
- iPad 横竖屏切换后图层不漂移，相框不变形。
- 1:1、3:4、4:3、16:9、9:16 五类照片均验证预览与导出。
- 20 个贴纸 + 一个相框 + 文字图层下，拖动和缩放保持流畅，保存期间内存无无界增长。
- VoiceOver 可读出分类、素材名、选中/锁定状态、删除/移除动作。
- Reduce Motion 下没有依赖动画才能理解的状态变化。

## 10. 发布门禁

只有同时满足以下条件才可展示贴纸/相框入口：

- `catalog.json` 至少包含一个通过校验的对应类别素材。
- 历史恢复、画布重映射和 preview/export 一致性测试通过。
- 素材版权和授权记录完成，且无真实用户照片进入仓库。
- 本地化检查、文件规模守卫、MiLensKit 全量 XCTest 和 App XCTest 通过。
- 已在至少一台 iPhone 真机验证手势、内存和导出；iPad 关键尺寸完成模拟器或真机检查。

未满足任一项时，保持真实空态或关闭入口，不把 Figma 演示素材描述为已上线能力。
