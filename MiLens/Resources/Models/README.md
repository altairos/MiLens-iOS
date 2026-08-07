# AI 模型资产

本目录存放 iOS 端 AI 推理所用的模型文件。

> 方案详见 [ADR-0007](../../../docs/adr/0007-ios-ai-inference-route.md)。
> 转换工具链见 [DEVELOPMENT.md §4.3](../../../DEVELOPMENT.md#43-ai-模型转换工具链)。

## 文件清单

| 文件 | 体积 | 进 Git | 说明 |
|---|---|---|---|
| `pet_text_embeddings.f32` | 40 KB | ✅ | CLIP text encoder 预计算向量（10 pet + 10 non-pet × 512 维 × float32） |
| `CLIPVisionEncoder.mlpackage` | ~42 MB（INT8）/ ~85 MB（FP16） | ❌（gitignore） | CLIP ViT-B/32 vision encoder，输出 512 维 L2-normalized embedding |
| `RTMPoseTPetFace.mlpackage` | ~3 MB（INT8）/ ~6 MB（FP16） | ❌（gitignore） | RTMPose-t 宠物脸 5 关键点，SimCC 输出 |

> `.mlpackage` 被 `.gitignore` 排除（大文件）。它们由转换脚本在 macOS 上生成，不提交版本控制。

## 生成模型文件（仅 macOS）

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

## CI 构建流程（P2+）

当 `CoreMLInferenceEngine` 真实实现接入后（P2 扫描 MVP），CI 构建需要先生成模型：

1. 触发转换脚本（macOS runner）
2. `xcodegen generate`
3. `xcodebuild build/test`

在转换脚本接入 CI 前（P1 阶段），缺少 `.mlpackage` 不影响编译——`InferenceEngine` 协议层只有 mock 实现，不引用真实模型文件。
