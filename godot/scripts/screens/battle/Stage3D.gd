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
const Build := preload("res://scripts/sim/Build.gd")
const Prof := preload("res://scripts/core/Prof.gd")
const Tide := preload("res://scripts/sim/Tide.gd")
const BattleController := preload("res://scripts/game/BattleController.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const Fx3D := preload("res://scripts/render/3d/Fx3D.gd")
const Wires := preload("res://scripts/render/3d/Wires.gd")

## 垂直視角（度）。窄＝接近正交；寬＝透視感強。
const FOV_DEG := 24.0
## 全景時，地圖四邊留的邊（倍數）：正俯瞰時 1.0（與 2D 的 fit 一模一樣），傾斜到最大時多留這麼多（地台與建築頂）。
const MARGIN_TILT := 0.05
const ZOOM_MAX_MULT := 3.0
const PAN_EASE := 14.0
const TILT_EASE := 10.0
const YAW_EASE := 10.0
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
## 敵人身體中段離地的高度（格）：彈著點、碎片爆、護盾的中心。
const FOE_BODY_Y := 0.2
## 流動珠的半徑相對於 2D 的倍率（3D 的珠子是球，擺在管子上）。
const BEAD_K := 1.15

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

## 落點預覽：同 `Extrude.SHADER`，半透明、往 `tint`（可放／不可放）推一點；不寫深度，疊起來的零件會透出來（鬼影的樣子）。
const GHOST_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float lift = 1.0;
uniform vec3 tint = vec3(0.4, 0.8, 0.6);
uniform float alpha = 0.62;
void vertex() {
	VERTEX.y = VERTEX.y * lift + UV.x * 0.0025;
}
void fragment() {
	ALBEDO = mix(COLOR.rgb, tint, 0.28);
	ALPHA = alpha;
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
var _solid_hit: ShaderMaterial = null    # 受擊一閃（`Extrude.FLASH_SHADER`）

# 特效、導管、珠子、落點預覽（B4.3）。
var _fx_mesh: ArrayMesh = null
var _fx_top_mesh: ArrayMesh = null
var _fx_mi: MeshInstance3D = null
var _fx_top_mi: MeshInstance3D = null
var _wire_mm: MultiMesh = null       # 所有導管：單位方盒的實例（一個 draw call）
var _wire_mmi: MultiMeshInstance3D = null
var _wire_mat: ShaderMaterial = null
var _wire_buf: PackedFloat32Array = PackedFloat32Array()
var _wires: Dictionary = {}        # 導管 id → {sig: Array, chunk: PackedFloat32Array, key: Vector4i}
var _routes: Dictionary = {}       # Vector4i（a.x, a.y, b.x, b.y）→ {rt: PackedVector3Array（管底路徑）, hh: 半個管厚}
var _wire_key: Array = []
var _shadow_mm: MultiMesh = null    # 敵人的落影：一個 MultiMesh
var _shadow_mmi: MultiMeshInstance3D = null
var _shadow_buf: PackedFloat32Array = PackedFloat32Array()
var _rw: int = 0                    # 這張圖的起伏（`_rel`）的快取：寬、地面高度陣列（每隻敵人每幀查一次，不走字典）
var _rfloor: PackedFloat32Array = PackedFloat32Array()
var _bead_mmi: MultiMeshInstance3D = null
var _bead_mm: MultiMesh = null
var _bead_buf: PackedFloat32Array = PackedFloat32Array()
var _ghost: MeshInstance3D = null
var _ghost_mat: ShaderMaterial = null
var _ghost_meshes: Dictionary = {}
var _ghost_key: Array = []
var _ghost_ok: bool = false
var _foe_info: PackedFloat32Array = PackedFloat32Array()   # 本幀畫出來的敵人，每隻 5 個：x（格）、z（格）、地面高、半徑（格）、血量比例（落影、血條用）
var _foe_motions: Dictionary = {}  # 型別 → `Models.foe_motion()`

var _nodes: Dictionary = {}       # 節點 id → {mi: MeshInstance3D, key: String}
var _foes: Dictionary = {}        # 敵人 id → MeshInstance3D
var _badges: Dictionary = {}      # 節點 id → {mi: MeshInstance3D, kind: String, cell: Vector2i, h: float}
var _badge_meshes: Dictionary = {}
var _view_k: float = 1.0          # 虛擬像素 → 實際像素的倍率（視窗縮放）
var _node_meshes: Dictionary = {} # 網格快取：key → ArrayMesh
var _foe_meshes: Dictionary = {}  # 「型別|變體」→ ArrayMesh
var _boxes: Array = []            # 拾取用：[{cell, base, h, lo, hi}]（base 是地形頂面、h 是建築高，兩者都乘 lift）
var _rel: Dictionary = {}         # 這張圖的起伏（`Relief.build()`）
var _scenery_parts: Array = []    # 這張圖的擺設零件（`Terrain.build()`，同一張圖不變）
var _scenery_key: Array = []
var _scenery_occ: Dictionary = {} # 蓋住擺設的格（建築 1、導管 2）；沒變就不重蓋網格
var _no_mesh: Dictionary = {}     # 沒有造型的型別（`stage3d_test` 要它是空的）
var _node_key: Array = []
var _map_id: String = "<none>"
var _gscale: float = 0.0
var _gwin: Vector2 = Vector2.ZERO   # 地面貼圖涵蓋的範圍大小（px，地圖座標）
var _gmap: Vector2 = Vector2.ZERO

## 目前的傾斜目標；`tilt`（契約）是緩動中的目前值。
var _goal_tilt: float = 0.0
## 目前的旋轉目標（0..360）；`yaw`（契約）是緩動中的目前值。
var _goal_yaw: float = 0.0
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
var _fit_cache: Dictionary = {}    # （傾斜, 旋轉, 圖大小）→ 剛好框住整張圖的高度（`_fit_view_h()`）
## 目前的相機姿態（與 `Camera3D` 同一組）：位置、前方、上方、右方（旋轉之後右方不再恆為 +X）。
var _pos: Vector3 = Vector3(0.0, 40.0, 0.0)
var _r: Vector3 = Vector3.RIGHT
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

	_solid_hit = ShaderMaterial.new()
	_solid_hit.shader = Shader.new()
	_solid_hit.shader.code = Extrude.FLASH_SHADER
	var fc := Palette.TIDE_BRIGHT
	_solid_hit.set_shader_parameter("flash_col", Vector3(fc.r, fc.g, fc.b))
	# 導管與珠子：各是一個 MultiMesh（一個 draw call）。導管的變換在世界座標乘 lift（`Wires.SHADER`）。
	_wire_mm = MultiMesh.new()
	_wire_mm.transform_format = MultiMesh.TRANSFORM_3D
	_wire_mm.use_colors = true
	_wire_mm.mesh = Wires.box_mesh()
	_wire_mat = ShaderMaterial.new()
	_wire_mat.shader = Shader.new()
	_wire_mat.shader.code = Wires.SHADER
	_wire_mmi = MultiMeshInstance3D.new()
	_wire_mmi.multimesh = _wire_mm
	_wire_mmi.material_override = _wire_mat
	_wire_mmi.custom_aabb = AABB(Vector3(-1.0, -1.0, -1.0), Vector3(512.0, 8.0, 512.0))
	_vp.add_child(_wire_mmi)
	_bead_mm = MultiMesh.new()
	_bead_mm.transform_format = MultiMesh.TRANSFORM_3D
	_bead_mm.use_colors = true
	_bead_mm.mesh = Wires.bead_mesh()
	_bead_mmi = MultiMeshInstance3D.new()
	_bead_mmi.multimesh = _bead_mm
	var bead_mat := ShaderMaterial.new()
	bead_mat.shader = Shader.new()
	bead_mat.shader.code = Wires.BEAD_SHADER
	_bead_mmi.material_override = bead_mat
	_bead_mmi.custom_aabb = AABB(Vector3(-1.0, -1.0, -1.0), Vector3(512.0, 8.0, 512.0))
	_vp.add_child(_bead_mmi)
	# 敵人的落影：腳下一圈淡淡的暗（一個 MultiMesh，不為每隻敵人各建一圈幾何）。
	_shadow_mm = MultiMesh.new()
	_shadow_mm.transform_format = MultiMesh.TRANSFORM_3D
	_shadow_mm.use_colors = true
	_shadow_mm.mesh = Fx3D.disc_mesh(12)
	var shadow_mat := ShaderMaterial.new()
	shadow_mat.shader = Shader.new()
	shadow_mat.shader.code = Fx3D.SHADER
	shadow_mat.render_priority = 3
	_shadow_mmi = MultiMeshInstance3D.new()
	_shadow_mmi.multimesh = _shadow_mm
	_shadow_mmi.material_override = shadow_mat
	_shadow_mmi.custom_aabb = AABB(Vector3(-1.0, -1.0, -1.0), Vector3(512.0, 8.0, 512.0))
	_shadow_mmi.visible = false
	_vp.add_child(_shadow_mmi)
	# 特效：一般的（深度測試）與永遠看得見的（血條）各一個重複使用的網格。
	_fx_mesh = ArrayMesh.new()
	_fx_top_mesh = ArrayMesh.new()
	var fx_mat := ShaderMaterial.new()
	fx_mat.shader = Shader.new()
	fx_mat.shader.code = Fx3D.SHADER
	fx_mat.render_priority = 5
	var fx_top_mat := ShaderMaterial.new()
	fx_top_mat.shader = Shader.new()
	fx_top_mat.shader.code = Fx3D.TOP_SHADER
	fx_top_mat.render_priority = 11
	_fx_mi = MeshInstance3D.new()
	_fx_mi.mesh = _fx_mesh
	_fx_mi.material_override = fx_mat
	_fx_mi.visible = false
	_vp.add_child(_fx_mi)
	_fx_top_mi = MeshInstance3D.new()
	_fx_top_mi.mesh = _fx_top_mesh
	_fx_top_mi.material_override = fx_top_mat
	_fx_top_mi.visible = false
	_vp.add_child(_fx_top_mi)
	# 落點預覽：手上那一種建築的半透明造型。
	_ghost_mat = ShaderMaterial.new()
	_ghost_mat.shader = Shader.new()
	_ghost_mat.shader.code = GHOST_SHADER
	_ghost_mat.render_priority = 4
	_ghost = MeshInstance3D.new()
	_ghost.material_override = _ghost_mat
	_ghost.visible = false
	_vp.add_child(_ghost)
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
	if not is_equal_approx(yaw, _goal_yaw):
		var dy := wrapf(_goal_yaw - yaw, -180.0, 180.0)
		if absf(dy) < 0.05:
			yaw = _goal_yaw
		else:
			yaw = fposmod(yaw + dy * (1.0 - exp(-YAW_EASE * delta)), 360.0)
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


## 看到的比整張圖少嗎？**用相機高度比，不用外接矩形**：旋轉之後外接矩形比真正看到的大，而「整張圖剛好裝進框架」
## 的 `_whole_h` 是跟著旋轉算的（`_fit_view_h()`）。放大或被可讀性地板限制時 `_view_h` 都小於它。
func oversized() -> bool:
	return _view_h < _whole_h - 0.001


func view_quad() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in [FRAME.position, FRAME.position + Vector2(FRAME.size.x, 0.0), FRAME.end, FRAME.position + Vector2(0.0, FRAME.size.y)]:
		out.append(_ground_at(p) * Shapes.GRID)
	return out


func in_view(p: Vector2) -> bool:
	return FRAME.has_point(to_screen(p))


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


# ── 契約：旋轉 ─────────────────────────────────────────────────────────

func can_rotate() -> bool:
	return true


func yaw_to(deg: float, immediate: bool = false) -> void:
	_goal_yaw = fposmod(deg, 360.0)
	if immediate or Motion.reduce:
		yaw = _goal_yaw
		_clamp_target()
		_apply_camera()
	view_moved.emit()
	scr.redraw()


func yaw_by(deg: float, immediate: bool = false) -> void:
	yaw_to(_goal_yaw + deg, immediate)


## 目標角度（`yaw` 是緩動中的目前值）。
func yaw_goal() -> float:
	return _goal_yaw


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
	Prof.mark()
	_sync_map()
	_apply_view_scale()
	_apply_ground_window()
	Prof.lap("s3d.window")
	# 地面（2D 舞台）由這裡親手推進：它的推導（交戰、威脅、敵人所在）與 3D 吃的是同一幀的值。
	_ground.s = s
	_ground.scr = scr
	# 地面貼圖涵蓋整張圖，所以敵人要靠這個範圍剔除；升起之後本體交給 3D（貼圖裡只留血量弧與減速描邊）。
	_ground.cull_rect = view_world_rect()
	_ground.draw_enemy_bodies = _lift <= FLAT_FOE_MAX_LIFT
	# 特效、血量弧：升起之後改畫在 3D。導管、珠子、落點預覽：一離開正俯瞰就改成 3D 的（低 lift 時 3D 的管子是貼地的帶，與 2D 的線同寬）。
	_ground.draw_fx = _lift <= FLAT_FOE_MAX_LIFT
	_ground.draw_wires = _lift <= LIFT_SHOW
	_ground.draw_ghost = _lift <= LIFT_SHOW
	_ground._process(delta)
	_ground.queue_redraw()
	engaged = _ground.engaged
	threat = _ground.threat
	Prof.lap("s3d.ground")
	_sync_nodes()
	Prof.lap("s3d.nodes")
	_sync_wires()
	Prof.lap("s3d.wires")
	_sync_scenery()
	Prof.lap("s3d.scenery")
	_sync_foes()
	Prof.lap("s3d.foes")
	_sync_fx()
	Prof.lap("s3d.fx")
	_sync_ghost()
	_update_beads()
	Prof.lap("s3d.beads")


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
	_wires.clear()
	_routes.clear()
	_wire_key = []
	_ghost_key = []
	_rel = Relief.build(s.map)
	_rw = int(_rel["w"])
	_rfloor = _rel["floor"]
	_ground_mesh.mesh = Relief.ground_mesh(_rel)
	_cliffs.mesh = Relief.cliff_mesh(_rel)
	_scenery_parts = Terrain.build(s.map, Shapes.GRID, 1)
	_scenery_occ = {}
	_scenery_key = []
	_scenery.mesh = Relief.scenery_mesh(s.map, _rel, {}, _scenery_parts)
	_fit_cache.clear()
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


## 擺設（岩石、貝殼、苔、礦點的水晶）是一張靜態網格。玩家蓋了東西（`s.rev` 變了）才檢查要不要重蓋：
## 岩石不長在建築與導管底下（`Relief.scenery_mesh()` 的 `occ`）。佔用的格沒變就不重蓋（升級、改線寬不會讓它重蓋）。
func _sync_scenery() -> void:
	var key := [s.get_instance_id(), s.rev, _map_id]
	if key == _scenery_key:
		return
	_scenery_key = key
	var occ := _occupied()
	if occ == _scenery_occ:
		return
	_scenery_occ = occ
	_scenery.mesh = Relief.scenery_mesh(s.map, _rel, occ, _scenery_parts)


## 玩家蓋了東西的格：建築 ＝ 1；導管經過的格（沿線每 0.25 格、兩側各 0.2 格的腳印）＝ 2。
func _occupied() -> Dictionary:
	var occ: Dictionary = {}
	for c: Dictionary in s.conduits:
		var ca: Vector2i = c["a"]
		var cb: Vector2i = c["b"]
		var pa := Vector2(ca) + Vector2(0.5, 0.5)
		var pb := Vector2(cb) + Vector2(0.5, 0.5)
		var n := maxi(1, ceili(pa.distance_to(pb) / 0.25))
		var dir := (pb - pa).normalized() if pa != pb else Vector2.RIGHT
		var perp := Vector2(-dir.y, dir.x)
		for i in n + 1:
			var p := pa.lerp(pb, float(i) / float(n))
			for lat: float in [-0.2, 0.0, 0.2]:
				var q := p + perp * lat
				occ[Vector2i(floori(q.x), floori(q.y))] = 2
	for nd: Dictionary in s.nodes:
		occ[nd["cell"]] = 1
	return occ


func _sync_foes() -> void:
	var alive: Dictionary = {}
	_foe_info.resize(0)
	# 視野外的敵人不建、不擺（放大看大圖時，其餘的敵人白白佔 draw call）；邊距比最大的敵人寬鬆。
	var view := view_world_rect().grow(Shapes.GRID * 2.0)
	var hit_ids: Dictionary = _ground._hit_ids_of()
	var tsec: float = _ground._time_s()
	var animate := not Motion.reduce
	for i in s.enemies.size():
		var e: Dictionary = s.enemies[i]
		var id := int(e["id"])
		alive[id] = true
		var mi: MeshInstance3D = _foes.get(id)
		# 位置與朝向問 2D 舞台：地面貼圖裡那隻扁的與這隻立體的，必然在同一個地方（同一個 progress）。
		var prog: float = _ground._enemy_prog(e, i)
		var p: Vector2 = _ground._path_px(prog)
		if not view.has_point(p):
			if mi != null:
				mi.visible = false
			continue
		var type := String(e["type"])
		var def := Enemies.of(type)
		if mi == null:
			mi = MeshInstance3D.new()
			mi.mesh = _foe_mesh(type, id)
			_foe_root.add_child(mi)
			_foes[id] = mi
		# 受擊一閃：這一 tick 有彈落在它身上，本體往亮階推一下（換材質，不必逐實例參數）。
		mi.material_override = _solid_hit if hit_ids.has(id) else _solid
		var d: Vector2 = Tide.heading_of(s.path, prog)
		var gx := p.x / Shapes.GRID
		var gz := p.y / Shapes.GRID
		var floor_y := _floor_at(floori(gx), floori(gz))
		mi.visible = true
		# 走在**地面**上（橋底下是溝）。動作由機制欄位推導（`Models.foe_motion`）：重甲慢而沉、迅捷前傾、再生有心跳……
		# 每一隻有自己的相位；`reduce_motion` 時不動。
		var yaw := atan2(-d.y, d.x)
		var hop := 0.0
		if animate:
			var pose := Models.foe_pose(_foe_motion(type, def), tsec, float(id) * 1.7)
			mi.basis = Basis.from_euler(Vector3(float(pose["roll"]), yaw, float(pose["pitch"])), EULER_ORDER_YZX).scaled_local(pose["scale"])
			hop = float(pose["hop"])
		else:
			mi.basis = Basis(Vector3.UP, yaw)
		mi.position = Vector3(gx, (floor_y + hop) * _lift, gz)
		_foe_info.append(gx)
		_foe_info.append(gz)
		_foe_info.append(floor_y)
		_foe_info.append(maxf(float(def.get("radius", 9.0)) / Shapes.GRID, Models.MIN_FOE_RADIUS))
		_foe_info.append(float(e["hp"]) / maxf(1.0, float(e.get("max_hp", def.get("hp", 1.0)))))
	for id: int in _foes.keys():
		if not alive.has(id):
			(_foes[id] as Node).queue_free()
			_foes.erase(id)


## 這一格的**地面**高度（敵人走的；橋底下是溝）。圖外是 0。比 `Relief.floor_at()` 快：不走字典。
func _floor_at(cx: int, cy: int) -> float:
	if cx < 0 or cy < 0 or cx >= _rw or cy * _rw + cx >= _rfloor.size():
		return 0.0
	return _rfloor[cy * _rw + cx]


func _foe_motion(type: String, def: Dictionary) -> Dictionary:
	if not _foe_motions.has(type):
		_foe_motions[type] = Models.foe_motion(def)
	return _foe_motions[type]


## 敵人的網格：一型四個變體（用 id 取），色相在品紅帶內小幅位移，同一型的幾隻不會長得一模一樣。
func _foe_mesh(type: String, id: int) -> ArrayMesh:
	var key := "%s|%d" % [type, id % 4]
	if not _foe_meshes.has(key):
		_foe_meshes[key] = Models.foe(Enemies.of(type), id % 4)
	return _foe_meshes[key]


# ── 導管（B4.3）────────────────────────────────────────────────────────

## 把 `s.conduits` 同步成 3D 的管子（一個 MultiMesh）。**每條導管的實例資料（`Wires.chunk()`）只在簽章——等級、寬度、
## 滿載比、缺電、受損——變了才重算**；路徑（貼著地形走）只在第一次建時算。寬度、顏色、受損與 2D `_sync_conduits()` 是
## 同一組算式，所以資訊通道原樣保留。有任何一條變了，才把各條的資料依序串成一塊緩衝區送出去。
func _sync_wires() -> void:
	var key := [s.get_instance_id(), s.tick_count, s.rev, _map_id]
	if key == _wire_key:
		return
	_wire_key = key
	var flows: Dictionary = s.rates["conduit_flow"]
	var sat: Dictionary = s.rates["satisfaction"]
	var bonus := float(s.mods["cap_bonus"])
	var cap_max := Build.conduit_cap(Build.CAP_MAX_LEVEL, bonus)
	var node_at: Dictionary = {}
	for n: Dictionary in s.nodes:
		node_at[n["cell"]] = int(n["id"])
	var alive: Dictionary = {}
	var dirty: bool = _wires.size() != s.conduits.size()
	for c: Dictionary in s.conduits:
		var id := int(c["id"])
		alive[id] = true
		var flow := float(flows.get(id, 0.0))
		var lv := int(c["level"])
		var cap := Build.conduit_cap(lv, bonus)
		var to_id: int = node_at.get(c["b"], -1)
		var starving: bool = to_id >= 0 and float(sat.get(to_id, 1.0)) < 0.95 and flow > 0.0
		var w := Shapes.conduit_width(flow, cap_max)
		var hp := float(c["hp"])
		var hurt := 0.0 if hp >= 40.0 else snappedf(1.0 - hp / 40.0, 0.1)
		# 簽章收齊畫它會讀的每個輸入：等級、寬度、滿載比（顏色的來源，量化到 1%）、缺電、受損。
		var sig := [lv, snappedf(w, 0.05), snappedf(flow / maxf(cap, 0.001), 0.01), starving, hurt]
		var rec: Dictionary = _wires.get(id, {})
		if rec.is_empty():
			var a: Vector2i = c["a"]
			var b: Vector2i = c["b"]
			rec = {"sig": [], "chunk": PackedFloat32Array(), "key": Vector4i(a.x, a.y, b.x, b.y)}
			_wires[id] = rec
			_routes[rec["key"]] = {"rt": Wires.route(_rel, a, b), "hh": 0.0}
		if rec["sig"] == sig:
			continue
		rec["sig"] = sig
		var route: Dictionary = _routes[rec["key"]]
		route["hh"] = Wires.half_height(w)
		rec["chunk"] = Wires.chunk(route["rt"], w, Palette.conduit(flow, cap, starving), lv, hurt)
		dirty = true
	for id: int in _wires.keys():
		if not alive.has(id):
			_routes.erase(_wires[id]["key"])
			_wires.erase(id)
			dirty = true
	if not dirty:
		return
	_wire_buf.resize(0)
	for c: Dictionary in s.conduits:
		_wire_buf.append_array((_wires[int(c["id"])] as Dictionary)["chunk"])
	var count := _wire_buf.size() / Wires.FLOATS
	if count > _wire_mm.instance_count:
		var cap_n := maxi(64, _wire_mm.instance_count)
		while cap_n < count:
			cap_n *= 2
		_wire_mm.instance_count = cap_n
	_wire_buf.resize(_wire_mm.instance_count * Wires.FLOATS)
	_wire_mm.visible_instance_count = count
	_wire_mm.buffer = _wire_buf


## 流動珠（3D）：規格讀 2D 舞台算好的那一份（`_bead_specs_cache`：哪幾條線、什麼色、多大、多快），位置沿著管子的路徑算，
## 珠子是擺在管頂上的小球。與 2D 的 `_update_beads()` 同一條時間軸（模擬秒數，零系統時間）。
func _update_beads() -> void:
	if not raised():
		if _bead_mm.visible_instance_count != 0:
			_bead_mm.visible_instance_count = 0
		return
	var specs: Array = _ground._bead_specs_cache
	var need := 0
	for sp: Array in specs:
		need += int(float(sp[2]) / Stage2D.BEAD_GAP) + 1
	if need > _bead_mm.instance_count:
		var cap := maxi(64, _bead_mm.instance_count)
		while cap < need:
			cap *= 2
		_bead_mm.instance_count = cap
		_bead_buf.resize(cap * 16)
	var t: float = (float(s.tick_count) + scr.accum / BattleController.TICK) * BattleController.TICK
	var n := 0
	for sp: Array in specs:
		var a: Vector2 = sp[0]
		var u: Vector2 = sp[1]
		var span: float = sp[2]
		var rad: float = float(sp[3]) / Shapes.GRID * BEAD_K
		var col: Color = sp[7]
		var b := a + u * span
		var rec: Dictionary = _routes.get(Vector4i(
			floori(a.x / Shapes.GRID), floori(a.y / Shapes.GRID), floori(b.x / Shapes.GRID), floori(b.y / Shapes.GRID)
		), {})
		if rec.is_empty():
			continue
		var rt: PackedVector3Array = rec["rt"]
		var hh: float = rec["hh"]
		var x := fposmod(t * float(sp[5]) * Stage2D.BEAD_SPEED + float(sp[6]), Stage2D.BEAD_GAP)
		while x < span:
			var q := (a + u * x) / Shapes.GRID
			var y := (Wires.height_on(rt, x / Shapes.GRID) + hh * 2.0 + rad * 0.55) * _lift
			var o := n * 16
			_bead_buf[o] = rad
			_bead_buf[o + 1] = 0.0
			_bead_buf[o + 2] = 0.0
			_bead_buf[o + 3] = q.x
			_bead_buf[o + 4] = 0.0
			_bead_buf[o + 5] = rad
			_bead_buf[o + 6] = 0.0
			_bead_buf[o + 7] = y
			_bead_buf[o + 8] = 0.0
			_bead_buf[o + 9] = 0.0
			_bead_buf[o + 10] = rad
			_bead_buf[o + 11] = q.y
			_bead_buf[o + 12] = col.r
			_bead_buf[o + 13] = col.g
			_bead_buf[o + 14] = col.b
			_bead_buf[o + 15] = 1.0
			n += 1
			x += Stage2D.BEAD_GAP
	_bead_mm.visible_instance_count = n
	_bead_mm.buffer = _bead_buf


# ── 特效（B4.3）────────────────────────────────────────────────────────

## 升起之後的特效、落影與血條。形狀、時間軸、顏色**沿用 2D**（`Stage2D._draw_shots()` 等）：彈道從**塔頂**飛向**敵人身上**
## （不是兩個地面點之間的線）、火花與碎片在身體的高度、護盾泡罩著身體、血條浮在頭上（永遠看得見）。
## 低於 `FLAT_FOE_MAX_LIFT` 時地面貼圖還畫著 2D 的那一份，這裡不畫（兩邊不同時畫同一件事）。
func _sync_fx() -> void:
	if _lift <= FLAT_FOE_MAX_LIFT:
		_fx_mi.visible = false
		_fx_top_mi.visible = false
		_shadow_mmi.visible = false
		return
	var pen := Fx3D.Pen.new()
	var top := Fx3D.Pen.new()
	var r := _r
	var u := _u
	var frac: float = scr.accum / BattleController.TICK
	_ground._enemy_index = _ground._index_enemies()   # 彈丸要找得到「此刻」的敵人
	# 落影：腳下一圈淡淡的暗（身體浮在溝裡，沒有它看不出離地多高）——一個 MultiMesh，寫緩衝區就好。
	# 血條：受傷的才有，浮在頭上，永遠看得見的那一層。
	var n_foes := _foe_info.size() / 5
	if n_foes > _shadow_mm.instance_count:
		var cap := maxi(64, _shadow_mm.instance_count)
		while cap < n_foes:
			cap *= 2
		_shadow_mm.instance_count = cap
		_shadow_buf.resize(cap * 16)
	var sc := Palette.alpha(Palette.MAT_SHADOW, 0.34)
	for k in n_foes:
		var o5 := k * 5
		var x := _foe_info[o5]
		var z := _foe_info[o5 + 1]
		var fy := _foe_info[o5 + 2]
		var rad := _foe_info[o5 + 3] * 0.95
		var o := k * 16
		_shadow_buf[o] = rad
		_shadow_buf[o + 1] = 0.0
		_shadow_buf[o + 2] = 0.0
		_shadow_buf[o + 3] = x
		_shadow_buf[o + 4] = 0.0
		_shadow_buf[o + 5] = 1.0
		_shadow_buf[o + 6] = 0.0
		_shadow_buf[o + 7] = fy * _lift + 0.012
		_shadow_buf[o + 8] = 0.0
		_shadow_buf[o + 9] = 0.0
		_shadow_buf[o + 10] = rad
		_shadow_buf[o + 11] = z
		_shadow_buf[o + 12] = sc.r
		_shadow_buf[o + 13] = sc.g
		_shadow_buf[o + 14] = sc.b
		_shadow_buf[o + 15] = sc.a
		if _foe_info[o5 + 4] < 1.0:
			Fx3D.hp_bar(top, _lifted(Vector3(x, fy + Models.FOE_HEIGHT + 0.22, z)), 0.5, 0.075, _foe_info[o5 + 4], r, u)
	_shadow_mm.visible_instance_count = n_foes
	if n_foes > 0:
		_shadow_mm.buffer = _shadow_buf
	_shadow_mmi.visible = n_foes > 0
	_fx_shots(pen, r, u, frac)
	_fx_bursts(pen, r, u, frac)
	_fx_shields(pen, r, u, frac)
	pen.to_mesh(_fx_mesh)
	top.to_mesh(_fx_top_mesh)
	_fx_mi.visible = not pen.is_empty()
	_fx_top_mi.visible = not top.is_empty()


func _fx_shots(pen: Fx3D.Pen, r: Vector3, u: Vector3, frac: float) -> void:
	for sh: Dictionary in s.shots:
		var def := NodeDefs.of(String(sh.get("by", "anchor")))
		var pa := _lifted(_muzzle_of(sh["from"]))
		var pb := _lifted(_body_of(_ground._shot_anchor(sh, "target", "prog", "to")))
		var t := Motion.progress(BattleController.SHOT_TTL, int(sh["ttl"]), frac)
		var fade := 1.0 - t
		var beam: bool = bool(def.get("pierce", false))
		# 砲口一閃（菱形；光束多一圈柔光）。
		if not Motion.reduce and t < 0.5:
			var k := 1.0 - t / 0.5
			if beam:
				pen.disc(pa, Fx3D.px(4.0 + 4.0 * k), r, u, Palette.alpha(Palette.ORDER_BRIGHT, 0.35 * k))
			pen.poly(pa, Shapes.ngon(Vector2.ZERO, Fx3D.px(3.0 + 5.0 * k), 4, 0.0), r, u, Palette.alpha(Palette.ORDER_BRIGHT, 0.85 * k))
		if beam:
			# 能量貫穿：整條線一次亮到底，寬度 3→1 衰減。
			pen.ribbon(pa, pb, Fx3D.px(6.0), _f, Palette.alpha(Palette.ORDER_BRIGHT, 0.10 + 0.18 * fade))
			pen.ribbon(pa, pb, Fx3D.px(1.0 + 2.0 * fade), _f, Palette.alpha(Palette.ORDER_BRIGHT, 0.35 + 0.65 * fade))
			continue
		# 物理彈丸：短促實心的一段沿線飛行。
		var d3 := pb - pa
		var total := d3.length()
		if total > 0.001:
			var dir := d3 / total
			var bolt := minf(Fx3D.px(14.0), total * 0.45)
			var head := pa + dir * (bolt + (total - bolt) * Motion.ease_out_cubic(t))
			pen.ribbon(head - dir * bolt, head, Fx3D.px(3.0), _f, Palette.alpha(Palette.ORDER_CYAN, 0.45 + 0.55 * fade))
		# 命中火花：落點炸開一顆四角星。
		if not Motion.reduce and t >= 0.6:
			var k := (1.0 - t) / 0.4
			var rr := 3.0 + 6.0 * (1.0 - k)
			pen.poly(pb, Shapes.star(Vector2.ZERO, Fx3D.px(rr), Fx3D.px(rr * 0.4), 4, PI * 0.25), r, u, Palette.alpha(Palette.ORDER_BRIGHT, 0.9 * k))
		# 濺射環：貼著腳下的擴張環，半徑就是資料裡的 `splash` 格（遊戲距離，不放大）。
		if sh.has("splash_at"):
			var at: Vector2 = _ground._shot_anchor(sh, "splash_target", "splash_prog", "splash_at")
			var cell := Vector2i(floori(at.x / Shapes.GRID), floori(at.y / Shapes.GRID))
			var ring_at := Vector3(at.x / Shapes.GRID, (Relief.floor_at(_rel, cell) + 0.14) * _lift + 0.01, at.y / Shapes.GRID)
			pen.flat_ring(ring_at, float(def.get("splash", 0.0)) * Motion.ease_out_cubic(t), Fx3D.px(2.0), Palette.alpha(Palette.ORDER_CYAN, 0.15 + 0.45 * fade))
		# 回收：一顆琥珀珠回流到塔（方向是反的，走 t 的後半段）。
		if float(def.get("reclaim", 0.0)) > 0.0 and t >= 0.4:
			var k := (t - 0.4) / 0.6
			pen.disc(pb.lerp(pa, Motion.ease_out_cubic(k)), Fx3D.px(3.0), r, u, Palette.alpha(Palette.ENERGY_AMBER, 1.0 - k))


func _fx_bursts(pen: Fx3D.Pen, r: Vector3, u: Vector3, frac: float) -> void:
	for b: Dictionary in s.bursts:
		var t := Motion.progress(int(b["life"]), int(b["ttl"]), frac)
		var e := Motion.ease_out_cubic(t)
		var at: Vector2 = b["at"]
		var cell := Vector2i(floori(at.x + 0.5), floori(at.y + 0.5))
		var chaos: bool = String(b["kind"]) == "chaos"
		var col := Palette.TIDE_MAGENTA if chaos else Palette.ORDER_CYAN
		var base_y := (Relief.floor_at(_rel, cell) + FOE_BODY_Y) if chaos else (_top(cell) + 0.3)
		var c := _lifted(Vector3(at.x + 0.5, base_y, at.y + 0.5))
		var seed_id := int(b["seed"])
		# 一次縮放閃光：混沌＝實心淡去、秩序＝線框擴張。**貼在地上**（直立的圓盤會被溝岸與地形切成鋸齒）。
		var flash := Palette.alpha(col, (1.0 - t) * (0.55 if chaos else 0.75))
		if chaos:
			pen.flat_disc(Vector3(at.x + 0.5, (Relief.floor_at(_rel, cell) + 0.14) * _lift + 0.01, at.y + 0.5), Fx3D.px(4.0 + 10.0 * e), flash)
		else:
			pen.flat_ring(Vector3(at.x + 0.5, _top(cell) * _lift + 0.02, at.y + 0.5), Fx3D.px(4.0 + 18.0 * e), Fx3D.px(2.0), flash)
		# 3–5 個幾何碎片：往外飛（地面方向）、先上拋再落。混沌＝不規則三角＋自轉，秩序＝正方、不自轉。
		var count := 3 + (absi(seed_id) % 3)
		for i in count:
			var dir := Motion.fragment_dir(seed_id, i, count)
			var dist := Fx3D.px(10.0 + 34.0 * e)
			var rise := (0.30 * e - 0.20 * t * t) * _lift
			var p := c + Vector3(dir.x * dist, rise, dir.y * dist)
			var rr := (8.0 if chaos else 6.5) * (1.0 - 0.6 * t)
			var bright: Color = Palette.TIDE_BRIGHT if chaos else Palette.ORDER_BRIGHT
			var fc := Palette.alpha(bright.lerp(col, minf(1.0, t / 0.3)), 1.0 - t)
			if chaos:
				var spin := float(seed_id) * 0.7 + t * 3.0
				pen.poly(p, PackedVector2Array([
					Vector2(Fx3D.px(rr * 1.4), 0.0).rotated(spin),
					Vector2(Fx3D.px(rr), 0.0).rotated(spin + 2.3),
					Vector2(Fx3D.px(rr * 0.8), 0.0).rotated(spin + 4.1),
				]), r, u, fc)
			else:
				var q := Fx3D.px(rr)
				pen.poly(p, PackedVector2Array([Vector2(-q, -q), Vector2(q, -q), Vector2(q, q), Vector2(-q, q)]), r, u, fc)


func _fx_shields(pen: Fx3D.Pen, r: Vector3, u: Vector3, frac: float) -> void:
	for sh: Dictionary in s.shields:
		var t := Motion.progress(int(sh["life"]), int(sh["ttl"]), frac)
		var cell: Vector2i = sh["at"]
		var c := _lifted(Vector3(float(cell.x) + 0.5, Relief.floor_at(_rel, cell) + FOE_BODY_Y + 0.05, float(cell.y) + 0.5))
		var rad := 0.62 + 0.22 * Motion.ease_out_cubic(t)
		var hex := PackedVector2Array()
		for i in 6:
			var a := TAU * float(i) / 6.0 - PI / 2.0
			hex.append(Vector2(cos(a), sin(a)) * rad)
		pen.outline(c, hex, Fx3D.px(3.0), r, u, Palette.alpha(Palette.ORDER_BRIGHT, (1.0 - t) * 0.95))
		var fill := clampf(float(sh["frac"]), 0.0, 1.0)
		pen.outline(c, hex, Fx3D.px(7.0), r, u, Palette.alpha(Palette.ORDER_CYAN, (1.0 - t) * 0.45 * fill))
		if t < 0.35:
			pen.disc(c, 0.30, r, u, Palette.alpha(Palette.ORDER_BRIGHT, (0.35 - t) * 1.6))


## 炮口：塔頂（格；高度未乘 lift）。塔已經不在了就取一個普通的高度。
func _muzzle_of(cell: Vector2i) -> Vector3:
	var n: Dictionary = s.node_at(cell)
	var h := 0.4
	if not n.is_empty():
		h = Models.height_of(String(n["type"]), int(n.get("level", 0))) * 0.85
	return Vector3(float(cell.x) + 0.5, _top(cell) + h, float(cell.y) + 0.5)


## 敵人身上的一點：地圖座標（px）→ 該格地面之上 `FOE_BODY_Y`（格；高度未乘 lift）。
func _body_of(px: Vector2) -> Vector3:
	var cell := Vector2i(floori(px.x / Shapes.GRID), floori(px.y / Shapes.GRID))
	return Vector3(px.x / Shapes.GRID, Relief.floor_at(_rel, cell) + FOE_BODY_Y, px.y / Shapes.GRID)


## 高度乘 lift。
func _lifted(v: Vector3) -> Vector3:
	return Vector3(v.x, v.y * _lift, v.z)


# ── 落點預覽（B4.3）────────────────────────────────────────────────────

## 手上拿著一種建築、游標在地圖上時：在那一格擺一個**半透明的 3D 造型**（框與射程圈仍畫在地上）。可放＝偏綠、不可放＝偏橙，
## 與 2D 的預覽同一組判定（`BuildController.preview_place()`）。條件與 `Stage2D._draw_hover()` 一致：選了類型、不是藍圖、
## 沒壓在導管上、沒在拉線。
func _sync_ghost() -> void:
	_ghost.visible = false
	if not raised() or scr.get("build_type") == null:
		return
	var bt := String(scr.build_type)
	if scr.mode != scr.Mode.BUILD or bt == "" or scr.bp_index >= 0 or scr.drag_from.x >= 0 or not in_map(scr.hover):
		return
	if _ground._hover_wire >= 0 and scr.drag_from.x < 0:
		return
	var key := [s.get_instance_id(), s.tick_count, s.rev, bt, scr.hover]
	if key != _ghost_key:
		_ghost_key = key
		_ghost_ok = bool(BuildController.preview_place(s, bt, scr.hover)["ok"])
	if not _ghost_meshes.has(bt):
		_ghost_meshes[bt] = Models.node({"type": bt, "level": 0, "hp": NodeDefs.hp(bt)}, 0)
	var mesh: ArrayMesh = _ghost_meshes[bt]
	if Extrude.triangle_count(mesh) == 0:
		return
	var tint := Palette.OK_GREEN if _ghost_ok else Palette.WARN_ORANGE
	_ghost_mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_ghost.mesh = mesh
	var cell: Vector2i = scr.hover
	_ghost.position = Vector3(float(cell.x) + 0.5, _top(cell) * _lift, float(cell.y) + 0.5)
	_ghost.visible = true


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


## 3D 導管的條數、本幀畫出來的珠子數、特效網格有沒有東西（`stage3d_test`／`SelfTest` 用）。
func wire_count() -> int:
	return _wires.size()


func bead_count() -> int:
	return _bead_mm.visible_instance_count


## 這一幀 3D 導管的實例數（管身、環箍、光暈加起來）。
func wire_instances() -> int:
	return _wire_mm.visible_instance_count


func wire_route(id: int) -> PackedVector3Array:
	var rec: Dictionary = _wires.get(id, {})
	if rec.is_empty():
		return PackedVector3Array()
	return (_routes[rec["key"]] as Dictionary)["rt"]


func shadow_count() -> int:
	return _shadow_mm.visible_instance_count if _shadow_mmi.visible else 0


func fx_triangles() -> int:
	return Extrude.triangle_count(_fx_mesh) + Extrude.triangle_count(_fx_top_mesh)


func hp_bar_triangles() -> int:
	return Extrude.triangle_count(_fx_top_mesh)


func ghost_visible() -> bool:
	return _ghost.visible


## 沒有造型的節點型別（要是空的）。
func missing_meshes() -> Array:
	return _no_mesh.keys()


## 現在 3D 世界有沒有在畫（lift 夠大）。
func raised() -> bool:
	return _lift > LIFT_SHOW


# ── 內部：相機 ─────────────────────────────────────────────────────────

func _map_cells() -> Vector2:
	return Vector2(s.map["size"]) if s != null and not s.map.is_empty() else Vector2(10.0, 10.0)


## 相機姿態：`[位置, 前方, 上方, 離目標點的距離, 右方]`。`tilt_deg` ＝ 0 時正俯瞰；`yaw_deg` ＝ 地圖在畫面上順時針轉過的角度。
## 畫面上「上」在地面上的方向 `h` 與「右」`r`：yaw ＝ 0 時 h ＝ −z（北）、r ＝ +x；順時針轉 ψ 時 r ＝ (cosψ, 0, −sinψ)、h ＝ (−sinψ, 0, −cosψ)。
static func _pose(view_h: float, tilt_deg: float, target: Vector2, yaw_deg: float = 0.0) -> Array:
	var p := deg_to_rad(90.0 - tilt_deg)
	var psi := deg_to_rad(yaw_deg)
	var r := Vector3(cos(psi), 0.0, -sin(psi))
	var h := Vector3(-sin(psi), 0.0, -cos(psi))
	var f := h * cos(p) + Vector3(0.0, -sin(p), 0.0)
	var u := Vector3(0.0, cos(p), 0.0) + h * sin(p)
	var dist := view_h * 0.5 / tan(deg_to_rad(FOV_DEG * 0.5))
	return [Vector3(target.x, 0.0, target.y) - f * dist, f, u, dist, r]


## 世界點 → NDC（x, y ∈ [-1, 1] 在畫面內）＋ 深度。深度 ≤ 0 ＝ 在相機後面。
static func _ndc(pose: Array, aspect: float, x: Vector3) -> Vector3:
	var pos: Vector3 = pose[0]
	var f: Vector3 = pose[1]
	var u: Vector3 = pose[2]
	var r: Vector3 = pose[4]
	var th := tan(deg_to_rad(FOV_DEG * 0.5))
	var v := x - pos
	var zc := v.dot(f)
	if zc < 0.001:
		return Vector3(INF, INF, zc)
	return Vector3(v.dot(r) / (zc * th * aspect), v.dot(u) / (zc * th), zc)


## 這個傾斜角、旋轉角下，剛好框住整張圖（含 `MARGIN`）所需的畫面高度（格）。二分搜尋：距離變大，
## 四個角單調地往畫面中心收，所以「塞得下」對距離是單調的。四個角取**地形最高處**那個高度（隆起的圖邊緣最容易出框）。
## 結果依（傾斜、旋轉、圖大小）快取——旋轉時每幀換一個角度，所以快取是一張小表，不是單一格。
func _fit_view_h(t_deg: float, yaw_deg: float) -> float:
	var margin := 1.0 + MARGIN_TILT * clampf(t_deg / TILT_MAX, 0.0, 1.0)
	var m := _map_cells()
	var key := Vector3(snappedf(t_deg, 0.01), snappedf(yaw_deg, 0.01), m.x * 4096.0 + m.y)
	if _fit_cache.has(key):
		return _fit_cache[key]
	var c := m * 0.5
	var y := float(_rel.get("max", 0.0)) * _lift_of(t_deg)
	var corners: Array[Vector3] = [
		Vector3(0.0, y, 0.0), Vector3(m.x, y, 0.0), Vector3(m.x, y, m.y), Vector3(0.0, y, m.y),
	]
	var lo := 1.0
	var hi := 800.0
	for _i in 32:
		var mid := (lo + hi) * 0.5
		var pose := _pose(mid, t_deg, c, yaw_deg)
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
	if _fit_cache.size() > 96:
		_fit_cache.clear()
	_fit_cache[key] = hi
	return hi


## 把 `tilt`、`zoom`、`_target` 套到相機、升起程度與各個 3D 節點上。
func _apply_camera() -> void:
	if _cam == null:
		return
	var whole := _fit_view_h(tilt, yaw)
	_whole_h = whole
	# 可讀性地板：一格至少 `MIN_READABLE_CELL` px ⇒ 畫面最多涵蓋這麼多格。一屏可見的戰役關卡在不旋轉時永遠 whole ≤ 地板。
	# ★ 地板只管**大圖**（不旋轉也塞不進地板的）：一屏可見的圖旋轉之後，外接的範圍會變大（轉 45° 的 30×18 要 34 格高），
	#   硬守地板的話整張圖就看不全——旋轉是玩家自己選的，選了就該看得到整張圖，所以旋轉時讓全景一格小於地板（最小約 15 px）。
	var floor_h := FRAME.size.y / Shapes.MIN_READABLE_CELL
	var fits_unrotated: bool = _fit_view_h(tilt, 0.0) <= floor_h + 0.001
	_fit_h = whole if fits_unrotated else minf(whole, floor_h)
	_view_h = _fit_h / maxf(zoom, 1.0)
	var pose := _pose(_view_h, tilt, _target, yaw)
	_pos = pose[0]
	_f = pose[1]
	_u = pose[2]
	_dist = pose[3]
	_r = pose[4]
	_cam.transform = Transform3D(Basis(_r, _u, -_f), _pos)
	var diag := _map_cells().length()
	_cam.near = maxf(0.05, _dist * 0.3)
	_cam.far = _dist * 2.6 + diag
	_lift = _lift_of(tilt)
	_solid.set_shader_parameter("lift", _lift)
	_solid_hit.set_shader_parameter("lift", _lift)
	_ghost_mat.set_shader_parameter("lift", _lift)
	_wire_mat.set_shader_parameter("lift", _lift)
	_ground_mat.set_shader_parameter("lift", _lift)
	_place_nodes()
	_place_badges()
	var show := _lift > LIFT_SHOW
	_cliffs.visible = show
	_scenery.visible = show
	_node_root.visible = show
	_foe_root.visible = show
	_wire_mmi.visible = show
	_bead_mmi.visible = show


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
	var dir := _r * (nx * _th * _aspect) + _u * (ny * _th) + _f
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
	var n := _ndc([_pos, _f, _u, _dist, _r], _aspect, x)
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
