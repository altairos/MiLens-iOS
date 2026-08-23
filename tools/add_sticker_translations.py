#!/usr/bin/env python3
"""为 MiLens/Resources/Localizable.xcstrings 注入 12 款贴纸的多语言本地化与 a11y 词条。

支持语言：zh-Hans, zh-Hant, en, ja, ko, fr, de。
"""

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
XCSTRINGS_PATH = REPO_ROOT / "MiLens" / "Resources" / "Localizable.xcstrings"

TRANSLATIONS = {
    "decoration.sticker.sunPaw": {
        "zh-Hans": "暖阳爪印",
        "zh-Hant": "暖陽爪印",
        "en": "Sun Paw",
        "ja": "陽だまりの肉球",
        "ko": "햇살 발자국",
        "fr": "Patte ensoleillée",
        "de": "Sonnenpfote",
    },
    "decoration.sticker.pawMark": {
        "zh-Hans": "档案足印",
        "zh-Hant": "檔案足印",
        "en": "Archive Paw",
        "ja": "アーカイブの足跡",
        "ko": "기록 발자국",
        "fr": "Empreinte d'archive",
        "de": "Archivpfote",
    },
    "decoration.sticker.tandemPaws": {
        "zh-Hans": "步步相伴",
        "zh-Hant": "步步相伴",
        "en": "Tandem Paws",
        "ja": "よりそう足跡",
        "ko": "함께 걷는 발자국",
        "fr": "Pas à pas",
        "de": "Schritt für Schritt",
    },
    "decoration.sticker.warmHeart": {
        "zh-Hans": "温存心痕",
        "zh-Hant": "溫存心痕",
        "en": "Warm Heart",
        "ja": "温かなハート",
        "ko": "따스한 하트",
        "fr": "Cœur chaleureux",
        "de": "Warmes Herz",
    },
    "decoration.sticker.bloomFlower": {
        "zh-Hans": "春日花期",
        "zh-Hant": "春日花期",
        "en": "Spring Bloom",
        "ja": "春の開花",
        "ko": "봄날의 꽃",
        "fr": "Éclosion printanière",
        "de": "Frühlingsblüte",
    },
    "decoration.sticker.retroCamera": {
        "zh-Hans": "定格镜头",
        "zh-Hant": "定格鏡頭",
        "en": "Retro Camera",
        "ja": "レトロカメラ",
        "ko": "레트로 카메라",
        "fr": "Appareil rétro",
        "de": "Retro-Kamera",
    },
    "decoration.sticker.foodBowl": {
        "zh-Hans": "满满食光",
        "zh-Hant": "滿滿食光",
        "en": "Full Bowl",
        "ja": "ごはんのじかん",
        "ko": "맛있는 식사",
        "fr": "Bol gourmand",
        "de": "Futternapf",
    },
    "decoration.sticker.sleepyMoon": {
        "zh-Hans": "甜梦月影",
        "zh-Hant": "甜夢月影",
        "en": "Sleepy Moon",
        "ja": "おやすみ月",
        "ko": "달콤한 꿈의 달",
        "fr": "Lune endormie",
        "de": "Schlafender Mond",
    },
    "decoration.sticker.radiantStar": {
        "zh-Hans": "守护微光",
        "zh-Hant": "守護微光",
        "en": "Radiant Star",
        "ja": "輝く星",
        "ko": "수호의 별빛",
        "fr": "Étoile radieuse",
        "de": "Strahlender Stern",
    },
    "decoration.sticker.archiveSeal": {
        "zh-Hans": "珍藏火漆印",
        "zh-Hant": "珍藏火漆印",
        "en": "Archive Seal",
        "ja": "アーカイブシーリング",
        "ko": "소장용 씰",
        "fr": "Sceau d'archive",
        "de": "Archiv-Siegel",
    },
    "decoration.sticker.adoptionRibbon": {
        "zh-Hans": "家人丝带",
        "zh-Hant": "家人絲帶",
        "en": "Family Ribbon",
        "ja": "家族のリボン",
        "ko": "가족 리본",
        "fr": "Ruban de famille",
        "de": "Familienband",
    },
    "decoration.sticker.birthdayCake": {
        "zh-Hans": "诞辰烛光",
        "zh-Hant": "誕辰燭光",
        "en": "Birthday Candle",
        "ja": "バースデーキャンドル",
        "ko": "생일 촛불",
        "fr": "Bougie d'anniversaire",
        "de": "Geburtstagskerze",
    },
}


def main():
    with open(XCSTRINGS_PATH, "r", encoding="utf-8") as f:
        catalog = json.load(f)

    strings = catalog.setdefault("strings", {})

    added = 0
    updated = 0

    for key, loc_map in TRANSLATIONS.items():
        entry = strings.setdefault(key, {
            "extractionState": "manual",
            "localizations": {}
        })
        is_new = len(entry.get("localizations", {})) == 0

        for lang, val in loc_map.items():
            entry["localizations"][lang] = {
                "stringUnit": {
                    "state": "translated",
                    "value": val
                }
            }

        if is_new:
            added += 1
        else:
            updated += 1
        print(f"  [注入] {key} ({loc_map['zh-Hans']} / {loc_map['en']})")

    # Xcode xcstrings 原生序列化：冒号前带空格（" : "）且 strings 按字母序；
    # 缺省 json.dump（"key": value + 追加到末尾）会产生全文件噪音 diff（2026-08-24 实际踩坑）。
    with open(XCSTRINGS_PATH, "w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2, separators=(",", " : "), sort_keys=True, ensure_ascii=False)
        f.write("\n")

    print(f"\n成功完成 Localizable.xcstrings 贴纸 a11y/本地化词条注入！新增: {added}, 更新: {updated}")


if __name__ == "__main__":
    main()
