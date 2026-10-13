extends SceneTree
## 舞台契約測試：`Stage3D` 必須滿足 `screens/battle/Stage.gd` 的契約（B4.0 脊椎）。
##
## **這是 2D→3D 轉換的驗收尺**：契約的每一條都在這裡被當成斷言。換一個舞台實作（或把 `Stage3D` 做完整）
## 之後，這支必須維持全綠——它守的是「局內畫面與 HUD 不必知道舞台是 2D 還是 3D」這件事。
##
## 不載入 autoload（`30_TECH_DESIGN.md` §4.2），所以 `Stage3D` 自己也不得引用任何 autoload——這支測試
## 順便守住它。主畫面的部分（`scr`）用一個最小的替身。
##
## 跑法：<godot> --headless --path godot --script res://tests/stage3d_test.gd

const T := preload("res://tests/_assert.gd")
const Stage := preload("res://scripts/screens/battle/Stage.gd")
const Stage3D := preload("res://scripts/screens/battle/Stage3D.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const Maps := preload("res://data/Maps.gd")


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
	var t := T.new("stage3d_test", 29)
	var s := SessionState.new()
	s.setup(Maps.SHOAL)
	var scr := ScrStub.new()
	root.add_child(scr)
	var st := Stage3D.new()
	st.scr = scr
	st.s = s
	st.view_moved.connect(func() -> void: _moved += 1)
	scr.add_child(st)
	await process_frame
	await process_frame
	st.reset_view()

	var m: Vector2i = s.map["size"]
	var mpx := Vector2(m) * 32.0

	# ── 投影與拾取：格 → 螢幕 → 同一格；`point_at` 與 `center` 同一個座標系 ──
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

	# ── 平移：拖曳往右＝看到更左邊；夾在地圖範圍內 ──
	st.zoom_by(Stage.ZOOM_STEP * Stage.ZOOM_STEP, anchor)
	var x0 := st.view_world_rect().position.x
	st.pan_by(Vector2(60.0, 0.0))
	t.ok(st.view_world_rect().position.x < x0, "pan_by(+x)：視野往左移（拖曳往右）")
	st.pan_by(Vector2(99999.0, 99999.0))
	var edge := st.view_world_rect()
	t.ok(edge.position.x >= -mpx.x and edge.position.y >= -mpx.y, "pan_by：推到底夾在地圖範圍內")
	st.pan_by(Vector2(-99999.0, -99999.0))
	t.ok(st.view_world_rect().end.x <= mpx.x * 2.0, "pan_by：反向推到底也夾住")

	# ── center_view_on：把某一格移到畫面中央 ──
	var target := Vector2i(m.x / 2, m.y / 2)
	st.center_view_on(target, true)
	var center_px := st.view_world_rect().get_center()
	t.ok(center_px.distance_to(st.center(target)) < 40.0, "★ center_view_on：視野中心落在那一格附近")

	# ── 回到全景 ──
	st.reset_view()
	t.ok(is_equal_approx(st.zoom, st.fit) and not st.oversized(), "reset_view：回到全景")

	# ── 每幀同步：局的狀態 → 3D（節點、導管、敵人）──
	st._process(0.0)
	t.eq(st._nodes.size(), s.nodes.size(), "同步：節點數 ＝ 局裡的節點數（核心也算）")
	var a := s.add_node("relay", Vector2i(3, 3))
	var b := s.add_node("generator", Vector2i(6, 3))
	s.add_conduit(Vector2i(3, 3), Vector2i(6, 3))
	s.add_enemy("drifter")
	st._process(0.0)
	t.eq(st._nodes.size(), s.nodes.size(), "同步：新增節點後數量一致")
	t.eq(st._wires.size(), 1, "同步：新增導管後數量一致")
	t.eq(st._foes.size(), 1, "同步：新增敵人後數量一致")
	s.remove_node_at(Vector2i(6, 3))
	s.enemies.clear()
	st._process(0.0)
	t.eq(st._nodes.size(), s.nodes.size(), "同步：拆掉節點後多出來的被清掉")
	t.eq(st._wires.size(), 0, "同步：連帶拆掉的導管也被清掉")
	t.eq(st._foes.size(), 0, "同步：敵人死了就清掉")
	t.ok(a != b, "（探針）兩個新節點的 id 不同")

	# ── 每幀推導給 HUD 讀 ──
	t.ok(st.engaged is Dictionary and st.threat is Dictionary, "每幀推導：engaged／threat 存在")

	quit(t.report())
