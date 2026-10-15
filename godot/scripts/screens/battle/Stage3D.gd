extends "res://scripts/screens/battle/Stage.gd"
## 傾斜舞台（B4.1）：**預設是俯瞰的 2D，往側面轉，3D 就長出來**——像地圖 App 的 3D 模式。
##
## ── 做法：地面是 2D，建築與敵人是 3D ──────────────────────────────────────────
## · **地面**（地貌、格線、路徑、導管、流動珠、礦點、特效、選取、游標、階段色調）＝ 整個 `Stage2D` 畫進一個
##   `SubViewport`，當貼圖貼在地上。它**就是**現行的 2D 舞台（一行美術都沒重寫）：所以俯瞰（`tilt = 0`）時
##   畫面與 2D 一樣，2D 修的每一個缺陷、加的每一種特效，這裡自動跟上。
## · **地形**（`Relief`）：每一格一個高度（梯田），頂面貼上面那張貼圖，格與格之間是懸崖；敵人路徑是溝、橋是拱起的橋面。
## · **建築與敵人**（`Models`）：每種各自手作的多材質網格，站在各自那一格的頂面上。
##   高度（地形與建築）一律乘 `lift`（由傾斜角決定）：俯瞰時 lift ＝ 0，一切退化成貼地的平面（建築直接隱藏，
##   露出貼圖裡的 2D 本尊）；越往側面轉，lift 越大，地才隆起、建築才長高。傾斜只是改一個 uniform，網格不必重建。
##
## ── 相機 ──────────────────────────────────────────────────────────────────
## 透視、窄視角（`FOV_DEG`）：正俯瞰時地面上每一點同深度＝與正交完全一樣（所以導管線寬的可讀性在預設視角
## 毫無損失，`20_ART_DIRECTION` R-3）；傾斜時才長出近大遠小。**只有傾斜、縮放、平移，沒有旋轉**（D3）。
## **全景（zoom ＝ fit）永遠框住整張圖**——「戰役關卡一屏可見」是鎖定的設計，而且是**每個傾斜角度**都成立：
## 傾斜一動，fit 的距離就重算（`_fit_view_h()`）。
##
## ── 座標 ──────────────────────────────────────────────────────────────────
## **1 格 ＝ 1 單位**，`Vector3(格.x, 高度, 格.y)`；格 (cx, cy) 的中心在 (cx+0.5, 頂面高度, cy+0.5)。契約的「地圖座標」仍是
## 格 × `Shapes.GRID` 像素，換算只在 `center()`／`to_screen()` 兩處。**拾取要看地形**：射線沿著地形步進（`_ground_t()`），
## `to_screen()` 投影的是那一格的**頂面**——兩者互為反運算（往返斷言在 `stage3d_test`）。**投影與拾取用自己的算式**（與 `Camera3D` 同一組
## 參數），不靠 `Camera3D` 的方法——所以不必等第一個畫面就能回答，`stage3d_test` 另有一條斷言守這兩者一致。
##
## ── 為什麼測得出來（`--script` 不載入 autoload）──────────────────────────────
## 這個檔案與它內嵌的 `Stage2D` 都不引用任何 autoload（`Stage2D` 查 `Hooks` 走節點路徑）。

const Stage2D := preload("res://scripts/screens/battle/Stage2D.gd")
const Extrude := preload("res://scripts/render/3d/Extrude.gd")
const Glyphs := preload("res://scripts/render/2d/Glyphs.gd")
const Models := preload("res://scripts/render/3d/Models.gd")
const Relief := preload("res://scripts/render/3d/Relief.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const Enemies := preload("res://data/Enemies.gd")

## 垂直視角（度）。窄＝接近正交；寬＝透視感強。
const FOV_DEG := 24.0
## 全景時，地圖四邊留的邊（倍數）：正俯瞰時 1.0（與 2D 的 fit 一模一樣），傾斜到最大時多留這麼多（地台與建築頂）。
const MARGIN_TILT := 0.05
const ZOOM_MAX_MULT := 3.0
const PAN_EASE := 14.0
const TILT_EASE := 10.0
## 傾斜到這個角度時，建築長到全高（之前以平滑曲線過渡）。
const LIFT_FULL_DEG := 38.0
## lift 小於它就不畫 3D（露出貼圖裡的 2D 本尊）。
const LIFT_SHOW := 0.012
## 地面貼圖的超取樣（相對於螢幕上的格寬）。
const GROUND_SS := 1.5
const GROUND_TEX_MAX := 4096
## 射線沿地形步進的步長（格）。
const MARCH_STEP := 0.05
## 升起程度超過這個就不再畫地面貼圖裡的扁敵人（3D 的敵人已經夠高、蓋住了它）。
const FLAT_FOE_MAX_LIFT := 0.30

## 地面：貼圖 × 頂點色（地形的受光與遮蔽）。高度與頂點色的作用都隨 lift 淡入——lift ＝ 0 時是一片平的貼圖。
## 貼圖只涵蓋視野（`uv_rect` ＝ 貼圖在地圖上的位置與大小，0..1 的地圖座標），見 `_apply_ground_window()`。
const GROUND_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_linear;
uniform float lift = 1.0;
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
varying vec3 tint;
void vertex() {
	VERTEX.y = VERTEX.y * lift;
	tint = mix(vec3(1.0), COLOR.rgb, lift);
}
void fragment() {
	ALBEDO = texture(tex, (UV - uv_rect.xy) / uv_rect.zw).rgb * tint;
}
"""

## 地面貼圖要不要真的畫（預設要）。**測試用**：`--script` 測試的替身畫面層沒有 HUD 面板，
## 2D 舞台的 `_draw()` 會去問它們；契約測試問的是投影、拾取與同步，不需要那張貼圖。
## 要在 `add_child()` 之前設。
var ground_draw: bool = true

var _view: TextureRect = null
var _vp: SubViewport = null
var _cam: Camera3D = null
var _gvp: SubViewport = null
var _ground: Stage2D = null
var _ground_mesh: MeshInstance3D = null
var _cliffs: MeshInstance3D = null
var _scenery: MeshInstance3D = null
var _node_root: Node3D = null
var _foe_root: Node3D = null
var _badge_root: Node3D = null
var _badge_mat: ShaderMaterial = null
var _solid: ShaderMaterial = null
var _ground_mat: ShaderMaterial = null

var _nodes: Dictionary = {}       # 節點 id → {mi: MeshInstance3D, key: String}
var _foes: Dictionary = {}        # 敵人 id → MeshInstance3D
var _badges: Dictionary = {}      # 節點 id → {mi: MeshInstance3D, kind: String, cell: Vector2i, h: float}
var _badge_meshes: Dictionary = {}
var _view_k: float = 1.0          # 虛擬像素 → 實際像素的倍率（視窗縮放）
var _node_meshes: Dictionary = {} # 網格快取：key → ArrayMesh
var _foe_meshes: Dictionary = {}  # 「型別|變體」→ ArrayMesh
var _boxes: Array = []            # 拾取用：[{cell, base, h, lo, hi}]（base 是地形頂面、h 是建築高，兩者都乘 lift）
var _rel: Dictionary = {}         # 這張圖的起伏（`Relief.build()`）
var _no_mesh: Dictionary = {}     # 沒有造型的型別（`stage3d_test` 要它是空的）
var _node_key: Array = []
var _map_id: String = "<none>"
var _gscale: float = 0.0
var _gwin: Vector2 = Vector2.ZERO   # 地面貼圖涵蓋的範圍大小（px，地圖座標）
var _gmap: Vector2 = Vector2.ZERO

## 目前的傾斜目標；`tilt`（契約）是緩動中的目前值。
var _goal_tilt: float = 0.0
## 目標點（格為單位）與它的追趕目標。
var _target: Vector2 = Vector2.ZERO
var _goal: Vector2 = Vector2.ZERO
## 在目標點深度上，畫面高度涵蓋幾格；全景時的值；相機離目標點多遠。
## `_whole_h` ＝ 剛好框住整張圖的高度；`_fit_h` ＝ 全景實際用的高度——大圖（無盡）受**可讀性地板**限制
## （一格至少 `Shapes.MIN_READABLE_CELL` px，與 2D 同一條，RG-58），所以只會看到圖的一部分、小地圖才現身。
var _view_h: float = 20.0
var _fit_h: float = 20.0
var _whole_h: float = 20.0
var _dist: float = 40.0
var _fit_cache_tilt: float = -1.0
var _fit_cache_map: Vector2 = Vector2.ZERO
## 目前的相機姿態（與 `Camera3D` 同一組）：位置、前方、上方。右方恆為 +X。
var _pos: Vector3 = Vector3(0.0, 40.0, 0.0)
var _f: Vector3 = Vector3(0.0, -1.0, 0.0)
var _u: Vector3 = Vector3(0.0, 0.0, -1.0)
var _th: float = tan(deg_to_rad(FOV_DEG * 0.5))
var _aspect: float = FRAME.size.x / FRAME.size.y
var _lift: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ── 地面：整個 2D 舞台畫進一個 SubViewport，當貼圖貼在地上 ──
	_gvp = SubViewport.new()
	_gvp.disable_3d = true
	_gvp.transparent_bg = false
	_gvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_gvp.size = Vector2i(1024, 512)
	add_child(_gvp)
	_ground = Stage2D.new()
	_ground.scr = scr
	_ground.s = s
	_ground.frame = Rect2(Vector2.ZERO, Vector2(_gvp.size))
	_ground.visible = ground_draw
	_ground.draw_badges = false
	_gvp.add_child(_ground)
	# 由本舞台每幀親手推進（見 `_process`）：貼圖與 3D 的資料才保證是同一幀的。
	_ground.set_process(false)

	# ── 3D 世界 ──
	# 3D 世界畫進一個 SubViewport，再用一張 TextureRect 貼在 `FRAME` 上（不用 SubViewportContainer：它把視窗解析度釘在
	# 虛擬像素，全螢幕時 3D 會被放大而糊掉；這裡的解析度跟著視窗縮放走，見 `_apply_view_scale()`）。
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = Vector2i(FRAME.size)
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_view = TextureRect.new()
	_view.texture = _vp.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.position = FRAME.position
	_view.size = FRAME.size
	add_child(_view)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.BG_DEEP
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = FOV_DEG
	_vp.add_child(_cam)
	_cam.current = true

	_solid = ShaderMaterial.new()
	_solid.shader = Shader.new()
	_solid.shader.code = Extrude.SHADER
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = Shader.new()
	_ground_mat.shader.code = GROUND_SHADER
	_ground_mat.set_shader_parameter("tex", _gvp.get_texture())

	_ground_mesh = MeshInstance3D.new()
	_ground_mesh.material_override = _ground_mat
	_vp.add_child(_ground_mesh)
	_cliffs = MeshInstance3D.new()
	_cliffs.material_override = _solid
	_vp.add_child(_cliffs)
	_scenery = MeshInstance3D.new()
	_scenery.material_override = _solid
	_vp.add_child(_scenery)
	_node_root = Node3D.new()
	_foe_root = Node3D.new()
	_badge_root = Node3D.new()
	_badge_mat = ShaderMaterial.new()
	_badge_mat.shader = Shader.new()
	_badge_mat.shader.code = Extrude.BADGE_SHADER
	_badge_mat.render_priority = 10
	_vp.add_child(_node_root)
	_vp.add_child(_foe_root)
	_vp.add_child(_badge_root)
	_apply_camera()


# ── 契約：視野 ─────────────────────────────────────────────────────────

func reset_view() -> void:
	_sync_map()
	zoom = 1.0
	fit = 1.0
	pan = Vector2.ZERO
	pan_goal = Vector2.ZERO
	_target = _map_cells() * 0.5
	_goal = _target
	_apply_camera()
	view_moved.emit()


func zoom_by(mult: float, anchor: Vector2) -> void:
	var before := _ground_at(anchor)
	var new_zoom := clampf(zoom * mult, 1.0, ZOOM_MAX_MULT)
	if is_equal_approx(new_zoom, zoom):
		return
	zoom = new_zoom
	_apply_camera()
	# 讓 `anchor` 底下那一點留在原地。透視下一步修正不夠準（目標一動，相機也動），所以收斂兩次。
	for _i in 2:
		var after := _ground_at(anchor)
		_target += before - after
		_clamp_target()
		_goal = _target
		_apply_camera()
	view_moved.emit()
	scr.refresh_zoom()
	scr.redraw()


func pan_by(rel: Vector2) -> void:
	_target += _ground_shift(rel)
	_clamp_target()
	_goal = _target
	_apply_camera()
	view_moved.emit()
	scr.redraw()


func pan_to(p: Vector2, immediate: bool = false) -> void:
	# 契約裡 `p` 是「相對置中位置的螢幕像素偏移」。
	_goal = _map_cells() * 0.5 + _ground_shift(p)
	_clamp_goal()
	if immediate or Motion.reduce:
		_target = _goal
	_apply_camera()
	view_moved.emit()
	scr.redraw()


func center_view_on(c: Vector2i, immediate: bool = false) -> void:
	_goal = Vector2(c) + Vector2(0.5, 0.5)
	_clamp_goal()
	if immediate or Motion.reduce:
		_target = _goal
	_apply_camera()
	view_moved.emit()
	scr.redraw()


func tick_view(delta: float) -> void:
	var moved := false
	if not _target.is_equal_approx(_goal):
		_target = _target.lerp(_goal, 1.0 - exp(-PAN_EASE * delta))
		if _target.distance_to(_goal) < 0.01:
			_target = _goal
		moved = true
	if not is_equal_approx(tilt, _goal_tilt):
		tilt = lerpf(tilt, _goal_tilt, 1.0 - exp(-TILT_EASE * delta))
		if absf(tilt - _goal_tilt) < 0.05:
			tilt = _goal_tilt
		moved = true
	if moved:
		_clamp_target()
		_apply_camera()
		scr.redraw()


func view_world_rect() -> Rect2:
	var pts: Array[Vector2] = [
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


# ── 契約：傾斜 ─────────────────────────────────────────────────────────

func can_tilt() -> bool:
	return true


func tilt_to(deg: float, immediate: bool = false) -> void:
	_goal_tilt = clampf(deg, 0.0, TILT_MAX)
	if immediate or Motion.reduce:
		tilt = _goal_tilt
		_clamp_target()
		_apply_camera()
	view_moved.emit()
	scr.redraw()


func tilt_by(deg: float, immediate: bool = false) -> void:
	tilt_to(_goal_tilt + deg, immediate)


func tilt_toggle() -> void:
	tilt_to(0.0 if _goal_tilt > 5.0 else TILT_DEFAULT)


## 目標角度（`tilt` 是緩動中的目前值）。
func tilt_goal() -> float:
	return _goal_tilt


## 目前的升起程度（0 ＝ 貼地的 2D，1 ＝ 全高）。
func lift() -> float:
	return _lift


# ── 契約：投影與拾取 ───────────────────────────────────────────────────

## 螢幕座標 → 格。**看得到什麼就是什麼**：傾斜後游標底下若是一棟建築（頂面或側面），回的是那一棟的格，
## 不是射線穿過它之後打到的、它後面的那塊地。
func cell_at(pos: Vector2) -> Vector2i:
	var ray := _ray(pos)
	var g := _hit_ground(ray)
	var cell := Vector2i(floori(g.x), floori(g.y))
	if _lift <= LIFT_SHOW or _boxes.is_empty():
		return cell
	var best := _ground_t(ray)
	for b: Dictionary in _boxes:
		var lo: Vector3 = b["lo"]
		var hi: Vector3 = b["hi"]
		lo.y = float(b["base"]) * _lift
		hi.y = (float(b["base"]) + float(b["h"])) * _lift
		var t := _ray_box(ray[0], ray[1], lo, hi)
		if t >= 0.0 and t < best:
			best = t
			cell = b["cell"]
	return cell


func point_at(pos: Vector2) -> Vector2:
	return _ground_at(pos) - Vector2(0.5, 0.5)


func center(c: Vector2i) -> Vector2:
	return Vector2(c) * Shapes.GRID + Vector2(Shapes.GRID, Shapes.GRID) * 0.5


## 地圖座標 → 螢幕座標：投影的是那一格**頂面**上的點（地形隆起時，格心不在 y ＝ 0）。
func to_screen(p: Vector2) -> Vector2:
	return _screen_of(Vector3(p.x / Shapes.GRID, _top_px(p) * _lift, p.y / Shapes.GRID))


## 某一格上方 `h` 格高（從頂面算起）的點的螢幕位置（徽章、浮動標記用）。
func to_screen_at(p: Vector2, h: float) -> Vector2:
	return _screen_of(Vector3(p.x / Shapes.GRID, (_top_px(p) + h) * _lift, p.y / Shapes.GRID))


func in_map(c: Vector2i) -> bool:
	var m := _map_cells()
	return c.x >= 0 and c.y >= 0 and float(c.x) < m.x and float(c.y) < m.y


func invalidate() -> void:
	if _ground != null:
		_ground.invalidate()
	_node_key = []


# ── 每幀：把 `s` 同步成 3D ─────────────────────────────────────────────

func _process(delta: float) -> void:
	if s == null or _ground == null:
		return
	_sync_map()
	_apply_view_scale()
	_apply_ground_window()
	# 地面（2D 舞台）由這裡親手推進：它的推導（交戰、威脅、敵人所在）與 3D 吃的是同一幀的值。
	_ground.s = s
	_ground.scr = scr
	# 地面貼圖涵蓋整張圖，所以敵人要靠這個範圍剔除；升起之後本體交給 3D（貼圖裡只留血量弧與減速描邊）。
	_ground.cull_rect = view_world_rect()
	_ground.draw_enemy_bodies = _lift <= FLAT_FOE_MAX_LIFT
	_ground._process(delta)
	_ground.queue_redraw()
	engaged = _ground.engaged
	threat = _ground.threat
	_sync_nodes()
	_sync_foes()


func _sync_map() -> void:
	var id := String(s.map.get("id", ""))
	var m := _map_cells()
	if id == _map_id and m == _gmap:
		return
	_map_id = id
	_gmap = m
	_gscale = 0.0
	for rec: Dictionary in _nodes.values():
		(rec["mi"] as Node).queue_free()
	_nodes.clear()
	for mi: MeshInstance3D in _foes.values():
		mi.queue_free()
	_foes.clear()
	_node_key = []
	_boxes.clear()
	for rec: Dictionary in _badges.values():
		(rec["mi"] as Node).queue_free()
	_badges.clear()
	_rel = Relief.build(s.map)
	_ground_mesh.mesh = Relief.ground_mesh(_rel)
	_cliffs.mesh = Relief.cliff_mesh(_rel)
	_scenery.mesh = Relief.scenery_mesh(s.map, _rel)
	_fit_cache_tilt = -1.0
	_gwin = Vector2.ZERO
	_apply_ground_window()


## 3D 視窗的解析度跟著視窗縮放走（全螢幕時 `FRAME` 的一個虛擬像素不只一個實際像素）。1–2.5 倍。
func _apply_view_scale() -> void:
	var vp := get_viewport()
	var k := 1.0
	if vp != null:
		k = clampf(vp.get_final_transform().get_scale().x, 1.0, 2.5)
	if is_equal_approx(k, _view_k) and _vp.size == Vector2i(FRAME.size * k):
		return
	_view_k = k
	_vp.size = Vector2i(FRAME.size * k)


## 地面貼圖只涵蓋**看得到的範圍**（視野的外接矩形外加兩格邊），不是整張圖：大圖（無盡）的 2D 內容有上千個畫布項，
## 整張圖每幀重畫太貴（壓力場景裡它佔了一半的幀時間），而引擎會把落在貼圖外的畫布項剔掉。
## · 解析度跟著**螢幕上一格有多大**走（放大看就換更大的貼圖，否則貼圖糊掉），分段（0.5 一檔）而不是連續——換檔要重配
##   render target，連續變會每幀重配；
## · 視窗大小只長不縮（縮到六成以下才縮），同樣是為了不每幀重配；
## · 視窗在地圖上的位置每幀跟著鏡頭走（改內嵌 2D 舞台的 `pan`），貼圖到地面的對應由著色器的 `uv_rect` 負責。
func _apply_ground_window() -> void:
	var map_px := _map_cells() * Shapes.GRID
	var vr := view_world_rect().grow(Shapes.GRID * 2.0)
	var want := FRAME.size.y * _view_k / maxf(_view_h, 0.001) / Shapes.GRID * GROUND_SS
	var cap := float(GROUND_TEX_MAX) / maxf(vr.size.x, vr.size.y)
	var sc := minf(clampf(ceilf(want * 2.0) / 2.0, 1.0, maxf(1.0, cap)), cap)
	var need := vr.size
	if (
		_gwin.x < need.x or _gwin.y < need.y or _gwin.x > need.x * 1.7 or _gwin.y > need.y * 1.7
		or not is_equal_approx(sc, _gscale)
	):
		_gwin = need * 1.08
	_gscale = sc
	var tex := Vector2i(ceili(_gwin.x * sc), ceili(_gwin.y * sc))
	if _gvp.size != tex:
		_gvp.size = tex
	var tex_px := Vector2(tex)
	# 框架 ＝ 貼圖本身；2D 舞台的原點（`_map_origin()` ＝ 框架中心置中 ＋ pan）對到視窗左上角。
	_ground.frame = Rect2(Vector2.ZERO, tex_px)
	_ground.zoom = sc
	_ground.fit = sc
	var origin := vr.get_center() - tex_px / sc * 0.5
	_ground.pan = -origin * sc - (tex_px - map_px * sc) * 0.5
	_ground_mat.set_shader_parameter("uv_rect", Vector4(
		origin.x / map_px.x, origin.y / map_px.y, tex_px.x / sc / map_px.x, tex_px.y / sc / map_px.y
	))


func _sync_nodes() -> void:
	var key := [s.get_instance_id(), s.tick_count, s.rev, Motion.reduce]
	if key == _node_key:
		return
	_node_key = key
	_boxes.clear()
	var alive: Dictionary = {}
	for n: Dictionary in s.nodes:
		var id := int(n["id"])
		alive[id] = true
		var type := String(n["type"])
		var lv := int(n.get("level", 0))
		var rec: Dictionary = _nodes.get(id, {})
		if rec.is_empty():
			var mi := MeshInstance3D.new()
			mi.material_override = _solid
			_node_root.add_child(mi)
			rec = {"mi": mi, "key": ""}
			_nodes[id] = rec
		var mkey := _mesh_key(n, type, lv)
		if rec["key"] != mkey:
			rec["key"] = mkey
			(rec["mi"] as MeshInstance3D).mesh = _node_mesh(n, type, lv, mkey)
		var cell: Vector2i = n["cell"]
		var base := _top(cell)
		rec["base"] = base
		(rec["mi"] as MeshInstance3D).position = Vector3(float(cell.x) + 0.5, base * _lift, float(cell.y) + 0.5)
		var half := 0.75 if type == "core" else 0.45
		_boxes.append({
			"cell": cell, "base": base, "h": Models.height_of(type, lv),
			"lo": Vector3(float(cell.x) + 0.5 - half, 0.0, float(cell.y) + 0.5 - half),
			"hi": Vector3(float(cell.x) + 0.5 + half, 0.0, float(cell.y) + 0.5 + half),
		})
	for id: int in _nodes.keys():
		if not alive.has(id):
			(_nodes[id]["mi"] as Node).queue_free()
			_nodes.erase(id)
	_sync_badges()


## 三態徽章（缺礦砂／缺電／滿溢）：**面向相機的記號**，擺在建築頂上方。正俯瞰時（lift ＝ 0）它落在節點的北邊——
## 與 2D 同一個位置、同一組形狀與顏色；傾斜後隨 lift 升到建築頂上。
func _sync_badges() -> void:
	var node_state: Dictionary = s.rates["node_state"]
	var alive: Dictionary = {}
	for n: Dictionary in s.nodes:
		var id := int(n["id"])
		var kind := ""
		match int(node_state.get(id, SessionState.NORMAL)):
			SessionState.STARVED:
				kind = "starved"
			SessionState.STARVED_POWER:
				kind = "power"
			SessionState.OVERFLOW:
				kind = "overflow"
		if kind == "":
			continue
		alive[id] = true
		var rec: Dictionary = _badges.get(id, {})
		if rec.is_empty():
			var mi := MeshInstance3D.new()
			mi.material_override = _badge_mat
			_badge_root.add_child(mi)
			rec = {"mi": mi, "kind": ""}
			_badges[id] = rec
		if rec["kind"] != kind:
			rec["kind"] = kind
			if not _badge_meshes.has(kind):
				_badge_meshes[kind] = Extrude.badge_mesh(kind)
			(rec["mi"] as MeshInstance3D).mesh = _badge_meshes[kind]
		rec["cell"] = n["cell"]
		rec["h"] = Models.height_of(String(n["type"]), int(n.get("level", 0)))
	for id: int in _badges.keys():
		if not alive.has(id):
			(_badges[id]["mi"] as Node).queue_free()
			_badges.erase(id)
	_place_badges()


## 徽章的位置隨 lift 變：lift ＝ 0 在 2D 徽章的位置（節點中心往北 20 px），lift ＝ 1 在建築頂上方。
func _place_badges() -> void:
	for rec: Dictionary in _badges.values():
		var cell: Vector2i = rec["cell"]
		var cx := float(cell.x) + 0.5
		var cz := float(cell.y) + 0.5
		var base := _top(cell)
		var ground := Vector3(cx, base * _lift + 0.02, cz - 20.0 / Shapes.GRID)
		var top := Vector3(cx, (base + float(rec["h"])) * _lift + 0.42, cz - 0.06)
		(rec["mi"] as MeshInstance3D).position = ground.lerp(top, _lift)


## 一座節點的網格快取鍵：**畫它會讀的每一個輸入**（級數、受傷、儲槽的充能格、核心的心跳 tick）。
func _mesh_key(n: Dictionary, type: String, lv: int) -> String:
	var hurt := float(n["hp"]) < NodeDefs.hp(type)
	var bucket := 0
	if type == "silo":
		bucket = int(float(n.get("charge", 0.0)) / maxf(1.0, float(NodeDefs.of("silo")["capacity"])) * 16.0)
	return "%s|%d|%d|%d|%d|%d" % [type, lv, int(hurt), bucket, s.tick_count if type == "core" else 0, int(Motion.reduce)]


func _node_mesh(n: Dictionary, type: String, lv: int, mkey: String) -> ArrayMesh:
	if _node_meshes.has(mkey):
		return _node_meshes[mkey]
	if _node_meshes.size() > 400:
		_node_meshes.clear()   # 核心每 tick 一把鍵：不清會一路長
	var mesh: ArrayMesh = Models.node(n, s.tick_count)
	if Extrude.triangle_count(mesh) == 0:
		# 沒有配方：退回把 2D 零件擠高（不會是隱形的塔），並記下來讓測試變紅。
		_no_mesh[type] = true
		var parts: Array = Glyphs.build_for(n, Vector2.ZERO, s.tick_count)
		mesh = Extrude.glyph_mesh(parts, Models.height_of(type, lv), Glyphs.scale_for(n))
	_node_meshes[mkey] = mesh
	return mesh


func _sync_foes() -> void:
	var alive: Dictionary = {}
	# 視野外的敵人不建、不擺（放大看大圖時，其餘的敵人白白佔 draw call）；邊距比最大的敵人寬鬆。
	var view := view_world_rect().grow(Shapes.GRID * 2.0)
	for i in s.enemies.size():
		var e: Dictionary = s.enemies[i]
		var id := int(e["id"])
		alive[id] = true
		var mi: MeshInstance3D = _foes.get(id)
		if not view.has_point(_ground._enemy_pos(e, i)):
			if mi != null:
				mi.visible = false
			continue
		if mi == null:
			mi = MeshInstance3D.new()
			mi.material_override = _solid
			mi.mesh = _foe_mesh(String(e["type"]), id)
			_foe_root.add_child(mi)
			_foes[id] = mi
		# 位置與朝向問 2D 舞台：地面貼圖裡那隻扁的與這隻立體的，必然在同一個地方。
		var p: Vector2 = _ground._enemy_pos(e, i)
		var d: Vector2 = _ground._enemy_dir(e, i)
		var cell := Vector2i(floori(p.x / Shapes.GRID), floori(p.y / Shapes.GRID))
		mi.visible = true
		# 走在**地面**上（橋底下是溝）；每一隻有自己的相位，輕輕上下晃（`reduce_motion` 時不晃）。
		var bob := 0.0 if Motion.reduce else 0.018 * sin(_ground._time_s() * 7.0 + float(id) * 1.7)
		mi.position = Vector3(p.x / Shapes.GRID, (Relief.floor_at(_rel, cell) + bob) * _lift, p.y / Shapes.GRID)
		mi.rotation.y = atan2(-d.y, d.x)
	for id: int in _foes.keys():
		if not alive.has(id):
			(_foes[id] as Node).queue_free()
			_foes.erase(id)


## 敵人的網格：一型四個變體（用 id 取），色相在品紅帶內小幅位移，同一型的幾隻不會長得一模一樣。
func _foe_mesh(type: String, id: int) -> ArrayMesh:
	var key := "%s|%d" % [type, id % 4]
	if not _foe_meshes.has(key):
		_foe_meshes[key] = Models.foe(Enemies.of(type), id % 4)
	return _foe_meshes[key]


# ── 測試用的讀值 ───────────────────────────────────────────────────────

func ground_stage() -> Node:
	return _ground


func node_count() -> int:
	return _nodes.size()


func foe_count() -> int:
	return _foes.size()


func badge_count() -> int:
	return _badges.size()


func ground_scale() -> float:
	return _gscale


## 這張圖的起伏（`Relief.build()` 的結果）。
func relief() -> Dictionary:
	return _rel


## 沒有造型的節點型別（要是空的）。
func missing_meshes() -> Array:
	return _no_mesh.keys()


## 現在 3D 世界有沒有在畫（lift 夠大）。
func raised() -> bool:
	return _lift > LIFT_SHOW


# ── 內部：相機 ─────────────────────────────────────────────────────────

func _map_cells() -> Vector2:
	return Vector2(s.map["size"]) if s != null and not s.map.is_empty() else Vector2(10.0, 10.0)


## 相機姿態：位置、前方、上方、離目標點的距離。`tilt_deg` ＝ 0 時正俯瞰。
static func _pose(view_h: float, tilt_deg: float, target: Vector2) -> Array:
	var p := deg_to_rad(90.0 - tilt_deg)
	var f := Vector3(0.0, -sin(p), -cos(p))
	var u := Vector3(0.0, cos(p), -sin(p))
	var dist := view_h * 0.5 / tan(deg_to_rad(FOV_DEG * 0.5))
	return [Vector3(target.x, 0.0, target.y) - f * dist, f, u, dist]


## 世界點 → NDC（x, y ∈ [-1, 1] 在畫面內）＋ 深度。深度 ≤ 0 ＝ 在相機後面。
static func _ndc(pose: Array, aspect: float, x: Vector3) -> Vector3:
	var pos: Vector3 = pose[0]
	var f: Vector3 = pose[1]
	var u: Vector3 = pose[2]
	var th := tan(deg_to_rad(FOV_DEG * 0.5))
	var v := x - pos
	var zc := v.dot(f)
	if zc < 0.001:
		return Vector3(INF, INF, zc)
	return Vector3(v.x / (zc * th * aspect), v.dot(u) / (zc * th), zc)


## 這個傾斜角下，剛好框住整張圖（含 `MARGIN`）所需的畫面高度（格）。二分搜尋：距離變大，
## 四個角單調地往畫面中心收，所以「塞得下」對距離是單調的。四個角取**地形最高處**那個高度（隆起的圖邊緣最容易出框）。
func _fit_view_h(t_deg: float) -> float:
	var margin := 1.0 + MARGIN_TILT * clampf(t_deg / TILT_MAX, 0.0, 1.0)
	var m := _map_cells()
	if is_equal_approx(t_deg, _fit_cache_tilt) and m == _fit_cache_map:
		return _whole_h
	var c := m * 0.5
	var y := float(_rel.get("max", 0.0)) * _lift_of(t_deg)
	var corners: Array[Vector3] = [
		Vector3(0.0, y, 0.0), Vector3(m.x, y, 0.0), Vector3(m.x, y, m.y), Vector3(0.0, y, m.y),
	]
	var lo := 1.0
	var hi := 800.0
	for _i in 32:
		var mid := (lo + hi) * 0.5
		var pose := _pose(mid, t_deg, c)
		var ok := true
		for x: Vector3 in corners:
			var n := _ndc(pose, _aspect, x)
			if not is_finite(n.x) or absf(n.x) > 1.0 / margin or absf(n.y) > 1.0 / margin:
				ok = false
				break
		if ok:
			hi = mid
		else:
			lo = mid
	_fit_cache_tilt = t_deg
	_fit_cache_map = m
	_whole_h = hi
	return hi


## 把 `tilt`、`zoom`、`_target` 套到相機、升起程度與各個 3D 節點上。
func _apply_camera() -> void:
	if _cam == null:
		return
	var whole := _fit_view_h(tilt)
	# 可讀性地板：一格至少 `MIN_READABLE_CELL` px ⇒ 畫面最多涵蓋這麼多格。一屏可見的戰役關卡永遠 whole ≤ 地板。
	_fit_h = minf(whole, FRAME.size.y / Shapes.MIN_READABLE_CELL)
	_view_h = _fit_h / maxf(zoom, 1.0)
	var pose := _pose(_view_h, tilt, _target)
	_pos = pose[0]
	_f = pose[1]
	_u = pose[2]
	_dist = pose[3]
	_cam.transform = Transform3D(Basis(Vector3.RIGHT, _u, -_f), _pos)
	var diag := _map_cells().length()
	_cam.near = maxf(0.05, _dist * 0.3)
	_cam.far = _dist * 2.6 + diag
	_lift = _lift_of(tilt)
	_solid.set_shader_parameter("lift", _lift)
	_ground_mat.set_shader_parameter("lift", _lift)
	_place_nodes()
	_place_badges()
	var show := _lift > LIFT_SHOW
	_cliffs.visible = show
	_scenery.visible = show
	_node_root.visible = show
	_foe_root.visible = show


## 傾斜角 → 升起程度（0..1，平滑曲線）。
static func _lift_of(tilt_deg: float) -> float:
	var t := clampf(tilt_deg / LIFT_FULL_DEG, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## 這一格頂面的高度（格；沒乘 lift）。圖外是 0。
func _top(c: Vector2i) -> float:
	return Relief.top_at(_rel, c) if not _rel.is_empty() else 0.0


## 地圖座標（px）所在那一格的頂面高度。
func _top_px(p: Vector2) -> float:
	return _top(Vector2i(floori(p.x / Shapes.GRID), floori(p.y / Shapes.GRID)))


## 世界點在地形表面之下嗎（含剛好在面上）？圖外的表面是 y ＝ 0。
func _below(p: Vector3) -> bool:
	return p.y <= _top(Vector2i(floori(p.x), floori(p.z))) * _lift


## 把所有建築擺到各自那一格的頂面上（頂面高度隨 lift 變）。
func _place_nodes() -> void:
	for rec: Dictionary in _nodes.values():
		var mi := rec["mi"] as MeshInstance3D
		mi.position.y = float(rec.get("base", 0.0)) * _lift


## 螢幕座標 → 射線 [起點, 單位方向]。
func _ray(pos: Vector2) -> Array:
	var nx := (pos.x - FRAME.position.x) / FRAME.size.x * 2.0 - 1.0
	var ny := 1.0 - (pos.y - FRAME.position.y) / FRAME.size.y * 2.0
	var dir := Vector3.RIGHT * (nx * _th * _aspect) + _u * (ny * _th) + _f
	return [_pos, dir.normalized()]


## 射線打到**地形表面**的參數 t（沿單位方向的距離）；打不到回極大值。
## 俯瞰（lift ≈ 0）或圖是平的：就是 y ＝ 0 的平面。否則在「地形最高處以下」那一段薄層裡等距步進，
## 找到第一個落到表面之下的取樣，再二分逼近——層厚最多約 0.4 格，步長 `MARCH_STEP`，每次拾取不過二十來步。
func _ground_t(ray: Array) -> float:
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	if d.y > -0.0001:
		return 1.0e9
	var t_plane := -o.y / d.y
	var top_y := float(_rel.get("max", 0.0)) * _lift
	if _lift <= LIFT_SHOW or top_y < 0.002:
		return t_plane
	var t0 := maxf(0.0, (top_y - o.y) / d.y)
	var t_prev := t0
	var t := t0
	while t <= t_plane + MARCH_STEP:
		if _below(o + d * t):
			var lo := t_prev
			var hi := t
			for _i in 14:
				var mid := (lo + hi) * 0.5
				if _below(o + d * mid):
					hi = mid
				else:
					lo = mid
			return hi
		t_prev = t
		t += MARCH_STEP
	return t_plane


## 射線打到地面的點（格為單位，浮點；格的中心在 +0.5）。
func _hit_ground(ray: Array) -> Vector2:
	var t := _ground_t(ray)
	if t >= 1.0e8:
		return Vector2(-1000.0, -1000.0)
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	var hit := o + d * t
	return Vector2(hit.x, hit.z)


func _ground_at(pos: Vector2) -> Vector2:
	return _hit_ground(_ray(pos))


## 射線與軸對齊方盒的進入點 t（沒打到回 -1）。
static func _ray_box(o: Vector3, d: Vector3, lo: Vector3, hi: Vector3) -> float:
	var t0 := 0.0
	var t1 := 1.0e9
	for axis in 3:
		var oa: float = o[axis]
		var da: float = d[axis]
		if absf(da) < 1.0e-9:
			if oa < lo[axis] or oa > hi[axis]:
				return -1.0
			continue
		var ta := (lo[axis] - oa) / da
		var tb := (hi[axis] - oa) / da
		if ta > tb:
			var sw := ta
			ta = tb
			tb = sw
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return -1.0
	return t0


## 世界點 → 螢幕座標。
func _screen_of(x: Vector3) -> Vector2:
	var n := _ndc([_pos, _f, _u, _dist], _aspect, x)
	if not is_finite(n.x):
		return Vector2(-1000.0, -1000.0)
	return FRAME.position + Vector2((n.x * 0.5 + 0.5) * FRAME.size.x, (0.5 - n.y * 0.5) * FRAME.size.y)


## 螢幕上拖 `rel` 像素，目標點要在地面上挪多少（格）。**抓著地面拖**：以畫面中心為基準量兩次射線，
## 正俯瞰時精確，傾斜時是中心附近的近似（遠處的地面看起來會比手指慢一點）。
func _ground_shift(rel: Vector2) -> Vector2:
	var c := FRAME.position + FRAME.size * 0.5
	return _ground_at(c) - _ground_at(c + rel)


func _clamp_goal() -> void:
	var lim := _pan_limit()
	var c := _map_cells() * 0.5
	_goal = Vector2(clampf(_goal.x, c.x - lim.x, c.x + lim.x), clampf(_goal.y, c.y - lim.y, c.y + lim.y))


func _clamp_target() -> void:
	var lim := _pan_limit()
	var c := _map_cells() * 0.5
	_target = Vector2(clampf(_target.x, c.x - lim.x, c.x + lim.x), clampf(_target.y, c.y - lim.y, c.y + lim.y))
	_goal.x = clampf(_goal.x, c.x - lim.x, c.x + lim.x)
	_goal.y = clampf(_goal.y, c.y - lim.y, c.y + lim.y)


## 目標點離地圖中心最遠能走多遠：整張圖剛好裝得進畫面時是 0（fit 時平移恆為 0），放大後線性放寬，
## 看到整張圖的 1/N 時恰好走得到邊（視野只剩 1/N，中心走到「邊 − 半個視野」）。大圖（受可讀性地板限制）全景時就已經大於 1。
func _pan_limit() -> Vector2:
	var eff := _whole_h / maxf(_view_h, 0.001)
	return _map_cells() * 0.5 * (1.0 - 1.0 / maxf(eff, 1.0))
