extends SceneTree
## 開發工具（**不是測試**，不在 `qa/check.py` 的清單裡）：把十四種建築 × 三個級數、六種敵人 × 四個變體
## 擺成一張陳列照，看 3D 造型。造型是**只有親眼看才判得了**的東西（`stage3d_test` 只量輪廓與色階的下限）。
##
## 跑法（要開視窗，不能 --headless）：
##   GALLERY_OUT=C:/tmp/gallery.png GALLERY_TILT=50 GALLERY_FOCUS=17,8 GALLERY_ZOOM=2 \
##     <godot> --path godot --rendering-driver opengl3 --script res://tests/gallery_shot.gd
## `GALLERY_FOCUS` ＝ 要看的那一格（預設圖中央）、`GALLERY_ZOOM` ＝ 放大幾倍（預設 1）、`GALLERY_TILT` ＝ 傾斜角（預設 50）。
## 三排建築：0 級（y ＝ 4）、2 級（y ＝ 8）、5 級（y ＝ 12）；敵人在 y ＝ 15，每型四個變體。
## 最上面一排（y ＝ 2）是四條導管：細（2 px）、中（5 px）、粗＋三級環箍（8 px）、粗＋受損光暈，三種資源的珠子在跑。
## `GALLERY_FX=1`：在敵人那一排旁邊補一發彈丸、一次碎片爆、一個護盾、兩隻受傷的敵人（看特效與血條）。
## `GALLERY_GHOST=類型,x,y`：手上拿著那種建築、游標在 (x, y)——看落點預覽的半透明造型（例：`GALLERY_GHOST=prism,6,6`）。

const Stage := preload("res://scripts/screens/battle/Stage.gd")
const Stage3D := preload("res://scripts/screens/battle/Stage3D.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const Maps := preload("res://data/Maps.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Enemies := preload("res://data/Enemies.gd")
const Build := preload("res://scripts/sim/Build.gd")


class ScrStub:
	extends Control
	var accum: float = 0.0
	var hover: Vector2i = Vector2i(-999, -999)
	var selected: Vector2i = Vector2i(-1, -1)
	# 落點預覽（`Stage3D._sync_ghost()`）問的欄位。
	enum Mode { BUILD, DEMOLISH }
	var mode: int = Mode.DEMOLISH
	var build_type: String = ""
	var bp_index: int = -1
	var drag_from: Vector2i = Vector2i(-1, -1)

	func redraw() -> void:
		pass

	func refresh_zoom() -> void:
		pass


func _initialize() -> void:
	_run()


func _run() -> void:
	var out := OS.get_environment("GALLERY_OUT")
	var tilt := float(OS.get_environment("GALLERY_TILT")) if OS.has_environment("GALLERY_TILT") else 50.0
	var zoom := float(OS.get_environment("GALLERY_ZOOM")) if OS.has_environment("GALLERY_ZOOM") else 1.0
	var map := Maps.SANDBOX.duplicate(true)
	map["id"] = "gallery"
	map["size"] = Vector2i(34, 17)
	map["core"] = Vector2i(31, 1)
	var s := SessionState.new()
	s.setup(map)
	s.nodes.clear()
	var types: Array = []
	for ty: String in NodeDefs.DEFS.keys():
		if ty != "core":
			types.append(ty)
	var rows: Array[int] = [0, 2, 5]
	for r in rows.size():
		for i in types.size():
			var id := s.add_node(String(types[i]), Vector2i(2 + 2 * i, 4 + 4 * r))
			for n: Dictionary in s.nodes:
				if int(n["id"]) == id:
					n["level"] = rows[r]
	s.add_node("core", Vector2i(31, 1))
	# 導管：四條，寬度由流量、環箍由等級、光暈由血量決定（與局內同一組算式）。
	var cap_max := Build.conduit_cap(Build.CAP_MAX_LEVEL, 0.0)
	var wires: Array = [
		[2, 0.0, 0, 40.0], [9, 0.5, 0, 40.0], [16, 1.0, 3, 40.0], [23, 1.0, 0, 10.0],
	]
	for wspec: Array in wires:
		var xa := int(wspec[0])
		s.add_node("relay", Vector2i(xa, 2))
		s.add_node("relay", Vector2i(xa + 5, 2))
		var cid := s.add_conduit(Vector2i(xa, 2), Vector2i(xa + 5, 2))
		for cd: Dictionary in s.conduits:
			if int(cd["id"]) == cid:
				cd["level"] = int(wspec[2])
				cd["hp"] = float(wspec[3])
		(s.rates["conduit_flow"] as Dictionary)[cid] = float(wspec[1]) * cap_max
		(s.rates["conduit_net"] as Dictionary)[cid] = Vector3(1.0, 1.0, 0.4)
	s.rev += 1

	var bg := ColorRect.new()
	bg.color = Palette.BG_DEEP
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	var scr := ScrStub.new()
	root.add_child(scr)
	var st := Stage3D.new()
	st.ground_draw = false
	st.scr = scr
	st.s = s
	scr.add_child(st)
	await process_frame
	await process_frame
	# 地面貼圖沒有 2D 舞台可畫（替身畫面層沒有 HUD）：塗一整片地色，讓陳列照看得到地形與建築的相對關係。
	var fill := ColorRect.new()
	fill.color = Palette.ground("shoal").lightened(0.35)
	fill.size = Vector2(4096.0, 4096.0)
	st._gvp.add_child(fill)
	st.reset_view()
	st.tilt_to(tilt, true)
	var focus := Vector2i(17, 8)
	if OS.has_environment("GALLERY_FOCUS"):
		var parts := OS.get_environment("GALLERY_FOCUS").split(",")
		focus = Vector2i(int(parts[0]), int(parts[1]))
	if zoom > 1.0:
		st.zoom_by(zoom, Stage.FRAME.get_center())
	st.center_view_on(focus, true)
	# 敵人：每型四個變體，面朝 +x。
	var x := 2.0
	for ft: String in Enemies.DEFS.keys():
		for v in 4:
			var mi := MeshInstance3D.new()
			mi.mesh = st._foe_mesh(ft, v)
			mi.material_override = st._solid
			mi.position = Vector3(x, 0.0, 15.5)
			st._foe_root.add_child(mi)
			x += 1.3
		x += 0.6
	if OS.has_environment("GALLERY_GHOST"):
		var gp := OS.get_environment("GALLERY_GHOST").split(",")
		scr.mode = ScrStub.Mode.BUILD
		scr.build_type = gp[0]
		scr.hover = Vector2i(int(gp[1]), int(gp[2]))
	if OS.has_environment("GALLERY_FX"):
		# 兩隻受傷的敵人（敵人走路徑，所以把路徑接到陳列的那一排旁邊）＋ 一發彈丸、一次碎片爆、一個護盾。
		var path_cells: Array[Vector2i] = []
		for gx in range(2, 34):
			path_cells.append(Vector2i(gx, 15))
		s.path = path_cells
		for k in 2:
			var fid := s.add_enemy("shellback" if Enemies.DEFS.has("shellback") else String(Enemies.DEFS.keys()[0]))
			(s.enemies[k] as Dictionary)["progress"] = 10.0 + 5.0 * float(k)
			(s.enemies[k] as Dictionary)["hp"] = float((s.enemies[k] as Dictionary)["hp"]) * (0.35 + 0.3 * float(k))
			if k == 0:
				s.shots.append({"from": Vector2i(10, 12), "to": Vector2i(12, 15), "ttl": 3, "by": "anchor", "target": fid})
		s.bursts.append({"at": Vector2(24.0, 15.0), "kind": "chaos", "seed": 5, "life": 3, "ttl": 6})
		s.bursts.append({"at": Vector2(20.0, 14.0), "kind": "order", "seed": 3, "life": 3, "ttl": 6})
		s.shields.append({"at": Vector2i(17, 15), "life": 2, "ttl": 4, "frac": 0.7})
		s.rev += 1
	for _i in 6:
		st._process(0.016)
		await process_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	if out != "":
		img.save_png(out)
		print("[gallery] saved ", out, " ", img.get_size())
	quit(0)
