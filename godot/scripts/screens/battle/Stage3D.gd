extends "res://scripts/screens/battle/Stage.gd"
## 3D 舞台（B4.0 **脊椎**，實驗性——預設不啟用，見 `TL_STAGE=3d`）。
##
## 這個檔案存在的唯一目的：**證明 `Stage.gd` 的契約是真的**——局內畫面、覆蓋層與全部 HUD 一個字不改，
## 就能跑在一個 3D 舞台上（點擊拾取、蓋節點、拉導管、縮放平移、小地圖）。
## 所以它刻意**粗糙**：節點是方塊、導管是長條、敵人是球，沒有特效、沒有地貌、沒有每種節點的造型。
## 那些是 B4.1 之後的事（`docs/70_3D_MIGRATION.md` §4、§8），而且要先等使用者拍板 D1–D7。
##
## 世界座標：**1 格 ＝ 1 單位**，`Vector3(格.x, 高度, 格.y)`；格 (cx, cy) 的中心在 (cx+0.5, 0, cy+0.5)。
## 「地圖座標」（契約裡的 `center()`／`to_screen()` 的單位）仍是格 × `Shapes.GRID` 像素，
## 這個檔案只在 `_world()` 與 `_map_px()` 兩處換算。
##
## 相機：固定俯角、**正交投影**（D3：保住導管線寬的可讀性）、只有縮放與平移。
## 世界放在一個 `SubViewport`（`own_world_3d`），`SubViewportContainer` 就是 `FRAME` 那個矩形。

const Combat := preload("res://scripts/sim/Combat.gd")
const Tide := preload("res://scripts/sim/Tide.gd")
const Build := preload("res://scripts/sim/Build.gd")
const Enemies := preload("res://data/Enemies.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")

## 相機俯角（度）。
const PITCH_DEG := 55.0
## fit 時地圖四周留的邊（倍數）。
const MARGIN := 1.04
const ZOOM_MAX_MULT := 3.0
const PAN_EASE := 14.0

const GROUND_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec4 base_color : source_color;
uniform vec4 line_color : source_color;
uniform vec2 cells;
void fragment() {
	vec2 g = fract(UV * cells);
	float w = 0.035;
	float line = clamp(step(g.x, w) + step(g.y, w), 0.0, 1.0);
	ALBEDO = mix(base_color.rgb, line_color.rgb, line);
}
"""

var _vpc: SubViewportContainer = null
var _vp: SubViewport = null
var _cam: Camera3D = null
var _static_root: Node3D = null
var _node_root: Node3D = null
var _wire_root: Node3D = null
var _foe_root: Node3D = null
var _hover_mark: MeshInstance3D = null
var _select_mark: MeshInstance3D = null

var _nodes: Dictionary = {}      # 節點 id → MeshInstance3D
var _wires: Dictionary = {}      # 導管 id → MeshInstance3D
var _foes: Dictionary = {}       # 敵人 id → MeshInstance3D
var _mats: Dictionary = {}       # 快取：(顏色, 透明) → Material
var _map_id: String = "<none>"

## 目前正交尺寸（世界單位，螢幕高度）、fit 時的尺寸、鏡頭看的那一點（格為單位）與它的目標。
var _size_now: float = 10.0
var _size_fit: float = 10.0
var _target: Vector2 = Vector2.ZERO
var _goal: Vector2 = Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vpc = SubViewportContainer.new()
	_vpc.stretch = true
	_vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vpc.position = FRAME.position
	_vpc.size = FRAME.size
	add_child(_vpc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = Vector2i(FRAME.size)
	_vpc.add_child(_vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.BG_DEEP
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Palette.TEXT_SECONDARY
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -28.0, 0.0)
	sun.light_energy = 0.9
	_vp.add_child(sun)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.1
	_cam.far = 200.0
	_vp.add_child(_cam)
	_cam.current = true
	_static_root = Node3D.new()
	_node_root = Node3D.new()
	_wire_root = Node3D.new()
	_foe_root = Node3D.new()
	for r: Node3D in [_static_root, _wire_root, _node_root, _foe_root]:
		_vp.add_child(r)
	_hover_mark = _box_mesh(Vector3(0.96, 0.03, 0.96), Palette.ORDER_BRIGHT, 0.35)
	_select_mark = _box_mesh(Vector3(1.04, 0.05, 1.04), Palette.ENERGY_AMBER, 0.5)
	_vp.add_child(_hover_mark)
	_vp.add_child(_select_mark)
	_hover_mark.visible = false
	_select_mark.visible = false


# ── 契約：視野 ─────────────────────────────────────────────────────────

func reset_view() -> void:
	_sync_map()
	var size_cells := _map_cells()
	var sin_p := sin(deg_to_rad(PITCH_DEG))
	var aspect := FRAME.size.x / FRAME.size.y
	_size_fit = maxf(size_cells.x / aspect, size_cells.y * sin_p) * MARGIN
	_size_now = _size_fit
	fit = 1.0
	zoom = 1.0
	_target = size_cells * 0.5
	_goal = _target
	pan = Vector2.ZERO
	pan_goal = Vector2.ZERO
	_apply_camera()
	view_moved.emit()


func zoom_by(mult: float, anchor: Vector2) -> void:
	var before := _ground_at(anchor)
	var new_zoom := clampf(zoom * mult, fit, fit * ZOOM_MAX_MULT)
	if is_equal_approx(new_zoom, zoom):
		return
	zoom = new_zoom
	_size_now = _size_fit / zoom
	_apply_camera()
	# 讓 `anchor` 底下那一點留在原地：量縮放後同一個螢幕點落在哪，把差補回目標。
	var after := _ground_at(anchor)
	_target += before - after
	_goal = _target
	_clamp_target()
	_apply_camera()
	view_moved.emit()
	scr.refresh_zoom()
	scr.redraw()


func pan_by(rel: Vector2) -> void:
	_target -= _px_to_ground(rel)
	_goal = _target
	_clamp_target()
	_apply_camera()
	view_moved.emit()
	scr.redraw()


func pan_to(p: Vector2, immediate: bool = false) -> void:
	# 契約裡 `p` 是「相對置中位置的螢幕像素偏移」。
	_goal = _map_cells() * 0.5 - _px_to_ground(p)
	if immediate or Motion.reduce:
		_target = _goal
	_clamp_goal()
	_apply_camera()
	view_moved.emit()
	scr.redraw()


func center_view_on(c: Vector2i, immediate: bool = false) -> void:
	_goal = Vector2(c) + Vector2(0.5, 0.5)
	if immediate or Motion.reduce:
		_target = _goal
	_clamp_goal()
	_apply_camera()
	view_moved.emit()
	scr.redraw()


func tick_view(delta: float) -> void:
	if _target.is_equal_approx(_goal):
		return
	_target = _target.lerp(_goal, 1.0 - exp(-PAN_EASE * delta))
	if _target.distance_to(_goal) < 0.01:
		_target = _goal
	_apply_camera()
	scr.redraw()


func view_world_rect() -> Rect2:
	var pts := [
		_ground_at(FRAME.position), _ground_at(FRAME.position + Vector2(FRAME.size.x, 0.0)),
		_ground_at(FRAME.end), _ground_at(FRAME.position + Vector2(0.0, FRAME.size.y)),
	]
	var lo: Vector2 = pts[0]
	var hi: Vector2 = pts[0]
	for p: Vector2 in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo * Shapes.GRID, (hi - lo) * Shapes.GRID)


func oversized() -> bool:
	var v := view_world_rect()
	var m := _map_cells() * Shapes.GRID
	return v.size.x < m.x - 0.5 or v.size.y < m.y - 0.5


# ── 契約：投影與拾取 ───────────────────────────────────────────────────

func cell_at(pos: Vector2) -> Vector2i:
	var g := _ground_at(pos)
	return Vector2i(floori(g.x), floori(g.y))


func point_at(pos: Vector2) -> Vector2:
	return _ground_at(pos) - Vector2(0.5, 0.5)


func center(c: Vector2i) -> Vector2:
	return Vector2(c) * Shapes.GRID + Vector2(Shapes.GRID, Shapes.GRID) * 0.5


func to_screen(p: Vector2) -> Vector2:
	var w := Vector3(p.x / Shapes.GRID, 0.0, p.y / Shapes.GRID)
	return _cam.unproject_position(w) + FRAME.position


func in_map(c: Vector2i) -> bool:
	var m := _map_cells()
	return c.x >= 0 and c.y >= 0 and float(c.x) < m.x and float(c.y) < m.y


# ── 每幀：把 `s` 同步成 3D ─────────────────────────────────────────────

func _process(delta: float) -> void:
	if s == null:
		return
	_sync_map()
	_derive()
	_sync_nodes()
	_sync_wires()
	_sync_foes()
	_sync_marks()


## 每幀的推導（HUD 與小地圖讀）。**同 `Stage2D._draw()` 開頭那幾行**——它們與畫法無關，
## 下一步該把它們升到 `Stage.gd`（`docs/70_3D_MIGRATION.md` §3 的「每幀推導」）。
func _derive() -> void:
	var cells := Combat.enemy_cells(s.enemies, s.path)
	engaged = Combat.engaged(s.nodes, cells)
	var out: Dictionary = {}
	for c: Vector2i in cells:
		for dx in range(-Tide.BLAST, Tide.BLAST + 1):
			for dy in range(-Tide.BLAST, Tide.BLAST + 1):
				out[c + Vector2i(dx, dy)] = true
	threat = out


func _sync_map() -> void:
	var id := String(s.map.get("id", ""))
	if id == _map_id:
		return
	_map_id = id
	for ch: Node in _static_root.get_children():
		ch.queue_free()
	var m := _map_cells()
	# 地面：一塊平面 ＋ 格線 shader。
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = m
	ground.mesh = plane
	ground.position = Vector3(m.x * 0.5, 0.0, m.y * 0.5)
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = GROUND_SHADER
	sm.set_shader_parameter("base_color", Palette.BG_PANEL)
	sm.set_shader_parameter("line_color", Palette.BORDER_SUBTLE)
	sm.set_shader_parameter("cells", m)
	ground.material_override = sm
	_static_root.add_child(ground)
	# 敵人路徑（含暈的那一圈留給 B4.3）。
	for c: Vector2i in s.path:
		var cell := _box_mesh(Vector3(1.0, 0.02, 1.0), Palette.TIDE_DEEP, 0.55)
		cell.position = _world(c, 0.012)
		_static_root.add_child(cell)
	# 礦點、跨越點。
	for c: Vector2i in s.map.get("ore", []):
		var ore := _box_mesh(Vector3(0.5, 0.03, 0.5), Palette.ORDER_CYAN, 0.55)
		ore.position = _world(c, 0.02)
		_static_root.add_child(ore)
	for c: Vector2i in s.map.get("crossings", []):
		var br := _box_mesh(Vector3(1.0, 0.07, 1.0), Palette.ORDER_CYAN, 0.8)
		br.position = _world(c, 0.04)
		_static_root.add_child(br)
	# 換圖後把鏡頭交給 `reset_view()`（`Battle._setup_session()` 緊接著會呼叫它）。


func _sync_nodes() -> void:
	var alive: Dictionary = {}
	for n: Dictionary in s.nodes:
		var id := int(n["id"])
		alive[id] = true
		var type := String(n["type"])
		var def := NodeDefs.of(type)
		var is_tower: bool = bool(def.get("tower", false))
		var is_core := type == "core"
		var mi: MeshInstance3D = _nodes.get(id)
		if mi == null:
			var h := 1.1 if is_core else (0.9 if is_tower else 0.5)
			var w := 1.2 if is_core else 0.72
			var col := Palette.ORDER_BRIGHT if is_core else (Palette.ENERGY_AMBER if is_tower else Palette.ORDER_CYAN)
			mi = _box_mesh(Vector3(w, h, w), col, 1.0)
			_node_root.add_child(mi)
			_nodes[id] = mi
			mi.set_meta("h", h)
		mi.position = _world(n["cell"], float(mi.get_meta("h")) * 0.5)
		# 缺料／缺電的節點變暗：最小的「瓶頸可見」，B4.1 再換成正式的徽章。
		var st := int((s.rates["node_state"] as Dictionary).get(id, 0))
		mi.visible = true
		mi.transparency = 0.0 if st == 0 else 0.35
	for id: int in _nodes.keys():
		if not alive.has(id):
			(_nodes[id] as Node).queue_free()
			_nodes.erase(id)


func _sync_wires() -> void:
	var alive: Dictionary = {}
	var flows: Dictionary = s.rates["conduit_flow"]
	for c: Dictionary in s.conduits:
		var id := int(c["id"])
		alive[id] = true
		var a := _world(c["a"], 0.18)
		var b := _world(c["b"], 0.18)
		var mi: MeshInstance3D = _wires.get(id)
		if mi == null:
			mi = MeshInstance3D.new()
			mi.mesh = BoxMesh.new()
			_wire_root.add_child(mi)
			_wires[id] = mi
		var span := maxf(0.01, a.distance_to(b))
		var cap := Build.conduit_cap(int(c["level"]), float(s.mods["cap_bonus"]))
		# 顏色＝負載：青（有餘裕）→ 橙（滿載）。**B4.1 才做正式的線寬／流動珠編碼。**
		var sat := clampf(float(flows.get(id, 0.0)) / maxf(cap, 0.001), 0.0, 1.0)
		var width := 0.09 + 0.07 * float(int(c["level"]))
		(mi.mesh as BoxMesh).size = Vector3(width, width, span)
		var basis := Basis.looking_at(b - a, Vector3.UP) if span > 0.011 else Basis.IDENTITY
		mi.transform = Transform3D(basis, (a + b) * 0.5)
		mi.material_override = _mat(Palette.ORDER_CYAN.lerp(Palette.WARN_ORANGE, sat), 1.0)
	for id: int in _wires.keys():
		if not alive.has(id):
			(_wires[id] as Node).queue_free()
			_wires.erase(id)


func _sync_foes() -> void:
	var alive: Dictionary = {}
	for e: Dictionary in s.enemies:
		var id := int(e["id"])
		alive[id] = true
		var mi: MeshInstance3D = _foes.get(id)
		if mi == null:
			mi = MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = 0.3
			sph.height = 0.6
			mi.mesh = sph
			mi.material_override = _mat(Palette.TIDE_MAGENTA, 1.0)
			_foe_root.add_child(mi)
			_foes[id] = mi
		var def := Enemies.of(String(e["type"]))
		var ahead := float(def.get("speed", 1.0)) * minf(float(scr.accum), BattleController.TICK)
		var prog := minf(float(e["progress"]) + ahead, float(s.path.size() - 1))
		var p := Tide.pos_of(s.path, prog)
		mi.position = Vector3(p.x + 0.5, 0.3, p.y + 0.5)
	for id: int in _foes.keys():
		if not alive.has(id):
			(_foes[id] as Node).queue_free()
			_foes.erase(id)


func _sync_marks() -> void:
	var h: Vector2i = scr.hover
	_hover_mark.visible = in_map(h)
	if _hover_mark.visible:
		_hover_mark.position = _world(h, 0.03)
	var sel: Vector2i = scr.selected
	_select_mark.visible = sel.x >= 0 and in_map(sel)
	if _select_mark.visible:
		_select_mark.position = _world(sel, 0.05)


# ── 內部：換算與相機 ───────────────────────────────────────────────────

func _map_cells() -> Vector2:
	return Vector2(s.map["size"]) if s != null and not s.map.is_empty() else Vector2(10.0, 10.0)


func _world(c: Vector2i, y: float) -> Vector3:
	return Vector3(float(c.x) + 0.5, y, float(c.y) + 0.5)


func _apply_camera() -> void:
	var p := deg_to_rad(PITCH_DEG)
	var d := 60.0
	_cam.size = _size_now
	_cam.rotation_degrees = Vector3(-PITCH_DEG, 0.0, 0.0)
	_cam.position = Vector3(_target.x, d * sin(p), _target.y + d * cos(p))


## 螢幕座標 → 地面上的點（格為單位，浮點；格的中心在 +0.5）。
func _ground_at(pos: Vector2) -> Vector2:
	var local := pos - FRAME.position
	var o := _cam.project_ray_origin(local)
	var dir := _cam.project_ray_normal(local)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(o, dir)
	if hit == null:
		return Vector2(-1000.0, -1000.0)
	var v: Vector3 = hit
	return Vector2(v.x, v.z)


## 螢幕上的相對像素 → 地面上的相對位移（格）。
func _px_to_ground(rel: Vector2) -> Vector2:
	var sin_p := sin(deg_to_rad(PITCH_DEG))
	var per_px_y := _size_now / FRAME.size.y
	return Vector2(rel.x * per_px_y, rel.y * per_px_y / sin_p)


func _clamp_goal() -> void:
	var m := _map_cells()
	_goal = Vector2(clampf(_goal.x, 0.0, m.x), clampf(_goal.y, 0.0, m.y))


func _clamp_target() -> void:
	var m := _map_cells()
	_target = Vector2(clampf(_target.x, 0.0, m.x), clampf(_target.y, 0.0, m.y))
	_goal = _target


func _mat(col: Color, alpha: float) -> StandardMaterial3D:
	var key := "%s/%.2f" % [col.to_html(), alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Palette.alpha(col, alpha)
	if alpha < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


func _box_mesh(size: Vector3, col: Color, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(col, alpha)
	return mi
