"""開機畫面（`godot/assets/ui/splash.png`）的產生器——**這支才是它的原始碼，不要去修 png**。

為什麼有開機畫面：引擎自己的初始化（視窗、顯示卡驅動、字型資料）就要 1.5–2 秒，這段腳本管不到；
預設的開機畫面是 Godot 的 logo。換成遊戲自己的，等待就是「遊戲在開」而不是「別人的引擎在開」。

色值抄自 `scripts/render/Palette.gd`（Godot 以外的工具讀不到那支）：BG_DEEP／BORDER_SUBTLE／ORDER_CYAN／ORDER_BRIGHT／
TIDE_DEEP／TIDE_MAGENTA／TEXT_PRIMARY／TEXT_SECONDARY。改色先改 Palette，再回來同步這裡。

  python assetgen/gen_splash.py
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

BG_DEEP = "#0a1420"
BORDER_SUBTLE = "#1d3547"
ORDER_CYAN = "#7fd4e8"
ORDER_BRIGHT = "#a8f0ff"
ORDER_DIM = "#3c6e80"
TIDE_DEEP = "#7b2d5e"
TIDE_MAGENTA = "#ff4d6d"
TEXT_PRIMARY = "#e8f1f5"
TEXT_SECONDARY = "#8ba3b0"

W, H, S = 1280, 720, 2          # 輸出尺寸；內部以 2 倍畫再縮（抗鋸齒）
OUT = Path(__file__).resolve().parent.parent / "godot" / "assets" / "ui" / "splash.png"
FONT_DIR = Path("C:/Windows/Fonts")


def font(name: str, px: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT_DIR / name), px * S)


def main() -> None:
    img = Image.new("RGB", (W * S, H * S), BG_DEEP)
    d = ImageDraw.Draw(img)

    # 格線（與遊戲地圖同一種底紋）
    step = 40 * S
    for x in range(0, W * S, step):
        d.line([(x, 0), (x, H * S)], fill=BORDER_SUBTLE, width=1)
    for y in range(0, H * S, step):
        d.line([(0, y), (W * S, y)], fill=BORDER_SUBTLE, width=1)

    # 敵潮的路徑帶（左上往下轉進核心）：只有敵人與危險才用品紅／橙——這裡是「潮」。
    # 55% 不透明：它是背景，不跟字搶。
    band = [(-40, 90), (170, 90), (170, 630), (1320, 630)]
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).line([(x * S, y * S) for x, y in band], fill=int(255 * 0.55), width=56 * S, joint="curve")
    img.paste(TIDE_DEEP, mask=mask)
    d = ImageDraw.Draw(img)
    for i in range(3):
        cx, cy = 60 + i * 60, 90
        d.polygon([((cx - 7) * S, (cy - 9) * S), ((cx + 7) * S, cy * S), ((cx - 7) * S, (cy + 9) * S)], fill=TIDE_MAGENTA)

    # 「線」：一條導管橫過去，三個節點
    y = 520
    d.line([(300 * S, y * S), (980 * S, y * S)], fill=ORDER_CYAN, width=6 * S)
    for x in (300, 640, 980):
        d.ellipse([(x - 16) * S, (y - 16) * S, (x + 16) * S, (y + 16) * S], fill=BG_DEEP, outline=ORDER_BRIGHT, width=4 * S)
        d.ellipse([(x - 6) * S, (y - 6) * S, (x + 6) * S, (y + 6) * S], fill=ORDER_CYAN)

    # 標題
    title, sub = "潮與線", "Tide & Line"
    ft, fs = font("msjhbd.ttc", 150), font("msjh.ttc", 44)
    tw = d.textlength(title, font=ft)
    d.text(((W * S - tw) / 2, 150 * S), title, font=ft, fill=TEXT_PRIMARY)
    sw = d.textlength(sub, font=fs)
    d.text(((W * S - sw) / 2, 350 * S), sub, font=fs, fill=ORDER_CYAN)

    out = img.resize((W, H), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT, optimize=True)
    print("wrote", OUT, OUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
