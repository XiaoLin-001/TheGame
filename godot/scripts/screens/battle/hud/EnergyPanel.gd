extends Node
## 能量收支面板（`10_GDD.md` §6.2）：供給、儲槽放電、回收、各類耗能、淨值，以及餵不飽的節點。
##
## **列數與順序恆定**（`ENERGY_ROWS`），沒有值的列留在原位變暗——面板才不會每個 tick 抖一次（B0.7.4）。

const Stage := preload("res://scripts/screens/battle/Stage.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")

## 擁有這個模組的局內畫面（`screens/Battle.gd`）。由它在建立時指派。
var scr: Control = null
## 同伴模組（Stage）。
var stage: Stage = null
## 局的狀態（與 `scr.s` 同一個物件；換局時由畫面重新指派）。
var s: RefCounted = null


## 能量收支面板的**固定列序**。列數與順序恆定，沒有值的列留在原位變暗，
## 面板才不會每個 tick 抖一次（B0.7.4）。`short0..2` 是餵不飽的節點清單。
const ENERGY_ROWS := [
	"gen", "silo_out", "reclaim", "sep1", "tower", "smelt", "silo_in", "silo_store", "sep2", "net",
	"short0", "short1", "short2", "tip", "tip2",
]

## 「餵不飽」最多列幾座，其餘收成一行「…還有 N 座」。
const SHORT_ROWS := 3

var energy_panel: Control = null

var energy_button: Button = null

var energy_rows: Dictionary = {}


## ★ 能量收支面板（使用者要求：「不太清楚怎樣的操作可以讓能量增加、哪些會減少」）。
##
## 頂欄的能量條說的是**結果**（供給 30／需求 37），它不說「這 37 是誰吃的」。
## 這張表把每一項逐條攤開並**即時跟著跑**，所以它同時是答案與教材：
## 玩家蓋一台發電機，`+` 那一欄當場多 20——因果在同一個畫面上發生。
##
## 只列**這一局真的存在**的項目：一張永遠有八行的表沒有資訊量，
## 有幾行會動、什麼時候動，本身就是資訊。
## 底欄的抽屜開關。
func make_toggle() -> Button:
	energy_button = Button.new()
	energy_button.text = "能量"
	energy_button.toggle_mode = true
	energy_button.toggled.connect(on_toggle_energy)
	return energy_button


func build_panel() -> void:
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
	scr.add_child(box)
	energy_panel = box


func on_toggle_energy(open: bool) -> void:
	energy_panel.visible = open


func refresh_energy() -> void:
	if energy_panel == null or not energy_panel.visible:
		return
	var r: Dictionary = s.rates
	var gen := 0.0
	var reclaim := 0.0
	var tower := 0.0
	# 熔爐的耗能**不能併進任何一列既有的**：它既不是交戰耗能（待機也吃），
	# 也不是儲槽充能。B1.1 之前 `silo_in = demand − tower` 會把熔爐那 10/秒
	# 記到儲槽頭上——面板從此開始說謊。
	var smelt := 0.0
	for n: Dictionary in s.nodes:
		var def := NodeDefs.of(String(n["type"]))
		gen += float(def.get("power_out", 0.0)) * float((r["satisfaction"] as Dictionary).get(n["id"], 1.0))
		if def.has("reclaim"):
			reclaim += float(n["buffer"])
		smelt += float(def.get("power_in", 0.0))
		if stage.engaged.get(int(n["id"]), false):
			tower += float(def.get("engage_power", 0.0))
	var supply := float(r["power_supply"])
	var demand := float(r["power_demand"])
	var silo_out := maxf(0.0, supply - gen)
	var silo_in := maxf(0.0, demand - tower - smelt)
	var net := supply - demand

	_set_row("gen", "＋ 發電機 ×%d　%+.0f" % [s.count_of("generator"), gen],
		gen > 0.05, Palette.ENERGY_AMBER)
	_set_row("silo_out", "＋ 儲槽放電　%+.0f" % silo_out, silo_out > 0.05, Palette.ENERGY_AMBER)
	_set_row("reclaim", "＋ 回收者存量　%.0f（擊殺換來的，限速注入）" % reclaim,
		reclaim > 0.05, Palette.ENERGY_AMBER)
	_set_row("sep1", "─────────────────", false)
	_set_row("tower", "− 塔（交戰 %d 座）　%.0f" % [int(r["engaged"]), tower], tower > 0.05)
	_set_row("smelt", "− 熔爐 ×%d　%.0f（待機也吃）" % [s.count_of("smelter"), smelt],
		smelt > 0.05)
	_set_row("silo_in", "− 儲槽充能　%.0f（受自己那條線限速）" % silo_in, silo_in > 0.05)
	# ★ 儲槽**存量**（B2.4.4）。它原本掛在頂欄，而頂欄的三階層次容不下 11 個
	#   數字（§2 反模式：每畫面最多 4 個主要數字）。搬到這裡而不是刪掉：
	#   這一格是「充放電」那兩列的分母，放在它們旁邊比放在頂欄更講得通。
	#   ★ **每一顆儲槽自己身上還有一圈琥珀弧**，所以「哪一顆滿了」在地圖上讀得到，
	#     頂欄少的只是那個總和數字。
	_set_row("silo_store", "　　儲槽存量　%.0f/%.0f" % [r["silo_charge"], r["silo_capacity"]],
		float(r["silo_capacity"]) > 0.05, Palette.ENERGY_AMBER)
	_set_row("sep2", "─────────────────", false)

	# ★ 「誰餵不飽」（使用者要求）。淨值只說「差多少」，不說「誰在挨餓」——
	#   而玩家能採取的動作（拉優先權、加粗那條線、多蓋一台發電機）取決於後者。
	#   名單直接取三態徽章的 `STARVED`，與地圖上的橙色倒三角是同一份判定。
	var short_list: Array[String] = []
	var states: Dictionary = r["node_state"]
	for n: Dictionary in s.nodes:
		# ★ `is_starved()` 而不是 `== STARVED`（B2.4.8）：缺料分成礦／電兩態之後，
		#   寫死等號的地方會安靜地漏掉一半的節點——而「安靜地漏掉」正是這一整批
		#   在修的東西。
		if not SessionState.is_starved(int(states.get(int(n["id"]), 0))):
			continue
		short_list.append("%s%s %.0f%%" % [
			NodeDefs.label(String(n["type"])), n["cell"],
			100.0 * float((r["satisfaction"] as Dictionary).get(n["id"], 1.0))
		])

	var ok_all := short_list.is_empty()
	_set_row("net", "淨值　%+.0f/秒　%s" % [net, "餵得飽" if ok_all else "有東西在挨餓"], true,
		Palette.OK_GREEN if ok_all else Palette.WARN_ORANGE)
	for i in SHORT_ROWS:
		var key := "short%d" % i
		if ok_all:
			_set_row(key, "　全部餵得飽" if i == 0 else "", false)
		elif i == SHORT_ROWS - 1 and short_list.size() > SHORT_ROWS:
			_set_row(key, "　…還有 %d 座" % (short_list.size() - SHORT_ROWS + 1), true,
				Palette.WARN_ORANGE)
		elif i < short_list.size():
			_set_row(key, "　餵不飽：" + short_list[i] if i == 0 else "　　　　　" + short_list[i],
				true, Palette.WARN_ORANGE)
		else:
			_set_row(key, "", false)

	_set_row("tip", "加電：多蓋發電機（每台吃 4 礦砂/秒）", false)
	_set_row("tip2", "省電：塔少一點，或用「優先權」決定誰先餓", false)


## `live` ＝ 這一項現在有沒有在作用。**沒作用的列不隱藏、只變暗**——
## 隱藏會讓下面每一列往上跳，而一張一直在動的表讀不了（B0.7.4）。
func _set_row(key: String, text: String, live: bool, col: Color = Palette.TEXT_SECONDARY) -> void:
	var l: Label = energy_rows[key]
	l.text = text
	l.add_theme_color_override("font_color", col if live else Palette.TEXT_DISABLED)


## 本 tick 每條導管的**能量**淨流（沿 a→b 為正）。
func energy_net() -> Dictionary:
	var out: Dictionary = {}
	for c: Dictionary in s.conduits:
		var v: Vector3 = (s.rates["conduit_net"] as Dictionary).get(c["id"], Vector3.ZERO)
		out[c["id"]] = v.y
	return out


## 會發電的那些格（發電機、放電中的儲槽、回收者的緩衝）。
func power_sources() -> Dictionary:
	var out: Dictionary = {}
	for n: Dictionary in s.nodes:
		var d := NodeDefs.of(String(n["type"]))
		if float(d.get("power_out", 0.0)) > 0.0 or String(n["type"]) in ["silo", "reclaimer"]:
			out[n["cell"]] = true
	return out
