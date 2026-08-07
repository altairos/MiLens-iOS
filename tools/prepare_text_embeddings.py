"""Prepare CLIP pet text embeddings for iOS bundling.

The source HarmonyOS project ships a raw float32 binary file
(`pet_text_embeddings.f32`, 40 KB) containing pre-computed CLIP text encoder
outputs for 20 keys (10 pet + 10 non-pet), each a 512-dim normalized vector.

iOS reuses this file as-is — no conversion needed. This script validates the
file format and generates a Swift reference for the loading code.

Source layout (must match PetTextEmbeddings.ets):
    PET_KEYS     = ['cat','kitten','dog','puppy','rabbit',
                    'hamster','bird','fish','turtle','pet']
    NON_PET_KEYS = ['person','car','building','food','plant',
                    'flower','furniture','sky','water','document']
    Layout: [pet0_512f][pet1_512f]...[pet9_512f][nonpet0_512f]...[nonpet9_512f]
    Total:  20 × 512 × 4 bytes = 40,960 bytes

Examples:
    # Verify source file
    python tools/prepare_text_embeddings.py \\
        --input /path/to/pet_text_embeddings.f32 --verify-only

    # Copy to iOS Resources and verify
    python tools/prepare_text_embeddings.py \\
        --input /path/to/pet_text_embeddings.f32 \\
        --output MiLens/Resources/Models/pet_text_embeddings.f32
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

EMBEDDING_DIM = 512

PET_KEYS = [
    "cat", "kitten", "dog", "puppy", "rabbit",
    "hamster", "bird", "fish", "turtle", "pet",
]
NON_PET_KEYS = [
    "person", "car", "building", "food", "plant",
    "flower", "furniture", "sky", "water", "document",
]

EXPECTED_BYTES = (len(PET_KEYS) + len(NON_PET_KEYS)) * EMBEDDING_DIM * 4


def verify(data: bytes) -> dict[str, list[float]]:
    """Verify the binary file and decode all embeddings.

    Returns a dict {key: [512 floats]}.
    """
    if len(data) != EXPECTED_BYTES:
        raise ValueError(
            f"File size mismatch: got {len(data)} bytes, "
            f"expected {EXPECTED_BYTES} bytes "
            f"(20 keys × {EMBEDDING_DIM} dims × 4 bytes/float32)"
        )

    values = struct.unpack(f"<{len(data) // 4}f", data)
    all_keys = PET_KEYS + NON_PET_KEYS
    result: dict[str, list[float]] = {}

    for i, key in enumerate(all_keys):
        offset = i * EMBEDDING_DIM
        vec = list(values[offset : offset + EMBEDDING_DIM])
        result[key] = vec

        # Sanity check: CLIP text embeddings are L2-normalized
        norm = sum(v * v for v in vec) ** 0.5
        if abs(norm - 1.0) > 0.01:
            print(f"  [WARN] '{key}' L2 norm = {norm:.4f} (expected ~1.0)")

    return result


def print_swift_reference(embeddings: dict[str, list[float]]) -> None:
    """Print a Swift code snippet showing how to load the .f32 file."""
    print("\n── Swift loading reference ──────────────────────────────────────")
    print("""
// PetTextEmbeddings.swift — load pre-computed CLIP text embeddings
// Corresponds to source PetTextEmbeddings.ets

import Foundation

enum PetTextEmbeddings {
    static let embeddingDim = 512

    static let petKeys = [
        "cat", "kitten", "dog", "puppy", "rabbit",
        "hamster", "bird", "fish", "turtle", "pet"
    ]
    static let nonPetKeys = [
        "person", "car", "building", "food", "plant",
        "flower", "furniture", "sky", "water", "document"
    ]

    struct EmbeddingSet {
        let pet: [String: [Float]]
        let nonPet: [String: [Float]]
    }

    static func load() throws -> EmbeddingSet {
        guard let url = Bundle.main.url(
            forResource: "pet_text_embeddings", withExtension: "f32"
        ) else {
            throw NSError(domain: "PetTextEmbeddings", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "f32 file not found in bundle"])
        }
        let data = try Data(contentsOf: url)
        let expected = (petKeys.count + nonPetKeys.count) * embeddingDim * 4
        guard data.count == expected else {
            throw NSError(domain: "PetTextEmbeddings", code: 2,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Size mismatch: \\(data.count) vs expected \\(expected)"])
        }
        let floats = data.withUnsafeBytes { ptr -> [Float] in
            let buf = ptr.bindMemory(to: Float.self)
            return Array(buf)
        }

        func takeVectors(_ keys: [String], start: Int) -> [String: [Float]] {
            var result: [String: [Float]] = [:]
            for (i, key) in keys.enumerated() {
                let offset = start + i * embeddingDim
                result[key] = Array(floats[offset..<offset + embeddingDim])
            }
            return result
        }

        return EmbeddingSet(
            pet: takeVectors(petKeys, start: 0),
            nonPet: takeVectors(nonPetKeys, start: petKeys.count * embeddingDim)
        )
    }
}
""")
    print("────────────────────────────────────────────────────────────────\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify and prepare CLIP pet text embeddings for iOS."
    )
    parser.add_argument(
        "--input",
        type=Path,
        required=True,
        help="Path to source pet_text_embeddings.f32.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Copy to this path (e.g. MiLens/Resources/Models/pet_text_embeddings.f32).",
    )
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="Only verify the input file, do not copy.",
    )
    parser.add_argument(
        "--print-swift",
        action="store_true",
        help="Print Swift code reference for loading the embeddings.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if not args.input.is_file():
        raise FileNotFoundError(f"Input not found: {args.input}")

    data = args.input.read_bytes()
    print(f"Input: {args.input} ({len(data)} bytes)")

    embeddings = verify(data)
    print(f"[PASS] Verified: {len(embeddings)} embeddings, {EMBEDDING_DIM} dims each")

    # Print a few sample values for spot-checking
    for key in ("cat", "dog", "person"):
        vec = embeddings[key]
        print(f"  '{key}': first 5 = [{', '.join(f'{v:.6f}' for v in vec[:5])}]")

    if not args.verify_only and args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(data)
        print(f"Copied → {args.output}")

    if args.print_swift:
        print_swift_reference(embeddings)


if __name__ == "__main__":
    main()
