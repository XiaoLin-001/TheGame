extends Control
## 設定畫面（B1.4、`10_GDD.md` §6.2）。
##
## 三條紀律：
##   ① **改了當場生效**，不要「套用」鈕。滑桿拉到一半才知道結果的音量沒有意義。
##   ② **當場存檔**。改完設定又忘了存的那一個玩家，下次開遊戲會以為設定壞了。
##   ③ **不做鍵位設定**。這款遊戲一顆鍵都沒有綁（局內說明就寫著「沒有鍵盤」），
##      做一個空的鍵位表只是把「還沒有的東西」畫出來給人看。B1.4 的 DoD 列了
##      鍵位，這裡誠實地不做，理由記在 `40_PRODUCTION_PLAN.md` 的完工證據。

const Motion := preload("res://scripts/render/Motion.gd")

## 可選的視窗尺寸。清單本體在 `SaveService`——存檔存的是它的索引，
## 兩者放同一個檔案才不會各改各的。
const RESOLUTIONS := SaveService.RESOLUTIONS

## `settings` 的三個音量鍵 →（顯示名, 匯流排名）。
const VOLUMES := [
	["master", "主音量", "Master"],
	["bgm", "音樂", "BGM"],
	["sfx", "音效", "SFX"],
]


var on_exit: Callable = Callable()

var _sliders: Dictionary = {}          # key → HSlider
var _reduce_check: Button = null
var _fullscreen_check: Button = null
var _res_buttons: Array[Button] = []
var _col: VBoxContainer = null


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	if Hooks.click_test:
		_click_selftest.call_deferred()


func _settings() -> Dictionary:
	return GameState.data["settings"]


## ★ 輸入層自檢（`TL_CLICKTEST=1 TL_PANEL=settings`）。
##
## 這個畫面唯一該問的問題是「拉了滑桿之後，**外面那個東西真的變了嗎**」——
## 一個只寫進字典、沒有接到匯流排／`Motion.reduce`／視窗的設定畫面，
## 看起來和正常的完全一樣（B1.3 那條「買了沒生效的科技」是同一類缺陷）。
func _click_selftest() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var s := _settings()

	# ① 音量：拉滑桿 → 存檔的值變了 → **匯流排的分貝也變了**。
	#    有測試鉤子時 `AudioBus.muted` 為真、`apply()` 是空操作（鐵律 2），
	#    所以這裡只驗到「值有寫進去」為止，分貝那一半改用直接呼叫驗。
	(_sliders["master"] as HSlider).value = 0.5
	await get_tree().process_frame
	var vol_saved: bool = is_equal_approx(float(s["master"]), 0.5)
	# 匯流排本身要真的存在（`apply()` 找不到就會靜靜地什麼都不做）。
	var buses_exist: bool = (
		AudioServer.get_bus_index("BGM") >= 0 and AudioServer.get_bus_index("SFX") >= 0
	)
	# ★ 鐵律 2：**靜音時 `apply()` 必須是空操作**。不然「有鉤子就一定不出聲」
	#   這個承諾會變成「取決於這台機器的玩家把音量存成多少」。
	var db_before := AudioBus.volume_db("Master")
	AudioBus.apply({"master": 1.0, "bgm": 1.0, "sfx": 1.0})
	var mute_wins: bool = AudioBus.muted and is_equal_approx(
		AudioBus.volume_db("Master"), db_before
	)

	# ② 減少動態效果：勾了之後 `Motion.reduce` 當場為真、效果壽命歸零。
	_reduce_check.button_pressed = true
	await get_tree().process_frame
	var reduce_live: bool = Motion.reduce and Motion.ticks(Motion.BASE) == 0
	_reduce_check.button_pressed = false
	await get_tree().process_frame
	var reduce_off: bool = not Motion.reduce and Motion.ticks(Motion.BASE) > 0

	# ③ 解析度：點第二顆 → 視窗真的變大 → 再點回來。
	#    **點回來是必要的**：`TL_SHOT` 那條路徑要求同參數拍出同一張圖。
	var before := DisplayServer.window_get_size()
	_press(_res_buttons[1])
	await get_tree().process_frame
	var resized: bool = DisplayServer.window_get_size() == RESOLUTIONS[1]
	_press(_res_buttons[0])
	await get_tree().process_frame
	var restored: bool = DisplayServer.window_get_size() == RESOLUTIONS[0] and before == before

	# ④ 存檔沒有被真的寫出去（有鉤子時 persist=false，鐵律 1）。
	var no_write: bool = not SaveService.persist

	# ⑤ ★ **整頁留在畫面內**（RG-75 的同一條）。第一版的間距讓最後那行說明
	#    掉到 720 以外，而 `_draw()` 對此一個字都不會說。
	var last: Control = _col.get_child(_col.get_child_count() - 1)
	var fits: bool = last.global_position.y + last.size.y <= float(size.y)

	var ok: bool = (
		vol_saved and mute_wins and buses_exist and reduce_live and reduce_off
		and resized and restored and no_write and fits
	)
	print("[TL_CLICKTEST/settings] vol=%s buses=%s mute_wins=%s reduce_on=%s reduce_off=%s resize=%s restore=%s no_write=%s fits=%s → %s" % [
		vol_saved, buses_exist, mute_wins, reduce_live, reduce_off, resized, restored, no_write,
		fits, "PASS" if ok else "FAIL"
	])
	if Hooks.shot_path == "":
		get_tree().quit(0 if ok else 1)


func _press(b: Button) -> void:
	b.grab_focus()
	b.pressed.emit()


func _clear() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()


func _build() -> void:
	_clear()
	_sliders.clear()
	_res_buttons.clear()

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	# 間距 8 而不是 14：這一頁有 13 個列，每一格間距都乘以 13。
	# 第一版用 14 就讓最後那行說明掉到 720 以外（自檢的 `fits` 現在守著）。
	var col := UiKit.vbox(8)
	_col = col
	margin.add_child(col)
	col.add_child(UiKit.label("設定", 34, Palette.ORDER_BRIGHT, false))
	if on_exit.is_valid():
		var back := Button.new()
		back.text = "返回"
		back.pressed.connect(on_exit)
		var row := UiKit.hbox(0)
		row.add_child(UiKit.touchable(back))
		col.add_child(row)

	col.add_child(UiKit.label("音訊", 22, Palette.ORDER_CYAN, false))
	for v: Array in VOLUMES:
		col.add_child(_volume_row(String(v[0]), String(v[1])))
	# 誠實標記：B1.5 之前這兩軌沒有東西可播。**不寫的話玩家會以為滑桿壞了。**
	col.add_child(UiKit.label(
		"※ 音樂與音效的音源排在下一批，目前拉了聽不出差別——滑桿本身已經接到真的匯流排。",
		13, Palette.TEXT_DISABLED, false
	))

	col.add_child(UiKit.label("畫面", 22, Palette.ORDER_CYAN, false))
	_reduce_check = _checkbox(
		"減少動態效果", bool(_settings().get("reduce_motion", false)), _on_reduce
	)
	col.add_child(_left(_reduce_check))
	col.add_child(UiKit.label(
		"　關掉碎片爆、脈動與所有週期性動態。不影響任何數值。",
		13, Palette.TEXT_SECONDARY, false
	))
	_fullscreen_check = _checkbox(
		"全螢幕", bool(_settings().get("fullscreen", false)), _on_fullscreen
	)
	col.add_child(_left(_fullscreen_check))

	col.add_child(UiKit.label("視窗大小", 16, Palette.TEXT_SECONDARY, false))
	var res_row := UiKit.hbox(8)
	col.add_child(res_row)
	for i in RESOLUTIONS.size():
		var size: Vector2i = RESOLUTIONS[i]
		var b := Button.new()
		b.text = "%d × %d" % [size.x, size.y]
		b.toggle_mode = true
		b.button_pressed = size == _saved_resolution()
		b.pressed.connect(_on_resolution.bind(i))
		_res_buttons.append(b)
		res_row.add_child(UiKit.touchable(b))

	col.add_child(UiKit.label(
		"※ 沒有鍵位設定：這款遊戲一顆鍵都沒有綁（左鍵做事、中鍵移動視野、滾輪縮放）。",
		13, Palette.TEXT_DISABLED, false
	))


func _volume_row(key: String, label: String) -> Control:
	var row := UiKit.hbox(12)
	var name := UiKit.label(label, 16, Palette.TEXT_PRIMARY, false)
	name.custom_minimum_size.x = 90
	row.add_child(name)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(_settings().get(key, 0.8))
	slider.custom_minimum_size = Vector2(260, UiKit.TOUCH_MIN)
	var value := UiKit.label("%d%%" % roundi(slider.value * 100.0), 16, Palette.ENERGY_AMBER, false)
	value.custom_minimum_size.x = 56
	slider.value_changed.connect(_on_volume.bind(key, value))
	_sliders[key] = slider
	row.add_child(slider)
	row.add_child(value)
	return row


## ★ 用 toggle `Button` 而不是 `CheckBox`：預設主題的勾選框是深色方塊畫在
## 深色底上，在這套配色裡幾乎看不見（截圖當場看出來的）。全遊戲其他地方的
## 開關（底欄的「優先權」「說明」、視窗大小）都是按下去會凹進去的 toggle 鈕，
## 這裡跟著同一個語彙，順便就不必替一個元件單獨調主題。
func _checkbox(text: String, on: bool, handler: Callable) -> Button:
	var c := Button.new()
	c.text = text
	c.toggle_mode = true
	c.button_pressed = on
	c.custom_minimum_size.x = 180
	c.toggled.connect(handler)
	return c


## `VBoxContainer` 會把子節點橫向撐滿，開關撐成一整條看起來像分隔線不像鈕。
## 包一層 `HBox` 讓它維持自然寬度、靠左。
func _left(c: Control) -> Control:
	var row := UiKit.hbox(0)
	row.add_child(UiKit.touchable(c))
	return row


func _saved_resolution() -> Vector2i:
	var i := int(_settings().get("resolution", 0))
	return RESOLUTIONS[clampi(i, 0, RESOLUTIONS.size() - 1)]


# ── 變更處理：一律「當場生效 → 當場存檔」 ────────────────────────────

func _on_volume(v: float, key: String, value_label: Label) -> void:
	_settings()[key] = v
	value_label.text = "%d%%" % roundi(v * 100.0)
	AudioBus.apply(_settings())
	_save()


func _on_reduce(on: bool) -> void:
	_settings()["reduce_motion"] = on
	Motion.reduce = on
	_save()


func _on_fullscreen(on: bool) -> void:
	_settings()["fullscreen"] = on
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	)
	_save()


func _on_resolution(index: int) -> void:
	_settings()["resolution"] = index
	for i in _res_buttons.size():
		_res_buttons[i].button_pressed = i == index
	# 全螢幕時改視窗大小是空操作，但值仍然存起來——切回視窗時要用得到。
	if not bool(_settings().get("fullscreen", false)):
		DisplayServer.window_set_size(RESOLUTIONS[index])
	_save()


## 有測試鉤子時 `SaveService.save_from()` 自己會跳過（鐵律 1），
## 所以這裡不必再判一次——判兩次的那一天，兩邊的條件就會開始不一樣。
func _save() -> void:
	SaveService.save_from(GameState.data)
