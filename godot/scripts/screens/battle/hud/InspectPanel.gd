extends Node
## 檢視面板（B3.6／B3.7）：點一座塔或一條導管就開，講它是誰、射程與數據、當下耗能、
## **是誰在餵它電**，並在旁邊放它能做的兩件事（升級／加粗、拆除）。
##
## 動詞跟著**被選中的那個東西**走，不跟模式走——面板已經知道玩家選的是哪一個東西，
## 不必再用座標猜一次。選取本身（`selected`／`sel_wire`）是畫面層的狀態，這裡只讀它。

const Overlay2D := preload("res://scripts/screens/battle/Overlay2D.gd")
const Stage := preload("res://scripts/screens/battle/Stage.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const Build := preload("res://scripts/sim/Build.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Combat := preload("res://scripts/sim/Combat.gd")
const FlowNetwork := preload("res://scripts/sim/FlowNetwork.gd")
const CodexPanel := preload("res://scripts/screens/battle/hud/CodexPanel.gd")
const EnergyPanel := preload("res://scripts/screens/battle/hud/EnergyPanel.gd")
const HintBar := preload("res://scripts/screens/battle/hud/HintBar.gd")

## 擁有這個模組的局內畫面（`screens/Battle.gd`）。由它在建立時指派。
var scr: Control = null
## 同伴模組（Overlay2D）。
var overlay: Overlay2D = null
## 同伴模組（Stage）。
var stage: Stage = null
## 局的狀態（與 `scr.s` 同一個物件；換局時由畫面重新指派）。
var s: RefCounted = null
## 同伴模組。
var codexpanel: CodexPanel = null
## 同伴模組。
var energypanel: EnergyPanel = null
## 同伴模組。
var hintbar: HintBar = null


var _inspect_panel: Control = null

var _inspect_label: Label = null

## ★ 檢視面板上的兩顆動詞鈕（B3.7）。升級／加粗共用一顆——選的是什麼就升什麼。
var _inspect_up: Button = null

var _inspect_del: Button = null

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
	_inspect_label = UiKit.label("", 13, Palette.TEXT_PRIMARY, false)
	# ★ 356 ＝ 量到的最長一行。**不開 autowrap**：這些行是設計成單行的，折行會讓
	#   面板從 258 長到 552，一個蓋住半張地圖的浮層比它要修的位移更糟。
	_inspect_label.custom_minimum_size.x = 356.0
	col.add_child(_inspect_label)
	var row := UiKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_up = Button.new()
	_inspect_up.pressed.connect(_on_inspect_upgrade)
	_inspect_del = Button.new()
	_inspect_del.pressed.connect(_on_inspect_demolish)
	for b: Button in [_inspect_up, _inspect_del]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(UiKit.touchable(b))
	col.add_child(row)
	box.add_child(col)
	scr.add_child(box)
	_inspect_panel = box


## 被選取那條導管在 `s.conduits` 裡的索引。找不到（被拆了、被敵人啃斷了）回 −1。
##
## 每次都重找而不是記索引——理由寫在 `_sel_wire` 的宣告上。線性掃：一局的導管
## 是幾十條，而這只在玩家選著一條線的那些幀跑。
func sel_wire_index() -> int:
	if scr.sel_wire < 0:
		return -1
	for i in s.conduits.size():
		if int((s.conduits[i])["id"]) == scr.sel_wire:
			return i
	return -1


## 選一條導管。再點同一條＝取消（和選節點同一個開關語意）。
func select_wire(id: int) -> void:
	scr.selected = Vector2i(-1, -1)
	scr.sel_wire = -1 if scr.sel_wire == id else id
	scr.message = ""
	refresh_inspect()


func _on_inspect_upgrade() -> void:
	var wi := sel_wire_index()
	if wi >= 0:
		var code := BuildController.upgrade(s, wi)
		if code == Build.OK:
			AudioBus.play("build_wire")
		scr.message = scr.text_of(code)
	elif scr.selected.x >= 0:
		var code := BuildController.upgrade_node(s, scr.selected)
		if code == Build.OK:
			AudioBus.play("build_place")
		scr.message = scr.text_of(code)
	refresh_inspect()
	hintbar.refresh_hint()
	scr.redraw()


func _on_inspect_demolish() -> void:
	var wi := sel_wire_index()
	var code := ""
	if wi >= 0:
		code = BuildController.demolish_conduit(s, wi)
	elif scr.selected.x >= 0:
		code = BuildController.demolish(s, scr.selected)
	else:
		return
	if code == Build.OK:
		AudioBus.play("build_destroyed", -4.0)
		# 拆掉的東西不能繼續選著：面板下一幀就沒有東西可講了。
		scr.selected = Vector2i(-1, -1)
		scr.sel_wire = -1
	scr.message = scr.text_of(code)
	refresh_inspect()
	hintbar.refresh_hint()
	scr.redraw()


## ★ 被選取那一座的**當下數據**（B3.6）。每幀重算——它講的是這個 tick。
##
## 三件事，照玩家問的順序：**這是什麼 → 它現在吃多少電 → 電從哪來。**
## 前兩件是它自己的欄位，第三件要逆著本 tick 的實際流向走（`FlowNetwork.upstream_power()`）。
func refresh_inspect() -> void:
	if _inspect_panel == null:
		return
	if Hooks.naked:
		_inspect_panel.visible = false
		return
	# 選著的那條線可能已經不在了（自己拆的、或敵人啃斷的）。**在這裡收掉**，
	# 而不是等某個讀 `s.conduits[i]` 的地方越界——那個症狀是整支函式中止（RG-164）。
	var wi := sel_wire_index()
	if scr.sel_wire >= 0 and wi < 0:
		scr.sel_wire = -1
	if wi >= 0:
		_refresh_inspect_wire(wi)
		return
	var n: Dictionary = s.node_at(scr.selected) if scr.selected.x >= 0 else {}
	if n.is_empty():
		_inspect_panel.visible = false
		return
	var type := String(n["type"])
	var def := NodeDefs.of(type)
	var lvl := int(n.get("level", 0))
	var scale := Build.node_scale(lvl)
	var lines: Array[String] = []
	lines.append("%s%s" % [NodeDefs.label(type), "　%d 級" % lvl if lvl > 0 else ""])
	lines.append("生命　%d / %d" % [int(n["hp"]), int(NodeDefs.hp(type))])

	# ── 它自己的數據（升級之後要顯示**升過的值**，不是表上的原值）──
	# ★ B3.8：升的是哪一項各問各的（`10_GDD.md` §4.3）。這裡**不能用 `scale`**
	#   ——那是耗能倍率；一座第 2 級加射速的錨，傷害還停在 1 級的值。
	var eff := Build.effect_scale(type, lvl)
	var rng := Build.node_range(type, lvl)
	if rng > 0.0:
		lines.append("射程　%.0f 格" % rng)
	if float(def.get("dmg", 0.0)) > 0.0:
		lines.append("傷害　%.0f × %.1f 發/秒" % [
			float(def["dmg"]) * eff * float(s.mods["damage_mult"]),
			float(def.get("rof", 0.0)) * Build.rof_scale(type, lvl),
		])
	if float(def.get("slow", 0.0)) > 0.0:
		# 光環塔的**全部效果**都在這一行。B3.5 起它一直沒有被級數乘過，而面板
		# 也從來沒有印出來——使用者實玩才發現「潮鳴跟霜礁升級都沒用」（B3.8）。
		lines.append("減速　%d%%%s" % [
			int(round(minf(float(def["slow"]) * eff, Combat.SLOW_MAX) * 100.0)),
			"　破甲 %d%%" % int(round(float(def["armor_break"]) * eff * 100.0))
				if float(def.get("armor_break", 0.0)) > 0.0 else "",
		])
	if Build.splash_radius(type, lvl) > 0.0:
		lines.append("濺射　%.1f 格" % Build.splash_radius(type, lvl))
	if float(def.get("reclaim", 0.0)) > 0.0:
		lines.append("回收　射程內任何死亡的 %d%% 換能量" % int(round(
			float(def["reclaim"]) * eff * 100.0
		)))
	if float(def.get("ore_out", 0.0)) > 0.0:
		lines.append("產出　%.1f 礦砂/秒" % (float(def["ore_out"]) * eff
			* float(s.mods["produce_mult"])))
	if float(def.get("power_out", 0.0)) > 0.0:
		lines.append("發電　%.0f 能量/秒" % (float(def["power_out"]) * eff
			* float(s.mods["produce_mult"])))

	# ── 耗能：**帳面**與**當下**分開講 ──
	# 帳面是「它交戰時會吃多少」，當下是「這個 tick 它真的拿到多少」。
	# 只講一個的話，玩家看不出「它在挨餓」——而那正是他點開這座塔的原因。
	var engage := float(def.get("engage_power", 0.0)) * scale * float(s.mods["engage_mult"])
	var idle := float(def.get("power_in", 0.0)) * scale
	if engage > 0.0 or idle > 0.0:
		# ⚠ **預設值不能是 1.0**。沒接進電網的節點根本不在解算器的表上，
		#   `.get(id, 1.0)` 會把「查無此人」讀成「餵得飽飽的」——
		#   截圖當場抓到面板自相矛盾：上一行寫「餵得 100%」，下一行寫「供電 沒有」。
		#   用 −1 當哨兵，把「沒在表上」和「在表上而且滿足率是 1」分開。
		var sat_raw := float((s.rates["satisfaction"] as Dictionary).get(int(n["id"]), -1.0))
		var wired: bool = sat_raw >= 0.0
		var sat: float = sat_raw if wired else 0.0
		# `.get()` 不是 `.has()`：`_engaged` 是 {id: bool}，沒交戰的塔**鍵也在**，
		# 值才是 false（第 1008 行那條既有斷言用的就是 get）。
		var busy: bool = engage > 0.0 and bool(stage.engaged.get(int(n["id"]), false))
		var draw := (engage if busy else 0.0) + idle
		if engage > 0.0:
			lines.append("交戰耗能　%.1f 能量/秒%s" % [engage, "" if busy else "（待機 0）"])
		if idle > 0.0:
			lines.append("待機耗能　%.1f 能量/秒" % idle)
		if not wired:
			# 和提示列講同一句話——同一件事在兩個地方要有同一個說法。
			lines.append("此刻　沒接進電網，交戰時一發都打不出來")
		else:
			lines.append("此刻　%.1f 能量/秒　餵得 %d%%" % [draw * sat, int(round(sat * 100.0))])

	# ── ★ 電從哪來 ──
	var sources: Dictionary = energypanel.power_sources()
	var chain := FlowNetwork.upstream_power(s.conduits, energypanel.energy_net(), scr.selected, sources)
	var feeders: Dictionary = chain["sources"]
	if engage > 0.0 or idle > 0.0:
		# ⚠ 「沒有外部來源」和「在挨餓」**不是同一件事**。回收者靠自己的回收緩衝、
		#   儲槽靠自己的存量，兩者都會出現「一條線都沒有在餵它，而它餵得飽飽的」。
		#   第一版一律寫「沒有——這一刻沒有任何電流進來」，於是面板上一行寫
		#   「餵得 100%」、下一行寫「沒有供電」，讀起來像壞掉了（截圖當場看到）。
		var self_fed: bool = String(n["type"]) in ["reclaimer", "silo"]
		var supply_text := "%d 座（已在地圖上標出）" % feeders.size()
		if feeders.is_empty():
			supply_text = "沒有外部來源，這一刻靠自己的存量" if self_fed 				else "這一刻沒有電流進來"
		lines.append("供電　%s" % supply_text)

	# ── ★ 兩顆動詞鈕（B3.7）──
	# **核心兩顆都關**：它升不得也拆不得（`upgrade_node()`／`demolish()` 都擋著）。
	# 鈕在那裡而按不動，等於邀請玩家去按一個保證失敗的東西。
	if type == "core":
		_show_verbs("", "")
	else:
		# ★ B3.8：鈕上寫**這一級買到的是什麼**。三級各不相同，而玩家在按下去
		#   之前必須知道自己買的是射程還是射速——否則「多元化」對他等於隨機。
		var up := "已滿級" if lvl >= Build.NODE_MAX_LEVEL else "升級　%s　%d 礦砂" % [
			codexpanel.step_text(Build.next_step(type, lvl)),
			Build.node_upgrade_cost(NodeDefs.cost(type), lvl),
		]
		var refund := BuildController.node_refund(type)
		_show_verbs(up, "拆除　退 %d 礦砂" % refund.x, lvl < Build.NODE_MAX_LEVEL)
	_place_inspect(lines)


## ★ 被選取那條導管的當下數據（B3.7）。
##
## 玩家點一條線要問的是同一組問題，只是主詞換了：**它多粗 → 這一刻擠不擠 →
## 加粗要多少錢**。「擠不擠」是這一批真正要答的——導管滿載在圖上是變色與線寬，
## 那是給掃視用的；點下去要拿得到數字。
func _refresh_inspect_wire(wi: int) -> void:
	var c: Dictionary = s.conduits[wi]
	var lvl := int(c["level"])
	var cap := Build.conduit_cap(lvl, float(s.mods["cap_bonus"]))
	var flow := float((s.rates["conduit_flow"] as Dictionary).get(c["id"], 0.0))
	var lines: Array[String] = []
	lines.append("導管%s" % ("　%d 級" % lvl if lvl > 0 else ""))
	lines.append("生命　%d / 40" % int(c["hp"]))
	lines.append("長度　%d 格" % (Build.conduit_cost(c["a"], c["b"]) / Build.CONDUIT_COST_PER_CELL))
	# 「這一刻擠不擠」：滿載是這條線正在**卡住**它下游的每一個節點。
	lines.append("流量　%.1f / %.0f 每秒%s" % [
		flow, cap, "　已滿載" if flow >= cap - 0.05 else ""
	])
	if lvl < Build.CAP_MAX_LEVEL:
		lines.append("加粗後　%.0f 每秒" % Build.conduit_cap(lvl + 1, float(s.mods["cap_bonus"])))

	var up := "已滿級"
	if lvl < Build.CAP_MAX_LEVEL:
		var alloy := Build.upgrade_alloy(lvl)
		up = "加粗　%d 礦砂%s" % [
			Build.upgrade_cost(lvl), "" if alloy == 0 else " ＋ %d 合金" % alloy
		]
	var refund := BuildController.conduit_refund(c)
	_show_verbs(up, "拆除　退 %d 礦砂" % refund.x, lvl < Build.CAP_MAX_LEVEL)
	_place_inspect(lines)


## 兩顆鈕的文字與可按性。空字串＝那顆鈕整個收起來。
func _show_verbs(up: String, del: String, up_on: bool = true) -> void:
	_inspect_up.visible = up != ""
	_inspect_up.text = up
	_inspect_up.disabled = not up_on
	_inspect_del.visible = del != ""
	_inspect_del.text = del


## 面板的內容與座標。**兩種選取共用**——版面規則只有一份，不然加第三種選取時
## 會有一種悄悄跑到畫面外（RG-139／149／162／170 都是同一個錯法）。
func _place_inspect(lines: Array[String]) -> void:
	_inspect_label.text = "
".join(lines)
	_inspect_panel.visible = true
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
	#      `scr.size.y` 停在 258，於是底邊釘住之下頂邊高出 140px，塔的資料浮在一塊
	#      空白底板的上緣。B3.9.1 把**寬**改成常數就是為了根治這件事，高度這一半
	#      當時沒改到（那一批的 clicktest 收尾自己寫了 `size = Vector2.ZERO`）。
	#      `get_combined_minimum_size()` 是這一份內容真正要多高，不必等下一幀。
	_inspect_panel.size = Vector2(INSPECT_W, _inspect_panel.get_combined_minimum_size().y)
	var bottom: float = stage.FRAME.end.y - 12.0
	var pos := Vector2(float(scr.size.x) - INSPECT_W - 24.0, bottom - _inspect_panel.size.y)
	var probe := Rect2(Vector2(pos.x, bottom - INSPECT_MAX_H), Vector2(INSPECT_W, INSPECT_MAX_H))
	# ⚠ **右下角住著三個東西**：能量收支面板（右上）、小地圖（右下）、和它自己。
	#   讓位一律**往左挪，不能往上擠**：能量面板自己就有 358 高，右緣從 y 96 排到
	#   454，小地圖從 525 起——中間只剩 71px，塞不下一個 174px 高的面板。
	#   B3.7 把上限夾在小地圖上緣，結果是面板被推回去壓在能量面板身上
	#   （量到 392–650 對 96–454）——**那只是把一個重疊換成另一個重疊**
	#   （`版面=false` 從 B3.8 就紅著）。
	if energypanel.energy_panel != null and energypanel.energy_panel.visible:
		var energy := Rect2(energypanel.energy_panel.position, energypanel.energy_panel.size)
		if probe.intersects(energy):
			pos.x = maxf(stage.FRAME.position.x + 12.0, energy.position.x - INSPECT_W - 12.0)
			probe.position.x = pos.x
	var mini: Rect2 = overlay.minimap_rect()
	if probe.intersects(mini):
		pos.x = maxf(stage.FRAME.position.x + 12.0, mini.position.x - INSPECT_W - 12.0)
	_inspect_panel.position = pos
