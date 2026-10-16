"""在一個**私有的 Windows 桌面**上跑指令——自動化開出來的遊戲視窗不會出現在使用者的螢幕上。

為什麼有這支（使用者 2026-10-16：「測試的時候可以不要讓視窗彈出來到我的螢幕前嗎？」）：
  · `--position` 沒用：Godot 會把視窗夾回螢幕內（量過：要求 -32000,-32000，實際落在 -8,-31）。
  · `--headless` 不行：那是 dummy display server，沒有 GL、不做 GUI 命中測試，截圖與 clicktest 都跑不了。
  · 視窗一建立就搶前景焦點——使用者正在打字的時候，字會打進遊戲視窗。
  · 解法：`CreateDesktop` 建一個**不是使用者看得到的那個**桌面，把行程開在上面。同一個登入工作階段，GPU 照常渲染
    （量過：NVIDIA OpenGL 3.3、TL_SHOT 存得出完整的畫面）；視窗在別的桌面上，不顯示、不搶焦點、沒有實體滑鼠。

用法：
  python qa/desk.py [--cwd DIR] [--timeout 秒] -- <exe> <args...>     環境變數沿用目前的（TL_* 照常傳）
  from desk import run_hidden                                           `qa/check.py` 的 `_godot()` 走這個

`TL_VISIBLE=1`：要親眼看遊戲視窗時（人在電腦前、明確要看）才用，跳過私有桌面。
非 Windows：沒有這個問題的對應物，原樣執行。
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
import time
import uuid


def _to_cmdline(argv: list[str]) -> str:
    return subprocess.list2cmdline([str(a) for a in argv])


def run_hidden(argv: list[str], env: dict[str, str] | None = None, cwd: str | None = None,
               timeout: float = 120) -> tuple[int, str, float]:
    """跑 `argv`，stdout＋stderr 合併回傳：(returncode, 輸出, 秒數)。逾時回 124，並連子行程一起結束。"""
    env = dict(os.environ if env is None else env)
    t0 = time.time()
    if os.name != "nt" or env.get("TL_VISIBLE") or "--headless" in argv:  # headless ＝ 沒有視窗，不需要私有桌面
        p = subprocess.Popen([str(a) for a in argv], cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, encoding="utf-8", errors="replace")
        try:
            out, _ = p.communicate(timeout=timeout)
            return p.returncode, out or "", time.time() - t0
        except subprocess.TimeoutExpired:
            p.kill()
            out, _ = p.communicate()
            return 124, (out or "") + "\n[desk] 逾時", time.time() - t0

    import ctypes
    from ctypes import wintypes as wt

    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    u32 = ctypes.WinDLL("user32", use_last_error=True)

    class STARTUPINFOW(ctypes.Structure):
        _fields_ = [
            ("cb", wt.DWORD), ("lpReserved", wt.LPWSTR), ("lpDesktop", wt.LPWSTR), ("lpTitle", wt.LPWSTR),
            ("dwX", wt.DWORD), ("dwY", wt.DWORD), ("dwXSize", wt.DWORD), ("dwYSize", wt.DWORD),
            ("dwXCountChars", wt.DWORD), ("dwYCountChars", wt.DWORD), ("dwFillAttribute", wt.DWORD),
            ("dwFlags", wt.DWORD), ("wShowWindow", wt.WORD), ("cbReserved2", wt.WORD),
            ("lpReserved2", ctypes.c_void_p), ("hStdInput", wt.HANDLE), ("hStdOutput", wt.HANDLE),
            ("hStdError", wt.HANDLE),
        ]

    class PROCESS_INFORMATION(ctypes.Structure):
        _fields_ = [("hProcess", wt.HANDLE), ("hThread", wt.HANDLE), ("dwProcessId", wt.DWORD), ("dwThreadId", wt.DWORD)]

    u32.CreateDesktopW.restype = wt.HANDLE
    u32.CreateDesktopW.argtypes = [wt.LPCWSTR, wt.LPCWSTR, ctypes.c_void_p, wt.DWORD, wt.DWORD, ctypes.c_void_p]
    u32.CloseDesktop.argtypes = [wt.HANDLE]
    k32.CreateProcessW.argtypes = [
        wt.LPCWSTR, wt.LPWSTR, ctypes.c_void_p, ctypes.c_void_p, wt.BOOL, wt.DWORD, ctypes.c_void_p, wt.LPCWSTR,
        ctypes.POINTER(STARTUPINFOW), ctypes.POINTER(PROCESS_INFORMATION),
    ]
    k32.WaitForSingleObject.argtypes = [wt.HANDLE, wt.DWORD]
    k32.GetExitCodeProcess.argtypes = [wt.HANDLE, ctypes.POINTER(wt.DWORD)]
    k32.CloseHandle.argtypes = [wt.HANDLE]

    name = "TLDesk_%d_%s" % (os.getpid(), uuid.uuid4().hex[:6])
    hdesk = u32.CreateDesktopW(name, None, None, 0, 0x10000000, None)  # GENERIC_ALL
    if not hdesk:
        # 不退回「開在使用者桌面上」——那正是這支要避免的事。
        return 125, "[desk] CreateDesktop 失敗（err=%d）；要在使用者桌面上跑請明確設 TL_VISIBLE=1" % ctypes.get_last_error(), 0.0

    fd, log = tempfile.mkstemp(prefix="tl_desk_", suffix=".log")
    os.close(fd)
    try:
        si = STARTUPINFOW()
        si.cb = ctypes.sizeof(si)
        si.lpDesktop = name
        pi = PROCESS_INFORMATION()
        # 經 `cmd /c` 把輸出導到檔案：不必在私有桌面上傳遞管線把手。`cmd` 的結束碼 ＝ 最後那個程式的結束碼。
        cmd = 'cmd.exe /d /s /c "%s > "%s" 2>&1"' % (_to_cmdline(argv), log)
        block = "".join("%s=%s\0" % (k, v) for k, v in env.items()) + "\0"
        # CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW
        env_buf = ctypes.create_unicode_buffer(len(block) + 1)
        ctypes.memmove(env_buf, block.encode("utf-16-le"), len(block) * 2)
        ok = k32.CreateProcessW(None, ctypes.create_unicode_buffer(cmd), None, None, False, 0x400 | 0x08000000,
                                env_buf, cwd, ctypes.byref(si), ctypes.byref(pi))
        if not ok:
            return 125, "[desk] CreateProcess 失敗（err=%d）" % ctypes.get_last_error(), time.time() - t0
        rc = 124
        waited = k32.WaitForSingleObject(pi.hProcess, int(timeout * 1000))
        if waited == 0:
            code = wt.DWORD()
            k32.GetExitCodeProcess(pi.hProcess, ctypes.byref(code))
            rc = int(code.value)
        else:
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(pi.dwProcessId)], capture_output=True)
            k32.WaitForSingleObject(pi.hProcess, 5000)
        k32.CloseHandle(pi.hProcess)
        k32.CloseHandle(pi.hThread)
        try:
            out = open(log, encoding="utf-8", errors="replace").read()
        except OSError:
            out = ""
        if rc == 124:
            out += "\n[desk] 逾時（已連同子行程一起結束）"
        return rc, out, time.time() - t0
    finally:
        u32.CloseDesktop(hdesk)
        try:
            os.remove(log)
        except OSError:
            pass


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--cwd", default=None)
    ap.add_argument("--timeout", type=float, default=120)
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.cmd[1:] if a.cmd and a.cmd[0] == "--" else a.cmd
    if not cmd:
        ap.error("沒有指令")
    rc, out, dt = run_hidden(cmd, cwd=a.cwd, timeout=a.timeout)
    sys.stdout.buffer.write(out.encode("utf-8", "replace"))
    print("\n[desk] rc=%d %.1fs" % (rc, dt))
    return rc


if __name__ == "__main__":
    sys.exit(main())
