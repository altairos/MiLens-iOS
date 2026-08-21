# MiLens iOS 自定义字体

本目录存放 App 内嵌的标题（display）字体文件。字体选择与用法见 [UI-DESIGN.md](../../../UI-DESIGN.md) §2。

## 字体清单

| 文件 | PostScript 名 | 字重 | 用途 | 体积 |
|---|---|---|---|---|
| `LXGWWenKaiGB-Regular.ttf` | `LXGWWenKai-Regular` | Regular | 简体中文 display 标题 | 3.27 MB |
| `LXGWWenKaiTC-Regular.ttf` | `LXGWWenKaiTC-Regular` | Regular | 繁体中文（台湾）display 标题 | 0.86 MB |
| `JyunsaiKaai-Regular.ttf` | `JyunsaiKaai` | Regular | 繁体中文（香港）display 标题 | 1.14 MB |
| `KleeOne-Regular.ttf` | `KleeOne-Regular` | Regular | 日文 display 标题 | 1.35 MB |
| `Fraunces-Bold.ttf` | `Fraunces-Bold` | Bold (700) | 英/法/德文 display 大标题（Latin Extended） | 62.6 KB |
| `Fraunces-Semibold.ttf` | `Fraunces-Semibold` | Semibold (600) | 英/法/德文 display 次级标题（Latin Extended） | 62.6 KB |
| `JacquesFrancois-Regular.ttf` | `JacquesFrancois-Regular` | Regular | 编辑式衬线 overline（「LIFE 02 · …」「ARCHIVE OUTPUT」10pt 小标） | 60 KB |

**合计约 6.81 MB。**

## 字符集子集化（体积控制）

完整字体体积过大，已按 App 当前本地化文案和必要符号子集化：

- **霞鹜文楷**：保留 GB2312 全集（6763 汉字）+ ASCII + 常用中文/数学标点，共 6976 字符。压缩 86.6%（24.39 MB → 3.27 MB）。覆盖简体中文 V1.0 全部文案需求。
- **霞鶩文楷 TC / 芫茜雅楷 / Klee One**：根据 `.xcstrings` 中的本地化文案生成区域标题子集，并保留 Latin Extended、符号和标点。
- **Fraunces**：保留 Latin Extended（法语重音、德语变音符号与 ß）及常用标点，每字重约 62.6 KB。
- **Jacques Francois**：单一 Regular 字重、仅拉丁字符，本身仅 ~60 KB，无需子集化，整字体嵌入。

> 如需新增本地化字符或用户可输入的生僻字，用 `fontTools` 重新子集化（见下方「重新生成」），不要直接替换为完整字体。当前标题子集不保证覆盖任意用户宠物名，发布前需补充字符集并验证 Core Text fallback。

## 重新生成子集

源字体下载 + 子集化脚本见 `.tmp-fonts/`（已 gitignore）。重新生成流程：

```powershell
# 1. 将官方源字体放入 .tmp-fonts/sources/（该目录已 gitignore）
# 2. 生成所有区域标题字体子集
python tools/subset-display-fonts.py
```

依赖：Python 3.12+ + fontTools（`pip install fonttools`）。

## 许可与合规

所有字体均基于 **SIL Open Font License 1.1**，允许免费商用、嵌入 App 分发。合规要求：

- ✅ 可随 App 分发、嵌入、子集化
- ❌ 禁止单独出售字体文件
- ❌ 衍生字体禁用各上游字体的保留名称
- 📄 许可证原文：[OFL-LXGWWenKai.txt](OFL-LXGWWenKai.txt)、[OFL-LXGWWenKaiTC.txt](OFL-LXGWWenKaiTC.txt)、[OFL-Klee.txt](OFL-Klee.txt)、[OFL-JyunsaiKaai.txt](OFL-JyunsaiKaai.txt)、[OFL-Fraunces.txt](OFL-Fraunces.txt)、[OFL-JacquesFrancois.txt](OFL-JacquesFrancois.txt)

「关于」页需注明字体来源与许可（OFL 要求）。

## 字体来源

- **霞鹜文楷 LXGW WenKai** v1.522 — https://github.com/lxgw/LxgwWenKai （作者：LXGW，基于 Fontworks Klee）
- **霞鶩文楷 TC LXGW WenKai TC** — https://github.com/lxgw/LxgwWenKaiTC （作者：LXGW，繁體字形，基于 Fontworks Klee）
- **芫茜雅楷 JyunsaiKaai** — https://github.com/ItMarki/jyunsaikaai （作者：ItMarki，香港字形，基于 Klee/Iansui/LXGW WenKai）
- **Klee One** — https://github.com/fontworks-fonts/Klee （作者：Fontworks）
- **Fraunces** — https://github.com/undercasetype/Fraunces （作者：Undercase Type，Google Fonts 收录版可变字体）
- **Jacques Francois** — https://github.com/google/fonts/tree/main/ofl/jacquesfrancois （作者：Cyreal，Google Fonts 收录，SIL OFL）
