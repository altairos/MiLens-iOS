# MiLens 色彩对比度审计（WCAG AA）

> 由 design-token-bridge `validate_contrast`（level AA）生成，色值源 `UI-DESIGN.md` §3.1。

## Light 主题

| 配对 | 前景 | 背景 | 对比度 | AA 正文 (≥4.5) | AA 大字 (≥3) | 结论 |
|---|---|---:|---|---|---|---|
| TextPrimary on SurfaceCanvas | `#1F1B18` | `#FAF8F5` | 16.13 | 通过 | 通过 | ✅ |
| TextPrimary on SurfacePrimary | `#1F1B18` | `#FFFFFF` | 17.10 | 通过 | 通过 | ✅ |
| OnActionPrimary on ActionPrimary | `#FFFFFF` | `#BC4727` | 5.16 | 通过 | 通过 | ✅ |
| 白字 on BrandCoral | `#FFFFFF` | `#FD8663` | 2.40 | 不通过 | 不通过 | ❌ |

## Dark 主题

| 配对 | 前景 | 背景 | 对比度 | AA 正文 (≥4.5) | AA 大字 (≥3) | 结论 |
|---|---|---:|---|---|---|---|
| TextPrimary on SurfaceBackground | `#F2EBE3` | `#161311` | 15.65 | 通过 | 通过 | ✅ |
| TextPrimary on SurfaceCard | `#F2EBE3` | `#221E1A` | 14.01 | 通过 | 通过 | ✅ |
| TextPrimary on SurfaceElevated | `#F2EBE3` | `#2C2722` | 12.51 | 通过 | 通过 | ✅ |
| TextPrimary on SurfaceGrouped | `#F2EBE3` | `#1C1916` | 14.82 | 通过 | 通过 | ✅ |
| TextSecondary on SurfaceBackground | `#B5A89C` | `#161311` | 7.97 | 通过 | 通过 | ✅ |
| TextSecondary on SurfaceCard | `#B5A89C` | `#221E1A` | 7.13 | 通过 | 通过 | ✅ |
| TextTertiary on SurfaceBackground | `#9B8B80` | `#161311` | 5.64 | 通过 | 通过 | ✅ |
| TextTertiary on SurfaceCard | `#9B8B80` | `#221E1A` | 5.04 | 通过 | 通过 | ✅ |
| TextTertiary on SurfaceElevated | `#9B8B80` | `#2C2722` | 4.50 | 通过 | 通过 | ✅ |
| TextOnActionPrimary on ActionPrimary | `#161311` | `#E8845F` | 6.96 | 通过 | 通过 | ✅ |
| TextOnAccent on AccentColor | `#FFFFFF` | `#E8845F` | 2.66 | 不通过 | 不通过 | ❌ |
| AccentColor on SurfaceBackground | `#E8845F` | `#161311` | 6.96 | 通过 | 通过 | ✅ |
| DogAccent on SurfaceCard | `#D19E43` | `#221E1A` | 6.85 | 通过 | 通过 | ✅ |
| Success on SurfaceCard | `#72C998` | `#221E1A` | 8.29 | 通过 | 通过 | ✅ |
| Danger on SurfaceCard | `#EF7D76` | `#221E1A` | 6.19 | 通过 | 通过 | ✅ |
| Warning on SurfaceCard | `#F0B85A` | `#221E1A` | 9.23 | 通过 | 通过 | ✅ |
| MemoryMarker on SurfaceCard | `#91857A` | `#221E1A` | 4.61 | 通过 | 通过 | ✅ |

### 常暗编辑面（无暗色变体，两主题渲染同值，按单一值审计）

| 配对 | 前景 | 背景 | 对比度 | 结论 |
|---|---|---:|---|---|
| DarkroomText on DarkroomBadge | `#F1D8CA` | `#1D1815` | 12.91 | ✅ |
| EditorialInk on EditorialPaper | `#1B1612` | `#F4EEE4` | 15.55 | ✅ |
| EditorialCopper on EditorialPaper | `#B04125` | `#F4EEE4` | 5.01 | ✅ |
| TextPrimary(D) on StudioSurface | `#F2EBE3` | `#221D1A` | 14.12 | ✅ |
| TextPrimary(D) on DialSurface | `#F2EBE3` | `#7C3F30` | 6.81 | ✅ |
| PaywallSubtitle on PaywallGradientStart | `#D4CCC4` | `#0D0A09` | 12.43 | ✅ |
| ProBody on ProCardDark | `#B5A89C` | `#14110F` | 8.10 | ✅ |

## 结论

- 正文、次文字、三级文字、动作色、语义色全部达标。
- **Light 唯一不达标**：`BrandCoral`（`#FD8663`）配白字 2.40:1 → 已按 §3.1 拆分为纯装饰 `BrandCoral` 与交互 `ActionPrimary #BC4727`（白字 5.16:1）。
- **Dark 一处不达标**：
  1. 白字 on `AccentColor #E8845F` 2.66:1 → 与 Light 同类债；白字永不落在珊瑚上，交互改用 `ActionPrimary` 或暗字。
- `TextTertiary` 暗侧已由 `#7A6F64` 调亮至 `#9B8B80`，SurfaceBackground 5.64 / SurfaceCard 5.04 / SurfaceElevated 4.50，全部 ≥4.5 达标。
- `Border` / `Separator` 暗侧 1.44 / 1.14:1 属装饰性结构、可接受；但任何依赖边框色单独表达的状态（选中 / 错误）需另加非颜色提示。
- 常暗编辑面（Studio / Darkroom / Dial / Seal / Paywall）全部达标，`DogAccent` 金黄在暗侧 6.85:1 达标。
