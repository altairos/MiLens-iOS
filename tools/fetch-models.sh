#!/usr/bin/env bash
# fetch-models.sh —— 从 GitHub Release 下载生产模型并校验 SHA256（P1 模型交付）。
#
# 用法：tools/fetch-models.sh
#   - 读取 tools/model-manifest.json（模型清单，内嵌 sha256——保证校验与发布一致）
#   - 下载 GitHub Release tar 包 → shasum -a 256 校验 → 解包到 MiLens/Resources/Models/
#   - 幂等：所有模型已就位（.mlpackage 非空目录）则跳过——CI 缓存场景
#   - 失败：非零退出（下载失败 / SHA256 不匹配 / 解包不完整），绝不带病构建
#
# 环境变量：
#   MILENS_MODEL_BASE_URL  覆盖下载基址（默认 GitHub Release；本地/镜像测试用）
#
# 依赖：curl / shasum / tar / python3（macOS 与 GitHub Actions macOS runner 均自带）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/model-manifest.json"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$PROJECT_ROOT/MiLens/Resources/Models"

# 用 python3 解析 manifest（macOS 自带，避免 jq 依赖）
read_manifest() {
  python3 -c "import json; print(json.load(open('$MANIFEST'))$1)"
}

REPO="$(read_manifest "['repo']")"
TAG="$(read_manifest "['release_tag']")"
ARCHIVE="$(read_manifest "['archive']")"
EXPECTED_SHA="$(read_manifest "['archive_sha256']")"
BASE_URL="${MILENS_MODEL_BASE_URL:-https://github.com/$REPO/releases/download/$TAG}"

# 清单中的模型相对路径列表
model_paths() {
  python3 -c "
import json
for f in json.load(open('$MANIFEST'))['files']:
    print(f['path'])
"
}

# 幂等检查：清单中的模型全部就位（目录存在且非空）
all_present() {
  while IFS= read -r rel_path; do
    local full="$PROJECT_ROOT/$rel_path"
    if [ ! -d "$full" ] || [ -z "$(ls -A "$full" 2>/dev/null)" ]; then
      return 1
    fi
  done < <(model_paths)
  return 0
}

if all_present; then
  echo "fetch-models: 模型已就位，跳过下载（幂等）"
  exit 0
fi

echo "fetch-models: 下载 $BASE_URL/$ARCHIVE"
TMP_ARCHIVE="$(mktemp)"
trap 'rm -f "$TMP_ARCHIVE"' EXIT

curl -fL --retry 3 "$BASE_URL/$ARCHIVE" -o "$TMP_ARCHIVE"

ACTUAL_SHA="$(shasum -a 256 "$TMP_ARCHIVE" | awk '{print $1}')"
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "fetch-models: SHA256 校验失败（期望 ${EXPECTED_SHA}，实际 ${ACTUAL_SHA}）" >&2
  exit 1
fi
echo "fetch-models: SHA256 校验通过"

mkdir -p "$TARGET_DIR"
tar -xzf "$TMP_ARCHIVE" -C "$TARGET_DIR"

# 解包完整性复核（校验通过但解包缺文件也视为失败）
if ! all_present; then
  echo "fetch-models: 解包不完整（清单模型缺失）" >&2
  exit 1
fi

echo "fetch-models: 完成——模型已解包到 $TARGET_DIR"
