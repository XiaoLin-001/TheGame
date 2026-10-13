#!/usr/bin/env python3
"""統一的品質閘門入口（B3.14）。

CLAUDE.md「跑與測」列了二十幾條各自獨立的指令。這支把它們收成**一個入口**，
讓接手的人不必先讀完 CLAUDE.md 才知道「改完要跑什麼」。

    python qa/check.py lint                 靜態地雷掃描（不需要 Godot，約 1 秒）
    python qa/check.py tests                headless 單元／整合測試（19 支，約 5 分鐘）
    python qa/check.py tests flow save      只跑指定幾支
    python qa/check.py tests --fast         跳過最慢的 campaign_test（約 3 分鐘）
    python qa/check.py click                輸入層自檢（需要視窗；每條約 6 秒）
    python qa/check.py shots OUT_DIR        截圖矩陣存進 OUT_DIR
    python qa/check.py shots NEW --against OLD
                                            截圖矩陣，並與 OLD 逐像素比對
    python qa/check.py all                  lint ＋ tests ＋ click ＋ 文案稽核

截圖比對是**重構的安全網**：TL_SHOT 下模擬凍結、動效不走，同參數在同一台機器上
拍出同一張圖——所以「搬動程式碼」的批次可以要求 0 像素差。

Godot 執行檔：預設 `tools/godot/Godot_v4.7-stable_win64_console.exe`，
可用環境變數 `TL_GODOT` 覆寫。沒有的話先跑 `dev/setup.ps1`。
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")  # 與 qa/gd_lint.py 同一個慣例
ROOT = Path(__file__).resolve().parent.parent
GODOT = Path(os.environ.get("TL_GODOT", ROOT / "tools" / "godot" / "Godot_v4.7-stable_win64_console.exe"))

# 跑的順序 ＝ 從快到慢，壞掉的地基先紅。campaign 最慢（五關參考解實跑）。
TESTS = [
    "flow", "build", "combat", "tide", "save", "determinism", "hud", "tech", "audio",
    "perf", "endless", "daily", "blueprint", "roster", "tycoon", "progress",
    "difficulty", "m2", "campaign",
]

# 輸入層自檢：(名稱, TL_PANEL)。空字串 ＝ 預設的局內畫面。
# ⚠ 這是唯一不能 --headless 的檢查（dummy display server 不做 GUI 命中測試）。
CLICKTESTS = [
    ("battle", ""), ("campaign", "campaign"), ("tech", "tech"), ("achievements", "achievements"),
    ("tiers", "tiers"), ("daily", "daily"), ("roster", "roster"), ("tycoon", "tycoon"),
    ("settings", "settings"), ("title", "title"),
]

# 截圖矩陣：名稱 → 環境變數。涵蓋每個畫面、局內的幾種互動狀態與十關。
# 新增畫面或新增「只有互動才到得了」的狀態時，在這裡加一列。
_DEMO = {"TL_DEMO_TICKS": "1600"}
SHOTS: dict[str, dict[str, str]] = {
    "title": {"TL_PANEL": "title"},
    "battle_demo": {"TL_PANEL": "battle", "TL_SEED": "42"},
    "battle_first": {"TL_PANEL": "battle", "TL_DEMO_TICKS": "0"},
    "battle_naked": {"TL_PANEL": "battle", "TL_SEED": "42", "TL_NAKED": "1"},
    "battle_prep": {"TL_PANEL": "battle", "TL_SEED": "42", "TL_DEMO_TICKS": "200"},
    "sandbox": {"TL_PANEL": "sandbox"},
    "endless": {"TL_PANEL": "endless", "TL_SEED": "42"},
    "campaign_select": {"TL_PANEL": "campaign"},
    **{f"campaign_L{n}": {"TL_PANEL": "campaign", "TL_LEVEL": str(n), **_DEMO} for n in range(1, 11)},
    "fx_focus": {"TL_PANEL": "campaign", "TL_LEVEL": "5", "TL_DEMO_TICKS": "581", "TL_FOCUS": "30,15,3"},
    "inspect_tower": {"TL_CLICKTEST": "1", "TL_PANEL": "campaign", "TL_LEVEL": "4", **_DEMO},
    "inspect_wire": {"TL_CLICKTEST": "1", "TL_PICK": "wire", "TL_PANEL": "campaign", "TL_LEVEL": "4", **_DEMO},
    "panels": {"TL_CLICKTEST": "1"},
    "tiers": {"TL_PANEL": "tiers"},
    "tiers_open": {"TL_CLICKTEST": "1", "TL_PANEL": "tiers"},
    "daily": {"TL_PANEL": "daily"},
    "roster": {"TL_PANEL": "roster"},
    "roster_open": {"TL_CLICKTEST": "1", "TL_PANEL": "roster"},
    "tycoon_orders": {"TL_CLICKTEST": "1", "TL_PANEL": "tycoon"},
    "tycoon_lines": {"TL_CLICKTEST": "1", "TL_PANEL": "tycoon", "TL_LEVEL": "2"},
    "tech": {"TL_CLICKTEST": "1", "TL_PANEL": "tech"},
    "achievements": {"TL_CLICKTEST": "1", "TL_PANEL": "achievements"},
    "settings": {"TL_PANEL": "settings"},
}


def _godot(args: list[str], env_extra: dict[str, str], timeout: int) -> tuple[int, str, float]:
    if not GODOT.exists():
        sys.exit(f"找不到 Godot：{GODOT}\n先跑 dev/setup.ps1，或設環境變數 TL_GODOT。")
    env = {k: v for k, v in os.environ.items() if not k.startswith("TL_") or k == "TL_GODOT"}
    env.update(env_extra)
    t0 = time.time()
    try:
        p = subprocess.run(
            [str(GODOT), *args], cwd=ROOT, env=env, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=timeout,
        )
        return p.returncode, (p.stdout or "") + (p.stderr or ""), time.time() - t0
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"")
        out = out.decode("utf-8", "replace") if isinstance(out, bytes) else out
        return 124, out + "\n[check.py] 逾時", time.time() - t0


def cmd_lint(_a: argparse.Namespace) -> int:
    r = subprocess.run([sys.executable, str(ROOT / "qa" / "gd_lint.py")], cwd=ROOT)
    return r.returncode


def cmd_copy(_a: argparse.Namespace) -> int:
    """文案稽核（`20_ART_DIRECTION.md` §3.5）。基準見 CLAUDE.md。"""
    g = ROOT / "godot"
    for script in ("copy_extract.py", "copy_tells.py"):
        r = subprocess.run([sys.executable, str(ROOT / "qa" / script)], cwd=g)
        if r.returncode != 0:
            return r.returncode
    return 0


def cmd_tests(a: argparse.Namespace) -> int:
    names = a.names or [t for t in TESTS if not (a.fast and t == "campaign")]
    bad: list[str] = []
    for n in names:
        rc, out, dt = _godot(["--headless", "--path", "godot", "--script", f"res://tests/{n}_test.gd"], {}, 900)
        ok = rc == 0
        print(f"  {'PASS' if ok else 'FAIL'}  {n:<12} {dt:6.1f}s")
        if not ok:
            bad.append(n)
            print("\n".join("      " + ln for ln in out.strip().splitlines()[-12:]))
    print(f"tests: {len(names) - len(bad)}/{len(names)} 通過" + (f"　失敗：{', '.join(bad)}" if bad else ""))
    return 1 if bad else 0


def cmd_click(a: argparse.Namespace) -> int:
    bad = 0
    for name, panel in CLICKTESTS:
        if a.names and name not in a.names:
            continue
        env = {"TL_CLICKTEST": "1", "TL_MUTE": "1"}
        if panel:
            env["TL_PANEL"] = panel
        rc, out, dt = _godot(["--path", "godot", "--rendering-driver", "opengl3"], env, 180)
        marks = [ln for ln in out.splitlines() if "[TL_CLICKTEST" in ln]
        failed = rc != 0 or any("FAIL" in ln for ln in marks) or not any("PASS" in ln for ln in marks)
        print(f"  {'FAIL' if failed else 'PASS'}  {name:<13} {dt:5.1f}s  ({len(marks)} 段自檢)")
        if failed:
            bad += 1
            print("\n".join("      " + ln for ln in (marks or out.strip().splitlines())[-10:]))
    print(f"click: {'全部通過' if not bad else f'{bad} 條失敗'}")
    return 1 if bad else 0


def _compare(new: Path, old: Path) -> tuple[bool, str]:
    """逐像素比對。回傳 (相同, 說明)。"""
    from PIL import Image, ImageChops  # 只有 shots --against 才需要

    a, b = Image.open(new).convert("RGBA"), Image.open(old).convert("RGBA")
    if a.size != b.size:
        return False, f"尺寸不同 {a.size} vs {b.size}"
    diff = ImageChops.difference(a, b)
    box = diff.getbbox()
    if box is None:
        return True, "0 像素差"
    n = sum(1 for px in diff.getdata() if px != (0, 0, 0, 0))
    return False, f"{n} 像素不同，範圍 {box}"


def cmd_shots(a: argparse.Namespace) -> int:
    out = Path(a.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    against = Path(a.against).resolve() if a.against else None
    names = a.names or list(SHOTS)
    worst = 0
    for n in names:
        env = {"TL_SHOT": str(out / f"{n}.png"), "TL_MUTE": "1", **SHOTS[n]}
        rc, log, dt = _godot(["--path", "godot", "--rendering-driver", "opengl3"], env, 120)
        png = out / f"{n}.png"
        if rc != 0 or not png.exists():
            print(f"  ERR   {n:<18} rc={rc}")
            print("\n".join("      " + ln for ln in log.strip().splitlines()[-6:]))
            worst = 1
            continue
        if against is None:
            print(f"  ok    {n:<18} {dt:4.1f}s")
            continue
        old = against / f"{n}.png"
        if not old.exists():
            print(f"  NEW   {n:<18} （基準裡沒有）")
            continue
        same, why = _compare(png, old)
        print(f"  {'SAME' if same else 'DIFF'}  {n:<18} {why}")
        if not same:
            worst = 1
    return worst


def cmd_all(a: argparse.Namespace) -> int:
    a.names, a.fast = [], False
    rc = 0
    for label, fn in (("lint", cmd_lint), ("copy", cmd_copy), ("tests", cmd_tests), ("click", cmd_click)):
        print(f"\n── {label} " + "─" * 50)
        rc |= fn(a)
    return rc


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("lint").set_defaults(fn=cmd_lint)
    sub.add_parser("copy").set_defaults(fn=cmd_copy)
    p = sub.add_parser("tests")
    p.add_argument("names", nargs="*")
    p.add_argument("--fast", action="store_true", help="跳過最慢的 campaign_test")
    p.set_defaults(fn=cmd_tests)
    p = sub.add_parser("click")
    p.add_argument("names", nargs="*")
    p.set_defaults(fn=cmd_click)
    p = sub.add_parser("shots")
    p.add_argument("out")
    p.add_argument("names", nargs="*")
    p.add_argument("--against", help="與這個資料夾裡同名的 png 逐像素比對")
    p.set_defaults(fn=cmd_shots)
    sub.add_parser("all").set_defaults(fn=cmd_all)
    a = ap.parse_args()
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
