"""Convert RTMPose-t pet face model to Core ML for MiLens iOS.

Converts the source ONNX model (rtmpose_t_pet_face.onnx, 5-keypoint pet face
pose estimation with SimCC output) to a Core ML ML Program (.mlpackage).

Model contract (from source PoseInferenceService.ets / PoseInferenceMath.ets):
- Input:  ``images``  [1, 3, 192, 192] NCHW float32
- Output: ``simcc_x`` [1, 5, 384], ``simcc_y`` [1, 5, 384]
- Preprocessing: ImageNet normalize (mean=[0.485,0.456,0.406], std=[0.229,0.224,0.225])
- Constants: INPUT_SIZE=192, NUM_KEYPOINTS=5, UPSCALE_FACTOR=2, SIMCC_LENGTH=384

Prerequisites:
    pip install -r tools/requirements-models.txt   (macOS only)

Examples:
    # Basic conversion (FP16 by default, ~6 MB)
    python tools/convert_rtmpose_coreml.py \\
        --onnx /path/to/rtmpose_t_pet_face.onnx \\
        --output MiLens/Resources/Models/RTMPoseTPetFace.mlpackage

    # With INT8 quantization (~3 MB)
    python tools/convert_rtmpose_coreml.py \\
        --onnx /path/to/rtmpose_t_pet_face.onnx \\
        --quantization int8 \\
        --output MiLens/Resources/Models/RTMPoseTPetFace.mlpackage

    # Validate against ONNX Runtime
    python tools/convert_rtmpose_coreml.py \\
        --onnx /path/to/rtmpose_t_pet_face.onnx \\
        --validation-dir /path/to/test_images \\
        --output MiLens/Resources/Models/RTMPoseTPetFace.mlpackage
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

# ── Constants (must match source PoseInferenceService.ets) ───────────────────

INPUT_SIZE = 192
NUM_KEYPOINTS = 5
UPSCALE_FACTOR = 2
SIMCC_LENGTH = INPUT_SIZE * UPSCALE_FACTOR  # 384

# ImageNet normalization (RTMPose standard, not CLIP!)
IMAGENET_MEAN = np.asarray([0.485, 0.456, 0.406], dtype=np.float32)
IMAGENET_STD = np.asarray([0.229, 0.224, 0.225], dtype=np.float32)

IMAGE_SUFFIXES = {".bmp", ".jpeg", ".jpg", ".png", ".webp"}


# ── Image preprocessing ──────────────────────────────────────────────────────


def preprocess_image(path: Path) -> np.ndarray:
    """RTMPose preprocessing: resize → ImageNet normalize → NCHW.

    For validation we assume the bbox crop has already been applied upstream
    (same as source preparePoseInput). Here we just resize to 192×192 and
    normalize, since the validation images are pre-cropped face regions.
    """
    with Image.open(path) as source:
        image = source.convert("RGB").resize(
            (INPUT_SIZE, INPUT_SIZE), Image.Resampling.BILINEAR
        )
        pixels = np.asarray(image, dtype=np.float32) / 255.0
    normalized = (pixels - IMAGENET_MEAN) / IMAGENET_STD
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


def convert_to_coreml(
    onnx_path: Path,
    output_path: Path,
    quantization: str,
) -> None:
    """Convert ONNX → Core ML .mlpackage.

    The input is configured as a flexible MultiArray (not ImageType) because
    RTMPose receives a pre-cropped, pre-resized tensor from the Swift pose
    preprocessing pipeline (matching source preparePoseInput). ImageNet
    normalization is applied in Swift code, not inside the model — this
    keeps the model a pure function of its ONNX semantics.
    """
    import coremltools as ct

    print(f"Loading ONNX: {onnx_path}")
    print(f"Converting ONNX → Core ML (target iOS 17+), opset 12...")

    mlmodel = ct.convert(
        str(onnx_path),
        inputs=[
            ct.TensorType(
                name="images",
                shape=(1, 3, INPUT_SIZE, INPUT_SIZE),
            )
        ],
        outputs=[
            ct.TensorType(name="simcc_x"),
            ct.TensorType(name="simcc_y"),
        ],
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.ALL,
        convert_to="ml-program",
    )

    # Metadata
    mlmodel.short_description = (
        f"RTMPose-t pet face pose ({NUM_KEYPOINTS} keypoints, SimCC)"
    )
    mlmodel.author = "MiLens iOS — converted from rtmpose_t_pet_face.onnx"
    mlmodel.version = "1.0"

    if quantization == "fp16":
        mlmodel = ct.optimize.coreml.use_fp16storage(mlmodel)
        print("Applied FP16 storage optimization.")
    elif quantization == "int8":
        from coremltools.optimize.coreml import (
            OpPalettizerConfig,
            OptimizationConfig,
            op_palettizer,
        )

        config = OptimizationConfig(
            global_config=OpPalettizerConfig(
                mode="kmeans",
                nbits=8,
            )
        )
        mlmodel = op_palettizer(mlmodel, config)
        print("Applied INT8 (8-bit palette) quantization.")

    mlmodel.save(str(output_path))
    size_mb = sum(
        f.stat().st_size for f in output_path.rglob("*") if f.is_file()
    ) / 1024 / 1024
    print(f"Saved → {output_path} ({size_mb:.2f} MB)")


# ── Validation ───────────────────────────────────────────────────────────────


def validate(
    onnx_path: Path,
    mlpackage_path: Path,
    validation_images: list[Path],
) -> None:
    """Compare Core ML output vs ONNX Runtime baseline.

    Pass criteria (per ADR-0007 §4.4):
    - 5-keypoint average pixel error < 2px (in 224×224 / 192×192 coordinate space)
    """
    if not validation_images:
        print("No validation images — skipping accuracy check.")
        return

    import coremltools as ct
    import onnxruntime as ort

    # ONNX Runtime baseline
    providers = ["CPUExecutionProvider"]
    session = ort.InferenceSession(str(onnx_path), providers=providers)

    # Core ML model
    mlmodel = ct.models.MLModel(str(mlpackage_path))

    keypoint_errors: list[float] = []

    for img_path in validation_images:
        preprocessed = preprocess_image(img_path)

        # ONNX inference
        onnx_out = session.run(
            None, {"images": preprocessed.astype(np.float32)}
        )
        onnx_x = onnx_out[0]  # [1, 5, 384]
        onnx_y = onnx_out[1]  # [1, 5, 384]

        # Core ML inference
        coreml_out = mlmodel.predict({"images": preprocessed.astype(np.float32)})
        coreml_x = coreml_out["simcc_x"]
        coreml_y = coreml_out["simcc_y"]

        # Decode SimCC to keypoint coordinates (argmax → pixel position)
        for kp in range(NUM_KEYPOINTS):
            onnx_x_pos = float(np.argmax(onnx_x[0, kp])) / UPSCALE_FACTOR
            onnx_y_pos = float(np.argmax(onnx_y[0, kp])) / UPSCALE_FACTOR
            coreml_x_pos = float(np.argmax(coreml_x[0, kp])) / UPSCALE_FACTOR
            coreml_y_pos = float(np.argmax(coreml_y[0, kp])) / UPSCALE_FACTOR

            dx = coreml_x_pos - onnx_x_pos
            dy = coreml_y_pos - onnx_y_pos
            keypoint_errors.append(float(np.sqrt(dx * dx + dy * dy)))

    mean_err = float(np.mean(keypoint_errors))
    max_err = float(np.max(keypoint_errors))
    threshold = 2.0

    print(
        f"\nValidation ({len(validation_images)} images, "
        f"{len(keypoint_errors)} keypoints):\n"
        f"  keypoint error: mean={mean_err:.4f}px, max={max_err:.4f}px\n"
        f"  threshold: <{threshold}px"
    )

    if max_err >= threshold:
        print(f"  [WARN] ABOVE THRESHOLD -- investigate conversion precision.")
    else:
        print(f"  [PASS]")


# ── CLI ──────────────────────────────────────────────────────────────────────


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert RTMPose-t pet face ONNX to Core ML (.mlpackage)."
    )
    parser.add_argument(
        "--onnx",
        type=Path,
        required=True,
        help="Path to source rtmpose_t_pet_face.onnx.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("RTMPoseTPetFace.mlpackage"),
        help="Output .mlpackage path.",
    )
    parser.add_argument(
        "--quantization",
        choices=("int8", "fp16"),
        default="fp16",
        help="Quantization mode (default: fp16 — model is only ~6 MB).",
    )
    parser.add_argument(
        "--validation-dir",
        type=Path,
        help="Directory of test images for accuracy comparison.",
    )
    parser.add_argument(
        "--validation-count",
        type=int,
        default=10,
        help="Images for accuracy comparison (default: 10).",
    )
    parser.add_argument(
        "--skip-validation",
        action="store_true",
        help="Skip accuracy validation.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if not args.onnx.is_file():
        raise FileNotFoundError(f"ONNX model not found: {args.onnx}")

    convert_to_coreml(
        onnx_path=args.onnx,
        output_path=args.output,
        quantization=args.quantization,
    )

    if not args.skip_validation:
        validation_images: list[Path] = []
        if args.validation_dir and args.validation_dir.is_dir():
            validation_images = collect_images(
                args.validation_dir, args.validation_count
            )

        validate(args.onnx, args.output, validation_images)
    else:
        print("Validation skipped (--skip-validation).")


if __name__ == "__main__":
    main()
