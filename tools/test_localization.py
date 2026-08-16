#!/usr/bin/env python3
"""localization.py 单元测试（纯 stdlib，不依赖 openpyxl）。

覆盖 check 工具链的核心纯逻辑：每语言统计、needs_review 检测、占位符漂移、
长度规则、硬编码文案检测、多 catalog × 多源码根配对、Excel sheet 命名。
运行：python tools/test_localization.py
"""

from __future__ import annotations

import argparse
import contextlib
import io
import json
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
        self.assertEqual(loc._decode_swift_string("\\u{FF0B}"), "＋")
        self.assertEqual(loc._decode_swift_string("\\u4f60\\u597d"), "你好")

    def test_decoration_detects_uppercase_latin(self):
        # 英文装饰（warning 级）：纯拉丁 + 全大写词命中；
        # 品牌词 / 白名单缩写 / 无全大写词的文案放过；CJK 归 hardcoded_problems。
        self._write("V.swift",
                    'Text("PATTERN PARAMETERS")\n'
                    'Text("EMPTY ARCHIVE / 00")\n'
                    'Text("MiLens")\n'
                    'Text("PRO")\n'
                    'Text("Pro · A4 PDF")\n'
                    'Text("中文文案")\n')
        probs = loc.decoration_problems(self.root, set())
        texts = [p[2] for p in probs]
        self.assertIn("PATTERN PARAMETERS", texts)
        self.assertIn("EMPTY ARCHIVE / 00", texts)
        self.assertNotIn("MiLens", texts)          # 无全大写词
        self.assertNotIn("PRO", texts)              # 白名单
        self.assertNotIn("Pro · A4 PDF", texts)     # PDF 白名单
        self.assertNotIn("中文文案", texts)          # CJK 不归装饰分支

    def test_decoration_skips_catalog_and_interpolation(self):
        # 已在 catalog（精确或插值归一化后）命中则放过
        self._write("V.swift",
                    'Text("PET CARD")\n'
                    'Text("LIFE 02 · \\(n) DAYS")\n')
        probs = loc.decoration_problems(
            self.root, {"PET CARD", "LIFE 02 · %lld DAYS"})
        self.assertEqual(probs, [])

    def test_decoration_skips_unicode_escape_and_brand_watermarks(self):
        # Swift \u{XXXX} 转义还原后为非拉丁字符，不因转义源码形态误报；
        # MILENS 复合品牌水印整串白名单放过（全语言通用，保留硬编码）。
        self._write("V.swift",
                    'Text("\\u{FF0B}")\n'
                    'Text("MILENS · LIFE ARCHIVE")\n'
                    'Text("MILENS PET PROFILE")\n')
        probs = loc.decoration_problems(self.root, set())
        self.assertEqual(probs, [])


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

    def test_widget_config_api_forms(self):
        # WidgetKit/AppIntents 配置面 API：参数类型 LocalizedStringResource，
        # 传 key 即查表，语义上只能是 key，无条件收
        self._write("W.swift",
                    '.configurationDisplayName("widget.lifeArchive.name")\n'
                    '.description("widget.lifeArchive.desc")\n'
                    'IntentDescription("widget.entity.pet")\n'
                    '@Parameter(title: "widget.entity.pet")\n'
                    'static var title: LocalizedStringResource = "widget.photoEcho.title"\n'
                    'typeDisplayRepresentation: TypeDisplayRepresentation = "widget.entity.pet"\n')
        self.assertEqual(loc.extract_code_keys(self.root),
                         {"widget.lifeArchive.name", "widget.lifeArchive.desc",
                          "widget.entity.pet", "widget.photoEcho.title"})

    def test_text_dotted_key_forms(self):
        # Text 参数是 LocalizedStringKey（运行时查表）：dotted 形态视为 key 引用
        # （含插值归一化）；品牌/装饰文案不匹配 dotted 形态，不误报
        self._write("W.swift",
                    'Text("widget.lifeArchive.name")\n'
                    'Text("widget.stale.updated \\(date)")\n'
                    'Text("MiLens")\n'
                    'Text("FIRST LIGHT · 欢迎")\n')
        self.assertEqual(loc.extract_code_keys(self.root),
                         {"widget.lifeArchive.name", "widget.stale.updated \\(date)"})

    def test_case_display_representations_dict(self):
        # AppEnum caseDisplayRepresentations 字典条目（.case: "key"）
        self._write("W.swift",
                    'caseDisplayRepresentations: [\n'
                    '    .todayOrRecent: "widget.intents.photoEcho.source.todayOrRecent",\n'
                    '    .byPet: "widget.intents.photoEcho.source.byPet"\n'
                    ']\n')
        self.assertEqual(loc.extract_code_keys(self.root),
                         {"widget.intents.photoEcho.source.todayOrRecent",
                          "widget.intents.photoEcho.source.byPet"})

    def test_switch_case_symbol_mapping_not_key(self):
        # switch 映射 case .xxx: "sf.symbol.name" 是 SF Symbol 名而非本地化 key，
        # 字典形态用 (?<!case\s) 排除，避免误报缺 key
        self._write("V.swift",
                    'switch self {\n'
                    'case .petProfiles: "pawprint.fill"\n'
                    'case .timeline: "clock.arrow.circlepath"\n'
                    '}\n')
        self.assertEqual(loc.extract_code_keys(self.root), set())


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


class SheetNameTests(unittest.TestCase):
    def test_single_catalog_keeps_stem(self):
        # stem 唯一（含 InfoPlist）时保持原名，旧表导入兼容
        app = Path("MiLens/Resources/Localizable.xcstrings")
        plist = Path("MiLens/Resources/InfoPlist.xcstrings")
        self.assertEqual(loc.sheet_name_for(app, [app, plist]), "Localizable")
        self.assertEqual(loc.sheet_name_for(plist, [app, plist]), "InfoPlist")

    def test_duplicate_stems_disambiguated_by_parent(self):
        # App 与 Widget 的 catalog 都叫 Localizable：用父目录名去歧义
        app = Path("MiLens/Resources/Localizable.xcstrings")
        widget = Path("MiLensWidget/Localizable.xcstrings")
        both = [app, widget]
        self.assertEqual(loc.sheet_name_for(app, both), "Resources.Localizable")
        self.assertEqual(loc.sheet_name_for(widget, both),
                         "MiLensWidget.Localizable")


class ImportSheetResolveTests(unittest.TestCase):
    def test_prefers_plain_stem(self):
        xc = Path("MiLensWidget/Localizable.xcstrings")
        self.assertEqual(
            loc.resolve_import_sheet(xc, ["Localizable", "MiLensWidget.Localizable"]),
            "Localizable")

    def test_falls_back_to_disambiguated(self):
        # 双 catalog 导出的表无裸 stem：回退去歧义名各取所需
        xc = Path("MiLensWidget/Localizable.xcstrings")
        self.assertEqual(
            loc.resolve_import_sheet(
                xc, ["Resources.Localizable", "MiLensWidget.Localizable"]),
            "MiLensWidget.Localizable")

    def test_missing_returns_none(self):
        xc = Path("MiLens/Resources/Localizable.xcstrings")
        self.assertIsNone(loc.resolve_import_sheet(xc, ["别的"]))


class MultiRootCheckTests(unittest.TestCase):
    """多 catalog × 多源码根：各 Localizable 只与路径祖先根的代码比对。"""

    def setUp(self) -> None:
        self._dir = tempfile.TemporaryDirectory()
        self.root = Path(self._dir.name)
        self.app_root = self.root / "App"
        self.widget_root = self.root / "Widget"

    def tearDown(self) -> None:
        self._dir.cleanup()

    def _swift(self, root: Path, name: str, key: str) -> None:
        root.mkdir(parents=True, exist_ok=True)
        (root / name).write_text(
            f'let s = String(localized: "{key}")\n', encoding="utf-8")

    def _xc(self, rel: str, keys: list[str]) -> Path:
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(_obj({k: _entry(k) for k in keys}),
                                ensure_ascii=False), encoding="utf-8")
        return p

    def _check(self, xcs: list[Path]) -> tuple[int, str]:
        buf = io.StringIO()
        ns = argparse.Namespace(
            xcstrings=[str(p) for p in xcs],
            project_yml=None,
            source_root=[str(self.app_root), str(self.widget_root)],
        )
        with contextlib.redirect_stdout(buf):
            code = loc.cmd_check(ns)
        return code, buf.getvalue()

    def test_each_catalog_pairs_with_own_root(self):
        self._swift(self.app_root, "V.swift", "app.key")
        self._swift(self.widget_root, "W.swift", "widget.key")
        app_xc = self._xc("App/Resources/Localizable.xcstrings", ["app.key"])
        widget_xc = self._xc("Widget/Localizable.xcstrings", ["widget.key"])
        code, out = self._check([app_xc, widget_xc])
        self.assertEqual(code, 0)
        self.assertNotIn("[缺 key]", out)
        self.assertNotIn("[多余 key]", out)

    def test_missing_reported_only_by_owning_catalog(self):
        # Widget 代码引用 widget.key 但 Widget catalog 缺失：只报一次；
        # App catalog 不因 Widget 根的引用误报（祖先根配对不串扰）。
        self._swift(self.app_root, "V.swift", "app.key")
        self._swift(self.widget_root, "W.swift", "widget.key")
        app_xc = self._xc("App/Resources/Localizable.xcstrings", ["app.key"])
        widget_xc = self._xc("Widget/Localizable.xcstrings", [])
        code, out = self._check([app_xc, widget_xc])
        self.assertEqual(code, 1)
        self.assertEqual(out.count("[缺 key]"), 1)
        self.assertIn("'widget.key'", out)

    def test_extra_checked_against_own_root_only(self):
        # Widget catalog 混入 app.only：App 根的字面量不参与 Widget 比对报 extra
        # （warning 不阻断）；App 侧无任何告警。
        self._swift(self.app_root, "V.swift", "app.key")
        widget_xc = self._xc("Widget/Localizable.xcstrings", ["app.only"])
        code, out = self._check([widget_xc])
        self.assertEqual(code, 0)
        self.assertIn("app.only", out)

    def test_catalog_without_ancestor_falls_back_to_all_roots(self):
        # catalog 不在任何根下（如独立交付表）：回退全部根并集，
        # 两边代码字面量均豁免 extra。
        self._swift(self.app_root, "V.swift", "app.key")
        self._swift(self.widget_root, "W.swift", "widget.key")
        other_xc = self._xc("Other/Localizable.xcstrings",
                            ["app.key", "widget.key"])
        code, out = self._check([other_xc])
        self.assertEqual(code, 0)
        self.assertNotIn("[多余 key]", out)


if __name__ == "__main__":
    unittest.main(verbosity=2)
