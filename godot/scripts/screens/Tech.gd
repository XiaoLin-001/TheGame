extends Control
## 科技樹（`10_GDD.md` §3.6、§7.8）。M1 首批 12 節點，三支路線各一欄。
##
## 這個畫面要回答的問題只有兩個，所以版面就只長成這兩個問題的形狀：
##   ① **我現在有多少研究數據、這一個要花多少？**（每張卡上就有價，不必心算）
##   ② **買了會怎樣？**（效果寫成局內看得到的數字，例如「10 → 12」，
##      不是「+2 吞吐」這種要玩家自己去找基準值的說法）
##
## 已解鎖的節點**留在畫面上並標成已解鎖**，不隱藏——科技樹同時是路線圖。

const Tech := preload("res://data/Tech.gd")

const CARD := Vector2(300, 116)


## 回上一層。由呼叫端指派。
var on_exit: Callable = Callable()

## 供自檢按的解鎖鈕，與 `Tech.NODES` 同索引。
var _buttons: Array[Button] = []
var _data_label: Label = null
var _scroll: ScrollContainer = null


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	if Hooks.click_test:
		_click_selftest.call_deferred()


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=tech`）。
##
## 和關卡選擇同一個理由：這個畫面的全部價值就是「一顆鈕點得到、而且真的扣款」。
## 存檔在有鉤子時是預設值（研究數據 0），所以先塞一筆數據進去再點——
## **不寫檔**（`SaveService.persist=false`），玩家的真實進度碰不到。
func _click_selftest() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var twelve: bool = _buttons.size() == Tech.count()
	# 新存檔：研究數據 0 → 每一顆都買不起；第二階還要前置。
	var all_broke: bool = twelve and _buttons[0].disabled

	var tech: Dictionary = GameState.data["tech"]
	tech["data"] = 500.0
	_build()
	await get_tree().process_frame
	var first_open: bool = _buttons[0].text.contains("解鎖")and not _buttons[0].disabled
	# 第二階（cap2）在第一階還沒買之前必須是鎖著的，而且要說出原因。
	var tier2_locked: bool = _buttons[1].disabled and _buttons[1].text.contains("導管擴容 I")

	var b: Button = _buttons[0]
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
	var unlocked: Array = tech["unlocked"]
	var bought: bool = unlocked.has("cap1")
	var charged: bool = is_equal_approx(float(tech["data"]), 500.0 - float(Tech.cost("cap1")))
	# 買完第一階，第二階就該開了——路線圖要當場往前走一格。
	var tier2_open: bool = not _buttons[1].disabled

	# ★ **最後一顆鈕到得了嗎**（RG-47／RG-60）。捲到底之後它必須整顆在畫面內——
	#   第一版沒有捲動容器，最長那一支的第 5 張卡直接被推到 720 以外，
	#   而畫面上看起來只是「這一欄比較短」。
	_scroll.scroll_vertical = 999999
	await get_tree().process_frame
	var last: Button = _buttons[_buttons.size() - 1]
	var reachable: bool = (
		last.size.y >= 44.0
		and last.global_position.y + last.size.y <= float(size.y)
		and last.global_position.y >= 0.0
	)

	var ok: bool = (
		twelve and all_broke and first_open and tier2_locked
		and bought and charged and tier2_open and reachable
	)
	print("[TL_CLICKTEST/tech] twelve=%s broke=%s first_open=%s tier2_locked=%s bought=%s charged=%s tier2_open=%s last_reachable=%s → %s" % [
		twelve, all_broke, first_open, tier2_locked, bought, charged, tier2_open, reachable,
		"PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		get_tree().quit(0 if ok else 1)


func _clear() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()


func _data() -> float:
	return float((GameState.data.get("tech", {}) as Dictionary).get("data", 0))


func _unlocked() -> Array:
	return (GameState.data.get("tech", {}) as Dictionary).get("unlocked", [])


func _build() -> void:
	_clear()
	_buttons.clear()

	# ★ 走容器與錨點，**不寫死像素位置**（P1 手機移植條款）。
	#   三支路線之中最長的那一支是 5 張卡，加上頁首就已經超過 720——第一版
	#   把最後一張卡推到畫面外，而 `_draw()` 對此一個字都不會說（RG-47／RG-60
	#   的同一個教訓）。所以卡片區一律裝在捲動容器裡：**M3 這棵樹要長到 45 個節點**，
	#   靠「把卡片再壓矮一點」撐是撐不過去的。
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var col := UiKit.vbox(10)
	margin.add_child(col)
	col.add_child(UiKit.label("科技樹", 34, Palette.ORDER_BRIGHT, false))
	_data_label = UiKit.label(
		"研究數據 %s" % UiKit.commas(int(_data())), 18, Palette.ENERGY_AMBER, false
	)
	col.add_child(_data_label)
	col.add_child(UiKit.label(
		"研究數據只能靠遊玩取得（戰役每顆星都有），買不到。科技是永久的，下一局起就生效。",
		14, Palette.TEXT_SECONDARY, false
	))
	if on_exit.is_valid():
		var back := Button.new()
		back.text = "返回"
		back.pressed.connect(on_exit)
		var back_row := UiKit.hbox(0)
		back_row.add_child(UiKit.touchable(back))
		col.add_child(back_row)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)

	var row := UiKit.hbox(16)
	_scroll.add_child(row)
	# 依 `Tech.NODES` 的順序建鈕，讓 `_buttons` 的索引和資料表對得起來——
	# 自檢按的是「第 0 個節點」，那必須就是表上的第一列。
	var by_id: Dictionary = {}
	for branch: String in Tech.BRANCHES:
		row.add_child(_branch_column(branch, by_id))
	for n: Dictionary in Tech.NODES:
		_buttons.append(by_id[n["id"]])


func _branch_column(branch: String, by_id: Dictionary) -> Control:
	var col := UiKit.vbox(8)
	col.add_child(UiKit.label(
		Tech.BRANCH_NAMES[branch], 22, Palette.ORDER_CYAN, false
	))
	for n: Dictionary in Tech.of_branch(branch):
		col.add_child(_card(n, by_id))
	return col


func _card(n: Dictionary, by_id: Dictionary) -> Control:
	var id := String(n["id"])
	var owned: bool = _unlocked().has(id)
	var code: String = Tech.can_unlock(id, _unlocked(), _data())

	var box := UiKit.panel()
	box.custom_minimum_size = CARD
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var col := UiKit.vbox(4)
	box.add_child(col)

	col.add_child(UiKit.label(
		String(n["name"]), 17,
		Palette.ENERGY_AMBER if owned else Palette.TEXT_PRIMARY, false
	))
	# ★ `Label` 不解析 Markdown——資料表裡的 `**` 要在這裡剝掉，
	#   不然畫面上會出現一堆星號（同一個坑踩過三次了）。
	var desc := UiKit.label(String(n["desc"]).replace("**", ""), 13, Palette.TEXT_SECONDARY, false)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(CARD.x - 24, 0)
	col.add_child(desc)

	var b := Button.new()
	if owned:
		b.text = "已解鎖"
		b.disabled = true
	else:
		match code:
			Tech.NEEDS_PREREQ:
				# 前置寫出**名字**，不寫「需要前置」——後者要玩家自己去對表。
				b.text = "先解鎖　%s" % String(Tech.of(Tech.prereq(id))["name"])
				b.disabled = true
			Tech.NO_DATA:
				b.text = "%d 研究數據（還差 %d）" % [
					Tech.cost(id), int(ceilf(float(Tech.cost(id)) - _data()))
				]
				b.disabled = true
			_:
				b.text = "解鎖　%d 研究數據" % Tech.cost(id)
				b.pressed.connect(_unlock.bind(id))
	by_id[id] = b
	col.add_child(UiKit.touchable(b))
	return box


## 解鎖：扣款、寫進存檔、重畫。**規則判定回頭問 `Tech.can_unlock()`**——
## 鈕的 `disabled` 是畫面狀態，不是規則；只信它的話，任何一條讓鈕變成可按的路
## （自檢、日後的鍵盤操作）都會繞過檢查。
func _unlock(id: String) -> void:
	var tech: Dictionary = GameState.data["tech"]
	var unlocked: Array = tech["unlocked"]
	if Tech.can_unlock(id, unlocked, float(tech.get("data", 0))) != Tech.OK:
		return
	tech["data"] = float(tech.get("data", 0)) - float(Tech.cost(id))
	unlocked.append(id)
	SaveService.save_from(GameState.data)
	_build()
