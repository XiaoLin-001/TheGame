class_name UiKit
extends RefCounted
## 共用 UI helper（全 static）。
##
## 兩件它必須負責的事：
##   1. **CJK 字型**——Godot 預設字型不含中文，直接用會變豆腐字。全專案一律
##      走這裡的 SystemFont，不得改回預設字型（30_TECH_DESIGN.md §4.3 地雷 3）。
##   2. **手機移植預留條款**（20_ART_DIRECTION.md §1.3b）——版面一律用容器與
##      錨點，不硬編碼像素位置（P1）；可點元素命中區 ≥ 44×44（P2）。

## 觸控命中區下限（P2）。視覺可以更小，命中區不行。
const TOUCH_MIN := 44.0

const FONT_NAMES := [
	"Microsoft JhengHei",  # Windows 繁中主力
	"Noto Sans TC",
	"Microsoft YaHei",
	"PingFang TC",         # macOS fallback
	"sans-serif",
]

static var _theme: Theme = null


## 全專案共用主題。在畫面的根 Control 設一次，子節點自動繼承。
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var f := SystemFont.new()
	f.font_names = PackedStringArray(FONT_NAMES)
	_theme = Theme.new()
	_theme.default_font = f
	_theme.default_font_size = 16
	return _theme


static func label(text: String, size: int, color: Color, centered: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func vbox(separation: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


## 讓任何 Control 滿足 P2 的最小命中區。所有互動元件都應該經過這裡。
static func touchable(c: Control) -> Control:
	c.custom_minimum_size = Vector2(
		maxf(c.custom_minimum_size.x, TOUCH_MIN),
		maxf(c.custom_minimum_size.y, TOUCH_MIN)
	)
	# ★ 點擊音接在這裡（B1.5）。全遊戲每一顆鈕都經過 `touchable()`，所以這是
	#   唯一一個接得完的地方——逐一在各畫面連 `pressed` 的那條路，漏掉的那幾顆
	#   鈕會安靜到沒有人發現。
	var b := c as Button
	if b != null:
		b.pressed.connect(func() -> void: AudioBus.play("ui_click"))
	return c


## 浮層容器。**預設的 `PanelContainer` 背景太透**，蓋在地圖上時導管會從字後面
## 穿過去，暗色的次要文字直接讀不到（B0.7.4 使用者回報）。
## 這裡給一個近乎不透明的底 ＋ 一圈細邊，讓浮層與地圖分得開。
## `opacity` 留給角色簡介那種刻意要半透明的（它要讓人看見底下是什麼）。
static func panel(opacity: float = 0.96) -> PanelContainer:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.alpha(Palette.BG_PANEL, opacity)
	style.border_color = Palette.BORDER_STRONG
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)   # radius.ui（20_ART_DIRECTION.md §1.4）
	style.set_content_margin_all(10)
	box.add_theme_stylebox_override("panel", style)
	# 浮層是資訊不是障礙物：一律不吃滑鼠（RG-39）。
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


## ★ 清空一個節點的子節點（B1.9）。
##
## **`remove_child()` 要在 `queue_free()` 之前**：後者要到影格末才生效，中間那一幀
## 舊畫面還在畫、也還在吃滑鼠——關卡選擇會疊在戰場上（`Campaign._clear()` 的原註）。
## 這個順序在四個 screens 各寫過一份，而**只要有一份寫反就是一個看得到的閃爍**。
static func clear(node: Node) -> void:
	for c: Node in node.get_children():
		node.remove_child(c)
		c.queue_free()


## ★ ESC ＝ 返回上一層（B1.9）。回傳「我消費掉這個事件了嗎」。
##
## 全遊戲每個有「返回」的畫面接的都是同一條（B1.4.1），而它在
## Settings／Tech／Campaign 三個檔案裡是逐字相同的六行。三份的問題不是行數，
## 是**其中一份忘了 `set_input_as_handled()` 或忘了播 `ui_back` 也不會有人發現**。
##
## 局內畫面（`Battle`）**不走這裡**：它的 ESC 是開選單不是返回，而且要先讓路給
## 疊在上面的設定浮層——語意不同的東西不該共用一個入口。
static func esc_returns(node: Node, event: InputEvent, on_exit: Callable) -> bool:
	if not event.is_action_pressed("ui_cancel") or not on_exit.is_valid():
		return false
	node.get_viewport().set_input_as_handled()
	AudioBus.play("ui_back")   # ESC ＝ 取消手勢，全遊戲同一個音（B1.5）
	on_exit.call()
	return true


## ★ 自檢：「ESC 到得了這個畫面的處理器嗎」（B1.9）。
##
## **不能真的呼叫 `on_exit`**——那會把畫面拆掉，後面的 print 就落在一個正在被
## 釋放的節點上。所以暫時把它換成一個只翻旗標的 Callable：要驗的是**事件到不到
## 得了那支處理器**，不是返回本身。驗完換回來。
##
## 走 `Input.parse_input_event()` 的完整輸入管線，才驗得到「`ui_cancel` 這個
## action 真的對得上 ESC 鍵」——直接呼叫處理器兩件都驗不到。
##
## Settings 與 Tech 各寫過一份逐字相同的 14 行；`screen` 必須有 `on_exit` 欄位。
static func esc_reaches(screen: Node) -> bool:
	var real_exit: Callable = screen.on_exit
	var escaped := [false]
	screen.on_exit = func() -> void: escaped[0] = true
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		ev.pressed = pressed
		Input.parse_input_event(ev)
	for _i in 3:
		await screen.get_tree().process_frame
	screen.on_exit = real_exit
	return escaped[0]


## 千分位。資源數字到處都要用，統一在這裡免得各處各寫一份。
static func commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if n < 0 else out
