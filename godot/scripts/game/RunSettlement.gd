extends RefCounted
## 局末結算（通關或核心歸零）：把一局的結果算出來，並寫進**傳入的存檔字典**。
## B3.14 自 `screens/Battle.gd` 的 `_refresh_over()` 抽出。
##
## 三個數字照 `10_GDD.md` §7.6 逐項攤開——**玩家要看得出研究數據是怎麼算出來的**，
## 一個總分教不會他下一局該改什麼。失敗不扣任何東西（紅線 R1）。
##
## **純函式、不引用 autoload、不做存檔 IO。** 只改 `save` 這個字典；
## 要不要寫進檔案是畫面的事（回傳的 `dirty` 告訴它有沒有改過）。
## 所以 headless 測試可以結算一整局而不碰玩家的真存檔，3D 畫面也不必重寫結算。

const BattleController := preload("res://scripts/game/BattleController.gd")
const Difficulty := preload("res://data/Difficulty.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Progress := preload("res://scripts/meta/Progress.gd")
const Score := preload("res://scripts/sim/Score.gd")


## `run`：同 `RunSetup.new_session()` 的 spec，外加 `daily_date`（每日局成績記在哪一天）。
##
## 回傳：
##   won, waves, score        基本成績（`waves` ＝ 撐過的波數）
##   data_total               研究數據合計（`Score.research_data`）
##   record                   只有無盡／每日有：`{prev_wave, prev_output, fresh_wave, fresh_output}`
##   stars, star_lines, gain  只有戰役有（`stars` 其餘為 −1）；`gain` ＝ 關卡獎勵的研究數據
##   comps, comps_total       升級材料：這局得到幾個、現有幾個（戰役與無盡才算）
##   dirty                    存檔字典有沒有被改過（畫面據此決定要不要寫檔）
static func settle(s: RefCounted, run: Dictionary, save: Dictionary) -> Dictionary:
	# ★ 局一結束 `BattleController.step()` 就直接 return，開火線與碎片的 `ttl`
	#   從此不再遞減——它們會**永遠停在畫面上**，看起來像每一座塔都卡在開火的
	#   那一幀（使用者回報「他們還在射擊」）。三者都是純渲染、不進 `state_hash()`，
	#   在結算時收乾淨。
	s.shots.clear()
	s.bursts.clear()
	s.shields.clear()
	var won: bool = s.phase == "won"
	var waves: int = s.wave_index if won else maxi(0, s.wave_index - 1)
	var score := Score.throughput(s.delivered_total, s.tick_count, BattleController.TICK)
	var level: Dictionary = run.get("level", {})
	var endless_seed: int = int(run.get("endless_seed", 0))
	var out := {
		"won": won, "waves": waves, "score": score,
		"data_total": Score.research_data(waves, score, s.bonus_data),
		"record": {}, "stars": -1, "star_lines": [] as Array[String], "gain": 0.0,
		"comps": 0, "comps_total": 0, "dirty": false,
	}

	# ★ 無盡的個人最佳（B2.1a、§7.10）。無盡沒有星，「破了幾項紀錄」就是它的成就感來源。
	if endless_seed != 0:
		var board: String = String(run.get("daily_board", ""))
		var difficulty: int = int(run.get("difficulty", 0))
		# ★ 每日挑戰記在自己那一格，不混進無盡的個人最佳（B2.2）：兩者的地圖
		#   來源一樣，但無盡是「隨便一張圖能撐多久」、每日是「今天這張圖」。
		#   混在一起會讓無盡的紀錄被一張特別好打的日圖洗掉。
		var daily: bool = board != ""
		# ★ 無盡的紀錄逐難度層各一筆（sv3、`data/Difficulty.gd`）：拿第 0 層的
		#   紀錄去比第 3 層的成績，「破紀錄」那三個字就會變成一句謊。
		var slot: Dictionary = (
			((save.get("daily", {}) as Dictionary).get("today", {}) as Dictionary).get(board, {})
			if daily else Difficulty.best(save, difficulty)
		)
		# ⚠ `slot` 是存檔字典裡那一格的**參照**，`apply_*` 會就地改它：
		#   「前次」必須在寫入**之前**讀出來，否則每一次都讀到剛寫進去的新值。
		var prev_wave := int(slot.get("wave", 0))
		var prev_output := float(slot.get("output", 0.0))
		var fresh: Dictionary = (
			Progress.apply_daily(save, String(run.get("daily_date", "")), board, waves, score)
			if daily else Progress.apply_endless(save, waves, score, difficulty)
		)
		out["record"] = {
			"prev_wave": prev_wave,
			"prev_output": prev_output,
			"fresh_wave": bool(fresh["wave"]),
			"fresh_output": bool(fresh["output"]),
		}
		out["dirty"] = true

	# ★ 星等與獎勵只在戰役關卡有（測試圖與沙盤沒有進度可寫）。
	if not level.is_empty():
		var stars := Score.stars(
			won, s.core_hp(), NodeDefs.hp("core"), score, float(level["star_throughput"])
		)
		out["stars"] = stars
		out["star_lines"] = star_lines(s, level, stars, score)
		out["gain"] = Progress.apply_result(
			save, String((level["map"] as Dictionary)["id"]), stars, int(level["reward"])
		)
		out["dirty"] = true

	# ★ 升級材料（B2.7、§7.15 的第一條路）。**只有戰役與無盡算**——
	#   測試圖與沙盤沒有進度可寫（星等與研究數據的同一條線）。
	#   只數波數：加星數加成的話，重刷第 1 關會比打完第 5 關划算。
	if not level.is_empty() or endless_seed != 0:
		var comps: int = Progress.apply_components(save, waves)
		out["comps"] = comps
		if comps > 0:
			out["comps_total"] = Progress.components(save)
			out["dirty"] = true
	return out


## 三顆星各自的達成與否，逐條講清楚——**沒拿到的那顆要說出差在哪**，
## 不然「兩顆星」只是一個沒有下一步的評分。
static func star_lines(s: RefCounted, level: Dictionary, stars: int, score: float) -> Array[String]:
	var threshold := float(level["star_throughput"])
	var out: Array[String] = [
		"%s 通關" % ("★" if stars >= 1 else "☆"),
		"%s 核心無損（%.0f/%.0f）" % [
			"★" if stars >= 2 else "☆", s.core_hp(), NodeDefs.hp("core")
		],
		"%s 產能積分 %.2f ／ 門檻 %.2f" % ["★" if stars >= 3 else "☆", score, threshold],
	]
	return out
