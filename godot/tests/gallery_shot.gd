extends SceneTree
## 開發工具（**不是測試**，不在 `qa/check.py` 的清單裡）：把十四種建築 × 三個級數、六種敵人 × 四個變體
## 擺成一張陳列照，看 3D 造型。造型是**只有親眼看才判得了**的東西（`stage3d_test` 只量輪廓與色階的下限）。
##
## 跑法（要開視窗，不能 --headless）：
##   GALLERY_OUT=C:/tmp/gallery.png GALLERY_TILT=50 GALLERY_FOCUS=17,8 GALLERY_ZOOM=2 \
##     <godot> --path godot --rendering-driver opengl3 --script res://tests/gallery_shot.gd
## `GALLERY_FOCUS` ＝ 要看的那一格（預設圖中央）、`GALLERY_ZOOM` ＝ 放大幾倍（預設 1）、`GALLERY_TILT` ＝ 傾斜角（預設 50）。
## 三排建築：0 級（y ＝ 4）、2 級（y ＝ 8）、5 級（y ＝ 12）；敵人在 y ＝ 15，每型四個變體。

const Stage := preload("res://scripts/screens/battle/Stage.gd")
const Stage3D := preload("res://scripts/screens/battle/Stage3D.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")
const Maps := preload("res://data/Maps.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Enemies := preload("res://data/Enemies.gd")


class ScrStub:
	extends Control
	var accum: float = 0.0
	var hover: Vector2i = Vector2i(-999, -999)
	var selected: Vector2i = Vector2i(-1, -1)

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
