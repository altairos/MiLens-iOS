#!/usr/bin/env python3
"""MiLens 相框 / 贴纸素材导入工具。

把素材作者准备好的相框目录（manifest + PNG）导入到工程：
  - MiLens/Resources/Assets.xcassets/<id>.imageset/   （PNG + Contents.json）
  - MiLens/Resources/Decorations/catalog.json          （运行时元数据，App 启动加载）

支持三种自适应模式（fitMode，详见 MiLensKit/Sources/MiLensKit/Editor/FrameFitSupport.swift）：
  - stretch     单张 PNG 拉伸铺满（纯色 / 渐变边框；角部会变形）
  - nine_patch  单张 PNG + 九宫格 inset，角部不变形、四边单向拉伸、中央透明窗口双向拉伸
                （几何 / 线条类相框推荐）
  - ratio_set   多张不同比例 PNG，运行时按照片比例自动选最优
                （复杂花纹相框，如拍立得 / 手绘）

manifest 字段（snake_case，便于素材作者）→ catalog.json（camelCase，匹配 Swift Codable）。
catalog.json 由 App 层 DecorationCatalogLoader 解码为 DecorationCatalog 注入编辑器。

典型工作流：
  # 1. 初始化一个新相框目录（生成 manifest 模板）
  python tools/frame_import.py init assets_src/frame_polaroid_white

  # 2. 美术把 PNG 放进该目录：
  #    stretch / nine_patch：frame_polaroid_white.png
  #    ratio_set：frame_polaroid_white_1x1.png / _3x4.png / _4x3.png / _16x9.png / _9x16.png
  #    编辑 frame.json 填 fit_mode / nine_patch_insets / supported_ratios

  # 3. 导入到工程（扫描 assets_src/ 下所有子目录，合并到 catalog）
  python tools/frame_import.py add assets_src

  # 4. 校验 catalog + imageset 完整性
  python tools/frame_import.py validate

  # 5. 列出已导入项
  python tools/frame_import.py list

PNG 命名约定：
  - stretch / nine_patch：<id>.png
  - ratio_set：<id>_<ratio>.png，ratio 为 "WxH"（如 1x1 / 3x4 / 16x9）

manifest 字段（frame.json）：
  id                   必填，全小写下划线，如 frame_polaroid_white
  name                 显示名（如「拍立得白」）
  category             frame 或 sticker（默认 frame）
  fit_mode             stretch / nine_patch / ratio_set（默认 stretch）
  is_premium           bool，Pro 专属（默认 false）
  group                分组稳定 ID（frame: recommended/film/paper/holiday；sticker: recommended/paw/daily/memorial；
                       默认 recommended，与 MiLensKit DecorationGroupIds 一致，显示名走本地化 decoration.group.<id>）
  sort_order           int，面板排序（默认 0）
  nine_patch_insets    {top,left,bottom,right}，仅 nine_patch 模式
  supported_ratios     ["1x1","3x4",...]，仅 ratio_set 模式（可省略，从文件名自动发现）
  native_aspect_ratio  素材原始宽高比 width/height，面板预览用（可选）
  preview_path         面板预览图 imageset 名（可选，默认 = id）
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path


# --------------------------------------------------------------------------- #
# 默认路径
# --------------------------------------------------------------------------- #

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ASSETS = REPO_ROOT / "MiLens" / "Resources" / "Assets.xcassets"
DEFAULT_CATALOG = REPO_ROOT / "MiLens" / "Resources" / "Decorations" / "catalog.json"

MANIFEST_NAMES = ("frame.json", "sticker.json", "decoration.json")
VALID_CATEGORIES = ("frame", "sticker")
VALID_FITMODES = ("stretch", "nine_patch", "ratio_set")
# 分组稳定 ID（与 MiLensKit/Sources/MiLensKit/Editor/DecorationCatalog.swift 的 DecorationGroupIds 一致；
# UI 显示名走本地化 key decoration.group.<id>，见 MiLens/Resources/Localizable.xcstrings）。
VALID_FRAME_GROUPS = ("recommended", "film", "paper", "holiday")
VALID_STICKER_GROUPS = ("recommended", "paw", "daily", "memorial")
FITMODE_SNAKE_TO_CAMEL = {
    "stretch": "stretch",
    "nine_patch": "ninePatch",
    "ratio_set": "ratioSet",
}


def valid_groups_for(category: str) -> tuple[str, ...]:
    """按类别返回合法分组 ID（frame 与 sticker 分组集合互不通用）。"""
    return VALID_STICKER_GROUPS if category == "sticker" else VALID_FRAME_GROUPS


# --------------------------------------------------------------------------- #
# manifest 加载与校验
# --------------------------------------------------------------------------- #

def load_manifest(frame_dir: Path) -> dict | None:
    """在 frame_dir 中查找 manifest（按 MANIFEST_NAMES 顺序优先）。"""
    for name in MANIFEST_NAMES:
        p = frame_dir / name
        if p.exists():
            with p.open(encoding="utf-8") as f:
                return json.load(f)
    return None


def validate_manifest(m: dict, source: str) -> list[str]:
    """返回错误信息列表；空表示通过。"""
    errs: list[str] = []
    if not m.get("id"):
        errs.append(f"{source}: 缺少 id")
    elif not re.fullmatch(r"[a-z0-9_]+", m["id"]):
        errs.append(f"{source}: id 必须全小写字母/数字/下划线，实际 {m['id']!r}")
    if not m.get("name"):
        errs.append(f"{source}: 缺少 name")
    cat = m.get("category", "frame")
    if cat not in VALID_CATEGORIES:
        errs.append(f"{source}: category 必须 in {VALID_CATEGORIES}，实际 {cat!r}")
    group = m.get("group", "recommended")
    if group not in valid_groups_for(cat):
        errs.append(f"{source}: group 必须 in {valid_groups_for(cat)}（category={cat}），实际 {group!r}")
    fit = m.get("fit_mode", "stretch")
    if fit not in VALID_FITMODES:
        errs.append(f"{source}: fit_mode 必须 in {VALID_FITMODES}，实际 {fit!r}")
    # sticker 是固定尺寸小图，不需自适应——强制 stretch
    if cat == "sticker" and fit != "stretch":
        errs.append(f"{source}: sticker 只支持 stretch（贴纸是固定小图，不做九宫格/多比例）")
    if fit == "nine_patch":
        insets = m.get("nine_patch_insets")
        if not insets or not all(k in insets for k in ("top", "left", "bottom", "right")):
            errs.append(f"{source}: nine_patch 模式需要 nine_patch_insets(top/left/bottom/right)")
    if fit == "ratio_set":
        ratios = m.get("supported_ratios")
        if ratios is not None and (not isinstance(ratios, list) or not ratios):
            errs.append(f"{source}: ratio_set 模式 supported_ratios 必须是非空列表或省略（自动发现）")
    return errs


# --------------------------------------------------------------------------- #
# PNG 发现与 ratio 解析
# --------------------------------------------------------------------------- #

def find_pngs(frame_dir: Path, item_id: str, fit_mode: str) -> list[tuple[str, Path]]:
    """返回 [(ratio_token, png_path)]。

    - stretch / nine_patch：单张 <id>.png，ratio_token 为空串。
    - ratio_set：所有 <id>_*.png，ratio_token 为后缀（如 "1x1"）。
    """
    if fit_mode in ("stretch", "nine_patch"):
        p = frame_dir / f"{item_id}.png"
        return [("", p)] if p.exists() else []
    # ratio_set：扫描所有 <id>_*.png
    results: list[tuple[str, Path]] = []
    for png in sorted(frame_dir.glob(f"{item_id}_*.png")):
        ratio = png.stem[len(item_id) + 1:]  # 去掉 "<id>_" 前缀
        if ratio:
            results.append((ratio, png))
    return results


def ratio_token_valid(token: str) -> bool:
    """校验 "WxH" 格式（W/H 为正数，如 1x1 / 3x4 / 16x9）。"""
    return bool(re.fullmatch(r"\d+(?:\.\d+)?x\d+(?:\.\d+)?", token))


# --------------------------------------------------------------------------- #
# imageset 写入
# --------------------------------------------------------------------------- #

def write_imageset(assets_dir: Path, asset_name: str, png: Path, dry_run: bool) -> Path:
    """复制 PNG 到 <assets>/<asset_name>.imageset/ 并生成 Contents.json。

    使用 universal + 1x/2x/3x 三档占位（filename 仅 1x），Xcode 自动从 1x 放大，
    适合单张高分辨率 PNG 装饰素材。返回 imageset 目录路径。
    """
    imageset_dir = assets_dir / f"{asset_name}.imageset"
    target_png = imageset_dir / f"{asset_name}.png"
    contents = {
        "images": [
            {"filename": target_png.name, "idiom": "universal", "scale": "1x"},
            {"idiom": "universal", "scale": "2x"},
            {"idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    rel = lambda p: p.relative_to(REPO_ROOT) if REPO_ROOT in p.parents else p.name  # noqa: E731
    if dry_run:
        print(f"    [DRY] 写 {rel(target_png)}")
        print(f"    [DRY] 写 {rel(imageset_dir / 'Contents.json')}")
        return imageset_dir
    imageset_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(png, target_png)
    with (imageset_dir / "Contents.json").open("w", encoding="utf-8") as f:
        json.dump(contents, f, indent=2, ensure_ascii=False)
        f.write("\n")
    return imageset_dir


# --------------------------------------------------------------------------- #
# catalog 合并
# --------------------------------------------------------------------------- #

def load_catalog(path: Path) -> dict:
    if path.exists():
        with path.open(encoding="utf-8") as f:
            return json.load(f)
    return {"items": []}


def save_catalog(path: Path, catalog: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2, ensure_ascii=False)
        f.write("\n")


def manifest_to_catalog_item(m: dict, fit_mode: str, found_ratios: list[str]) -> dict:
    """manifest（snake_case）→ catalog item（camelCase，匹配 Swift Codable 字段名）。"""
    item = {
        "id": m["id"],
        "name": m.get("name", m["id"]),
        "category": m.get("category", "frame"),
        "resourcePath": m["id"],
        "previewPath": m.get("preview_path") or m["id"],
        "isPremium": bool(m.get("is_premium", False)),
        "group": m.get("group", "recommended"),
        "sortOrder": int(m.get("sort_order", 0)),
        "fitMode": FITMODE_SNAKE_TO_CAMEL[fit_mode],
    }
    if fit_mode == "nine_patch":
        insets = m["nine_patch_insets"]
        item["ninePatchInsets"] = {
            "top": float(insets["top"]),
            "left": float(insets["left"]),
            "bottom": float(insets["bottom"]),
            "right": float(insets["right"]),
        }
    else:
        item["ninePatchInsets"] = None
    if fit_mode == "ratio_set":
        # 声明的 ratio ∪ 实际发现的 ratio 文件名
        declared = m.get("supported_ratios") or []
        item["supportedRatios"] = sorted(set(declared) | set(found_ratios))
    else:
        item["supportedRatios"] = None
    item["nativeAspectRatio"] = m.get("native_aspect_ratio")
    return item


def upsert_catalog_item(catalog: dict, item: dict) -> bool:
    """按 id 去重更新；返回是否为新增（True=新增，False=覆盖）。"""
    items = catalog.setdefault("items", [])
    for i, existing in enumerate(items):
        if existing.get("id") == item["id"]:
            items[i] = item
            return False
    items.append(item)
    return True


# --------------------------------------------------------------------------- #
# 子命令实现
# --------------------------------------------------------------------------- #

def cmd_add(args: argparse.Namespace) -> int:
    source = Path(args.source)
    if not source.is_dir():
        sys.exit(f"错误：源目录不存在 {source}")
    assets = Path(args.assets)
    catalog_path = Path(args.catalog)

    frame_dirs = sorted([d for d in source.iterdir() if d.is_dir()])
    if not frame_dirs:
        print(f"警告：{source} 下无子目录")
        return 0

    catalog = load_catalog(catalog_path) if not args.dry_run else {"items": []}
    added = updated = skipped = 0
    rel = lambda p: p.relative_to(REPO_ROOT) if REPO_ROOT in p.parents else p.name  # noqa: E731

    for fd in frame_dirs:
        manifest = load_manifest(fd)
        if manifest is None:
            print(f"[跳过] {fd.name}: 无 manifest（{'/'.join(MANIFEST_NAMES)}）")
            skipped += 1
            continue
        errs = validate_manifest(manifest, fd.name)
        if errs:
            for e in errs:
                print(f"  [错误] {e}")
            skipped += 1
            continue
        # 命令行覆盖
        if args.group:
            manifest["group"] = args.group
        if args.premium:
            manifest["is_premium"] = True

        fit_mode = manifest.get("fit_mode", "stretch")
        item_id = manifest["id"]
        pngs = find_pngs(fd, item_id, fit_mode)
        if not pngs:
            print(f"  [错误] {fd.name}: 未找到 PNG（fit_mode={fit_mode}, id={item_id}）")
            skipped += 1
            continue

        found_ratios: list[str] = []
        asset_error = False
        for ratio_token, png in pngs:
            if fit_mode == "ratio_set":
                if not ratio_token_valid(ratio_token):
                    print(f"  [错误] {fd.name}: ratio 后缀非法 {ratio_token!r}（应为 WxH，如 1x1/3x4/16x9）")
                    asset_error = True
                    continue
                asset_name = f"{item_id}_{ratio_token}"
                found_ratios.append(ratio_token)
            else:
                asset_name = item_id
            if not png.exists():
                print(f"  [错误] {fd.name}: PNG 不存在 {png}")
                asset_error = True
                continue
            print(f"[导入] {asset_name} <- {rel(png)}")
            write_imageset(assets, asset_name, png, args.dry_run)

        if asset_error:
            skipped += 1
            continue

        item = manifest_to_catalog_item(manifest, fit_mode, found_ratios)
        is_new = upsert_catalog_item(catalog, item) if not args.dry_run else True
        mark = "+" if is_new else "~"
        print(f"  catalog {mark} {item['id']} ({fit_mode}"
              + (f", ratios={found_ratios}" if found_ratios else "") + ")")
        if is_new:
            added += 1
        else:
            updated += 1

    if not args.dry_run:
        save_catalog(catalog_path, catalog)
        print(f"\n已写入 {rel(catalog_path)}（+{added} ~{updated} 跳过{skipped}）")
    else:
        print(f"\n[DRY] 未写文件（+{added} ~{updated} 跳过{skipped}）")
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    path = Path(args.catalog)
    catalog = load_catalog(path)
    items = catalog.get("items", [])
    if not items:
        print(f"{path} 中无装饰项")
        return 0
    print(f"{path}（{len(items)} 项）:")
    print(f"{'id':<32} {'cat':<8} {'fitMode':<12} {'group':<8} {'pro':<3} name")
    for it in sorted(items, key=lambda x: (x.get("category", ""), x.get("sortOrder", 0))):
        print(f"{it.get('id',''):<32} {it.get('category',''):<8} "
              f"{it.get('fitMode',''):<12} {it.get('group',''):<8} "
              f"{'Y' if it.get('isPremium') else 'N':<3} {it.get('name','')}")
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    path = Path(args.catalog)
    assets = Path(args.assets)
    if not path.exists():
        print(f"[失败] catalog 不存在：{path}")
        return 1
    problems = 0
    try:
        with path.open(encoding="utf-8") as f:
            catalog = json.load(f)
    except json.JSONDecodeError as e:
        print(f"[失败] catalog.json JSON 解析错误：{e}")
        return 1
    items = catalog.get("items", [])
    seen_ids: set[str] = set()
    for it in items:
        item_id = it.get("id", "")
        if not item_id:
            print("[错误] 项缺 id")
            problems += 1
            continue
        if item_id in seen_ids:
            print(f"[错误] 重复 id: {item_id}")
            problems += 1
        seen_ids.add(item_id)
        fit = it.get("fitMode", "stretch")
        cat = it.get("category", "frame")
        if cat not in VALID_CATEGORIES:
            print(f"[错误] {item_id}: category={cat} 非法")
            problems += 1
        group = it.get("group", "recommended")
        if group not in valid_groups_for(cat):
            print(f"[错误] {item_id}: group={group} 非法（category={cat} 应为 {valid_groups_for(cat)}）")
            problems += 1
        if fit not in FITMODE_SNAKE_TO_CAMEL.values():
            print(f"[错误] {item_id}: fitMode={fit} 非法（应为 {list(FITMODE_SNAKE_TO_CAMEL.values())}）")
            problems += 1
        if fit == "ninePatch":
            insets = it.get("ninePatchInsets")
            if not insets or not all(k in insets for k in ("top", "left", "bottom", "right")):
                print(f"[错误] {item_id}: ninePatch 模式缺 ninePatchInsets(top/left/bottom/right)")
                problems += 1
        # imageset 存在性
        if fit == "ratioSet":
            ratios = it.get("supportedRatios") or []
            if not ratios:
                print(f"[错误] {item_id}: ratioSet 模式 supportedRatios 为空")
                problems += 1
            for r in ratios:
                asset_name = f"{it.get('resourcePath', item_id)}_{r}"
                if not (assets / f"{asset_name}.imageset").is_dir():
                    print(f"[错误] {item_id}: 缺 imageset {asset_name}.imageset")
                    problems += 1
        else:
            asset_name = it.get("resourcePath", item_id)
            if not (assets / f"{asset_name}.imageset").is_dir():
                print(f"[错误] {item_id}: 缺 imageset {asset_name}.imageset")
                problems += 1
    if problems:
        print(f"\n校验失败：{problems} 个问题")
        return 1
    print(f"校验通过：{len(items)} 项")
    return 0


def cmd_init(args: argparse.Namespace) -> int:
    target = Path(args.target)
    if target.exists() and any(target.iterdir()):
        sys.exit(f"错误：目标目录非空 {target}")
    target.mkdir(parents=True, exist_ok=True)
    item_id = args.id or target.name
    manifest = {
        "_comment": "相框 / 贴纸 manifest。完整字段说明见 tools/frame_import.py 文档头注释。",
        "id": item_id,
        "name": args.name or item_id,
        "category": "frame",
        "fit_mode": "nine_patch",
        "is_premium": False,
        "group": "recommended",
        "sort_order": 0,
        "nine_patch_insets": {"top": 96, "left": 96, "bottom": 96, "right": 96},
        "supported_ratios": None,
        "native_aspect_ratio": None,
        "preview_path": None,
    }
    manifest_path = target / "frame.json"
    with manifest_path.open("w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"已创建 {manifest_path}")
    print(f"\n下一步：")
    print(f"  1. 把 PNG 放到 {target}/")
    print(f"     - stretch / nine_patch 模式：{item_id}.png")
    print(f"     - ratio_set 模式：{item_id}_1x1.png, {item_id}_3x4.png, ...")
    print(f"  2. 编辑 frame.json 调整 fit_mode / nine_patch_insets / supported_ratios")
    print(f"  3. 运行导入：python tools/frame_import.py add {target.parent}")
    return 0


# --------------------------------------------------------------------------- #
# 入口
# --------------------------------------------------------------------------- #

def main() -> None:
    # Windows 默认控制台编码（GBK）无法输出中文，统一重配置 stdout 为 UTF-8
    # （与 tools/localization.py 一致；macOS/Linux 默认即 UTF-8）。
    if sys.stdout is not None:
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass

    p = argparse.ArgumentParser(
        description="MiLens 相框 / 贴纸素材导入工具（生成 imageset + catalog.json）。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="详见工具文件头注释。",
    )
    sub = p.add_subparsers(dest="command", required=True)

    pa = sub.add_parser("add", help="扫描源目录，导入素材到 Assets + catalog")
    pa.add_argument("source", help="源目录（其下每个子目录 = 一个相框/贴纸）")
    pa.add_argument("--assets", default=str(DEFAULT_ASSETS),
                    help=f"Assets.xcassets 路径（默认 {DEFAULT_ASSETS}）")
    pa.add_argument("--catalog", default=str(DEFAULT_CATALOG),
                    help=f"catalog.json 路径（默认 {DEFAULT_CATALOG}）")
    pa.add_argument("--group", help="覆盖 manifest 的 group 字段")
    pa.add_argument("--premium", action="store_true", help="标记为 Pro 专属（is_premium=true）")
    pa.add_argument("--dry-run", action="store_true", help="只打印，不写文件")
    pa.set_defaults(func=cmd_add)

    pl = sub.add_parser("list", help="列出 catalog 中的装饰项")
    pl.add_argument("--catalog", default=str(DEFAULT_CATALOG))
    pl.set_defaults(func=cmd_list)

    pv = sub.add_parser("validate", help="校验 catalog 与 imageset 完整性")
    pv.add_argument("--catalog", default=str(DEFAULT_CATALOG))
    pv.add_argument("--assets", default=str(DEFAULT_ASSETS))
    pv.set_defaults(func=cmd_validate)

    pi = sub.add_parser("init", help="初始化一个新相框目录（生成 manifest 模板）")
    pi.add_argument("target", help="目标目录（将创建）")
    pi.add_argument("--id", help="素材 id（默认用目录名）")
    pi.add_argument("--name", help="显示名（默认用目录名）")
    pi.set_defaults(func=cmd_init)

    args = p.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
