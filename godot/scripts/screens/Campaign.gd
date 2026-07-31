extends Control
## 戰役關卡選擇（`10_GDD.md` §6.2 畫面流、§7.9）。
##
## 一關一張卡，橫排五張。每張卡上有四件事，缺一不可：
##   ① 星等（拿到的與沒拿到的都畫出來——沒拿到的那幾顆才是回來的理由）
##   ② **這一關新解鎖什麼**，因為那就是它要教的機制（§7.9 難度階梯）
##   ③ 一句話講它考什麼
##   ④ 鎖住時**說清楚要先過哪一關**，不是一個沒有下文的灰色方塊

const CampaignData := preload("res://data/Campaign.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const BattleScreen := preload("res://scripts/screens/Battle.gd")
const TechScreen := preload("res://scripts/screens/Tech.gd")

## 卡片寬度。五張 ＋ 四道間距要放進 1280 的設計基準。
const CARD := Vector2(228, 300)


## 回上一層（標題）。由呼叫端指派；沒指派就不畫返回鈕。
var on_exit: Callable = Callable()

## 卡片上那顆「出擊」鈕，供自檢按（與關卡序同索引）。
var _enter_buttons: Array[Button] = []


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	if Hooks.click_test and Hooks.level <= 0:
		_click_selftest.call_deferred()


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=campaign`）。
##
## 這個畫面的全部價值就是**一顆鈕點得到**，而 B0.7.2 教過的事情是：
## 畫得出來不代表點得到（滿版 `Control` 的 `mouse_filter` 會把事件吃掉）。
## 用合成滑鼠事件真的走一次 Godot 的輸入路由，不是直接呼叫 `_enter()`。
func _click_selftest() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var five: bool = _enter_buttons.size() == CampaignData.count()
	var first_open: bool = five and not _enter_buttons[0].disabled
	# 新存檔：第 2 關必須是鎖著的，而且鈕上要寫出解鎖條件。
	var second_locked: bool = five and _enter_buttons[1].disabled
	var says_why: bool = five and _enter_buttons[1].text.contains("第 1 關")

	var b: Button = _enter_buttons[0]
	var at := b.global_position + b.size * 0.5
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		Input.parse_input_event(ev)
	for _i in 4:
		await get_tree().process_frame
	# 真的進了局內畫面嗎？（卡片被清掉、Battle 掛上來了）
	var entered: bool = false
	for c: Node in get_children():
		if c.get_script() == BattleScreen:
			entered = true
	var ok: bool = five and first_open and second_locked and says_why and entered
	print("[TL_CLICKTEST/campaign] cards=%s first_open=%s second_locked=%s says_why=%s entered=%s → %s" % [
		five, first_open, second_locked, says_why, entered, "PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		get_tree().quit(0 if ok else 1)


## `queue_free()` 要到影格末才生效，中間那一幀舊畫面還在畫——
## 先 `remove_child()` 讓它當場離開樹，關卡選擇才不會疊在戰場上。
func _clear() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()


func _build() -> void:
	_clear()

	var col := UiKit.vbox(14)
	col.position = Vector2(24, 40)
	add_child(col)
	col.add_child(UiKit.label("戰役", 34, Palette.ORDER_BRIGHT, false))
	col.add_child(UiKit.label(
		"每一關解鎖一種新的建造選項——那一顆鈕就是它要教的東西。", 15,
		Palette.TEXT_SECONDARY, false
	))
	var data := int(float((GameState.data.get("tech", {}) as Dictionary).get("data", 0)))
	col.add_child(UiKit.label(
		"研究數據 %s" % UiKit.commas(data), 15, Palette.ENERGY_AMBER, false
	))
	var back_row := UiKit.hbox(8)
	col.add_child(back_row)
	if on_exit.is_valid():
		var back := Button.new()
		back.text = "返回標題"
		back.pressed.connect(on_exit)
		back_row.add_child(UiKit.touchable(back))
	# ★ 研究數據是在這個畫面上賺到的，花掉它的地方就該在同一個畫面上到得了（B1.3）。
	var tech := Button.new()
	tech.text = "科技樹"
	tech.pressed.connect(_enter_tech)
	back_row.add_child(UiKit.touchable(tech))

	var row := UiKit.hbox(12)
	col.add_child(row)
	_enter_buttons.clear()
	for i in CampaignData.count():
		row.add_child(_card(i))


## 這一關解鎖了嗎？第 1 關永遠開著，之後要前一關通關（≥1 星，§7.9）。
func _unlocked(index: int) -> bool:
	if index <= 0:
		return true
	# 「通關」＝上一關至少 1 星（sv2 起沒有另一份 `cleared` 清單，§7.9）。
	return _stars(index - 1) >= 1


func _stars(index: int) -> int:
	var best: Dictionary = (GameState.data.get("campaign", {}) as Dictionary).get("stars", {})
	return int(best.get(CampaignData.id_at(index), 0))


func _card(index: int) -> Control:
	var lv: Dictionary = CampaignData.at(index)
	var m: Dictionary = lv["map"]
	var open := _unlocked(index)
	var stars := _stars(index)

	var box := UiKit.panel()
	box.custom_minimum_size = CARD
	box.mouse_filter = Control.MOUSE_FILTER_PASS   # 卡片裡有按鈕，不能整張不吃滑鼠
	# 鎖住的卡整張變暗。**只暗標題會看起來像壞掉**，而不是像「還沒到」。
	# 內容仍然讀得到：它是路線圖，先看見後面有什麼才知道要往哪走。
	if not open:
		box.modulate = Color(1, 1, 1, 0.5)
	var col := UiKit.vbox(6)
	box.add_child(col)

	col.add_child(UiKit.label(
		"第 %d 關　%s" % [index + 1, m["name"]], 20,
		Palette.TEXT_PRIMARY if open else Palette.TEXT_DISABLED, false
	))
	col.add_child(UiKit.label(
		"★★★".substr(0, stars) + "☆☆☆".substr(0, 3 - stars), 20,
		Palette.ENERGY_AMBER if stars > 0 else Palette.TEXT_DISABLED, false
	))

	var lesson := UiKit.label(String(lv["lesson"]), 13, Palette.TEXT_SECONDARY, false)
	lesson.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lesson.custom_minimum_size = Vector2(CARD.x - 24, 0)
	col.add_child(lesson)

	col.add_child(UiKit.label("新解鎖　%s" % _new_unlocks(index), 13, Palette.ORDER_CYAN, false))
	col.add_child(UiKit.label(
		"%d 波　橋 %d 座　準備期 %d 秒" % [
			(m["waves"] as Array).size(), (m["crossings"] as Array).size(),
			int(m["prep_time"])
		], 13, Palette.TEXT_SECONDARY, false
	))
	col.add_child(UiKit.label(
		"獎勵　每顆星 %d 研究數據" % int(lv["reward"]), 13, Palette.TEXT_SECONDARY, false
	))

	var b := Button.new()
	if open:
		b.text = "出擊"
		b.pressed.connect(_enter.bind(index))
	else:
		# 鎖住要說清楚條件。一個沒有下文的灰色方塊會讓玩家以為是壞掉了。
		b.text = "先通過第 %d 關" % index
		b.disabled = true
	_enter_buttons.append(b)
	col.add_child(UiKit.touchable(b))
	return box


## 這一關比上一關多出來的建造選項。第 1 關列它自己全部的。
func _new_unlocks(index: int) -> String:
	var now: Array = (CampaignData.at(index) as Dictionary)["unlocked"]
	var prev: Array = [] if index <= 0 else (CampaignData.at(index - 1) as Dictionary)["unlocked"]
	var names: Array[String] = []
	for type: String in now:
		if not prev.has(type):
			names.append(NodeDefs.label(type))
	return "・".join(names)


func _enter_tech() -> void:
	_clear()
	var screen := TechScreen.new()
	screen.on_exit = _build
	add_child(screen)


func _enter(index: int) -> void:
	_clear()
	var battle := BattleScreen.new()
	# ★ 指派要在 `add_child()` **之前**——`_ready()` 一進來就會讀 `level`。
	battle.level = CampaignData.at(index)
	battle.on_exit = _build
	add_child(battle)
