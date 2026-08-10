#!/usr/bin/env python3
"""MiLens 本地化工具链 GUI（tkinter 桌面版）。

对现有命令行工具链的图形化封装：
- tools/localization.py：String Catalog ↔ Excel 导出 / 导入 / 校验
- tools/localization-assets.py：全球本地化资产工作簿（9 sheet × 7 语种）

功能：
- 语言进度总览：knownRegions 声明的每语种 × 已译 / 初译待审 / 缺译，实时统计
- 缺译清单：逐 key 检查，双击复制 key 便于定位源码
- 一键操作：完整 check / 导出 Excel / 导入 Excel / 生成资产工作簿 / 打开工作簿
- 任务在后台线程执行，日志区实时输出，界面不冻结

用法：
  python tools/localization-gui.py                # 启动桌面 GUI
  python tools/localization-gui.py --self-check   # 无界面自检（CI / 无显示环境）

依赖：tkinter（Python 标准库）+ openpyxl（tools/requirements.txt）。
"""

from __future__ import annotations

import argparse
import contextlib
import io
import queue
import sys
import threading
from dataclasses import dataclass
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")  # Windows GBK 控制台无需 PYTHONUTF8=1

try:
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
except ImportError:  # --self-check 模式不需要 GUI
    tk = None  # type: ignore[assignment]

import localization as loc

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "MiLens" / "Resources"
XCSTRINGS = [
    RES / "Localizable.xcstrings",
    RES / "InfoPlist.xcstrings",
]
PROJECT_YML = ROOT / "project.yml"
SOURCE_ROOT = ROOT / "MiLens"
ASSETS_XLSX = ROOT / "docs" / "localization" / "global-localization.xlsx"

LANG_NAMES = {
    "zh-Hans": "简体中文",
    "zh-Hant": "繁體中文",
    "ja": "日本語",
    "ko": "한국어",
    "en": "English",
    "fr": "Français",
    "de": "Deutsch",
}


# --------------------------------------------------------------------------- #
# 纯逻辑层（不依赖 tkinter，可无头测试）
# --------------------------------------------------------------------------- #

@dataclass
class LangStatus:
    """某语言的翻译进度统计。"""

    lang: str
    name: str
    total: int = 0
    translated: int = 0
    needs_review: int = 0
    missing: int = 0
    is_source: bool = False

    @property
    def pct(self) -> int:
        if self.total == 0:
            return 0
        return round((self.translated + self.needs_review) * 100 / self.total)


def scan_statuses(xc_paths: list[Path] | None = None,
                  known: list[str] | None = None) -> list[LangStatus]:
    """统计各语言翻译进度（合并全部 .xcstrings）。

    缺译 = 无译文或 state=="new"；初译待审 = state=="needs_review"；
    已译 = state=="translated"。源语言行只作参照（translated=total）。
    """
    xc_paths = xc_paths or XCSTRINGS
    known = known or loc.parse_known_regions(PROJECT_YML)
    source = ""
    stats: dict[str, LangStatus] = {}
    for path in xc_paths:
        obj = loc.load_xcstrings(path)
        if not source:
            source = obj.get("sourceLanguage", "")
        strings = obj.get("strings", {})
        for lang in known:
            st = stats.setdefault(lang, LangStatus(lang, LANG_NAMES.get(lang, lang)))
            if lang == source:
                st.is_source = True
                st.total += len(strings)
                st.translated += len(strings)
                continue
            for key in strings:
                value, state = loc.entry_value_state(strings[key], lang)
                st.total += 1
                if not value or state == "new":
                    st.missing += 1
                elif state == "needs_review":
                    st.needs_review += 1
                else:
                    st.translated += 1
    return [stats[l] for l in known if l in stats]


def missing_problems(xc_paths: list[Path] | None = None,
                     known: list[str] | None = None) -> list[tuple[str, str, str]]:
    """返回 (lang, key, 说明) 缺译问题列表，与 `localization.py check` 缺译断言同语义。"""
    xc_paths = xc_paths or XCSTRINGS
    known = known or loc.parse_known_regions(PROJECT_YML)
    source = ""
    problems: list[tuple[str, str, str]] = []
    for path in xc_paths:
        obj = loc.load_xcstrings(path)
        if not source:
            source = obj.get("sourceLanguage", "")
        for key in sorted(obj.get("strings", {}).keys()):
            locs = obj["strings"][key].get("localizations", {})
            for lang in known:
                if lang == source:
                    continue
                unit = locs.get(lang, {}).get("stringUnit")
                if not unit:
                    problems.append((lang, key, f"{path.stem}：无译文"))
                elif unit.get("state") == "new" or not unit.get("value"):
                    problems.append((lang, key, f"{path.stem}：未完成（state={unit.get('state')!r}）"))
    return problems


# --------------------------------------------------------------------------- #
# 操作封装（复用 localization.py 子命令；stdout 由调用方重定向捕获）
# --------------------------------------------------------------------------- #

def run_check() -> str:
    ns = argparse.Namespace(
        xcstrings=[str(p) for p in XCSTRINGS],
        project_yml=str(PROJECT_YML),
        source_root=str(SOURCE_ROOT),
    )
    loc.cmd_check(ns)
    return "check 完成"


def run_export(out: Path, langs: str | None) -> str:
    ns = argparse.Namespace(
        xcstrings=[str(p) for p in XCSTRINGS],
        out=str(out),
        lang=langs,
    )
    loc.cmd_export(ns)
    return f"已导出 -> {out}"


def run_import(xlsx: Path, lang: str, targets: list[Path]) -> str:
    for target in targets:
        ns = argparse.Namespace(in_file=str(xlsx), xcstrings=str(target), lang=lang)
        loc.cmd_import(ns)
    return f"已导入语言「{lang}」→ {len(targets)} 个文件"


def run_build_assets() -> str:
    import localization_assets as assets
    assets.main()
    return f"已生成资产工作簿 -> {ASSETS_XLSX}"


# --------------------------------------------------------------------------- #
# GUI
# --------------------------------------------------------------------------- #

class LocalizationApp:
    """本地化工作台主窗口。"""

    TITLE = "MiLens 本地化工作台"
    SIZE = (1180, 760)

    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title(self.TITLE)
        self.root.geometry(f"{self.SIZE[0]}x{self.SIZE[1]}")
        self.root.minsize(960, 620)

        style = ttk.Style()
        style.theme_use("clam")
        style.configure("Treeview", rowheight=24)

        self._busy = 0  # 正在执行的后台任务数
        self._queue: queue.Queue = queue.Queue()

        self._build_toolbar()
        self._build_status_panel()
        self._build_problem_panel()
        self._build_log_panel()
        self._build_statusbar()

        self.refresh_status()
        self._log("就绪。语言进度来自 .xcstrings + project.yml knownRegions 实时统计。")

    # ---- 界面构建 --------------------------------------------------------- #

    def _build_toolbar(self) -> None:
        bar = ttk.Frame(self.root, padding=(8, 6))
        bar.pack(fill="x")
        self.btn_refresh = ttk.Button(bar, text="🔄 刷新状态", command=self.refresh_status)
        self.btn_refresh.pack(side="left")
        self.btn_check = ttk.Button(bar, text="✅ 完整 check", command=lambda: self.submit("check", run_check))
        self.btn_check.pack(side="left", padx=(6, 0))
        self.btn_export = ttk.Button(bar, text="📤 导出 Excel", command=self._ask_export)
        self.btn_export.pack(side="left", padx=(6, 0))
        self.btn_import = ttk.Button(bar, text="📥 导入 Excel", command=self._ask_import)
        self.btn_import.pack(side="left", padx=(6, 0))
        self.btn_assets = ttk.Button(bar, text="📊 生成资产工作簿", command=self._build_assets)
        self.btn_assets.pack(side="left", padx=(6, 0))
        self.btn_open = ttk.Button(bar, text="📂 打开工作簿", command=self._open_assets)
        self.btn_open.pack(side="left", padx=(6, 0))

        self._export_lang = ttk.Combobox(bar, width=12, state="readonly")
        self._export_lang.pack(side="right", padx=(0, 6))
        self._import_lang = ttk.Combobox(bar, width=12, state="readonly")
        self._import_lang.pack(side="right")
        ttk.Label(bar, text="导出语言：").pack(side="right")
        ttk.Label(bar, text="导入语言：").pack(side="right", padx=(12, 0))

    def _build_status_panel(self) -> None:
        box = ttk.LabelFrame(self.root, text="语言进度（knownRegions）", padding=6)
        box.pack(fill="x", padx=8, pady=(6, 4))
        cols = ("lang", "total", "translated", "needs_review", "missing", "pct")
        headers = {"lang": "语言", "total": "总 key", "translated": "已译",
                   "needs_review": "初译待审", "missing": "缺译", "pct": "完成率"}
        self.status_tree = ttk.Treeview(box, columns=cols, show="headings", height=6)
        for c in cols:
            self.status_tree.heading(c, text=headers[c])
            width = 220 if c == "lang" else 110
            self.status_tree.column(c, width=width, anchor="w" if c == "lang" else "center")
        self.status_tree.tag_configure("source", foreground="#8A7F75")
        self.status_tree.tag_configure("good", foreground="#1E7B45")
        self.status_tree.tag_configure("warn", foreground="#B8860B")
        self.status_tree.tag_configure("bad", foreground="#C0392B")
        self.status_tree.pack(fill="x")

    def _build_problem_panel(self) -> None:
        box = ttk.LabelFrame(self.root, text="缺译清单（双击复制 key）", padding=6)
        box.pack(fill="both", expand=True, padx=8, pady=4)
        cols = ("lang", "key", "note")
        self.problem_tree = ttk.Treeview(box, columns=cols, show="headings")
        self.problem_tree.heading("lang", text="语言")
        self.problem_tree.heading("key", text="key")
        self.problem_tree.heading("note", text="说明")
        self.problem_tree.column("lang", width=90, anchor="center")
        self.problem_tree.column("key", width=460)
        self.problem_tree.column("note", width=300)
        self.problem_tree.pack(fill="both", expand=True)
        self.problem_tree.bind("<Double-1>", self._copy_problem_key)

    def _build_log_panel(self) -> None:
        box = ttk.LabelFrame(self.root, text="日志", padding=6)
        box.pack(fill="both", expand=True, padx=8, pady=(4, 2))
        frame = ttk.Frame(box)
        frame.pack(fill="both", expand=True)
        self.log_text = tk.Text(frame, height=10, wrap="word", state="disabled",
                                font=("Consolas", 9))
        scroll = ttk.Scrollbar(frame, command=self.log_text.yview)
        self.log_text.configure(yscrollcommand=scroll.set)
        scroll.pack(side="right", fill="y")
        self.log_text.pack(side="left", fill="both", expand=True)

    def _build_statusbar(self) -> None:
        self.status_var = tk.StringVar(value="就绪")
        ttk.Label(self.root, textvariable=self.status_var, relief="sunken",
                  anchor="w", padding=(6, 2)).pack(fill="x", side="bottom")

    # ---- 状态与问题表 ------------------------------------------------------ #

    def refresh_status(self) -> None:
        self._set_busy(1)
        self._run_worker(self._load_status, self._paint_status)

    def _load_status(self) -> tuple[list[LangStatus], list[tuple[str, str, str]]]:
        return scan_statuses(), missing_problems()

    def _paint_status(self, data: tuple[list[LangStatus], list[tuple[str, str, str]]]) -> None:
        statuses, problems = data
        self.status_tree.delete(*self.status_tree.get_children())
        for s in statuses:
            if s.is_source:
                row = (f"{s.name}（{s.lang}，源语言）", str(s.total), str(s.total), "—", "—", "100%")
                tag = "source"
            else:
                row = (f"{s.name}（{s.lang}）", str(s.total), str(s.translated),
                       str(s.needs_review), str(s.missing), f"{s.pct}%")
                tag = "good" if s.missing == 0 else ("warn" if s.missing <= s.total * 0.2 else "bad")
            self.status_tree.insert("", "end", values=row, tags=(tag,))

        self.problem_tree.delete(*self.problem_tree.get_children())
        for lang, key, note in problems:
            name = LANG_NAMES.get(lang, lang)
            self.problem_tree.insert("", "end", values=(f"{name}（{lang}）", key, note))
        self.status_var.set(f"已更新：{len(statuses)} 语种，缺译 {len(problems)} 条")
        self._set_busy(-1)

    # ---- 后台任务 ---------------------------------------------------------- #

    def submit(self, title: str, fn) -> None:
        self._set_busy(1)
        self._log(f"▶ {title}…")
        self._run_worker(fn, self._on_task_done, title=title)

    def _run_worker(self, fn, on_done, **kwargs) -> None:
        q = queue.Queue()

        def worker() -> None:
            buf = io.StringIO()
            try:
                with contextlib.redirect_stdout(buf):
                    result = fn()
                q.put(("done", result, buf.getvalue()))
            except SystemExit as e:  # cmd_* 子命令以 sys.exit 结束
                q.put(("exit", e.code, buf.getvalue()))
            except Exception as e:  # noqa: BLE001 GUI 需兜底显示
                q.put(("error", repr(e), buf.getvalue() + "\n" + type(e).__name__ + ": " + str(e)))

        threading.Thread(target=worker, daemon=True).start()
        self.root.after(60, lambda: self._poll(q, on_done, **kwargs))

    def _poll(self, q: queue.Queue, on_done, **kwargs) -> None:
        try:
            kind, payload, out = q.get_nowait()
        except queue.Empty:
            self.root.after(60, lambda: self._poll(q, on_done, **kwargs))
            return
        if out:
            self._log(out.rstrip())
        if kind == "done":
            self._log(f"✔ {kwargs.get('title', '任务')}完成：{payload}")
            on_done(payload)
        elif kind == "exit":
            self._log(f"⚠ 任务以退出码 {payload} 结束（见上方输出）")
            self._set_busy(-1)
        else:
            self._log(f"✘ 任务失败：{payload}")
            self._set_busy(-1)

    def _on_task_done(self, result) -> None:
        self._set_busy(-1)
        self.refresh_status()

    def _set_busy(self, delta: int) -> None:
        self._busy += delta
        state = "disabled" if self._busy > 0 else "normal"
        for b in (self.btn_refresh, self.btn_check, self.btn_export,
                  self.btn_import, self.btn_assets, self.btn_open):
            b.configure(state=state)

    # ---- 导入 / 导出 / 工作簿 --------------------------------------------- #

    def _refresh_lang_combos(self) -> None:
        langs = [s.lang for s in scan_statuses() if not s.is_source]
        self._import_lang.configure(values=langs)
        if self._import_lang.get() not in langs:
            self._import_lang.set(langs[0] if langs else "")
        self._export_lang.configure(values=["全部已有语言"] + langs)
        if self._export_lang.get() not in self._export_lang.cget("values"):
            self._export_lang.set("全部已有语言")

    def _ask_export(self) -> None:
        self._refresh_lang_combos()
        default = ROOT / "docs" / "localization" / "export.xlsx"
        path = filedialog.asksaveasfilename(
            title="导出 String Catalog 到 Excel",
            defaultextension=".xlsx", initialfile=default.name, initialdir=default.parent,
            filetypes=[("Excel 工作簿", "*.xlsx")])
        if not path:
            return
        sel = self._export_lang.get()
        langs = None if sel in ("", "全部已有语言") else sel
        self.submit(f"导出 Excel（{sel or '全部'}）",
                    lambda: run_export(Path(path), langs))

    def _ask_import(self) -> None:
        self._refresh_lang_combos()
        path = filedialog.askopenfilename(
            title="选择翻译完成的 Excel",
            initialdir=ROOT / "docs" / "localization",
            filetypes=[("Excel 工作簿", "*.xlsx")])
        if not path:
            return
        lang = self._import_lang.get()
        if not lang:
            messagebox.showwarning("提示", "请先选择导入语言。")
            return
        targets = [RES / "Localizable.xcstrings", RES / "InfoPlist.xcstrings"]
        self.submit(f"导入 Excel → {lang}",
                    lambda: run_import(Path(path), lang, targets))

    def _build_assets(self) -> None:
        self.submit("生成资产工作簿", run_build_assets)

    def _open_assets(self) -> None:
        if not ASSETS_XLSX.exists():
            messagebox.showinfo("提示", f"工作簿尚未生成：{ASSETS_XLSX}\n请先点击「生成资产工作簿」。")
            return
        try:
            import os
            os.startfile(str(ASSETS_XLSX))  # Windows；macOS/Linux 见下方兜底
        except AttributeError:
            import subprocess
            opener = "open" if sys.platform == "darwin" else "xdg-open"
            subprocess.Popen([opener, str(ASSETS_XLSX)])

    # ---- 杂项 -------------------------------------------------------------- #

    def _copy_problem_key(self, _event) -> None:
        sel = self.problem_tree.selection()
        if not sel:
            return
        key = self.problem_tree.item(sel[0], "values")[1]
        self.root.clipboard_clear()
        self.root.clipboard_append(key)
        self._log(f"已复制 key：{key}")

    def _log(self, text: str) -> None:
        self.log_text.configure(state="normal")
        self.log_text.insert("end", text + "\n")
        self.log_text.see("end")
        self.log_text.configure(state="disabled")


# --------------------------------------------------------------------------- #
# 无界面自检（--self-check，供 CI / 无显示环境验证）
# --------------------------------------------------------------------------- #

def self_check() -> int:
    print("== MiLens 本地化 GUI 自检 ==")
    known = loc.parse_known_regions(PROJECT_YML)
    print(f"knownRegions = {known}")
    statuses = scan_statuses()
    problems = missing_problems()
    for s in statuses:
        mark = "源语言" if s.is_source else "缺译" if s.missing else ("初译待审" if s.needs_review else "已译")
        print(f"  {s.lang:8s} total={s.total:4d} translated={s.translated:4d} "
              f"needs_review={s.needs_review:3d} missing={s.missing:4d} {mark}")
    print(f"缺译问题 {len(problems)} 条")

    # 结构断言（数值不硬编码，只验证不变量）
    non_source = [s for s in statuses if not s.is_source]
    assert non_source, "knownRegions 中应存在非源语言"
    totals = {s.total for s in non_source}
    assert len(totals) == 1, f"各语言总 key 数应一致：{totals}"
    assert known == [s.lang for s in statuses], "语言顺序应与 knownRegions 一致"
    assert len(problems) == sum(s.missing for s in non_source), "缺译清单应与统计一致"

    print("自检通过：统计与缺译清单一致，无异常。")
    return 0


# --------------------------------------------------------------------------- #
# 入口
# --------------------------------------------------------------------------- #

def main() -> int:
    if "--self-check" in sys.argv:
        return self_check()
    if tk is None:
        sys.exit("错误：缺少 tkinter（Python 标准库），无法启动 GUI。请使用 --self-check 模式。")
    root = tk.Tk()
    app = LocalizationApp(root)  # noqa: F841 持有引用即存活
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
