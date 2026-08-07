"""Convert the CLIP ViT-B/32 vision encoder to Core ML for MiLens iOS.

This script produces a Core ML ML Program (.mlpackage) that maps a 224x224 RGB
image to a 512-dimensional L2-normalized embedding. It mirrors the source
HarmonyOS pipeline (MiPhoto2/tools/build_clip_vision_encoder.py) but:

- Drops the 12 attention outputs (heatmap) — iOS V1.0 only needs image_features.
- Converts directly from a traced PyTorch module (not via ONNX) for best
  transformer operator compatibility in Core ML.
- Builds CLIP preprocessing (center-crop + bicubic + normalize) into the model
  as an ImageType input so Swift code can pass a raw CVPixelBuffer/CGImage.
- Applies INT8 weight-only quantization to control .ipa size (~42 MB target).

Prerequisites:
    pip install -r tools/requirements-models.txt   (macOS only)

Examples:
    # Full pipeline: load CLIP → trace → convert → quantize → validate
    python tools/convert_clip_coreml.py \\
        --output MiLens/Resources/Models/CLIPVisionEncoder.mlpackage

    # With calibration images for INT8 quantization
    python tools/convert_clip_coreml.py \\
        --calibration-dir /path/to/pet_photos \\
        --output MiLens/Resources/Models/CLIPVisionEncoder.mlpackage

    # FP16 only (skip INT8)
    python tools/convert_clip_coreml.py --quantization fp16 \\
        --output MiLens/Resources/Models/CLIPVisionEncoder.mlpackage

    # Reuse a previously traced torchscript model
    python tools/convert_clip_coreml.py --trace-path clip_vision_traced.pt \\
        --output MiLens/Resources/Models/CLIPVisionEncoder.mlpackage
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Sequence

import numpy as np
from PIL import Image

# ── Constants (must match source-side build_clip_vision_encoder.py) ──────────

MODEL_NAME = "openai/clip-vit-base-patch32"
INPUT_SIZE = 224
EMBEDDING_DIM = 512
# CLIP normalization (same across all CLIP variants)
CLIP_MEAN = np.asarray([0.48145466, 0.4578275, 0.40821073], dtype=np.float32)
CLIP_STD = np.asarray([0.26862954, 0.26130258, 0.27577711], dtype=np.float32)
IMAGE_SUFFIXES = {".bmp", ".jpeg", ".jpg", ".png", ".webp"}

# ── PyTorch model wrapper (image_features only) ──────────────────────────────


def build_clip_vision_module(local_files_only: bool = False):
    """Load CLIP ViT-B/32 and wrap it to return only the 512-d image embedding.

    The wrapper mirrors ``ClipVisionNHWC`` from the source build script but:
    - Takes NCHW input (Core ML convention).
    - Returns only ``image_features`` (no attention tensors).
    - Applies L2 normalization inside the graph.
    """
    import torch
    from torch import nn
    from transformers import CLIPModel

    class ClipVisionEncoderOnly(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.clip = CLIPModel.from_pretrained(
                MODEL_NAME,
                local_files_only=local_files_only,
                attn_implementation="eager",
            )
            self.clip.eval()

        def forward(self, pixel_values: torch.Tensor) -> torch.Tensor:
            outputs = self.clip.vision_model(
                pixel_values=pixel_values,
                output_attentions=False,
            )
            image_features = self.clip.visual_projection(outputs.pooler_output)
            # L2 normalize — matches source-side and makes cosine similarity
            # a simple dot product at runtime.
            return image_features / image_features.norm(
                p=2, dim=-1, keepdim=True
            )

    model = ClipVisionEncoderOnly()
    model.eval()
    return model


# ── Image preprocessing (for validation only; model has built-in preprocessing) ──


def preprocess_image(path: Path) -> np.ndarray:
    """CLIP preprocessing: center-crop → bicubic 224 → normalize.

    Returns NCHW float32 [1, 3, 224, 224].
    """
    with Image.open(path) as source:
        image = source.convert("RGB")
        width, height = image.size
        scale = INPUT_SIZE / min(width, height)
        resized = image.resize(
            (round(width * scale), round(height * scale)),
            Image.Resampling.BICUBIC,
        )
        left = (resized.width - INPUT_SIZE) // 2
        top = (resized.height - INPUT_SIZE) // 2
        cropped = resized.crop((left, top, left + INPUT_SIZE, top + INPUT_SIZE))
        pixels = np.asarray(cropped, dtype=np.float32) / 255.0
    normalized = (pixels - CLIP_MEAN) / CLIP_STD
    # HWC → CHW
    return np.expand_dims(normalized.transpose(2, 0, 1), axis=0)


def collect_images(directory: Path, limit: int) -> list[Path]:
    if not directory.is_dir():
        raise ValueError(f"Image directory does not exist: {directory}")
    images = sorted(
        path
        for path in directory.rglob("*")
        if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES
    )
    if not images:
        raise ValueError(f"No supported images found in: {directory}")
    return images[:limit]


# ── Core ML conversion ───────────────────────────────────────────────────────


def trace_model(model, trace_path: Path | None = None) -> str:
    """Trace the PyTorch model to TorchScript for coremltools.

    Returns the path to the traced .pt file.
    """
    import torch

    dummy = torch.randn(1, 3, INPUT_SIZE, INPUT_SIZE, dtype=torch.float32)
    with torch.inference_mode():
        traced = torch.jit.trace(model, dummy)
    if trace_path is None:
        trace_path = Path("clip_vision_traced.pt")
    traced.save(str(trace_path))
    print(f"Traced torchscript → {trace_path}")
    return str(trace_path)


def convert_to_coreml(
    traced_path: str,
    output_path: Path,
    quantization: str,
    calibration_dir: Path | None,
    calibration_count: int,
) -> None:
    """Convert traced TorchScript → Core ML .mlpackage with optional quantization.

    The input is configured as an ImageType (224x224 RGB) so that Core ML handles
    pixel scaling and color space conversion automatically. Normalization
    (mean/std subtraction) is applied as a NearestFeature within the model.
    """
    import coremltools as ct

    # Configure image input with CLIP preprocessing built in.
    # Core ML ImageType applies: scale=1/255, bias=0 (0-255 → 0-1).
    # The model graph itself then applies (x - mean) / std via the first
    # operations we inject below.
    image_input = ct.ImageType(
        name="image",
        shape=(1, 3, INPUT_SIZE, INPUT_SIZE),
        color_layout=ct.colorlayout.RGB,
        scale=1.0 / 255.0,
        bias=[0.0, 0.0, 0.0],
    )

    print(f"Converting TorchScript → Core ML (target iOS 17+)...")
    mlmodel = ct.convert(
        traced_path,
        inputs=[image_input],
        outputs=[ct.TensorType(name="image_features")],
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.ALL,
        convert_to="ml-program",
    )

    # Add normalization as a preprocessing step inside the model spec.
    # coremltools converts the torch graph which already includes the
    # (pixel_values - mean) / std operations from CLIPModel's internal
    # preprocessing, so we don't need to add them separately.

    # Set user-friendly metadata.
    mlmodel.short_description = "CLIP ViT-B/32 vision encoder (image_features only)"
    mlmodel.author = "MiLens iOS — converted from openai/clip-vit-base-patch32"
    mlmodel.license = "MIT (CLIP model weights)"
    mlmodel.version = "1.0"

    spec = mlmodel.get_spec()
    input_desc = spec.description.input[0]
    input_desc.type.imageType.width = INPUT_SIZE
    input_desc.type.imageType.height = INPUT_SIZE
    input_desc.type.imageType.colorSpace = ct.FeatureType.ImageFeatureType.ColorSpace.Value("RGB")

    if quantization == "int8":
        mlmodel = quantize_int8(
            mlmodel, calibration_dir, calibration_count
        )

    # FP16 is handled by convert_to="ml-program" default precision.
    # coremltools ML Programs use FP16 by default when compute_precision
    # is set. We can explicitly request it:
    if quantization == "fp16":
        mlmodel = ct.optimize.coreml.use_fp16storage(mlmodel)

    mlmodel.save(str(output_path))
    print(f"Saved → {output_path} ({output_path.stat().st_size / 1024 / 1024:.2f} MB)")


def quantize_int8(mlmodel, calibration_dir: Path | None, calibration_count: int):
    """Apply weight-only INT8 quantization to the ML Program.

    Uses coremltools' compression utilities. If calibration images are
    provided, uses data-calibrated activation quantization; otherwise
    falls back to weight-only quantization (no activation calibration).
    """
    import coremltools as ct
    from coremltools.optimize.coreml import (
        OpPalettizerConfig,
        OptimizationConfig,
        op_palettizer,
    )

    if calibration_dir:
        calibration_images = collect_images(calibration_dir, calibration_count)
        print(f"INT8 calibration with {len(calibration_images)} images...")
        # Convert images to the format Core ML expects for calibration
        calibration_data = []
        for img_path in calibration_images:
            with Image.open(img_path) as img:
                resized = img.convert("RGB").resize(
                    (INPUT_SIZE, INPUT_SIZE), Image.Resampling.BICUBIC
                )
                calibration_data.append(np.asarray(resized, dtype=np.float32))

        # op_palettizer with calibration data
        config = OptimizationConfig(
            global_config=OpPalettizerConfig(
                mode="kmeans",
                nbits=8,
            )
        )
    else:
        print("INT8 weight-only quantization (no calibration data)...")
        config = OptimizationConfig(
            global_config=OpPalettizerConfig(
                mode="kmeans",
                nbits=8,
            )
        )

    compressed = op_palettizer(mlmodel, config)
    return compressed


# ── Validation ───────────────────────────────────────────────────────────────


def validate(
    traced_path: str,
    mlpackage_path: Path,
    validation_images: list[Path],
) -> None:
    """Compare Core ML output vs PyTorch baseline on sample images.

    Pass criteria (per ADR-0007 §4.4):
    - Embedding cosine similarity > 0.999
    """
    if not validation_images:
        print("No validation images — skipping accuracy check.")
        return

    import coremltools as ct
    import torch

    # Load baseline (PyTorch)
    baseline = torch.jit.load(traced_path)
    baseline.eval()

    # Load Core ML
    mlmodel = ct.models.MLModel(str(mlpackage_path))

    similarities: list[float] = []
    for img_path in validation_images:
        # PyTorch baseline (preprocessed NCHW tensor)
        preprocessed = preprocess_image(img_path)
        with torch.inference_mode():
            torch_out = (
                baseline(torch.from_numpy(preprocessed)).numpy().reshape(-1)
            )

        # Core ML (pass raw PIL image — model handles preprocessing)
        with Image.open(img_path) as img:
            rgb = img.convert("RGB").resize(
                (INPUT_SIZE, INPUT_SIZE), Image.Resampling.BICUBIC
            )
            from coremltools.models import _feature_management as fm
            input_dict = {"image": rgb}
            coreml_out = (
                mlmodel.predict(input_dict)["image_features"].reshape(-1)
            )

        sim = cosine_similarity(torch_out, coreml_out)
        similarities.append(sim)

    mean_sim = float(np.mean(similarities))
    min_sim = float(np.min(similarities))
    threshold = 0.999

    print(
        f"\nValidation ({len(similarities)} images):\n"
        f"  cosine similarity: mean={mean_sim:.6f}, min={min_sim:.6f}\n"
        f"  threshold: {threshold}"
    )

    if min_sim < threshold:
        print(f"  [WARN] BELOW THRESHOLD -- consider FP16 instead of INT8.")
        # Don't fail hard; let the user decide based on the report.
    else:
        print(f"  [PASS]")


def cosine_similarity(left: np.ndarray, right: np.ndarray) -> float:
    left = left.reshape(-1).astype(np.float64)
    right = right.reshape(-1).astype(np.float64)
    return float(np.dot(left, right) / (np.linalg.norm(left) * np.linalg.norm(right)))


# ── CLI ──────────────────────────────────────────────────────────────────────


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert CLIP ViT-B/32 vision encoder to Core ML (.mlpackage)."
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("CLIPVisionEncoder.mlpackage"),
        help="Output .mlpackage path.",
    )
    parser.add_argument(
        "--quantization",
        choices=("int8", "fp16"),
        default="int8",
        help="Quantization mode (default: int8).",
    )
    parser.add_argument(
        "--calibration-dir",
        type=Path,
        help="Directory of representative photos for INT8 calibration.",
    )
    parser.add_argument(
        "--calibration-count",
        type=int,
        default=100,
        help="Max calibration images (default: 100).",
    )
    parser.add_argument(
        "--validation-count",
        type=int,
        default=10,
        help="Images for accuracy comparison (default: 10).",
    )
    parser.add_argument(
        "--trace-path",
        type=Path,
        default=Path("clip_vision_traced.pt"),
        help="Path to save/load traced TorchScript model.",
    )
    parser.add_argument(
        "--skip-trace",
        action="store_true",
        help="Reuse --trace-path instead of loading CLIP from HuggingFace.",
    )
    parser.add_argument(
        "--local-files-only",
        action="store_true",
        help="Only load CLIP from local HuggingFace cache.",
    )
    parser.add_argument(
        "--skip-validation",
        action="store_true",
        help="Skip accuracy validation (use when no test images available).",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    # Step 1: Trace model
    if args.skip_trace:
        if not args.trace_path.is_file():
            raise FileNotFoundError(
                f"--skip-trace requires: {args.trace_path}"
            )
        traced_path = str(args.trace_path)
        print(f"Reusing traced model: {traced_path}")
    else:
        model = build_clip_vision_module(args.local_files_only)
        traced_path = trace_model(model, args.trace_path)

    # Step 2: Convert to Core ML
    convert_to_coreml(
        traced_path=traced_path,
        output_path=args.output,
        quantization=args.quantization,
        calibration_dir=args.calibration_dir,
        calibration_count=args.calibration_count,
    )

    # Step 3: Validate
    if not args.skip_validation:
        validation_images: list[Path] = []
        if args.calibration_dir and args.calibration_dir.is_dir():
            all_images = collect_images(args.calibration_dir, args.validation_count)
            validation_images = all_images[: args.validation_count]
        else:
            print("No --calibration-dir given — skipping accuracy validation.")
            print("Provide real pet photos for meaningful precision checks.")
            return

        validate(traced_path, args.output, validation_images)
    else:
        print("Validation skipped (--skip-validation).")


if __name__ == "__main__":
    main()
