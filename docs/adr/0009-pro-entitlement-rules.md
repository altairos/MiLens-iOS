# ADR-0009：V1 MiLens Pro 权益规则

- 状态：已采纳
- 日期：2026-08-09
- 范围：付费墙、路由门控、设置页、App Store 元数据与测试

## 决策

V1 采用单一二元权益：`ProEntitlementStore.isPro`。Pro 只解锁以下两项能力：

1. 完整拼豆工作室：多种风格、配色方案，以及 A4 图纸导出/分享。
2. 完整图片编辑器：裁切、调色、抠图与文字工具。

以下能力保持免费：宠物档案（沿用现有技术上限 20 个）、相册整理/扫描/质量评分/重复分组、成长时间线，以及宠物卡片创建和导出。

家庭共享是 StoreKit 产品配置提供的分发能力，不作为 App 内独立功能或额外门控；对外文案只能表述为 Apple 提供的家庭共享支持。

## 不承诺的权益

当前实现没有 Pro 专属的宠物数量上限、模板目录或独立“高清导出”档位，因此不再对外承诺“无限宠物档案”“高级创作模板”或模糊的“全部功能”。新增权益必须先更新本 ADR、`ProFeature`、门控测试和 App Store 元数据。

## 实现映射

- `MiLens/Services/Store/ProFeature.swift`：Pro 功能清单与共享文案键。
- `MiLens/App/Route.swift`：路由是否需要 Pro 的纯规则。
- `MiLens/App/RootTabView.swift`：统一路由门控。
- `MiLens/Views/Settings/PaywallView.swift`、`SettingsView.swift`：同一功能清单的展示。
- `MiLensTests/RouteTests.swift`：免费/Pro 路由回归测试。
- `docs/AppStore-metadata.md`：审核和商店文案的运营稿。
