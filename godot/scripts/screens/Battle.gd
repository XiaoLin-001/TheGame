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

## 地圖左上角。36×19 格 ×32px = 1152×608；左側 120px 留給建造欄，
## 浮層與地圖**不重疊**（RG-20 的先行實踐，正式驗收在 B0.6）。
const ORIGIN := Vector2(120.0, 56.0)

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
	_accum += delta
	var guard := 0
	while _accum >= BattleController.TICK and guard < 8:
		BattleController.step(s)
		_accum -= BattleController.TICK
		guard += 1
	_refresh_top()
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

	_draw_path()
	_draw_ore_cells()
	_draw_conduits()
	_draw_nodes()
	_draw_hover()


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
		draw_line(_center(c["a"]), _center(c["b"]), Palette.conduit(flow, cap, starving), w)
		# 升級過的幹線在端點加刻度，讓「我升過這條」在無數值下也看得見。
		for i in range(int(c["level"])):
			var t := 0.12 + 0.06 * float(i)
			draw_circle(_center(c["a"]).lerp(_center(c["b"]), t), 2.5, Palette.ORDER_BRIGHT)


func _draw_nodes() -> void:
	for n: Dictionary in s.nodes:
		var p := _center(n["cell"])
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
	_top = UiKit.hbox(20)
	_top.position = Vector2(120, 14)
	add_child(_top)
	for i in 4:
		_top.add_child(UiKit.label("", 16, Palette.TEXT_PRIMARY, false))

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

	_hint = UiKit.label("", 14, Palette.TEXT_SECONDARY, false)
	_hint.position = Vector2(120, 672)
	_hint.size = Vector2(1140, 40)
	add_child(_hint)
	_refresh_hint()


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
	# TL_NAKED：隱藏所有數值標籤，只留線寬／顏色（`30_TECH_DESIGN.md` §4.1）。
	if Hooks.naked:
		_top.visible = false
		return
	var r: Dictionary = s.rates
	var texts := [
		["礦砂 %s　▲%.1f/秒" % [UiKit.commas(int(s.ore)), r["ore_in"]], Palette.ORDER_CYAN],
		["能量 %.0f/%.0f" % [r["power_supply"], r["power_demand"]], Palette.ENERGY_AMBER],
		["儲槽 %.0f/%.0f" % [r["silo_charge"], r["silo_capacity"]], Palette.ENERGY_AMBER],
		["節點 %d　導管 %d" % [s.nodes.size(), s.conduits.size()], Palette.TEXT_SECONDARY],
	]
	for i in texts.size():
		var l := _top.get_child(i) as Label
		l.text = String(texts[i][0])
		l.add_theme_color_override("font_color", texts[i][1])


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
