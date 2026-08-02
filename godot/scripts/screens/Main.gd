extends Control
## 標題畫面（目前的 main_scene）。
##
## B0.1 只需要它證明三件事：專案能開起來、版面走容器（P1）、CJK 字型不是豆腐字。
## 主選單與各面板排在 M1（B1.4）；`TL_PANEL` 的路由表也在那時才長出來。

const BattleScreen := preload("res://scripts/screens/Battle.gd")
const CampaignScreen := preload("res://scripts/screens/Campaign.gd")
const TechScreen := preload("res://scripts/screens/Tech.gd")
const SettingsScreen := preload("res://scripts/screens/Settings.gd")
const CampaignData := preload("res://data/Campaign.gd")

## ★ `TL_PANEL` → 要進的畫面。**這張表就是「認得哪些畫面」的唯一一份**（B1.9）。
##
## 舊版在這裡另外存了一份 `KNOWN_PANELS` 字串陣列，唯一的工作是在名字不認得時
## 印警告——而 `_ready()` 的 if 串本身就是那份名單，兩者遲早不同步。
## 現在名單只有一份：**能不能路由，就是認不認得**。
##
## `sandbox` ＝ 局內畫面但換成沙盤「靜水」（`data/Maps.gd`）：沒有敵人，
## 只有三種資源在跑，用來驗合金那一列流動珠（B1.1）。
## `campaign` ＝ 戰役關卡選擇；配 `TL_LEVEL=1..5` 直接進那一關（B1.2）。
## `title` 不在表上——它的語意就是「什麼都不進」。
const PANEL_SCREENS := {
	"battle": BattleScreen,
	"sandbox": BattleScreen,
	"campaign": CampaignScreen,
	"tech": TechScreen,
	"settings": SettingsScreen,
}


## 主選單的五顆鈕（自檢要按得到）。
var _menu_buttons: Array[Button] = []


func _ready() -> void:
	theme = UiKit.theme()
	if PANEL_SCREENS.has(Hooks.panel):
		_enter(
			PANEL_SCREENS[Hooks.panel],
			_campaign_level if Hooks.panel == "campaign" else Callable()
		)
		return
	_build()
	# 不當掉、不假裝成功：說清楚它還沒被實作，留在標題畫面。
	if Hooks.panel != "" and Hooks.panel != "title":
		push_warning("TL_PANEL=%s 尚未實作，停在標題畫面" % Hooks.panel)
		print("[TL_PANEL] unknown=%s known=%s" % [
			Hooks.panel, ", ".join(PANEL_SCREENS.keys())
		])
	if Hooks.click_test:
		_click_selftest.call_deferred()


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=title`，B1.9）。
##
## **這一支是 B1.9 重構自己逼出來的**：主選單那五顆鈕原本各接一支 `_enter_*`，
## 改成 `_enter.bind(Screen)` 之後——`Callable.bind()` 把參數綁在**尾端**，
## 綁錯位置就是一顆按了沒反應的鈕，而 `_draw()` 一個字都不會說（B0.7.2 同一課）。
## 其餘三條 clicktest 全走 `TL_PANEL`，**完全繞過主選單**，所以這條路是零覆蓋。
##
## 驗一圈完整往返：戰役（bind 帶 setup）→ ESC 回標題 → 科技樹（bind 不帶 setup）。
func _click_selftest() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var five: bool = _menu_buttons.size() == 5

	await _press(_menu_buttons[0])                     # 戰役
	var to_campaign: bool = _child_script() == CampaignScreen

	# ESC ＝ 回標題（`_enter()` 把 `on_exit` 指成 `_back_to_title`）。
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		ev.pressed = pressed
		Input.parse_input_event(ev)
	for _i in 4:
		await get_tree().process_frame
	# 回到標題＝五顆鈕**重新長出來**（`_build()` 有跑），不是舊的那五顆還在。
	var back_home: bool = _child_script() == null and _menu_buttons.size() == 5

	await _press(_menu_buttons[1])                     # 科技樹
	var to_tech: bool = _child_script() == TechScreen

	var ok: bool = five and to_campaign and back_home and to_tech
	print("[TL_CLICKTEST/title] buttons=%s campaign=%s esc_home=%s tech=%s → %s" % [
		five, to_campaign, back_home, to_tech, "PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		get_tree().quit(0 if ok else 1)


## 合成一次真的滑鼠點擊（不是直接 emit `pressed`）——要驗的是事件路由得到，
## 而那正是 B0.7.2 靜靜壞掉五個批次的地方。
func _press(b: Button) -> void:
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


## 現在掛在底下的是哪一個畫面？（標題畫面本身沒有 script 為 screen 的子節點）
func _child_script() -> Script:
	for c: Node in get_children():
		var sc := c.get_script() as Script
		if sc != null:
			return sc
	return null


## ★ 切到某個畫面（B1.9）。四支 `_enter_battle` / `_enter_campaign` /
## `_enter_tech` / `_enter_settings` 做的是同一件事——清子節點、new、指
## `on_exit`、掛上去——差別只有那個 script 與一個可選的後續動作。
##
## 順手修掉一個不一致：舊的四支只 `queue_free()` 不 `remove_child()`，
## 而 `_back_to_title()` 兩個都做。`queue_free()` 要到影格末才生效，中間那一幀
## 舊畫面還在畫也還在吃滑鼠——現在四條路都走 `UiKit.clear()` 的同一個順序。
func _enter(script: Script, setup: Callable = Callable()) -> void:
	UiKit.clear(self)
	var screen: Control = script.new()
	# 測試圖也要有回頭路：局內選單的「退出」就是這個 `on_exit`（B1.4.1）。
	screen.on_exit = _back_to_title
	add_child(screen)
	if setup.is_valid():
		setup.call(screen)


## `TL_LEVEL=N` 直接進第 N 關——**有些畫面只有進去才到得了**
## （局末星等要打完才有），截圖鉤子需要一條不用手點的路。
func _campaign_level(screen: Control) -> void:
	if Hooks.level >= 1 and Hooks.level <= CampaignData.count():
		screen._enter.call_deferred(Hooks.level - 1)


func _back_to_title() -> void:
	UiKit.clear(self)
	_build()


func _build() -> void:
	AudioBus.music("menu")
	# 全部走容器與錨點，不寫死像素位置 —— 手機移植預留條款 P1。
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := UiKit.vbox(16)
	center.add_child(col)

	col.add_child(UiKit.label(GameState.GAME_NAME, 48, Palette.ORDER_BRIGHT))
	col.add_child(UiKit.label(GameState.GAME_NAME_EN, 22, Palette.ORDER_CYAN))

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 24)
	col.add_child(gap)

	col.add_child(UiKit.label(GameState.TAGLINE, 16, Palette.TEXT_SECONDARY))

	# ★ 主選單（B1.4）。**戰役排第一顆**：它是這款遊戲；科技樹與設定是它的周邊，
	#   測試圖是給我自己用的。順序就是「玩家最可能想按的東西」由上而下。
	_menu_buttons.clear()
	for entry: Array in [
		["戰役　%s" % _campaign_progress(), _enter.bind(CampaignScreen, _campaign_level)],
		["科技樹　%s 研究數據" % UiKit.commas(int(_research_data())), _enter.bind(TechScreen)],
		["設定", _enter.bind(SettingsScreen)],
		["測試圖　淺灘", _enter.bind(BattleScreen)],
		["離開遊戲", _quit],
	]:
		var b := Button.new()
		b.text = String(entry[0])
		b.pressed.connect(entry[1] as Callable)
		_menu_buttons.append(b)
		col.add_child(UiKit.touchable(b))

	# TL_NAKED 的語意是「隱藏所有數值標籤，只留圖形」（30_TECH_DESIGN.md §4.1）。
	# 本批還沒有 HUD 可遮，先把版本／鉤子這行納管，證明這條路徑真的接通了；
	# 它真正的工作對象（頂欄數字、節點數值、優先權刻度）在 B0.6 出現。
	if Hooks.naked:
		print("[TL_NAKED] 版本列已隱藏；version=%s" % GameState.VERSION)
		return

	col.add_child(UiKit.label("v%s" % GameState.VERSION, 13, Palette.TEXT_DISABLED))

	# 只列名稱不列值 —— 值（例如 TL_SHOT 的絕對路徑）會撐爆版面，細節在 stdout。
	var hooks := Env.active()
	if hooks != "":
		col.add_child(UiKit.label(hooks, 11, Palette.WARN_ORANGE))


## 戰役進度：滿星是 15 顆。**主選單上就看得到「還差幾顆」**——
## 回來的理由要在按下去之前就成立，不是進了關卡選擇才發現。
func _campaign_progress() -> String:
	var best: Dictionary = (GameState.data.get("campaign", {}) as Dictionary).get("stars", {})
	var got := 0
	for id: String in CampaignData.ids():
		got += int(best.get(id, 0))
	var total := CampaignData.count() * 3
	return "%d／%d ★" % [got, total]


func _research_data() -> float:
	return float((GameState.data.get("tech", {}) as Dictionary).get("data", 0))


## 離開。**存一次再走**——設定畫面雖然改一次存一次，但戰役結算那條路徑
## 是在 `Battle` 裡寫的，留一個出口統一收尾比較不會漏。
func _quit() -> void:
	SaveService.save_from(GameState.data)
	get_tree().quit()
