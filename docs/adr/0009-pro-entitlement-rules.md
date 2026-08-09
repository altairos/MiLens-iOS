# ADR-0009：V1 MiLens Pro 情感付费规则

- 状态：已采纳
- 日期：2026-08-09
- 范围：付费墙、路由门控、设置页、App Store 元数据与测试

## 决策

V1 采用单一二元权益 `ProEntitlementStore.isPro`，但免费用户可以完整体验核心情感链路：

| 能力 | 免费版 | MiLens Pro |
|---|---|---|
| 宠物档案 | 1 个 | 最多 20 个 |
| 拼豆图纸生成 | 每个本地自然日 5 次 | 不限次数 |
| 基础图片编辑器 | 无限使用 | 无限使用 |
| 成长时间线 | 首次打开后 14 天完整体验，之后最近 365 天 | 全部历史 |
| 宠物卡片 | 免费 | 免费 |

拼豆配额只在生成成功后扣除；失败、取消和进入编辑器不扣次数。用户首次真正打开时间线后有 14 天完整历史体验，第 10 天起温和提醒；体验期结束后免费用户只看到最近一年。时间线旧数据永不删除，并显示 Pro 解锁提示。

## 未来计划权益

高级创作模板与高清导出属于 V1.0 计划能力，不得伪装成当前已经交付的功能。付费墙和 App Store 元数据可以提前宣传近期计划能力，但必须明确标注“计划加入/预计上线”，不得让用户误以为当前版本已经提供；功能上线后再同步更新为正式权益文案。

## 实现映射

- `MiLens/Services/Store/CommercialRules.swift`：配额、上限和时间线窗口。
- `MiLens/Services/Store/ProFeature.swift`：付费墙/设置页当前 Pro 功能清单。
- `MiLens/ViewModels/PetProfileViewModel.swift`：1/20 宠物档案上限。
- `MiLens/ViewModels/BeadViewModel.swift`：每日 5 次成功生成配额。
- `MiLens/ViewModels/TimelineViewModel.swift`、`TimelineAccessLogic`：365 天时间线窗口。
- `MiLensTests/CommercialRulesTests.swift`、`MiLensKit/Tests/MiLensKitTests/BeadFlowLogicTests.swift`：商业规则回归测试。
- `docs/AppStore-metadata.md`：商店和审核文案；未实现权益必须标注为未来计划，不得写成当前已交付能力。
