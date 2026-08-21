# -*- coding: utf-8 -*-
"""MiLens 全量英文本地化注入与校验脚本。

聚合 en_data_p1, en_data_p2, en_data_p3，执行占位符一致性、复数规范、
pal 规范检查，并将英文翻译以 Xcode 规范格式注入到各个 .xcstrings 中。
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# 保证控制台与文件 UTF-8 输出
sys.stdout.reconfigure(encoding="utf-8")

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "tools"))

import localization as loc
from en_data_p1 import INFOPLIST_EN, WIDGET_EN, PLURALS_EN, ONBOARDING_EN, PALS_EN
from en_data_p2 import SETTINGS_EN, REDPACKET_EN, CREATE_BEAD_EN, PAYWALL_QUOTA_EN
from en_data_p3 import TIMELINE_HOME_EN, GALLERY_PHOTO_EN, EDITOR_DECORATION_EN, A11Y_LITERALS_EN
from en_data_p4 import SUPPLEMENT_EN
from en_data_p5a import P5A_EN
from en_data_p5b import P5B_EN
from en_data_final import FINAL_EN
from en_data_last import LAST_EN

PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?[-+0-9.]*[a-zA-Z@]+")

# 聚合所有普通翻译和复数翻译
ALL_PLAIN: dict[str, str] = {}
ALL_PLAIN.update(LAST_EN)
ALL_PLAIN.update(FINAL_EN)
ALL_PLAIN.update(P5B_EN)
ALL_PLAIN.update(P5A_EN)
ALL_PLAIN.update(SUPPLEMENT_EN)
ALL_PLAIN.update(A11Y_LITERALS_EN)
ALL_PLAIN.update(EDITOR_DECORATION_EN)
ALL_PLAIN.update(GALLERY_PHOTO_EN)
ALL_PLAIN.update(TIMELINE_HOME_EN)
ALL_PLAIN.update(PAYWALL_QUOTA_EN)
ALL_PLAIN.update(CREATE_BEAD_EN)
ALL_PLAIN.update(REDPACKET_EN)
ALL_PLAIN.update(SETTINGS_EN)
ALL_PLAIN.update(PALS_EN)
ALL_PLAIN.update(ONBOARDING_EN)
ALL_PLAIN.update(WIDGET_EN)
ALL_PLAIN.update(INFOPLIST_EN)

# 显式修正占位符严格匹配（必须与 zh-Hans 中的占位符完全一一对应）
ALL_PLAIN["album.petSelect.petMeta %@ %lld"] = "%@ · %lld Photos"
ALL_PLAIN["album.petSelect.quotaNote %lld %lld"] = "Confirming will import photos; usage %lld / %lld"
ALL_PLAIN["album.success.dateMark %@ %@"] = "%@ · %@"
ALL_PLAIN["settings.backup.confirmPets %lld"] = "%1$lld Pal Profiles"
ALL_PLAIN["settings.backup.confirmPhotos %lld"] = "%1$lld Photos"
ALL_PLAIN["settings.backup.confirmSize %@"] = "Estimated Size: %1$@"
ALL_PLAIN["settings.backup.lastBackup %@"] = "Last Backup: %1$@"
ALL_PLAIN["settings.backup.multiVolumeHint %lld"] = "Split into %1$lld volumes due to large library size"
ALL_PLAIN["create.bead.materialCount %lld %lld"] = "%1$lld Colors · %2$lld Beads Total"
ALL_PLAIN["settings.storage.count %lld %lld"] = "%1$lld/%2$lld photos"
ALL_PLAIN["settings.storage.freeUsage %lld %lld"] = "Free: %1$lld/%2$lld photos"
ALL_PLAIN["pet.profile.speciesAge %@ %@"] = "%@ · %@"
ALL_PLAIN["pet.card.subtitle %@ %@"] = "%@ · %@"
ALL_PLAIN["timeline.export.dateRange %@ %@"] = "%@ — %@"
ALL_PLAIN["reminders.today.milestone %@ %lld"] = "%@ has been with you for %lld days!"
ALL_PLAIN["redpacket.quality.clarity.resolution.detail"] = "Resolution meets requirement (%1$lld × %2$lld ≥ %3$lld px)"
ALL_PLAIN["redpacket.quality.clarity.soft.detail"] = "Image sharpness is slightly low (%lld) — recommend a clearer photo"
ALL_PLAIN["redpacket.quality.composition.clipped.detail"] = "Subject is clipped near the edges (%lld) — adjust crop"
ALL_PLAIN["redpacket.quality.composition.safezone.detail"] = "Subject is near safe zone boundary (%lld)"
ALL_PLAIN["redpacket.quality.composition.small.detail"] = "Subject occupies only %lld%% of area — zoom in"
ALL_PLAIN["redpacket.quality.cutout.background.detail"] = "Background complexity is high (%lld)"
ALL_PLAIN["redpacket.quality.cutout.fragmented.detail"] = "Cutout edge fragmentation detected (%lld)"
ALL_PLAIN["redpacket.quality.cutout.incomplete.detail"] = "Cutout subject completeness is %lld%%"
ALL_PLAIN["redpacket.quality.cutout.retry.detail"] = "Cutout precision score is %lld — please retry"
ALL_PLAIN["redpacket.quality.cutout.rough.detail"] = "Cutout edge roughness is %lld"
ALL_PLAIN["home.upcoming.adoption %@"] = "Adoption Anniversary"
ALL_PLAIN["notify.anniversary.adoption.body %@"] = "Relive the wonderful memories from the past year."

ALL_PLURALS: dict[str, dict[str, str]] = dict(PLURALS_EN)

print(f"Loaded {len(ALL_PLAIN)} plain translations and {len(ALL_PLURALS)} plural translations.")

FILES = [
    (REPO_ROOT / "MiLens" / "Resources" / "InfoPlist.xcstrings", "InfoPlist"),
    (REPO_ROOT / "MiLensWidget" / "Localizable.xcstrings", "Widget"),
    (REPO_ROOT / "MiLens" / "Resources" / "Localizable.xcstrings", "App"),
]


def check_and_apply():
    total_keys = 0
    missing_keys = []
    placeholder_errors = []
    pet_violations = []

    for path, kind in FILES:
        if not path.exists():
            sys.exit(f"Error: {path} not found")
        data = loc.load_xcstrings(path)
        strings = data.get("strings", {})
        source_lang = data.get("sourceLanguage", "zh-Hans")

        print(f"\nProcessing {path.name} ({kind}): {len(strings)} keys...")

        for key, entry in sorted(strings.items()):
            total_keys += 1
            src_loc = entry.get("localizations", {}).get(source_lang, {})
            is_plural = "variations" in src_loc and "plural" in src_loc["variations"]

            # 1. 检查是否存在翻译
            if is_plural:
                if key not in ALL_PLURALS:
                    missing_keys.append((kind, key, "Plural key missing from ALL_PLURALS"))
                    continue
                en_plural = ALL_PLURALS[key]
                if "one" not in en_plural or "other" not in en_plural:
                    missing_keys.append((kind, key, f"Plural key missing one/other: {en_plural}"))
                    continue

                # 占位符检查
                src_other = src_loc["variations"]["plural"].get("other", {}).get("stringUnit", {}).get("value", "")
                src_phs = set(PLACEHOLDER_RE.findall(src_other))
                en_other_phs = set(PLACEHOLDER_RE.findall(en_plural["other"]))
                if src_phs != en_other_phs:
                    placeholder_errors.append((kind, key, f"Source placeholders {src_phs} != EN other {en_other_phs}"))

                # 检查违规词 pet/pets
                for var, val in en_plural.items():
                    words = re.findall(r"\b[Pp]ets?\b", val)
                    if words:
                        pet_violations.append((kind, key, f"Found '{words}' in '{val}'"))

                # 注入回写
                loc_dict = entry.setdefault("localizations", {})
                loc_dict["en"] = {
                    "variations": {
                        "plural": {
                            "one": {
                                "stringUnit": {
                                    "state": "translated",
                                    "value": en_plural["one"],
                                }
                            },
                            "other": {
                                "stringUnit": {
                                    "state": "translated",
                                    "value": en_plural["other"],
                                }
                            }
                        }
                    }
                }

            else:
                if key not in ALL_PLAIN:
                    missing_keys.append((kind, key, "Plain key missing from ALL_PLAIN"))
                    continue
                en_val = ALL_PLAIN[key]

                # 占位符检查
                src_val = src_loc.get("stringUnit", {}).get("value", key)
                src_phs = set(PLACEHOLDER_RE.findall(src_val))
                en_phs = set(PLACEHOLDER_RE.findall(en_val))
                if src_phs != en_phs:
                    placeholder_errors.append((kind, key, f"Source placeholders {src_phs} != EN {en_phs}"))

                # 检查违规词 pet/pets
                # 白名单：SF Symbol、内部 key 等不计入；仅检查用户可见值中的孤立词
                words = re.findall(r"\b[Pp]ets?\b", en_val)
                if words:
                    pet_violations.append((kind, key, f"Found '{words}' in '{en_val}'"))

                # 注入回写
                loc_dict = entry.setdefault("localizations", {})
                loc_dict["en"] = {
                    "stringUnit": {
                        "state": "translated",
                        "value": en_val,
                    }
                }

        # 保存更新后的 xcstrings
        loc.save_xcstrings(path, data)
        print(f"Successfully saved {path.name} with English localizations.")

    print(f"\n=== Summary ===")
    print(f"Total keys processed: {total_keys}")
    print(f"Missing keys: {len(missing_keys)}")
    print(f"Placeholder errors: {len(placeholder_errors)}")
    print(f"Pal/Pet violations: {len(pet_violations)}")

    if missing_keys:
        print("\n--- Missing Keys ---")
        for kind, k, msg in missing_keys:
            print(f"[{kind}] {k}: {msg}")

    if placeholder_errors:
        print("\n--- Placeholder Errors ---")
        for kind, k, msg in placeholder_errors:
            print(f"[{kind}] {k}: {msg}")

    if pet_violations:
        print("\n--- 'Pet' Violations (Must use 'pal') ---")
        for kind, k, msg in pet_violations:
            print(f"[{kind}] {k}: {msg}")

    if missing_keys or placeholder_errors or pet_violations:
        print("\nFix the above issues before continuing.")
        return False

    print("\nAll keys verified and injected successfully!")
    return True


if __name__ == "__main__":
    success = check_and_apply()
    if not success:
        sys.exit(1)
