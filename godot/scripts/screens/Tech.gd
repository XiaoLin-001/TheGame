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
const Levels := preload("res://data/Levels.gd")

const CARD := Vector2(300, 116)


## 回上一層。由呼叫端指派。
var on_exit: Callable = Callable()

## 供自檢按的解鎖鈕，與 `Tech.NODES` 同索引。
var _buttons: Array[Button] = []
var _data_label: Label = null
## 供自檢按的等級軸升級鈕，與 `Levels.AXES` 同索引。
var _level_buttons: Array[Button] = []
var _scroll: ScrollContainer = null


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	# ★ `and Hooks.panel == "tech"`（B1.9）：本畫面同時掛得到標題與關卡選擇兩處，
	#   只有「它自己是受測對象」時才該跑自己的自檢（`Settings` 的同一條）。
	if Hooks.click_test and Hooks.panel == "tech":
		_click_selftest.call_deferred()


## ESC ＝ 返回上一層（B1.4.1）。
func _unhandled_key_input(event: InputEvent) -> void:
	UiKit.esc_returns(self, event, on_exit)


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
	# ★ 等級軸（B2.7）也一樣：零材料 → 兩顆都是關的。
	#
	# ⚠ **這一條要在買科技之前量。** 第一版放在後面，量到的是 `disabled=false`
	#   ——因為買下 `cap1` 當場達成了成就「第一項科技」，15 材料立刻進帳。
	#   斷言是錯的，程式是對的：那正是「成就沒有領取鈕」該有的樣子。
	var broke_levels: bool = _level_buttons.size() == 2 and _level_buttons[0].disabled

	var tech: Dictionary = GameState.data["tech"]
	tech["data"] = 500.0
	_build()
	await get_tree().process_frame
	var first_open: bool = _buttons[0].text.contains("解鎖")and not _buttons[0].disabled
	# 第二階（cap2）在第一階還沒買之前必須是鎖著的，而且要說出原因。
	var tier2_locked: bool = _buttons[1].disabled and _buttons[1].text.contains("導管擴容 I")

	await UiKit.click(_buttons[0])
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

	# ★ 等級軸（B2.7）。存檔在有鉤子時是零級零材料 → 兩顆都該是關的；
	#   塞一筆局末材料進去（**不寫檔**）之後才點得下去。
	(GameState.data["levels"] as Dictionary)["from_battle"] = 500
	_build()
	await get_tree().process_frame
	var lv_open: bool = not _level_buttons[0].disabled
	var before := _components()
	await UiKit.click(_level_buttons[0])
	var lv_up: bool = Levels.level_of(GameState.data, Levels.TOWER) == 1
	# **餘額是推導的**（`SaveService.components()`），所以「有沒有真的扣款」
	# 問的是那一支——不是去看某個欄位有沒有被減。
	var lv_charged: bool = _components() == before - Levels.cost(0)

	# ★ ESC ＝ 返回（B1.4.1）。**不能真的呼叫 `on_exit`**（那會把這個畫面拆掉，
	#   後面的 print 就落在一個正在被釋放的節點上），所以暫時換成一個只翻旗標的
	#   Callable：要驗的是「事件到不到得了這支處理器」，不是返回本身。
	var esc_back: bool = await UiKit.esc_reaches(self)

	var ok: bool = (
		twelve and all_broke and first_open and tier2_locked
		and bought and charged and tier2_open and reachable and esc_back
		and broke_levels and lv_open and lv_up and lv_charged
	)
	print("[TL_CLICKTEST/tech] twelve=%s broke=%s first_open=%s tier2_locked=%s bought=%s charged=%s tier2_open=%s last_reachable=%s esc_back=%s lv_broke=%s lv_open=%s lv_up=%s lv_charged=%s → %s" % [
		twelve, all_broke, first_open, tier2_locked, bought, charged, tier2_open, reachable,
		esc_back, broke_levels, lv_open, lv_up, lv_charged, "PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		get_tree().quit(0 if ok else 1)




func _data() -> float:
	return float((GameState.data.get("tech", {}) as Dictionary).get("data", 0))


func _components() -> int:
	return SaveService.components(GameState.data)


## ★ 等級軸兩張卡（B2.7、§7.15）。橫向一列放在捲動區**外面**：
## 它只有兩張、而且是「先看這裡」的東西——藏進 12 張科技卡裡要捲才看得到。
func _level_row() -> Control:
	var row := UiKit.hbox(16)
	_level_buttons.clear()
	for axis: String in Levels.AXES:
		row.add_child(_level_card(axis))
	return row


func _level_card(axis: String) -> Control:
	var lv := Levels.level_of(GameState.data, axis)
	var box := UiKit.panel()
	box.custom_minimum_size = Vector2(CARD.x, 0)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var col := UiKit.vbox(4)
	box.add_child(col)

	col.add_child(UiKit.label(
		"%s　%d／%d 級" % [String(Levels.AXIS_NAMES[axis]), lv, Levels.MAX_LEVEL], 17,
		Palette.ENERGY_AMBER if lv > 0 else Palette.TEXT_PRIMARY, false
	))
	# **效果寫成局內看得到的數字**（這個畫面開頭那兩個問題的第二個）。
	var desc := UiKit.label(
		"%s　現在 ×%.2f" % [String(Levels.AXIS_DESC[axis]), Levels.mult(lv)],
		13, Palette.TEXT_SECONDARY, false
	)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(CARD.x - 24, 0)
	col.add_child(desc)

	var b := Button.new()
	match Levels.can_upgrade(GameState.data, axis, _components()):
		Levels.MAXED:
			b.text = "已滿級　×%.2f" % Levels.mult(Levels.MAX_LEVEL)
			b.disabled = true
		Levels.NO_COMPONENTS:
			b.text = "%d 材料（還差 %d）" % [
				Levels.cost(lv), Levels.cost(lv) - _components()
			]
			b.disabled = true
		_:
			b.text = "升級　%d 材料　→ ×%.2f" % [Levels.cost(lv), Levels.mult(lv + 1)]
			b.pressed.connect(_level_up.bind(axis))
	_level_buttons.append(b)
	col.add_child(UiKit.touchable(b))
	return box


## 升一級。**規則判定回頭問 `SaveService.apply_level_up()`**（同 `_unlock()`）。
func _level_up(axis: String) -> void:
	if not SaveService.apply_level_up(GameState.data, axis):
		return
	AudioBus.play("ui_unlock")
	SaveService.save_from(GameState.data)
	_build()


func _unlocked() -> Array:
	return (GameState.data.get("tech", {}) as Dictionary).get("unlocked", [])


func _build() -> void:
	UiKit.clear(self)
	_buttons.clear()

	var col := UiKit.screen(self, 10)
	# ★ 這個畫面從 B2.7 起裝的是**局外成長的兩軸**（§1 B2）——等級軸沒有自己的
	#   入口，因為它和科技樹回答的是同一個問題（我的永久強化買到哪裡了）。
	#   主選單已經九顆鈕塞滿 720px，多一顆的代價是把「離開遊戲」推出畫面。
	col.add_child(UiKit.label("局外成長", 32, Palette.ORDER_BRIGHT, false))
	_data_label = UiKit.label(
		"研究數據 %s　　升級材料 %s" % [
			UiKit.commas(int(_data())), UiKit.commas(_components())
		], 16, Palette.ENERGY_AMBER, false
	)
	col.add_child(_data_label)
	# ★ **要換行**：這一段比一張卡寬，不設 autowrap 就會直接切在畫面右緣
	#   （B2.7 截圖抓到）。`UiKit.label()` 預設不換行，長句一律自己開。
	var intro := UiKit.label(
		"兩種貨幣、兩把各自獨立的尺。研究數據只能靠遊玩取得（戰役每顆星都有），"
		+ "科技全解鎖對戰鬥數值的總增幅上限 +35%；升級材料來自局末波數、潮汐公司"
		+ "與成就，等級軸的兩軸各自最多 +80%。兩者都是永久的，下一局起就生效。",
		14, Palette.TEXT_SECONDARY, false
	)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(intro)
	col.add_child(_level_row())
	var nav := UiKit.back_row("返回", on_exit, 0)
	if nav != null:
		col.add_child(nav)

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
	AudioBus.play("ui_unlock")
	var tech: Dictionary = GameState.data["tech"]
	var unlocked: Array = tech["unlocked"]
	if Tech.can_unlock(id, unlocked, float(tech.get("data", 0))) != Tech.OK:
		return
	tech["data"] = float(tech.get("data", 0)) - float(Tech.cost(id))
	unlocked.append(id)
	SaveService.save_from(GameState.data)
	_build()
