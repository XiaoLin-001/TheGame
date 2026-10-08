class_name BattleResult
extends RefCounted
## 局末結算面板。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

const Daily := preload("res://scripts/sim/Daily.gd")
const Difficulty := preload("res://data/Difficulty.gd")
const RunSettlement := preload("res://scripts/game/RunSettlement.gd")
const Score := preload("res://scripts/sim/Score.gd")

var over_panel: Control = null

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


## 局末結算（通關或核心歸零）。三個數字照 `10_GDD.md` §7.6 逐項攤開——
## **玩家要看得出研究數據是怎麼算出來的**，一個總分教不會他下一局該改什麼。
## **重來按鈕必須在 1 次點擊之內**（`50_QA_PLAN.md` §4.4），
## 而且失敗不扣任何東西（紅線 R1）——局內狀態本來就不持久化。
func refresh_over() -> void:
	if battle.bars.ff_button != null:
		battle.bars.ff_button.disabled = battle.s.phase != "prep"
	if battle.s.phase != "lost" and battle.s.phase != "won":
		if over_panel != null:
			over_panel.queue_free()
			over_panel = null
		return
	if over_panel != null:
		return
	# 算數字與改存檔字典在核心層的 `RunSettlement`（headless 也能結算一整局）；
	# 這裡只負責擺面板與寫檔。
	var res := RunSettlement.settle(battle.s, battle.run_spec(), GameState.data)
	if bool(res["dirty"]):
		SaveService.save_from(GameState.data)
	var won: bool = res["won"]
	var waves: int = res["waves"]
	var score: float = res["score"]
	var box := UiKit.panel()
	box.position = Vector2(440, 230)
	var col := UiKit.vbox(10)
	box.add_child(col)
	col.add_child(UiKit.label(
		"通關" if won else "核心已毀", 32, Palette.OK_GREEN if won else Palette.TIDE_MAGENTA
	))
	# ★ 無盡的個人最佳（B2.1a、§7.10）。放在星等的位置——無盡沒有星，
	#   「破了幾項紀錄」就是它的成就感來源。兩欄各自比對（`apply_endless`）。
	var record: Dictionary = res["record"]
	if not record.is_empty():
		var daily: bool = battle.daily_board != ""
		if daily:
			col.add_child(UiKit.label(
				"每日挑戰　%s　%s" % [
					battle.daily_date, "統一配置" if battle.daily_board == Daily.UNIFORM else "自由配置"
				], 13, Palette.ORDER_CYAN, false
			))
		elif battle.difficulty > 0:
			# 紀錄記在哪一層要說出來，否則「最高波次 8 波」看起來像退步。
			col.add_child(UiKit.label(
				"無盡　%s" % Difficulty.name_of(battle.difficulty), 13, Palette.WARN_ORANGE, false
			))
		for line: Array in [
			["最高波次　%d 波" % waves, bool(record["fresh_wave"]), "前次 %d 波" % int(record["prev_wave"])],
			["最佳產能　%.1f" % score, bool(record["fresh_output"]), "前次 %.1f" % float(record["prev_output"])],
		]:
			col.add_child(UiKit.label(
				"%s　%s" % [line[0], "★ 新紀錄" if line[1] else line[2]],
				15, Palette.ENERGY_AMBER if line[1] else Palette.TEXT_SECONDARY, false
			))
	# ★ 星等與獎勵只在戰役關卡有（測試圖與沙盤沒有進度可寫）。
	var stars: int = res["stars"]
	if stars >= 0:
		col.add_child(UiKit.label(
			"★★★".substr(0, stars) + "☆☆☆".substr(0, 3 - stars), 32, Palette.ENERGY_AMBER
		))
		for line: String in res["star_lines"]:
			col.add_child(UiKit.label(line, 13, Palette.TEXT_SECONDARY, false))
		if float(res["gain"]) > 0.0:
			col.add_child(UiKit.label(
				"關卡獎勵　＋%.0f 研究數據" % float(res["gain"]), 13, Palette.OK_GREEN, false
			))
	# ★ 升級材料（B2.7、§7.15 的第一條路）。
	if int(res["comps"]) > 0:
		col.add_child(UiKit.label(
			"升級材料　＋%d（撐過的波數）　現有 %d" % [int(res["comps"]), int(res["comps_total"])],
			13, Palette.OK_GREEN, false
		))
	for line: String in [
		"撐過 %d 波　　＋%.0f 研究數據" % [waves, Score.DATA_PER_WAVE * float(waves)],
		"產能積分 %.1f（送達核心 %s 礦砂）　＋%.0f" % [
			score, UiKit.commas(int(battle.s.delivered_total)), Score.DATA_PER_SCORE * score
		],
		"提前召喚累計加成　　＋%.0f" % battle.s.bonus_data,
		"研究數據合計 %.0f　　擊殺 %d" % [float(res["data_total"]), battle.s.kills],
		"失敗不扣任何東西" if not won else "",
	]:
		if line != "":
			col.add_child(UiKit.label(line, 13, Palette.TEXT_SECONDARY, false))
	# ★ 死因歸因（B1.7）。M1 的驗收句子是「說得出自己為什麼輸」——
	#   上面那幾行是**成績**，這一行才是**原因**。放在按鈕正上方：
	#   玩家的視線在按「立刻重來」之前一定會經過這裡。
	var why := battle.diag.line(won)
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
	again.pressed.connect(battle.restart)
	buttons.add_child(UiKit.touchable(again))
	if battle.on_exit.is_valid():
		var back := Button.new()
		back.text = "回關卡選擇"
		back.pressed.connect(battle.on_exit)
		buttons.add_child(UiKit.touchable(back))
	# 面板本身不吃滑鼠（`UiKit.panel` 的 RG-39），但**這兩顆鈕要點得到**。
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	battle.add_child(box)
	over_panel = box

