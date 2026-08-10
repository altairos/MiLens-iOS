# -*- coding: utf-8 -*-
"""临时脚本：检查 catalog 中字面量 key 的结构。"""
import json
import sys

sys.stdout.reconfigure(encoding="utf-8")

obj = json.load(open("MiLens/Resources/Localizable.xcstrings", encoding="utf-8"))
for k in ["和它一起的每一天", "还没有成长记录", "分享", "先留下一张照片", "添加照片",
          "本地数据无法加载", "材料清单", "好", "重试", "取消"]:
    entry = obj["strings"].get(k, None)
    print(repr(k), "->", json.dumps(entry, ensure_ascii=False) if entry else "ABSENT")
