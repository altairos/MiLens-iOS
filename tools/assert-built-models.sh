#!/usr/bin/env bash
# assert-built-models.sh —— 断言构建产物包含全部生产 Core ML 模型（.mlmodelc）。
#
# 背景：CI 若在 xcodegen generate 之后才下载 .mlpackage，生成的工程不会引用模型，
# 构建产物会静默缺失模型；ClipInferenceService.create() 加载失败返回 nil，
# 正式包会静默降级到 Vision 预筛。本脚本在 build/archive 后校验产物，
# 模型缺失即失败（绝不带病交付）。
#
# 用法：
#   tools/assert-built-models.sh build/DerivedData/Build/Products/Debug-iphonesimulator/MiLens.app
#   tools/assert-built-models.sh build/MiLens.xcarchive/Products/Applications/MiLens.app
#
# 模型名与 fetch-models.sh 同源（tools/model-manifest.json，仅检查 purpose=production）；
# .mlpackage 编译后产物名为 <name>.mlmodelc。
#
# 依赖：python3 / find / grep（macOS 与 GitHub Actions macOS runner 均自带）

set -euo pipefail

APP_BUNDLE="${1:?用法: assert-built-models.sh <MiLens.app 路径>}"
if [ ! -d "$APP_BUNDLE" ]; then
  echo "assert-built-models: App bundle 不存在: $APP_BUNDLE" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/model-manifest.json"

# 清单中 purpose=production 的模型名列表
model_names() {
  python3 -c "
import json
for f in json.load(open('$MANIFEST'))['files']:
    if f.get('purpose') == 'production':
        print(f['name'])
"
}

compiled="$(find "$APP_BUNDLE" -type d -name '*.mlmodelc' -exec basename {} \; | sort)"
missing=0
while IFS= read -r name; do
  expected="$name.mlmodelc"
  if ! grep -qxF "$expected" <<<"$compiled"; then
    echo "assert-built-models: [FAIL] 构建产物缺少模型 $expected" >&2
    missing=1
  else
    echo "assert-built-models: [OK] $expected"
  fi
done < <(model_names)

if [ "$missing" -ne 0 ]; then
  echo "assert-built-models: 构建产物模型不完整——检查 xcodegen 生成时机与模型下载顺序（见 ci.yml）" >&2
  exit 1
fi
echo "assert-built-models: 全部生产模型已进入构建产物"
