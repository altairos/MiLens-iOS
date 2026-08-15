#!/usr/bin/env python3
"""MiLens 平台隔离守卫 —— AGENTS.md §3「系统框架经 protocol 抽象」的 CI 自动化。

检测 Photos/PhotosUI 框架越界（对应 docs/audit/remediation-plan.md P1-3 ②，
根治 R3 复发；DESIGN.md 平台隔离规则）：

  ERROR（硬门禁）：
  - MiLens/Views/ 下禁止 `import Photos`（PHAsset/PHPhotoLibrary 不得进入视图层）
  - MiLens/Services/ 下仅 Platform/ 子目录（适配器所在地）与 FILE_EXEMPTIONS
    登记文件可 `import Photos`，其余禁止
  - 上述白名单之外的任何 App 源码禁止直接使用 Photos 框架符号
    （PHAsset/PHPhotoLibrary/PHImageManager/...）——防绕过 import 检查的
    隐式透传（如经 PhotosUI re-export）

  允许：
  - `import PhotosUI`（声明式系统组件 PhotosPicker 等，与 ShareLink 同级
    的系统标准 UI，不属平台隔离违规）
  - Services/Platform/ 下任意使用（协议真实现所在地）
  - MiLensWidget/ 扫描 import 与符号，白名单规则同 Services/

  豁免：FILE_EXEMPTIONS 逐文件登记，每项必须给出 docs/adr/ 下的 ADR，
  脚本校验 ADR 存在且豁免文件仍存在（防死条目）。

  注释不计违规：行内 `//` 之后与整行 `//` 注释先剥离再匹配
  （View 头注释常含「保存相册走 PHPhotoLibrary」等说明文字）。

  扫描范围：MiLens/、MiLensWidget/（App 源码）。测试目录不扫——
  适配器测试（如 IOSPhotoLibraryAccessTests）直接使用系统类型验证
  协议实现，属合法用法。

用法：
  python tools/check-imports.py
  python tools/check-imports.py --root <fixture 根>   # 自测用
退出码：0 = 无违规；1 = 存在违规或白名单失效；2 = 参数/路径错误。
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# --------------------------------------------------------------------------- #
# 规则配置
# --------------------------------------------------------------------------- #

# 结构性白名单：这些目录下的文件可 import/使用 Photos 框架（协议适配器所在地）
STRUCTURAL_ALLOW_DIRS = (
    "MiLens/Services/Platform/",
)

# 逐文件豁免：相对仓库根 posix 路径 -> ADR 文件名（docs/adr/ 下）。
# 新增豁免必须先写 ADR（背景/期限/移除条件），再登记到这里。
# 历史唯一豁免 BeadExportService 已随 P2-1 收敛到 PhotoLibraryAccess 协议
# （2026-08-16，ADR-0011 §2.2 关闭），当前无豁免项。
FILE_EXEMPTIONS: dict[str, str] = {}

# Photos 框架符号（\b 边界匹配；PHObject 涵盖全部 PH 资产类型基类）
PH_SYMBOLS = (
    "PHAsset", "PHAssetCollection", "PHAssetCreationRequest",
    "PHAssetChangeRequest", "PHCollectionList", "PHFetchResult",
    "PHFetchOptions", "PHImageManager", "PHImageRequestOptions",
    "PHObject", "PHPhotoLibrary",
)
PH_SYMBOL_RE = re.compile(r"\b(" + "|".join(PH_SYMBOLS) + r")\b")
IMPORT_PHOTOS_RE = re.compile(r"^\s*import\s+Photos\s*$")

SCAN_ROOTS = ("MiLens", "MiLensWidget")


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def strip_comment(line: str) -> str:
    """剥离行内注释（不处理字符串内的 //，符号误报概率可忽略）。"""
    idx = line.find("//")
    return line if idx < 0 else line[:idx]


def is_allowed(rel_posix: str) -> bool:
    if rel_posix in FILE_EXEMPTIONS:
        return True
    return rel_posix.startswith(STRUCTURAL_ALLOW_DIRS)


def scan_file(path: Path, rel: str) -> list[str]:
    failures: list[str] = []
    allowed = is_allowed(rel)
    for idx, raw in enumerate(
            path.read_text(encoding="utf-8").splitlines(), start=1):
        code = strip_comment(raw)
        if not allowed and IMPORT_PHOTOS_RE.match(code):
            failures.append(f"{rel}:{idx}: ERROR import Photos（平台隔离）：{raw.strip()}")
        if not allowed and PH_SYMBOL_RE.search(code):
            failures.append(
                f"{rel}:{idx}: ERROR Photos 框架符号（{PH_SYMBOL_RE.search(code).group(1)}）：{raw.strip()}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description="MiLens 平台隔离守卫（import Photos 审计）。")
    parser.add_argument("--root", default=None,
                        help="覆盖扫描根（自测用；默认 MiLens + MiLensWidget）。")
    args = parser.parse_args()

    root = Path(args.root).resolve() if args.root else repo_root()

    # 白名单健康检查：ADR 必须存在，豁免文件必须仍存在
    failures: list[str] = []
    for rel, adr in FILE_EXEMPTIONS.items():
        adr_path = repo_root() / "docs" / "adr" / adr
        if not adr_path.is_file():
            failures.append(f"白名单失效：{rel} 登记的 ADR docs/adr/{adr} 不存在")
        elif not (root / rel).is_file():
            failures.append(f"白名单过期：{rel} 文件已不存在，请删除登记项")

    roots = [root / r for r in SCAN_ROOTS]
    roots = [r for r in roots if r.is_dir()]
    if not roots:
        print(f"扫描根目录不存在: {SCAN_ROOTS}", file=sys.stderr)
        return 2

    scanned = 0
    for r in roots:
        for f in sorted(r.rglob("*.swift")):
            rel = f.relative_to(root).as_posix()
            scanned += 1
            failures.extend(scan_file(f, rel))

    if failures:
        print(f"── ERROR（平台隔离违规，{len(failures)} 处）──")
        for msg in failures:
            print(f"  {msg}")
        print("\n失败：Photos 框架只能出现在 Services/Platform/ 适配器或"
              " ADR 豁免文件中；Views 禁 PHAsset/PHPhotoLibrary"
              "（DESIGN.md 平台隔离 / AGENTS.md §3）。")
        return 1

    print(f"通过：{scanned} 个文件扫描，0 处 Photos 越界"
          f"（豁免 {len(FILE_EXEMPTIONS)} 项均带 ADR）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
