class_name Motion
extends RefCounted
## 動效 token（`20_ART_DIRECTION.md` §4）。**全 static，純函式。**
##
## ── 為什麼到 B1.6 才有這個檔案 ──────────────────────────────────────
## `CLAUDE.md` 的專案結構從第一批就列著它、§4.1 也早就定義了時長階，
## 但它一直沒有被實作：於是每個動效都是散在畫面層的字面量
## （`sin(tick * 0.4)`、`sin(tick * 0.25)`、`ttl = 3`），四個問題跟著來——
##   ① 時長階形同不存在，沒有人在對 0.12／0.24／0.50
##   ② `settings.reduce_motion` 是**死設定**：存檔裡有、沒有任何人讀
##   ③ 同一種脈動在兩個地方用不同係數，看起來像兩件不同的事
##   ④ 「所有動效都可跳過」（§4.4）沒有任何一個掛勾點
##
## ── 兩條紀律 ────────────────────────────────────────────────────────
## **① 一律由 tick 驅動，不用系統時間。** 渲染可以不確定，但別引入新的亂數源
##    ——`TL_SHOT` 凍結在第 N tick 時，同參數要拍出同一張圖。
## **② `reduce` 為真時，所有週期性動態一律回傳靜止值。** 這既是無障礙需求，
##    也是高手快速重來的需求（§4.4）。開關由畫面層在 `_ready()` 從存檔設進來。

## 時長階（§4.1）。秒。
const INSTANT := 0.12   ## 按鈕回饋、hover、選中框
const BASE := 0.24      ## 面板開闔、數值補間、狀態切換
const SLOW := 0.50      ## 畫面轉場、局末結算逐項揭示
const AMBIENT := 2.0    ## 敵潮脈動、背景呼吸（循環）

const Clock := preload("res://scripts/sim/Clock.gd")
## 固定時間步。**值的唯一來源是 `sim/Clock.gd`**（B1.9）——這裡只是別名，
## 讓呼叫端維持讀得懂的 `Motion.TICK`。
const TICK := Clock.TICK

## ★ 「減少動態效果」（§4.4）。**全域、由畫面層設定一次。**
## 為真時：脈動回靜止值、碎片與閃光不生成、時長階回 0。
static var reduce: bool = false


## 時長階 → tick 數（至少 1，否則 `reduce` 之外的效果會一出生就死）。
static func ticks(seconds: float) -> int:
	return 0 if reduce else maxi(1, roundi(seconds / TICK))


# ── 緩動（§4.2）────────────────────────────────────────────────────────
#
# §4.2 訂了三條曲線，但**只有一條需要是函式**：
#   `ease-out-cubic`（玩家操作的回饋）── 就是下面這支。
#   `linear`（系統自動的變化）── **就是「不套緩動」本身**。給它一支
#     `return clampf(t, 0, 1)` 的函式，呼叫端讀起來反而像套了什麼東西。
#   `ease-in-out-sine` 循環（敵潮的動態）── 已經實作在 `pulse()` / `pulse01()`
#     裡面（`sin(TAU × …)` 就是那條曲線）。另開一支獨立入口是第二個真相來源。
#
# 兩支都曾經存在、零呼叫端，B1.9 刪除。

## 玩家操作的回饋：快起慢收＝有回應感。
static func ease_out_cubic(t: float) -> float:
	var x := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - x * x * x


# ── 週期脈動 ──────────────────────────────────────────────────────────

## 呼吸式脈動，回傳 `1.0 ± amount`。`period` 是週期（秒）。
##
## 全專案的脈動一律走這裡：B1.6 之前能量條用 `sin(tick*0.4)`、敵人用
## `sin(tick*0.25)`，兩個係數沒有任何理由不同，看起來卻像兩件不同的事。
static func pulse(tick: int, period: float = AMBIENT, amount: float = 0.12,
		phase: float = 0.0) -> float:
	if reduce or period <= 0.0:
		return 1.0
	return 1.0 + amount * sin(TAU * (float(tick) * TICK / period) + phase)


## 同一條曲線，但值域收在 `0..1`（透明度用）。
static func pulse01(tick: int, period: float = AMBIENT, lo: float = 0.35,
		phase: float = 0.0) -> float:
	if reduce or period <= 0.0:
		return 1.0
	var k := 0.5 + 0.5 * sin(TAU * (float(tick) * TICK / period) + phase)
	return lo + (1.0 - lo) * k


# ── 效果的生命週期 ────────────────────────────────────────────────────

## 一個 tick 壽命制的效果，現在走到哪了（0 ＝ 剛生成，1 ＝ 結束）。
##
## `frac` 是這一 tick 內已經過的比例（畫面層的 `_accum / TICK`），
## 有它才能在 10Hz 的模擬上畫出 60Hz 的平滑動畫。
static func progress(life: int, ttl: int, frac: float = 0.0) -> float:
	if life <= 0:
		return 1.0
	return clampf((float(life - ttl) + clampf(frac, 0.0, 1.0)) / float(life), 0.0, 1.0)


## ★ 幾何碎片的方向。**零 RNG**：由來源 id 與序號決定，所以同一次擊殺
## 在任何機器上、重播幾次都炸成同一個樣子（`30_TECH_DESIGN.md` §2.4）。
##
## 不是均勻分佈的 `i/n × TAU`——那會炸成一朵標本花。加一個由 id 決定的
## 不規則量，讓每一次爆炸各有各的樣子，但仍然是確定的。
static func fragment_dir(source_id: int, index: int, count: int) -> Vector2:
	var base := TAU * float(index) / float(maxi(1, count))
	var jitter := sin(float(source_id) * 2.399 + float(index) * 1.618) * 0.55
	return Vector2(cos(base + jitter), sin(base + jitter))
