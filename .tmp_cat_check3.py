# -*- coding: utf-8 -*-
import json
import sys

sys.stdout.reconfigure(encoding="utf-8")

obj = json.load(open(r"E:\iOSprojects\MiLens\MiLens\Resources\Localizable.xcstrings", encoding="utf-8"))
print("total keys:", len(obj["strings"]))
checks = {
    "fenxiang": "\u5206\u4eab",
    "chengzhang": "\u6210\u957f\u65f6\u95f4\u7ebf",
    "heita": "\u548c\u5b83\u4e00\u8d77\u7684\u6bcf\u4e00\u5929",
    "weizhi": "\u672a\u77e5\u9519\u8bef",
    "quanbu": "\u5168\u90e8\u5ba0\u7269",
}
for name, k in checks.items():
    print(name, "->", "OK" if k in obj["strings"] else "ABSENT")
samples = sorted(k for k in obj["strings"] if any(c.isascii() and c.isalpha() for c in k))
print("sample keys:", samples[:12], "... total", len(samples))
