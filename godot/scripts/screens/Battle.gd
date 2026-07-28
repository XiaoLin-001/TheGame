extends Control
## 局內畫面（`10_GDD.md` §6.2：**全畫面地圖 ＋ 浮層**，不是三欄式）。
##
## B0.3 只做「建造與地圖」需要的部分：地圖繪製、四種建造模式、頂欄供需。
## 真正的 HUD（三態徽章、能量列脈動、提前召喚、局末結算）是 B0.6；
## 敵人與波次是 B0.4。**這一批要證明的是：線會亮、線會滿載、加粗會變粗。**

const SessionState := preload("res://scripts/game/SessionState.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const Build := preload("res://scripts/sim/Build.gd")
const MapsData := preload("res://data/Maps.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Enemies := preload("res://data/Enemies.gd")
const Tide := preload("res://scripts/sim/Tide.gd")
const Combat := preload("res://scripts/sim/Combat.gd")
const Score := preload("res://scripts/sim/Score.gd")

## 地圖左上角。36×19 格 ×32px = 1152×608；左側 120px 留給建造欄，
## 浮層與地圖**不重疊**（RG-20 的先行實踐，正式驗收在 B0.6）。
const ORIGIN := Vector2(120.0, 56.0)

## `10_GDD.md` §7.1。**只在準備期可用。**
const FAST_FORWARD_RATE := 4

## 流動珠（`20_ART_DIRECTION.md` §1.4a）：珠距、每單位流率的行進速度（px/秒）、
## 低於此流率就完全不畫。20/秒的幹線 ＝ 120 px/秒，一格 32px 約走四分之一秒。
const BEAD_GAP := 20.0
const BEAD_SPEED := 6.0
const BEAD_MIN_RATE := 0.05

enum Mode { BUILD, CONNECT, UPGRADE, DEMOLISH }

var s: RefCounted = null

var _mode: int = Mode.BUILD
var _build_type: String = "extractor"
var _connect_from: Vector2i = Vector2i(-1, -1)
var _hover: Vector2i = Vector2i(-999, -999)
var _accum: float = 0.0
var _message: String = ""

var _top: HBoxContainer = null
var _hint: Label = null
var _mode_buttons: Dictionary = {}
var _ff_button: Button = null
var _summon_button: Button = null
var _over_panel: Control = null
var _prio_panel: Control = null
var _prio_labels: Dictionary = {}
## 本幀交戰中的塔 `{id: Array}`。繪圖層自己算——它要畫的是「誰正在吃電」，
## 而模擬只留了一個座數（`rates.engaged`）。
var _engaged: Dictionary = {}


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	s = SessionState.new()
	s.setup(MapsData.SHOAL)
	_build_ui()
	if Hooks.panel == "battle":
		# 截圖驗證要看得到「流動中的網路」，空地圖證明不了任何事。
		_demo_layout()


func _process(delta: float) -> void:
	# ★ `TL_SHOT` 下模擬凍結在 `_demo_layout()` 推完的那一格。否則截圖落在第幾
	# tick 取決於這台機器 3 秒內跑了幾幀——同一份佈局在不同機器上會拍出不同
	# 數字，截圖就不能拿來做回歸比對，也對不上 `TL_SIM=<同一個 N>` 的輸出。
	if Hooks.shot_path == "":
		_accum += delta
		# 快進＝**多跑幾個 tick**，不是把 tick 拉長。固定時間步不能動，
		# 否則同一組操作在不同倍率下會跑出不同結果（§2.4 確定性）。
		var mult: int = s.speed_mult if s.phase == "prep" else 1
		var guard := 0
		while _accum >= BattleController.TICK and guard < 8 * mult:
			for _i in mult:
				BattleController.step(s)
			_accum -= BattleController.TICK
			guard += mult
	_refresh_top()
	_refresh_over()
	queue_redraw()


# ── 輸入 ──────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var c := _cell_at((event as InputEventMouseMotion).position)
		if c != _hover:
			_hover = c
			_refresh_hint()
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_act(_cell_at(mb.position))
	_refresh_hint()


func _act(cell: Vector2i) -> void:
	match _mode:
		Mode.BUILD:
			_message = _text_of(BuildController.place(s, _build_type, cell))
		Mode.CONNECT:
			if s.node_at(cell).is_empty():
				_message = "連線模式：請點節點（先起點、後終點）"
			elif _connect_from.x < 0:
				_connect_from = cell
				_message = "起點已選：%s。再點一個節點拉線。" % _label_at(cell)
			else:
				_message = _text_of(BuildController.lay_conduit(s, _connect_from, cell))
				_connect_from = Vector2i(-1, -1)
		Mode.UPGRADE:
			var ci: int = s.conduit_at(cell)
			if ci < 0:
				_message = "升級模式：請點一段導管（不是節點）"
			else:
				_message = _text_of(BuildController.upgrade(s, ci))
		Mode.DEMOLISH:
			_message = _text_of(BuildController.demolish(s, cell))


func _text_of(code: String) -> String:
	return "✔ 完成" if code == Build.OK else "✕ " + BuildController.reason_text(code)


func _label_at(cell: Vector2i) -> String:
	var n: Dictionary = s.node_at(cell)
	return NodeDefs.label(String(n["type"])) if not n.is_empty() else "空地"


func _cell_at(pos: Vector2) -> Vector2i:
	return Shapes.to_grid(pos - ORIGIN)


func _in_map(c: Vector2i) -> bool:
	var size: Vector2i = s.map["size"]
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


# ── 繪圖 ──────────────────────────────────────────────────────────────

func _draw() -> void:
	var size: Vector2i = s.map["size"]
	var rect := Rect2(ORIGIN, Vector2(size) * Shapes.GRID)
	draw_rect(rect, Palette.BG_PANEL)

	# 網格只畫在地圖範圍內：畫到浮層底下會讓「哪裡可以蓋」變得曖昧。
	draw_set_transform(ORIGIN, 0.0, Vector2.ONE)
	Shapes.draw_grid(self, Rect2(Vector2.ZERO, Vector2(size) * Shapes.GRID))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_engaged = Combat.engaged(s.nodes, Combat.enemy_cells(s.enemies, s.path))
	_draw_path()
	_draw_ore_cells()
	_draw_conduits()
	_draw_nodes()
	_draw_enemies()
	_draw_shots()
	_draw_hover()
	# 階段色調（`10_GDD.md` §6.2 硬性要求 4）：**不看計時器也知道自己在哪個階段**。
	# 蓋在最上層而不是墊在底下——墊底的話節點與敵人會把它整片蓋掉。
	draw_rect(rect, Palette.alpha(
		Palette.WARN_ORANGE if s.phase == "wave" else Palette.ORDER_CYAN,
		0.10 if s.phase == "wave" else 0.03
	))
	_draw_energy_bar()


func _draw_path() -> void:
	# 敵人路徑屬於**混沌**側：低透明度帶狀底色（20_ART_DIRECTION.md §1.6）。
	var band := Palette.alpha(Palette.TIDE_DEEP, 0.45)
	for c: Vector2i in MapsData.path_of(s.map):
		draw_rect(Rect2(_world(c), Vector2(Shapes.GRID, Shapes.GRID)), band)
	for c: Vector2i in s.map.get("crossings", []):
		_draw_crossing(c)


## 跨越點（橋）：**「架高」必須用畫的說清楚**——它是「橋上導管不受攻擊」
## 這條規則的唯一解釋（`20_ART_DIRECTION.md` §1.6）。硬性要求：一眼可辨。
func _draw_crossing(cell: Vector2i) -> void:
	var p := _world(cell)
	var g := Shapes.GRID
	# 橋下留可見的路徑帶陰影
	draw_rect(Rect2(p + Vector2(3, 3), Vector2(g - 6, g - 6)), Palette.alpha(Palette.BG_DEEP, 0.55))
	# 橋面：兩條 order.cyan 平行線，方向與路徑垂直（導管要橫越）
	var path: Dictionary = s.sets["path"]
	var horizontal := path.has(cell + Vector2i(1, 0)) or path.has(cell + Vector2i(-1, 0))
	var c := Palette.ORDER_CYAN
	if horizontal:
		# 橋面沿垂直方向（導管要南北橫越），兩端伸出格外＝架高的「引道」
		for dx: float in [7.0, g - 7.0]:
			draw_line(p + Vector2(dx, -6), p + Vector2(dx, g + 6), c, 3.0)
		# 橋頭：兩端各一條橫桿，把「這是一段結構」講清楚
		for dy: float in [-6.0, g + 6.0]:
			draw_line(p + Vector2(4, dy), p + Vector2(g - 4, dy), c, 2.0)
	else:
		for dy: float in [7.0, g - 7.0]:
			draw_line(p + Vector2(-6, dy), p + Vector2(g + 6, dy), c, 3.0)
		for dx: float in [-6.0, g + 6.0]:
			draw_line(p + Vector2(dx, 4), p + Vector2(dx, g - 4), c, 2.0)


func _draw_ore_cells() -> void:
	var occupied: Dictionary = s.occupied()
	for c: Vector2i in s.map.get("ore", []):
		if occupied.has(c):
			continue  # 蓋上採集器後由節點填實
		draw_arc(_center(c), 10.0, 0.0, TAU, 24, Palette.ORDER_DIM, 2.0)


func _draw_conduits() -> void:
	var flows: Dictionary = s.rates["conduit_flow"]
	var sat: Dictionary = s.rates["satisfaction"]
	for c: Dictionary in s.conduits:
		var cap := Build.conduit_cap(int(c["level"]))
		var flow := float(flows.get(c["id"], 0.0))
		var to_node: Dictionary = s.node_at(c["b"])
		var starving := (
			not to_node.is_empty() and float(sat.get(to_node["id"], 1.0)) < 0.95 and flow > 0.0
		)
		var w := Shapes.conduit_width(flow, cap)
		# 受損：先鋪一圈 warn.orange 光暈。**線被打斷之前要先看得出它在挨打**，
		# 否則產能中斷對玩家來說會是憑空發生的。
		if float(c["hp"]) < 40.0:
			var hurt := 1.0 - float(c["hp"]) / 40.0
			draw_line(
				_center(c["a"]), _center(c["b"]),
				Palette.alpha(Palette.WARN_ORANGE, 0.25 + 0.55 * hurt), w + 6.0
			)
		draw_line(_center(c["a"]), _center(c["b"]), Palette.conduit(flow, cap, starving), w)
		# 升級過的幹線在端點加刻度，讓「我升過這條」在無數值下也看得見。
		# **垂直短刻線，不是圓點**：圓點會和流動珠混成同一個東西，而兩者語意相反
		# （固定的線材等級 vs 變動的流量）——`20_ART_DIRECTION.md` §1.4a。
		var pa := _center(c["a"])
		var pb := _center(c["b"])
		var perp := (pb - pa).normalized().orthogonal()
		for i in range(int(c["level"])):
			var at := pa.lerp(pb, 0.12 + 0.05 * float(i))
			draw_line(at - perp * 5.0, at + perp * 5.0, Palette.ORDER_BRIGHT, 2.0)
		# ★ 流動珠：礦砂一列、能量一列，各自往自己的淨流向跑（§1.4a）。
		var net: Vector2 = (s.rates["conduit_net"] as Dictionary).get(c["id"], Vector2.ZERO)
		# 只有一種資源在跑時**走線的正中央**：多數導管都是這種，
		# 硬要分兩排會讓珠子懸在細線外面，看起來像掉出來的東西。
		var both := absf(net.x) >= BEAD_MIN_RATE and absf(net.y) >= BEAD_MIN_RATE
		var off := (w * 0.45 + 1.0) if both else 0.0
		# 礦砂珠用 `text.primary`（近白）而不是 `order.bright`：導管本身就是亮青，
		# 亮青珠子在亮青線上只讀得出「這裡有個洞」，讀不出「有東西在跑」。
		# 能量珠的琥珀本來就與線色分屬兩個色相，維持配色紀律 2。
		_draw_beads(pa, pb, net.x, Palette.TEXT_PRIMARY, -off, w)
		_draw_beads(pa, pb, net.y, Palette.ENERGY_AMBER, off, w)


## ★ 流動珠（`20_ART_DIRECTION.md` §1.4a）。線寬與顏色說的是「這條線有多滿」，
## 沒有任何元素在說「東西正在動」——一張靜態的粗線看起來是接線圖，不是產線。
##
## **這不是實體物品搬運。** 珠子的位置由已解出的流率 ＋ 經過的模擬秒數推算，
## 模擬層一無所知，珠子不參與任何判定（`10_GDD.md` §3.1 鎖定：流量網路）。
## 一旦它變成有位置有狀態的實體，`O(物品數)` 的效能與確定性負債就回來了。
##
## `amount` 帶號：正＝沿 a→b、負＝反向。速度 ∝ 流率，間距固定。
##
## ponytail: 每顆珠子兩個 `draw_circle` ＝ 每幀約 `導管數 × 線長/20 × 2` 次繪製。
## M0 一屏（13 條導管）約 500 次，無感；`30_TECH_DESIGN.md` §5 的壓力情境
## （2000 條導管）會爆到六位數。到那時改成單一 `draw_multiline` 批繪或
## 用 shader 把相位推進 GPU——**在量到之前不要先做**。
func _draw_beads(
	a: Vector2, b: Vector2, amount: float, col: Color, offset: float, width: float
) -> void:
	if absf(amount) < BEAD_MIN_RATE:
		return  # 沒在流動的線必須是靜止的——這是「哪裡斷了」最快的讀法
	var span := a.distance_to(b)
	if span < 1.0:
		return
	var u := (b - a) / span
	var side := u.orthogonal() * offset
	# 相位用模擬秒數推（tick 數 ＋ 幀內插值），不用系統時間：
	# 渲染可以不確定，但別引入新的亂數源。`TL_SHOT` 下模擬凍結 → 珠子也凍結。
	var t := (float(s.tick_count) + _accum / BattleController.TICK) * BattleController.TICK
	# 珠子大小跟著線寬走：這樣它**強化**「線寬＝流量」而不是把線戳成虛線。
	# 固定大小的珠子在 2px 的細線上會蓋掉整條線，粗細那條資訊就沒了（R-3）。
	var r := clampf(width * 0.32, 1.4, 3.0)
	var x := fposmod(t * amount * BEAD_SPEED, BEAD_GAP)
	while x < span:
		var p := a + u * x + side
		# **深色底是這個元素能被看見的唯一原因**：導管本身就是亮青，
		# 亮青珠子畫在亮青線上等於沒畫（使用者實看 B0.6 時反映的正是這件事）。
		draw_circle(p, r + 1.2, Palette.BG_DEEP)
		draw_circle(p, r, col)
		x += BEAD_GAP


func _draw_nodes() -> void:
	for n: Dictionary in s.nodes:
		var p := _center(n["cell"])
		var full := NodeDefs.hp(String(n["type"]))
		if float(n["hp"]) < full:
			# **血條不是圓環**：儲槽的充能也是琥珀色圓弧，兩個圓弧疊在同一顆
			# 12px 的節點上肉眼分不出來（本批截圖當場抓到）。形狀不同才分得開。
			var frac := clampf(float(n["hp"]) / full, 0.0, 1.0)
			var bar := Vector2(24.0, 3.0)
			var at := p + Vector2(-bar.x * 0.5, 15.0)
			draw_rect(Rect2(at, bar), Palette.alpha(Palette.BG_DEEP, 0.8))
			draw_rect(Rect2(at, Vector2(bar.x * frac, bar.y)), Palette.WARN_ORANGE)
		match String(n["type"]):
			"core":
				# 最大的幾何體，order.bright 描邊（§1.6）。
				draw_rect(Rect2(p - Vector2(15, 15), Vector2(30, 30)), Palette.BG_RAISED)
				draw_rect(
					Rect2(p - Vector2(15, 15), Vector2(30, 30)), Palette.ORDER_BRIGHT, false, 2.0
				)
				draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Palette.ORDER_BRIGHT)
			"extractor":
				draw_circle(p, 11.0, Palette.ORDER_CYAN)
				draw_arc(p, 11.0, 0.0, TAU, 24, Palette.ORDER_BRIGHT, 1.5)
			"generator":
				# 琥珀專屬於能量（§1.1 配色紀律 2）。
				draw_rect(Rect2(p - Vector2(11, 11), Vector2(22, 22)), Palette.ENERGY_AMBER)
			"relay":
				var d := PackedVector2Array([
					p + Vector2(0, -8), p + Vector2(8, 0), p + Vector2(0, 8), p + Vector2(-8, 0)
				])
				draw_colored_polygon(d, Palette.ORDER_DIM)
			"silo":
				var frac := float(n["charge"]) / maxf(1.0, float(NodeDefs.of("silo")["capacity"]))
				draw_arc(p, 12.0, 0.0, TAU, 32, Palette.ORDER_DIM, 2.0)
				if frac > 0.0:
					draw_arc(p, 12.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 32, Palette.ENERGY_AMBER, 4.0)
				# 四隻塔各給一個一眼可辨的幾何體（`20_ART_DIRECTION.md` §1.6）。
				# 全部嚴格對齊格中心——與敵潮的不規則凸包形成對比，那個對比就是主題。
			"anchor":
				draw_rect(Rect2(p - Vector2(8, 8), Vector2(16, 16)), Palette.ORDER_CYAN)
			"prism":
				# 三角形＝稜鏡。合金銀把「它是最貴的那一座」講出來。
				draw_colored_polygon(PackedVector2Array([
					p + Vector2(0, -12), p + Vector2(11, 7), p + Vector2(-11, 7)
				]), Palette.ALLOY_STEEL)
			"knell":
				# 同心圓＝場。它不開火，畫成「發散」比畫成砲塔誠實。
				draw_arc(p, 11.0, 0.0, TAU, 28, Palette.ORDER_CYAN, 2.0)
				draw_arc(p, 5.0, 0.0, TAU, 20, Palette.ORDER_CYAN, 2.0)
			"reclaimer":
				draw_rect(Rect2(p - Vector2(10, 10), Vector2(20, 20)), Palette.ORDER_CYAN, false, 2.0)
				draw_circle(p, 6.0, Palette.ORDER_BRIGHT)
		_draw_engaged(n, p)
		_draw_badge(n, p)


## ★ 交戰指示：**琥珀＝能量**（配色紀律 2）。有環＝這座塔本 tick 正在吃電。
## 它只講「在不在吃電」；「吃不吃得飽」由三態徽章講（B0.6 前這裡還多畫一段
## 橙色缺口弧，那和 `缺料` 徽章編碼的是同一件事，留一個就好）。
func _draw_engaged(n: Dictionary, p: Vector2) -> void:
	if _engaged.get(int(n["id"]), false):
		draw_arc(p, 15.0, 0.0, TAU, 32, Palette.ENERGY_AMBER, 2.0)


## ★ 節點三態徽章（`10_GDD.md` §3.1）。**`正常` 不畫任何東西**——徽章是例外
## 標記，一屏 14 個節點全掛上「我很好」等於把要找的那兩個埋進雜訊裡。
## 靠**形狀**分辨而不只是顏色：倒三角＝空的（缺料）、正三角＝滿的（滿溢）。
func _draw_badge(n: Dictionary, p: Vector2) -> void:
	match int((s.rates["node_state"] as Dictionary).get(int(n["id"]), SessionState.NORMAL)):
		SessionState.STARVED:
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(-7, -25), p + Vector2(7, -25), p + Vector2(0, -16)
			]), Palette.WARN_ORANGE)
		SessionState.OVERFLOW:
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -25), p + Vector2(7, -16), p + Vector2(-7, -16)
			]), Palette.ORDER_BRIGHT)


## ★ 能量列（`10_GDD.md` §6.2 硬性要求 1）：**全畫面最醒目的元件，而且是一條
## 圖形不是一串數字**——長度即資訊，所以它在 `TL_NAKED` 下要留著。
## 琥珀＝供給、右側橙色＝短少的部分（脈動）、細刻度＝需求落在哪裡。
func _draw_energy_bar() -> void:
	var r: Dictionary = s.rates
	var supply := float(r["power_supply"])
	var demand := float(r["power_demand"])
	var span := maxf(1.0, maxf(supply, demand))
	var w := float(s.map["size"].x) * Shapes.GRID
	var at := Vector2(ORIGIN.x, ORIGIN.y - 12.0)
	draw_rect(Rect2(at, Vector2(w, 8.0)), Palette.BG_RAISED)
	draw_rect(Rect2(at, Vector2(w * supply / span, 8.0)), Palette.ENERGY_AMBER)
	if demand > supply:
		# 脈動用 tick 數推，不用系統時間——渲染可以不確定，但別引入新的亂數源。
		var pulse := 0.55 + 0.45 * sin(float(s.tick_count) * 0.4)
		var x := w * supply / span
		draw_rect(
			Rect2(at + Vector2(x, 0.0), Vector2(w * demand / span - x, 8.0)),
			Palette.alpha(Palette.WARN_ORANGE, pulse)
		)
	draw_rect(Rect2(at + Vector2(w * demand / span - 1.0, -3.0), Vector2(2.0, 14.0)),
		Palette.TEXT_PRIMARY)


## 開火線。留 `SHOT_TTL` 個 tick 並隨之淡出——瞬間閃一下的線等於沒畫。
func _draw_shots() -> void:
	for sh: Dictionary in s.shots:
		var fade := float(sh["ttl"]) / float(BattleController.SHOT_TTL)
		draw_line(
			_center(sh["from"]), _center(sh["to"]),
			Palette.alpha(Palette.ORDER_BRIGHT, 0.25 + 0.6 * fade), 2.0
		)


## 敵潮屬於**混沌**側（`20_ART_DIRECTION.md` §0）：不規則凸包、不對齊網格、
## 呼吸式脈動。玩家的一切則是正圓正方、嚴格對齊——這個對比就是主題本身。
func _draw_enemies() -> void:
	for e: Dictionary in s.enemies:
		var def := Enemies.of(String(e["type"]))
		var p := _enemy_pos(e)
		var r := float(def.get("radius", 9.0))
		# 脈動用 tick 數推，不用系統時間——渲染可以不確定，但別引入新的亂數源。
		var pulse := 1.0 + 0.12 * sin(float(s.tick_count) * 0.25 + float(e["id"]))
		var pts := PackedVector2Array()
		for i in 9:
			var a := TAU * float(i) / 9.0
			# 每隻各自的不規則度，由 id 決定（同一隻永遠長同一個樣子）。
			# 值域收在 0.85–1.15：再寬就會有頂點塌進去，變成尖角旗子而不是水滴。
			var wobble := 1.0 + 0.15 * sin(float(e["id"]) * 3.7 + a * 2.0)
			pts.append(p + Vector2(cos(a), sin(a)) * r * pulse * wobble)
		draw_colored_polygon(pts, Palette.TIDE_MAGENTA)
		var frac := float(e["hp"]) / maxf(1.0, float(def.get("hp", 1.0)))
		if frac < 1.0:
			draw_arc(p, r + 4.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 20, Palette.TIDE_DEEP, 2.0)


func _enemy_pos(e: Dictionary) -> Vector2:
	var prog := float(e["progress"])
	var i := clampi(int(floor(prog)), 0, s.path.size() - 1)
	var j := mini(i + 1, s.path.size() - 1)
	# 格與格之間插值：模擬是離散的，呈現不必是（60Hz 插值，§2.4）。
	return _center(s.path[i]).lerp(_center(s.path[j]), prog - float(i))


func _draw_hover() -> void:
	if not _in_map(_hover):
		return
	var p := _world(_hover)
	var g := Vector2(Shapes.GRID, Shapes.GRID)
	if _mode == Mode.BUILD:
		var pv := BuildController.preview_place(s, _build_type, _hover)
		var col: Color = Palette.OK_GREEN if pv["ok"] else Palette.WARN_ORANGE
		draw_rect(Rect2(p, g), Palette.alpha(col, 0.18))
		draw_rect(Rect2(p, g), col, false, 2.0)
		# 塔的射程要**在花錢之前**看得到——擺位是本作的主要決策，
		# 讓玩家蓋完才發現打不到路徑等於逼他拆（§3.5 塔的擺位）。
		var r := float(NodeDefs.of(_build_type).get("range", 0.0))
		if r > 0.0:
			draw_arc(
				_center(_hover), r * Shapes.GRID, 0.0, TAU, 64,
				Palette.alpha(col, 0.45), 1.5
			)
	else:
		draw_rect(Rect2(p, g), Palette.BORDER_STRONG, false, 2.0)
	if _connect_from.x >= 0:
		draw_rect(Rect2(_world(_connect_from), g), Palette.ORDER_BRIGHT, false, 2.0)
		draw_line(_center(_connect_from), _center(_hover), Palette.alpha(Palette.ORDER_BRIGHT, 0.5), 2.0)


func _world(c: Vector2i) -> Vector2:
	return ORIGIN + Shapes.to_world(c)


func _center(c: Vector2i) -> Vector2:
	return _world(c) + Vector2(Shapes.GRID, Shapes.GRID) * 0.5


# ── 浮層 ──────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_top = UiKit.hbox(18)
	_top.position = Vector2(120, 14)
	add_child(_top)
	for i in 7:
		_top.add_child(UiKit.label("", 15, Palette.TEXT_PRIMARY, false))

	var col := UiKit.vbox(4)
	col.position = Vector2(8, 56)
	col.custom_minimum_size = Vector2(104, 0)
	add_child(col)

	for type: String in NodeDefs.BUILDABLE:
		var b := Button.new()
		# TL_NAKED 連造價都遮：它的語意是「隱藏所有數值標籤」，不是「隱藏狀態數值」。
		b.text = (
			NodeDefs.label(type) if Hooks.naked
			else "%s %d" % [NodeDefs.label(type), NodeDefs.cost(type)]
		)
		b.pressed.connect(_on_build_type.bind(type))
		col.add_child(UiKit.touchable(b))

	col.add_child(_spacer(12))
	for pair: Array in [[Mode.CONNECT, "連線"], [Mode.UPGRADE, "加粗"], [Mode.DEMOLISH, "拆除"]]:
		var b := Button.new()
		b.text = String(pair[1])
		b.pressed.connect(_on_mode.bind(int(pair[0])))
		_mode_buttons[int(pair[0])] = b
		col.add_child(UiKit.touchable(b))

	# 建造欄放不下八種節點再加動作鈕（8×44 已經吃掉 380px），
	# 所以時間流與面板開關搬到地圖下緣那條 56px 的空帶——那裡本來就空著。
	var bar := UiKit.hbox(8)
	bar.position = Vector2(8, 668)
	add_child(bar)
	_ff_button = Button.new()
	_ff_button.text = "快進 4×"
	_ff_button.pressed.connect(_on_fast_forward)
	bar.add_child(UiKit.touchable(_ff_button))
	_summon_button = Button.new()
	_summon_button.pressed.connect(_on_summon_now)
	bar.add_child(UiKit.touchable(_summon_button))
	var prio := Button.new()
	prio.text = "優先權"
	prio.pressed.connect(_on_toggle_priority)
	bar.add_child(UiKit.touchable(prio))

	_build_priority_panel()

	_hint = UiKit.label("", 14, Palette.TEXT_SECONDARY, false)
	_hint.position = Vector2(320, 678)
	_hint.size = Vector2(950, 36)
	add_child(_hint)
	_refresh_hint()


## ★ 依**節點類型**的優先權面板（`10_GDD.md` §3.1）。
##
## 三件事是設計鎖死的，不要「順手」改掉：
##   ① **列固定、順序固定**（`NodeDefs.PRIORITY_ROWS`）——不可暫停的戰術動作
##      必須是一個手勢；滑桿會跑位就不是手勢了。
##   ② **沒有「每一座」的選項**——操作負擔不得隨建築數量成長（風險 R-1）。
##   ③ 預設收合。它是抽屜不是常駐欄（§6.2 全畫面地圖 ＋ 可收合浮層）。
func _build_priority_panel() -> void:
	var box := PanelContainer.new()
	box.position = Vector2(930, 96)
	box.visible = false
	var col := UiKit.vbox(6)
	box.add_child(col)
	col.add_child(UiKit.label("能量／礦砂不足時，誰先餓死", 14, Palette.TEXT_SECONDARY, false))
	for type: String in NodeDefs.PRIORITY_ROWS:
		var row := UiKit.hbox(6)
		var name_label := UiKit.label(NodeDefs.label(type), 15, Palette.TEXT_PRIMARY, false)
		name_label.custom_minimum_size = Vector2(72, 0)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_label)
		var down := Button.new()
		down.text = "◀"
		down.pressed.connect(_on_priority.bind(type, -1))
		row.add_child(UiKit.touchable(down))
		var value := UiKit.label("", 17, Palette.ENERGY_AMBER)
		value.custom_minimum_size = Vector2(30, 0)
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(value)
		_prio_labels[type] = value
		var up := Button.new()
		up.text = "▶"
		up.pressed.connect(_on_priority.bind(type, 1))
		row.add_child(UiKit.touchable(up))
		col.add_child(row)
	add_child(box)
	_prio_panel = box
	_refresh_priority()


func _on_toggle_priority() -> void:
	_prio_panel.visible = not _prio_panel.visible


func _on_priority(type: String, delta: int) -> void:
	s.priorities[type] = clampi(
		int(s.priorities.get(type, 1)) + delta, NodeDefs.PRIORITY_MIN, NodeDefs.PRIORITY_MAX
	)
	_refresh_priority()


## TL_NAKED 明文包含「優先權面板刻度」（`30_TECH_DESIGN.md` §4.1）：
## 刻度是數值標籤，改用琥珀小方塊表示同一個 1–5，形狀仍讀得出高低。
func _refresh_priority() -> void:
	for type: String in _prio_labels:
		var v := int(s.priorities.get(type, 1))
		(_prio_labels[type] as Label).text = "▪".repeat(v) if Hooks.naked else str(v)


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _on_build_type(type: String) -> void:
	_mode = Mode.BUILD
	_build_type = type
	_connect_from = Vector2i(-1, -1)
	_message = ""
	_refresh_hint()


func _on_mode(mode: int) -> void:
	_mode = mode
	_connect_from = Vector2i(-1, -1)
	_message = ""
	_refresh_hint()


func _refresh_top() -> void:
	_refresh_summon()
	# TL_NAKED：隱藏所有數值標籤，只留線寬／顏色（`30_TECH_DESIGN.md` §4.1）。
	# **能量條不在此列**——它是圖形，長度即資訊（§6.2 硬性要求 1），畫在 `_draw()`。
	if Hooks.naked:
		_top.visible = false
		return
	var r: Dictionary = s.rates
	var core_full := NodeDefs.hp("core")
	var core_col: Color = (
		Palette.WARN_ORANGE if s.core_hp() < core_full else Palette.ORDER_BRIGHT
	)
	var texts := [
		["礦砂 %s　▲%.1f/秒" % [UiKit.commas(int(s.ore)), r["ore_in"]], Palette.ORDER_CYAN],
		["能量 %.0f/%.0f" % [r["power_supply"], r["power_demand"]], Palette.ENERGY_AMBER],
		["儲槽 %.0f/%.0f" % [r["silo_charge"], r["silo_capacity"]], Palette.ENERGY_AMBER],
		# 「能量需求為什麼突然翻倍」這個問題的答案永遠是交戰座數（§7.4 峰值約束）。
		["交戰 %d 座　擊殺 %d" % [int(r["engaged"]), s.kills], Palette.ENERGY_AMBER],
		[_phase_text(), Palette.TIDE_MAGENTA if s.phase == "wave" else Palette.TEXT_SECONDARY],
		["核心 %.0f/%.0f" % [maxf(0.0, s.core_hp()), core_full], core_col],
		["節點 %d　導管 %d" % [s.nodes.size(), s.conduits.size()], Palette.TEXT_SECONDARY],
	]
	for i in texts.size():
		var l := _top.get_child(i) as Label
		l.text = String(texts[i][0])
		l.add_theme_color_override("font_color", texts[i][1])


## 準備期顯示倒數（**計時器就在畫面上**——它是關卡參數不是隱藏係數，§7.7）。
func _phase_text() -> String:
	match s.phase:
		"prep":
			var left: float = maxf(0.0, s.prep_time() - s.phase_time)
			var ff := "　▶%d×" % s.speed_mult if s.speed_mult > 1 else ""
			# 駐足在核心的敵人不會隨波次結束而消失（§3.5）。不講的話，
			# 玩家會看到核心在準備期掉血卻找不到原因。
			var left_over := "　殘敵 %d" % s.enemies.size() if not s.enemies.is_empty() else ""
			return "準備期 %0.1fs　下一波 %d%s%s" % [left, s.wave_index + 1, ff, left_over]
		"wave":
			return "第 %d 波　敵人 %d" % [s.wave_index, s.enemies.size()]
		"won":
			return "通關"
		_:
			return "核心已毀"


## 快進只在準備期能按（`10_GDD.md` B5：可跳過等待，戰鬥期不可加速也不可減速）。
func _on_fast_forward() -> void:
	if s.phase != "prep":
		return
	s.speed_mult = 1 if s.speed_mult > 1 else FAST_FORWARD_RATE
	_refresh_top()


## ★ 提前召喚：**按鈕常駐顯示當前獎勵倍率**（`10_GDD.md` §6.2 硬性要求 3）——
## 下注的誘惑要一直在眼前，而不是按下去才知道賭到多少。
## 倍率隨倒數每 tick 縮水，所以這個字串每幀重算。
func _refresh_summon() -> void:
	if _summon_button == null:
		return
	var can: bool = s.phase == "prep"
	_summon_button.disabled = not can
	if Hooks.naked or not can:
		_summon_button.text = "提前召喚"
		return
	var bonus := Score.summon_bonus(maxf(0.0, s.prep_time() - s.phase_time), s.prep_time())
	_summon_button.text = "提前召喚 +%d%%" % roundi((bonus - 1.0) * 100.0)


func _on_summon_now() -> void:
	BattleController.start_wave(s)
	_refresh_top()


## 局末結算（通關或核心歸零）。三個數字照 `10_GDD.md` §7.6 逐項攤開——
## **玩家要看得出研究數據是怎麼算出來的**，一個總分教不會他下一局該改什麼。
## **重來按鈕必須在 1 次點擊之內**（`50_QA_PLAN.md` §4.4），
## 而且失敗不扣任何東西（紅線 R1）——局內狀態本來就不持久化。
func _refresh_over() -> void:
	if _ff_button != null:
		_ff_button.disabled = s.phase != "prep"
	if s.phase != "lost" and s.phase != "won":
		if _over_panel != null:
			_over_panel.queue_free()
			_over_panel = null
		return
	if _over_panel != null:
		return
	var won: bool = s.phase == "won"
	var waves: int = s.wave_index if won else maxi(0, s.wave_index - 1)
	var score := Score.throughput(s.delivered_total, s.tick_count, BattleController.TICK)
	var box := PanelContainer.new()
	box.position = Vector2(440, 250)
	var col := UiKit.vbox(10)
	box.add_child(col)
	col.add_child(UiKit.label(
		"通關" if won else "核心已毀", 32, Palette.OK_GREEN if won else Palette.TIDE_MAGENTA
	))
	for line: String in [
		"撐過 %d 波　　＋%.0f 研究數據" % [waves, Score.DATA_PER_WAVE * float(waves)],
		"產能積分 %.1f（送達核心 %s 礦砂）　＋%.0f" % [
			score, UiKit.commas(int(s.delivered_total)), Score.DATA_PER_SCORE * score
		],
		"提前召喚累計加成　　＋%.0f" % s.bonus_data,
		"研究數據合計 %.0f　　擊殺 %d" % [
			Score.research_data(waves, score, s.bonus_data), s.kills
		],
		"失敗不扣任何東西" if not won else "",
	]:
		if line != "":
			col.add_child(UiKit.label(line, 15, Palette.TEXT_SECONDARY, false))
	var again := Button.new()
	again.text = "立刻重來"
	again.pressed.connect(_restart)
	col.add_child(UiKit.touchable(again))
	add_child(box)
	_over_panel = box


func _restart() -> void:
	for c: Node in get_children():
		c.queue_free()
	_over_panel = null
	_top = null
	_hint = null
	_ff_button = null
	_summon_button = null
	_prio_panel = null
	_prio_labels.clear()
	s = SessionState.new()
	s.setup(MapsData.SHOAL)
	_accum = 0.0
	_message = ""
	_build_ui()


func _refresh_hint() -> void:
	if Hooks.naked:
		_hint.visible = false
		return
	var parts: Array[String] = []
	match _mode:
		Mode.BUILD:
			if _in_map(_hover):
				parts.append_array(BuildController.preview_place(s, _build_type, _hover)["lines"])
			else:
				parts.append("建造：%s" % NodeDefs.label(_build_type))
		Mode.CONNECT:
			parts.append("連線：點兩個節點。導管只能走水平／垂直／45°，過路徑只能走橋。")
		Mode.UPGRADE:
			parts.append("加粗：點一段導管。每級 +6 吞吐，造價 20×級數，上限 3 級（→28）。")
		Mode.DEMOLISH:
			parts.append("拆除：點節點或導管，返還 75%%。")
	if _message != "":
		parts.append(_message)
	_hint.text = "　".join(parts)


# ── 截圖用的示範佈局（只在 TL_PANEL=battle 時建立）─────────────────────
#
# 指令表在 `data/Maps.gd`，與 `TL_SIM` 的 headless 跑局共用同一份——
# 截圖與數字看的必須是同一個局面。
func _demo_layout() -> void:
	var failures := BuildController.apply_ops(s, MapsData.SHOAL_DEMO)
	for f: Dictionary in failures:
		push_warning("示範佈局第 %d 步失敗：%s" % [f["index"], f["reason"]])
	# 快轉到敵潮進入塔的射程。等真實時間跑 86 秒等於讓使用者的桌面開著一個
	# 視窗發呆一分半，模擬本來就不吃 delta，直接推 tick 就好。
	#
	# ★ **推的是 tick，不是階段**（B0.6 改）：讓準備期自己倒數完、波次自己開。
	# 舊寫法直接呼叫 `start_wave()` 把倒數跳過去，B0.5 還沒差別，B0.6 之後
	# 那等於一次滿額的提前召喚（倍率 1.5），截圖的掉落數字會和 `TL_SIM`
	# （自然開波）對不起來。現在 `TL_DEMO_TICKS=N` 與 `TL_SIM=N` 是同一個局面。
	for _i in Hooks.demo_ticks:
		BattleController.step(s)
