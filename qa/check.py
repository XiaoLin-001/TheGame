#!/usr/bin/env python3
"""統一的品質閘門入口（B3.14）。

CLAUDE.md「跑與測」列了二十幾條各自獨立的指令。這支把它們收成**一個入口**，
讓接手的人不必先讀完 CLAUDE.md 才知道「改完要跑什麼」。

    python qa/check.py lint                 靜態地雷掃描（不需要 Godot，約 1 秒）
    python qa/check.py tests                headless 單元／整合測試（21 支，約 5 分鐘）
    python qa/check.py tests flow save      只跑指定幾支
    python qa/check.py tests --fast         跳過最慢的 campaign_test（約 3 分鐘）
    python qa/check.py click                輸入層自檢（需要視窗；每條約 6 秒）
    python qa/check.py shots OUT_DIR        截圖矩陣存進 OUT_DIR
    python qa/check.py shots NEW --against OLD
                                            截圖矩陣，並與 OLD 逐像素比對
    python qa/check.py perf                 渲染幀時間（戰役第 1／5／10 關與壓力場景；需要視窗，約 1 分鐘）
    python qa/check.py perf --base DIR      同上，並與另一份工作樹（例如舊版的 `git worktree`）用同一把尺對比
    python qa/check.py perf --runs 3        每個場景跑三次取中位數（桌面上別的程式會讓單次量測漂 30–50%）
    python qa/check.py all                  lint ＋ tests ＋ click ＋ 文案稽核

截圖比對是**重構的安全網**：TL_SHOT 下模擬凍結、動效不走，同參數在同一台機器上
拍出同一張圖——所以「搬動程式碼」的批次可以要求 0 像素差。

Godot 執行檔：預設 `tools/godot/Godot_v4.7-stable_win64_console.exe`，
可用環境變數 `TL_GODOT` 覆寫。沒有的話先跑 `python dev/setup.py`。
"""
from __future__ import annotations

import argparse
import os
import re
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
    "perf", "fuzz", "render_cache", "endless", "daily", "blueprint", "roster", "tycoon", "progress",
    "difficulty", "m2", "campaign",
]

# 輸入層自檢：(名稱, TL_PANEL)。空字串 ＝ 預設的局內畫面。
# ⚠ 這是唯一不能 --headless 的檢查（dummy display server 不做 GUI 命中測試）。
CLICKTESTS: list[tuple[str, str, dict[str, str]]] = [
    ("battle", "", {}), ("endless", "endless", {}), ("campaign", "campaign", {}), ("tech", "tech", {}), ("achievements", "achievements", {}),
    ("tiers", "tiers", {}), ("daily", "daily", {}), ("roster", "roster", {}), ("tycoon", "tycoon", {}),
    ("settings", "settings", {}), ("title", "title", {}),
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
    "tiers_open": {"TL_CLICKTEST": "1", "TL_PANEL": "tiers", "TL_SEED": "42"},
    "daily": {"TL_PANEL": "daily"},
    "roster": {"TL_PANEL": "roster"},
    "roster_open": {"TL_CLICKTEST": "1", "TL_PANEL": "roster"},
    "tycoon_orders": {"TL_CLICKTEST": "1", "TL_PANEL": "tycoon"},
    "tycoon_lines": {"TL_CLICKTEST": "1", "TL_PANEL": "tycoon", "TL_LEVEL": "2"},
    "tech": {"TL_CLICKTEST": "1", "TL_PANEL": "tech"},
    "achievements": {"TL_CLICKTEST": "1", "TL_PANEL": "achievements"},
    "settings": {"TL_PANEL": "settings"},
}


# 渲染量測矩陣：名稱 → 環境變數。戰役關卡跑**活的模擬**（`TL_DEMO_TICKS` ＝ 參考解跑完之後；敵人進出、血量與流量在變）——
# 那是玩家真正會碰到的負載。壓力場景是規模哨兵：模擬凍結，而且每 6 幀模擬一個 tick（一成的元素變一次）。
PERF: dict[str, dict[str, str]] = {
    **{f"campaign_L{n}": {"TL_PANEL": "campaign", "TL_LEVEL": str(n), "TL_DEMO_TICKS": "1600"} for n in (1, 5, 10)},
    "stress（547 節點／2045 導管／200 敵人）": {},
}


def _godot(args: list[str], env_extra: dict[str, str], timeout: int, project: Path | None = None) -> tuple[int, str, float]:
    if not GODOT.exists():
        sys.exit(f"找不到 Godot：{GODOT}\n先跑 `python dev/setup.py`，或設環境變數 TL_GODOT。")
    env = {k: v for k, v in os.environ.items() if not k.startswith("TL_") or k == "TL_GODOT"}
    env.update(env_extra)
    t0 = time.time()
    # Popen 而不是 run：`*_console.exe` 只是個轉接殼，真正的遊戲是它的子行程。
    # `subprocess.run(timeout=)` 逾時只殺殼，**視窗會一直留在使用者的桌面上**（B3.14 踩到）。
    p = subprocess.Popen(
        [str(GODOT), *args], cwd=project or ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace",
    )
    try:
        out, err = p.communicate(timeout=timeout)
        return p.returncode, (out or "") + (err or ""), time.time() - t0
    except subprocess.TimeoutExpired:
        if os.name == "nt":
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(p.pid)], capture_output=True)
        else:
            p.kill()
        out, err = p.communicate()
        return 124, (out or "") + (err or "") + "\n[check.py] 逾時（已連同子行程一起結束）", time.time() - t0


def cmd_lint(_a: argparse.Namespace) -> int:
    """靜態掃描 ＋ 分層檢查（sim／data／meta 不得往上依賴 screens／render／ui／game／core）。"""
    rc = 0
    for script, args in (("gd_lint.py", []), ("gd_graph.py", ["--layers"])):
        rc |= subprocess.run([sys.executable, str(ROOT / "qa" / script), *args], cwd=ROOT).returncode
    return rc


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
        # 執行期錯誤會**中止那一支函式**而不是讓斷言變紅（RG-164），所以 stderr 裡的 SCRIPT ERROR 一律當失敗。
        ok = rc == 0 and "SCRIPT ERROR" not in out
        print(f"  {'PASS' if ok else 'FAIL'}  {n:<12} {dt:6.1f}s")
        if not ok:
            bad.append(n)
            print("\n".join("      " + ln for ln in out.strip().splitlines()[-12:]))
    print(f"tests: {len(names) - len(bad)}/{len(names)} 通過" + (f"　失敗：{', '.join(bad)}" if bad else ""))
    return 1 if bad else 0


def cmd_click(a: argparse.Namespace) -> int:
    bad = 0
    for name, panel, extra in CLICKTESTS:
        if a.names and name not in a.names:
            continue
        env = {"TL_CLICKTEST": "1", "TL_MUTE": "1", **extra}
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

    # ⚠ 一律轉 RGB 再比：Pillow 新版的 `getbbox()` 對 RGBA **只看 alpha 通道**——截圖的 alpha 恆為 255，
    #   差值的 alpha 恆為 0，於是任何兩張圖都會被判成「0 像素差」（B3.15 發現：整個截圖比對曾經是空的）。
    a, b = Image.open(new).convert("RGB"), Image.open(old).convert("RGB")
    if a.size != b.size:
        return False, f"尺寸不同 {a.size} vs {b.size}"
    diff = ImageChops.difference(a, b)
    box = diff.getbbox()
    if box is None:
        return True, "0 像素差"
    r, g, bl = diff.split()  # `getdata()` 在 Pillow 14 會移除；逐通道取最大再數非零的像素
    n = ImageChops.lighter(ImageChops.lighter(r, g), bl).point(lambda v: 255 if v else 0).histogram()[255]
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


_STRESS_RE = re.compile(r"\[TL_STRESS\] 節點 (\d+)／導管 (\d+)／敵人 (\d+)\s+→\s+平均 ([\d.]+) ms.*?最壞 ([\d.]+) ms")
_QUANT_RE = re.compile(r"中位 ([\d.]+)／p95 ([\d.]+)／p99 ([\d.]+) ms；超出 16\.7 ms 的有 (\d+)／(\d+) 幀")


def _perf_one(env: dict[str, str], project: Path | None) -> dict[str, float | str]:
    """回傳 avg／worst／p95／over（超出 16.7 ms 的幀占比 %）與 TL_PROF 報表。**關掉 vsync**：開著的話幀時間會被
    釘在螢幕週期的倍數（240 Hz 螢幕上是 4.17 ms 的倍數），量不出 4 ms 以下的任何差別。
    舊版（沒有分位數輸出）只回平均與最壞。"""
    nan = float("nan")
    e = {"TL_STRESS": "1", "TL_MUTE": "1", "TL_PROF": "1", **env}
    rc, out, _ = _godot(["--disable-vsync", "--path", "godot", "--rendering-driver", "opengl3"], e, 300, project)
    m = _STRESS_RE.search(out)
    if rc != 0 or m is None:
        return {"avg": nan, "worst": nan, "p95": nan, "over": nan, "prof": out[-600:]}
    q = _QUANT_RE.search(out)
    prof = "\n".join(ln.split("] ", 1)[1] for ln in out.splitlines() if "[TL_PROF]" in ln and "ms" in ln)
    return {
        "avg": float(m.group(4)), "worst": float(m.group(5)), "prof": prof,
        "p95": float(q.group(2)) if q else nan,
        "over": 100.0 * int(q.group(4)) / int(q.group(5)) if q else nan,
    }


def _median_run(env: dict[str, str], project: Path | None, runs: int) -> dict[str, float | str]:
    """同一個場景跑 `runs` 次，每個指標取中位數——桌面上別的程式（瀏覽器、通訊軟體）會讓單次量測漂 30–50%。"""
    rs = [_perf_one(env, project) for _ in range(max(1, runs))]
    out: dict[str, float | str] = dict(rs[0])
    for k in ("avg", "worst", "p95", "over"):
        vals = sorted(float(r[k]) for r in rs)
        out[k] = vals[len(vals) // 2]
    return out


def cmd_perf(a: argparse.Namespace) -> int:
    """渲染幀時間（牆上時鐘，RG-183）。`--base DIR`：同一把尺量另一份工作樹，並列出倍數。
    60 FPS ＝ 16.67 ms；45 FPS（底線）＝ 22.22 ms。"""
    base = Path(a.base).resolve() if a.base else None
    print(f"{'場景':<34}{'平均 ms':>9}{'p95':>8}{'最壞':>8}{'超16.7ms':>10}" + (f"{'舊版平均':>10}{'舊版最壞':>10}{'倍數':>7}" if base else ""))
    for name, env in PERF.items():
        r = _median_run(env, None, a.runs)
        line = f"{name:<34}{r['avg']:9.2f}{r['p95']:8.2f}{r['worst']:8.2f}{r['over']:9.1f}%"
        if base:
            b = _median_run(env, base, a.runs)
            line += f"{b['avg']:10.2f}{b['worst']:10.2f}{(b['avg'] / r['avg'] if r['avg'] else float('nan')):6.1f}×"
        print(line)
        if a.prof:
            print("\n".join("      " + ln for ln in str(r["prof"]).splitlines()[:12]))
    return 0


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
    p = sub.add_parser("perf")
    p.add_argument("--base", help="另一份工作樹（含 godot/ 的資料夾），用同一把尺量並對比")
    p.add_argument("--runs", type=int, default=1, help="每個場景跑幾次、取中位數（桌面有別的程式在跑時建議 3）")
    p.add_argument("--prof", action="store_true", help="逐段列出 TL_PROF 的報表（GDScript 側每一段每幀花多少）")
    p.set_defaults(fn=cmd_perf)
    sub.add_parser("all").set_defaults(fn=cmd_all)
    a = ap.parse_args()
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
