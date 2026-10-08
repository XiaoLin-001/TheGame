class_name BattleInspectPanel
extends RefCounted
## 檢視面板：被選取的建築或導管的當下數據、升級與拆除。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

const Build := preload("res://scripts/sim/Build.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const Readout := preload("res://scripts/game/Readout.gd")

var inspect_panel: Control = null

var inspect_label: Label = null

## ★ 檢視面板上的兩顆動詞鈕（B3.7）。升級／加粗共用一顆——選的是什麼就升什麼。
var inspect_up: Button = null

var inspect_del: Button = null

## ★ B3.7：面板底下多兩顆鈕（升級／加粗、拆除）。
##
## 動詞跟著**被選中的那個東西**走，不再跟著模式走。原本要動一座塔得先去底欄按
## 「升級」、點它、再按回來——三步裡有兩步不是決定。現在點它就看得到它，
## 而它能做的兩件事就寫在旁邊。
##
## ⚠ `UiKit.panel()` 是 `MOUSE_FILTER_IGNORE`（RG-39：浮層是資訊不是障礙物），
##   但那只管容器自己——Godot 的命中測試照樣會走進子節點，所以鈕收得到點擊，
##   而鈕以外的地方仍然穿透到底下的地圖。
## 檢視面板的固定寬高（B3.9.1）。**位置只能是離散狀態的函式**——見 `_place_inspect`。
## `INSPECT_MAX_H` 是它最高的樣子（導管面板量到 342），只拿來判避讓。
const INSPECT_W := 383.0

const INSPECT_MAX_H := 360.0

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


func build_inspect_panel() -> void:
	# ★ B3.7 起用標準不透明度（0.96），不再是角色簡介那種半透明。
	# 半透明的理由是「讓玩家看見底下是什麼」，而這個面板底下不是它要講的東西
	# ——被選取的那一格與供電來源都在畫面另一邊。加了兩顆鈕之後代價更明顯：
	# 節點圖形從字和鈕後面透出來，而**可以按的東西要讀起來是實心的**。
	var box := UiKit.panel()
	box.visible = false
	var col := UiKit.vbox(8)
	# ⚠ **內層容器要一起穿透**。`UiKit.panel()` 自己是 `MOUSE_FILTER_IGNORE`
	#   （RG-39：浮層是資訊不是障礙物），但 `Container` 預設是 `STOP`——面板底下
	#   那一塊地圖於是點不到也拖不動。B3.9.1 把面板挪到畫面中段之後這件事才要緊。
	#   兩顆鈕仍是 `STOP`（它們就是要點的東西）。
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspect_label = UiKit.label("", 13, Palette.TEXT_PRIMARY, false)
	# ★ 356 ＝ 量到的最長一行。**不開 autowrap**：這些行是設計成單行的，折行會讓
	#   面板從 258 長到 552，一個蓋住半張地圖的浮層比它要修的位移更糟。
	inspect_label.custom_minimum_size.x = 356.0
	col.add_child(inspect_label)
	var row := UiKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspect_up = Button.new()
	inspect_up.pressed.connect(_on_inspect_upgrade)
	inspect_del = Button.new()
	inspect_del.pressed.connect(_on_inspect_demolish)
	for b: Button in [inspect_up, inspect_del]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(UiKit.touchable(b))
	col.add_child(row)
	box.add_child(col)
	battle.add_child(box)
	inspect_panel = box


## 被選取那條導管在 `s.conduits` 裡的索引。找不到（被拆了、被敵人啃斷了）回 −1。
##
## 每次都重找而不是記索引——理由寫在 `_sel_wire` 的宣告上。線性掃：一局的導管
## 是幾十條，而這只在玩家選著一條線的那些幀跑。
func sel_wire_index() -> int:
	if battle.sel_wire < 0:
		return -1
	for i in battle.s.conduits.size():
		if int((battle.s.conduits[i])["id"]) == battle.sel_wire:
			return i
	return -1


## 選一條導管。再點同一條＝取消（和選節點同一個開關語意）。
func select_wire(id: int) -> void:
	battle.selected = Vector2i(-1, -1)
	battle.sel_wire = -1 if battle.sel_wire == id else id
	battle.message = ""
	refresh_inspect()


func _on_inspect_upgrade() -> void:
	var wi := sel_wire_index()
	if wi >= 0:
		var code := BuildController.upgrade(battle.s, wi)
		if code == Build.OK:
			AudioBus.play("build_wire")
		battle.message = battle.inp.text_of(code)
	elif battle.selected.x >= 0:
		var code := BuildController.upgrade_node(battle.s, battle.selected)
		if code == Build.OK:
			AudioBus.play("build_place")
		battle.message = battle.inp.text_of(code)
	refresh_inspect()
	battle.hints.refresh_hint()
	battle.queue_redraw()


func _on_inspect_demolish() -> void:
	var wi := sel_wire_index()
	var code := ""
	if wi >= 0:
		code = BuildController.demolish_conduit(battle.s, wi)
	elif battle.selected.x >= 0:
		code = BuildController.demolish(battle.s, battle.selected)
	else:
		return
	if code == Build.OK:
		AudioBus.play("build_destroyed", -4.0)
		# 拆掉的東西不能繼續選著：面板下一幀就沒有東西可講了。
		battle.selected = Vector2i(-1, -1)
		battle.sel_wire = -1
	battle.message = battle.inp.text_of(code)
	refresh_inspect()
	battle.hints.refresh_hint()
	battle.queue_redraw()


## ★ 被選取那一座的**當下數據**（B3.6）。每幀重算——它講的是這個 tick。
##
## 三件事，照玩家問的順序：**這是什麼 → 它現在吃多少電 → 電從哪來。**
## 前兩件是它自己的欄位，第三件要逆著本 tick 的實際流向走（`FlowNetwork.upstream_power()`）。
func refresh_inspect() -> void:
	if inspect_panel == null:
		return
	if Hooks.naked:
		inspect_panel.visible = false
		return
	# 選著的那條線可能已經不在了（自己拆的、或敵人啃斷的）。**在這裡收掉**，
	# 而不是等某個讀 `s.conduits[i]` 的地方越界——那個症狀是整支函式中止（RG-164）。
	var wi := sel_wire_index()
	if battle.sel_wire >= 0 and wi < 0:
		battle.sel_wire = -1
	# 內容與兩顆動詞鈕的文字在核心層的 `Readout`；這裡只管擺版面。
	var model: Dictionary = {}
	if wi >= 0:
		model = Readout.inspect_wire(battle.s, wi)
	elif battle.selected.x >= 0:
		model = Readout.inspect_node(battle.s, battle.selected, battle.engaged)
	if model.is_empty():
		inspect_panel.visible = false
		return
	_show_verbs(String(model["up"]), String(model["del"]), bool(model["up_on"]))
	var lines: Array[String] = []
	lines.assign(model["lines"])
	place_inspect(lines)


## 兩顆鈕的文字與可按性。空字串＝那顆鈕整個收起來。
func _show_verbs(up: String, del: String, up_on: bool = true) -> void:
	inspect_up.visible = up != ""
	inspect_up.text = up
	inspect_up.disabled = not up_on
	inspect_del.visible = del != ""
	inspect_del.text = del


## 面板的內容與座標。**兩種選取共用**——版面規則只有一份，不然加第三種選取時
## 會有一種悄悄跑到畫面外（RG-139／149／162／170 都是同一個錯法）。
func place_inspect(lines: Array[String]) -> void:
	inspect_label.text = "
".join(lines)
	inspect_panel.visible = true
	# ── ★ 座標只能是**離散狀態**的函式（B3.9.1，使用者回報「點了升級之後，滑鼠會
	#      位移到一個很奇怪的位置」）───────────────────────────────────────
	#
	#   位移的不是游標，是面板。它的位置本來同時是**內容**的函式：靠右對齊用的是
	#   實際寬度（字一長就往左滑，量到 277 → 383），避讓鄰居判的是實際高度
	#   （多一行就從右緣彈到 x=477）。於是升一級＝兩顆鈕跑掉，而停在原地的游標
	#   落到地圖上，或落到「拆除」上。
	#
	#   兩條規矩：
	#   ① **寬高一律用常數**（`INSPECT_W`／`INSPECT_MAX_H`）算位置與避讓，實際尺寸
	#      只拿來對齊底邊。位置因此只由「鄰居開著沒」決定——那是玩家自己按的開關，
	#      不是每 tick 都在變的數字。
	#   ② **底邊釘住**。兩顆動詞鈕在面板底列，底邊不動＝鈕不動；內容變多時往上長。
	#      頂邊釘住的話，多一行字就把鈕往下推。
	#   ③ ★ B3.10：**尺寸每次自己算，不讀上一次留下的**。自由浮動的 `Control`
	#      只會長不會縮——先點一條導管（面板 258 高）再點一座塔（內容 120），
	#      `size.y` 停在 258，於是底邊釘住之下頂邊高出 140px，塔的資料浮在一塊
	#      空白底板的上緣。B3.9.1 把**寬**改成常數就是為了根治這件事，高度這一半
	#      當時沒改到（那一批的 clicktest 收尾自己寫了 `size = Vector2.ZERO`）。
	#      `get_combined_minimum_size()` 是這一份內容真正要多高，不必等下一幀。
	inspect_panel.size = Vector2(INSPECT_W, inspect_panel.get_combined_minimum_size().y)
	var bottom := BattleCamera.FRAME.end.y - 12.0
	var pos := Vector2(float(battle.size.x) - INSPECT_W - 24.0, bottom - inspect_panel.size.y)
	var probe := Rect2(Vector2(pos.x, bottom - INSPECT_MAX_H), Vector2(INSPECT_W, INSPECT_MAX_H))
	# ⚠ **右下角住著三個東西**：能量收支面板（右上）、小地圖（右下）、和它自己。
	#   讓位一律**往左挪，不能往上擠**：能量面板自己就有 358 高，右緣從 y 96 排到
	#   454，小地圖從 525 起——中間只剩 71px，塞不下一個 174px 高的面板。
	#   B3.7 把上限夾在小地圖上緣，結果是面板被推回去壓在能量面板身上
	#   （量到 392–650 對 96–454）——**那只是把一個重疊換成另一個重疊**
	#   （`版面=false` 從 B3.8 就紅著）。
	if battle.energy.energy_panel != null and battle.energy.energy_panel.visible:
		var energy := Rect2(battle.energy.energy_panel.position, battle.energy.energy_panel.size)
		if probe.intersects(energy):
			pos.x = maxf(BattleCamera.FRAME.position.x + 12.0, energy.position.x - INSPECT_W - 12.0)
			probe.position.x = pos.x
	var mini := battle.guide.minimap_rect()
	if probe.intersects(mini):
		pos.x = maxf(BattleCamera.FRAME.position.x + 12.0, mini.position.x - INSPECT_W - 12.0)
	inspect_panel.position = pos

