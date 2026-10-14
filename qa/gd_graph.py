#!/usr/bin/env python3
"""GDScript 依賴圖（B3.14）：回答「砍掉這個檔案，會壞掉誰？」

不需要 Godot。靜態掃 `preload("res://…")`、`load("res://…")`、autoload 與 `class_name`
的使用，建出檔案層級的依賴圖。

    python qa/gd_graph.py                  整張表：行數、直接依賴、爆炸半徑（runtime）
    python qa/gd_graph.py --why FILE       誰依賴 FILE（直接、以及遞移到哪些畫面）
    python qa/gd_graph.py --cut FILE ...   假設把這些檔案砍掉：列出會**無法載入**的檔案
    python qa/gd_graph.py --layers         檢查分層規則（sim/data 不得依賴 screens/render/ui）

「爆炸半徑」＝直接或遞移依賴它的 runtime 檔案數（不含 tests/）。
它是**載入層級**的，不是功能層級：砍掉 `Tycoon*` 不會讓遊戲載入失敗，
但主選單會少一顆鈕——這種「功能性」的分級在 `docs/60_CODE_MAP.md`。
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")  # 與 qa/gd_lint.py 同一個慣例

ROOT = Path(__file__).resolve().parent.parent / "godot"
PRELOAD = re.compile(r'\b(?:pre)?load\("res://([^"]+\.gd)"\)')
CLASS_NAME = re.compile(r"^class_name\s+(\w+)", re.M)
AUTOLOAD = re.compile(r'^(\w+)="\*res://([^"]+)"', re.M)

# 分層規則：左邊這些目錄**不得**依賴右邊這些目錄（`30_TECH_DESIGN.md` §2；CLAUDE.md 技術慣例）。
# sim 與 data 是純函式層——渲染與畫面長什麼樣，不該影響模擬的結果。
FORBIDDEN = {
    "scripts/sim": ["scripts/screens", "scripts/ui", "scripts/render", "scripts/game", "scripts/core"],
    "data": ["scripts/screens", "scripts/ui", "scripts/render", "scripts/game", "scripts/core"],
    "scripts/meta": ["scripts/screens", "scripts/ui", "scripts/render", "scripts/game", "scripts/core"],
}
# 已知且已登記的例外：(來源, 被依賴者)。每一條都要寫理由；目前沒有。
ALLOWED: set[tuple[str, str]] = set()


def load() -> tuple[dict[str, set[str]], dict[str, int], dict[str, str]]:
    files = {p.relative_to(ROOT).as_posix(): p for p in ROOT.rglob("*.gd")}
    classes: dict[str, str] = {}
    for r, p in files.items():
        m = CLASS_NAME.search(p.read_text(encoding="utf-8"))
        if m:
            classes[m.group(1)] = r
    proj = (ROOT / "project.godot").read_text(encoding="utf-8")
    autos = {n: path for n, path in AUTOLOAD.findall(proj)}
    names = {**classes, **autos}
    graph: dict[str, set[str]] = {}
    loc: dict[str, int] = {}
    for r, p in files.items():
        text = p.read_text(encoding="utf-8")
        loc[r] = text.count("\n") + 1
        deps = {d for d in PRELOAD.findall(text) if d in files}
        code = re.sub(r"#.*", "", text)
        for n, target in names.items():
            if target != r and re.search(rf"\b{n}\b\.", code):
                deps.add(target)
        # `extends "res://….gd"`
        for d in re.findall(r'^extends\s+"res://([^"]+)"', text, re.M):
            if d in files:
                deps.add(d)
        graph[r] = deps
    return graph, loc, autos


def closure(graph: dict[str, set[str]], roots: list[str]) -> set[str]:
    seen: set[str] = set()
    stack = list(roots)
    while stack:
        x = stack.pop()
        if x in seen or x not in graph:
            continue
        seen.add(x)
        stack.extend(graph[x])
    return seen


def reverse(graph: dict[str, set[str]]) -> dict[str, set[str]]:
    rev: dict[str, set[str]] = {r: set() for r in graph}
    for r, ds in graph.items():
        for d in ds:
            rev[d].add(r)
    return rev


def dependents(rev: dict[str, set[str]], target: str, skip_tests: bool = True) -> set[str]:
    seen: set[str] = set()
    stack = [target]
    while stack:
        x = stack.pop()
        for y in rev.get(x, ()):
            if y not in seen and not (skip_tests and y.startswith("tests/")):
                seen.add(y)
                stack.append(y)
    return seen


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--why", metavar="FILE")
    ap.add_argument("--cut", nargs="+", metavar="FILE")
    ap.add_argument("--layers", action="store_true")
    a = ap.parse_args()
    graph, loc, autos = load()
    rev = reverse(graph)

    def norm(f: str) -> str:
        f = f.replace("\\", "/")
        for r in graph:
            if r == f or r.endswith("/" + f) or r.endswith(f):
                return r
        sys.exit(f"找不到檔案：{f}")

    if a.layers:
        bad = 0
        for src, deps in graph.items():
            for rule, banned in FORBIDDEN.items():
                if not src.startswith(rule + "/"):
                    continue
                for d in sorted(deps):
                    if any(d.startswith(b + "/") for b in banned) and (src, d) not in ALLOWED:
                        print(f"  違規  {src} → {d}")
                        bad += 1
        print(f"分層檢查：{bad} 條違規" if bad else "分層檢查：0 條違規（sim／data／meta 都沒有往上依賴）")
        return 1 if bad else 0

    if a.why:
        t = norm(a.why)
        direct = sorted(x for x in rev[t] if not x.startswith("tests/"))
        print(f"{t}（{loc[t]} 行）\n直接被這些依賴（{len(direct)}）：")
        for x in direct:
            print(f"  {x}")
        tr = sorted(dependents(rev, t) - set(direct))
        print(f"遞移（再 {len(tr)} 個）：" + (", ".join(tr) if tr else "—"))
        tests = sorted(x for x in rev[t] if x.startswith("tests/"))
        print(f"測試直接用它：{', '.join(tests) if tests else '—'}")
        return 0

    roots = [*autos.values(), "scripts/screens/Main.gd"]
    runtime = closure(graph, roots)

    if a.cut:
        cut = {norm(c) for c in a.cut}
        broken = set()
        for c in cut:
            broken |= dependents(rev, c, skip_tests=False)
        broken -= cut
        rt = sorted(b for b in broken if b in runtime)
        ts = sorted(b for b in broken if b.startswith("tests/"))
        print(f"砍掉 {', '.join(sorted(cut))}（共 {sum(loc[c] for c in cut)} 行）：")
        print(f"  runtime 會載入失敗的檔案（{len(rt)}）：" + (", ".join(rt) if rt else "無"))
        print(f"  會跟著壞的測試（{len(ts)}）：" + (", ".join(ts) if ts else "無"))
        main_dead = "scripts/screens/Main.gd" in broken
        print("  ⇒ 遊戲" + ("**開不起來**（Main.gd 載入失敗）" if main_dead else "仍能開起來（要改的是引用它的那幾行）"))
        return 0

    print(f"{'檔案':<42}{'行':>6}{'直接依賴':>8}{'被依賴(直接)':>12}{'爆炸半徑':>10}")
    rows = []
    for r in runtime:
        direct = len([x for x in rev[r] if x in runtime])
        rows.append((len(dependents(rev, r) & runtime), direct, r))
    for blast, direct, r in sorted(rows, reverse=True):
        print(f"{r:<42}{loc[r]:>6}{len(graph[r]):>8}{direct:>12}{blast:>10}")
    total = sum(loc[r] for r in runtime)
    print(f"\nruntime：{len(runtime)} 檔、{total} 行；tests：{sum(1 for r in graph if r.startswith('tests/'))} 檔、"
          f"{sum(loc[r] for r in graph if r.startswith('tests/'))} 行")
    return 0


if __name__ == "__main__":
    sys.exit(main())
