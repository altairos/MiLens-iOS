#!/usr/bin/env python3
"""Fraunces 字重修正 —— 固定全部可变轴 + 重写 name 表 + 拉丁子集。

修正 subset.py 的问题：instancer 只固定 wght 导致残留可变轴与冲突的 PostScript 名。
"""
from __future__ import annotations
import subprocess
import sys
from pathlib import Path

from fontTools.ttLib import TTFont

TMP = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
PY = sys.executable

# Fraunces 轴默认值：opsz=144（display 大标题光学尺寸），SOFT=0，WONK=0
AXES = {"wght": None, "opsz": "144", "SOFT": "0", "WONK": "0"}  # wght 每次不同

# 需要重写的 name 记录（platform 3/Windows + platform 1/Mac 双设）
NAME_MAP = {
    700: {  # Bold
        1: "Fraunces", 2: "Bold", 4: "Fraunces Bold",
        6: "Fraunces-Bold", 16: "Fraunces", 17: "Bold",
    },
    600: {  # Semibold
        1: "Fraunces", 2: "Semibold", 4: "Fraunces Semibold",
        6: "Fraunces-Semibold", 16: "Fraunces", 17: "Semibold",
    },
}


def fix_name(ttf: TTFont, weight: int) -> None:
    """重写 name 表核心记录，删除可变字体命名实例残留。"""
    nb = ttf["name"]
    records = NAME_MAP[weight]
    # 删除所有需要重写的 nameID + nameID 25（Variations PS Prefix，可变残留）
    drop_ids = set(records.keys()) | {3, 25}
    nb.names = [r for r in nb.names if r.nameID not in drop_ids]
    # 重新设置（Windows platform 3 + Mac platform 1，iOS 优先读 platform 3）
    for nid, val in records.items():
        nb.setName(val, nid, 3, 1, 0x409)   # Windows Unicode BMP en-US
        nb.setName(val, nid, 1, 0, 0)        # Mac Roman English（兼容）
    # Unique identifier（nameID 3）
    nb.setName(f"MiLens-{records[6]};Sub-set", 3, 3, 1, 0x409)


def main() -> None:
    vf = TMP / "Fraunces-VF.ttf"
    latin_text = TMP / "latin-chars.txt"
    if not latin_text.exists():
        latin_text.write_text("".join(chr(c) for c in range(0x20, 0x7F)), encoding="utf-8")

    for wght, fname in [(700, "Fraunces-Bold.ttf"), (600, "Fraunces-Semibold.ttf")]:
        static = TMP / f"Fraunces-static-{wght}-full.ttf"
        out = TMP / fname
        # 1. instancer 固定全部 4 轴 → 完全静态字体
        subprocess.run([
            PY, "-m", "fontTools.varLib.instancer", str(vf),
            f"wght={wght}", "opsz=144", "SOFT=0", "WONK=0",
            f"--output={static}",
        ], check=True)
        # 2. 修正 name 表
        ttf = TTFont(static)
        fix_name(ttf, wght)
        ttf.save(static)
        # 3. 拉丁子集（name 已修正，subset 会保留）
        subprocess.run([
            PY, "-m", "fontTools.subset", str(static),
            f"--text-file={latin_text}",
            f"--output-file={out}",
            "--notdef-outline", "--recalc-bounds",
            "--layout-features=*", "--name-IDs=*",
            "--drop-tables+=DSIG",
        ], check=True)
        # 4. 验证 PostScript 名
        v = TTFont(out)
        ps = v["name"].getName(6, 1, 0, 0) or v["name"].getName(6, 3, 1, 0x409)
        kb = out.stat().st_size / 1024
        print(f"[Fraunces {wght}] {fname} → {kb:.1f} KB, PostScript={ps}")


if __name__ == "__main__":
    main()
