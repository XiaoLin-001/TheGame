extends Node
## 局內選單（ESC 或左上角「選單」鈕，B1.4.1）與從它開出來的設定浮層。
##
## **選單也不暫停**（純即時不可暫停是鎖定的設計）：面板上寫明「時間仍在走」。
## ESC 是快捷，不是唯一的路（P3：操作不得只靠鍵盤）。

const SettingsScreen := preload("res://scripts/screens/Settings.gd")

## 擁有這個模組的局內畫面（`screens/Battle.gd`）。由它在建立時指派。
var scr: Control = null


## 局內選單（ESC 或左上角「選單」鈕）。`null` ＝ 沒開。
var menu_layer: Control = null

var menu_button: Button = null

var menu_buttons: Array[Button] = []

## 從局內選單開出來的設定浮層。開著時 ESC 由它自己處理（回到選單）。
var settings_layer: Control = null


# ── 局內選單（B1.4.1）────────────────────────────────────────────────
#
# ★ **不暫停**（`10_GDD.md` B5「不可暫停，但可跳過等待」）。選單開著的這幾秒
#   敵人仍然在走、電仍然在流。這不是偷懶：可暫停的選單就是一個「隨時可以停下來
#   慢慢想」的按鍵，而那正是 B5 要擋掉的東西。面板上直接寫出來，玩家才不會
#   以為是遊戲壞了——**沒說出口的規則會被當成 bug**。

## ESC。**鍵盤不是唯一的路**（手機移植預留條款 P3）：左上角有一顆「選單」鈕
## 做完全同一件事，`_toggle_menu()` 是兩者共用的那一個入口。
func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# 設定浮層開著時**不消費事件**，交給它自己的 ESC（它會回到選單）。
	# 這樣兩邊誰先被呼叫都不影響結果——不必賭 Godot 的輸入傳遞順序。
	if settings_layer != null:
		return
	get_viewport().set_input_as_handled()
	AudioBus.play("ui_back")   # ESC ＝ 取消手勢，全遊戲同一個音（B1.5）
	toggle_menu()


## 左上角的「選單」鈕。
func build_button() -> void:
	# ★ 選單（B1.4.1）。ESC 是快捷，**不是唯一的路**（P3：操作不得只靠鍵盤）。
	#   放左上角 x<120、y<56 那塊角落——頂欄從 x=120 起、建造欄從 y=56 起，
	#   全畫面只剩這裡是空的，而它也正好是選單的慣例位置。
	var menu_bar := UiKit.hbox(0)
	menu_bar.position = Vector2(8, 6)
	scr.add_child(menu_bar)
	menu_button = Button.new()
	menu_button.text = "選單"
	menu_button.custom_minimum_size.x = 104
	menu_button.pressed.connect(toggle_menu)
	menu_bar.add_child(UiKit.touchable(menu_button))


func toggle_menu() -> void:
	if menu_layer != null:
		_close_menu()
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
	_close_menu()
	menu_layer = _scrim()
	scr.add_child(menu_layer)
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
		["繼續", _close_menu],
		["重來（本局歸零）", scr.restart],
		["設定", _open_settings],
	]
	if scr.on_exit.is_valid():
		entries.append(["退出（放棄本局）", scr.on_exit])
	for entry: Array in entries:
		var b := Button.new()
		b.text = String(entry[0])
		b.custom_minimum_size.x = 200
		b.pressed.connect(entry[1] as Callable)
		menu_buttons.append(b)
		col.add_child(UiKit.touchable(b))


func _close_menu() -> void:
	if menu_layer == null:
		return
	# `queue_free()` 要到影格末才生效，中間那一幀遮罩還在畫也還在吃滑鼠——
	# 先 `scr.remove_child()` 讓它當場離開樹（`Campaign._clear()` 同一條）。
	scr.remove_child(menu_layer)
	menu_layer.queue_free()
	menu_layer = null
	menu_buttons.clear()


## 局內開設定：整個設定畫面原封不動疊上來，不另做一份「局內版設定」——
## 兩份設定畫面遲早會有一份漏掉新選項。
func _open_settings() -> void:
	_close_menu()
	settings_layer = _scrim()
	scr.add_child(settings_layer)
	var screen := SettingsScreen.new()
	screen.on_exit = _close_settings
	settings_layer.add_child(screen)


func _close_settings() -> void:
	if settings_layer != null:
		scr.remove_child(settings_layer)
		settings_layer.queue_free()
		settings_layer = null
	_open_menu()
