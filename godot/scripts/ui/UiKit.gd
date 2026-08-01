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
