extends Node
## 依**節點類型**的優先權面板（`10_GDD.md` §3.1）。
##
## 三件事是設計鎖死的，不要「順手」改掉：
##   ① **列固定、順序固定**（`NodeDefs.PRIORITY_ROWS`）——不可暫停的戰術動作必須是一個手勢
##   ② **沒有「每一座」的選項**——操作負擔不得隨建築數量成長（風險 R-1）
##   ③ 預設收合。它是抽屜不是常駐欄（§6.2）

const NodeDefs := preload("res://data/NodeDefs.gd")
const BuildBar := preload("res://scripts/screens/battle/hud/BuildBar.gd")

## 擁有這個模組的局內畫面（`screens/Battle.gd`）。由它在建立時指派。
var scr: Control = null
## 局的狀態（與 `scr.s` 同一個物件；換局時由畫面重新指派）。
var s: RefCounted = null
## 同伴模組。
var buildbar: BuildBar = null


var prio_panel: Control = null

var prio_labels: Dictionary = {}


func build_priority_panel() -> void:
	var box := UiKit.panel()
	# B1.1 起 9 列：單欄 × 44px 觸控高度（手機移植前提，不能縮）放不進一屏，
	# 改**雙欄**——左生產、右防線（`NodeDefs.PRIORITY_SPLIT`），而那個分界
	# 正好就是這個面板在問的問題。
	#
	# 位置搬到畫面左下：能量面板佔右上（872..1264 × 96..416）、提示列佔
	# x ≥ 520 的底邊、底欄鈕佔 y ≥ 668——這一塊是唯一能讓兩張表同時開又
	# 互不相疊的地方。舊的 (1000, 330) 其實早就和能量面板疊了 66px。
	box.position = Vector2(128, 380)
	box.visible = false
	var outer := UiKit.vbox(4)
	box.add_child(outer)
	outer.add_child(UiKit.label("能量／礦砂不足時，誰先餓死", 13, Palette.TEXT_SECONDARY, false))
	var cols := UiKit.hbox(10)
	outer.add_child(cols)
	var lanes := [UiKit.vbox(4), UiKit.vbox(4)]
	cols.add_child(lanes[0])
	cols.add_child(lanes[1])
	# ★ 只列這一關蓋得出來的（核心永遠在，它不是玩家蓋的）。B1.2 起前幾關
	#   只解鎖四到六種節點，把另外五條永遠用不到的滑桿也列出來，就是把
	#   「這一格是我的戰術決定」稀釋成「這一排我看不懂」。**一局之內清單不變**，
	#   所以滑桿仍然恆在同一位置（R-1／R-15 要保的是那一件事）。
	# ★ 一列＝一個**角色的角色**，不是一個資料表的鍵（`NodeDefs.PRIORITY_GROUP`，
	#   B2.4）。長哨與定潮併進「錨」那一列、霜礁併進「潮鳴」那一列，所以滑桿數
	#   永遠是這九條的子集——M3 的 24 隻角色也不會讓這個面板長成一份表單（R-1）。
	var rows: Array = []
	for type: String in NodeDefs.PRIORITY_ROWS:
		if type == "core":
			rows.append(type)
			continue
		for member: String in NodeDefs.priority_members(type):
			if buildbar.buildable().has(member):
				rows.append(type)
				break
	var split := 0
	for type: String in rows:
		if NodeDefs.PRIORITY_ROWS.find(type) < NodeDefs.PRIORITY_SPLIT:
			split += 1
	for i in rows.size():
		var type := String(rows[i])
		var row := UiKit.hbox(4)
		var name_label := UiKit.label(NodeDefs.label(type), 13, Palette.TEXT_PRIMARY, false)
		name_label.custom_minimum_size = Vector2(52, 0)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_label)
		var down := Button.new()
		down.text = "◀"
		down.pressed.connect(_on_priority.bind(type, -1))
		row.add_child(UiKit.touchable(down))
		var value := UiKit.label("", 16, Palette.ENERGY_AMBER)
		value.custom_minimum_size = Vector2(24, 0)
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(value)
		prio_labels[type] = value
		var up := Button.new()
		up.text = "▶"
		up.pressed.connect(_on_priority.bind(type, 1))
		row.add_child(UiKit.touchable(up))
		(lanes[0] if i < split else lanes[1]).add_child(row)
	scr.add_child(box)
	prio_panel = box
	_refresh_priority()


## ★ 操作說明抽屜（`50_QA_PLAN.md` §4.4）。
##
## **它存在的理由是一句實測回饋**：使用者拿到 B0.7 的 build，第一句話是
## 「你沒教我要怎麼操作」。當時提示列只講「下一步的目標」，從頭到尾沒有任何
## 地方講過「蓋東西」＝左欄選一種、再左鍵點地圖——那是一條靠試錯才學得到的規則，
## 而試錯要花掉的正是那 60 秒準備期。
##
## **預設開在空地圖上、有東西之後就不再擋路**：不用存檔旗標（那要跨局狀態），
## 用「這一局蓋了東西沒有」判斷——玩家一放下第一個節點就代表他會操作了。
## 這張圖有幾座橋，說明就講幾座。零座也是一句有用的話——
## 「這一關不用擔心過路徑」本身就是關卡設計要傳達的訊息（§7.9 第 1 關）。
func bridge_line() -> String:
	var n: int = (s.sets["crossings"] as Dictionary).size()
	if n <= 0:
		return "　導管不能跨過敵人路徑（紫帶）。這張圖沒有橋，所有東西都在同一側"
	return "　導管要過敵人路徑（紫帶）只能走「橋」，也就是路徑上那 %d 段架高結構" % n


func on_toggle_priority(open: bool) -> void:
	prio_panel.visible = open


## 一條滑桿推的是**整列**（`NodeDefs.priority_members`，B2.4）。`FlowNetwork`
## 仍然逐 type 讀 `priorities[type]`——合併只發生在這裡，模擬層不知道有這回事。
func _on_priority(row: String, delta: int) -> void:
	for type: String in NodeDefs.priority_members(row):
		s.priorities[type] = clampi(
			int(s.priorities.get(type, 1)) + delta, NodeDefs.PRIORITY_MIN, NodeDefs.PRIORITY_MAX
		)
	_refresh_priority()


## TL_NAKED 明文包含「優先權面板刻度」（`30_TECH_DESIGN.md` §4.1）：
## 刻度是數值標籤，改用琥珀小方塊表示同一個 1–5，形狀仍讀得出高低。
func _refresh_priority() -> void:
	for type: String in prio_labels:
		var v := int(s.priorities.get(type, 1))
		(prio_labels[type] as Label).text = "▪".repeat(v) if Hooks.naked else str(v)
