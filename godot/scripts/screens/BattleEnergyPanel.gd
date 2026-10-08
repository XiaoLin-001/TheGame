class_name BattleEnergyPanel
extends RefCounted
## 能量收支面板。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

const Readout := preload("res://scripts/game/Readout.gd")

## 能量收支面板的**固定列序**。列數與順序恆定，沒有值的列留在原位變暗，
## 面板才不會每個 tick 抖一次（B0.7.4）。`short0..2` 是餵不飽的節點清單。
const ENERGY_ROWS := [
	"gen", "silo_out", "reclaim", "sep1", "tower", "smelt", "silo_in", "silo_store", "sep2", "net",
	"short0", "short1", "short2", "tip", "tip2",
]

var energy_panel: Control = null

var energy_button: Button = null

var energy_rows: Dictionary = {}

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


## ★ 能量收支面板（使用者要求：「不太清楚怎樣的操作可以讓能量增加、哪些會減少」）。
##
## 頂欄的能量條說的是**結果**（供給 30／需求 37），它不說「這 37 是誰吃的」。
## 這張表把每一項逐條攤開並**即時跟著跑**，所以它同時是答案與教材：
## 玩家蓋一台發電機，`+` 那一欄當場多 20——因果在同一個畫面上發生。
##
## 只列**這一局真的存在**的項目：一張永遠有八行的表沒有資訊量，
## 有幾行會動、什麼時候動，本身就是資訊。
func build_energy_panel() -> void:
	var box := UiKit.panel()
	box.position = Vector2(872, 96)
	box.visible = false
	# ★ **固定尺寸、固定列數**（B0.7.4）。使用者回報「面板會因為一些小改動
	#   一直跳動，很難看清楚」——原因是沒有數值的列會自己隱藏，`PanelContainer`
	#   跟著縮放，於是每過一個 tick 版面就位移一次。
	#   **一張一直在動的表，讀不了**。現在列數恆定、寬度恆定，
	#   不存在的項目留在原位變暗——**位置固定本身就是可讀性**。
	# 320 ＝ 標題 ＋ 14 列 ×（17 ＋ 3）＋ 邊距。B1.1 多了「熔爐」一列。
	box.custom_minimum_size = Vector2(392, 320)
	var col := UiKit.vbox(3)
	box.add_child(col)
	col.add_child(UiKit.label("能量收支（每秒）", 16, Palette.ENERGY_AMBER, false))
	for key: String in ENERGY_ROWS:
		var l := UiKit.label("", 13, Palette.TEXT_SECONDARY, false)
		l.custom_minimum_size = Vector2(380, 17)
		col.add_child(l)
		energy_rows[key] = l
	battle.add_child(box)
	energy_panel = box


func on_toggle_energy(open: bool) -> void:
	energy_panel.visible = open


func refresh_energy() -> void:
	if energy_panel == null or not energy_panel.visible:
		return
	# 每一列寫什麼在核心層的 `Readout.energy_rows()`；這裡只把語意色翻成 Palette。
	for row: Array in Readout.energy_rows(battle.s, battle.engaged):
		_set_row(String(row[0]), String(row[1]), bool(row[2]), _tone_color(String(row[3])))


func _tone_color(tone: String) -> Color:
	match tone:
		"energy":
			return Palette.ENERGY_AMBER
		"warn":
			return Palette.WARN_ORANGE
		"ok":
			return Palette.OK_GREEN
	return Palette.TEXT_SECONDARY


## `live` ＝ 這一項現在有沒有在作用。**沒作用的列不隱藏、只變暗**——
## 隱藏會讓下面每一列往上跳，而一張一直在動的表讀不了（B0.7.4）。
func _set_row(key: String, text: String, live: bool, col: Color = Palette.TEXT_SECONDARY) -> void:
	var l: Label = energy_rows[key]
	l.text = text
	l.add_theme_color_override("font_color", col if live else Palette.TEXT_DISABLED)
