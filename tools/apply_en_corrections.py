# -*- coding: utf-8 -*-
"""把 en_corrections.py 的复审修正同步写入三个 .xcstrings（幂等）。

值替换仅动 en 的 stringUnit.value；结构操作（删死 key / 拆分新 key）
按 en_corrections.DELETE_KEYS / NEW_ENTRIES 执行。写回复用
localization.py 的 Xcode 风格序列化，保证格式与 Xcode 原生输出一致。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "tools"))

import localization as loc
from en_corrections import CORRECTIONS, DELETE_KEYS, NEW_ENTRIES

PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?[-+0-9.]*[a-zA-Z@]+")

FILES = [
    REPO_ROOT / "MiLens" / "Resources" / "Localizable.xcstrings",
    REPO_ROOT / "MiLensWidget" / "Localizable.xcstrings",
    REPO_ROOT / "MiLens" / "Resources" / "InfoPlist.xcstrings",
]


def main() -> int:
    replaced: list[tuple[str, str]] = []
    deleted: list[str] = []
    added: list[str] = []
    errors: list[str] = []

    for path in FILES:
        data = loc.load_xcstrings(path)
        strings = data.get("strings", {})
        src_lang = data.get("sourceLanguage", "zh-Hans")
        dirty = False

        # 1) 值替换（仅 plain 条目；替换前校验占位符与 zh 源文一致）
        for key, new_val in CORRECTIONS.items():
            if key not in strings:
                continue
            entry = strings[key]
            src_loc = entry.get("localizations", {}).get(src_lang, {})
            en_loc = entry.get("localizations", {}).get("en", {})
            # 字面量 key 条目可无 zh-Hans localization（key 即源文，回退用 key）
            src_val = src_loc.get("stringUnit", {}).get("value", key)
            if "variations" in en_loc or "variations" in src_loc:
                errors.append(f"[{path.name}] {key}: plural/unexpected shape, skipped")
                continue
            src_phs = set(PLACEHOLDER_RE.findall(src_val))
            new_phs = set(PLACEHOLDER_RE.findall(new_val))
            if src_phs != new_phs:
                errors.append(f"[{path.name}] {key}: placeholders {new_phs} != source {src_phs}")
                continue
            old_val = en_loc.get("stringUnit", {}).get("value")
            if old_val == new_val:
                # 幂等重跑：值已一致视为已生效，计入 replaced 供终检
                replaced.append((path.name, key))
                continue
            en_loc["stringUnit"] = {"state": "translated", "value": new_val}
            entry.setdefault("localizations", {})["en"] = en_loc
            replaced.append((path.name, key))
            dirty = True

        # 2) 删除死 key（仅 App 主表）
        for key in DELETE_KEYS:
            if key in strings:
                del strings[key]
                deleted.append(key)
                dirty = True

        # 3) 新增拆分 key：先从所有文件清理（自愈误加），仅 App 主表写入；
        #    注意 Widget 表文件名同为 Localizable.xcstrings，须按完整路径判断；
        #    en 值必须与 CORRECTIONS 一致
        for key in NEW_ENTRIES:
            if key in strings:
                del strings[key]
                dirty = True
        if path == FILES[0]:
            for key, entry in NEW_ENTRIES.items():
                if key in CORRECTIONS:
                    entry["localizations"]["en"]["stringUnit"]["value"] = CORRECTIONS[key]
                strings[key] = entry
                added.append(key)
                dirty = True
                if key in CORRECTIONS:
                    replaced.append((path.name, key))

        # 仅在发生实质变更时写盘：无命中的文件（如 InfoPlist）不重排格式
        if dirty:
            loc.save_xcstrings(path, data)

    print(f"Replaced {len(replaced)} values:")
    for name, key in sorted(replaced):
        print(f"  [{name}] {key}")
    print(f"Deleted {len(deleted)}: {deleted}")
    print(f"Added {len(added)}: {added}")

    if errors:
        print("\nERRORS:")
        for e in errors:
            print(f"  {e}")
        return 1

    # 全部修正 key 都必须已生效（替换或新增），否则视为失配
    untouched = sorted(set(CORRECTIONS) - {k for _, k in replaced})
    if untouched:
        print(f"\nWARNING: {len(untouched)} correction keys matched no entry:")
        for k in untouched:
            print(f"  {k}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
