#!/usr/bin/env bash
# check-coverage.sh —— CI 覆盖率门禁（H3）。
# 解析 xcodebuild test -enableCodeCoverage YES 产出的 .xcresult，
# 提取 MiLens（App）与 MiLensKit 的 line/function/branch 覆盖率并与基线比较；
# 任一指标低于基线即退出码非零（CI 失败），不低于基线则打印 PASS 汇总。
#
# 用法：
#   tools/check-coverage.sh build/TestResult.xcresult
#   tools/check-coverage.sh --selftest      # 固定 fixture 自测（单位与比较逻辑）
#
# 基线（默认值为占位基线，对齐源端 entry/shared 口径；首次实测后校准，
# 校准方式见 DEVELOPMENT.md §2.2）。可用环境变量覆盖，便于本地/CI 调参：
#   APP_LINE_MIN / APP_FUNCTION_MIN / APP_BRANCH_MIN   MiLens App target 基线
#   KIT_LINE_MIN / KIT_FUNCTION_MIN / KIT_BRANCH_MIN   MiLensKit target 基线
#   FILE_MIN_LINES    最差文件报告忽略小文件的阈值（可执行行，默认 50）
#   APP_FILE_MIN / KIT_FILE_MIN   可选单文件行覆盖下限（百分数，默认 0=关闭）
#
# 口径说明（2026-08-13 修正权重失真）：
# - line 覆盖率优先用每文件 coveredLines/uncoveredLines 做【行数加权】
#   （Σ已覆盖行 / Σ可执行行）——准确反映大文件覆盖。此前 line/function 用
#   文件级等权算术平均，导致 2000 行低覆盖文件与 10 行高覆盖文件权重相同，
#   整体被稀释高估。xccov report 未提供行数时回退算术平均并打印提示。
# - function 覆盖率：xccov report 不含每文件函数计数，维持文件级算术平均
#   （与 Xcode 目标汇总口径近似）。
# - branch 为 covered/count 精确汇总（无分支为 100%）。
# - 附加：倒数 5 个最差文件报告（可执行行 ≥ FILE_MIN_LINES）+ 可选单文件下限。
# 单位统一：xccov 的 line/functionCoverage 是 0…1 小数，比较前统一乘 100 转百分比
# （与基线百分数同单位——曾出现直接拿 0…1 与 30 比较导致门禁恒失败的单位错误，
# 由 --selftest fixture 守护；fixture 现含 coveredLines/uncoveredLines，守护
# 行数加权与算术平均不可混淆——加权数值偏离算术时，若误回退算术则 selftest 失败）。
#
# 依赖：xcrun / python3（macOS 与 GitHub Actions macOS runner 均自带）

set -euo pipefail

XC_RESULT="${1:?用法: check-coverage.sh <path.xcresult> 或 check-coverage.sh --selftest}"
if [ "$XC_RESULT" != "--selftest" ] && [ ! -d "$XC_RESULT" ]; then
  echo "check-coverage: xcresult 不存在: $XC_RESULT" >&2
  exit 2
fi

APP_LINE_MIN="${APP_LINE_MIN:-30}"
APP_FUNCTION_MIN="${APP_FUNCTION_MIN:-25}"
APP_BRANCH_MIN="${APP_BRANCH_MIN:-30}"
KIT_LINE_MIN="${KIT_LINE_MIN:-47}"
KIT_FUNCTION_MIN="${KIT_FUNCTION_MIN:-50}"
KIT_BRANCH_MIN="${KIT_BRANCH_MIN:-44}"

python3 - "$XC_RESULT" \
  "$APP_LINE_MIN" "$APP_FUNCTION_MIN" "$APP_BRANCH_MIN" \
  "$KIT_LINE_MIN" "$KIT_FUNCTION_MIN" "$KIT_BRANCH_MIN" <<'PY'
import json
import os
import subprocess
import sys

args = sys.argv[1:]
selftest = args[0] == "--selftest"
app_ml, app_mf, app_mb, kit_ml, kit_mf, kit_mb = (float(a) for a in args[1:7])


def normalize_report(raw):
    """归一化 xccov --report --json 顶层结构。
    旧版（≤Xcode 15）：顶层为 target 对象列表 [{target, coverageData}]；
    新版（Xcode 16+）可能包裹在 {"targets": [...]} 或其他 dict 形态。
    无法识别时 dump 结构样本到 stderr 并退出（退出码 2），便于下轮适配。"""
    if isinstance(raw, list):
        return raw
    if isinstance(raw, dict):
        ts = raw.get("targets")
        if isinstance(ts, list):
            return ts
        # {targetName: {...}} 映射形态兜底
        if raw and all(isinstance(v, dict) for v in raw.values()):
            return [{"target": k, **v} for k, v in raw.items()]
    sys.stderr.write(
        "check-coverage: 无法识别的 xccov JSON 顶层结构，前 800 字符样本：\n"
        + json.dumps(raw, ensure_ascii=False)[:800] + "\n")
    sys.exit(2)


# 附加阈值（环境变量；selftest 使用默认值，不依赖外部环境）。
FILE_MIN_LINES = int(os.environ.get("FILE_MIN_LINES", "50"))   # 最差文件报告忽略小文件的阈值
APP_FILE_MIN = float(os.environ.get("APP_FILE_MIN", "0"))      # App 单文件行覆盖下限（%），0=关闭
KIT_FILE_MIN = float(os.environ.get("KIT_FILE_MIN", "0"))      # Kit 单文件行覆盖下限（%），0=关闭

if selftest:
    # 固定 fixture（含 coveredLines/uncoveredLines，守护行数加权）：
    # App 两文件行数加权恰好 30%（PASS 基线），但算术平均为 56.7%——
    # 若误回退算术平均，加权断言失败；App 整体必须 PASS，Kit 必须 FAIL。
    #   Small.swift: 90/100  = 0.90  （小·高）
    #   Big.swift:   210/900 ≈ 0.2333（大·低）
    #   加权 = (90+210)/(100+900) = 0.30；算术 = (0.90+0.2333)/2 = 0.5667
    report = [
        {"target": "MiLens.app", "coverageData": [
            {"name": "Small.swift", "coveredLines": 90, "uncoveredLines": 10,
             "lineCoverage": 0.90, "functionCoverage": 0.25,
             "branches": [{"covered": 1, "count": 5}]},
            {"name": "Big.swift", "coveredLines": 210, "uncoveredLines": 690,
             "lineCoverage": 0.2333, "functionCoverage": 0.25,
             "branches": [{"covered": 2, "count": 5}]},
        ]},
        {"target": "MiLensKit", "coverageData": [
            {"name": "Kit.swift", "coveredLines": 469, "uncoveredLines": 531,
             "lineCoverage": 0.469, "functionCoverage": 0.50,
             "branches": [{"covered": 22, "count": 50}]},
        ]},
    ]
else:
    xc_result = args[0]
    report = json.loads(subprocess.check_output(
        ["xcrun", "xccov", "view", "--report", "--json", xc_result], text=True))
    report = normalize_report(report)

mins = {"MiLens (App)": (app_ml, app_mf, app_mb),
        "MiLensKit": (kit_ml, kit_mf, kit_mb)}


def pct(x: float) -> str:
    return f"{x * 100:.1f}%"


def collect_files(include: tuple, exclude: tuple):
    """收集指定 target 的全部文件覆盖率对象。"""
    files = []
    for t in report:
        name = t.get("target") or t.get("name") or ""
        if not any(k in name for k in include):
            continue
        if any(k in name for k in exclude):
            continue
        files.extend(t.get("coverageData") or [])
    return files


def line_coverage(files):
    """行覆盖率：所有文件均有 coveredLines/uncoveredLines 时做行数加权
    （Σ已覆盖行 / Σ可执行行，准确反映大文件覆盖）；否则回退文件级算术平均。
    返回 (value, method, weighted)。weighted=False 表示因缺行数回退（需提示）。"""
    cov = unc = 0
    weighted = True
    for f in files:
        c, u = f.get("coveredLines"), f.get("uncoveredLines")
        if c is None or u is None:
            weighted = False
            break
        cov += c
        unc += u
    if weighted and (cov + unc) > 0:
        return cov / (cov + unc), "weighted", True
    vals = [f.get("lineCoverage", 0.0) for f in files]
    return (sum(vals) / len(vals) if vals else 0.0), "arithmetic", False


def fn_coverage(files):
    """函数覆盖率：xccov report 不含每文件函数计数 → 文件级算术平均。"""
    vals = [f.get("functionCoverage", 0.0) for f in files]
    return (sum(vals) / len(vals) if vals else 0.0), "arithmetic"


def branch_coverage(files):
    """分支覆盖率：covered/count 精确汇总（无分支为 100%）。"""
    covered = sum(b.get("covered", 0) for f in files for b in f.get("branches", []))
    count = sum(b.get("count", 0) for f in files for b in f.get("branches", []))
    return covered / count if count > 0 else 1.0


def worst_files(files, limit=5):
    """返回 [(name, lineCoverage, executableLines)] 按覆盖率升序；过滤小文件
    （可执行行 < FILE_MIN_LINES 不参与，避免 10 行文件噪点）。"""
    rows = []
    for f in files:
        c, u = f.get("coveredLines"), f.get("uncoveredLines")
        if c is None or u is None:
            continue
        total = c + u
        if total < FILE_MIN_LINES:
            continue
        lcov = f.get("lineCoverage")
        if lcov is None:
            lcov = c / total if total > 0 else 0.0
        rows.append((f.get("name") or f.get("sourceFile") or "?", lcov, total))
    rows.sort(key=lambda r: r[1])
    return rows[:limit]


ok = True
results = {}
specs = {
    "MiLens (App)": (("MiLens",), ("Tests", "Kit"), APP_FILE_MIN),
    "MiLensKit": (("MiLensKit",), ("Tests",), KIT_FILE_MIN),
}
for name, (inc, exc, file_min) in specs.items():
    files = collect_files(inc, exc)
    if not files:
        # 透明化：target 对象样本助力适配未知 xccov 结构
        sample = next((json.dumps(t, ensure_ascii=False)[:600]
                       for t in report if isinstance(t, dict)), "无 target 对象")
        print(f"[FAIL] {name}: 未在 xcresult 中找到覆盖率数据；target 样本：{sample}")
        results[name] = False
        ok = False
        continue

    line, line_m, line_weighted = line_coverage(files)
    fn, fn_m = fn_coverage(files)
    branch = branch_coverage(files)
    min_line, min_fn, min_branch = mins[name]

    # 单位统一为百分比：xccov 的 line/functionCoverage 是 0…1 小数，基线是百分数
    passed = line * 100 >= min_line and fn * 100 >= min_fn and branch * 100 >= min_branch

    # 可选单文件下限：任何达标文件（可执行行 ≥ FILE_MIN_LINES）低于下限 → 该 target 失败。
    # 直击「大体量低覆盖文件被均值掩盖」问题：均值达标但单文件塌方也会被拦下。
    floor_ok = True
    qualifying = worst_files(files, limit=len(files))
    if file_min > 0:
        for _, lcov, _ in qualifying:
            if lcov * 100 < file_min:
                floor_ok = False
                break
    passed = passed and floor_ok

    floor_tag = f"  单文件下限={file_min}% {'PASS' if floor_ok else 'FAIL'}" if file_min > 0 else ""
    print(f"[{'PASS' if passed else 'FAIL'}] {name}: "
          f"line={pct(line)} ({line_m}, min {min_line}%) "
          f"function={pct(fn)} ({fn_m}, min {min_fn}%) "
          f"branch={pct(branch)} (min {min_branch}%){floor_tag}")

    # 行数缺失回退提示：xccov report 未提供行数时 line 退化为算术平均（修复的加权
    # 暂不生效），明确告知避免误以为加权已生效。
    if not line_weighted and not selftest:
        print(f"       [note] {name}: xccov 未提供 coveredLines/uncoveredLines，"
              f"line 回退文件级算术平均（加权未生效）")

    # 倒数最差文件报告（透明化：暴露被均值掩盖的大体量低覆盖文件）
    wf = worst_files(files)
    if wf:
        print(f"       最差文件（可执行行 ≥ {FILE_MIN_LINES}, 最多 5 个）:")
        for nm, lcov, total in wf:
            print(f"         {pct(lcov):>7}  {nm}  ({total} 行)")

    results[name] = passed
    ok = ok and passed

if selftest:
    app_ok = results.get("MiLens (App)") is True
    kit_ok = results.get("MiLensKit") is False
    # 守护：行数加权必须生效——App 加权 line=0.30，算术平均会得 0.5667。
    # 若有人误把 line_coverage 回退为算术平均，line_w 将等于 0.5667，断言失败。
    app_files = collect_files(("MiLens",), ("Tests", "Kit"))
    line_w, method, _ = line_coverage(app_files)
    line_a = sum(f.get("lineCoverage", 0.0) for f in app_files) / len(app_files)
    weighted_active = (method == "weighted"
                       and abs(line_w - 0.30) < 1e-9
                       and abs(line_a - 0.56665) < 1e-3
                       and line_w < line_a)
    if app_ok and kit_ok and weighted_active:
        print("check-coverage: selftest PASS（行数加权生效；App=基线 PASS / Kit<基线 FAIL，单位与比较逻辑正确）")
        sys.exit(0)
    print("check-coverage: selftest FAIL（App/Kit 结果与预期不符，或行数加权未生效——"
          "阈值单位、比较逻辑或加权口径错误）")
    sys.exit(1)

print(f"check-coverage: {'门禁通过' if ok else '覆盖率未达基线（用环境变量覆盖基线或补测试）'}")
sys.exit(0 if ok else 1)
PY
