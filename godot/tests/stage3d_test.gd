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


## 主畫面的替身：契約的實作只會問它這幾件事。
class ScrStub:
	extends Control
	var accum: float = 0.0
	var hover: Vector2i = Vector2i(-999, -999)
	var selected: Vector2i = Vector2i(-1, -1)
	var refreshed: int = 0

	func redraw() -> void:
		pass

	func refresh_zoom() -> void:
		refreshed += 1


var _moved: int = 0


func _initialize() -> void:
	_run()


## 要等一個 process frame：`--script` 模式下 `_initialize()` 裡加進樹的節點，`_ready()` 要到主迴圈開始才跑。
func _run() -> void:
	var t := T.new("stage3d_test", 100)
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

	quit(t.report())
