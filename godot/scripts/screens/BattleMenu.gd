class_name BattleMenu
extends RefCounted
## 局內選單與設定浮層（不暫停）。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

const SettingsScreen := preload("res://scripts/screens/Settings.gd")

## 局內選單（ESC 或左上角「選單」鈕）。`null` ＝ 沒開。
var menu_layer: Control = null

var menu_button: Button = null

var menu_buttons: Array[Button] = []

## 從局內選單開出來的設定浮層。開著時 ESC 由它自己處理（回到選單）。
var settings_layer: Control = null

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


func toggle_menu() -> void:
	if menu_layer != null:
		close_menu()
		return
	_open_menu()


## 半透明遮罩。它做兩件事：把戰場壓暗讓選單讀得到，以及**吃掉滑鼠**——
## 選單開著的時候點下去不該蓋出一個節點來（`mouse_filter` 預設 STOP）。
func _scrim() -> Control:
	var layer := ColorRect.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.color = Palette.alpha(Palette.BG_DEEP, 0.82)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP   # 明寫：擋滑鼠是它一半的工作
	return layer


func _open_menu() -> void:
	close_menu()
	menu_layer = _scrim()
	battle.add_child(menu_layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.add_child(center)
	var box := UiKit.panel()
	box.mouse_filter = Control.MOUSE_FILTER_PASS   # 面板不吃滑鼠，但鈕要點得到
	center.add_child(box)
	var col := UiKit.vbox(8)
	box.add_child(col)
	col.add_child(UiKit.label("選單", 32, Palette.ORDER_BRIGHT))
	col.add_child(UiKit.label("時間仍在走。選單不暫停。", 13, Palette.WARN_ORANGE))
	menu_buttons.clear()
	# 「重來」與「退出」的代價寫在鈕上。**不做二次確認**：R1 說失敗只花時間，
	# 而一句括號比一個確認框省一次點擊，也省一整個對話框元件。
	var entries: Array = [
		["繼續", close_menu],
		["重來（本局歸零）", battle.restart],
		["設定", _open_settings],
	]
	if battle.on_exit.is_valid():
		entries.append(["退出（放棄本局）", battle.on_exit])
	for entry: Array in entries:
		var b := Button.new()
		b.text = String(entry[0])
		b.custom_minimum_size.x = 200
		b.pressed.connect(entry[1] as Callable)
		menu_buttons.append(b)
		col.add_child(UiKit.touchable(b))


func close_menu() -> void:
	if menu_layer == null:
		return
	# `queue_free()` 要到影格末才生效，中間那一幀遮罩還在畫也還在吃滑鼠——
	# 先 `remove_child()` 讓它當場離開樹（`Campaign._clear()` 同一條）。
	battle.remove_child(menu_layer)
	menu_layer.queue_free()
	menu_layer = null
	menu_buttons.clear()


## 局內開設定：整個設定畫面原封不動疊上來，不另做一份「局內版設定」——
## 兩份設定畫面遲早會有一份漏掉新選項。
func _open_settings() -> void:
	close_menu()
	settings_layer = _scrim()
	battle.add_child(settings_layer)
	var screen := SettingsScreen.new()
	screen.on_exit = _close_settings
	settings_layer.add_child(screen)


func _close_settings() -> void:
	if settings_layer != null:
		battle.remove_child(settings_layer)
		settings_layer.queue_free()
		settings_layer = null
	_open_menu()
