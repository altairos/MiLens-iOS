#!/usr/bin/env python3
"""localization.py 单元测试（纯 stdlib，不依赖 openpyxl）。

覆盖 check 工具链的核心纯逻辑：每语言统计、needs_review 检测、占位符漂移、
长度规则、硬编码文案检测。运行：python tools/test_localization.py
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import localization as loc  # noqa: E402


def _unit(value: str, state: str = "translated") -> dict:
    return {"stringUnit": {"state": state, "value": value}}


def _entry(source_value: str, *lang_units: tuple[str, str, str], comment: str = "") -> dict:
    """构造普通条目；lang_units=(lang, value, state)。"""
    entry: dict = {"localizations": {"zh-Hans": _unit(source_value)}}
    if comment:
        entry["comment"] = comment
    for lang, value, state in lang_units:
        entry["localizations"][lang] = _unit(value, state)
    return entry


def _plural_entry(lang: str = "en", **variants: str) -> dict:
    """构造复数条目：variants 关键字为变体名 -> 值（均标 translated）。"""
    plural = {}
    for var, value in variants.items():
        plural[var] = {"stringUnit": {"state": "translated", "value": value}}
    return {"localizations": {
        lang: {"variations": {"plural": plural}}}}


def _obj(strings: dict) -> dict:
    return {"sourceLanguage": "zh-Hans", "strings": strings, "version": "1.0"}


class ScanStatusesTests(unittest.TestCase):
    def test_counts_translated_review_missing(self):
        obj = _obj({
            "k.ok": _entry("源", ("en", "ok", "translated")),
            "k.review": _entry("源", ("en", "draft", "needs_review")),
            "k.new": _entry("源", ("en", "", "new")),
            "k.empty": _entry("源"),  # en 无译文
        })
        sts = loc.scan_statuses([(Path("Localizable.xcstrings"), obj)],
                                ["zh-Hans", "en"])
        en = next(s for s in sts if s.lang == "en")
        self.assertEqual((en.total, en.translated, en.needs_review, en.missing),
                         (4, 1, 1, 2))
        self.assertFalse(en.is_source)
        zh = next(s for s in sts if s.lang == "zh-Hans")
        self.assertTrue(zh.is_source)

    def test_pct_full_when_translated(self):
        obj = _obj({"k": _entry("源", ("en", "ok", "translated"))})
        en = loc.scan_statuses([(Path("x"), obj)], ["zh-Hans", "en"])[1]
        self.assertEqual(en.pct, 100)

    def test_lang_names_known(self):
        self.assertEqual(loc.LANG_NAMES["zh-Hans"], "简体中文")
        self.assertEqual(loc.LANG_NAMES["de"], "Deutsch")


class ReviewProblemsTests(unittest.TestCase):
    def test_reports_needs_review_only(self):
        obj = _obj({
            "k.review": _entry("源", ("en", "draft", "needs_review")),
            "k.ok": _entry("源", ("en", "ok", "translated")),
        })
        probs = loc.review_problems(obj, Path("Localizable.xcstrings"),
                                    ["zh-Hans", "en"])
        self.assertEqual(len(probs), 1)
        self.assertEqual(probs[0][0], "en")
        self.assertIn("k.review", probs[0][1])

    def test_skips_empty(self):
        # 空 value 归 missing_problems，review_problems 不报
        obj = _obj({"k": _entry("源", ("en", "", "needs_review"))})
        self.assertEqual(loc.review_problems(obj, Path("x"),
                                             ["zh-Hans", "en"]), [])


class PlaceholderProblemsTests(unittest.TestCase):
    def test_missing_placeholder_reported(self):
        obj = _obj({"k": _entry("源 %d %@", ("en", "ok %d", "translated"))})
        probs = loc.placeholder_problems(obj, Path("x"), ["zh-Hans", "en"])
        self.assertEqual(len(probs), 1)
        self.assertIn("%@", probs[0][2])

    def test_matching_placeholders_ok(self):
        obj = _obj({"k": _entry("源 %d %@", ("en", "ok %d %@", "translated"))})
        self.assertEqual(loc.placeholder_problems(obj, Path("x"),
                                                  ["zh-Hans", "en"]), [])

    def test_source_without_placeholder_skipped(self):
        obj = _obj({"k": _entry("源", ("en", "ok", "translated"))})
        self.assertEqual(loc.placeholder_problems(obj, Path("x"),
                                                  ["zh-Hans", "en"]), [])

    def test_plural_entries_skipped(self):
        # 复数条目由 plural_problems 负责，此处不重复检查
        obj = _obj({"k": _plural_entry(one="1 %lld", other="%lld items")})
        self.assertEqual(loc.placeholder_problems(obj, Path("x"),
                                                  ["zh-Hans", "en"]), [])


class LengthRulesTests(unittest.TestCase):
    def test_resolve_priority_exact_over_prefix_over_default(self):
        rules = {"default": 5, "keys": {"exact": 10}, "prefixes": {"p.": 3}}
        self.assertEqual(loc.resolve_maxlen("exact", "", rules), 10)
        self.assertEqual(loc.resolve_maxlen("p.x", "", rules), 3)
        self.assertEqual(loc.resolve_maxlen("other", "", rules), 5)
        self.assertIsNone(loc.resolve_maxlen("k", "", {}))

    def test_comment_tag(self):
        rules = {"comment_tag": "len"}
        self.assertEqual(loc.resolve_maxlen("k", "按钮 [len:8]", rules), 8)

    def test_length_problems_reports_and_skips(self):
        rules = {"default": 3}
        obj = _obj({
            "k.long": _entry("源", ("en", "toolong", "translated")),
            "k.ok": _entry("源", ("en", "ok", "translated")),
        })
        probs = loc.length_problems(obj, Path("x"), ["zh-Hans", "en"], rules)
        self.assertEqual(len(probs), 1)
        self.assertIn("k.long", probs[0][1])
        self.assertEqual(loc.length_problems(obj, Path("x"),
                                             ["zh-Hans", "en"], {}), [])


class HardcodedTests(unittest.TestCase):
    def setUp(self) -> None:
        self._dir = tempfile.TemporaryDirectory()
        self.root = Path(self._dir.name)

    def tearDown(self) -> None:
        self._dir.cleanup()

    def _write(self, name: str, content: str) -> None:
        (self.root / name).write_text(content, encoding="utf-8")

    def test_detects_cjk_not_in_catalog(self):
        self._write("V.swift",
                    'Text("已收录")\nText("硬编码中文")\nText("plain")\n')
        probs = loc.hardcoded_problems(self.root, {"已收录"})
        texts = [p[2] for p in probs]
        self.assertIn("硬编码中文", texts)
        self.assertNotIn("已收录", texts)
        self.assertNotIn("plain", texts)  # 无 CJK 不报

    def test_interpolation_normalizes_to_catalog_key(self):
        # 插值字面量归一化后若命中 catalog 不报
        self._write("V.swift", 'Text("计数 \\(n)")\n')
        probs = loc.hardcoded_problems(self.root, {"计数 %lld"})
        self.assertEqual(probs, [])

    def test_decode_swift_string(self):
        self.assertEqual(loc._decode_swift_string("a\\nb"), "a\nb")
        self.assertEqual(loc._decode_swift_string('a\\"b'), 'a"b')


class ExtractCodeKeysTests(unittest.TestCase):
    def setUp(self) -> None:
        self._dir = tempfile.TemporaryDirectory()
        self.root = Path(self._dir.name)

    def tearDown(self) -> None:
        self._dir.cleanup()

    def _write(self, name: str, content: str) -> None:
        (self.root / name).write_text(content, encoding="utf-8")

    def test_extracts_literal_keys(self):
        self._write("V.swift",
                    'let a = String(localized: "k.a")\n'
                    'let b = NSLocalizedString("k.b", comment: "")\n')
        self.assertEqual(loc.extract_code_keys(self.root), {"k.a", "k.b"})

    def test_dynamic_mark_skips_line(self):
        # 数据驱动动态 key：行内 loc:dynamic 标记豁免提取，同文件其他行不受影响
        self._write("V.swift",
                    'NSLocalizedString("decoration.group.\\(id)", comment: "")  // loc:dynamic\n'
                    'NSLocalizedString("k.normal", comment: "")\n')
        self.assertEqual(loc.extract_code_keys(self.root), {"k.normal"})

    def test_mark_only_affects_own_line(self):
        # 标记只在所在行生效（行级语义，不是文件级）
        self._write("V.swift",
                    '// loc:dynamic\n'
                    'let a = String(localized: "k.a")\n')
        self.assertEqual(loc.extract_code_keys(self.root), {"k.a"})


class EntryPluralTests(unittest.TestCase):
    def test_plural_rule_type_ignored(self):
        # 历史 import 曾写入非法 pluralRuleType 键（已于 2026-08 清理），
        # entry_plural 对残留文件保持容忍：跳过非变体键
        entry = {"localizations": {"zh-Hans": {"variations": {"plural": {
            "pluralRuleType": "pluralRuleType",
            "other": {"stringUnit": {"state": "translated", "value": "%lld 天"}},
        }}}}}
        self.assertEqual(loc.entry_plural(entry, "zh-Hans"),
                         {"other": ("%lld 天", "translated")})

    def test_non_plural_entry_returns_none(self):
        self.assertIsNone(loc.entry_plural({"localizations": {}}, "en"))


class NormalizeKeyTests(unittest.TestCase):
    def test_interpolation_normalized(self):
        self.assertEqual(loc.normalize_localized_key("k \\(x)"), "k %lld")

    def test_placeholder_normalized(self):
        self.assertEqual(loc.normalize_localized_key("k %@"), "k %lld")
        self.assertEqual(loc.normalize_localized_key("k %1$@"), "k %lld")


if __name__ == "__main__":
    unittest.main(verbosity=2)
