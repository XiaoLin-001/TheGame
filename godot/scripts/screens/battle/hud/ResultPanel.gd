extends Node
## 局末結算面板：勝負、星等、產能積分、研究數據，以及一句話的死因（`Feedback.diag_line()`）。
##
## **重來按鈕必須在 1 次點擊之內**（`50_QA_PLAN.md` §4.4）。結算在這裡寫存檔（星等、獎勵、研究數據）。

const Feedback := preload("res://scripts/screens/battle/Feedback.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Score := preload("res://scripts/sim/Score.gd")
const Daily := preload("res://scripts/sim/Daily.gd")
const Difficulty := preload("res://data/Difficulty.gd")
const TopBar := preload("res://scripts/screens/battle/hud/TopBar.gd")

## 擁有這個模組的局內畫面（`screens/Battle.gd`）。由它在建立時指派。
var scr: Control = null
## 同伴模組（Feedback）。
var feedback: Feedback = null
## 局的狀態（與 `scr.s` 同一個物件；換局時由畫面重新指派）。
var s: RefCounted = null
## 同伴模組。
var topbar: TopBar = null


var over_panel: Control = null


## 局末結算（通關或核心歸零）。三個數字照 `10_GDD.md` §7.6 逐項攤開——
## **玩家要看得出研究數據是怎麼算出來的**，一個總分教不會他下一局該改什麼。
## **重來按鈕必須在 1 次點擊之內**（`50_QA_PLAN.md` §4.4），
## 而且失敗不扣任何東西（紅線 R1）——局內狀態本來就不持久化。
func refresh_over() -> void:
	if topbar.ff_button != null:
		topbar.ff_button.disabled = s.phase != "prep"
	if s.phase != "lost" and s.phase != "won":
		if over_panel != null:
			over_panel.queue_free()
			over_panel = null
		return
	if over_panel != null:
		return
	# ★ 局一結束 `BattleController.step()` 就直接 return，開火線與碎片的 `ttl`
	#   從此不再遞減——它們會**永遠停在畫面上**，看起來像每一座塔都卡在開火的
	#   那一幀（使用者回報「他們還在射擊」）。兩者都是純渲染、不進 `state_hash()`，
	#   由畫面層在這裡收乾淨。
	s.shots.clear()
	s.bursts.clear()
	s.shields.clear()
	var won: bool = s.phase == "won"
	var waves: int = s.wave_index if won else maxi(0, s.wave_index - 1)
	var score := Score.throughput(s.delivered_total, s.tick_count, BattleController.TICK)
	var box := UiKit.panel()
	box.position = Vector2(440, 230)
	var col := UiKit.vbox(10)
	box.add_child(col)
	col.add_child(UiKit.label(
		"通關" if won else "核心已毀", 32, Palette.OK_GREEN if won else Palette.TIDE_MAGENTA
	))
	# ★ 無盡的個人最佳（B2.1a、§7.10）。放在星等的位置——無盡沒有星，
	#   「破了幾項紀錄」就是它的成就感來源。兩欄各自比對（`apply_endless`）。
	if scr.endless_seed != 0:
		# ★ 每日挑戰記在自己那一格，不混進無盡的個人最佳（B2.2）：兩者的地圖
		#   來源一樣，但無盡是「隨便一張圖能撐多久」、每日是「今天這張圖」。
		#   混在一起會讓無盡的紀錄被一張特別好打的日圖洗掉。
		var daily: bool = scr.daily_board != ""
		# ★ 無盡的紀錄逐難度層各一筆（sv3、`data/Difficulty.gd`）：拿第 0 層的
		#   紀錄去比第 3 層的成績，「破紀錄」那三個字就會變成一句謊。
		var slot: Dictionary = (
			((GameState.data.get("daily", {}) as Dictionary).get("today", {}) as Dictionary)
				.get(scr.daily_board, {})
			if daily else Difficulty.best(GameState.data, scr.difficulty)
		)
		var prev_wave := int(slot.get("wave", 0))
		var prev_output := float(slot.get("output", 0.0))
		var fresh := (
			SaveService.apply_daily(GameState.data, scr.daily_date, scr.daily_board, waves, score)
			if daily else SaveService.apply_endless(GameState.data, waves, score, scr.difficulty)
		)
		SaveService.save_from(GameState.data)
		if daily:
			col.add_child(UiKit.label(
				"每日挑戰　%s　%s" % [
					scr.daily_date, "統一配置" if scr.daily_board == Daily.UNIFORM else "自由配置"
				], 13, Palette.ORDER_CYAN, false
			))
		elif scr.difficulty > 0:
			# 紀錄記在哪一層要說出來，否則「最高波次 8 波」看起來像退步。
			col.add_child(UiKit.label(
				"無盡　%s" % Difficulty.name_of(scr.difficulty), 13, Palette.WARN_ORANGE, false
			))
		for line: Array in [
			["最高波次　%d 波" % waves, bool(fresh["wave"]), "前次 %d 波" % prev_wave],
			["最佳產能　%.1f" % score, bool(fresh["output"]), "前次 %.1f" % prev_output],
		]:
			col.add_child(UiKit.label(
				"%s　%s" % [line[0], "★ 新紀錄" if line[1] else line[2]],
				15, Palette.ENERGY_AMBER if line[1] else Palette.TEXT_SECONDARY, false
			))
	# ★ 星等與獎勵只在戰役關卡有（測試圖與沙盤沒有進度可寫）。
	if not scr.level.is_empty():
		var stars := Score.stars(
			won, s.core_hp(), NodeDefs.hp("core"), score, float(scr.level["star_throughput"])
		)
		var gain := SaveService.apply_result(
			GameState.data, String((scr.level["map"] as Dictionary)["id"]),
			stars, int(scr.level["reward"])
		)
		SaveService.save_from(GameState.data)
		col.add_child(UiKit.label(
			"★★★".substr(0, stars) + "☆☆☆".substr(0, 3 - stars), 32, Palette.ENERGY_AMBER
		))
		for line: String in _star_lines(stars, score):
			col.add_child(UiKit.label(line, 13, Palette.TEXT_SECONDARY, false))
		if gain > 0.0:
			col.add_child(UiKit.label(
				"關卡獎勵　＋%.0f 研究數據" % gain, 13, Palette.OK_GREEN, false
			))
	# ★ 升級材料（B2.7、§7.15 的第一條路）。**只有戰役與無盡算**——
	#   測試圖與沙盤沒有進度可寫（星等與研究數據的同一條線）。
	#   只數波數：加星數加成的話，重刷第 1 關會比打完第 5 關划算。
	var comps := 0
	if not scr.level.is_empty() or scr.endless_seed != 0:
		comps = SaveService.apply_components(GameState.data, waves)
		if comps > 0:
			SaveService.save_from(GameState.data)
			col.add_child(UiKit.label(
				"升級材料　＋%d（撐過的波數）　現有 %d" % [
					comps, SaveService.components(GameState.data)
				], 13, Palette.OK_GREEN, false
			))
	for line: String in [
		"撐過 %d 波　　＋%.0f 研究數據" % [waves, Score.DATA_PER_WAVE * float(waves)],
		"產能積分 %.1f（送達核心 %s 礦砂）　＋%.0f" % [
			score, UiKit.commas(int(s.delivered_total)), Score.DATA_PER_SCORE * score
		],
		"提前召喚累計加成　　＋%.0f" % s.bonus_data,
		"研究數據合計 %.0f　　擊殺 %d" % [
			Score.research_data(waves, score, s.bonus_data), s.kills
		],
		"失敗不扣任何東西" if not won else "",
	]:
		if line != "":
			col.add_child(UiKit.label(line, 13, Palette.TEXT_SECONDARY, false))
	# ★ 死因歸因（B1.7）。M1 的驗收句子是「說得出自己為什麼輸」——
	#   上面那幾行是**成績**，這一行才是**原因**。放在按鈕正上方：
	#   玩家的視線在按「立刻重來」之前一定會經過這裡。
	var why: String = feedback.diag_line(won)
	if why != "":
		var lbl := UiKit.label(
			why, 13, Palette.WARN_ORANGE if not won else Palette.ORDER_CYAN, false
		)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size.x = 400.0
		col.add_child(lbl)
	var buttons := UiKit.hbox(8)
	col.add_child(buttons)
	var again := Button.new()
	again.text = "立刻重來"
	again.pressed.connect(scr.restart)
	buttons.add_child(UiKit.touchable(again))
	if scr.on_exit.is_valid():
		var back := Button.new()
		back.text = "回關卡選擇"
		back.pressed.connect(scr.on_exit)
		buttons.add_child(UiKit.touchable(back))
	# 面板本身不吃滑鼠（`UiKit.panel` 的 RG-39），但**這兩顆鈕要點得到**。
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	scr.add_child(box)
	over_panel = box


## 三顆星各自的達成與否，逐條講清楚——**沒拿到的那顆要說出差在哪**，
## 不然「兩顆星」只是一個沒有下一步的評分。
func _star_lines(stars: int, score: float) -> Array[String]:
	var threshold := float(scr.level["star_throughput"])
	var out: Array[String] = [
		"%s 通關" % ("★" if stars >= 1 else "☆"),
		"%s 核心無損（%.0f/%.0f）" % [
			"★" if stars >= 2 else "☆", s.core_hp(), NodeDefs.hp("core")
		],
		"%s 產能積分 %.2f ／ 門檻 %.2f" % ["★" if stars >= 3 else "☆", score, threshold],
	]
	return out
