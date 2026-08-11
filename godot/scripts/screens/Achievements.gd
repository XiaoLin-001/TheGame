extends Control
## 成就與公司等級（`10_GDD.md` §3.9、§7.15；B2.7）。
##
## 這個畫面**沒有任何一顆「領取」鈕**，而那是它最重要的性質：成就是推導的
## （`data/Achievements.gd` 的說明），達成的當下獎勵就已經在餘額裡了。
## 一顆會忘記按的領取鈕只會製造「我明明達成了卻沒拿到」的客訴。
##
## 所以這個畫面要回答的問題只有兩個：
##   ① **我現在到哪了**（公司等級 ＋ 進度條 ＋ 已達成幾條）
##   ② **下一條差多少**（每一列都寫「現在／門檻」，不寫「未達成」）

const Achievements := preload("res://data/Achievements.gd")
const RosterData := preload("res://data/Roster.gd")
const CampaignData := preload("res://data/Campaign.gd")

const CARD_W := 380.0


## 回上一層。由呼叫端指派。
var on_exit: Callable = Callable()

var _rows: Array[Control] = []
var _scroll: ScrollContainer = null


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	if Hooks.click_test and Hooks.panel == "achievements":
		_click_selftest.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	UiKit.esc_returns(self, event, on_exit)


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=achievements`）。
##
## 這個畫面沒有鈕可按（返回那一顆除外），所以自檢驗的是**資料真的長在畫面上**：
##   · 20 列全部建出來（`Achievements.count()`，不是寫死的 20）
##   · 零進度時已達成 0 條、公司等級 1
##   · 塞一筆進度進去（**不寫檔**）之後那一列真的變成已達成，而且材料餘額跟著動
##   · 捲到底之後**最後一列整條在畫面內**（RG-47／RG-60 的同一課）
func _click_selftest() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var all_rows: bool = _rows.size() == Achievements.count()
	var virgin: bool = (
		Achievements.done(GameState.data).is_empty()
		and Achievements.company_level(GameState.data) == 1
	)

	# 「初次通關」＝ 通關 1 關。給第 1 關 1 顆星。
	var before := SaveService.components(GameState.data)
	((GameState.data["campaign"] as Dictionary)["stars"] as Dictionary)[CampaignData.id_at(0)] = 1
	_build()
	await get_tree().process_frame
	var got: Array[String] = Achievements.done(GameState.data)
	var earned: bool = got.has("clear1")
	# ★ **達成的當下獎勵就在餘額裡**——沒有領取鈕，所以這一條就是那句話的斷言。
	var paid: bool = SaveService.components(GameState.data) == before + 20
	var level_up: bool = Achievements.company_level(GameState.data) >= 1

	_scroll.scroll_vertical = 999999
	await get_tree().process_frame
	var last: Control = _rows[_rows.size() - 1]
	var reachable: bool = (
		last.global_position.y >= 0.0
		and last.global_position.y + last.size.y <= float(size.y)
	)

	var esc_back: bool = await UiKit.esc_reaches(self)

	var ok: bool = (
		all_rows and virgin and earned and paid and level_up and reachable and esc_back
	)
	print("[TL_CLICKTEST/achievements] rows=%s(%d) virgin=%s earned=%s paid=%s company=%s last_reachable=%s esc_back=%s → %s" % [
		all_rows, _rows.size(), virgin, earned, paid, level_up, reachable, esc_back,
		"PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		get_tree().quit(0 if ok else 1)


func _build() -> void:
	UiKit.clear(self)
	_rows.clear()

	var col := UiKit.screen(self, 10)

	var save: Dictionary = GameState.data
	var done := Achievements.done(save)
	var progress := Achievements.company_progress(save)

	col.add_child(UiKit.label(
		"公司等級 %d" % Achievements.company_level(save), 32, Palette.ORDER_BRIGHT, false
	))
	# ★ 一行就好。原本這裡另外寫了「它只是一個彙總、不另外發獎勵」——
	#   那是在回答一個玩家還沒問的問題，而且讀起來像在替自己的設計辩護。
	col.add_child(UiKit.label(
		"塔防與潮汐公司的進度都會推它。離下一級 %d／%d 點。"
		% [progress[0], progress[1]],
		14, Palette.TEXT_SECONDARY, false
	))
	col.add_child(UiKit.label(
		"成就 %d／%d　　升級材料 %s　　聲望券 %d" % [
			done.size(), Achievements.count(),
			UiKit.commas(SaveService.components(save)), RosterData.tokens(save)
		], 16, Palette.ENERGY_AMBER, false
	))
	col.add_child(UiKit.label(
		"達成的當下就入帳，沒有領取鈕。",
		13, Palette.TEXT_SECONDARY, false
	))

	var nav := UiKit.back_row("返回", on_exit)
	if nav != null:
		col.add_child(nav)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)

	# 兩欄。20 條排成一直行要捲三次才看得完，而「我還差哪幾條」是一個要一眼掃的問題。
	var cols := UiKit.hbox(16)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(cols)
	var left := UiKit.vbox(8)
	var right := UiKit.vbox(8)
	cols.add_child(left)
	cols.add_child(right)

	var metrics := Achievements.metrics(save)
	# `rows()` 而不是 `LIST`：門檻與文案有兩條是由關卡數推導的（B3.3）。
	var defs := Achievements.rows()
	for i in defs.size():
		var row := _row(defs[i] as Dictionary, done, metrics)
		_rows.append(row)
		(left if i < (defs.size() + 1) / 2 else right).add_child(row)


func _row(a: Dictionary, done: Array[String], metrics: Dictionary) -> Control:
	var got: bool = done.has(String(a["id"]))
	var have := int(metrics.get(String(a["metric"]), 0))
	var need := int(a["need"])

	var box := UiKit.panel()
	box.custom_minimum_size = Vector2(CARD_W, 0)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var col := UiKit.vbox(2)
	box.add_child(col)

	col.add_child(UiKit.label(
		"%s%s" % ["✔ " if got else "", String(a["name"])], 16,
		Palette.OK_GREEN if got else Palette.TEXT_PRIMARY, false
	))
	# ★ **寫「現在／門檻」，不寫「未達成」**：後者說不出「我還差多少」，
	#   而那正是一張成就清單唯一有用的資訊。
	var reward := "＋%d 材料" % int(a["component"])
	if int(a["token"]) > 0:
		reward += "・＋%d 聲望券" % int(a["token"])
	var line := UiKit.label(
		"%s　%s　%d／%d" % [String(a["desc"]), reward, mini(have, need), need],
		13, Palette.TEXT_SECONDARY if got else Palette.TEXT_DISABLED, false
	)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(CARD_W - 24, 0)
	col.add_child(line)
	return box
