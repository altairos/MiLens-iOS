# MiLens iOS 自定义字体

本目录存放 App 内嵌的自定义字体文件。字体选择与用法见 [UI-DESIGN.md](../../../UI-DESIGN.md) §2。

## 字体清单

| 文件 | PostScript 名 | 字重 | 用途 | 体积 |
|---|---|---|---|---|
| `LXGWWenKaiGB-Regular.ttf` | `LXGWWenKai-Regular` | Regular | 中文 display 标题（问候、档案名、区块标题） | 3.27 MB |
| `Fraunces-Bold.ttf` | `Fraunces-Bold` | Bold (700) | 英文 display 大标题（品牌名、英文标语） | 22.5 KB |
| `Fraunces-Semibold.ttf` | `Fraunces-Semibold` | Semibold (600) | 英文 display 次级标题 | 22.5 KB |
| `JacquesFrancois-Regular.ttf` | `JacquesFrancois-Regular` | Regular | 编辑式衬线 overline（「LIFE 02 · …」「ARCHIVE OUTPUT」10pt 小标） | 60 KB |

**合计约 3.37 MB。**

## 字符集子集化（体积控制）

完整字体体积过大（霞鹜文楷 24 MB），已子集化：

- **霞鹜文楷**：保留 GB2312 全集（6763 汉字）+ ASCII + 常用中文/数学标点，共 6976 字符。压缩 86.6%（24.39 MB → 3.27 MB）。覆盖简体中文 V1.0 全部文案需求。
- **Fraunces**：保留基本拉丁（ASCII），每字重 22.5 KB。
- **Jacques Francois**：单一 Regular 字重、仅拉丁字符，本身仅 ~60 KB，无需子集化，整字体嵌入。

> 如需新增字符（繁体、生僻字），用 `fontTools` 重新子集化（见下方「重新生成」），不要直接替换为完整字体。

## 重新生成子集

源字体下载 + 子集化脚本见 `.tmp-fonts/`（已 gitignore）。重新生成流程：

```powershell
# 1. 下载源字体（霞鹜文楷 v1.522 + Fraunces 可变字体）到 .tmp-fonts/
# 2. 子集化
cd .tmp-fonts
python subset.py          # 霞鹜文楷 GB2312 子集
python fraunces_fix.py    # Fraunces 全轴静态化 + name 修正 + 拉丁子集
# 3. 复制输出到 Resources/Fonts/
```

依赖：Python 3.12+ + fontTools（`pip install fonttools`）。

## 许可与合规

两款字体均基于 **SIL Open Font License 1.1**，允许免费商用、嵌入 App 分发。合规要求：

- ✅ 可随 App 分发、嵌入、子集化
- ❌ 禁止单独出售字体文件
- ❌ 衍生字体禁用保留名称「LXGW」「霞鹜」「Fraunces」「Jacques Francois」
- 📄 许可证原文：[OFL-LXGWWenKai.txt](OFL-LXGWWenKai.txt)、[OFL-Fraunces.txt](OFL-Fraunces.txt)、[OFL-JacquesFrancois.txt](OFL-JacquesFrancois.txt)

「关于」页需注明字体来源与许可（OFL 要求）。

## 字体来源

- **霞鹜文楷 LXGW WenKai** v1.522 — https://github.com/lxgw/LxgwWenKai （作者：LXGW，基于 Fontworks Klee）
- **Fraunces** — https://github.com/undercasetype/Fraunces （作者：Undercase Type，Google Fonts 收录版可变字体）
- **Jacques Francois** — https://github.com/google/fonts/tree/main/ofl/jacquesfrancois （作者：Cyreal，Google Fonts 收录，SIL OFL）
