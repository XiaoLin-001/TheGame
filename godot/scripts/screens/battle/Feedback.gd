extends Node
## 局內回饋：從**狀態的差值**推導音效與死因（`CLAUDE.md` 技術慣例）。
##
## 全部在畫面層，**模擬層（`scripts/sim/`）一行都不知道它的存在**——在 sim 裡塞一行
## `AudioBus.play()`，每日挑戰的重播就會出聲。代價是要自己記上一幀；換到的是 `sim/` 可以
## 在 headless 重播一萬次而不出聲。

const BattleController := preload("res://scripts/game/BattleController.gd")

## 擁有這個模組的局內畫面（`screens/Battle.gd`）。由它在建立時指派。
var scr: Control = null
## 局的狀態（與 `scr.s` 同一個物件；換局時由畫面重新指派）。
var s: RefCounted = null


## ★ 音訊（B1.5）。上一幀的幾個數字，用來推導「這一幀發生了什麼」。
## **音效一律從畫面層推導，模擬層維持零副作用**（`CLAUDE.md` 技術慣例）：
## 在 `scripts/sim/` 裡塞一行 `AudioBus.play()` 就等於讓每日挑戰的重播會出聲。
var _audio_prev: Dictionary = {}

## 上一幀看到的 tick 序號（音訊與死因診斷共用的邊緣偵測）。
var last_tick: int = -1

## 死因歸因的累計（B1.7）。純畫面層，模擬層不知道它的存在。
var _diag: Dictionary = {}


## ★ 死因歸因的原始資料（B1.7）。
##
## M1 的驗收句子是「**陌生人可以說得出自己為什麼輸**」。局末面板原本只給
## 「撐過幾波、產能積分多少」——那些是**成績**，不是**原因**。玩家輸掉的時候
## 要的是下一句「所以我下次該改什麼」。
##
## 全部從畫面層累計，模擬層一個欄位都不動（`scripts/sim/` 零副作用）。
func diag_tick() -> void:
	if s.phase != "wave":
		return
	_diag["wave_ticks"] = int(_diag["wave_ticks"]) + 1
	if float(s.rates["power_demand"]) > float(s.rates["power_supply"]) + 0.01:
		_diag["starved"] = int(_diag["starved"]) + 1
	# 核心開始掉血的那一波 ＝ 第一次有敵人走到底。
	if int(_diag["leak_wave"]) < 0 and s.core_hp() < float(_diag["core_hp"]) - 0.01:
		_diag["leak_wave"] = s.wave_index
	_diag["core_hp"] = s.core_hp()


## 一句話的死因。**只給一句**：三條並列的診斷等於沒有診斷。
func diag_line(won: bool) -> String:
	var ticks: int = maxi(1, int(_diag["wave_ticks"]))
	var starve := float(_diag["starved"]) / float(ticks)
	var leak: int = int(_diag["leak_wave"])
	if not won:
		if leak >= 0:
			return "為什麼輸　第 %d 波開始有敵人走到核心。%s" % [
				leak,
				"缺電讓塔的射速掉了（%d%% 的戰鬥時間供不應求）——先補發電機或儲槽。" % roundi(starve * 100.0)
				if starve >= 0.25 else "那條路線上的火力不夠——把塔往敵人的必經之路挪，或多蓋一座。",
			]
		return "為什麼輸　核心被相鄰的敵人啃掉了。節點退開敵人路徑 2 格就打不到。"
	if starve >= 0.25:
		return "下一次　有 %d%% 的戰鬥時間供不應求，塔是降速在打的——補電力就能拉高產能積分。" % roundi(starve * 100.0)
	return ""


func audio_reset() -> void:
	_audio_prev = {
		"kills": s.kills, "nodes": s.nodes.size(), "core": s.core_hp(),
		"warn_at": -99.0, "core_at": -99.0, "phase": s.phase,
	}
	last_tick = s.tick_count
	_diag = {"wave_ticks": 0, "starved": 0, "leak_wave": -1, "core_hp": s.core_hp()}


## 這一幀發生了什麼？全部從狀態的差值推出來——**不在模擬層留任何一個
## 「順便播個音」的呼叫**。代價是要自己記上一幀，換到的是 `sim/` 仍然
## 可以在 headless 重播一萬次而不出聲。
func audio_tick(advanced: bool) -> void:
	if _audio_prev.is_empty():
		return
	var over: bool = s.phase == "won" or s.phase == "lost"
	# ★ B2.1f：戰鬥期**完全沒有音樂**（使用者拍板）。這一行淡的是準備期那首。
	AudioBus.battle_hush(s.phase == "wave")
	# ★ 開打的號令。**邊緣觸發**（上一幀不是 wave、這一幀是）——
	#   照 `phase` 每幀播的話一波會播兩百次，而且它有 1.7 秒長。
	#   放在 `advanced` 判斷**之前**：提前召喚是玩家按鈕當幀就換 phase 的，
	#   等下一個 tick 才響會慢半拍，而這個音的全部價值就是「就是現在」。
	if s.phase == "wave" and String(_audio_prev.get("phase", "")) != "wave":
		AudioBus.play("wave_start")
	_audio_prev["phase"] = s.phase
	# 局結束就停掉生產的循環音。它是「東西正在跑」的聲音，而東西已經不跑了。
	AudioBus.flow(0.0 if over else clampf(float(s.rates["ore_in"]) / 30.0, 0.0, 1.0))

	# ★★ **一次性音效只在模擬真的往前走了一格時才判定。**
	#
	# 少了這一條會出兩件事，而且兩件都出過：
	#   ① 畫面 60fps、tick 10Hz → 同一發開火線會被連續 6 幀看到「ttl 還是滿的」，
	#      於是一發子彈播六次音。
	#   ② **局結束後 `BattleController.step()` 直接 return，`ttl` 從此不再遞減**
	#      → 最後那一 tick 的開火線永遠停在「剛剛才生出來」的狀態，
	#      音效就每一幀重放一次，聽起來像卡住了（使用者回報）。
	#
	# 用「差值偵測」的東西，就要確定自己是在**變化的那一刻**被呼叫的。
	if not advanced:
		return
	var now := float(s.tick_count) * BattleController.TICK

	# 開火：`ttl` 還是滿的就是這一 tick 才生出來的那幾發。
	# **一種塔一幀只出一個音**——五座錨同時開火時要聽到「一發」，
	# 不是五個同相位的正弦疊起來爆掉。
	var fired: Dictionary = {}
	for sh: Dictionary in s.shots:
		if int(sh["ttl"]) != BattleController.SHOT_TTL:
			continue
		var n: Dictionary = s.node_at(sh["from"])
		if not n.is_empty():
			fired[String(n["type"])] = true
	for type: String in fired:
		AudioBus.play("fire_%s" % type, -4.0)

	if s.kills > int(_audio_prev["kills"]):
		AudioBus.play("enemy_hit")
	# 節點變少＝被啃掉或被玩家拆掉。兩件事共用一個音是刻意的：
	# 玩家自己拆的那一次他知道自己在做什麼，不需要另一個音來告訴他。
	if s.nodes.size() < int(_audio_prev["nodes"]):
		AudioBus.play("build_destroyed", -2.0)
	# ★ 核心受擊與能量不足都要**節流**。核心每 tick 都在掉血，照實播就是
	#   每秒十次 0.9 秒的爆炸；警報響個不停等於沒有警報。
	if s.core_hp() < float(_audio_prev["core"]) - 0.01 and now - float(_audio_prev["core_at"]) >= 0.8:
		AudioBus.play("core_hit")
		_audio_prev["core_at"] = now
	var short: bool = float(s.rates["power_demand"]) > float(s.rates["power_supply"]) + 0.01
	if short and s.phase == "wave" and now - float(_audio_prev["warn_at"]) >= 4.0:
		AudioBus.play("warn_power", -5.0)
		_audio_prev["warn_at"] = now

	_audio_prev["kills"] = s.kills
	_audio_prev["nodes"] = s.nodes.size()
	_audio_prev["core"] = s.core_hp()
