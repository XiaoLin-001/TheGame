class_name BattleAudioCues
extends RefCounted
## 音訊提示：從狀態的逐幀差值推導音效，模擬層維持零副作用。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

const BattleController := preload("res://scripts/game/BattleController.gd")

## ★ 音訊（B1.5）。上一幀的幾個數字，用來推導「這一幀發生了什麼」。
## **音效一律從畫面層推導，模擬層維持零副作用**（`CLAUDE.md` 技術慣例）：
## 在 `scripts/sim/` 裡塞一行 `AudioBus.play()` 就等於讓每日挑戰的重播會出聲。
var _audio_prev: Dictionary = {}

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


func audio_reset() -> void:
	_audio_prev = {
		"kills": battle.s.kills, "nodes": battle.s.nodes.size(), "core": battle.s.core_hp(),
		"warn_at": -99.0, "core_at": -99.0, "phase": battle.s.phase,
	}
	battle.last_tick = battle.s.tick_count
	battle.diag.reset(battle.s)


## 這一幀發生了什麼？全部從狀態的差值推出來——**不在模擬層留任何一個
## 「順便播個音」的呼叫**。代價是要自己記上一幀，換到的是 `sim/` 仍然
## 可以在 headless 重播一萬次而不出聲。
func audio_tick(advanced: bool) -> void:
	if _audio_prev.is_empty():
		return
	var over: bool = battle.s.phase == "won" or battle.s.phase == "lost"
	# ★ B2.1f：戰鬥期**完全沒有音樂**（使用者拍板）。這一行淡的是準備期那首。
	AudioBus.battle_hush(battle.s.phase == "wave")
	# ★ 開打的號令。**邊緣觸發**（上一幀不是 wave、這一幀是）——
	#   照 `phase` 每幀播的話一波會播兩百次，而且它有 1.7 秒長。
	#   放在 `advanced` 判斷**之前**：提前召喚是玩家按鈕當幀就換 phase 的，
	#   等下一個 tick 才響會慢半拍，而這個音的全部價值就是「就是現在」。
	if battle.s.phase == "wave" and String(_audio_prev.get("phase", "")) != "wave":
		AudioBus.play("wave_start")
	_audio_prev["phase"] = battle.s.phase
	# 局結束就停掉生產的循環音。它是「東西正在跑」的聲音，而東西已經不跑了。
	AudioBus.flow(0.0 if over else clampf(float(battle.s.rates["ore_in"]) / 30.0, 0.0, 1.0))

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
	var now := float(battle.s.tick_count) * BattleController.TICK

	# 開火：`ttl` 還是滿的就是這一 tick 才生出來的那幾發。
	# **一種塔一幀只出一個音**——五座錨同時開火時要聽到「一發」，
	# 不是五個同相位的正弦疊起來爆掉。
	var fired: Dictionary = {}
	for sh: Dictionary in battle.s.shots:
		if int(sh["ttl"]) != BattleController.SHOT_TTL:
			continue
		var n: Dictionary = battle.s.node_at(sh["from"])
		if not n.is_empty():
			fired[String(n["type"])] = true
	for type: String in fired:
		AudioBus.play("fire_%s" % type, -4.0)

	if battle.s.kills > int(_audio_prev["kills"]):
		AudioBus.play("enemy_hit")
	# 節點變少＝被啃掉或被玩家拆掉。兩件事共用一個音是刻意的：
	# 玩家自己拆的那一次他知道自己在做什麼，不需要另一個音來告訴他。
	if battle.s.nodes.size() < int(_audio_prev["nodes"]):
		AudioBus.play("build_destroyed", -2.0)
	# ★ 核心受擊與能量不足都要**節流**。核心每 tick 都在掉血，照實播就是
	#   每秒十次 0.9 秒的爆炸；警報響個不停等於沒有警報。
	if battle.s.core_hp() < float(_audio_prev["core"]) - 0.01 and now - float(_audio_prev["core_at"]) >= 0.8:
		AudioBus.play("core_hit")
		_audio_prev["core_at"] = now
	var short: bool = float(battle.s.rates["power_demand"]) > float(battle.s.rates["power_supply"]) + 0.01
	if short and battle.s.phase == "wave" and now - float(_audio_prev["warn_at"]) >= 4.0:
		AudioBus.play("warn_power", -5.0)
		_audio_prev["warn_at"] = now

	_audio_prev["kills"] = battle.s.kills
	_audio_prev["nodes"] = battle.s.nodes.size()
	_audio_prev["core"] = battle.s.core_hp()
