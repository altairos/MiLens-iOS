#!/usr/bin/env python3
"""MiLens 相框素材导入 GUI（tkinter 桌面版）。

对 tools/frame_import.py 命令行工具的图形化封装，提供：
- 源目录扫描：实时列出每个素材的 manifest 状态、PNG 完整性
- manifest 可视化编辑：表单字段 + fitMode 联动（stretch/ninePatch/ratioSet）
- PNG 预览 + 九宫格叠加：拖动滑块实时调整 inset，所见即所得
- 一键操作：扫描 / 新建模板 / 导入工程 / 校验 / 列表 catalog
- 后台线程执行，日志区实时输出，界面不冻结

用法：
  python tools/frame-import-gui.py                # 启动桌面 GUI
  python tools/frame-import-gui.py --self-check   # 无界面自检（CI / 无显示环境）

依赖：tkinter（Python 标准库）。PNG 预览使用 tkinter.PhotoImage（支持 PNG，无需 Pillow）。
"""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import queue
import sys
import threading
from dataclasses import dataclass, field
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")  # Windows GBK 控制台无需 PYTHONUTF8=1

try:
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
except ImportError:  # --self-check 模式不需要 GUI
    tk = None  # type: ignore[assignment]

import frame_import as fi

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = ROOT / "assets_src"
STANDARD_RATIOS = ["1x1", "3x4", "4x3", "16x9", "9x16", "2x3", "3x2"]

FITMODE_LABELS = {
    "stretch": "拉伸铺满（stretch）— 角部会变形，仅适合纯色边框",
    "nine_patch": "九宫格（ninePatch）— 角部不变形，几何/线条相框推荐",
    "ratio_set": "多比例（ratioSet）— 按照片比例自动选最优 PNG",
}


# --------------------------------------------------------------------------- #
# 纯逻辑层（不依赖 tkinter，可无头测试）
# --------------------------------------------------------------------------- #

@dataclass
class FrameItemStatus:
    """扫描源目录得到的单项状态。"""
    dir_path: Path
    manifest: dict | None
    errors: list[str] = field(default_factory=list)
    pngs: list[tuple[str, Path]] = field(default_factory=list)

    @property
    def item_id(self) -> str:
        return self.manifest.get("id", "") if self.manifest else self.dir_path.name

    @property
    def has_manifest(self) -> bool:
        return self.manifest is not None

    @property
    def fit_mode(self) -> str:
        return self.manifest.get("fit_mode", "stretch") if self.manifest else "stretch"

    @property
    def category(self) -> str:
        return self.manifest.get("category", "frame") if self.manifest else "frame"

    @property
    def png_count(self) -> int:
        return len(self.pngs)

    @property
    def status_label(self) -> str:
        if not self.has_manifest:
            return "缺 manifest"
        if self.errors:
            return f"错误×{len(self.errors)}"
        if self.png_count == 0:
            return "缺 PNG"
        return "✓就绪"


def scan_source_dir(source: Path) -> list[FrameItemStatus]:
    """扫描源目录下每个子目录，返回每项状态（含 manifest 校验 + PNG 探测）。"""
    if not source.is_dir():
        return []
    results: list[FrameItemStatus] = []
    for d in sorted(source.iterdir()):
        if not d.is_dir():
            continue
        status = FrameItemStatus(dir_path=d, manifest=fi.load_manifest(d))
        if status.manifest:
            status.errors = list(fi.validate_manifest(status.manifest, d.name))
            status.pngs = fi.find_pngs(d, status.item_id, status.fit_mode)
            # ratio_set 模式：声明的 ratio 必须都有对应 PNG
            if status.fit_mode == "ratio_set":
                declared = status.manifest.get("supported_ratios") or []
                found_tokens = {t for t, _ in status.pngs}
                missing = [r for r in declared if r not in found_tokens]
                if missing:
                    status.errors.append(f"声明 ratio 缺 PNG：{missing}")
        else:
            # 无 manifest，用目录名探测是否有 PNG（提示用户补 manifest）
            status.pngs = fi.find_pngs(d, d.name, "stretch")
        results.append(status)
    return results


def load_form_from_manifest(manifest: dict | None, fallback_id: str) -> dict:
    """从 manifest（可能为 None）构造 GUI 表单初始值。"""
    if not manifest:
        return {
            "id": fallback_id, "name": fallback_id, "category": "frame",
            "fit_mode": "stretch", "is_premium": False, "group": "基础",
            "sort_order": 0, "inset_top": 0, "inset_left": 0,
            "inset_bottom": 0, "inset_right": 0,
            "supported_ratios": [], "native_aspect_ratio": None,
            "preview_path": None,
        }
    insets = manifest.get("nine_patch_insets") or {}
    return {
        "id": manifest.get("id", fallback_id),
        "name": manifest.get("name", fallback_id),
        "category": manifest.get("category", "frame"),
        "fit_mode": manifest.get("fit_mode", "stretch"),
        "is_premium": bool(manifest.get("is_premium", False)),
        "group": manifest.get("group", "基础"),
        "sort_order": int(manifest.get("sort_order", 0)),
        "inset_top": int(insets.get("top", 0)),
        "inset_left": int(insets.get("left", 0)),
        "inset_bottom": int(insets.get("bottom", 0)),
        "inset_right": int(insets.get("right", 0)),
        "supported_ratios": list(manifest.get("supported_ratios") or []),
        "native_aspect_ratio": manifest.get("native_aspect_ratio"),
        "preview_path": manifest.get("preview_path"),
    }


def manifest_from_form(form: dict) -> dict:
    """从 GUI 表单数据构造 manifest dict（snake_case，写回 frame.json）。"""
    m: dict = {
        "id": form["id"].strip(),
        "name": form["name"].strip() or form["id"].strip(),
        "category": form["category"],
        "fit_mode": form["fit_mode"],
        "is_premium": bool(form["is_premium"]),
        "group": form["group"].strip() or "基础",
        "sort_order": int(form["sort_order"] or 0),
        "native_aspect_ratio": form.get("native_aspect_ratio"),
        "preview_path": form.get("preview_path") or None,
    }
    if form["fit_mode"] == "nine_patch":
        m["nine_patch_insets"] = {
            "top": int(form["inset_top"]),
            "left": int(form["inset_left"]),
            "bottom": int(form["inset_bottom"]),
            "right": int(form["inset_right"]),
        }
        m["supported_ratios"] = None
    elif form["fit_mode"] == "ratio_set":
        m["nine_patch_insets"] = None
        m["supported_ratios"] = sorted(set(form.get("supported_ratios", [])))
    else:  # stretch
        m["nine_patch_insets"] = None
        m["supported_ratios"] = None
    return m


def save_manifest(frame_dir: Path, manifest: dict) -> Path:
    """把 manifest 写到 frame_dir/frame.json（保留 _comment 字段）。"""
    path = frame_dir / "frame.json"
    # 若已存在文件且含 _comment，保留该字段
    if path.exists():
        try:
            old = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(old, dict) and "_comment" in old:
                manifest = {"_comment": old["_comment"], **manifest}
        except (json.JSONDecodeError, OSError):
            pass
    with path.open("w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    return path


def nine_patch_preview_lines(img_w: int, img_h: int, insets: dict) -> dict:
    """返回九宫格 4 条参考线在图像空间的坐标（用于 Canvas 叠加绘制，纯函数可无头测试）。

    返回 {"v_left", "v_right", "h_top", "h_bottom"}；inset 非法时返回全 0。
    """
    top = max(0, min(int(insets.get("top", 0)), img_h))
    left = max(0, min(int(insets.get("left", 0)), img_w))
    bottom = max(0, min(int(insets.get("bottom", 0)), img_h))
    right = max(0, min(int(insets.get("right", 0)), img_w))
    if top + bottom >= img_h or left + right >= img_w:
        return {"v_left": 0, "v_right": img_w, "h_top": 0, "h_bottom": img_h}
    return {
        "v_left": left,
        "v_right": img_w - right,
        "h_top": top,
        "h_bottom": img_h - bottom,
    }


# --------------------------------------------------------------------------- #
# 操作封装（复用 frame_import.py 子命令；stdout 由调用方重定向捕获）
# --------------------------------------------------------------------------- #

def run_add(source: Path, assets: Path, catalog: Path,
            group: str | None = None, premium: bool = False) -> str:
    ns = argparse.Namespace(
        source=str(source), assets=str(assets), catalog=str(catalog),
        group=group, premium=premium, dry_run=False,
    )
    fi.cmd_add(ns)
    return f"已导入 {source}"


def run_validate(catalog: Path, assets: Path) -> str:
    ns = argparse.Namespace(catalog=str(catalog), assets=str(assets))
    rc = fi.cmd_validate(ns)
    return "校验通过" if rc == 0 else f"校验失败（exit={rc}）"


def run_list(catalog: Path) -> str:
    ns = argparse.Namespace(catalog=str(catalog))
    fi.cmd_list(ns)
    return "列表完成"


def run_init(target: Path, item_id: str | None = None, name: str | None = None) -> str:
    ns = argparse.Namespace(target=str(target), id=item_id, name=name)
    fi.cmd_init(ns)
    return f"已初始化 {target}"


# --------------------------------------------------------------------------- #
# GUI
# --------------------------------------------------------------------------- #

class FrameImportApp:
    """相框素材工作台主窗口。"""

    TITLE = "MiLens 相框素材工作台"
    SIZE = (1280, 840)
    PREVIEW_SIZE = 360  # PNG 预览 Canvas 边长

    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title(self.TITLE)
        self.root.geometry(f"{self.SIZE[0]}x{self.SIZE[1]}")
        self.root.minsize(1040, 700)

        style = ttk.Style()
        style.theme_use("clam")
        style.configure("Treeview", rowheight=24)

        # 路径状态
        self.source_var = tk.StringVar(value=str(DEFAULT_SOURCE))
        self.assets_var = tk.StringVar(value=str(fi.DEFAULT_ASSETS))
        self.catalog_var = tk.StringVar(value=str(fi.DEFAULT_CATALOG))

        # 表单变量
        self._form: dict[str, tk.Variable] = {}
        self._ratio_vars: dict[str, tk.BooleanVar] = {}
        self._init_form_vars()

        # 任务/选中状态
        self._busy = 0
        self._queue: queue.Queue = queue.Queue()
        self._current_status: FrameItemStatus | None = None
        self._preview_photo: tk.PhotoImage | None = None  # 持有引用防 GC
        self._preview_img_w = 0
        self._preview_img_h = 0

        self._build_toolbar()
        self._build_paths_panel()
        self._build_main_panels()
        self._build_log_panel()
        self._build_statusbar()

        self._log("就绪。源目录默认 assets_src，可在上方修改。点击「扫描」刷新列表。")
        if DEFAULT_SOURCE.is_dir():
            self.refresh_list()

    # ---- 表单变量初始化 --------------------------------------------------- #

    def _init_form_vars(self) -> None:
        z = lambda v: tk.StringVar(value=str(v))  # noqa: E731
        i = lambda v: tk.IntVar(value=int(v))  # noqa: E731
        self._form = {
            "id": z(""), "name": z(""), "category": z("frame"),
            "fit_mode": z("stretch"), "group": z("基础"),
            "sort_order": tk.IntVar(value=0),
            "is_premium": tk.BooleanVar(value=False),
            "inset_top": i(0), "inset_left": i(0),
            "inset_bottom": i(0), "inset_right": i(0),
            "native_aspect_ratio": z(""),
            "preview_path": z(""),
        }
        for r in STANDARD_RATIOS:
            self._ratio_vars[r] = tk.BooleanVar(value=False)

    # ---- 界面构建 --------------------------------------------------------- #

    def _build_toolbar(self) -> None:
        bar = ttk.Frame(self.root, padding=(8, 6))
        bar.pack(fill="x")
        self.btn_scan = ttk.Button(bar, text="🔄 扫描", command=self.refresh_list)
        self.btn_scan.pack(side="left")
        self.btn_init = ttk.Button(bar, text="➕ 新建模板", command=self._ask_init)
        self.btn_init.pack(side="left", padx=(6, 0))
        self.btn_save = ttk.Button(bar, text="💾 保存 manifest", command=self._save_current)
        self.btn_save.pack(side="left", padx=(6, 0))
        ttk.Separator(bar, orient="vertical").pack(side="left", fill="y", padx=10)
        self.btn_import = ttk.Button(bar, text="📦 导入工程", command=self._do_import)
        self.btn_import.pack(side="left")
        self.btn_validate = ttk.Button(bar, text="✅ 校验 catalog", command=self._do_validate)
        self.btn_validate.pack(side="left", padx=(6, 0))
        self.btn_list = ttk.Button(bar, text="📋 列出 catalog", command=self._do_list)
        self.btn_list.pack(side="left", padx=(6, 0))

    def _build_paths_panel(self) -> None:
        box = ttk.Frame(self.root, padding=(8, 2))
        box.pack(fill="x")
        # 源目录
        ttk.Label(box, text="源目录：").grid(row=0, column=0, sticky="w")
        ttk.Entry(box, textvariable=self.source_var, width=48).grid(row=0, column=1, sticky="we", padx=4)
        ttk.Button(box, text="浏览…", command=lambda: self._pick_dir(self.source_var)).grid(row=0, column=2)
        # Assets
        ttk.Label(box, text="Assets：").grid(row=1, column=0, sticky="w", pady=(4, 0))
        ttk.Entry(box, textvariable=self.assets_var, width=48).grid(row=1, column=1, sticky="we", padx=4, pady=(4, 0))
        ttk.Button(box, text="浏览…", command=lambda: self._pick_dir(self.assets_var)).grid(row=1, column=2, pady=(4, 0))
        # Catalog
        ttk.Label(box, text="catalog：").grid(row=2, column=0, sticky="w", pady=(4, 0))
        ttk.Entry(box, textvariable=self.catalog_var, width=48).grid(row=2, column=1, sticky="we", padx=4, pady=(4, 0))
        ttk.Button(box, text="浏览…", command=lambda: self._pick_file(self.catalog_var, "*.json")).grid(row=2, column=2, pady=(4, 0))
        box.columnconfigure(1, weight=1)

    def _build_main_panels(self) -> None:
        paned = ttk.PanedWindow(self.root, orient="horizontal")
        paned.pack(fill="both", expand=True, padx=8, pady=4)
        paned.add(self._build_list_panel(), weight=1)
        paned.add(self._build_editor_panel(), weight=2)
        paned.add(self._build_preview_panel(), weight=1)

    def _build_list_panel(self) -> ttk.Frame:
        box = ttk.LabelFrame(self.root, text="素材列表（源目录下每个子目录）", padding=6)
        cols = ("id", "category", "fit_mode", "png", "status")
        headers = {"id": "id", "category": "类别", "fit_mode": "fitMode",
                   "png": "PNG", "status": "状态"}
        self.list_tree = ttk.Treeview(box, columns=cols, show="headings", height=12)
        for c in cols:
            self.list_tree.heading(c, text=headers[c])
            w = 160 if c == "id" else (70 if c in ("category", "png", "status") else 90)
            self.list_tree.column(c, width=w, anchor="w" if c == "id" else "center")
        self.list_tree.tag_configure("ready", foreground="#1E7B45")
        self.list_tree.tag_configure("warn", foreground="#B8860B")
        self.list_tree.tag_configure("bad", foreground="#C0392B")
        self.list_tree.pack(fill="both", expand=True)
        self.list_tree.bind("<<TreeviewSelect>>", self._on_select)
        return box

    def _build_editor_panel(self) -> ttk.Frame:
        box = ttk.LabelFrame(self.root, text="manifest 编辑器", padding=8)
        # 用 Canvas + ScrollFrame 容纳长表单
        inner = self._make_scrollable(box)

        row = [0]

        def add_entry(label, key, width=28):
            ttk.Label(inner, text=label).grid(row=row[0], column=0, sticky="w", pady=2)
            e = ttk.Entry(inner, textvariable=self._form[key], width=width)
            e.grid(row=row[0], column=1, sticky="we", padx=(4, 0), pady=2)
            row[0] += 1

        def add_combo(label, key, values):
            ttk.Label(inner, text=label).grid(row=row[0], column=0, sticky="w", pady=2)
            cb = ttk.Combobox(inner, textvariable=self._form[key], values=values,
                              state="readonly", width=26)
            cb.grid(row=row[0], column=1, sticky="w", padx=(4, 0), pady=2)
            row[0] += 1

        def add_check(label, key):
            ttk.Checkbutton(inner, text=label, variable=self._form[key]) \
                .grid(row=row[0], column=1, sticky="w", padx=(4, 0), pady=2)
            row[0] += 1

        # 基本字段
        add_entry("id *", "id")
        add_entry("name（显示名）", "name")
        add_combo("category", "category", ["frame", "sticker"])
        add_combo("fit_mode", "fit_mode", list(FITMODE_LABELS.keys()))
        add_entry("group（分组）", "group")
        add_entry("sort_order（排序）", "sort_order", width=8)
        add_check("is_premium（Pro 专属）", "is_premium")
        add_entry("preview_path（可选）", "preview_path")

        # fitMode 联动区域：ninePatch / ratioSet
        ttk.Separator(inner, orient="horizontal").grid(row=row[0], column=0, columnspan=2,
                                                        sticky="we", pady=(10, 4))
        row[0] += 1
        self._fitmode_label = ttk.Label(inner, text="", foreground="#666")
        self._fitmode_label.grid(row=row[0], column=0, columnspan=2, sticky="w")
        row[0] += 1

        # ninePatch inset 滑块容器
        self._inset_frame = ttk.LabelFrame(inner, text="nine_patch_insets（像素，源图像素空间）", padding=4)
        self._inset_frame.grid(row=row[0], column=0, columnspan=2, sticky="we", pady=4)
        self._build_inset_sliders(self._inset_frame)
        row[0] += 1

        # ratioSet 复选框容器
        self._ratio_frame = ttk.LabelFrame(inner, text="supported_ratios（ratio_set 模式选择要提供的比例）", padding=4)
        self._ratio_frame.grid(row=row[0], column=0, columnspan=2, sticky="we", pady=4)
        self._build_ratio_checks(self._ratio_frame)
        row[0] += 1

        inner.columnconfigure(1, weight=1)

        # 初始联动
        self._form["fit_mode"].trace_add("write", lambda *_: self._on_fitmode_change())
        self._on_fitmode_change()
        return box

    def _build_inset_sliders(self, parent) -> None:
        for idx, key in enumerate(["inset_top", "inset_left", "inset_bottom", "inset_right"]):
            label_map = {"inset_top": "top", "inset_left": "left",
                         "inset_bottom": "bottom", "inset_right": "right"}
            ttk.Label(parent, text=label_map[key]).grid(row=idx, column=0, sticky="w")
            scale = ttk.Scale(parent, from_=0, to=512, orient="horizontal",
                              variable=None, command=lambda v, k=key: self._on_inset_drag(k, v))
            scale.grid(row=idx, column=1, sticky="we", padx=4)
            val_lbl = ttk.Label(parent, text="0", width=5)
            val_lbl.grid(row=idx, column=2)
            scale._val_lbl = val_lbl  # type: ignore[attr-defined]
            scale._key = key  # type: ignore[attr-defined]
            parent.columnconfigure(1, weight=1)
        # inset 变化触发预览重画
        for k in ["inset_top", "inset_left", "inset_bottom", "inset_right"]:
            self._form[k].trace_add("write", lambda *_: self._redraw_preview_grid())

    def _build_ratio_checks(self, parent) -> None:
        for i, r in enumerate(STANDARD_RATIOS):
            ttk.Checkbutton(parent, text=r, variable=self._ratio_vars[r]) \
                .grid(row=i // 4, column=i % 4, sticky="w", padx=4, pady=2)

    def _build_preview_panel(self) -> ttk.Frame:
        box = ttk.LabelFrame(self.root, text="PNG 预览（九宫格模式叠加红色参考线）", padding=6)
        self.preview_canvas = tk.Canvas(box, width=self.PREVIEW_SIZE, height=self.PREVIEW_SIZE,
                                        bg="#2b2b2b", highlightthickness=0)
        self.preview_canvas.pack(fill="both", expand=True)
        self.preview_info = ttk.Label(box, text="（选中素材后显示 PNG）", foreground="#888")
        self.preview_info.pack(anchor="w")
        return box

    def _build_log_panel(self) -> None:
        box = ttk.LabelFrame(self.root, text="日志", padding=6)
        box.pack(fill="both", expand=False, padx=8, pady=(4, 2))
        frame = ttk.Frame(box)
        frame.pack(fill="both", expand=True)
        self.log_text = tk.Text(frame, height=8, wrap="word", state="disabled",
                                font=("Consolas", 9))
        scroll = ttk.Scrollbar(frame, command=self.log_text.yview)
        self.log_text.configure(yscrollcommand=scroll.set)
        scroll.pack(side="right", fill="y")
        self.log_text.pack(side="left", fill="both", expand=True)

    def _build_statusbar(self) -> None:
        self.status_var = tk.StringVar(value="就绪")
        ttk.Label(self.root, textvariable=self.status_var, relief="sunken",
                  anchor="w", padding=(6, 2)).pack(fill="x", side="bottom")

    def _make_scrollable(self, parent) -> ttk.Frame:
        """给 parent 套一个可滚动区域，返回内部容器。"""
        canvas = tk.Canvas(parent, highlightthickness=0, height=320)
        scroll = ttk.Scrollbar(parent, orient="vertical", command=canvas.yview)
        inner = ttk.Frame(canvas)
        inner.bind("<Configure>",
                   lambda _: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.create_window((0, 0), window=inner, anchor="nw")
        canvas.configure(yscrollcommand=scroll.set)
        canvas.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")
        return inner

    # ---- 列表与选中 ------------------------------------------------------- #

    def refresh_list(self) -> None:
        self._set_busy(1)
        self._run_worker(self._scan_worker, self._paint_list)

    def _scan_worker(self) -> list[FrameItemStatus]:
        return scan_source_dir(Path(self.source_var.get()))

    def _paint_list(self, items: list[FrameItemStatus]) -> None:
        self.list_tree.delete(*self.list_tree.get_children())
        for st in items:
            tag = "ready" if st.status_label == "✓就绪" else \
                  ("bad" if st.errors else "warn")
            self.list_tree.insert("", "end", iid=str(st.dir_path),
                                  values=(st.item_id, st.category, st.fit_mode,
                                          str(st.png_count), st.status_label),
                                  tags=(tag,))
        n_ready = sum(1 for s in items if s.status_label == "✓就绪")
        self.status_var.set(f"扫描完成：{len(items)} 项，就绪 {n_ready} 项")
        self._set_busy(-1)

    def _on_select(self, _event) -> None:
        sel = self.list_tree.selection()
        if not sel:
            return
        dir_path = Path(sel[0])
        # 扫描单项
        status = FrameItemStatus(dir_path=dir_path, manifest=fi.load_manifest(dir_path))
        if status.manifest:
            status.errors = list(fi.validate_manifest(status.manifest, dir_path.name))
            status.pngs = fi.find_pngs(dir_path, status.item_id, status.fit_mode)
        else:
            status.pngs = fi.find_pngs(dir_path, dir_path.name, "stretch")
        self._current_status = status
        self._load_form_from_status(status)
        self._load_preview(status)

    def _load_form_from_status(self, status: FrameItemStatus) -> None:
        form = load_form_from_manifest(status.manifest, status.dir_path.name)
        self._form["id"].set(form["id"])
        self._form["name"].set(form["name"])
        self._form["category"].set(form["category"])
        self._form["fit_mode"].set(form["fit_mode"])
        self._form["group"].set(form["group"])
        self._form["sort_order"].set(form["sort_order"])
        self._form["is_premium"].set(form["is_premium"])
        self._form["inset_top"].set(form["inset_top"])
        self._form["inset_left"].set(form["inset_left"])
        self._form["inset_bottom"].set(form["inset_bottom"])
        self._form["inset_right"].set(form["inset_right"])
        self._form["native_aspect_ratio"].set(
            "" if form["native_aspect_ratio"] is None else str(form["native_aspect_ratio"]))
        self._form["preview_path"].set(form["preview_path"] or "")
        for r, var in self._ratio_vars.items():
            var.set(r in form["supported_ratios"])
        self._on_fitmode_change()

    # ---- fitMode 联动 ----------------------------------------------------- #

    def _on_fitmode_change(self) -> None:
        fit = self._form["fit_mode"].get()
        self._fitmode_label.configure(text=FITMODE_LABELS.get(fit, ""))
        # ninePatch：显示 inset 滑块；ratioSet：显示 ratio 复选框；stretch：都隐藏
        if fit == "nine_patch":
            self._inset_frame.grid()
            self._ratio_frame.grid_remove()
        elif fit == "ratio_set":
            self._inset_frame.grid_remove()
            self._ratio_frame.grid()
        else:
            self._inset_frame.grid_remove()
            self._ratio_frame.grid_remove()
        self._redraw_preview_grid()

    def _on_inset_drag(self, key: str, value: str) -> None:
        """滑块拖动：更新 IntVar + 标签 + 重画参考线。"""
        v = int(float(value))
        self._form[key].set(v)
        # 找到对应 scale 的标签更新
        for child in self._inset_frame.winfo_children():
            if isinstance(child, ttk.Scale) and getattr(child, "_key", None) == key:
                child._val_lbl.configure(text=str(v))  # type: ignore[attr-defined]
                break

    # ---- PNG 预览 + 九宫格叠加 ------------------------------------------- #

    def _load_preview(self, status: FrameItemStatus) -> None:
        self.preview_canvas.delete("all")
        self._preview_photo = None
        self._preview_img_w = self._preview_img_h = 0
        if not status.pngs:
            self.preview_info.configure(text="（该素材无 PNG）")
            return
        # 取第一张 PNG（ratio_set 取 ratio 列表第一张）作为预览
        png_path = status.pngs[0][1]
        try:
            self._preview_photo = tk.PhotoImage(file=str(png_path))
            self._preview_img_w = self._preview_photo.width()
            self._preview_img_h = self._preview_photo.height()
        except tk.TclError:
            self.preview_info.configure(text=f"（PNG 读取失败：{png_path.name}）")
            return
        # 缩放显示（fit 进 PREVIEW_SIZE）
        size = self.PREVIEW_SIZE - 16
        self._disp_w, self._disp_h, self._scale_factor = self._fit_size(
            self._preview_img_w, self._preview_img_h, size, size)
        # tkinter PhotoImage 缩放：subsample 只支持整数倍，用 zoom/subsample 组合
        disp_photo = self._scale_photo(self._preview_photo, self._scale_factor)
        self._preview_photo = disp_photo  # 持有缩放后的引用
        x0 = (self.PREVIEW_SIZE - self._disp_w) // 2
        y0 = (self.PREVIEW_SIZE - self._disp_h) // 2
        self.preview_canvas.create_image(x0, y0, anchor="nw", image=disp_photo)
        self._preview_origin = (x0, y0)
        ratio_info = f"{png_path.name}  原始 {self._preview_img_w}×{self._preview_img_h}"
        if status.fit_mode == "ratio_set":
            ratios = [t for t, _ in status.pngs]
            ratio_info += f"  比例 {ratios}"
        self.preview_info.configure(text=ratio_info)
        self._redraw_preview_grid()

    @staticmethod
    def _fit_size(w: int, h: int, max_w: int, max_h: int) -> tuple[int, int, float]:
        scale = min(max_w / w, max_h / h, 1.0)
        return int(w * scale), int(h * scale), scale

    @staticmethod
    def _scale_photo(photo: tk.PhotoImage, scale: float) -> tk.PhotoImage:
        """整数倍 subsample 近似缩放（无 Pillow 依赖）。"""
        if scale >= 1.0:
            return photo  # 不放大
        # subsample 因子（≥2 才缩小）
        factor = max(1, round(1 / scale))
        try:
            return photo.subsample(factor, factor)
        except tk.TclError:
            return photo

    def _redraw_preview_grid(self) -> None:
        """按当前 inset 在预览 Canvas 上重画 4 条九宫格参考线。"""
        # 防御：编辑器面板构建阶段会触发 fitMode 变化，此时 preview_canvas 尚未创建。
        if not hasattr(self, "preview_canvas"):
            return
        self.preview_canvas.delete("grid_line")
        if self._preview_photo is None or self._preview_img_w == 0:
            return
        fit = self._form["fit_mode"].get()
        if fit != "nine_patch":
            return
        # 把 inset 从原图像素空间映射到显示空间
        insets_px = {
            "top": self._form["inset_top"].get(),
            "left": self._form["inset_left"].get(),
            "bottom": self._form["inset_bottom"].get(),
            "right": self._form["inset_right"].get(),
        }
        lines = nine_patch_preview_lines(self._preview_img_w, self._preview_img_h, insets_px)
        # 当前显示图相对于原图的缩放因子（subsample 后）
        disp_w = self._preview_photo.width()
        disp_h = self._preview_photo.height()
        sx = disp_w / self._preview_img_w if self._preview_img_w else 1
        sy = disp_h / self._preview_img_h if self._preview_img_h else 1
        x0, y0 = self._preview_origin
        v_left = x0 + lines["v_left"] * sx
        v_right = x0 + lines["v_right"] * sx
        h_top = y0 + lines["h_top"] * sy
        h_bottom = y0 + lines["h_bottom"] * sy
        # 画 2 条竖线 + 2 条横线（红色虚线）
        for x in (v_left, v_right):
            self.preview_canvas.create_line(x, y0, x, y0 + disp_h, fill="#ff4444",
                                            dash=(4, 3), width=1, tags="grid_line")
        for y in (h_top, h_bottom):
            self.preview_canvas.create_line(x0, y, x0 + disp_w, y, fill="#ff4444",
                                            dash=(4, 3), width=1, tags="grid_line")

    # ---- 保存 manifest ---------------------------------------------------- #

    def _save_current(self) -> None:
        if self._current_status is None:
            messagebox.showinfo("提示", "请先在左侧列表选中一个素材。")
            return
        form = self._collect_form()
        errs = fi.validate_manifest(form, self._current_status.dir_path.name)
        if errs:
            messagebox.showwarning("manifest 校验失败", "\n".join(errs))
            return
        manifest = manifest_from_form(form)
        path = save_manifest(self._current_status.dir_path, manifest)
        self._log(f"✔ 已保存 {path.relative_to(ROOT) if ROOT in path.parents else path.name}")
        self.refresh_list()

    def _collect_form(self) -> dict:
        form = {k: v.get() for k, v in self._form.items()}
        form["supported_ratios"] = [r for r, var in self._ratio_vars.items() if var.get()]
        return form

    # ---- 工具栏操作 ------------------------------------------------------- #

    def _ask_init(self) -> None:
        name = (self._form["id"].get() or "frame_new").strip() or "frame_new"
        default_dir = Path(self.source_var.get()) / name
        path = filedialog.asksaveasfilename(
            title="新建相框素材目录（生成 frame.json 模板）",
            initialdir=str(Path(self.source_var.get())),
            initialfile=name,
            confirmoverwrite=True,
        )
        if not path:
            return
        target = Path(path)
        self.submit(f"新建模板 {target.name}",
                    lambda: run_init(target, item_id=target.name, name=target.name))

    def _do_import(self) -> None:
        source = Path(self.source_var.get())
        assets = Path(self.assets_var.get())
        catalog = Path(self.catalog_var.get())
        if not source.is_dir():
            messagebox.showwarning("提示", f"源目录不存在：{source}")
            return
        if not messagebox.askyesno("确认导入",
                                   f"将扫描 {source}\n并写入\n  Assets: {assets}\n  catalog: {catalog}\n\n继续？"):
            return
        self.submit("导入工程", lambda: run_add(source, assets, catalog))

    def _do_validate(self) -> None:
        catalog = Path(self.catalog_var.get())
        assets = Path(self.assets_var.get())
        self.submit("校验 catalog", lambda: run_validate(catalog, assets))

    def _do_list(self) -> None:
        catalog = Path(self.catalog_var.get())
        self.submit("列出 catalog", lambda: run_list(catalog))

    def _pick_dir(self, var: tk.StringVar) -> None:
        d = filedialog.askdirectory(initialdir=var.get() or str(ROOT))
        if d:
            var.set(d)

    def _pick_file(self, var: tk.StringVar, pattern: str = "*") -> None:
        f = filedialog.askopenfilename(
            initialdir=Path(var.get()).parent or str(ROOT),
            filetypes=[("文件", pattern)])
        if f:
            var.set(f)

    # ---- 后台任务 --------------------------------------------------------- #

    def submit(self, title: str, fn) -> None:
        self._set_busy(1)
        self._log(f"▶ {title}…")
        self._run_worker(fn, self._on_task_done, title=title)

    def _run_worker(self, fn, on_done, **kwargs) -> None:
        q: queue.Queue = queue.Queue()

        def worker() -> None:
            buf = io.StringIO()
            try:
                with contextlib.redirect_stdout(buf):
                    result = fn()
                q.put(("done", result, buf.getvalue()))
            except SystemExit as e:
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

    def _on_task_done(self, _result) -> None:
        self._set_busy(-1)
        self.refresh_list()

    def _set_busy(self, delta: int) -> None:
        self._busy += delta
        state = "disabled" if self._busy > 0 else "normal"
        for b in (self.btn_scan, self.btn_init, self.btn_save,
                  self.btn_import, self.btn_validate, self.btn_list):
            b.configure(state=state)

    # ---- 日志 ------------------------------------------------------------- #

    def _log(self, text: str) -> None:
        self.log_text.configure(state="normal")
        self.log_text.insert("end", text + "\n")
        self.log_text.see("end")
        self.log_text.configure(state="disabled")


# --------------------------------------------------------------------------- #
# 无界面自检（--self-check，供 CI / 无显示环境验证）
# --------------------------------------------------------------------------- #

def self_check() -> int:
    print("== MiLens 相框素材 GUI 自检 ==")
    # 1. manifest ↔ form 往返
    manifest = {
        "id": "frame_demo", "name": "演示", "category": "frame",
        "fit_mode": "nine_patch", "is_premium": False, "group": "基础",
        "sort_order": 1,
        "nine_patch_insets": {"top": 10, "left": 20, "bottom": 30, "right": 40},
        "supported_ratios": None,
    }
    form = load_form_from_manifest(manifest, "fallback")
    assert form["id"] == "frame_demo"
    assert form["inset_top"] == 10 and form["inset_right"] == 40
    assert form["fit_mode"] == "nine_patch"

    rt = manifest_from_form(form)
    for k in ("id", "name", "category", "fit_mode", "is_premium", "group", "sort_order"):
        assert rt[k] == manifest[k], f"round-trip 失败：{k} {rt[k]} != {manifest[k]}"
    assert rt["nine_patch_insets"] == manifest["nine_patch_insets"]
    print("  ✓ manifest ↔ form 往返一致")

    # 2. ratio_set 模式 form 转换
    form2 = dict(form)
    form2["fit_mode"] = "ratio_set"
    form2["supported_ratios"] = ["1x1", "3x4", "9x16"]
    rt2 = manifest_from_form(form2)
    assert rt2["nine_patch_insets"] is None
    assert rt2["supported_ratios"] == ["1x1", "3x4", "9x16"]
    print("  ✓ ratio_set 模式 supported_ratios 序列化正确")

    # 3. nine_patch 参考线坐标
    lines = nine_patch_preview_lines(100, 100, {"top": 10, "left": 20, "bottom": 30, "right": 40})
    assert lines == {"v_left": 20, "v_right": 60, "h_top": 10, "h_bottom": 70}
    print("  ✓ 九宫格参考线坐标正确")

    # 4. inset 非法时退化为全图
    bad = nine_patch_preview_lines(100, 100, {"top": 60, "left": 0, "bottom": 60, "right": 0})
    assert bad == {"v_left": 0, "v_right": 100, "h_top": 0, "h_bottom": 100}
    print("  ✓ inset 非法时参考线退化为全图")

    # 5. 扫描源目录（若 assets_src 存在）
    if DEFAULT_SOURCE.is_dir():
        items = scan_source_dir(DEFAULT_SOURCE)
        print(f"  ✓ 扫描 {DEFAULT_SOURCE.name}：{len(items)} 项")
    else:
        print(f"  - 跳过扫描（{DEFAULT_SOURCE.name} 不存在）")

    print("自检通过。")
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
    app = FrameImportApp(root)  # noqa: F841 持有引用即存活
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
