#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""《潮與線》音源產生器（B1.5）。

為什麼是程序生成而不是找素材：`20_ART_DIRECTION.md` §6.1 的決策是「全程序繪製、
零外部圖檔」，理由是授權乾淨、體積可控、調一個 token 全遊戲同步。音訊沿用同一條
——差別只在它產出的是 `.wav` 檔而不是每幀重畫。**這支腳本就是音源的原始碼**：
要調音色改這裡再跑一次，不要去修 wav。

    python assetgen/gen_audio.py

輸出（`20_ART_DIRECTION.md` §6.2 的命名慣例）：
    godot/assets/audio/bgm/tl_bgm_*.wav
    godot/assets/audio/sfx/tl_sfx_*.wav

音樂的三個硬性條件（§5.1「無縫接軌」）：
  ① 三首曲子**同長度、同 BPM、同調性**——戰鬥層是疊上去的，不是換一首。
  ② 每個週期性成分在一個 loop 內都要有**整數個週期**，否則接點會啪一聲。
     `tone()` 會把頻率量化到 1/LOOP 的整數倍來保證這件事。
  ③ 打擊音不要撞到 loop 末端（尾巴會被切掉 → 同樣是啪一聲）。
"""

import math
import os
import random
import struct
import wave

RATE = 22050          # 這是背景音樂與短音效，22.05kHz 聽不出差別，檔案小一半
BPM = 90.0
BEAT = 60.0 / BPM     # 0.6667 s
LOOP = BEAT * 24      # 16.0 s ＝ 6 小節 4/4。三首 BGM 共用這個長度
ROOT = 55.0           # A1。全案的調性中心（A 小調）

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "audio")


# ── 基本零件 ──────────────────────────────────────────────────────────

def buf(dur):
    return [0.0] * int(RATE * dur)


def tone(dst, freq, start, dur, amp, phase=0.0, loop=None, shape="sine"):
    """加一個正弦（或方波）。`loop` 給值時把頻率量化成該長度內的整數週期。"""
    if loop:
        freq = max(1, round(freq * loop)) / loop
    n0 = int(start * RATE)
    w = 2.0 * math.pi * freq
    for i in range(int(dur * RATE)):
        j = n0 + i
        if j >= len(dst):
            break
        v = math.sin(w * (i / RATE) + phase)
        if shape == "square":
            v = 1.0 if v >= 0.0 else -1.0
        elif shape == "saw":
            x = (freq * (i / RATE) + phase / (2.0 * math.pi)) % 1.0
            v = 2.0 * x - 1.0
        dst[j] += v * (amp(i / RATE) if callable(amp) else amp)


def loop_noise(dur, lo, hi, partials, seed, amp=1.0):
    """**接得起來的**噪音：把一堆整數倍頻率的正弦相加，所以一個 loop 內
    每個成分都剛好走完整數個週期。純 `random()` 噪音在接點必啪一聲。"""
    rng = random.Random(seed)
    out = buf(dur)
    freqs = [round(rng.uniform(lo, hi) * dur) / dur for _ in range(partials)]
    phases = [rng.uniform(0, 2 * math.pi) for _ in range(partials)]
    for f, ph in zip(freqs, phases):
        w = 2.0 * math.pi * f
        for i in range(len(out)):
            out[i] += math.sin(w * (i / RATE) + ph)
    k = amp / math.sqrt(max(1, partials))
    return [v * k for v in out]


def noise(dur, seed):
    rng = random.Random(seed)
    return [rng.uniform(-1.0, 1.0) for _ in range(int(dur * RATE))]


def lowpass(sig, cutoff, circular=False):
    """一階 RC 低通。夠用了——這裡要的是「悶一點」不是濾波器教科書。

    `circular=True` 給**會循環播放**的素材用：濾波器有狀態，從 y=0 起跑的那段
    暫態和訊號末端的穩態接不起來，接點就會啪一聲（`audio_test` 抓到過）。
    先空跑一遍拿到末端狀態，再從那裡跑第二遍，出來的就是週期性穩態。
    """
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    y = 0.0
    for _pass in range(2 if circular else 1):
        out = []
        for v in sig:
            y += a * (v - y)
            out.append(y)
    return out


def highpass(sig, cutoff):
    lp = lowpass(sig, cutoff)
    return [v - l for v, l in zip(sig, lp)]


def env_exp(t, dur, curve=6.0):
    """打擊音的包絡：瞬間起音 ＋ 指數衰減。"""
    if t >= dur:
        return 0.0
    return math.exp(-curve * t / dur)


def mix(dst, src, at, gain=1.0):
    n0 = int(at * RATE)
    for i, v in enumerate(src):
        j = n0 + i
        if j >= len(dst):
            break
        dst[j] += v * gain


def fade_edges(sig, ms=4.0):
    """一次性音效的頭尾各抹 4ms，避免 DC 起跳的爆音。"""
    n = int(RATE * ms / 1000.0)
    for i in range(min(n, len(sig))):
        k = i / n
        sig[i] *= k
        sig[-1 - i] *= k
    return sig


def normalize(sig, peak):
    m = max(abs(v) for v in sig) or 1.0
    return [v * peak / m for v in sig]


def write(path, sig):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32000)) for v in sig
        ))
    print("  %-42s %5.1f s" % (os.path.basename(path), len(sig) / RATE))


# ── BGM ───────────────────────────────────────────────────────────────
#
# 氣質（§5「像在一座深海工廠裡工作，而外面有東西在敲玻璃」）：
#   base ＝ 工廠的嗡鳴與稀疏的機械節拍（準備期，平靜）
#   perc ＝ 疊在同一首上的打擊層與失諧高頻（戰鬥期，外面那個東西開始敲了）
#   menu ＝ 同一個嗡鳴，但幾乎什麼都不做（極簡、留白多）

def bgm_base():
    out = buf(LOOP)
    # 低頻 drone：根音、五度、八度。慢 LFO 讓它會呼吸（2 個週期 / loop）。
    lfo = lambda t: 0.32 + 0.10 * math.sin(2.0 * math.pi * (2.0 / LOOP) * t)
    tone(out, ROOT, 0, LOOP, lfo, loop=LOOP)
    tone(out, ROOT * 1.5, 0, LOOP, lambda t: lfo(t) * 0.45, loop=LOOP, phase=1.1)
    tone(out, ROOT * 2, 0, LOOP, lambda t: lfo(t) * 0.30, loop=LOOP, phase=2.2)
    # A 小調鋪底，很輕，每 8 拍漲落一次。
    for f, a in [(220.0, 0.06), (261.63, 0.05), (329.63, 0.045)]:
        tone(out, f, 0, LOOP,
             lambda t, a=a: a * (0.5 + 0.5 * math.sin(2.0 * math.pi * (3.0 / LOOP) * t)),
             loop=LOOP)
    # 稀疏的機械節拍：每 2 拍一下，悶悶的短敲擊。**最後一拍留白**，
    # 免得尾巴被 loop 切斷。
    for b in range(0, 24, 2):
        if b * BEAT > LOOP - 0.5:
            break
        tick = lowpass(noise(0.09, 700 + b), 2600)
        tick = [v * env_exp(i / RATE, 0.09, 9.0) for i, v in enumerate(tick)]
        mix(out, tick, b * BEAT, 0.16 if b % 8 else 0.26)
    return normalize(out, 0.72)


def bgm_perc():
    out = buf(LOOP)
    # 打擊層：每一拍一顆低頻 kick（下滑的正弦），反拍一個金屬碎響。
    for b in range(24):
        t0 = b * BEAT
        if t0 > LOOP - 0.4:
            break
        kick = buf(0.26)
        for i in range(len(kick)):
            t = i / RATE
            f = 110.0 * math.exp(-9.0 * t) + 44.0
            kick[i] = math.sin(2.0 * math.pi * f * t) * env_exp(t, 0.26, 7.0)
        mix(out, kick, t0, 0.55 if b % 4 == 0 else 0.34)
        if b * BEAT + BEAT * 0.5 < LOOP - 0.2:
            hat = highpass(noise(0.06, 31 + b), 5200)
            hat = [v * env_exp(i / RATE, 0.06, 14.0) for i, v in enumerate(hat)]
            mix(out, hat, t0 + BEAT * 0.5, 0.20)
    # 失諧的高頻：兩個差 8Hz 的正弦互相打拍，慢慢進出。**這是「威脅」那一層**。
    swell = lambda t: 0.05 * (0.5 - 0.5 * math.cos(2.0 * math.pi * (2.0 / LOOP) * t))
    tone(out, 1320.0, 0, LOOP, swell, loop=LOOP)
    tone(out, 1328.0, 0, LOOP, swell, loop=LOOP, phase=0.7)
    return normalize(out, 0.70)


def bgm_menu():
    """主選單。

    ★ 第一版是「drone ＋ 每 6 拍一顆鐘」，使用者回報「不好，要再帶感一點點」。
    **「一點點」是規格的一部分**：它是選單曲，不是戰鬥曲——把打擊層搬過來就
    等於每次回主選單都被催一次。所以加的是**脈動與行進感**，不是鼓：
      ① 走一條八分音符的低音撥弦（A–A–C–E 循環），它給的是「有東西在走」
      ② 每小節第一拍一個很輕的低頻脈衝當骨架，不是 kick
      ③ 鐘留著但退到後面——它現在是點綴，不是唯一在動的東西
    """
    out = buf(LOOP)
    lfo = lambda t: 0.30 + 0.07 * math.sin(2.0 * math.pi * (1.0 / LOOP) * t)
    tone(out, ROOT, 0, LOOP, lfo, loop=LOOP)
    tone(out, ROOT * 2, 0, LOOP, lambda t: lfo(t) * 0.20, loop=LOOP, phase=1.7)

    # ① 八分音符的低音撥弦。音高走 A–A–C–E，四拍一循環。
    steps = [110.0, 110.0, 130.81, 164.81]
    for k in range(48):                      # 24 拍 × 2 ＝ 48 個八分音符
        t0 = k * BEAT * 0.5
        if t0 > LOOP - 0.35:
            break
        f = steps[(k // 2) % 4]
        pluck = buf(0.32)
        for i in range(len(pluck)):
            t = i / RATE
            e = env_exp(t, 0.32, 9.0)
            pluck[i] = (
                math.sin(2.0 * math.pi * f * t) * e
                + 0.35 * math.sin(2.0 * math.pi * f * 2.0 * t) * e * e
            )
        # 反拍輕一點：那個強弱差就是「行進」的感覺，音量一樣大只會變節拍器。
        mix(out, fade_edges(pluck, 2.0), t0, 0.30 if k % 2 == 0 else 0.17)

    # ② 每小節第一拍的低頻脈衝。很輕，只給骨架。
    for b in range(0, 24, 4):
        if b * BEAT > LOOP - 0.4:
            break
        pulse = buf(0.3)
        for i in range(len(pulse)):
            t = i / RATE
            pulse[i] = math.sin(
                2.0 * math.pi * (95.0 * math.exp(-10.0 * t) + 55.0) * t
            ) * env_exp(t, 0.3, 6.0)
        mix(out, pulse, b * BEAT, 0.30)

    # ③ 鐘：退到 0.14，並且只留兩顆——它現在是點綴。
    for k, b in enumerate([0, 12]):
        f = [880.0, 659.25][k]
        bell = buf(2.4)
        for i in range(len(bell)):
            t = i / RATE
            e = env_exp(t, 2.4, 5.0)
            bell[i] = (
                math.sin(2.0 * math.pi * f * t) * e
                + 0.30 * math.sin(2.0 * math.pi * f * 2.01 * t) * e * e
            )
        mix(out, fade_edges(bell, 3.0), b * BEAT, 0.14)
    return normalize(out, 0.68)


# ── SFX ───────────────────────────────────────────────────────────────

def sfx_build_place():
    """節點放置：短促金屬扣合。"""
    out = buf(0.16)
    click = lowpass(noise(0.05, 11), 5000)
    mix(out, [v * env_exp(i / RATE, 0.05, 12.0) for i, v in enumerate(click)], 0.0, 0.8)
    for f, a in [(880.0, 0.5), (1319.0, 0.28), (1976.0, 0.14)]:
        tone(out, f, 0.005, 0.15, lambda t, a=a: a * env_exp(t, 0.15, 11.0))
    return fade_edges(normalize(out, 0.80))


def sfx_build_wire():
    """導管連接：扣上去的兩段聲。

    ★ 第一版是 0.28 秒的上升掃頻（§5.1 的字面寫法），使用者回報不喜歡——
    掃頻在這套音色裡聽起來像雷射，而**拉一條管子是機械動作不是能量武器**，
    而且它是全遊戲按最多次的音之一，尖銳的高頻掃上去幾次就煩了。
    改成「推進去 → 卡住」：一段短的下行實體聲，接一個乾的金屬扣。
    """
    out = buf(0.20)
    # ① 推進去：320 → 190Hz 的短促身體，帶一點摩擦噪音。
    for i in range(len(out)):
        t = i / RATE
        out[i] = math.sin(
            2.0 * math.pi * (320.0 * math.exp(-22.0 * t) + 190.0) * t
        ) * env_exp(t, 0.20, 13.0)
    slide = lowpass(noise(0.07, 313), 2400)
    mix(out, [v * env_exp(i / RATE, 0.07, 7.0) for i, v in enumerate(slide)], 0.0, 0.30)
    # ② 卡住：0.075 秒後一個很短的金屬扣。**兩段之間的間隔就是「接上了」**。
    latch = buf(0.06)
    for i in range(len(latch)):
        t = i / RATE
        e = env_exp(t, 0.06, 18.0)
        latch[i] = (
            math.sin(2.0 * math.pi * 1180.0 * t) * e
            + 0.5 * math.sin(2.0 * math.pi * 1770.0 * t) * e * e
        )
    mix(out, fade_edges(latch, 1.5), 0.075, 0.45)
    return fade_edges(normalize(out, 0.62), 2.0)


def sfx_build_destroyed():
    """建築損毀：低頻碎裂 ＋ 下滑。"""
    out = buf(0.5)
    crunch = lowpass(noise(0.5, 77), 1800)
    mix(out, [v * env_exp(i / RATE, 0.5, 5.0) for i, v in enumerate(crunch)], 0.0, 0.9)
    for i in range(len(out)):
        t = i / RATE
        out[i] += math.sin(2.0 * math.pi * (300.0 * math.exp(-5.0 * t) + 55.0) * t) \
            * env_exp(t, 0.5, 4.0) * 0.7
    return fade_edges(normalize(out, 0.85))


def sfx_prod_flow():
    """資源流動的低頻循環。**這一支要能無縫循環**（它一直開著）。"""
    dur = 2.0
    out = buf(dur)
    tone(out, 58.0, 0, dur, 0.5, loop=dur)
    tone(out, 87.0, 0, dur, 0.22, loop=dur, phase=1.3)
    hum = loop_noise(dur, 120.0, 900.0, 40, seed=5, amp=0.5)
    mix(out, lowpass(hum, 700, circular=True), 0.0, 1.0)
    # 慢的音量起伏，讓它不像一條死掉的正弦。
    for i in range(len(out)):
        out[i] *= 0.8 + 0.2 * math.sin(2.0 * math.pi * (2.0 / dur) * (i / RATE))
    return normalize(out, 0.55)


def _fire(dur, body, peak=0.78):
    out = buf(dur)
    for i in range(len(out)):
        out[i] = body(i / RATE)
    return fade_edges(normalize(out, peak))


def sfx_fire_anchor():
    """錨：短促結實的一擊。

    ★ 第一版是 200→80Hz、0.18 秒的低頻，使用者回報「太沉重」——錨是**射得最快的
    那一座塔**，一秒好幾發的東西不能用重擊的音色，聽久了像有人在敲牆。
    改成高一個八度、短一半，收尾帶一點乾的木質敲擊，讓它退回背景。
    """
    out = buf(0.10)
    for i in range(len(out)):
        t = i / RATE
        out[i] = math.sin(
            2.0 * math.pi * (520.0 * math.exp(-26.0 * t) + 240.0) * t
        ) * env_exp(t, 0.10, 15.0)
    tap = highpass(noise(0.03, 617), 2200)
    mix(out, [v * env_exp(i / RATE, 0.03, 16.0) for i, v in enumerate(tap)], 0.0, 0.35)
    return fade_edges(normalize(out, 0.52), 2.0)


def sfx_fire_prism():
    """稜鏡：明亮的電擊，帶一點 FM。"""
    return _fire(0.14, lambda t: math.sin(
        2.0 * math.pi * 1750.0 * t + 3.0 * math.sin(2.0 * math.pi * 430.0 * t)
    ) * env_exp(t, 0.14, 13.0), peak=0.62)


def sfx_fire_reclaimer():
    """回收者：吸回來的上滑短音（它的動作是回收，不是打擊）。"""
    return _fire(0.22, lambda t: math.sin(
        2.0 * math.pi * (300.0 + 700.0 * (t / 0.22) ** 2) * t) * env_exp(t, 0.22, 5.0), peak=0.58)


def sfx_fire_breaker():
    """碎浪：雙音重擊。"""
    out = buf(0.3)
    for i in range(len(out)):
        t = i / RATE
        e = env_exp(t, 0.3, 7.0)
        out[i] = (
            math.sin(2.0 * math.pi * (150.0 * math.exp(-8.0 * t) + 60.0) * t) * e
            + 0.5 * math.sin(2.0 * math.pi * 233.0 * t) * e * e
        )
    crack = highpass(noise(0.08, 909), 3000)
    mix(out, [v * env_exp(i / RATE, 0.08, 10.0) for i, v in enumerate(crack)], 0.0, 0.5)
    return fade_edges(normalize(out, 0.86))


def sfx_enemy_hit():
    """敵人受擊：短、乾、不搶戲（一波幾十次）。"""
    out = buf(0.07)
    tick = highpass(noise(0.07, 404), 1400)
    for i in range(len(out)):
        out[i] = tick[i] * env_exp(i / RATE, 0.07, 12.0)
    return fade_edges(normalize(out, 0.40), 2.0)


def sfx_warn_power():
    """能量不足：低頻警報，兩短聲。"""
    out = buf(0.55)
    for k in range(2):
        t0 = k * 0.22
        seg = buf(0.18)
        for i in range(len(seg)):
            t = i / RATE
            seg[i] = math.sin(2.0 * math.pi * 196.0 * t) * (
                1.0 if math.sin(2.0 * math.pi * 30.0 * t) > -0.5 else 0.5
            ) * min(1.0, t / 0.01) * env_exp(t, 0.18, 3.0)
        mix(out, seg, t0, 1.0)
    return fade_edges(normalize(out, 0.72))


def sfx_core_hit():
    """核心受擊：**全場最醒目的一個音**（§5.1）。低頻爆 ＋ 不諧和的二度。"""
    out = buf(0.9)
    for i in range(len(out)):
        t = i / RATE
        e = env_exp(t, 0.9, 4.0)
        out[i] = (
            math.sin(2.0 * math.pi * (90.0 * math.exp(-4.0 * t) + 41.0) * t) * e * 1.0
            + 0.35 * math.sin(2.0 * math.pi * 233.08 * t) * e
            + 0.30 * math.sin(2.0 * math.pi * 246.94 * t) * e   # 小二度 → 刺耳
        )
    boom = lowpass(noise(0.35, 13), 900)
    mix(out, [v * env_exp(i / RATE, 0.35, 6.0) for i, v in enumerate(boom)], 0.0, 0.6)
    return fade_edges(normalize(out, 0.95))


def sfx_ui_click():
    out = buf(0.05)
    c = lowpass(noise(0.05, 2), 3800)
    for i in range(len(out)):
        out[i] = c[i] * env_exp(i / RATE, 0.05, 16.0)
    tone(out, 1200.0, 0.0, 0.04, lambda t: 0.5 * env_exp(t, 0.04, 16.0))
    return fade_edges(normalize(out, 0.34), 2.0)


def sfx_ui_back():
    """取消：兩個下行音。"""
    out = buf(0.2)
    tone(out, 660.0, 0.0, 0.09, lambda t: 0.6 * env_exp(t, 0.09, 8.0))
    tone(out, 440.0, 0.08, 0.12, lambda t: 0.6 * env_exp(t, 0.12, 8.0))
    return fade_edges(normalize(out, 0.42))


def sfx_ui_unlock():
    """解鎖：上行的兩個音 ＋ 泛音（唯一一個「獎勵」音色）。"""
    out = buf(0.55)
    for k, f in enumerate([440.0, 659.25]):
        t0 = k * 0.11
        seg = buf(0.44)
        for i in range(len(seg)):
            t = i / RATE
            e = env_exp(t, 0.44, 5.0)
            seg[i] = (math.sin(2.0 * math.pi * f * t) + 0.3 * math.sin(2.0 * math.pi * f * 2 * t)) * e
        mix(out, fade_edges(seg, 3.0), t0, 0.6)
    return fade_edges(normalize(out, 0.62))


BGM = {
    "tl_bgm_battle_base": bgm_base,
    "tl_bgm_battle_perc": bgm_perc,
    "tl_bgm_menu": bgm_menu,
}

SFX = {
    "tl_sfx_build_place": sfx_build_place,
    "tl_sfx_build_wire": sfx_build_wire,
    "tl_sfx_build_destroyed": sfx_build_destroyed,
    "tl_sfx_prod_flow": sfx_prod_flow,
    "tl_sfx_fire_anchor": sfx_fire_anchor,
    "tl_sfx_fire_prism": sfx_fire_prism,
    "tl_sfx_fire_reclaimer": sfx_fire_reclaimer,
    "tl_sfx_fire_breaker": sfx_fire_breaker,
    "tl_sfx_enemy_hit": sfx_enemy_hit,
    "tl_sfx_warn_power": sfx_warn_power,
    "tl_sfx_core_hit": sfx_core_hit,
    "tl_sfx_ui_click": sfx_ui_click,
    "tl_sfx_ui_back": sfx_ui_back,
    "tl_sfx_ui_unlock": sfx_ui_unlock,
}


def main():
    print("BGM（%.1f s／%.0f BPM／A 小調，三首同長度）" % (LOOP, BPM))
    for name, fn in BGM.items():
        write(os.path.join(OUT, "bgm", name + ".wav"), fn())
    print("SFX（%d 支）" % len(SFX))
    for name, fn in SFX.items():
        write(os.path.join(OUT, "sfx", name + ".wav"), fn())


if __name__ == "__main__":
    main()
