extends Control
## 潮汐公司 — 訂單板（`10_GDD.md` §3.8、§7.14；B2.5）。**兩個畫面裡的第一個。**
##
## 這個畫面要回答三個問題，版面就長成這三個問題的形狀：
##   ① **我現在有什麼？**（資金／升級材料／招募券／廠等——最上面一行）
##   ② **有什麼可以收？**（做完的訂單，一顆鈕收掉）
##   ③ **下一步接什麼？**（可接的訂單，接了之後去第二個畫面上線）
##
## ── 它刻意沒有的東西（§3.8 約束 1：沒有失敗狀態、沒有時間壓力、沒有對手）──
## 沒有交期倒數、沒有錯過的懲罰、沒有「限時訂單」、沒有市場價格。
## **它是一個水龍頭，不是一個挑戰。** 任何要在這裡加張力的提案，
## 先回答約束 3：「這如何讓塔防更好玩」。

const TycoonSim := preload("res://scripts/meta/TycoonSim.gd")
const TycoonLinesScreen := preload("res://scripts/screens/TycoonLines.gd")


## 回上一層。由呼叫端指派。
var on_exit: Callable = Callable()

## 這次進來離線結算推進了幾秒（0 ＝ 沒有離線收益可講）。
var _settled: float = 0.0
var _scroll: ScrollContainer = null
## 供自檢用：接單鈕、收成鈕、擴廠鈕、產線編輯鈕。
var _accept_buttons: Array[Button] = []
var _collect_buttons: Array[Button] = []
var _expand_button: Button = null
var _lines_button: Button = null


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# ★ **離線結算在進畫面時做一次**，不是每幀跑一個計時器。
	#   tycoon 沒有「在線生產」與「離線生產」兩套規則——只有一套，
	#   而它的輸入是「你上次來是什麼時候」。兩套規則是膨脹的第一步。
	_settled = TycoonSim.settle(_state(), int(Time.get_unix_time_from_system()))
	if _settled > 0.0:
		SaveService.save_from(GameState.data)
	_build()
	if Hooks.click_test and Hooks.panel == "tycoon":
		_click_selftest.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	UiKit.esc_returns(self, event, on_exit)


func _state() -> Dictionary:
	return GameState.data["tycoon"]


func _build() -> void:
	UiKit.clear(self)
	_accept_buttons.clear()
	_collect_buttons.clear()

	var col := UiKit.screen(self, 12)
	var s := _state()
	var level := int(s["level"])

	col.add_child(UiKit.label("潮汐公司", 32, Palette.ORDER_BRIGHT, false))
	col.add_child(UiKit.label(
		"廠等 %d・產線位 %d・接單上限 %d" % [
			level, TycoonSim.slots(level), TycoonSim.order_cap(level)
		], 16, Palette.TEXT_SECONDARY, false
	))
	# ★ **三種產出各自說清楚它能換什麼**（§3.8：產出全部流向塔防）。
	#   一個沒有用途說明的數字會讓玩家以為這是一個獨立的分數。
	col.add_child(UiKit.label(
		"資金 %s（擴廠）　升級材料 %d（局外成長）　招募券 %d（名冊）" % [
			UiKit.commas(int(s["credits"])), int(s["components"]), int(s["tokens"])
		], 16, Palette.ENERGY_AMBER, false
	))
	if _settled > 0.0:
		col.add_child(UiKit.label(
			"你離開了 %s，產線照跑。做完的訂單停在產線位上等你收。"
				% _duration(_settled),
			13, Palette.OK_GREEN, false
		))

	var nav := UiKit.hbox(12)
	col.add_child(nav)
	if on_exit.is_valid():
		var back := Button.new()
		back.text = "返回"
		back.pressed.connect(on_exit)
		nav.add_child(UiKit.touchable(back))
	_lines_button = Button.new()
	_lines_button.text = "產線編輯"
	_lines_button.pressed.connect(_open_lines)
	nav.add_child(UiKit.touchable(_lines_button))
	_expand_button = Button.new()
	if level >= TycoonSim.MAX_LEVEL:
		_expand_button.text = "廠等已滿（%d）" % TycoonSim.MAX_LEVEL
		_expand_button.disabled = true
	else:
		var cost := TycoonSim.expand_cost(level)
		_expand_button.text = "擴廠　%s 資金" % UiKit.commas(cost)
		_expand_button.disabled = int(s["credits"]) < cost
		if not _expand_button.disabled:
			_expand_button.pressed.connect(_expand)
	nav.add_child(UiKit.touchable(_expand_button))
	# 擴廠買不起時說**還差多少**（藍圖庫缺口提示的同一條）：「資金不足」湊不到。
	if _expand_button.disabled and level < TycoonSim.MAX_LEVEL:
		var short := TycoonSim.expand_cost(level) - int(s["credits"])
		# ★ **擴廠給的東西每一級不一樣**：每一級都開一個新訂單階，產線位每三級
		#   才加一個（`TycoonSim.slots()`）。第一版一律寫「→ 產線位 N」，
		#   於是在不加產線位的那兩級它會顯示和現在一樣的數字——看起來像
		#   「花 911 換一個沒有變化的東西」。**說它真的會給的那一樣。**
		var gain := "第 %d 階訂單「%s」" % [level + 1, String(TycoonSim.ORDER_NAMES[level + 1])]
		if TycoonSim.slots(level + 1) > TycoonSim.slots(level):
			gain += " ＋ 第 %d 個產線位" % TycoonSim.slots(level + 1)
		nav.add_child(UiKit.label(
			"還差 %s 資金 → %s" % [UiKit.commas(short), gain], 13, Palette.WARN_ORANGE, false
		))

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	var list := UiKit.vbox(12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(list)

	list.add_child(UiKit.label("已接的訂單", 22, Palette.ORDER_CYAN, false))
	var orders: Array = s["orders"]
	if orders.is_empty():
		list.add_child(UiKit.label(
			"一張都還沒接。下面挑一張，再到「產線編輯」把它放上產線位。",
			13, Palette.TEXT_SECONDARY, false
		))
	for i in orders.size():
		list.add_child(_order_row(i, orders[i] as Dictionary))

	list.add_child(UiKit.label("可接的訂單", 22, Palette.ORDER_CYAN, false))
	var full: bool = orders.size() >= TycoonSim.order_cap(level)
	if full:
		list.add_child(UiKit.label(
			"接單簿滿了（%d 張）。收成或擴廠之後才接得下新的。" % orders.size(),
			13, Palette.WARN_ORANGE, false
		))
	for tier: int in TycoonSim.available_tiers(level):
		list.add_child(_offer_row(tier, full))
	if level < TycoonSim.MAX_LEVEL:
		list.add_child(UiKit.label(
			"第 %d 階「%s」要廠等 %d 才接得到。" % [
				level + 1, String(TycoonSim.ORDER_NAMES[level + 1]), level + 1
			], 13, Palette.TEXT_DISABLED, false
		))


## 一張已接訂單。**進度用文字寫清楚**，不做進度條動畫——
## 這個畫面的存在時間是「一兩分鐘就走」（§2.3），不需要看著它動。
func _order_row(index: int, order: Dictionary) -> Control:
	var tier := int(order["tier"])
	var line := int(order["line"])
	var work := TycoonSim.work_of(tier)
	var done := float(order["done"])
	var box := UiKit.panel()
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := UiKit.hbox(12)
	box.add_child(row)

	var where := "產線位 %d" % (line + 1) if line >= 0 else "未上線"
	var tone: Color = Palette.TEXT_SECONDARY
	if TycoonSim.is_done(order):
		where = "已完成・佔著產線位 %d" % (line + 1)
		tone = Palette.OK_GREEN
	elif line < 0:
		tone = Palette.WARN_ORANGE
	var text := UiKit.label(
		"%s（第 %d 階）　%d／%d　%s" % [
			String(TycoonSim.ORDER_NAMES[tier]), tier, int(done), int(work), where
		], 16, tone, false
	)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(text)

	if TycoonSim.is_done(order):
		var b := Button.new()
		b.text = "收成　%s 資金・%d 材料%s" % [
			UiKit.commas(TycoonSim.reward_of(tier)), TycoonSim.component_of(tier),
			"・%d 券" % TycoonSim.token_of(tier) if TycoonSim.token_of(tier) > 0 else ""
		]
		b.pressed.connect(_collect.bind(index))
		_collect_buttons.append(b)
		row.add_child(UiKit.touchable(b))
	return box


## 一張可接的訂單。**報酬寫在接之前**——決定要在按下去之前就做得出來。
func _offer_row(tier: int, full: bool) -> Control:
	var box := UiKit.panel()
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := UiKit.hbox(12)
	box.add_child(row)
	var text := UiKit.label(
		"%s（第 %d 階）　%d 秒　→　%s 資金・%d 材料%s" % [
			String(TycoonSim.ORDER_NAMES[tier]), tier, int(TycoonSim.work_of(tier)),
			UiKit.commas(TycoonSim.reward_of(tier)), TycoonSim.component_of(tier),
			"・%d 招募券" % TycoonSim.token_of(tier) if TycoonSim.token_of(tier) > 0 else ""
		], 16, Palette.TEXT_PRIMARY, false
	)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(text)
	var b := Button.new()
	b.text = "接單"
	b.disabled = full
	if not full:
		b.pressed.connect(_accept.bind(tier))
	_accept_buttons.append(b)
	row.add_child(UiKit.touchable(b))
	return box


## 「你離開了多久」。**用人話講**，不是印秒數。
func _duration(seconds: float) -> String:
	if seconds < 60.0:
		return "%d 秒" % int(seconds)
	if seconds < 3600.0:
		return "%d 分鐘" % int(seconds / 60.0)
	if seconds < 86400.0:
		return "%.1f 小時" % (seconds / 3600.0)
	return "%.1f 天" % (seconds / 86400.0)


# ── 動作。**規則判定一律在 `TycoonSim`**，不在按鈕的 `disabled` 上 ──────

func _accept(tier: int) -> void:
	if not TycoonSim.accept(_state(), tier):
		return
	AudioBus.play("ui_click")
	SaveService.save_from(GameState.data)
	_build()


func _collect(index: int) -> void:
	if not TycoonSim.collect(_state(), index):
		return
	# 收成沿用科技樹的解鎖音：兩者都是「得到一個永久的東西」。
	AudioBus.play("ui_unlock")
	SaveService.save_from(GameState.data)
	_build()


func _expand() -> void:
	if not TycoonSim.expand(_state()):
		return
	AudioBus.play("ui_unlock")
	SaveService.save_from(GameState.data)
	_build()


func _open_lines() -> void:
	var screen := TycoonLinesScreen.new()
	screen.on_exit = func() -> void:
		UiKit.clear(self)
		_build()
	UiKit.clear(self)
	add_child(screen)


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=tycoon`）。
##
## 走完整條循環：**接單 → 產線編輯指派 → 回來 → 快轉 → 收成 → 擴廠**。
## 每一步都用合成滑鼠事件，因為要驗的是事件路由得到（B0.7.2 那一課）。
##
## 存檔在有鉤子時是預設值（廠等 1、零資金），所以：
##   · 接單與指派靠真的點鈕
##   · **「時間過去了」直接呼叫 `accrue()`**——合成不出一分鐘的等待，
##     而那一段本來就由 `tycoon_test` 驗（含離線上限與時鐘倒退）
func _click_selftest() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var s := _state()

	var starts_clean: bool = (
		int(s["level"]) == 1 and int(s["credits"]) == 0 and (s["orders"] as Array).is_empty()
	)
	# 廠等 1 只接得到第 1 階，而且接單上限是 3。
	var offers_one_tier: bool = _accept_buttons.size() == 1

	await UiKit.click(_accept_buttons[0])
	var accepted: bool = (s["orders"] as Array).size() == 1

	# 產線編輯：進得去、指派得了、回得來。
	await UiKit.click(_lines_button)
	var lines_screen := _lines_child()
	var opened: bool = lines_screen != null
	var assigned := false
	if opened:
		await UiKit.click(lines_screen._assign_buttons[0])
		assigned = TycoonSim.order_on_line(s, 0) == 0
		await UiKit.click(lines_screen._back_button)
	# ★ 回來之後**訂單板要重畫**——`_build()` 沒被呼叫的話畫面會停在舊資料上，
	#   而它看起來完全正常（就是不會更新）。斷言看的是「有沒有收成鈕」。
	var returned: bool = _lines_child() == null and _accept_buttons.size() == 1

	# 快轉到做完（見上：這一段的規則由 `tycoon_test` 驗）。
	TycoonSim.accrue(s, TycoonSim.work_of(1))
	_build()
	await get_tree().process_frame
	var collectable: bool = _collect_buttons.size() == 1

	await UiKit.click(_collect_buttons[0])
	var collected: bool = (
		int(s["credits"]) == TycoonSim.reward_of(1) and (s["orders"] as Array).is_empty()
	)

	# 擴廠：**先確認它是灰的**（零資金買不起），塞夠錢之後才變得可按。
	var expand_gated: bool = _expand_button.disabled
	s["credits"] = TycoonSim.expand_cost(1)
	_build()
	await get_tree().process_frame
	await UiKit.click(_expand_button)
	var expanded: bool = int(s["level"]) == 2 and int(s["credits"]) == 0

	var esc_back: bool = await UiKit.esc_reaches(self)

	var ok: bool = (
		starts_clean and offers_one_tier and accepted and opened and assigned and returned
		and collectable and collected and expand_gated and expanded and esc_back
	)
	print("[TL_CLICKTEST/tycoon] clean=%s one_tier=%s accept=%s lines_open=%s assign=%s back=%s collectable=%s collect=%s expand_gated=%s expand=%s esc=%s → %s" % [
		starts_clean, offers_one_tier, accepted, opened, assigned, returned, collectable,
		collected, expand_gated, expanded, esc_back, "PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		get_tree().quit(0 if ok else 1)
		return
	# ★ 配 `TL_SHOT` 時把畫面留在「有訂單在跑、有東西可收」那一格——
	#   零進度的訂單板是空的，而要看的正是它忙起來的樣子。
	TycoonSim.accept(s, 1)
	TycoonSim.accept(s, 2)
	TycoonSim.assign(s, 0, 0)
	TycoonSim.assign(s, 1, 1)
	TycoonSim.accrue(s, TycoonSim.work_of(1))
	_build()
	# ★ `TL_LEVEL=2` 時再往前一步，把畫面留在**產線編輯**（第二個畫面）。
	#   產線編輯不在 `Main.PANEL_SCREENS` 上是刻意的（兩個畫面、一條路），
	#   所以它沒有自己的 `TL_PANEL`——而「從來沒有人看過那張圖」正是 RG-142
	#   的成因。借一個既有的鉤子（這裡 `TL_LEVEL` 的語意剛好是「第幾個畫面」）
	#   比多開一個入口便宜。
	#   ⚠ 第一版寫 `Hooks.seed`，而**那個欄位不存在**（`TL_SEED` 走的是
	#     `Rng.seed_value`）。截圖跑出來和沒加一樣，而畫面沒有任何錯誤徵兆——
	#     和 RG-142 是同一個形狀：**沒有讀那張圖就不會發現**。
	if Hooks.level == 2:
		await get_tree().process_frame
		_open_lines()


func _lines_child() -> Control:
	for c: Node in get_children():
		if c.get_script() == TycoonLinesScreen:
			return c as Control
	return null


