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
	return c


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
