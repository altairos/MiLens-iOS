#!/usr/bin/env python3
"""字体子集化脚本 —— MiLens iOS。

霞鹜文楷：完整 TTF (24MB) → GB2312 + ASCII + 常用标点 子集 (~3-4MB)。
Fraunces：可变字体 → varLib instancer 生成 Bold/Semibold 静态 → 拉丁子集 (~30KB)。

许可：两款字体均 SIL OFL 1.1，可嵌入 App 分发，禁止单独出售字体文件。
"""
from __future__ import annotations
import subprocess
import sys
from pathlib import Path

TMP = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent

SUBSET = [sys.executable, "-m", "fontTools.subset"]
INSTANCER = [sys.executable, "-m", "fontTools.varLib.instancer"]


def gen_charset_text() -> str:
    """生成 GB2312 + ASCII + 常用标点 的字符文本。"""
    chars: set[str] = set()
    # 基本拉丁（ASCII 可见字符 + 空格）
    for cp in range(0x20, 0x7F):
        chars.add(chr(cp))
    # 额外常用符号（全角空格、中文标点、数学符号等）
    extras = (
        "　，。！？、：；""''《》【】（）—…·•→←↑↓℃°±×÷"
        "√π★☆○●△▲▽▼◇◆□■♪♫✓✗♥☺☻♦♣♠"
    )
    for ch in extras:
        chars.add(ch)
    # GB2312 覆盖的 CJK 统一汉字（用 gb2312 codec 反查）
    for cp in range(0x4E00, 0x9FFF + 1):
        ch = chr(cp)
        try:
            ch.encode("gb2312")
            chars.add(ch)
        except UnicodeEncodeError:
            pass
    # CJK 标点符号区（U+3000-U+303F）
    for cp in range(0x3000, 0x3040):
        chars.add(chr(cp))
    # GB2312 符号区中可编码的通用标点
    for cp in range(0x2000, 0x2070):
        ch = chr(cp)
        try:
            ch.encode("gb2312")
            chars.add(ch)
        except UnicodeEncodeError:
            pass
    return "".join(sorted(chars))


def subset_wenkai() -> tuple[Path, float, float]:
    """子集化霞鹜文楷 Regular。返回 (输出路径, 源体积MB, 子集体积MB)。"""
    src = TMP / "LXGWWenKai-Regular.ttf"
    out = TMP / "LXGWWenKaiGB-Regular.ttf"
    text_file = TMP / "wenkai-chars.txt"

    text = gen_charset_text()
    text_file.write_text(text, encoding="utf-8")
    src_mb = src.stat().st_size / 1048576

    print(f"[霞鹜文楷] 字符集 {len(text)} 字符，源 {src_mb:.2f} MB")
    subprocess.run([
        *SUBSET, str(src),
        f"--text-file={text_file}",
        f"--output-file={out}",
        "--notdef-outline",
        "--recalc-bounds",
        "--layout-features=*",
        "--name-IDs=*",
        "--drop-tables+=DSIG",
    ], check=True)
    out_mb = out.stat().st_size / 1048576
    print(f"[霞鹜文楷] 子集 {out_mb:.2f} MB（压缩 {(1 - out_mb / src_mb) * 100:.1f}%）")
    return out, src_mb, out_mb


def instance_and_subset_fraunces() -> list[tuple[str, float]]:
    """Fraunces 可变字体 → 静态字重 → 拉丁子集。"""
    vf = TMP / "Fraunces-VF.ttf"
    results: list[tuple[str, float]] = []
    latin_text = TMP / "latin-chars.txt"
    # 拉丁字符集（大小写 + 数字 + 常用标点）
    latin = "".join(chr(c) for c in range(0x20, 0x7F))
    latin_text.write_text(latin, encoding="utf-8")

    for wght, name in [(700, "Fraunces-Bold.ttf"), (600, "Fraunces-Semibold.ttf")]:
        static = TMP / f"Fraunces-static-{wght}.ttf"
        out = TMP / name
        # 1. instantiate 静态字重
        subprocess.run([
            *INSTANCER, str(vf), f"wght={wght}",
            f"--output={static}",
        ], check=True)
        src_kb = static.stat().st_size / 1024
        # 2. 拉丁子集
        subprocess.run([
            *SUBSET, str(static),
            f"--text-file={latin_text}",
            f"--output-file={out}",
            "--notdef-outline",
            "--recalc-bounds",
            "--layout-features=*",
            "--name-IDs=*",
            "--drop-tables+=DSIG",
        ], check=True)
        out_kb = out.stat().st_size / 1024
        print(f"[Fraunces {wght}] 静态 {src_kb:.1f} KB → 拉丁子集 {out_kb:.1f} KB")
        results.append((name, out_kb))
    return results


def main() -> None:
    wenkai_out, wenkai_src_mb, wenkai_out_mb = subset_wenkai()
    fraunces = instance_and_subset_fraunces()
    total_kb = wenkai_out_mb * 1024 + sum(kb for _, kb in fraunces)
    print("\n=== 体积汇总 ===")
    print(f"霞鹜文楷 GB Regular: {wenkai_out_mb:.2f} MB")
    for name, kb in fraunces:
        print(f"{name}: {kb:.1f} KB")
    print(f"字体总计: {total_kb / 1024:.2f} MB ({total_kb:.0f} KB)")


if __name__ == "__main__":
    main()
