#!/usr/bin/env python3
"""MiLens UI token 纪律 lint —— 守护 UI-DESIGN.md §3 / §4 token 边界。

检测两类违规（退出码非 0 即存在 ERROR）：

ERROR（硬门禁，对应质量门禁第 1 条「色值只用 milensXxx token」）：
  - Color(.system...)          系统语义色当视觉色
  - Color.<named>              命名彩色当视觉色（red/orange/green/yellow/pink/purple/...）
  - .foregroundStyle(.<named>) 彩色前景（同上命名集合，排除 white/black/primary/secondary）
  - .foregroundColor(.<named>) 同上旧 API
  - Color(srgb:)/Color(red:)   字面 sRGB 色值（业务动态色需加 // ui-token:ok 注释豁免）

INFO（建议项，对应门禁第 2 条渐进收敛，不阻断）：
  - .font(.system(size: <数字字面量>))   硬编码字号（SF Symbol 图标尺寸用 Sizing.* 变量）
  - .foregroundStyle(.white)/Color.white.opacity  照片/黑底画布叠加，需人工确认场景合理

豁免：行尾或上一行带 `// ui-token:ok` 注释的行不报错（用于业务数据动态色，
如拼豆格子 Color(red: Double(row.rgb.r)...)、文字图层 Color(hexString:)）。

扫描范围：MiLens/ 下全部 .swift，排除 Theme/（token 定义处含合法 editorial 字面色）。

用法：
  python tools/check-ui-tokens.py
  python tools/check-ui-tokens.py --root MiLens/Views/MiLens/Components
退出码：0 = 无 ERROR；1 = 存在 ERROR。

详见 docs/UI-Rework计划.md 批次 A。
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# --------------------------------------------------------------------------- #
# 检测规则
# --------------------------------------------------------------------------- #

# 命名彩色集合（当视觉色用即违规；white/black/primary/secondary/clear 不在此列，场景合理）
NAMED_COLORS = (
    "red", "orange", "green", "blue", "gray", "grey", "yellow",
    "pink", "purple", "brown", "indigo", "teal", "mint", "cyan",
)

# ERROR 模式
ERROR_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("Color(.system...) 系统语义色", re.compile(r"Color\(\s*\.system")),
    ("Color(.<named>) 命名彩色", re.compile(r"Color\(\s*\.(?:" + "|".join(NAMED_COLORS) + r")\b")),
    ("Color.<named> 命名彩色", re.compile(r"\bColor\.(?:" + "|".join(NAMED_COLORS) + r")\b")),
    (".foregroundStyle(.<named>) 彩色前景", re.compile(r"\.foregroundStyle\(\s*\.(?:" + "|".join(NAMED_COLORS) + r")\b")),
    (".foregroundColor(.<named>) 彩色前景", re.compile(r"\.foregroundColor\(\s*\.(?:" + "|".join(NAMED_COLORS) + r")\b")),
    ("Color(red:)/Color(srgb:) 字面色值", re.compile(r"Color\(\s*(?:red:|srgb:)")),
]

# INFO 模式
INFO_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    (".font(.system(size: 数字)) 硬编码字号", re.compile(r"\.font\(\s*\.system\(\s*size:\s*\d")),
    (".foregroundStyle(.white) / Color.white.opacity 白色叠加", re.compile(r"(?:\.foregroundStyle\(\s*\.white|Color\.white\.opacity)")),
]

EXEMPT_MARK = "ui-token:ok"


def scan_file(path: Path) -> tuple[list[str], list[str]]:
    """返回 (errors, infos)，每条含「路径:行号: 描述」."""
    errors: list[str] = []
    infos: list[str] = []
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    for idx, line in enumerate(lines, start=1):
        # 豁免：当前行或上一行带 ui-token:ok
        ctx = (lines[idx - 2] if idx >= 2 else "") + "\n" + line
        if EXEMPT_MARK in ctx:
            continue
        for desc, pat in ERROR_PATTERNS:
            if pat.search(line):
                errors.append(f"{path}:{idx}: ERROR {desc}: {line.strip()}")
        for desc, pat in INFO_PATTERNS:
            if pat.search(line):
                infos.append(f"{path}:{idx}: INFO  {desc}: {line.strip()}")
    return errors, infos


def main() -> int:
    parser = argparse.ArgumentParser(description="MiLens UI token 纪律 lint。")
    parser.add_argument(
        "--root", default="MiLens",
        help="扫描根目录（默认 MiLens，即 App target 源码）。",
    )
    parser.add_argument(
        "--exclude", action="append", default=["Theme"],
        help="排除的子目录名（默认 Theme；可多次指定）。",
    )
    parser.add_argument(
        "--strict", action="store_true",
        help="INFO 也计入失败退出码（默认只 ERROR 计失败）。",
    )
    args = parser.parse_args()

    root = Path(args.root)
    if not root.is_dir():
        # 兼容从仓库根之外调用
        alt = Path(__file__).resolve().parent.parent / args.root
        if alt.is_dir():
            root = alt
        else:
            print(f"扫描根目录不存在: {args.root}", file=sys.stderr)
            return 2

    excludes = set(args.exclude)
    swift_files = sorted(
        p for p in root.rglob("*.swift")
        if not any(part in excludes for part in p.relative_to(root).parts[:-1])
    )

    all_errors: list[str] = []
    all_infos: list[str] = []
    for f in swift_files:
        e, i = scan_file(f)
        all_errors.extend(e)
        all_infos.extend(i)

    if all_infos:
        print(f"── INFO（建议项，{len(all_infos)} 处）──")
        for line in all_infos:
            print(line)
        print()

    if all_errors:
        print(f"── ERROR（token 硬门禁违规，{len(all_errors)} 处）──")
        for line in all_errors:
            print(line)
        print(f"\n失败：{len(all_errors)} 处 ERROR。色值请改用 Color.milens* token，"
              f"业务动态色在行尾加 // ui-token:ok 豁免。")
        return 1

    if args.strict and all_infos:
        print(f"\n失败（--strict）：{len(all_infos)} 处 INFO。")
        return 1

    print(f"通过：{len(swift_files)} 个文件扫描，0 ERROR"
          f"（{len(all_infos)} INFO 为建议项）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
