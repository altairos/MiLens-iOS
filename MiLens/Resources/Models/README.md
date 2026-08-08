# AI 模型资产

本目录存放 iOS 端 AI 推理所用的模型文件。

> 方案详见 [ADR-0007](../../../docs/adr/0007-ios-ai-inference-route.md)。
> 转换工具链见 [DEVELOPMENT.md §4.3](../../../DEVELOPMENT.md#43-ai-模型转换工具链)。

## 文件清单

| 文件 | 体积 | 进 Git | 进 App Bundle | 说明 |
|---|---|---|---|---|
| `pet_text_embeddings.f32` | 40 KB | ✅ | ✅ | CLIP text encoder 预计算向量（10 pet + 10 non-pet × 512 维 × float32） |
| `CLIPVisionEncoder_int8.mlpackage` | ~84 MB（INT8） | ❌（gitignore） | ✅ **生产模型** | CLIP ViT-B/32 vision encoder，输出 512 维 L2-normalized embedding；`CoreMLInferenceEngine` 默认加载此模型 |
| `RTMPoseTPetFace_fp16.mlpackage` | ~6 MB（FP16） | ❌（gitignore） | ✅ **生产模型** | RTMPose-t 宠物脸 5 关键点，SimCC 输出；已随包交付，暂无可加载代码（供 V1.x 使用） |
| `CLIPVisionEncoder_fp16.mlpackage` | ~85 MB（FP16） | ❌（gitignore） | ❌ 实验模型 | 未随 Release 交付，仅本机转换/调试用 |
| `RTMPoseTPetFace_int8.mlpackage` | ~3 MB（INT8） | ❌（gitignore） | ❌ 实验模型 | 未随 Release 交付，仅本机转换/调试用 |

> `.mlpackage` 被 `.gitignore` 排除（大文件）。**生产模型通过 GitHub Release 交付**（见下），不提交版本控制。

## 获取生产模型（下载交付）

生产模型以 tar 包形式发布到 GitHub Release（`altairos/MiLens-iOS`，tag `models-v1`），清单内嵌 SHA256 保证校验一致：

```bash
tools/fetch-models.sh
```

脚本行为：

1. 读取 `tools/model-manifest.json`（模型名 / 发布文件名 / SHA256 / 目标路径）。
2. 下载 tar 包 → `shasum -a 256` 校验（不匹配立即失败，绝不带病构建）。
3. 解包到本目录，复核清单内模型全部就位。
4. 幂等：模型已就位则跳过（CI 缓存 / 重复执行场景）。

本地/镜像测试可覆盖下载基址：`MILENS_MODEL_BASE_URL=file:///path/to/dir tools/fetch-models.sh`。

发布命令（一次性操作，记录在 [DEVELOPMENT.md §4.3](../../../DEVELOPMENT.md#43-ai-模型转换工具链)）：

```bash
# 固定 mtime 保证 tar 包 SHA256 可复现
find CLIPVisionEncoder_int8.mlpackage RTMPoseTPetFace_fp16.mlpackage -exec touch -t 202608010000 {} +
tar -czf models-v1.tar.gz CLIPVisionEncoder_int8.mlpackage RTMPoseTPetFace_fp16.mlpackage
shasum -a 256 models-v1.tar.gz   # 写入 tools/model-manifest.json 的 archive_sha256
git tag models-v1 && git push origin models-v1
git push origin --tags
git archive -o /tmp/release-src.tar.gz HEAD   # 或直接上传已有 tar
gh release create models-v1 models-v1.tar.gz --title "Model pack v1" --notes "CLIP int8 + RTMPose fp16"
```

## 生成实验模型（仅 macOS，可选）

```bash
# 1. 创建 Python 虚拟环境并安装依赖
python3 -m venv ../../.venv-models
source ../../.venv-models/bin/activate
pip install -r ../../tools/requirements-models.txt

# 2. 转换 CLIP vision encoder（需要校准图片）
python ../../tools/convert_clip_coreml.py \
    --calibration-dir /path/to/pet_photos \
    --output ./CLIPVisionEncoder.mlpackage

# 3. 转换 RTMPose-t
python ../../tools/convert_rtmpose_coreml.py \
    --onnx /path/to/rtmpose_t_pet_face.onnx \
    --output ./RTMPoseTPetFace.mlpackage
```

转换后运行 `xcodegen generate`（在项目根目录），XcodeGen 会自动将 `.mlpackage` 识别为 Core ML 模型并加入构建。Xcode 编译时会将 `.mlpackage` 编译为 `.mlmodelc` 并打包到 App Bundle。

> 注意：`CLIPVisionEncoder_fp16.mlpackage` 与 `RTMPoseTPetFace_int8.mlpackage`（实验模型）已在 [project.yml](../../../project.yml) `excludes` 中排除，不会进 App Bundle；生产模型不依赖本机转换，直接由 Release 下载。

## CI 构建流程

CI（`.github/workflows/ci.yml`）在构建前运行 `tools/fetch-models.sh`（GitHub Actions macOS runner 自带 curl/shasum/tar/python3，无额外依赖），并用 `actions/cache` 缓存 `MiLens/Resources/Models` 加速后续运行：

1. `tools/fetch-models.sh`（下载 + SHA256 校验 + 解包，缓存命中则幂等跳过）
2. `xcodegen generate`
3. `xcodebuild build/test`

缺少 `.mlpackage` 时 App 测试仍可编译（`InferenceEngine` 协议层有 mock 实现），但真实模型缺失会在模型加载时失败——CI 用 Release 交付保证构建环境与本地一致。
