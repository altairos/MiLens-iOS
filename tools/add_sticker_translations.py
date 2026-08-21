#!/usr/bin/env python3
"""为 12 款贴纸补充多语言本地化翻译。"""

from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
XCSTRINGS_PATH = REPO_ROOT / "MiLens" / "Resources" / "Localizable.xcstrings"

translations = {
    "decoration.sticker.sunPaw": {
        "zh-Hans": "暖阳爪印",
        "zh-Hant": "暖陽爪印",
        "en": "Sun Paw",
        "ja": "陽だまり肉球",
        "ko": "햇살 발자국",
        "fr": "Patte Solaire",
        "de": "Sonnenpfote",
    },
    "decoration.sticker.pawMark": {
        "zh-Hans": "档案足印",
        "zh-Hant": "檔案足印",
        "en": "Archive Paw",
        "ja": "記録の足跡",
        "ko": "아카이브 발자국",
        "fr": "Empreinte d'Archive",
        "de": "Archiv-Pfotenabdruck",
    },
    "decoration.sticker.tandemPaws": {
        "zh-Hans": "步步相伴",
        "zh-Hant": "步步相伴",
        "en": "Tandem Paws",
        "ja": "よりそう足跡",
        "ko": "나란한 발자국",
        "fr": "Pas à Pas",
        "de": "Schritt für Schritt",
    },
    "decoration.sticker.warmHeart": {
        "zh-Hans": "温存心痕",
        "zh-Hant": "溫存心痕",
        "en": "Warm Heart",
        "ja": "ぬくもりハート",
        "ko": "따스한 마음",
        "fr": "Cœur Tendre",
        "de": "Warmes Herz",
    },
    "decoration.sticker.bloomFlower": {
        "zh-Hans": "春日花期",
        "zh-Hant": "春日花期",
        "en": "Spring Bloom",
        "ja": "春の花盛り",
        "ko": "봄날의 꽃",
        "fr": "Fleur Printanière",
        "de": "Frühlingsblüte",
    },
    "decoration.sticker.retroCamera": {
        "zh-Hans": "定格镜头",
        "zh-Hant": "定格鏡頭",
        "en": "Retro Shutter",
        "ja": "フィルムカメラ",
        "ko": "필름 카메라",
        "fr": "Instant Figé",
        "de": "Retro-Kamera",
    },
    "decoration.sticker.foodBowl": {
        "zh-Hans": "满满食光",
        "zh-Hant": "滿滿食光",
        "en": "Full Bowl",
        "ja": "ごはんタイム",
        "ko": "행복한 밥그릇",
        "fr": "Gamelle Gourmande",
        "de": "Futternapf",
    },
    "decoration.sticker.sleepyMoon": {
        "zh-Hans": "甜梦月影",
        "zh-Hant": "甜夢月影",
        "en": "Sleepy Moon",
        "ja": "おやすみ月夜",
        "ko": "달콤한 꿈달",
        "fr": "Douce Lune",
        "de": "Schlummernder Mond",
    },
    "decoration.sticker.radiantStar": {
        "zh-Hans": "守护微光",
        "zh-Hant": "守護微光",
        "en": "Radiant Star",
        "ja": "輝く守り星",
        "ko": "수호의 별빛",
        "fr": "Étoile Protectrice",
        "de": "Strahlender Stern",
    },
    "decoration.sticker.archiveSeal": {
        "zh-Hans": "珍藏火漆印",
        "zh-Hant": "珍藏火漆印",
        "en": "Archive Seal",
        "ja": "記念のシーリング",
        "ko": "기념 씰",
        "fr": "Sceau d'Archive",
        "de": "Archiv-Siegel",
    },
    "decoration.sticker.adoptionRibbon": {
        "zh-Hans": "家人丝带",
        "zh-Hant": "家人絲帶",
        "en": "Family Ribbon",
        "ja": "家族のリボン",
        "ko": "가족 리본",
        "fr": "Ruban de Famille",
        "de": "Familienband",
    },
    "decoration.sticker.birthdayCake": {
        "zh-Hans": "诞辰烛光",
        "zh-Hant": "誕辰燭光",
        "en": "Birthday Candle",
        "ja": "バースデーケーキ",
        "ko": "생일 촛불",
        "fr": "Bougie d'Anniversaire",
        "de": "Geburtstagskerze",
    },
}


def main():
    with XCSTRINGS_PATH.open("r", encoding="utf-8") as f:
        d = json.load(f)

    strings = d.setdefault("strings", {})
    for k, lang_dict in translations.items():
        if k not in strings:
            strings[k] = {"extractionState": "manual", "localizations": {}}
        for lang, val in lang_dict.items():
            strings[k].setdefault("localizations", {})[lang] = {
                "stringUnit": {
                    "state": "translated",
                    "value": val,
                }
            }

    with XCSTRINGS_PATH.open("w", encoding="utf-8") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"成功为 12 款贴纸写入多语言翻译到 {XCSTRINGS_PATH}")


if __name__ == "__main__":
    main()
