#!/usr/bin/env python3
"""frame_import.py 的素材契约回归测试。"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
IMPORTER = ROOT / "tools" / "frame_import.py"
CATALOG = ROOT / "MiLens" / "Resources" / "Decorations" / "catalog.json"
ASSETS = ROOT / "MiLens" / "Resources" / "Assets.xcassets"


class FrameImportTests(unittest.TestCase):
    def run_validate(self, catalog: Path, assets: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(IMPORTER), "validate", "--catalog", str(catalog), "--assets", str(assets)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )

    def test_production_catalog_contains_all_sticker_assets(self) -> None:
        catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
        stickers = [item for item in catalog["items"] if item["category"] == "sticker"]
        self.assertEqual(len(stickers), 12)
        self.assertEqual(
            {item["resourcePath"] for item in stickers},
            {path.name.removesuffix(".imageset") for path in ASSETS.glob("sticker_*.imageset")},
        )
        catalog_by_id = {item["id"]: item for item in stickers}
        for source_dir in sorted((ROOT / "assets_src" / "stickers").iterdir()):
            manifest = json.loads((source_dir / "sticker.json").read_text(encoding="utf-8"))
            item = catalog_by_id[source_dir.name]
            self.assertEqual(item["id"], manifest["id"])
            self.assertEqual(item["name"], manifest["name"])
            self.assertEqual(item["group"], manifest["group"])
            self.assertEqual(item["sortOrder"], manifest["sort_order"])
            self.assertEqual(item["isPremium"], manifest["is_premium"])
            self.assertEqual(item["nativeAspectRatio"], manifest["native_aspect_ratio"])
        result = self.run_validate(CATALOG, ASSETS)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_preview_imageset_fails_validation(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            catalog = temp / "catalog.json"
            assets = temp / "Assets.xcassets"
            asset = assets / "sticker_demo.imageset"
            asset.mkdir(parents=True)
            (asset / "demo.png").write_bytes(b"not a real png")
            (asset / "Contents.json").write_text(
                json.dumps({"images": [{"filename": "demo.png"}]}), encoding="utf-8"
            )
            catalog.write_text(
                json.dumps(
                    {
                        "items": [
                            {
                                "id": "sticker_demo",
                                "name": "decoration.sticker.demo",
                                "category": "sticker",
                                "resourcePath": "sticker_demo",
                                "previewPath": "sticker_demo_preview",
                                "fitMode": "stretch",
                                "group": "recommended",
                                "sortOrder": 1,
                            }
                        ]
                    }
                ),
                encoding="utf-8",
            )
            result = self.run_validate(catalog, assets)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("preview", result.stdout)

    def test_malformed_imageset_file_fails_validation(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            catalog = temp / "catalog.json"
            assets = temp / "Assets.xcassets"
            asset = assets / "sticker_demo.imageset"
            asset.mkdir(parents=True)
            (asset / "Contents.json").write_text(
                json.dumps({"images": [{"filename": "missing.png"}]}), encoding="utf-8"
            )
            catalog.write_text(
                json.dumps(
                    {
                        "items": [
                            {
                                "id": "sticker_demo",
                                "name": "decoration.sticker.demo",
                                "category": "sticker",
                                "resourcePath": "sticker_demo",
                                "previewPath": "sticker_demo",
                                "fitMode": "stretch",
                                "group": "recommended",
                                "sortOrder": 1,
                            }
                        ]
                    }
                ),
                encoding="utf-8",
            )
            result = self.run_validate(catalog, assets)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("缺文件", result.stdout)


if __name__ == "__main__":
    unittest.main()
