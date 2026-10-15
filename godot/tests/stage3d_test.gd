extends SceneTree
## 舞台契約測試：傾斜舞台 `Stage3D` 必須滿足 `screens/battle/Stage.gd` 的契約（B4.0 脊椎 → B4.1 傾斜）。
##
## **這是 2D→3D 轉換的驗收尺**：契約的每一條都在這裡被當成斷言。換一個舞台實作之後，這支必須維持全綠——
## 它守的是「局內畫面與 HUD 不必知道舞台是 2D 還是 3D」這件事。B4.1 起多守三件事：
##   · **傾斜**：每個傾斜角下全景都框得住整張圖（鎖定的設計：戰役關卡一屏可見）；
##   · **建築拾取**：游標底下是建築就選建築、不是它後面的地；
##   · **每種節點與敵人都有造型與高度**（漏一種的症狀是隱形，這裡要它變紅）。
##
## 不載入 autoload（`30_TECH_DESIGN.md` §4.2），所以 `Stage3D` 與它內嵌的 `Stage2D` 都不得引用任何 autoload
## ——這支測試順便守住它。主畫面的部分（`scr`）用一個最小的替身，地面貼圖的繪製關掉（`ground_draw`）。
##
## 跑法：<godot> --headless --path godot --script res://tests/stage3d_test.gd

const T := preload("res://tests/_assert.gd")
const Stage := preload("res://scripts/screens/battle/Stage.gd")
const Stage3D := preload("res://scripts/screens/battle/Stage3D.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const Maps := preload("res://data/Maps.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Enemies := preload("res://data/Enemies.gd")
const Extrude := preload("res://scripts/render/3d/Extrude.gd")
const Models := preload("res://scripts/render/3d/Models.gd")
const Relief := preload("res://scripts/render/3d/Relief.gd")
const Wires := preload("res://scripts/render/3d/Wires.gd")
const Fx3D := preload("res://scripts/render/3d/Fx3D.gd")


## 主畫面的替身：契約的實作只會問它這幾件事。
class ScrStub:
	extends Control
	var accum: float = 0.0
	var hover: Vector2i = Vector2i(-999, -999)
	var selected: Vector2i = Vector2i(-1, -1)
	var refreshed: int = 0
	# 落點預覽（`Stage3D._sync_ghost()`）問的欄位：`Battle` 的同名欄位。
	enum Mode { BUILD, DEMOLISH }
	var mode: int = Mode.DEMOLISH
	var build_type: String = ""
	var bp_index: int = -1
	var drag_from: Vector2i = Vector2i(-1, -1)

	func redraw() -> void:
		pass

	func refresh_zoom() -> void:
		refreshed += 1


var _moved: int = 0


func _initialize() -> void:
	_run()


## 要等一個 process frame：`--script` 模式下 `_initialize()` 裡加進樹的節點，`_ready()` 要到主迴圈開始才跑。
func _run() -> void:
	var t := T.new("stage3d_test", 150)
	var s := SessionState.new()
	s.setup(Maps.SHOAL)
	var scr := ScrStub.new()
	root.add_child(scr)
	var st := Stage3D.new()
	st.ground_draw = false
	st.scr = scr
	st.s = s
	st.view_moved.connect(func() -> void: _moved += 1)
	scr.add_child(st)
	await process_frame
	await process_frame
	st.reset_view()

	var m: Vector2i = s.map["size"]
	var mpx := Vector2(m) * 32.0
	t.ok(st.can_tilt(), "can_tilt：傾斜舞台能傾斜")

	# ── 投影與拾取（俯瞰）：格 → 螢幕 → 同一格；`point_at` 與 `center` 同一個座標系 ──
	var round_trip := true
	var point_ok := true
	var cells := 0
	for x in range(0, m.x, 3):
		for y in range(0, m.y, 3):
			var c := Vector2i(x, y)
			cells += 1
			round_trip = round_trip and st.cell_at(st.to_screen(st.center(c))) == c
			point_ok = point_ok and st.point_at(st.to_screen(st.center(c))).distance_to(Vector2(c)) < 0.01
	t.ok(cells > 20, "取樣夠多格（%d）" % cells)
	t.ok(round_trip, "★ 每一格：cell_at(to_screen(center(c))) == c")
	t.ok(point_ok, "★ point_at 與 center 同一個座標系（整數＝格中心）")
	t.ok(st.in_map(Vector2i(0, 0)) and st.in_map(Vector2i(m.x - 1, m.y - 1)), "in_map：四角在內")
	t.ok(not st.in_map(Vector2i(-1, 0)) and not st.in_map(Vector2i(m.x, 0)), "in_map：界外在外")

	# ── 進場視野：fit，框住整張圖（鎖定的設計：戰役關卡一屏可見）──
	t.ok(is_equal_approx(st.zoom, st.fit), "reset_view：zoom ＝ fit")
	var vr := st.view_world_rect()
	t.ok(
		vr.position.x <= 0.5 and vr.position.y <= 0.5 and vr.end.x >= mpx.x - 0.5 and vr.end.y >= mpx.y - 0.5,
		"★ reset_view：視野框住整張圖"
	)
	t.ok(not st.oversized(), "reset_view：fit 時地圖不算『大過一屏』")
	t.ok(_moved >= 1, "reset_view 發出 view_moved")
	t.ok(is_equal_approx(st.tilt, 0.0) and not st.raised(), "預設正俯瞰：tilt ＝ 0、3D 不畫（貼圖裡的 2D 本尊在畫）")

	# ── 縮放：倍率變大、視野變小、錨點底下那格不動 ──
	var anchor_cell := Vector2i(m.x / 2, m.y / 2)
	var anchor := st.to_screen(st.center(anchor_cell))
	var before_moved := _moved
	st.zoom_by(Stage.ZOOM_STEP, anchor)
	t.ok(st.zoom > st.fit, "zoom_by(ZOOM_STEP)：倍率變大")
	t.ok(st.view_world_rect().size.x < vr.size.x - 0.5, "zoom_by：視野變小")
	t.eq(st.cell_at(anchor), anchor_cell, "★ zoom_by：錨點底下那一格縮放前後不動")
	t.ok(_moved > before_moved, "zoom_by 發出 view_moved")
	t.ok(scr.refreshed >= 1, "zoom_by 通知畫面層刷新「全景 %」")
	for _i in 30:
		st.zoom_by(Stage.ZOOM_STEP, anchor)
	t.ok(st.zoom <= st.fit * 3.0 + 0.001, "zoom_by：上限是 fit 的 3 倍")
	for _i in 60:
		st.zoom_by(1.0 / Stage.ZOOM_STEP, anchor)
	t.ok(is_equal_approx(st.zoom, st.fit), "zoom_by：下限就是 fit（全景）")

	# ── 平移：拖曳往右＝看到更左邊；夾在地圖範圍內；全景時平移恆為 0 ──
	st.pan_by(Vector2(80.0, 40.0))
	t.ok(st.view_world_rect().position.distance_to(vr.position) < 0.5, "★ 全景時 pan_by 沒有作用（fit 時平移恆為 0）")
	st.zoom_by(Stage.ZOOM_STEP * Stage.ZOOM_STEP, anchor)
	var x0 := st.view_world_rect().position.x
	st.pan_by(Vector2(60.0, 0.0))
	t.ok(st.view_world_rect().position.x < x0, "pan_by(+x)：視野往左移（拖曳往右）")
	st.pan_by(Vector2(99999.0, 99999.0))
	var edge := st.view_world_rect()
	t.ok(edge.position.x >= -mpx.x * 0.05 and edge.position.y >= -mpx.y * 0.05, "pan_by：推到底夾在地圖範圍內")
	st.pan_by(Vector2(-99999.0, -99999.0))
	t.ok(st.view_world_rect().end.x <= mpx.x * 1.05, "pan_by：反向推到底也夾住")

	# ── center_view_on：把某一格移到畫面中央 ──
	var target := Vector2i(m.x / 2, m.y / 2)
	st.center_view_on(target, true)
	var center_px := st.view_world_rect().get_center()
	t.ok(center_px.distance_to(st.center(target)) < 40.0, "★ center_view_on：視野中心落在那一格附近")
	st.reset_view()
	t.ok(is_equal_approx(st.zoom, st.fit) and not st.oversized(), "reset_view：回到全景")

	# ── 傾斜：API ──
	var tilt_moved := _moved
	st.tilt_to(40.0, true)
	t.near(st.tilt, 40.0, "tilt_to(immediate)：當場到位")
	t.near(st.tilt_goal(), 40.0, "tilt_goal 是目標")
	t.ok(st.raised() and st.lift() > 0.5, "傾斜 40°：3D 在畫、建築長高")
	t.ok(_moved > tilt_moved, "tilt_to 發出 view_moved")
	st.tilt_to(999.0, true)
	t.near(st.tilt, Stage.TILT_MAX, "tilt_to：上限夾在 TILT_MAX")
	st.tilt_to(-5.0, true)
	t.near(st.tilt, 0.0, "tilt_to：下限夾在 0（正俯瞰）")
	st.tilt_by(15.0, true)
	st.tilt_by(10.0, true)
	t.near(st.tilt, 25.0, "tilt_by：累加相對量")
	st.tilt_to(0.0, true)
	st.tilt_toggle()
	t.near(st.tilt_goal(), Stage.TILT_DEFAULT, "tilt_toggle：俯瞰 → 預設傾斜角（目標）")
	t.near(st.tilt, 0.0, "tilt_toggle 不是瞬移：目前角度還在原地，由 tick_view 緩動過去")
	for _i in 200:
		st.tick_view(0.016)
	t.near(st.tilt, Stage.TILT_DEFAULT, "tick_view：緩動收斂到目標", 0.06)
	st.tilt_toggle()
	t.near(st.tilt_goal(), 0.0, "tilt_toggle：傾斜 → 回正俯瞰")
	for _i in 200:
		st.tick_view(0.016)
	t.ok(is_equal_approx(st.tilt, 0.0) and not st.raised(), "回正俯瞰：lift ＝ 0、3D 不畫")
	var l0 := 0.0
	var mono := true
	for deg in range(0, 63, 3):
		st.tilt_to(float(deg), true)
		mono = mono and st.lift() >= l0 - 0.0001
		l0 = st.lift()
	t.ok(mono and is_equal_approx(l0, 1.0), "lift 隨傾斜單調上升、到全高為 1")

	# ── ★ 每個傾斜角下，全景都框得住整張圖 ──
	var frame_ok := true
	var rect_ok := true
	var frame_probe := ""
	for deg in [0.0, 12.0, 25.0, 38.0, 50.0, Stage.TILT_MAX]:
		st.tilt_to(deg, true)
		st.reset_view()
		for corner: Vector2 in [Vector2(0, 0), Vector2(mpx.x, 0), mpx, Vector2(0, mpx.y)]:
			var sp := st.to_screen(corner)
			if not Stage.FRAME.grow(0.5).has_point(sp):
				frame_ok = false
				frame_probe = "%d° 角 %s → %s" % [int(deg), str(corner), str(sp)]
		var r := st.view_world_rect()
		rect_ok = rect_ok and r.position.x <= 0.5 and r.position.y <= 0.5 and r.end.x >= mpx.x - 0.5 and r.end.y >= mpx.y - 0.5
		t.ok(not st.oversized(), "%d°：全景不算『大過一屏』" % int(deg))
	t.ok(frame_ok, "★ 每個傾斜角：地圖四角都在畫面框架內（%s）" % frame_probe)
	t.ok(rect_ok, "★ 每個傾斜角：view_world_rect 涵蓋整張圖")

	# ── 傾斜下的投影往返（挑離任何建築遠的格：建築會擋住它後面的地，那是對的）──
	st.tilt_to(50.0, true)
	st.reset_view()
	var near_nodes := func(c: Vector2i) -> bool:
		for n: Dictionary in s.nodes:
			var nc: Vector2i = n["cell"]
			if absi(nc.x - c.x) <= 3 and absi(nc.y - c.y) <= 3:
				return true
		return false
	var tilt_round := true
	var tilt_cells := 0
	for x in range(1, m.x - 1, 3):
		for y in range(1, m.y - 1, 3):
			var c2 := Vector2i(x, y)
			if near_nodes.call(c2):
				continue
			tilt_cells += 1
			tilt_round = tilt_round and st.cell_at(st.to_screen(st.center(c2))) == c2
			tilt_round = tilt_round and st.point_at(st.to_screen(st.center(c2))).distance_to(Vector2(c2)) < 0.01
	t.ok(tilt_cells > 15, "傾斜取樣夠多格（%d）" % tilt_cells)
	t.ok(tilt_round, "★ 傾斜 50°：每一格 cell_at／point_at 往返成立")
	var vr50 := st.view_world_rect()
	t.ok(vr50.size.x > 0.0 and vr50.size.y > 0.0, "傾斜時 view_world_rect 有面積")

	# ── 相機與自己的算式一致（Camera3D 與投影／拾取用同一組參數）──
	var cam_err := 0.0
	var cam: Camera3D = st._cam
	for deg in [0.0, 30.0, 55.0]:
		st.tilt_to(deg, true)
		st.reset_view()
		for c3: Vector3 in [Vector3(3.0, 0.0, 3.0), Vector3(m.x * 0.5, 0.0, m.y * 0.5), Vector3(m.x - 2.0, 0.0, m.y - 2.0)]:
			var top_h := Relief.top_at(st.relief(), Vector2i(floori(c3.x), floori(c3.z))) * st.lift()
			var by_cam := cam.unproject_position(Vector3(c3.x, top_h, c3.z)) + Stage.FRAME.position
			var mine := st.to_screen(Vector2(c3.x, c3.z) * 32.0)
			cam_err = maxf(cam_err, by_cam.distance_to(mine))
	t.ok(cam_err < 0.6, "★ Camera3D.unproject_position 與 to_screen 一致（最大誤差 %.3f px）" % cam_err)

	# ── ★ 建築拾取：游標底下是建築，選到的就是那座建築（不是穿過去之後它後面的地）──
	st.tilt_to(0.0, true)
	st.reset_view()
	s.nodes.clear()
	s.conduits.clear()
	s.rev += 1
	var tall := Vector2i(m.x / 2, m.y / 2)
	s.add_node("longcall", tall)
	st._process(0.0)
	t.eq(st.cell_at(st.to_screen(st.center(tall))), tall, "俯瞰：點格心選到那一格")
	st.tilt_to(55.0, true)
	st.reset_view()
	st._process(0.0)
	var top_pt := st.to_screen_at(st.center(tall), Models.height_of("longcall", 0))
	var base_pt := st.to_screen(st.center(tall))
	t.ok(top_pt.y < base_pt.y - 3.0, "傾斜 55°：長哨的頂比它的底在螢幕上更高（%.1f vs %.1f）" % [top_pt.y, base_pt.y])
	t.eq(st.cell_at(top_pt), tall, "★ 傾斜：點建築的頂 → 選到那座建築")
	var ground_cell := Vector2i(floori(st.point_at(top_pt).x + 0.5), floori(st.point_at(top_pt).y + 0.5))
	t.ok(ground_cell.y < tall.y, "（探針）同一個像素的地面交點在建築後面（%s）——沒有建築拾取就會選錯" % str(ground_cell))
	var mid_pt := (top_pt + base_pt) * 0.5
	t.eq(st.cell_at(mid_pt), tall, "★ 傾斜：點建築的側面 → 選到那座建築")
	var far_cell := Vector2i(2, 2)
	t.eq(st.cell_at(st.to_screen(st.center(far_cell))), far_cell, "建築旁邊遠處的空地仍選到那一格")
	st.tilt_to(0.0, true)
	st._process(0.0)
	t.eq(st.cell_at(st.to_screen(st.center(tall))), tall, "回到俯瞰：拾取回到純地面")

	# ── 每幀同步：局的狀態 → 3D（節點、敵人）──
	s.nodes.clear()
	s.conduits.clear()
	s.enemies.clear()
	s.rev += 1
	st._process(0.0)
	t.eq(st.node_count(), 0, "同步：清空後沒有節點")
	var a := s.add_node("relay", Vector2i(3, 3))
	var b := s.add_node("generator", Vector2i(6, 3))
	s.add_conduit(Vector2i(3, 3), Vector2i(6, 3))
	s.add_enemy("drifter")
	st._process(0.0)
	t.eq(st.node_count(), s.nodes.size(), "同步：新增節點後數量一致")
	t.eq(st.foe_count(), 1, "同步：新增敵人後數量一致")
	s.remove_node_at(Vector2i(6, 3))
	s.enemies.clear()
	st._process(0.0)
	t.eq(st.node_count(), s.nodes.size(), "同步：拆掉節點後多出來的被清掉")
	t.eq(st.foe_count(), 0, "同步：敵人死了就清掉")
	t.ok(a != b, "（探針）兩個新節點的 id 不同")
	t.ok(st.engaged is Dictionary and st.threat is Dictionary, "每幀推導：engaged／threat 存在")

	# ── ★ 每種節點、每種敵人都有造型與高度（漏一種＝隱形的塔）──
	s.nodes.clear()
	s.conduits.clear()
	s.rev += 1
	var types: Array = NodeDefs.DEFS.keys()
	var x := 1
	for ty: String in types:
		if ty == "core":
			s.add_node(ty, Vector2i(m.x - 3, m.y - 3))
		else:
			s.add_node(ty, Vector2i(x, 1))
			x += 2
	st._process(0.0)
	t.eq(st.node_count(), types.size(), "每種節點（%d 種）都同步成 3D 節點" % types.size())
	t.ok(st.missing_meshes().is_empty(), "★ 每種節點都有零件清單（沒有的：%s）" % str(st.missing_meshes()))
	var heights_ok := true
	var meshes_ok := true
	var bounds_ok := true
	var bad := ""
	for ty2: String in types:
		if not Models.has_recipe(ty2):
			heights_ok = false
			bad = ty2
	for rec: Dictionary in st._nodes.values():
		var mesh: ArrayMesh = (rec["mi"] as MeshInstance3D).mesh
		if Extrude.triangle_count(mesh) < 4:
			meshes_ok = false
		var aabb := mesh.get_aabb()
		# 一座塔留在自己那一格（半寬 ≤ 0.5＋一點）、核心 1.5 格（≤ 0.8）；高度在表上的高度附近（不是矮得看不見、也不是長出天際）。
		var lim := 0.8 if (rec["key"] as String).begins_with("core") else 0.52
		var ty := (rec["key"] as String).split("|")[0]
		var hh := Models.height_of(ty, 0)
		if absf(aabb.position.x) > lim or absf(aabb.end.x) > lim or absf(aabb.position.z) > lim or absf(aabb.end.z) > lim 				or aabb.end.y > hh + 0.12 or aabb.end.y < hh * 0.6:
			bounds_ok = false
			bad = "%s %s %s" % [bad, ty, str(aabb)]
	t.ok(heights_ok, "★ 每種節點都有高度（Extrude.HEIGHT，缺：%s）" % bad)
	t.ok(meshes_ok, "★ 每種節點的網格都有面（沒有＝隱形的塔）")
	t.ok(bounds_ok, "每種節點的網格留在自己那一格附近、高度合理（%s）" % bad)
	var lv_ok := true
	for ty3: String in types:
		lv_ok = lv_ok and Models.height_of(ty3, 3) > Models.height_of(ty3, 0)
	t.ok(lv_ok, "升級讓建築長高")
	var foes_ok := true
	var foe_bounds := true
	var foe_bad := ""
	for ft: String in Enemies.DEFS.keys():
		var def := Enemies.of(ft)
		for variant in 4:
			var fm := Models.foe(def, variant)
			foes_ok = foes_ok and Extrude.triangle_count(fm) >= 60
			var fa := fm.get_aabb()
			var fr := maxf(float(def.get("radius", 9.0)) / 32.0, Models.MIN_FOE_RADIUS)
			# 敵人留在自己的半徑附近（群體三瓣放寬）、不高過 FOE_HEIGHT。
			if fa.end.y > Models.FOE_HEIGHT + 0.02 or maxf(absf(fa.position.x), absf(fa.end.x)) > fr * 2.1 + 0.05:
				foe_bounds = false
				foe_bad = "%s %s" % [ft, str(fa)]
	t.ok(foes_ok, "★ 每種敵人（%d 種 × 4 變體）都有網格" % Enemies.DEFS.size())
	t.ok(foe_bounds, "每種敵人的網格不高過 FOE_HEIGHT、不超出自己的半徑太多（%s）" % foe_bad)
	var variants_differ := false
	var m0 := Models.foe(Enemies.of("drifter"), 0)
	var m1 := Models.foe(Enemies.of("drifter"), 2)
	var c0 := m0.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
	var c1 := m1.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
	variants_differ = c0 != c1
	t.ok(variants_differ, "★ 同一型的不同變體顏色不同（不是一個模子印出來的）")
	# 敵人配色整組在品紅—紫色相帶內（色相 0.72–1.0 或 0–0.06；暖橙留給「建築受損」）。
	var hue_ok := true
	for ft2: String in Enemies.DEFS.keys():
		var fcols := Models.foe(Enemies.of(ft2), 1).surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
		for ci in range(0, fcols.size(), 7):
			var fc := fcols[ci]
			if fc.s > 0.25 and fc.v > 0.25 and not (fc.h >= 0.70 or fc.h <= 0.07):
				hue_ok = false
		pass
	t.ok(hue_ok, "★ 敵人的顏色全在品紅—紫的色相帶內（不用橙、不用青）")
	# 建築的色彩多樣性：每種節點至少用到 4 種不同的色（不是單色塊）。
	var rich := true
	var rich_bad := ""
	for rec2: Dictionary in st._nodes.values():
		var mc := ((rec2["mi"] as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
		var seen: Dictionary = {}
		for q in mc:
			seen["%d/%d/%d" % [int(q.r * 8.0), int(q.g * 8.0), int(q.b * 8.0)]] = true
		if seen.size() < 4:
			rich = false
			rich_bad = str(rec2["key"])
	t.ok(rich, "★ 每種建築至少用到 4 種以上的色階（材質拼起來的，不是單色塊；%s）" % rich_bad)

	# ── ★ 地形起伏 ──
	var rel := st.relief()
	t.ok(not rel.is_empty() and int(rel["w"]) == m.x and int(rel["h"]) == m.y, "起伏的尺寸 ＝ 地圖尺寸")
	var path_flat := true
	var bank_ok := true
	var nonneg := true
	var varied := {}
	for yy in m.y:
		for xx in m.x:
			var cc := Vector2i(xx, yy)
			var tp := Relief.top_at(rel, cc)
			nonneg = nonneg and tp >= 0.0
			if (rel["path"] as Dictionary).has(cc):
				# 溝（0）、橋面（BRIDGE）；通往核心的最後幾格抬到平台的高度（BANK）。
				path_flat = path_flat and (is_equal_approx(tp, 0.0) or is_equal_approx(tp, Relief.BRIDGE) or is_equal_approx(tp, Relief.BANK))
			else:
				varied[snappedf(tp, 0.001)] = true
	t.ok(nonneg, "所有格的頂面高度 ≥ 0")
	t.ok(path_flat, "★ 敵人路徑是溝（高 0）；跨越點是橋面（高 BRIDGE）")
	t.ok(varied.size() >= 3, "★ 地形真的有起伏：非路徑格有 %d 種以上的高度" % varied.size())
	for pc: Vector2i in (rel["path"] as Dictionary).keys():
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var nb := pc + Vector2i(dx, dy)
				if st.in_map(nb) and not (rel["path"] as Dictionary).has(nb):
					bank_ok = bank_ok and is_equal_approx(Relief.top_at(rel, nb), Relief.BANK)
	t.ok(bank_ok, "★ 溝的兩岸（路徑外一格）一律是岸（BANK）——侵蝕暈那一圈是平的，才數得出格數")
	var core_cell: Vector2i = s.map.get("core", Vector2i.ZERO)
	t.ok(is_equal_approx(Relief.top_at(rel, core_cell), Relief.BANK), "核心的格是平台（BANK）")
	var rel2 := Relief.build(s.map)
	t.ok((rel2["top"] as PackedFloat32Array) == (rel["top"] as PackedFloat32Array), "★ 起伏是確定的：同一張圖建兩次逐格相同")
	var gm := Relief.ground_mesh(rel)
	t.eq(Extrude.triangle_count(gm), m.x * m.y * 2, "頂面：每格兩個三角形")
	t.ok(Extrude.triangle_count(Relief.cliff_mesh(rel)) > 20, "懸崖與四周側壁有面")
	t.ok(Extrude.triangle_count(Relief.scenery_mesh(s.map, rel)) > 0, "地上的擺設（岩石、礦點水晶）有面")
	# 橋：用一張有跨越點的圖驗橋面與「橋底是空的」。
	var bridged := Maps.SHOAL.duplicate(true)
	var brel := Relief.build(bridged)
	var cr: Array = bridged.get("crossings", [])
	var bridge_ok := cr.size() > 0
	for cx: Vector2i in cr:
		bridge_ok = bridge_ok and is_equal_approx(Relief.top_at(brel, cx), Relief.BRIDGE) and is_equal_approx(Relief.floor_at(brel, cx), 0.0)
	t.ok(bridge_ok, "★ 橋（%d 座）：頂面是 BRIDGE、橋底的地面是 0（敵人從底下走）" % cr.size())
	# 拾取要看地形：傾斜 50° 時，隆起的格心投影後再拾取仍是同一格，而且地面交點在它的頂面上。
	st.tilt_to(50.0, true)
	st.reset_view()
	var hi_cell := Vector2i(-1, -1)
	var best_h := 0.0
	for yy2 in range(3, m.y - 3):
		for xx2 in range(3, m.x - 3):
			var c5 := Vector2i(xx2, yy2)
			if not near_nodes.call(c5) and Relief.top_at(rel, c5) > best_h:
				best_h = Relief.top_at(rel, c5)
				hi_cell = c5
	if hi_cell.x >= 0 and best_h > 0.12:
		t.eq(st.cell_at(st.to_screen(st.center(hi_cell))), hi_cell, "★ 傾斜：最高的那一格，投影後拾取回到同一格（%.2f 高）" % best_h)
		var plane_err := st.point_at(st.to_screen(st.center(hi_cell))).distance_to(Vector2(hi_cell))
		t.ok(plane_err < 0.02, "★ 傾斜：point_at 回到那一格的中心（誤差 %.4f）" % plane_err)
	else:
		t.ok(false, "（探針）這張圖找不到夠高的格（最高 %.2f）——地形沒有起伏？" % best_h)
	st.tilt_to(0.0, true)
	st.reset_view()

	# ── ★ 三態徽章：面向相機的記號，不被建築擋住；俯瞰時在 2D 徽章的位置，傾斜後升到建築頂上 ──
	s.nodes.clear()
	s.conduits.clear()
	s.add_node("extractor", Vector2i(5, 5))
	var gen_id := s.add_node("generator", Vector2i(9, 5))
	var rel_id := s.add_node("relay", Vector2i(13, 5))
	var ext_id := int((s.node_at(Vector2i(5, 5)))["id"])
	(s.rates["node_state"] as Dictionary)[ext_id] = SessionState.STARVED
	(s.rates["node_state"] as Dictionary)[gen_id] = SessionState.STARVED_POWER
	(s.rates["node_state"] as Dictionary)[rel_id] = SessionState.OVERFLOW
	s.rev += 1
	st.tilt_to(0.0, true)
	st._process(0.0)
	t.eq(st.badge_count(), 3, "★ 三種異常狀態各有一枚徽章（缺礦砂、缺電、滿溢）")
	t.ok(not (st.ground_stage() as Object).get("draw_badges"), "地面貼圖不再畫徽章（交給 3D 的記號）")
	var bpos0: Vector3 = (st._badges[ext_id]["mi"] as MeshInstance3D).position
	t.ok(absf(bpos0.x - 5.5) < 0.001 and absf(bpos0.z - (5.5 - 20.0 / 32.0)) < 0.001 and bpos0.y < 0.1,
		"俯瞰：徽章在節點北邊 20px、貼地（與 2D 同一個位置，%s）" % str(bpos0))
	st.tilt_to(55.0, true)
	st._process(0.0)
	var bpos1: Vector3 = (st._badges[ext_id]["mi"] as MeshInstance3D).position
	t.ok(bpos1.y > Models.height_of("extractor", 0), "傾斜：徽章升到建築頂上方（%s）" % str(bpos1))
	(s.rates["node_state"] as Dictionary).erase(ext_id)
	s.rev += 1
	st._process(0.0)
	t.eq(st.badge_count(), 2, "狀態恢復正常：徽章收掉")
	t.ok(Extrude.triangle_count(Extrude.badge_mesh("starved")) >= 2 and Extrude.triangle_count(Extrude.badge_mesh("power")) >= 8 and Extrude.triangle_count(Extrude.badge_mesh("overflow")) >= 2, "三種徽章的網格都有面（底＋記號）")
	t.eq(Extrude.triangle_count(Extrude.badge_mesh("nope")), 0, "沒有的種類回空網格")
	st.tilt_to(0.0, true)

	# ── 地面貼圖：解析度跟著螢幕上一格的大小，且不超過上限 ──
	st.tilt_to(0.0, true)
	st.reset_view()
	st._process(0.0)
	var g0 := st.ground_scale()
	t.ok(g0 >= 1.0, "地面貼圖：解析度 ≥ 1（每地圖 px 至少一個貼圖 px，%.2f）" % g0)
	st.zoom_by(Stage.ZOOM_STEP * Stage.ZOOM_STEP * Stage.ZOOM_STEP, Stage.FRAME.get_center())
	st._process(0.0)
	t.ok(st.ground_scale() >= g0, "放大後貼圖解析度不降（%.2f → %.2f）" % [g0, st.ground_scale()])
	var gpx: float = float(st._gvp.size.x)
	t.ok(gpx <= float(Stage3D.GROUND_TEX_MAX) + 1.0, "地面貼圖寬度不超過上限（%d）" % int(gpx))
	t.ok((st.ground_stage() as Control).size.x >= 1.0, "地面舞台（內嵌的 Stage2D）有尺寸")

	# ── 地面貼圖只涵蓋看得到的範圍（不是整張圖）──
	st.tilt_to(40.0, true)
	st.reset_view()
	st._process(0.0)
	var vr_now := st.view_world_rect()
	t.ok(st._gwin.x >= vr_now.size.x and st._gwin.y >= vr_now.size.y, "★ 地面貼圖的視窗涵蓋整個視野（%s ≥ %s）" % [str(st._gwin), str(vr_now.size)])
	var uvr: Vector4 = (st._ground_mat as ShaderMaterial).get_shader_parameter("uv_rect")
	t.ok(uvr.z > 0.0 and uvr.w > 0.0, "uv_rect 有大小")

	# ── ★ 大圖（無盡）：可讀性地板——一格至少 24 px，所以全景只看得到圖的一部分，小地圖才現身、平移才有用 ──
	var big := SessionState.new()
	big.setup(Maps.stress_map(), [], {})
	var scr2 := ScrStub.new()
	root.add_child(scr2)
	var st2 := Stage3D.new()
	st2.ground_draw = false
	st2.scr = scr2
	st2.s = big
	scr2.add_child(st2)
	await process_frame
	await process_frame
	st2.reset_view()
	var bm: Vector2i = big.map["size"]
	t.ok(bm.x * 32 > 1152 or bm.y * 32 > 604, "（探針）壓力場景的圖大過一屏（%s）" % str(bm))
	t.ok(st2.oversized(), "★ 大圖：全景時 oversized() ＝ 真（要出小地圖）")
	var seen_h := st2.view_world_rect().size.y / 32.0
	t.ok(seen_h <= Stage.FRAME.size.y / 24.0 * 1.05 + 0.5, "★ 大圖全景：畫面涵蓋的格數受可讀性地板限制（%.1f 格 ≤ %.1f）" % [seen_h, Stage.FRAME.size.y / 24.0])
	var x_before := st2.view_world_rect().position.x
	st2.pan_by(Vector2(-300.0, 0.0))
	t.ok(st2.view_world_rect().position.x > x_before + 20.0, "★ 大圖：全景時就能平移（pan_by 有作用）")
	var far := Vector2i(bm.x - 3, bm.y - 3)
	st2.center_view_on(far, true)
	t.eq(st2.cell_at(st2.to_screen(st2.center(far))), far, "大圖：跳到遠角那一格後，投影往返仍成立")
	t.ok(Stage.FRAME.has_point(st2.to_screen(st2.center(far))), "大圖：跳過去之後那一格在畫面框架內")
	st2.tilt_to(50.0, true)
	st2.center_view_on(far, true)
	t.ok(Stage.FRAME.has_point(st2.to_screen(st2.center(far))), "大圖傾斜 50°：跳過去之後那一格仍在畫面框架內")

	_b43(t, st, s, m, scr)
	quit(t.report())


## ★ B4.3：導管、特效、血條、受擊一閃、敵人動作、落點預覽。
func _b43(t: Object, st: Stage3D, s: SessionState, m: Vector2i, scr: Control) -> void:
	st.tilt_to(0.0, true)
	st.reset_view()
	s.nodes.clear()
	s.conduits.clear()
	s.enemies.clear()
	s.shots.clear()
	s.bursts.clear()
	s.shields.clear()
	s.rev += 1

	# ── Wires：路徑貼著地形、管身有厚度、顏色與寬度走 2D 同一組算式 ──
	var rel := st.relief()
	var ra := Vector2i(3, 2)
	var rb := Vector2i(9, 2)
	var rt := Wires.route(rel, ra, rb)
	t.ok(rt.size() >= 2, "Wires.route：至少兩個點（%d）" % rt.size())
	t.ok(absf(rt[0].x - 3.5) < 0.001 and absf(rt[rt.size() - 1].x - 9.5) < 0.001, "★ Wires.route：兩端落在節點格的中心")
	var above := true
	for i in rt.size():
		var floor_y := 0.0
		for dx: float in [-0.3, 0.3]:
			for dy: float in [-0.3, 0.3]:
				floor_y = maxf(floor_y, Relief.top_at(rel, Vector2i(floori(rt[i].x + dx), floori(rt[i].z + dy))))
		above = above and rt[i].y >= floor_y
	t.ok(above, "★ Wires.route：管底永遠在地形之上（過梯田不鑽進去）")
	t.ok(is_equal_approx(Wires.height_on(rt, 0.0), rt[0].y) and is_equal_approx(Wires.height_on(rt, 99.0), rt[rt.size() - 1].y), "Wires.height_on：兩端取端點、超出夾住")
	t.ok(Wires.length_of(rt) > 5.9 and Wires.length_of(rt) < 6.1, "Wires.length_of：水平長度 ≈ 6 格（%.2f）" % Wires.length_of(rt))
	# 橋：跨越點上的管底在橋面之上。
	var crossing: Vector2i = (s.map.get("crossings", []) as Array)[0]
	var horiz := (rel["path"] as Dictionary).has(crossing + Vector2i(1, 0))
	var ca := crossing + (Vector2i(0, -3) if horiz else Vector2i(-3, 0))
	var cb := crossing + (Vector2i(0, 3) if horiz else Vector2i(3, 0))
	var brt := Wires.route(rel, ca, cb)
	t.ok(Wires.height_on(brt, 3.0) >= Relief.BRIDGE, "★ 橋：導管過跨越點時管底在橋面之上（%.3f ≥ %.2f）" % [Wires.height_on(brt, 3.0), Relief.BRIDGE])
	# 一條導管的實例資料：每個實例 16 個浮點數（3×4 變換 ＋ 顏色）；順序＝光暈（若有）→ 管身（每段一個）→ 環箍。
	var c_plain := Wires.chunk(rt, 4.0, Palette.ORDER_CYAN, 0, 0.0)
	var c_lv := Wires.chunk(rt, 4.0, Palette.ORDER_CYAN, 3, 0.0)
	var c_hurt := Wires.chunk(rt, 4.0, Palette.ORDER_CYAN, 0, 0.8)
	var n_plain := c_plain.size() / Wires.FLOATS
	t.ok(c_plain.size() % Wires.FLOATS == 0 and n_plain == rt.size() - 1, "Wires.chunk：每一段管身一個實例（%d 個）" % n_plain)
	t.eq(c_lv.size() / Wires.FLOATS, n_plain + 3, "★ Wires.chunk：每一級多一個環箍（等級刻度保留）")
	t.eq(c_hurt.size() / Wires.FLOATS, n_plain * 2, "★ Wires.chunk：受損時每段多一條橙色光暈（挨打看得見）")
	t.eq(Wires.chunk(PackedVector3Array([Vector3.ZERO]), 4.0, Palette.ORDER_CYAN, 0, 0.0).size(), 0, "Wires.chunk：不成路徑的回空")
	var body_z := Vector3(c_plain[2], c_plain[6], c_plain[10])
	var body_y := Vector3(c_plain[1], c_plain[5], c_plain[9])
	t.ok(absf(body_z.length() - 4.0 / 32.0) < 0.0002, "★ Wires.chunk：管寬 ＝ 2D 的線寬（4 px → %.4f 格）" % body_z.length())
	t.ok(absf(body_y.length() - Wires.half_height(4.0) * 2.0) < 0.0002, "Wires.chunk：管有厚度（%.4f 格）" % body_y.length())
	t.ok(
		absf(c_plain[12] - Palette.ORDER_CYAN.r) < 0.0001 and absf(c_plain[13] - Palette.ORDER_CYAN.g) < 0.0001 and absf(c_plain[14] - Palette.ORDER_CYAN.b) < 0.0001,
		"★ Wires.chunk：管身的實例色就是 `Palette.conduit()` 給的色（頂面純白 × 實例色 ＝ 原色，與 2D 同色）"
	)
	t.ok(c_plain[7] - body_y.length() * 0.5 >= rt[0].y - 0.0001, "★ Wires.chunk：管底在路徑（地形之上）")
	var thin := Wires.chunk(rt, 2.0, Palette.ORDER_CYAN, 0, 0.0)
	var fat := Wires.chunk(rt, 8.0, Palette.ORDER_CYAN, 0, 0.0)
	t.ok(Vector3(fat[2], fat[6], fat[10]).length() > Vector3(thin[2], thin[6], thin[10]).length() * 3.5 and Vector3(fat[1], fat[5], fat[9]).length() > Vector3(thin[1], thin[5], thin[9]).length(), "★ Wires.chunk：流量越大管子越寬越厚（2 px → 8 px）")
	var box := Wires.box_mesh()
	t.eq(Extrude.triangle_count(box), 12, "Wires.box_mesh：單位方盒 12 個三角形")
	var box_cols := box.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
	var white := 0
	var darker := 0
	for bc in box_cols:
		if bc.r > 0.999 and bc.g > 0.999 and bc.b > 0.999:
			white += 1
		elif bc.r < 0.95:
			darker += 1
	t.ok(white == 6 and darker == 30, "★ Wires.box_mesh：頂面純白（乘實例色＝原色）、其餘五面壓暗（立體感；白 %d／暗 %d）" % [white, darker])
	t.ok(Extrude.triangle_count(Wires.bead_mesh()) >= 40, "Wires.bead_mesh：珠子是個有面的小球")
	t.ok(Wires.SHADER.contains("lift") and Wires.SHADER.contains("POSITION"), "導管的著色器在世界座標乘 lift")

	# ── 舞台裡的導管：3D 管子取代地面貼圖的導管，珠子沿管滾 ──
	var n1 := s.add_node("relay", ra)
	var n2 := s.add_node("generator", rb)
	var cid := s.add_conduit(ra, rb)
	s.rates["conduit_flow"][cid] = 6.0
	s.rates["conduit_net"][cid] = Vector3(1.0, 0.0, 0.0)
	var ground := st.ground_stage() as Object
	st.tilt_to(0.0, true)
	st._process(0.0)
	t.ok(st.wire_count() == s.conduits.size(), "同步：導管數量一致（%d）" % st.wire_count())
	t.ok(bool(ground.get("draw_wires")), "俯瞰：地面貼圖畫導管（2D 本尊）")
	t.ok(not st._wire_mmi.visible and st.bead_count() == 0, "俯瞰：3D 導管與珠子不畫")
	st.tilt_to(50.0, true)
	s.rev += 1
	st._process(0.0)
	t.ok(not bool(ground.get("draw_wires")), "★ 傾斜：地面貼圖不再畫導管（交給 3D 的管子，不重複畫）")
	t.ok(st._wire_mmi.visible and st.wire_instances() >= 1, "傾斜：3D 導管在畫（%d 個實例）" % st.wire_instances())
	t.ok(st.wire_route(cid).size() >= 2, "導管有自己的路徑")
	t.ok(st.bead_count() > 0, "★ 傾斜：有流量的導管上有珠子（%d 顆）" % st.bead_count())
	s.rates["conduit_net"][cid] = Vector3.ZERO
	s.rates["conduit_flow"][cid] = 0.0
	s.rev += 1
	st._process(0.0)
	t.eq(st.bead_count(), 0, "沒有流量：沒有珠子")
	s.remove_node_at(rb)
	s.conduits.clear()
	s.rev += 1
	st._process(0.0)
	t.eq(st.wire_count(), 0, "拆掉之後 3D 導管被清掉")
	t.eq(st.wire_instances(), 0, "拆掉之後沒有導管實例")
	st.tilt_to(0.0, true)
	st._process(0.0)
	t.ok(bool(ground.get("draw_wires")), "回到俯瞰：地面貼圖重新畫導管")
	t.ok(n1 != n2, "（探針）兩個節點的 id 不同")

	# ── Fx3D：筆的基本形狀 ──
	var pen := Fx3D.Pen.new()
	pen.disc(Vector3.ZERO, 1.0, Vector3.RIGHT, Vector3.UP, Color.WHITE, 12)
	t.eq(pen.verts.size(), 36, "Fx3D.Pen.disc：12 邊 ＝ 12 個三角形")
	pen.ribbon(Vector3.ZERO, Vector3(1, 0, 0), 0.1, Vector3(0, -1, 0), Color.WHITE)
	t.eq(pen.verts.size(), 42, "Fx3D.Pen.ribbon：兩個三角形")
	var degenerate := Fx3D.Pen.new()
	degenerate.ribbon(Vector3.ZERO, Vector3(0, -1, 0), 0.1, Vector3(0, -1, 0), Color.WHITE)
	t.ok(degenerate.is_empty(), "Fx3D.Pen.ribbon：沿視線的退化帶不畫")
	var bar := Fx3D.Pen.new()
	Fx3D.hp_bar(bar, Vector3.ZERO, 0.5, 0.075, 0.5, Vector3.RIGHT, Vector3.UP)
	var bar0 := Fx3D.Pen.new()
	Fx3D.hp_bar(bar0, Vector3.ZERO, 0.5, 0.075, 0.0, Vector3.RIGHT, Vector3.UP)
	t.ok(bar.verts.size() == bar0.verts.size() + 6, "Fx3D.hp_bar：有血才有那一段填色（空血只剩底與軌）")

	# ── 舞台裡的特效：升起之後才在 3D 裡畫，貼地的那一份關掉 ──
	s.nodes.clear()
	s.rev += 1
	var tower := s.add_node("anchor", Vector2i(6, 3))
	var foe := s.add_enemy("drifter")
	var foe_cell: Vector2i = s.path[mini(6, s.path.size() - 1)]
	(s.enemies[0] as Dictionary)["progress"] = 6.0
	s.shots.append({"from": Vector2i(6, 3), "to": foe_cell, "ttl": 3, "by": "anchor", "target": foe, "prog": 6.0})
	s.bursts.append({"at": Vector2(foe_cell), "kind": "chaos", "seed": 7, "life": 5, "ttl": 6})
	s.shields.append({"at": foe_cell, "life": 3, "ttl": 4, "frac": 0.6})
	s.rev += 1
	st.tilt_to(0.0, true)
	st._process(0.0)
	t.ok(bool(ground.get("draw_fx")), "俯瞰：地面貼圖畫特效（2D 本尊）")
	t.ok(not st._fx_mi.visible, "俯瞰：3D 特效不畫")
	st.tilt_to(50.0, true)
	st._process(0.0)
	t.ok(not bool(ground.get("draw_fx")), "★ 傾斜：地面貼圖不再畫特效（交給 3D，不重複畫）")
	t.ok(st.fx_triangles() > 20, "★ 傾斜：開火、碎片爆、護盾、落影在 3D 裡有面（%d 個三角形）" % st.fx_triangles())
	t.ok(st._fx_mi.visible, "傾斜：特效網格在畫")
	var fx_before := st.fx_triangles()
	s.shots.clear()
	s.bursts.clear()
	s.shields.clear()
	st._process(0.0)
	t.ok(st.fx_triangles() < fx_before, "特效清掉之後開火、碎片爆、護盾的面都沒了（%d → %d）" % [fx_before, st.fx_triangles()])
	t.eq(st.shadow_count(), 1, "★ 每隻畫出來的敵人腳下一圈落影（MultiMesh 的實例）")
	# 血條：滿血沒有、受傷才有（浮在頭上，永遠看得見的那一層）。
	t.eq(st.hp_bar_triangles(), 0, "滿血的敵人沒有血條")
	(s.enemies[0] as Dictionary)["hp"] = float((s.enemies[0] as Dictionary)["hp"]) * 0.4
	st._process(0.0)
	t.ok(st.hp_bar_triangles() >= 6, "★ 受傷的敵人頭上有血條（%d 個三角形）" % st.hp_bar_triangles())
	# 受擊一閃：這一 tick 有彈落在它身上 → 換成閃光材質；沒有 → 一般材質。
	var foe_mi: MeshInstance3D = st._foes[foe]
	t.ok(foe_mi.material_override == st._solid, "沒被打中：一般材質")
	s.shots.append({"from": Vector2i(6, 3), "to": foe_cell, "ttl": 3, "by": "anchor", "target": foe})
	st._process(0.0)
	t.ok(foe_mi.material_override == st._solid_hit, "★ 受擊一閃：這一 tick 被打中的敵人換成閃光材質")
	s.shots.clear()
	st._process(0.0)
	t.ok(foe_mi.material_override == st._solid, "閃完回到一般材質")

	# ── 敵人動作：由機制欄位推導、有界、有個性；reduce_motion 時不動 ──
	var motions: Dictionary = {}
	var pose_ok := true
	var bad_pose := ""
	for ft: String in Enemies.DEFS.keys():
		var mo := Models.foe_motion(Enemies.of(ft))
		motions[ft] = mo
		for tt in range(0, 40):
			var ps := Models.foe_pose(mo, float(tt) * 0.13, 1.7)
			var sc: Vector3 = ps["scale"]
			if sc.y < 0.9 or sc.y > 1.25 or sc.x < 0.85 or sc.x > 1.15 or absf(float(ps["roll"])) > 0.15 or absf(float(ps["pitch"])) > 0.4 or float(ps["hop"]) < 0.0 or float(ps["hop"]) > 0.06:
				pose_ok = false
				bad_pose = "%s %s" % [ft, str(ps)]
	t.ok(pose_ok, "★ 每種敵人的姿態在合理範圍內（壓扁 ±25%%、搖擺 < 0.15 rad、彈跳 < 0.06 格；%s）" % bad_pose)
	var rates: Dictionary = {}
	for ft2: String in motions.keys():
		rates[snappedf(float((motions[ft2] as Dictionary)["rate"]), 0.01)] = true
	t.ok(rates.size() >= 3, "★ 敵人的動作有個性：至少 %d 種不同的節奏（重甲沉、迅捷快、再生有心跳）" % rates.size())
	var any_beat := false
	for ft3: String in motions.keys():
		any_beat = any_beat or float((motions[ft3] as Dictionary)["beat"]) > 0.0
	t.ok(any_beat, "有再生的敵人有心跳")
	var f_basis0 := foe_mi.transform.basis
	scr.set("accum", 0.0)
	s.tick_count += 3
	st._process(0.0)
	t.ok(foe_mi.transform.basis != f_basis0, "★ 敵人會動：不同的時刻姿態不同")
	Motion.reduce = true
	s.tick_count += 2
	st._process(0.0)
	var still0 := foe_mi.transform.basis
	s.tick_count += 2
	st._process(0.0)
	t.ok(foe_mi.transform.basis == still0, "★ reduce_motion：敵人不動（姿態不隨時間變）")
	Motion.reduce = false

	# ── 落點預覽：手上拿著建築、游標在地圖上 → 傾斜時是半透明的 3D 造型 ──
	s.shots.clear()
	s.enemies.clear()
	s.rev += 1
	var bscr := scr as Object
	bscr.set("hover", Vector2i(8, 6))
	bscr.set("build_type", "")
	bscr.set("mode", 0)
	st._process(0.0)
	t.ok(not st.ghost_visible(), "手上沒拿東西：沒有 3D 預覽")
	bscr.set("build_type", "prism")
	st._process(0.0)
	t.ok(st.ghost_visible(), "★ 傾斜：拿著稜鏡、游標在地圖上 → 3D 預覽出現")
	t.ok(absf(st._ghost.position.x - 8.5) < 0.001 and absf(st._ghost.position.z - 6.5) < 0.001, "預覽在游標那一格的中心")
	bscr.set("hover", Vector2i(-999, -999))
	st._process(0.0)
	t.ok(not st.ghost_visible(), "游標在地圖外：沒有預覽")
	bscr.set("hover", Vector2i(8, 6))
	bscr.set("mode", 1)
	st._process(0.0)
	t.ok(not st.ghost_visible(), "不在建造模式：沒有預覽")
	bscr.set("mode", 0)
	st.tilt_to(0.0, true)
	st._process(0.0)
	t.ok(not st.ghost_visible() and bool(ground.get("draw_ghost")), "俯瞰：沒有 3D 預覽，2D 的那份在畫")
	bscr.set("build_type", "")
	st.tilt_to(0.0, true)
	if tower < 0:
		t.ok(false, "（探針）塔沒蓋成")
