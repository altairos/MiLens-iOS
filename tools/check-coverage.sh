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
#   APP_LINE_MIN / APP_FUNCTION_MIN / APP_BRANCH_MIN   MiLens App target
#   KIT_LINE_MIN / KIT_FUNCTION_MIN / KIT_BRANCH_MIN   MiLensKit target
#
# 口径说明：line/function 为文件级算术平均（xccov JSON 不含按行数加权的行数，
# 与 Xcode 报告目标汇总近似）；branch 为 covered/count 精确汇总（无分支为 100%）。
# xccov 的 lineCoverage/functionCoverage 是 0…1 小数，比较前统一乘 100 转百分比
# （与基线百分数同单位——曾出现直接拿 0…1 与 30 比较导致门禁恒失败的单位错误，
# 由 --selftest fixture 守护）。
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
import subprocess
import sys

args = sys.argv[1:]
selftest = args[0] == "--selftest"
if selftest:
    # 固定 fixture：App 各指标恰好等于基线（必须 PASS），Kit 行覆盖率低于基线
    # （必须 FAIL）。若比较单位错误（0…1 小数直接与 30/47 比较），App 将恒 FAIL，
    # 自测立即失败——防止单位回归。
    app_ml, app_mf, app_mb, kit_ml, kit_mf, kit_mb = (float(a) for a in args[1:7])
    report = [
        {"target": "MiLens.app", "coverageData": [
            {"lineCoverage": 0.30, "functionCoverage": 0.25,
             "branches": [{"covered": 3, "count": 10}]},
        ]},
        {"target": "MiLensKit", "coverageData": [
            {"lineCoverage": 0.469, "functionCoverage": 0.50,
             "branches": [{"covered": 22, "count": 50}]},
        ]},
    ]
else:
    xc_result = args[0]
    app_ml, app_mf, app_mb, kit_ml, kit_mf, kit_mb = (float(a) for a in args[1:7])
    report = json.loads(subprocess.check_output(
        ["xcrun", "xccov", "view", "--report", "--json", xc_result], text=True))

mins = {"MiLens (App)": (app_ml, app_mf, app_mb),
        "MiLensKit": (kit_ml, kit_mf, kit_mb)}


def pct(x: float) -> str:
    return f"{x * 100:.1f}%"


def target_metrics(include: tuple, exclude: tuple):
    """汇总指定 target 的 line/function/branch 覆盖率；无数据返回 None。"""
    files = []
    for t in report:
        name = t.get("target", "")
        if not any(k in name for k in include):
            continue
        if any(k in name for k in exclude):
            continue
        files.extend(t.get("coverageData", []))
    if not files:
        return None
    line = sum(f.get("lineCoverage", 0.0) for f in files) / len(files)
    fn = sum(f.get("functionCoverage", 0.0) for f in files) / len(files)
    covered = sum(b.get("covered", 0) for f in files for b in f.get("branches", []))
    count = sum(b.get("count", 0) for f in files for b in f.get("branches", []))
    branch = covered / count if count > 0 else 1.0
    return line, fn, branch


ok = True
results = {}
metrics_by_name = {
    "MiLens (App)": target_metrics(("MiLens",), ("Tests", "Kit")),
    "MiLensKit": target_metrics(("MiLensKit",), ("Tests",)),
}
for name, metrics in metrics_by_name.items():
    if metrics is None:
        print(f"[FAIL] {name}: 未在 xcresult 中找到覆盖率数据")
        results[name] = False
        ok = False
        continue
    line, fn, branch = metrics
    min_line, min_fn, min_branch = mins[name]
    # 单位统一为百分比：xccov 的 line/functionCoverage 是 0…1 小数，基线是百分数
    passed = line * 100 >= min_line and fn * 100 >= min_fn and branch * 100 >= min_branch
    print(f"[{'PASS' if passed else 'FAIL'}] {name}: "
          f"line={pct(line)} (min {min_line}%) "
          f"function={pct(fn)} (min {min_fn}%) "
          f"branch={pct(branch)} (min {min_branch}%)")
    results[name] = passed
    ok = ok and passed

if selftest:
    # 自测期望：等于基线 PASS、低于基线 FAIL——二者都满足说明单位与比较逻辑正确
    if results.get("MiLens (App)") is True and results.get("MiLensKit") is False:
        print("check-coverage: selftest PASS（等于基线 PASS / 低于基线 FAIL，单位与比较逻辑正确）")
        sys.exit(0)
    print("check-coverage: selftest FAIL（App/Kit 结果与预期不符——阈值单位或比较逻辑错误）")
    sys.exit(1)

print(f"check-coverage: {'门禁通过' if ok else '覆盖率未达基线（用环境变量覆盖基线或补测试）'}")
sys.exit(0 if ok else 1)
PY
