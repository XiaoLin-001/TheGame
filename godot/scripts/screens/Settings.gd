extends Control
## 設定畫面（B1.4、`10_GDD.md` §6.2）。
##
## 三條紀律：
##   ① **改了當場生效**，不要「套用」鈕。滑桿拉到一半才知道結果的音量沒有意義。
##   ② **當場存檔**。改完設定又忘了存的那一個玩家，下次開遊戲會以為設定壞了。
##   ③ **不做鍵位設定**。這款遊戲只綁了一顆鍵（ESC ＝ 選單／返回），
##      做一個空的鍵位表只是把「還沒有的東西」畫出來給人看。B1.4 的 DoD 列了
##      鍵位，這裡誠實地不做，理由記在 `40_PRODUCTION_PLAN.md` 的完工證據。

const Motion := preload("res://scripts/render/Motion.gd")

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
	# ★ `and Hooks.panel == "settings"`：本畫面也會被**局內選單**當浮層開起來
	#   （B1.4.1）。少了這一條，`TL_CLICKTEST=1`（局內）一開設定就會跑到這支
	#   自檢的 `get_tree().quit()`，把別人的自檢從中間打斷成「PASS」。
	if Hooks.click_test and Hooks.panel == "settings":
		Hooks.run_selftest(self)


## ESC ＝ 返回上一層。全遊戲每個有「返回」的畫面都接同一條（B1.4.1）。
func _unhandled_key_input(event: InputEvent) -> void:
	UiKit.esc_returns(self, event, on_exit)


func _settings() -> Dictionary:
	return GameState.data["settings"]


func _build() -> void:
	UiKit.clear(self)
	_sliders.clear()
	_res_buttons.clear()

	# 間距 8 而不是 14：這一頁有 13 個列，每一格間距都乘以 13。
	# 第一版用 14 就讓最後那行說明掉到 720 以外（自檢的 `fits` 現在守著）。
	var col := UiKit.screen(self, 8)
	_col = col
	col.add_child(UiKit.label("設定", 32, Palette.ORDER_BRIGHT, false))
	var nav := UiKit.back_row("返回", on_exit, 0)
	if nav != null:
		col.add_child(nav)

	col.add_child(UiKit.label("音訊", 22, Palette.ORDER_CYAN, false))
	for v: Array in VOLUMES:
		col.add_child(_volume_row(String(v[0]), String(v[1])))
	col.add_child(UiKit.label(
		"※ 音樂分兩層：準備期只有底層，開打時打擊層淡入。",
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
	for i in SaveService.RESOLUTIONS.size():
		var size: Vector2i = SaveService.RESOLUTIONS[i]
		var b := Button.new()
		b.text = "%d × %d" % [size.x, size.y]
		b.toggle_mode = true
		b.button_pressed = size == _saved_resolution()
		b.pressed.connect(_on_resolution.bind(i))
		_res_buttons.append(b)
		res_row.add_child(UiKit.touchable(b))

	col.add_child(UiKit.label(
		"※ 只有一顆鍵：ESC ＝ 選單／返回。其餘操作都在滑鼠上。",
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
	return SaveService.RESOLUTIONS[clampi(i, 0, SaveService.RESOLUTIONS.size() - 1)]


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
		DisplayServer.window_set_size(SaveService.RESOLUTIONS[index])
	_save()


## 有測試鉤子時 `SaveService.save_from()` 自己會跳過（鐵律 1），
## 所以這裡不必再判一次——判兩次的那一天，兩邊的條件就會開始不一樣。
func _save() -> void:
	SaveService.save_from(GameState.data)
