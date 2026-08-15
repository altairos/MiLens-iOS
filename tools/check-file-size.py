#!/usr/bin/env python3
"""MiLens 源码规模守卫 —— AGENTS.md §3「单文件超 600 行须拆分」的 CI 自动化。

规则（对应 docs/audit/remediation-plan.md P1-3 ①，根治 R2 复发）：

  默认上限 600 行；以下两类「编辑器/算法核心」上限 800 行：
    - MiLensKit/Sources/MiLensKit/ 全部（Kit 是拼豆算法/工具收敛地）
    - App 层路径含 Editor 目录段的文件（Views/Editor、ViewModels/Editor、
      Services/Editor）

  白名单：FILE_EXEMPTIONS 逐文件登记，每项必须给出 docs/adr/ 下的 ADR 文件名，
  脚本会校验该 ADR 存在——「白名单需 ADR」本身也是门禁（AGENTS.md §3
  「不留长期豁免」的可执行化）。豁免语义为**冻结**：登记 FROZEN_LINES
  当前行数，豁免期间继续增长直接失败，只许缩小（ADR-0011 §2.4）。

  扫描范围：MiLens/、MiLensWidget/、MiLensKit/Sources/（产品源码）。
  测试目录（MiLensTests/、MiLensUITests/、MiLensKit/Tests/）不在守卫范围：
  守卫语义针对产品代码的可维护性，测试文件是行为规格载体（如
  ZipBackupServiceTests 1000+ 行，拆分不产生维护收益）。

用法：
  python tools/check-file-size.py            # 全量检查
  python tools/check-file-size.py --stats    # 额外打印 top 10 大文件
  python tools/check-file-size.py --root ... # 指定扫描根（自测用）
退出码：0 = 全部合规；1 = 存在超标或白名单失效；2 = 参数/路径错误。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# --------------------------------------------------------------------------- #
# 规则配置
# --------------------------------------------------------------------------- #

DEFAULT_LIMIT = 600
CORE_LIMIT = 800

# 800 行上限适用的路径判定（posix 相对路径）
KIT_SOURCES_DIR = "MiLensKit/Sources/MiLensKit"
EDITOR_DIR_SEGMENT = "Editor"

# 扫描的产品源码根
SCAN_ROOTS = ("MiLens", "MiLensWidget", "MiLensKit/Sources")

# 逐文件白名单：相对仓库根的 posix 路径 -> ADR 文件名（docs/adr/ 下）。
# 新增豁免必须先写 ADR（背景/期限/移除条件），再登记到这里。
# 豁免即冻结（ADR-0011 §2.4）：FROZEN_LINES 登记当前行数，只许缩小。
# 2026-08-15：ADR-0011 §2.4 首批 5 个存量超标文件已全部拆分至 <600 行，条目清空。
FILE_EXEMPTIONS: dict[str, str] = {}

# 豁免冻结行数：豁免文件当前行数，超出即失败（防「豁免后继续膨胀」）。
FROZEN_LINES: dict[str, int] = {}

# --------------------------------------------------------------------------- #


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def limit_for(rel_posix: str) -> int:
    """按路径判定行数上限。"""
    if rel_posix.startswith(KIT_SOURCES_DIR):
        return CORE_LIMIT
    parts = rel_posix.split("/")
    # App 层编辑器核心目录（Views/Editor、ViewModels/Editor、Services/Editor）
    if len(parts) >= 2 and EDITOR_DIR_SEGMENT in parts[:-1]:
        return CORE_LIMIT
    return DEFAULT_LIMIT


def main() -> int:
    parser = argparse.ArgumentParser(description="MiLens 源码规模守卫（600/800 行）。")
    parser.add_argument("--root", default=None,
                        help="覆盖扫描根（自测用；默认 SCAN_ROOTS 相对仓库根）。")
    parser.add_argument("--stats", action="store_true",
                        help="额外打印 top 10 最大文件。")
    args = parser.parse_args()

    root = repo_root()
    if args.root:
        root = Path(args.root).resolve()

    # 白名单健康检查：豁免项的 ADR 必须真实存在
    failures: list[str] = []
    for rel, adr in FILE_EXEMPTIONS.items():
        adr_path = repo_root() / "docs" / "adr" / adr
        if not adr_path.is_file():
            failures.append(f"白名单失效：{rel} 登记的 ADR docs/adr/{adr} 不存在")
        elif not (root / rel).is_file():
            failures.append(f"白名单过期：{rel} 文件已不存在，请删除登记项")

    roots = [Path(args.root).resolve()] if args.root else [root / r for r in SCAN_ROOTS]
    roots = [r for r in roots if r.is_dir()]
    if not roots:
        print(f"扫描根目录不存在: {args.root or SCAN_ROOTS}", file=sys.stderr)
        return 2

    records: list[tuple[int, str, int]] = []  # (行数, 相对路径, 上限)
    exempted: list[str] = []
    for r in roots:
        for f in sorted(r.rglob("*.swift")):
            rel = f.relative_to(root).as_posix()
            lines = len(f.read_text(encoding="utf-8").splitlines())
            limit = limit_for(rel)
            if rel in FILE_EXEMPTIONS:
                frozen = FROZEN_LINES.get(rel)
                if frozen is None:
                    failures.append(f"白名单不完整：{rel} 缺 FROZEN_LINES 冻结行数")
                elif lines > frozen:
                    failures.append(
                        f"{rel}: {lines} 行 > 冻结行数 {frozen} 行——豁免只许缩小"
                        f"（ADR-0011 §2.4），继续增长须先拆分")
                else:
                    exempted.append(f"{rel}: {lines} 行（ADR 豁免冻结中，≤ {frozen}）")
                continue
            records.append((lines, rel, limit))
            if lines > limit:
                failures.append(
                    f"{rel}: {lines} 行 > 上限 {limit} 行——拆分或登记 ADR 白名单")

    if args.stats:
        print("── top 10 最大文件 ──")
        for lines, rel, limit in sorted(records, reverse=True)[:10]:
            print(f"  {lines:>5} / {limit}  {rel}")
        print()

    if exempted:
        print(f"── INFO（ADR 豁免中，{len(exempted)} 项）──")
        for msg in exempted:
            print(f"  {msg}")
        print()

    if failures:
        print(f"── ERROR（规模守卫违规，{len(failures)} 项）──")
        for msg in failures:
            print(f"  {msg}")
        print("\n失败：AGENTS.md §3 规模守卫（600/800 行）。")
        return 1

    print(f"通过：{len(records)} 个 Swift 源文件均在规模守卫内"
          f"（默认 {DEFAULT_LIMIT} 行，Kit/Editor 核心 {CORE_LIMIT} 行）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
