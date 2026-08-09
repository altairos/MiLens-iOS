#!/usr/bin/env python3
"""MiLens 本地化（String Catalog）导出 / 导入 / 校验工具。

支持任意语言的 String Catalog（.xcstrings）与 Excel（.xlsx）互转，
便于外部翻译人员离线翻译后再回写。结构按 Apple String Catalog 规范
组织，新增语言时无需改动本工具——只需在 project.yml 的 knownRegions
追加语言代码，再用本工具导出该语言的空列即可。

依赖：openpyxl（pip install -r tools/requirements.txt）。

典型工作流：
  # 1. 导出（生成待翻译 Excel，en 列留空待填）
  python tools/localization.py export \\
      MiLens/Resources/Localizable.xcstrings \\
      MiLens/Resources/InfoPlist.xcstrings \\
      build/localization.xlsx --lang en

  # 2. 翻译人员填写 Excel 中的 en 列

  # 3. 导入回写（自动在 .xcstrings 创建 en locale）
  python tools/localization.py import build/localization.xlsx \\
      MiLens/Resources/Localizable.xcstrings --lang en

  # 4. 校验（JSON 合法性 + 代码引用一致性 + 缺译检测）
  python tools/localization.py check \\
      MiLens/Resources/Localizable.xcstrings \\
      MiLens/Resources/InfoPlist.xcstrings \\
      --project-yml project.yml --source-root MiLens

详见 DEVELOPMENT.md §4.4。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

try:
    from openpyxl import Workbook, load_workbook
except ImportError:  # 延迟到子命令真正需要 openpyxl 时才报错
    Workbook = None  # type: ignore[assignment,misc]
    load_workbook = None  # type: ignore[assignment]


# --------------------------------------------------------------------------- #
# xcstrings 读写
# --------------------------------------------------------------------------- #

def load_xcstrings(path: Path) -> dict:
    """读取并解析 .xcstrings（JSON）。"""
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def dumps_xcstrings(obj: dict) -> str:
    """Xcode 风格序列化：2 空格缩进、键字母序、冒号后带空格、不转义非 ASCII。

    Apple String Catalog 在键与冒号间留一个空格（``"key" : value``），
    ``json.dumps`` 默认无此空格。下方正则仅匹配「字符串字面量 + 冒号」——
    JSON 中 value 字符串后不会紧跟冒号，故替换只作用于 key。
    """
    text = json.dumps(obj, indent=2, ensure_ascii=False, sort_keys=True)
    text = re.sub(r'("(?:\\.|[^"\\])*")(\s*):', r"\1 :", text)
    return text + "\n"


def save_xcstrings(path: Path, obj: dict) -> None:
    """以 Xcode 风格写回 .xcstrings。"""
    path.write_text(dumps_xcstrings(obj), encoding="utf-8")


# --------------------------------------------------------------------------- #
# 语言列管理
# --------------------------------------------------------------------------- #

def collect_languages(obj: dict) -> list[str]:
    """收集 xcstrings 中出现过的所有语言代码（含 sourceLanguage，置于首位）。"""
    langs: list[str] = []
    seen: set[str] = set()
    source = obj.get("sourceLanguage", "")
    if source:
        langs.append(source)
        seen.add(source)
    for entry in obj.get("strings", {}).values():
        for lang in entry.get("localizations", {}).keys():
            if lang not in seen:
                seen.add(lang)
                langs.append(lang)
    return langs


def entry_value_state(entry: dict, lang: str) -> tuple[str, str]:
    """返回 (value, state)；无 stringUnit 或无该语言时返回 ("", "")。"""
    loc = entry.get("localizations", {}).get(lang, {})
    unit = loc.get("stringUnit")
    if not unit:
        return "", ""
    return unit.get("value") or "", unit.get("state") or ""


# --------------------------------------------------------------------------- #
# export 子命令
# --------------------------------------------------------------------------- #

def cmd_export(args: argparse.Namespace) -> int:
    if Workbook is None:
        sys.exit("错误：缺少 openpyxl，请执行 pip install -r tools/requirements.txt")

    explicit = [x for x in (args.lang.split(",") if args.lang else []) if x]
    out = Path(args.out)
    wb = Workbook()
    wb.remove(wb.active)  # 移除默认空 sheet

    for xc_raw in args.xcstrings:
        path = Path(xc_raw)
        obj = load_xcstrings(path)
        source = obj.get("sourceLanguage", "")

        # 确定导出语言列：显式指定优先，否则导出文件中已有语言
        if explicit:
            langs = [source] if source else []
            langs += [x for x in explicit if x != source]
        else:
            langs = collect_languages(obj)

        ws = wb.create_sheet(title=path.stem)
        header = ["key", "comment", "source_" + source if source else "source"]
        for lang in langs:
            if lang == source:
                continue
            header.append(lang)
            header.append(lang + "_state")
        ws.append(header)

        strings = obj.get("strings", {})
        for key in sorted(strings.keys()):
            entry = strings[key]
            row = [key, entry.get("comment", ""), entry_value_state(entry, source)[0]]
            for lang in langs:
                if lang == source:
                    continue
                value, state = entry_value_state(entry, lang)
                row.append(value)
                row.append(state)
            ws.append(row)

    if not wb.sheetnames:  # 兜底：无输入文件时不留空工作簿
        wb.create_sheet("empty")
    out.parent.mkdir(parents=True, exist_ok=True)
    wb.save(out)
    print(f"已导出 {len(args.xcstrings)} 个 String Catalog -> {out}")
    return 0


# --------------------------------------------------------------------------- #
# import 子命令
# --------------------------------------------------------------------------- #

def cmd_import(args: argparse.Namespace) -> int:
    if load_workbook is None:
        sys.exit("错误：缺少 openpyxl，请执行 pip install -r tools/requirements.txt")

    in_path = Path(args.in_file)
    xc_path = Path(args.xcstrings)
    obj = load_xcstrings(xc_path)
    source = obj.get("sourceLanguage", "")

    wb = load_workbook(in_path)
    if xc_path.stem not in wb.sheetnames:
        sys.exit(f"错误：Excel 中找不到 sheet「{xc_path.stem}」")
    rows = list(wb[xc_path.stem].iter_rows(values_only=True))
    if not rows:
        sys.exit("错误：sheet 为空")

    header = [str(h) if h is not None else "" for h in rows[0]]

    # 确定目标语言
    lang = args.lang
    if not lang:
        for h in header:
            if h and not h.startswith("source_") and not h.endswith("_state") and h not in ("key", "comment"):
                lang = h
                break
    if not lang:
        sys.exit("错误：未指定 --lang，且 Excel 中无目标语言列")
    if lang == source:
        sys.exit(f"错误：--lang（{lang}）与源语言相同，不可导入源语言列")

    val_idx = header.index(lang) if lang in header else None
    state_col = lang + "_state"
    state_idx = header.index(state_col) if state_col in header else None
    key_idx = header.index("key") if "key" in header else 0
    if val_idx is None:
        sys.exit(f"错误：表头中找不到语言列「{lang}」")

    strings = obj.setdefault("strings", {})
    updated = added = 0
    for row in rows[1:]:
        if not row or row[key_idx] in (None, ""):
            continue
        key = str(row[key_idx]).strip()
        raw = row[val_idx]
        value = str(raw).strip() if raw is not None else ""
        if not value:  # 空单元格跳过，不覆盖已有译文
            continue
        raw_state = row[state_idx] if state_idx is not None else None
        state = str(raw_state).strip() if raw_state else "translated"

        entry = strings.get(key)
        if entry is None:
            entry = {}
            strings[key] = entry
            added += 1
        else:
            updated += 1
        entry.setdefault("localizations", {})[lang] = {
            "stringUnit": {"state": state, "value": value}
        }

    save_xcstrings(xc_path, obj)
    print(f"已导入语言「{lang}」：更新 {updated} 条，新增 {added} 条 -> {xc_path}")
    return 0


# --------------------------------------------------------------------------- #
# check 子命令
# --------------------------------------------------------------------------- #

# 匹配 String(localized: "...") 与 NSLocalizedString("...")
_KEY_RE = re.compile(r'(?:String\(localized:|NSLocalizedString\()\s*"((?:\\.|[^"\\])*)"')


def extract_code_keys(source_root: Path) -> set[str]:
    """扫描 Swift 源码中引用的本地化 key。"""
    keys: set[str] = set()
    for swift in source_root.rglob("*.swift"):
        try:
            text = swift.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        keys.update(_KEY_RE.findall(text))
    return keys


def parse_known_regions(project_yml: Path) -> list[str]:
    """从 project.yml 提取 knownRegions（简单正则，避免 pyyaml 依赖）。"""
    if not project_yml.exists():
        return []
    text = project_yml.read_text(encoding="utf-8")
    m = re.search(r"knownRegions:\s*\[([^\]]*)\]", text)
    if not m:
        return []
    return [r.strip().strip("\"'") for r in m.group(1).split(",") if r.strip()]


def cmd_check(args: argparse.Namespace) -> int:
    problems = 0
    project_yml = Path(args.project_yml) if args.project_yml else None
    source_root = Path(args.source_root) if args.source_root else None
    code_keys = extract_code_keys(source_root) if source_root else set()
    known = parse_known_regions(project_yml) if project_yml else []
    last_source = ""

    for xc_raw in args.xcstrings:
        path = Path(xc_raw)
        # ① JSON 合法性
        try:
            obj = load_xcstrings(path)
        except json.JSONDecodeError as e:
            print(f"[失败] {path}: JSON 解析错误 -> {e}")
            problems += 1
            continue
        except OSError as e:
            print(f"[失败] {path}: 无法读取 -> {e}")
            problems += 1
            continue

        source = obj.get("sourceLanguage", "")
        last_source = source
        strings = obj.get("strings", {})
        present = collect_languages(obj)
        print(f"[OK] {path.name}: {len(strings)} key，语言 {present}")

        # ② 格式稳定性（load -> dump 应与磁盘内容一致）
        original = path.read_text(encoding="utf-8")
        if original != dumps_xcstrings(obj):
            print(f"  [格式] {path.name} 与规范化（Xcode 风格）不一致，运行 import 或 Xcode 保存可修正")

        # ③ 代码引用一致性（仅 Localizable.xcstrings）
        if source_root and path.stem == "Localizable":
            xc_keys = set(strings.keys())
            missing = code_keys - xc_keys
            extra = xc_keys - code_keys
            if missing:
                print(f"  [缺 key] 代码引用但 String Catalog 缺少：{sorted(missing)}")
                problems += len(missing)
            if extra:
                print(f"  [多余 key] String Catalog 有但代码未引用：{sorted(extra)}")

        # ④ 缺译检测（knownRegions 声明的非源语言）
        for key in sorted(strings.keys()):
            locs = strings[key].get("localizations", {})
            for lang in known:
                if lang == source:
                    continue
                unit = locs.get(lang, {}).get("stringUnit")
                if not unit:
                    print(f"  [缺译] {key} @ {lang}: 无译文")
                    problems += 1
                elif unit.get("state") == "new" or not unit.get("value"):
                    print(f"  [缺译] {key} @ {lang}: 未完成（state={unit.get('state')!r}）")
                    problems += 1

    if known and last_source:
        non_source = [r for r in known if r != last_source]
        if non_source:
            print(f"[信息] knownRegions={known}，源语言={last_source}；"
                  f"非源语言 {non_source} 需在各 xcstrings 补齐译文。")

    if problems:
        print(f"\n校验完成：发现 {problems} 个问题。")
        return 1
    print("\n校验通过。")
    return 0


# --------------------------------------------------------------------------- #
# 入口
# --------------------------------------------------------------------------- #

def main() -> None:
    # Windows 默认控制台编码（GBK）无法输出 − 等 Unicode 字符，check 会抛
    # UnicodeEncodeError（此前需 PYTHONUTF8=1 才通过）；统一重配置 stdout 为 UTF-8，
    # 等价于设置 PYTHONUTF8=1，Windows/macOS/Linux 行为一致。
    if sys.stdout is not None:
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            # 非 TextIOWrapper（如测试环境替换的流）或不可重配置时保持原样
            pass

    p = argparse.ArgumentParser(
        description="MiLens 本地化（String Catalog）导出 / 导入 / 校验工具。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="详见 DEVELOPMENT.md §4.4。",
    )
    sub = p.add_subparsers(dest="command", required=True)

    pe = sub.add_parser("export", help="导出 xcstrings 为 Excel")
    pe.add_argument("xcstrings", nargs="+", help="一个或多个 .xcstrings 文件")
    pe.add_argument("out", help="输出 .xlsx 路径")
    pe.add_argument("--lang", help="要导出的目标语言，逗号分隔（如 en,ja）；不指定则导出文件中已有语言")
    pe.set_defaults(func=cmd_export)

    pi = sub.add_parser("import", help="从 Excel 导入回 xcstrings")
    pi.add_argument("in_file", help="输入 .xlsx 路径")
    pi.add_argument("xcstrings", help="目标 .xcstrings 文件")
    pi.add_argument("--lang", help="要导入的目标语言；不指定则取第一个非源语言列")
    pi.set_defaults(func=cmd_import)

    pc = sub.add_parser("check", help="校验 xcstrings 合法性与一致性")
    pc.add_argument("xcstrings", nargs="+", help="一个或多个 .xcstrings 文件")
    pc.add_argument("--project-yml", help="project.yml 路径（用于对比 knownRegions）")
    pc.add_argument("--source-root", help="Swift 源码根目录（扫描代码引用的 key）")
    pc.set_defaults(func=cmd_check)

    args = p.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
