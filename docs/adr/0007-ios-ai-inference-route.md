# ADR-0007：iOS AI 推理路线 —— Core ML 模型转换 + Vision 分割混合方案

- **状态**：Accepted
- **日期**：2026-08-08
- **决策者**：产品 + 工程
- **关联**：[PLAN.md](../../PLAN.md) P1.5、[MIGRATION_ASSESSMENT.md](../../MIGRATION_ASSESSMENT.md) §6、[DESIGN.md](../../DESIGN.md) §2/§9
- **续接**：源端 ADR 0001–0006（MiPhoto2），本文为 iOS 迁移期首份架构决策

---

## 1. 背景

源端（MiPhoto2）AI 链路由三件套组成：

| 组件 | 模型/能力 | 体积 | 用途 |
|---|---|---|---|
| CLIP 视觉编码器 | `clip_vision_encoder.ms`（ViT-B/32，224×224，512 维，12 层 attention） | **167.66 MB**（FP32） | 宠物/非宠物零样本分类 + 视觉特征提取（PetMatcher） |
| RTMPose-t 宠物脸 | `rtmpose_t_pet_face.ms`（5 关键点，SimCC 输出） | **5.90 MB** | 拼豆图纸二次裁切锚点 |
| VisionKit 主体分割 | CoreVisionKit `subjectSegmentation`（系统 API） | 0 | 抠图 alpha |
| 预计算文本 embedding | `pet_text_embeddings.f32` | 0.04 MB | CLIP 零样本分类的文本侧向量 |

源端检测管线（`PhotoScanner.runPetDetectionPipeline`）是两阶段：

1. **Phase 1 预筛**：CoreVisionKit `objectDetection`（animal/cat-head/dog-head 标签）快速过滤
2. **Phase 2 精确**：CLIP `fullClipInference` 零样本分类 + 提取 512 维 embedding
3. **多级降级**：CLIP 失败 → 用 CoreVision 候选；或手工特征（512 维）+ `matchRequired` 标记需用户确认

`PetMatcher`（宠物照片自动归属）依赖 CLIP embedding（512 维余弦相似度）+ 颜色签名（14 维 tiebreaker），并设计了完整降级链：CLIP → 手工特征 → 颜色签名。

iOS 迁移面临三选一：**A. Core ML 全转换**、**B. Vision 高阶 API 为主**、**C. 混合**。

## 2. 决策

**采用方案 A（Core ML 全转换）+ Vision 原生分割**，追求与源端行为一致的高保真迁移：

| 能力 | iOS 方案 | 模型来源 |
|---|---|---|
| 宠物检测/分类 | CLIP vision encoder → Core ML（INT8/FP16 量化）+ 预计算 text embeddings 复用 | 源端 ONNX 转换 |
| 宠物照片归属（PetMatcher） | CLIP 512 维 embedding + 14 维颜色签名（与源端一致） | 纯 Swift 重写 |
| 主体分割 | `VNGenerateForegroundInstanceMask`（iOS 17+ 原生） | iOS 系统框架 |
| 宠物脸 Pose | RTMPose-t → Core ML（5 关键点，SimCC） | 源端 ONNX 转换 |
| 预筛（Phase 1） | `VNClassifyImageRequest` / `VNRecognizeAnimalsRequest` 替代 CoreVisionKit | iOS 系统框架 |

### 2.1 分层落地

```
ViewModel / Service（业务决策）
        │
        ├──> VisionService（协议，P1.4 已定义）
        │       └──> IOSVisionService（真实实现）
        │              ├── VNClassifyImageRequest  → 宠物预筛
        │              └── VNGenerateForegroundInstanceMask → 主体分割
        │
        ├──> InferenceEngine（协议，P1.4 已定义）
        │       └──> CoreMLInferenceEngine（真实实现）
        │              ├── CLIPVisionEncoder.mlmodelc → 512 维 embedding
        │              └── RTMPoseTPetFace.mlmodelc → 5 关键点 SimCC
        │
        └──> AiInferenceLogic（纯函数，Swift 重写）
               ├── classifyImageEmbedding（cosine + 阈值 + gap）
               ├── selectOutputEmbedding / encodeInputTensor
               ├── PoseSimccDecoder（SimCC → 关键点坐标）
               └── ColorSignatureMath（14 维颜色签名）
```

业务层（ViewModel/Service/PetMatcher）只依赖协议与纯函数，Core ML/Vision 真实实现可注入 mock 测试——沿用源端 `AdapterContract` 纪律。

## 3. 理由

### 3.1 为什么选全转换而非 Vision 降级

- **PetMatcher 保真**：CLIP embedding 是源端多宠物自动归属的核心。降级到颜色签名/手工特征在单宠物场景可用，多宠物复杂场景需大量手动确认，破坏"扫描即自动归类"的核心体验。源端 225+ 匹配测试以 CLIP embedding 为黄金规格，直接翻译需保持特征空间一致。
- **检测精度可控**：CLIP 零样本分类（image vs text embedding cosine）比 iOS 系统分类模型（ImageNet 级，非宠物专用）更贴合宠物场景，且物种细分（猫/狗/鸟）与源端 text embedding 一致。`VNRecognizeAnimalsRequest` 仅支持猫狗，覆盖不足。
- **源端已有降级先例**：源端 PhotoScanner 在 CLIP 不可用时降级到手工特征，说明架构本身兼容"无模型"运行；iOS 侧反向亦可——Core ML 加载失败时降级到 Vision 预筛 + 颜色签名，保留可用性。

### 3.2 为什么分割仍用 Vision 而非自带模型

- `VNGenerateForegroundInstanceMask`（iOS 17+）直接对应源端 CoreVisionKit `subjectSegmentation`，质量通常优于（Apple Neural Engine 优化），且零自带模型、零转换成本。三个候选方案在此点一致，无争议。

### 3.3 为什么 Pose 也上 V1.0

- 拼豆图纸是 iOS V1.0 的核心叙事（创作变现），二次裁切锚点直接影响图纸质量。源端 `deriveFaceBoxFromPose` 的 coarse-to-fine 适配（双眼+鼻子可信时细化脸框）是成熟逻辑，值得随迁。
- RTMPose 仅 5.90 MB，转换后体积压力远小于 CLIP。
- 注：源端 RTMPose 存在 SimCC confidence 校准待办（one-vs-rest 近似，N=384 时有压制效应），iOS 侧随迁时需一并处理（见 §6 风险）。

## 4. 模型转换方案

### 4.1 CLIP vision encoder → Core ML

源端已用 `tools/build_clip_vision_encoder.py` 从 `openai/clip-vit-base-patch32` 导出 ONNX（NHWC，224×224，输出 image_features + 12 层 attention）。iOS 转换路径：

1. **输入**：源端 ONNX（或直接从 HuggingFace CLIPModel torch 导出）
2. **工具**：`coremltools`（`ct.convert`，target iOS 17+，compute_units = `.all`）
3. **输出裁剪**：Core ML 模型只保留 `image_features`（512 维归一化向量）。attention rollout 热图是源端诊断/可视化功能，非核心——iOS 侧不再导出 12 层 attention，避免 Core ML 对 transformer 多输出的兼容风险。如确需热图，在客户端用 Core ML 的 attention 输出重算，或降级关闭。
4. **量化**：FP32（167 MB）→ FP16（~85 MB）→ INT8 权重量化（~42 MB）。V1.0 采用 **INT8 量化**（`ct.optimize.coreml`），优先控制包体积；若精度校验不达标则退 FP16。
5. **预处理内置**：CLIP 标准预处理（中心裁剪 → 224×224 双线性 → RGB 归一化 mean/std）作为 Core ML 模型的 preprocessing pipeline 内置，或保留为 Swift 纯函数（沿用源端 `ClipPreprocess` 翻译）。

### 4.2 text embeddings 复用

`pet_text_embeddings.f32`（40 KB）是 CLIP text encoder 的预计算输出（pet/nonPet 两组）。**直接打包复用**该二进制文件（Float32 数组），iOS 侧写一个 `PetTextEmbeddings` 加载器（对应源端 `PetTextEmbeddings.ets`）。体积可忽略，无需在设备端跑 text encoder。

### 4.3 RTMPose-t → Core ML

1. **输入**：源端 `rtmpose_t_pet_face.onnx`（11.77 MB）
2. **输出**：simccX + simccY 两个张量（5 关键点 × SimCC_LENGTH）
3. **解码**：Swift 重写 `PoseInferenceMath` 的 SimCC 解码（argmax + 坐标变换 + UPSCALE_FACTOR），作为纯函数 XCTest 覆盖
4. **量化**：INT8 量化后 ~3 MB

### 4.4 精度校验基准

转换后必须通过精度校验，方法：用同一批样本图片（建议 50+ 含猫/狗/鸟/非宠物）跑 **PyTorch 原始模型 vs Core ML 模型**，对拍指标：

| 组件 | 校验指标 | 通过门槛 |
|---|---|---|
| CLIP embedding | 512 维 cosine similarity（原始 vs Core ML） | > 0.999 |
| CLIP 分类决策 | isPet / species 一致率 | > 98% |
| RTMPose 关键点 | 5 点平均像素误差（224×224 坐标系） | < 2px |

校验脚本纳入 `tools/`（Python，用 coremltools + onnxruntime/transformers），CI 可选运行。

## 5. 包体积预算

| 资产 | 体积 | 备注 |
|---|---|---|
| CLIP vision encoder（INT8 .mlpackage） | **84 MB** | 实跑值；INT8 cosine >0.999（PASS） |
| CLIP vision encoder（FP16 .mlpackage） | 168 MB | 精度最高（min cosine 0.999988），INT8 不达标时备选 |
| RTMPose-t（INT8 .mlpackage） | **3.1 MB** | 实跑值 |
| RTMPose-t（FP16 .mlpackage） | 6.0 MB | 默认推荐 |
| pet_text_embeddings.f32 | 0.04 MB | 已入仓库 |
| 字体子集（霞鹜文楷 + Fraunces） | ~3.3 MB | |
| App 框架代码 + 资源 | ~5–10 MB | |
| **合计预估 .ipa（INT8 CLIP）** | **~95–100 MB** | |

对照片类 App 可接受（App Store 蜂窝下载已无硬性限制）。CLIP INT8 实跑 84 MB（高于早期估算 ~42 MB，因 8-bit kmeans palettize 含 LUT 结构开销），但 cosine 精度达标（min 0.999128 >0.999）。若后续真机验证发现 INT8 分类精度退化，可退 FP16（168 MB）。

## 6. 风险与缓解

| 风险 | 等级 | 缓解 |
|---|---|---|
| CLIP INT8 量化精度损失超阈值 | 高 | 校验基准守门；不达标退 FP16；保留 Vision 预筛 + 颜色签名降级路径 |
| Core ML 对 transformer 算子支持不全 | 中 | 只导 image_features 单输出规避多 attention 输出；必要时用 coremltools `FlexibleShape` / custom op |
| RTMPose SimCC confidence 校准（源端遗留待办） | 中 | iOS 侧直接采用标准 softmax 归一化替代源端 one-vs-rest 近似，随迁移一并解决；真机采集 logit 分布核对门限 |
| 模型首次加载延迟（CLIP ~42MB） | 中 | 懒加载 + 后台预热；扫描任务级加载，非 App 启动加载 |
| 包体积挤压下载转化率 | 低 | INT8 量化优先；评估 App Thinning（按设备切片）；CLIP 模型可考虑按需下载（但 V1.0 优先内置保证离线可用） |

## 7. 落地任务（拆入后续里程碑）

| 任务 | 里程碑 | 说明 |
|---|---|---|
| `tools/convert_clip_coreml.py`（ONNX/Torch → Core ML + 量化 + 校验） | P1.5 续 / P2 前 | 产出 `CLIPVisionEncoder.mlmodelc` + 校验报告 |
| `tools/convert_rtmpose_coreml.py`（ONNX → Core ML + 校验） | P1.5 续 | 产出 `RTMPoseTPetFace.mlmodelc` |
| `CoreMLInferenceEngine`（InferenceEngine 真实实现） | P2 | 包装 `MLModel` predict，协议骨架 P1.4 已有 |
| `IOSVisionService`（VisionService 真实实现） | P2 | VNClassifyImageRequest + VNGenerateForegroundInstanceMask |
| `AiInferenceLogic`（Swift 纯函数重写） | P2 | 翻译 classifyImageEmbedding / selectOutputEmbedding 等 |
| `PetMatcher` + `ColorSignatureMath`（Swift 重写） | P2 | 源端 PetMatcher 测试作规格 |
| `PoseInferenceMath`（Swift 纯函数重写） | P4 | SimCC 解码 + deriveFaceBoxFromPose |
| 模型资产加入 `Resources/Models/` + project.yml 注册 | P2 前 | 确保 XcodeGen 打包 |

> P1.5 的产出是本 ADR（路线定案）+ 转换工具链。VisionService/InferenceEngine 的真实实现属于 P2 扫描 MVP 落地，P1.4 已留好协议骨架与 mock。

## 8. 决策记录

- **方案 A vs B vs C**：B（纯 Vision）MVP 最快但牺牲 PetMatcher 精度；C（混合）是 A 的渐进版；经产品决策选 **A（全转换）**，因 iOS V1.0 要保证与源端一致的自动归属体验，且模型体积经量化后可接受。
- **attention rollout**：V1.0 不导出 12 层 attention，只保留 image_features。热图为可视化增强，后置。
- **Pose confidence 校准**：随迁时采用标准 softmax 替代源端 one-vs-rest 近似，顺带解决源端遗留待办。
- **降级策略保留**：Core ML 加载失败时降级到 Vision 预筛 + 颜色签名匹配，保证 App 可用性（沿用源端降级纪律）。
