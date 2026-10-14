extends RefCounted
## 標題背景（B3.11）：一幅靜物——潮從左上進來、繞過玩家的線、抵達核心。
##
## **全部用局內同一套語彙畫**（`Glyphs`、`Foes`、`Shapes.band_jitter`、橋、流動珠），所以標題畫面
## 就是這款遊戲的第一張截圖，不是另一套美術。**零 RNG**：佈局是常數，動態只由時間 `t` 驅動；
## `TL_SHOT` 時 `t` 不走（同局內模擬凍結的理由）。
##
## **全 static**：背景是 `Main` 掛的一個**沒有 script 的 `Control`**，畫在它的 `draw` 訊號裡
## （`Main.gd` 的 `_backdrop`）——標題畫面的自檢用 `_child_script()` 找「現在掛著哪個畫面」，
## 一個帶 script 的背景會被當成畫面。這支檔案只負責「擺哪裡」，美術語彙全部來自 `render/2d/`。

const MapsData := preload("res://data/Maps.gd")
const Enemies := preload("res://data/Enemies.gd")
const Tide := preload("res://scripts/sim/Tide.gd")
const Motion := preload("res://scripts/render/Motion.gd")
const Glyphs := preload("res://scripts/render/2d/Glyphs.gd")
const Foes := preload("res://scripts/render/2d/Foes.gd")

## 潮的轉折點（格）。第一點在畫面外，最後一點是核心。
const PATH := [
	Vector2i(-1, 3), Vector2i(7, 3), Vector2i(7, 15), Vector2i(22, 15),
	Vector2i(22, 20), Vector2i(26, 20),
]
const BRIDGES := [Vector2i(7, 8), Vector2i(10, 15), Vector2i(22, 18)]
## [型別, 格]。每一格都退開路徑 2 格以上（walk-by 的傷害半徑是 1）——背景也守規則。
const NODES := [
	["core", Vector2i(26, 20)],
	["extractor", Vector2i(3, 8)], ["relay", Vector2i(10, 8)], ["smelter", Vector2i(13, 8)],
	["generator", Vector2i(10, 11)], ["silo", Vector2i(13, 11)],
	["relay", Vector2i(10, 18)], ["relay", Vector2i(18, 18)], ["relay", Vector2i(24, 18)],
	["prism", Vector2i(4, 12)], ["anchor", Vector2i(9, 13)], ["breaker", Vector2i(19, 13)],
	["reclaimer", Vector2i(13, 17)], ["knell", Vector2i(25, 17)],
	["extractor", Vector2i(33, 5)], ["generator", Vector2i(33, 9)], ["silo", Vector2i(36, 9)],
	["relay", Vector2i(33, 13)], ["longcall", Vector2i(35, 15)], ["ballast", Vector2i(31, 15)],
	["frostreef", Vector2i(33, 17)],
]
## [a, b, 珠子種類]：0 礦砂（近白）、1 能量（琥珀）、2 合金（紫）。只走 90°／45°，
## 過路徑一律走橋（`BRIDGES`）——和局內同一條規則。
const WIRES := [
	[Vector2i(3, 8), Vector2i(10, 8), 0], [Vector2i(10, 8), Vector2i(13, 8), 0],
	[Vector2i(10, 8), Vector2i(10, 11), 0], [Vector2i(10, 11), Vector2i(13, 11), 1],
	[Vector2i(10, 11), Vector2i(10, 18), 1], [Vector2i(10, 18), Vector2i(18, 18), 1],
	[Vector2i(18, 18), Vector2i(24, 18), 2], [Vector2i(24, 18), Vector2i(26, 20), 0],
	[Vector2i(33, 5), Vector2i(33, 9), 0], [Vector2i(33, 9), Vector2i(36, 9), 1],
	[Vector2i(33, 9), Vector2i(33, 13), 1], [Vector2i(33, 13), Vector2i(35, 15), 1],
	[Vector2i(33, 13), Vector2i(31, 15), 1], [Vector2i(33, 13), Vector2i(33, 17), 1],
]
## [型別, 起始進度（格）]。速度讀 `Enemies.DEFS`，走到底就從頭再來。
const ENEMIES := [
	["drifter", 0.0], ["drifter", 1.6], ["carapace", 5.0], ["ember", 11.0],
	["drifter", 16.0], ["carapace", 24.0],
]
const CORNERS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)
]
const SIDES: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
]
const AROUND: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)
]


static func _center(c: Vector2i) -> Vector2:
	return Shapes.to_world(c) + Vector2(Shapes.GRID, Shapes.GRID) * 0.5


## 一格的四角；`jitter` 為真時外緣格點走 `Shapes.band_jitter`（路徑帶），
## 否則貼格線（侵蝕暈）——和局內同一個分工（`Battle._draw_path()` 的原註）。
static func _quad(c: Vector2i, solid: Dictionary, jitter: bool) -> PackedVector2Array:
	var quad := PackedVector2Array()
	for corner: Vector2i in CORNERS:
		var g := c + corner
		var w := Shapes.to_world(g)
		if jitter:
			var interior := true
			for d: Vector2i in AROUND:
				if not solid.has(g + d):
					interior = false
			if not interior:
				w += Shapes.band_jitter(g.x, g.y)
		quad.append(w)
	return quad


## 畫一幀。`ci` 是 `Main` 掛的那個沒有 script 的 `Control`，`t` 是背景時間（秒）。
static func paint(ci: Control, t: float) -> void:
	var tick := int(t / Motion.TICK)
	Shapes.draw_grid(ci, Rect2(Vector2.ZERO, ci.size))

	# ── 潮：侵蝕暈 → 路徑帶 → 箭羽 → 橋 ──
	var path: Array = MapsData.path_of({"waypoints": PATH})
	var pset: Dictionary = {}
	for c: Vector2i in path:
		pset[c] = true
	var solid: Dictionary = {}
	for c: Vector2i in path:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				solid[c + Vector2i(dx, dy)] = true
	var halo := Palette.alpha(Palette.TIDE_DEEP, 0.13)
	var edge := Palette.alpha(Palette.TIDE_DEEP, 0.5)
	for c: Vector2i in solid:
		var q := _quad(c, solid, false)
		ci.draw_colored_polygon(q, halo)
		for side in 4:
			if not solid.has(c + SIDES[side]):
				ci.draw_line(q[side], q[(side + 1) % 4], edge, 1.0)
	var band := Palette.alpha(Palette.TIDE_DEEP, 0.45)
	for c: Vector2i in path:
		ci.draw_colored_polygon(_quad(c, solid, true), band)
	var arrow := Palette.alpha(Palette.TIDE_MAGENTA, 0.35)
	var k := 2
	while k < path.size() - 1:
		var here: Vector2i = path[k]
		var dir := Vector2(path[k + 1] - here).normalized()
		var tip := _center(here) + dir * 4.0
		ci.draw_line(tip, tip - dir * 5.0 + dir.orthogonal() * 5.0, arrow, 2.0)
		ci.draw_line(tip, tip - dir * 5.0 - dir.orthogonal() * 5.0, arrow, 2.0)
		k += 4
	for b: Vector2i in BRIDGES:
		_bridge(ci, b, pset)

	# ── 線：導管 ＋ 流動珠 ──
	for wire: Array in WIRES:
		_wire(ci, wire[0], wire[1], int(wire[2]), t)

	# ── 節點：兩趟（落影先、塔身後），和局內一樣 ──
	var rows: Array = []
	for entry: Array in NODES:
		var at := _center(entry[1])
		rows.append([at, Glyphs.build_for({"type": String(entry[0])}, at, tick)])
	for row: Array in rows:
		Glyphs.paint_shadows(ci, row[1])
	for row: Array in rows:
		Glyphs.paint_bodies(ci, row[1], row[0])

	# ── 潮的本體：在帶子上走 ──
	var total := float(maxi(path.size() - 1, 1))
	for idx in ENEMIES.size():
		var entry: Array = ENEMIES[idx]
		var def := Enemies.of(String(entry[0]))
		var speed := float(def.get("speed", 1.0))
		var prog := fposmod(float(entry[1]) + (0.0 if Motion.reduce else t) * speed, total)
		# `prog` 是「格心到格心」的連續座標，＝ `Tide.pos_of()` 的 progress − 0.5。
		var pos := Tide.pos_of(path, prog + 0.5) * Shapes.GRID + Vector2(Shapes.GRID, Shapes.GRID) * 0.5
		Foes.paint(ci, Foes.build(def, idx, pos, Tide.heading_of(path, prog + 0.5), t, false))


## 橋：`Battle._draw_crossing()` 的同一套（落影往側邊偏、雙線橋面、45° 引道）。
static func _bridge(ci: Control, cell: Vector2i, pset: Dictionary) -> void:
	var p := Shapes.to_world(cell)
	var g := Shapes.GRID
	var horizontal := pset.has(cell + Vector2i(1, 0)) or pset.has(cell + Vector2i(-1, 0))
	var c := Palette.ORDER_CYAN
	var drop := Vector2(0, 4) if horizontal else Vector2(4, 0)
	ci.draw_rect(Rect2(p + drop, Vector2(g, g)), Palette.alpha(Palette.BG_DEEP, 0.55))
	if horizontal:
		for dx: float in [7.0, g - 7.0]:
			ci.draw_line(p + Vector2(dx, -6), p + Vector2(dx, g + 6), c, 3.0)
		for dy: float in [-6.0, g + 6.0]:
			ci.draw_line(p + Vector2(4, dy), p + Vector2(g - 4, dy), c, 2.0)
			var away := signf(dy)
			for dx: float in [7.0, g - 7.0]:
				var out_x := -6.0 if dx < g * 0.5 else 6.0
				ci.draw_line(
					p + Vector2(dx, dy), p + Vector2(dx + out_x, dy + away * 6.0), c, 2.0
				)
	else:
		for dy: float in [7.0, g - 7.0]:
			ci.draw_line(p + Vector2(-6, dy), p + Vector2(g + 6, dy), c, 3.0)
		for dx: float in [-6.0, g + 6.0]:
			ci.draw_line(p + Vector2(dx, 4), p + Vector2(dx, g - 4), c, 2.0)
			var away := signf(dx)
			for dy: float in [7.0, g - 7.0]:
				var out_y := -6.0 if dy < g * 0.5 else 6.0
				ci.draw_line(
					p + Vector2(dx, dy), p + Vector2(dx + away * 6.0, dy + out_y), c, 2.0
				)


## 導管 ＋ 流動珠（`20_ART_DIRECTION.md` §1.4a 的簡化版：固定線寬、固定速度）。
## `reduce` 時珠子**仍然畫、但不動**——關動效不丟資訊（§1.4a）。
static func _wire(ci: Control, a: Vector2i, b: Vector2i, kind: int, t: float) -> void:
	var pa := _center(a)
	var pb := _center(b)
	ci.draw_line(pa, pb, Palette.ORDER_CYAN, 4.0)
	var col: Color = Palette.TEXT_PRIMARY
	if kind == 1:
		col = Palette.ENERGY_AMBER
	elif kind == 2:
		col = Palette.ALLOY_VIOLET
	var span := pa.distance_to(pb)
	if span < 1.0:
		return
	var u := (pb - pa) / span
	var x := fposmod((0.0 if Motion.reduce else t) * 48.0, 20.0)
	while x < span:
		var q := pa + u * x
		ci.draw_circle(q, 2.4, Palette.BG_DEEP)
		ci.draw_circle(q, 1.6, col)
		x += 20.0
