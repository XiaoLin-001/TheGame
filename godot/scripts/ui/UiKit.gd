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
	_style_buttons(_theme)
	return _theme


## ★ 按鈕的樣式（B2.9）。**全遊戲 41 顆鈕在這之前一顆都沒有套過美術 token**
## ——它們全是 Godot 的預設灰色方塊，而 `20_ART_DIRECTION.md` §1.1 的
## `bg.raised #162c3d` 那一列寫的就是「浮起元件（**按鈕**、卡片）」，
## §1.4 的 `radius.ui = 2` 寫的是「UI 面板與**按鈕**（僅此一種）」。
## 兩條 token 訂了三個月，沒有一顆鈕讀過它們。
##
## **設在主題上而不是逐顆設**：主題在每個畫面的根 Control 設一次、子節點自動繼承
## （`theme()` 的原註），所以這一支是唯一一個蓋得完 41 顆的地方——逐顆套的那條路，
## 漏掉的那幾顆會安靜地留著預設灰（`touchable()` 接點擊音的同一條理由）。
##
## 五態各有自己的樣子，因為**它們各自回答一個不同的問題**：
##   normal／hover ＝「這是可以按的」、pressed ＝「我按到了」、
##   disabled ＝「這顆現在不能按」（而它下面那行字會說為什麼）、
##   focus ＝ 鍵盤走到哪了（P3「操作不得只靠 hover」的另一半）。
static func _style_buttons(theme: Theme) -> void:
	for entry: Array in [
		# [態, 底色, 邊框色, 邊框寬]
		["normal", Palette.BG_RAISED, Palette.BORDER_SUBTLE, 1],
		["hover", Palette.BG_RAISED.lerp(Palette.ORDER_DIM, 0.35), Palette.BORDER_STRONG, 1],
		["pressed", Palette.BG_PANEL, Palette.ORDER_CYAN, 1],
		# 停用不是「暗一點的可按鈕」：**底色退回面板色、邊框近乎消失**，
		# 讓它在一排鈕裡看起來是凹下去的，而不是一顆比較暗的凸起。
		["disabled", Palette.alpha(Palette.BG_PANEL, 0.6), Palette.BORDER_SUBTLE, 1],
		# 聚焦框用 `stroke.emphasis`（§1.4 的 3）——它要在 hover 之上還看得出來。
		["focus", Palette.BG_RAISED.lerp(Palette.ORDER_DIM, 0.35), Palette.ORDER_BRIGHT, 3],
	]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = entry[1]
		sb.border_color = entry[2]
		sb.set_border_width_all(int(entry[3]))
		sb.set_corner_radius_all(2)      # radius.ui（§1.4「僅此一種」）
		# 間距階（§1.3）：**橫直都是 8**。
		#
		# ★ 第一版給了橫向 12，於是局內底欄那七顆鈕加起來寬了 56px，
		#   把提示文字整段推出視窗右緣（`Battle._place_hint()` 的 `hint_inside`
		#   當場變紅）。**按鈕的內距是一個全域尺寸**——在最擠的那個版面上才看得出
		#   它的代價，而最擠的那個版面是局內。
		sb.content_margin_left = 8.0
		sb.content_margin_right = 8.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		theme.set_stylebox(String(entry[0]), "Button", sb)
	for entry: Array in [
		["font_color", Palette.TEXT_PRIMARY],
		["font_hover_color", Palette.ORDER_BRIGHT],
		["font_pressed_color", Palette.ORDER_BRIGHT],
		["font_focus_color", Palette.TEXT_PRIMARY],
		["font_disabled_color", Palette.TEXT_DISABLED],
	]:
		theme.set_color(String(entry[0]), "Button", entry[1])


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
## 直向捲動區。四個畫面（成就／名冊／科技／訂單板）各寫一份逐字相同的四行，
## 而橫向捲動**一律關掉**是規則不是喜好：內容超出寬度時該換行，不該讓玩家去找
## 一條藏在右邊的捲軸。
static func scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return sc


## 合成一次 ESC（按下＋放開）。走 `Input.parse_input_event()` 的完整輸入管線，
## 才驗得到「`ui_cancel` 這個 action 真的對得上 ESC 鍵」與「事件真的傳到
## `_unhandled_key_input`」——直接呼叫處理器兩件都驗不到。
##
## 這六行曾經在 `UiKit` / `Battle` / `Campaign` / `Main` 各寫一份（同一個錯法
## 第二次：滑鼠那一份已經收在 `press()` 裡了）。
static func press_escape() -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		ev.pressed = pressed
		Input.parse_input_event(ev)


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
	press_escape()
	for _i in 3:
		await screen.get_tree().process_frame
	screen.on_exit = real_exit
	return escaped[0]


## ★ 自檢：合成一次真的滑鼠點擊（B2.7.2）。
##
## 不直接 `emit_signal("pressed")`：要驗的是**事件路由得到**，
## 而那正是 B0.7.2 静靜壞了五個批次的地方（`Callable.bind()` 綁錯位置
## 就是一顆按了沒反應的鈕，而 `_draw()` 一個字都不會說）。
##
## 這六行曾經在 `Main` / `Campaign` / `Roster` / `Tech` / `TycoonOrders`
## 各寫過一份，而且掛在三個不同的名字下（`_press` / `_click` / 直接內嵌）。
## ★ `Battle` 那份**不走這裡**：它要 `button_mask` 與滑鼠移動事件（拖曳），
##   是真的不一樣的東西——同 `esc_returns()` 不收局內畫面的同一條理由。
static func click(button: Button) -> void:
	# ★ **先把 tree 拿起來再送事件。** 這顆鈕很可能就是重建畫面的那一顆
	#   （`_unlock()` / `_assign()` / `_enter()` 都會 `_build()`），而重建會把它釋放
	#   ——事後再 `button.get_tree()` 就是「已釋放的實例」。舊的五份各自寫在畫面
	#   裡，`get_tree()` 問的是畫面（活著），所以搬進 `UiKit` 才暴露這一點。
	var tree := button.get_tree()
	var at := button.global_position + button.size * 0.5
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		Input.parse_input_event(ev)
	for _i in 4:
		await tree.process_frame


## ★ 一個全螢幕畫面的外框，回傳內容要放進去的那一欄（B2.7.2）。
##
## 六個畫面各寫過一份逐字相同的 margin 區塊。行數不是重點，
## 重點是 **24 是 `20_ART_DIRECTION.md` §1.3 的間距階**——六份各自寫死的話，
## 日後要改間距階就要改六個地方，而漏掉的那一個看起來完全正常。
static func screen(root: Control, separation: int = 12, pad: int = 24) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, pad)
	root.add_child(margin)
	var col := vbox(separation)
	margin.add_child(col)
	return col


## ★ 一列導覽鈕（返回…），B2.7.2。**一定包一層 `HBox`。**
##
## 直接丟進 `VBox` 的鈕會被拉成整個畫面寬。這不是假設性的：
## B2.5 的 `TycoonLines` 踩過一次（截圖抳到），而 B2.7.2 的 `/codebase-design`
## 審視又在 `DailyScreen` 找到一個**當時還活著的**（「返回標題」735px 寬）。
## 八顆鈕裡七顆包了、一顆沒包——**要記得的規矩會被忘記**，所以做成一支函式。
##
## 回傳那一列（呼叫端可以再往裡面加第二顆鈕）。`on_exit` 無效時回傳 `null`。
static func back_row(text: String, on_exit: Callable, separation: int = 12) -> HBoxContainer:
	if not on_exit.is_valid():
		return null
	var row := hbox(separation)
	var back := Button.new()
	back.text = text
	back.pressed.connect(on_exit)
	row.add_child(touchable(back))
	return row


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
