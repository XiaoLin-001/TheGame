extends Node
## 藍圖庫（`10_GDD.md` §3.7、§7.12；B2.3）：框選存藍圖、一鍵展開、成本預估與逐格缺口提示。
##
## 位置在畫面左中——優先權面板在 (128, 380)、能量面板在右上、提示列在底邊，這一塊是剩下唯一
## 放得下一張清單的地方（位置是**擠出來的**，不是挑出來的）。

const BuildController := preload("res://scripts/game/BuildController.gd")
const Blueprint := preload("res://scripts/sim/Blueprint.gd")
const Tech := preload("res://data/Tech.gd")

## 擁有這個模組的局內畫面（`screens/Battle.gd`）。由它在建立時指派。
var scr: Control = null
## 局的狀態（與 `scr.s` 同一個物件；換局時由畫面重新指派）。
var s: RefCounted = null


var bp_panel: PanelContainer = null


## ★ 依**節點類型**的優先權面板（`10_GDD.md` §3.1）。
##
## 三件事是設計鎖死的，不要「順手」改掉：
##   ① **列固定、順序固定**（`NodeDefs.PRIORITY_ROWS`）——不可暫停的戰術動作
##      必須是一個手勢；滑桿會跑位就不是手勢了。
##   ② **沒有「每一座」的選項**——操作負擔不得隨建築數量成長（風險 R-1）。
##   ③ 預設收合。它是抽屜不是常駐欄（§6.2 全畫面地圖 ＋ 可收合浮層）。
## ★ 藍圖抽屜（B2.3）。位置在畫面左中——優先權面板在 (128, 380)、
## 能量面板在右上、提示列在底邊，這一塊是剩下唯一放得下一張清單的地方。
## 底欄的抽屜開關。
func make_toggle() -> Button:
	# ★ 藍圖庫（B2.3）。放底欄抽屜而不是左欄：左欄的八種節點加動作鈕已經
	#   吃掉 380px，而藍圖是**每局用一兩次**的東西，不該和每秒都在點的建造欄搶位置。
	var bp_btn := Button.new()
	bp_btn.text = "藍圖"
	bp_btn.toggle_mode = true
	bp_btn.toggled.connect(on_toggle_blueprint)
	return bp_btn


func build_panel() -> void:
	var box := UiKit.panel()
	# 位置是**擠出來的**，不是挑出來的：優先權面板佔 128..510、能量面板佔
	# 872..1264、圖鑑浮層下緣到 320、提示列從 660 起——中間這一塊是唯一
	# 能讓三張浮層同時開又互不相疊的地方。
	# 第一版放 (128, 150)，於是被圖鑑整個蓋住（截圖抓到，文字從圖鑑後面透出來）。
	box.position = Vector2(560, 400)
	box.visible = false
	box.add_child(UiKit.vbox(4))
	scr.add_child(box)
	bp_panel = box
	refresh_blueprints()


# ── 藍圖庫（B2.3、`10_GDD.md` §3.7）───────────────────────────────────

## 這一份存檔有幾個槽。**吃的是玩家的科技，不是這一局的 `s.mods`**——
## 藍圖庫是跨局資產（§3.7），而每日挑戰的統一配置榜會把 `s.mods` 壓成中性值
## （憲法 B3）。用 `s.mods` 的話，打統一配置榜時玩家的槽會憑空少兩個。
func _bp_slots() -> int:
	var unlocked: Array = (GameState.data.get("tech", {}) as Dictionary).get("unlocked", [])
	return Blueprint.slots(Tech.mods(unlocked))


func blueprints() -> Array:
	return GameState.data.get("blueprints", [])


## 框選存檔。
func save_blueprint(a: Vector2i, b: Vector2i) -> void:
	var bp := Blueprint.capture(s.nodes, s.conduits, a, b)
	var err := SaveService.add_blueprint(GameState.data, bp, _bp_slots())
	if err != "":
		scr.message = err
		return
	SaveService.save_from(GameState.data)
	var cost: Dictionary = Blueprint.cost(bp)
	scr.message = "✔ 已存為藍圖　%d 節點・%d 導管　展開要 %d 礦砂" % [
		(bp["nodes"] as Array).size(), (bp["conduits"] as Array).size(), int(cost["ore"])
	]
	refresh_blueprints()


## 把手上那張藍圖放在 `cell`。**全有全無**（`BuildController.blueprint_place`）。
func expand_blueprint(cell: Vector2i) -> void:
	var list := blueprints()
	if scr.bp_index < 0 or scr.bp_index >= list.size():
		scr.bp_index = -1
		return
	var err := BuildController.blueprint_place(s, list[scr.bp_index], cell)
	if err != "":
		scr.message = err
		return
	AudioBus.play("build_place")
	# 放完就放下它。**不留在手上**：藍圖是「一次把一整條產線種下去」，
	# 連放兩次的自然結果是兩份重疊在一起而第二份整份失敗。
	scr.bp_index = -1
	scr.message = "✔ 藍圖已展開"
	refresh_blueprints()
	scr.redraw()


func on_toggle_blueprint(open: bool) -> void:
	bp_panel.visible = open
	if open:
		refresh_blueprints()


## 重畫藍圖抽屜。列出每一張的名字、成本，以及兩顆鈕（展開／刪除）。
func refresh_blueprints() -> void:
	if bp_panel == null:
		return
	var col: VBoxContainer = bp_panel.get_child(0)
	UiKit.clear(col)
	var list := blueprints()
	col.add_child(UiKit.label(
		"藍圖庫　%d／%d 槽" % [list.size(), _bp_slots()], 16, Palette.TEXT_PRIMARY, false
	))
	col.add_child(UiKit.label(
		"框選：切「藍圖」→ 在地圖上按住拖出一個框",
		13, Palette.TEXT_SECONDARY, false
	))
	if list.is_empty():
		col.add_child(UiKit.label("（尚無藍圖）", 13, Palette.TEXT_SECONDARY, false))
		return
	for i in list.size():
		var bp: Dictionary = list[i]
		var cost: Dictionary = Blueprint.cost(bp)
		var row := UiKit.hbox(6)
		col.add_child(row)
		# 成本寫在清單上，**不是等玩家點下去才知道**（§3.7「自動計算成本」）。
		var alloy_part := "" if int(cost["alloy"]) <= 0 else "・%d 合金" % int(cost["alloy"])
		row.add_child(UiKit.label("%s　%d 礦砂%s" % [
			String(bp.get("name", "")), int(cost["ore"]), alloy_part
		], 13, Palette.TEXT_PRIMARY, false))
		var take := Button.new()
		take.text = "放下" if scr.bp_index == i else "展開"
		take.pressed.connect(_on_take_blueprint.bind(i))
		row.add_child(UiKit.touchable(take))
		var del := Button.new()
		del.text = "刪除"
		del.pressed.connect(_on_delete_blueprint.bind(i))
		row.add_child(UiKit.touchable(del))


func _on_take_blueprint(i: int) -> void:
	# 再按一次＝放下。拿著藍圖時左鍵會展開它，沒有取消的手勢就等於卡住。
	scr.bp_index = -1 if scr.bp_index == i else i
	if scr.bp_index >= 0:
		scr.mode = scr.Mode.BUILD
		scr.message = "藍圖在手上：左鍵點地圖放下它（再按一次「放下」取消）"
	refresh_blueprints()
	scr.redraw()


func _on_delete_blueprint(i: int) -> void:
	var list := blueprints()
	if i < 0 or i >= list.size():
		return
	list.remove_at(i)
	GameState.data["blueprints"] = list
	SaveService.save_from(GameState.data)
	scr.bp_index = -1
	refresh_blueprints()
