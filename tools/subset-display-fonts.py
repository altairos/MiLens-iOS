#!/usr/bin/env python3
"""Generate the locale-aware display-font subsets used by MiLens.

Inputs are downloaded into .tmp-fonts/sources (ignored by git). Outputs are
written to MiLens/Resources/Fonts and are the only font binaries committed.
The app's localized strings are used as the minimum CJK character set so that
new translations cannot silently introduce tofu in display titles.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from fontTools.ttLib import TTFont


ROOT = Path(__file__).resolve().parents[1]
TMP = ROOT / ".tmp-fonts"
SOURCES = TMP / "sources"
OUTPUT = ROOT / "MiLens" / "Resources" / "Fonts"
PYTHON = sys.executable


def add_strings(value: object, chars: set[str]) -> None:
    if isinstance(value, str):
        chars.update(value)
    elif isinstance(value, dict):
        for item in value.values():
            add_strings(item, chars)
    elif isinstance(value, list):
        for item in value:
            add_strings(item, chars)


def display_characters() -> str:
    chars: set[str] = set(chr(codepoint) for codepoint in range(0x20, 0x7F))
    for catalog in (ROOT / "MiLens" / "Resources").glob("*.xcstrings"):
        add_strings(json.loads(catalog.read_text(encoding="utf-8")), chars)

    # The Latin Extended blocks cover French accents and German umlauts/ß.
    for start, end in ((0x00A0, 0x024F), (0x1E00, 0x1EFF), (0x2000, 0x207F)):
        chars.update(chr(codepoint) for codepoint in range(start, end + 1))
    chars.update("　，。！？、：；‘’“”《》【】（）—…·•→←↑↓℃°±×÷√π★☆○●△▲▽▼◇◆□■♪♫✓✗♥")
    return "".join(sorted(chars))


def subset(source: Path, target: Path, text_file: Path) -> None:
    subprocess.run(
        [
            PYTHON,
            "-m",
            "fontTools.subset",
            str(source),
            f"--text-file={text_file}",
            f"--output-file={target}",
            "--notdef-outline",
            "--recalc-bounds",
            "--layout-features=*",
            "--name-IDs=*",
            "--drop-tables+=DSIG",
        ],
        check=True,
    )


def rewrite_fraunces_names(font: TTFont, weight: int) -> None:
    names = font["name"]
    values = {
        700: ("Bold", "Fraunces-Bold"),
        600: ("Semibold", "Fraunces-Semibold"),
    }
    style, postscript = values[weight]
    replacements = {
        1: "Fraunces",
        2: style,
        4: f"Fraunces {style}",
        6: postscript,
        16: "Fraunces",
        17: style,
    }
    names.names = [record for record in names.names if record.nameID not in {*replacements, 3, 25}]
    for name_id, value in replacements.items():
        names.setName(value, name_id, 3, 1, 0x409)
        names.setName(value, name_id, 1, 0, 0)
    names.setName(f"MiLens-{postscript};Subset", 3, 3, 1, 0x409)


def build_fraunces(chars_file: Path) -> None:
    source = SOURCES / "Fraunces-VF.ttf"
    for weight, filename in ((700, "Fraunces-Bold.ttf"), (600, "Fraunces-Semibold.ttf")):
        static = TMP / f"Fraunces-{weight}-static.ttf"
        subprocess.run(
            [
                PYTHON,
                "-m",
                "fontTools.varLib.instancer",
                str(source),
                f"wght={weight}",
                "opsz=144",
                "SOFT=0",
                "WONK=0",
                f"--output={static}",
            ],
            check=True,
        )
        font = TTFont(static)
        rewrite_fraunces_names(font, weight)
        font.save(static)
        subset(static, OUTPUT / filename, chars_file)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    chars_file = TMP / "display-chars.txt"
    chars_file.write_text(display_characters(), encoding="utf-8")

    cjk_sources = (
        ("LXGWWenKaiTC-Regular.ttf", "LXGWWenKaiTC-Regular.ttf"),
        ("KleeOne-Regular.ttf", "KleeOne-Regular.ttf"),
        (
            "jyunsaikaai/jyunsaikaai-main/fonts/JyunsaiKaai-Regular.ttf",
            "JyunsaiKaai-Regular.ttf",
        ),
    )
    for source_name, output_name in cjk_sources:
        subset(SOURCES / source_name, OUTPUT / output_name, chars_file)
    build_fraunces(chars_file)

    print(f"Generated display subsets from {len(display_characters())} source characters:")
    for path in sorted(OUTPUT.glob("*.ttf")):
        print(f"  {path.name}: {path.stat().st_size / 1024:.1f} KiB")


if __name__ == "__main__":
    main()
