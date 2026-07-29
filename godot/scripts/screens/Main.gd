extends Control
## 標題畫面（目前的 main_scene）。
##
## B0.1 只需要它證明三件事：專案能開起來、版面走容器（P1）、CJK 字型不是豆腐字。
## 主選單與各面板排在 M1（B1.4）；`TL_PANEL` 的路由表也在那時才長出來。

const BattleScreen := preload("res://scripts/screens/Battle.gd")

## TL_PANEL 目前認得的畫面。其餘由後續批次補進來。
## `sandbox` ＝ 局內畫面但換成沙盤「靜水」（`data/Maps.gd`）：
## 沒有敵人，只有三種資源在跑，用來驗合金那一列流動珠（B1.1）。
const KNOWN_PANELS := ["title", "battle", "sandbox"]


func _ready() -> void:
	theme = UiKit.theme()
	if Hooks.panel in ["battle", "sandbox"]:
		_enter_battle()
		return
	_build()
	_route_panel()


## 切到局內。B1.4 會有真正的主選單與關卡選擇；現在只有一張測試圖。
func _enter_battle() -> void:
	for c: Node in get_children():
		c.queue_free()
	var battle := BattleScreen.new()
	add_child(battle)


func _build() -> void:
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

	# 可玩 build 的入口（工作室鐵律 2）。真正的主選單在 B1.4。
	var start := Button.new()
	start.text = "進入測試圖　淺灘"
	start.pressed.connect(_enter_battle)
	col.add_child(UiKit.touchable(start))

	# TL_NAKED 的語意是「隱藏所有數值標籤，只留圖形」（30_TECH_DESIGN.md §4.1）。
	# 本批還沒有 HUD 可遮，先把版本／鉤子這行納管，證明這條路徑真的接通了；
	# 它真正的工作對象（頂欄數字、節點數值、優先權刻度）在 B0.6 出現。
	if Hooks.naked:
		print("[TL_NAKED] 版本列已隱藏；version=%s" % GameState.VERSION)
		return

	col.add_child(UiKit.label("v%s" % GameState.VERSION, 13, Palette.TEXT_DISABLED))

	# 只列名稱不列值 —— 值（例如 TL_SHOT 的絕對路徑）會撐爆版面，細節在 stdout。
	var hooks := Env.active_names()
	if hooks != "":
		col.add_child(UiKit.label(hooks, 11, Palette.WARN_ORANGE))


func _route_panel() -> void:
	if Hooks.panel == "":
		return
	if Hooks.panel in KNOWN_PANELS:
		return
	# 不當掉、不假裝成功：說清楚它還沒被實作，留在標題畫面。
	push_warning("TL_PANEL=%s 尚未實作（B0.1 只有 title），停在標題畫面" % Hooks.panel)
	print("[TL_PANEL] unknown=%s known=%s" % [Hooks.panel, ", ".join(KNOWN_PANELS)])
