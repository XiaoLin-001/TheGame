#!/usr/bin/env python3
"""一鍵把這台機器弄到「能跑、能測、能匯出」（B3.14）。

    python dev/setup.py            檢查，缺什麼補什麼（冪等：已經有的不會重抓）
    python dev/setup.py --check    只檢查，不下載、不寫檔

它做的事，依序：
  1. Godot 4.7 console 執行檔  → tools/godot/（gitignore；官方 GitHub release）
  2. Windows 匯出範本          → %APPDATA%/Godot/export_templates/4.7.stable/
  3. godot/export_presets.cfg  → 由 dev/export_presets.template.cfg 產生（該檔 gitignore，
                                  因為 Godot 會把 Android keystore 密碼明文寫進它）
  4. 匯入專案（產生 .godot/ 快取）
  5. 靜態地雷掃描 qa/gd_lint.py

下載量：Godot 約 60 MB、匯出範本約 1 GB（只解出 Windows 要用的幾個檔，其餘丟掉）。
全部來自 https://github.com/godotengine/godot/releases ——不經任何第三方。
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")  # 與 qa/gd_lint.py 同一個慣例
ROOT = Path(__file__).resolve().parent.parent
VERSION = "4.7"
TAG = f"{VERSION}-stable"
BASE = f"https://github.com/godotengine/godot/releases/download/{TAG}"
GODOT_ZIP = f"Godot_v{TAG}_win64.exe.zip"
GODOT_CONSOLE = f"Godot_v{TAG}_win64_console.exe"
TEMPLATES_TPZ = f"Godot_v{TAG}_export_templates.tpz"
TEMPLATE_DIR = Path(os.environ.get("APPDATA", Path.home() / ".local" / "share")) / "Godot" / "export_templates" / f"{VERSION}.stable"
# 匯出 Windows Desktop 只會用到這兩個（release 是 export-release，debug 是 export-debug）
NEED_TEMPLATES = ["windows_release_x86_64.exe", "windows_debug_x86_64.exe"]

GODOT_DIR = ROOT / "tools" / "godot"
PRESETS = ROOT / "godot" / "export_presets.cfg"
PRESETS_TEMPLATE = ROOT / "dev" / "export_presets.template.cfg"


def say(ok: bool | None, msg: str) -> None:
    print(f"  [{'OK' if ok else ('--' if ok is None else '!!')}] {msg}", flush=True)


def download(url: str, dest: Path) -> None:
    print(f"       下載 {url}", flush=True)
    last = [-1]

    def hook(blocks: int, size: int, total: int) -> None:
        if total > 0:
            pct = min(100, blocks * size * 100 // total)
            if pct // 10 != last[0]:
                last[0] = pct // 10
                print(f"       … {pct}%", flush=True)

    urllib.request.urlretrieve(url, dest, hook)


def step_godot(check: bool) -> bool:
    exe = GODOT_DIR / GODOT_CONSOLE
    if exe.exists():
        say(True, f"Godot {VERSION}：{exe.relative_to(ROOT)}")
        return True
    if check:
        say(False, f"缺 Godot：{exe.relative_to(ROOT)}")
        return False
    GODOT_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        z = Path(tmp) / GODOT_ZIP
        download(f"{BASE}/{GODOT_ZIP}", z)
        with zipfile.ZipFile(z) as zf:
            zf.extractall(GODOT_DIR)
    ok = exe.exists()
    say(ok, f"Godot {VERSION} 已安裝到 {GODOT_DIR.relative_to(ROOT)}" if ok else "解壓後找不到 console 執行檔")
    return ok


def step_templates(check: bool) -> bool:
    missing = [n for n in NEED_TEMPLATES if not (TEMPLATE_DIR / n).exists()]
    if not missing:
        say(True, f"匯出範本：{TEMPLATE_DIR}")
        return True
    if check:
        say(False, f"缺匯出範本：{', '.join(missing)}（{TEMPLATE_DIR}）")
        return False
    TEMPLATE_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        t = Path(tmp) / TEMPLATES_TPZ
        download(f"{BASE}/{TEMPLATES_TPZ}", t)
        with zipfile.ZipFile(t) as zf:
            for name in zf.namelist():
                base = Path(name).name
                # 只留 Windows 的；Android／iOS／Web／Linux 各數百 MB，這個專案用不到
                if name.startswith("templates/") and (base.startswith("windows_") or base == "version.txt"):
                    with zf.open(name) as src, open(TEMPLATE_DIR / base, "wb") as dst:
                        shutil.copyfileobj(src, dst)
    still = [n for n in NEED_TEMPLATES if not (TEMPLATE_DIR / n).exists()]
    say(not still, "匯出範本已安裝" if not still else f"仍缺：{still}")
    return not still


def step_presets(check: bool) -> bool:
    if PRESETS.exists():
        say(True, f"匯出設定：{PRESETS.relative_to(ROOT)}")
        return True
    if check:
        say(False, f"缺 {PRESETS.relative_to(ROOT)}（由 dev/export_presets.template.cfg 產生）")
        return False
    shutil.copyfile(PRESETS_TEMPLATE, PRESETS)
    say(True, f"已由範本產生 {PRESETS.relative_to(ROOT)}")
    return True


def step_import(check: bool) -> bool:
    exe = GODOT_DIR / GODOT_CONSOLE
    if not exe.exists():
        say(None, "略過匯入（沒有 Godot）")
        return False
    if (ROOT / "godot" / ".godot").exists() and check:
        say(True, "專案已匯入（godot/.godot 存在）")
        return True
    if check:
        say(False, "專案尚未匯入（godot/.godot 不存在）")
        return False
    r = subprocess.run([str(exe), "--headless", "--path", "godot", "--import"], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    bad = [ln for ln in (r.stdout + r.stderr).splitlines() if "SCRIPT ERROR" in ln or "Parse Error" in ln]
    say(r.returncode == 0 and not bad, "專案匯入完成" if r.returncode == 0 and not bad else "匯入有錯：" + "; ".join(bad[:3]))
    return r.returncode == 0 and not bad


def step_lint() -> bool:
    r = subprocess.run([sys.executable, str(ROOT / "qa" / "gd_lint.py")], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    say(r.returncode == 0, "靜態地雷掃描：" + (r.stdout.strip().splitlines() or ["?"])[-1])
    return r.returncode == 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="只檢查，不下載、不寫檔")
    a = ap.parse_args()
    print("潮與線 Tide & Line — 環境檢查" + ("（唯讀）" if a.check else ""))
    ok = step_godot(a.check)
    ok &= step_templates(a.check)
    ok &= step_presets(a.check)
    ok &= step_import(a.check)
    ok &= step_lint()
    print()
    if ok:
        print("環境就緒。")
        print("  玩遊戲：        dev\\play.bat")
        print("  跑全部測試：    python qa/check.py all")
        print("  匯出 exe：      dev\\export.bat")
    else:
        print("有項目未就緒；不加 --check 重跑一次會自動補齊能補的。")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
