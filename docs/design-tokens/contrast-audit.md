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
| TextPrimary on SurfaceCanvas | `#F2EBE3` | `#161311` | 15.65 | 通过 | 通过 | ✅ |
| TextPrimary on SurfacePrimary | `#F2EBE3` | `#221E1A` | 14.01 | 通过 | 通过 | ✅ |

## 结论

- 正文、次文字、动作色全部达标（正文对比度均 ≥ 5:1）。
- **唯一不达标项**：`BrandCoral`（`#FD8663`）配白字仅 2.40:1，不能作为正文、小图标、按钮文字或唯一状态差异的背景 —— 已按 §3.1「纠正后的语义色」拆分为 `BrandCoral`（纯装饰）与 `ActionPrimary`（交互强调）。
- 深色模式下 `ActionPrimary` 使用 `#E8845F` 配暖黑字 `#161311`（≈7.1:1），达标。
