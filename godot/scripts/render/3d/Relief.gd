class_name Relief
extends RefCounted
## ★ 地形起伏（B4.2）：每一格一個高度，格與格之間是**階梯**（梯田），不是連續的坡。
##
## 使用者（2026-10-15）：「地形也要有起伏」。
##
## ── 為什麼是梯田，不是平滑的丘陵 ───────────────────────────────────────────
## 這是**格子遊戲**：玩家在格上蓋東西、數格子、拉導管。每一格的頂面是平的，建築就站在那一個高度上，
## 格線（2D 那張貼圖）貼在頂面上一點不歪；高低差用格與格之間的**懸崖**講。平滑的坡會讓建築的底面浮空或陷進去，
## 而且貼圖上的格線與導管會被拉歪。所以起伏的單位就是格：`top[c]`。
##
## ── 起伏長在哪、不長在哪 ───────────────────────────────────────────────────
##   · **敵人路徑是一條溝**（高度 0）；溝的兩岸（路徑外一格，也就是侵蝕暈）一律是**岸**（`BANK`），平的——
##     那一圈是 walk-by 的傷害半徑，規則要讓人用格子數邊界（`20_ART_DIRECTION.md` §1.6），所以它不起伏。
##   · **跨越點（橋）是拱起的橋面**（`BRIDGE`）：導管走在敵人頭上——設計鎖定的「橋是架高的」第一次真的架高了。
##     橋面下是**空的**（敵人從底下走過，`cliff_mesh()` 在橋與溝之間不畫牆）。
##   · 核心的 3×3 是平台（`BANK`）：核心蓋在平的地上（路徑最後幾格落在核心的 3×3 裡，也抬到平台高度）。
##   · **礦點是一座小台地**（B4.4）：頂面比它周圍八格最高的那一格再高 `ORE_RISE`。舊版把礦點壓成 `BANK`——周圍的梯田一高，
##     礦點就陷在坑底，傾斜時被前面的台階擋住、水晶被岩石蓋住（使用者：「採集點在某些情況下會變得沒這麼明顯」）。
##     台地一律高於鄰格，所以從任何角度看都不會被地形擋住；採集器蓋上去，站的就是這個高度。
##   · 其餘的格才有起伏，由地貌決定幅度與顆粒（岩礁粗而高、淺灘細而緩、殼場是一階一階的台地），
##     離溝 1–3.5 格之間從岸漸漸過渡到自己的高度。
## 全部是**地圖 id ＋ 格座標的整數雜湊**（`Terrain.noise()`）：零 RNG，同一張圖在任何機器上長一樣。
##
## ── lift ───────────────────────────────────────────────────────────────
## 高度和建築一樣乘 `lift`（`Extrude` 檔頭）：俯瞰時整張圖是平的，**與 2D 一模一樣**；傾斜時地才隆起。

const MapsData := preload("res://data/Maps.gd")
const E := preload("res://scripts/render/3d/Extrude.gd")

## 高度的量化階（格）。
const STEP := 1.0 / 24.0
## 溝兩岸與平台的高度（格）。
const BANK := 0.10
## 礦點台地比周圍八格最高的那一格再高多少（格）。
const ORE_RISE := 0.083
## 橋面的高度（格）：比岸再高一截，底下留給敵人走。
const BRIDGE := 0.24
## 地圖四周的側壁往下延伸多少（格）。
const SLAB_DEPTH := 0.30
## 視線取樣：中間幾點、頭尾各留多少比例、擋住的寬容（格）。
const LOS_SAMPLES := 10
const LOS_ENDS := 0.08
const LOS_MARGIN := 0.02
## 礦點的框（台地頂面上的亮青環）：外半徑、內半徑、高（格）。
const ORE_RING_OUT := 0.47
const ORE_RING_IN := 0.41
const ORE_RING_H := 0.012

## 地貌 → [振幅（格）, 頻率（每格）, 疊幾層, 量化倍數]。
const PROFILE := {
	"shoal": [0.42, 0.10, 2, 1],
	"reef": [0.78, 0.17, 3, 2],
	"slag": [0.74, 0.13, 3, 1],
	"moss": [0.60, 0.11, 3, 1],
	"shell": [0.56, 0.15, 2, 3],
	"current": [0.40, 0.08, 2, 1],
	"riptide": [0.60, 0.14, 3, 1],
	"trench": [0.72, 0.09, 2, 2],
}


## 一張圖的起伏。回傳 `{w, h, top, floor, max, path, cross, biome}`：
##   `top[y*w+x]`   ＝ 這一格頂面的高度（建築站的、游標點的）；
##   `floor[...]`   ＝ 這一格**地面**的高度（敵人走的；橋底下是溝，所以和 `top` 不同）。
static func build(map: Dictionary) -> Dictionary:
	var size: Vector2i = map.get("size", Vector2i.ZERO)
	var w := size.x
	var h := size.y
	var biome := Terrain.biome_of(map)
	var prof: Array = PROFILE.get(biome, PROFILE["shoal"])
	var amp: float = prof[0]
	var freq: float = prof[1]
	var oct: int = prof[2]
	var quant: float = STEP * float(prof[3])
	var salt := String(map.get("id", "")).hash() & 0xFFFF

	var is_path: Dictionary = {}
	for c: Vector2i in MapsData.path_of(map):
		is_path[c] = true
	var cross: Dictionary = {}
	for c: Vector2i in map.get("crossings", []):
		cross[c] = true
	var flat: Dictionary = {}
	var core: Vector2i = map.get("core", Vector2i.ZERO)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			flat[core + Vector2i(dx, dy)] = true

	# 離路徑多遠（棋盤距離，BFS，最多 4）。
	var dist: Dictionary = {}
	var frontier: Array[Vector2i] = []
	for c: Vector2i in is_path.keys():
		dist[c] = 0
		frontier.append(c)
	for step in 4:
		var next: Array[Vector2i] = []
		for c: Vector2i in frontier:
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var n := c + Vector2i(dx, dy)
					if not dist.has(n):
						dist[n] = step + 1
						next.append(n)
		frontier = next

	var top := PackedFloat32Array()
	var flr := PackedFloat32Array()
	top.resize(w * h)
	flr.resize(w * h)
	var max_top := 0.0
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			var t := 0.0
			var f := 0.0
			if is_path.has(c):
				t = BRIDGE if cross.has(c) else 0.0
				f = 0.0
				# 通往核心的最後幾格（核心 3×3 之內）抬到平台的高度：核心站的地是平的。
				if flat.has(c) and not cross.has(c):
					t = BANK
					f = BANK
			else:
				var d: int = dist.get(c, 99)
				if d <= 1 or flat.has(c):
					t = BANK
				else:
					var hn := amp * _stretch(_fbm(float(x) * freq, float(y) * freq, salt, oct))
					t = lerpf(BANK, hn, smoothstep(1.0, 3.5, float(d)))
					t = roundf(t / quant) * quant
				f = t
			top[y * w + x] = t
			flr[y * w + x] = f
			max_top = maxf(max_top, t)
	# 礦點台地：比周圍八格（不含溝）最高的那一格再高 `ORE_RISE`。先從**原本的**高度算，再一起套（相鄰的兩個礦點不會越疊越高）。
	var pads: Dictionary = {}
	for c: Vector2i in map.get("ore", []):
		if is_path.has(c) or c.x < 0 or c.y < 0 or c.x >= w or c.y >= h or flat.has(c):
			continue
		var hi_n := top[c.y * w + c.x]
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var n := c + Vector2i(dx, dy)
				if n == c or is_path.has(n) or n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
					continue
				hi_n = maxf(hi_n, top[n.y * w + n.x])
		pads[c] = roundf((hi_n + ORE_RISE) / STEP) * STEP
	for c: Vector2i in pads.keys():
		top[c.y * w + c.x] = pads[c]
		flr[c.y * w + c.x] = pads[c]
		max_top = maxf(max_top, float(pads[c]))
	return {
		"w": w, "h": h, "top": top, "floor": flr, "max": max_top,
		"path": is_path, "cross": cross, "biome": biome,
	}


## ★ 視線（B4.5）：`a` → `b`（格座標、遊戲裡的實際高度）的直線有沒有被地形擋住。沿線取樣 `LOS_SAMPLES` 點（頭尾各留 `LOS_ENDS`
## 的一段，免得被自己腳下那一格與目標所在的那一格擋住），任何一點比那一格的頂面低（`LOS_MARGIN` 的寬容）就是擋住。
## 純函式、零 RNG；**目前只用在畫面**（瞄準線的虛實），模擬層的射程判定不看它。
static func line_blocked(rel: Dictionary, a: Vector3, b: Vector3) -> bool:
	for k in range(1, LOS_SAMPLES + 1):
		var t := LOS_ENDS + (1.0 - 2.0 * LOS_ENDS) * float(k) / float(LOS_SAMPLES + 1)
		var p := a.lerp(b, t)
		if top_at(rel, Vector2i(floori(p.x), floori(p.z))) > p.y + LOS_MARGIN:
			return true
	return false


static func top_at(rel: Dictionary, c: Vector2i) -> float:
	return _at(rel, "top", c)


static func floor_at(rel: Dictionary, c: Vector2i) -> float:
	return _at(rel, "floor", c)


static func _at(rel: Dictionary, key: String, c: Vector2i) -> float:
	var w: int = rel["w"]
	var h: int = rel["h"]
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return 0.0
	return (rel[key] as PackedFloat32Array)[c.y * w + c.x]


# ── 網格 ────────────────────────────────────────────────────────────────

## 頂面：每格一塊平的方片，貼 2D 舞台的那張貼圖（UV ＝ 格座標 ÷ 圖寬高），頂點色是**受光與遮蔽**：
## 高處亮一點、懸崖腳下暗一點（比相鄰高出去的每一格暗一截）。著色器把這個色乘在貼圖上、再隨 lift 淡入——
## 俯瞰（lift ＝ 0）時乘 1，貼圖原樣。
static func ground_mesh(rel: Dictionary) -> ArrayMesh:
	var w: int = rel["w"]
	var h: int = rel["h"]
	var maxh := maxf(float(rel["max"]), 0.3)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			var t := top_at(rel, c)
			var shade_k := 0.80 + 0.40 * clampf(t / maxh, 0.0, 1.0)
			var corners: Array[Vector2i] = [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x + 1, y + 1), Vector2i(x, y + 1)]
			var cc: Array[Color] = []
			var vv: Array[Vector3] = []
			var uu: Array[Vector2] = []
			for g: Vector2i in corners:
				cc.append(Palette.tint(shade_k * (1.0 - _occlusion(rel, c, g, t))))
				vv.append(Vector3(float(g.x), t, float(g.y)))
				uu.append(Vector2(float(g.x) / float(w), float(g.y) / float(h)))
			for k: int in [0, 1, 2, 0, 2, 3]:
				verts.append(vv[k])
				cols.append(cc[k])
				uvs.append(uu[k])
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 格 `c` 在它的角 `g`（格角座標）上的遮蔽：碰到這個角的另外三格，每高出 `c` 一截就暗一點。
static func _occlusion(rel: Dictionary, c: Vector2i, g: Vector2i, t: float) -> float:
	var occ := 0.0
	for dx in [-1, 0]:
		for dy in [-1, 0]:
			var n := Vector2i(g.x + dx, g.y + dy)
			if n == c:
				continue
			var dh := top_at(rel, n) - t
			if dh > 0.001:
				occ += 0.085 * minf(1.0, dh / 0.12)
	return minf(occ, 0.35)


## 懸崖：相鄰兩格高度不同就在交界立一面牆，朝向低的那一邊；地圖四周的側壁一路延伸到地台底。
## 橋與溝之間**不立牆**（底下是空的，敵人從那裡走過）。
static func cliff_mesh(rel: Dictionary) -> ArrayMesh:
	var w: int = rel["w"]
	var h: int = rel["h"]
	var is_path: Dictionary = rel["path"]
	var cross: Dictionary = rel["cross"]
	var ground := Palette.ground(String(rel["biome"]))
	var wall := ground.lerp(Palette.ROCK, 0.6).lightened(0.55)
	var strata := wall.darkened(0.22)
	var sp := E.Soup.new()
	for y in h:
		for x in w:
			var a := Vector2i(x, y)
			var ta := top_at(rel, a)
			# 東邊與南邊的鄰居（每條交界只處理一次）。
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var b := a + dir
				if b.x >= w or b.y >= h:
					continue
				var tb := top_at(rel, b)
				if absf(ta - tb) < 0.001:
					continue
				if (cross.has(a) and is_path.has(b) and not cross.has(b)) or (cross.has(b) and is_path.has(a) and not cross.has(a)):
					continue
				var lo := minf(ta, tb)
				var hi := maxf(ta, tb)
				# 低的那一邊：法線朝它。
				var a_low := ta < tb
				if dir.x == 1:
					var xe := float(x + 1)
					var n := Vector3(-1.0 if a_low else 1.0, 0.0, 0.0)
					sp.face([Vector3(xe, lo, float(y)), Vector3(xe, lo, float(y + 1)), Vector3(xe, hi, float(y + 1)), Vector3(xe, hi, float(y))], n, wall)
				else:
					var ze := float(y + 1)
					var n2 := Vector3(0.0, 0.0, -1.0 if a_low else 1.0)
					sp.face([Vector3(float(x), lo, ze), Vector3(float(x + 1), lo, ze), Vector3(float(x + 1), hi, ze), Vector3(float(x), hi, ze)], n2, wall)
	# 四周的側壁。
	for x in w:
		var t0 := top_at(rel, Vector2i(x, 0))
		var t1 := top_at(rel, Vector2i(x, h - 1))
		sp.face([Vector3(float(x), -SLAB_DEPTH, 0.0), Vector3(float(x + 1), -SLAB_DEPTH, 0.0), Vector3(float(x + 1), t0, 0.0), Vector3(float(x), t0, 0.0)], Vector3(0.0, 0.0, -1.0), strata)
		sp.face([Vector3(float(x), -SLAB_DEPTH, float(h)), Vector3(float(x + 1), -SLAB_DEPTH, float(h)), Vector3(float(x + 1), t1, float(h)), Vector3(float(x), t1, float(h))], Vector3(0.0, 0.0, 1.0), strata)
	for y in h:
		var t0 := top_at(rel, Vector2i(0, y))
		var t1 := top_at(rel, Vector2i(w - 1, y))
		sp.face([Vector3(0.0, -SLAB_DEPTH, float(y)), Vector3(0.0, -SLAB_DEPTH, float(y + 1)), Vector3(0.0, t0, float(y + 1)), Vector3(0.0, t0, float(y))], Vector3(-1.0, 0.0, 0.0), strata)
		sp.face([Vector3(float(w), -SLAB_DEPTH, float(y)), Vector3(float(w), -SLAB_DEPTH, float(y + 1)), Vector3(float(w), t1, float(y + 1)), Vector3(float(w), t1, float(y))], Vector3(1.0, 0.0, 0.0), strata)
	return sp.to_mesh()


## 地上的擺設（一整張圖一個網格）：岩石與貝殼（吃 `Terrain.build()` 的零件，擠成低矮的丘）、苔（半球）、
## 礦點的水晶與框、橋的四根燈柱。高度站在各自那一格的頂面上；全部乘 lift。
##
## ★ `occ`（B4.4）：玩家蓋了東西的格（建築 ＝ 1、只有導管經過 ＝ 2）。**岩石與貝殼不長在建築與導管底下**——
## 擺設是靜態網格、與玩家的建築無關，舊版岩丘會從建築與管子裡長出來（管子鑽進岩石）。零件的腳印（外框）碰到任何有東西的格就略過；
## 礦點本身與它周圍一圈也一律不擺岩石（2D 的擺設已經避開礦點那一格，但丘會溢到鄰格）。礦點上蓋了東西或有導管經過時，水晶不畫（不從建築裡穿出來）。
## `parts` 是 `Terrain.build()` 的結果（同一張圖不變，呼叫端可快取）；沒給就現場算。
static func scenery_mesh(map: Dictionary, rel: Dictionary, occ: Dictionary = {}, parts: Array = []) -> ArrayMesh:
	var sp := E.Soup.new()
	var px := Shapes.GRID
	var keep_clear: Dictionary = {}
	for c: Vector2i in map.get("ore", []):
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				keep_clear[c + Vector2i(dx, dy)] = true
	# 地貌的大件。
	for part: Dictionary in (parts if not parts.is_empty() else Terrain.build(map, px, 1)):
		var col: Color = part["col"]
		match String(part["kind"]):
			"fill":
				if col.a < 0.5:
					continue
				var pts: PackedVector2Array = part["pts"]
				if pts.size() < 4:
					continue
				var mid := Vector2.ZERO
				for v: Vector2 in pts:
					mid += v
				mid /= float(pts.size())
				var area := _area(pts)
				if area < 50.0:
					continue
				if _footprint_taken(pts, px, occ, keep_clear):
					continue
				var cell := Vector2i(floori(mid.x / px), floori(mid.y / px))
				var base := top_at(rel, cell)
				var rel_pts := PackedVector2Array()
				for v: Vector2 in pts:
					rel_pts.append((v - mid) / px)
				var hh := clampf(0.30 * sqrt(area) / px, 0.04, 0.17)
				E.poly_mound(sp, Vector3(mid.x / px, base, mid.y / px), rel_pts, hh * 0.45, hh, 0.62, _rock(col))
			"disc":
				var r: float = float(part["r"]) / px
				if col.a < 0.4 or r < 0.03:
					continue
				var m: Vector2 = part["c"]
				if _footprint_taken(PackedVector2Array([m - Vector2(r, r) * px, m + Vector2(r, r) * px]), px, occ, keep_clear):
					continue
				var cell2 := Vector2i(floori(m.x / px), floori(m.y / px))
				E.dome(sp, Vector3(m.x / px, top_at(rel, cell2), m.y / px), Vector3(r, r * 0.7, r), _rock(col), 2, 6)
			_:
				pass
	# 礦點：一叢水晶（採集器蓋上去就被它的底座蓋住）。
	var path: Dictionary = rel["path"]
	for c: Vector2i in map.get("ore", []):
		if path.has(c):
			continue
		var base2 := top_at(rel, c)
		var cx := float(c.x) + 0.5
		var cz := float(c.y) + 0.5
		# 框：台地頂面的一圈亮青（不吃光照），傾斜時從任何角度都讀得出「這一格是礦」；採集器蓋上去之後它還在建築腳下露出一圈。
		E.annulus(sp, Vector3(cx, base2, cz), ORE_RING_OUT, ORE_RING_IN, ORE_RING_H, 16, Palette.ORDER_BRIGHT, false)
		if occ.has(c):
			continue
		# 一叢水晶：中間一根高的發光主晶，周圍五根矮的，青／青綠／亮青交替（比舊版的三根小晶高一倍、亮一階）。
		var crystals: Array[Vector3] = [
			Vector3(0.0, 0.0, 0.20), Vector3(0.19, 0.0, 0.06), Vector3(0.12, 0.0, -0.16), Vector3(-0.12, 0.0, -0.16), Vector3(-0.19, 0.0, 0.06),
		]
		var lens: Array[float] = [0.26, 0.20, 0.30, 0.22, 0.24]
		var hues: Array[Color] = [Palette.ORDER_CYAN, Palette.ORDER_BRIGHT, Palette.MAT_TEAL, Palette.ORDER_BRIGHT, Palette.ORDER_CYAN]
		for k in crystals.size():
			var o: Vector3 = crystals[k]
			E.spike(sp, Vector3(cx + o.x, base2, cz + o.z), Vector3(o.x * 0.6, 1.0, o.z * 0.6), lens[k], 0.055, hues[k], 5)
		E.spike(sp, Vector3(cx, base2, cz), Vector3.UP, 0.40, 0.075, Palette.GLOW_CYAN, 5, false)
	# 橋：四根燈柱（橋面本身是 `top`）。
	var cross: Dictionary = rel["cross"]
	for c: Vector2i in cross.keys():
		var cx2 := float(c.x) + 0.5
		var cz2 := float(c.y) + 0.5
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var p := Vector3(cx2 + 0.40 * sx, BRIDGE, cz2 + 0.40 * sz)
				E.box(sp, p, Vector2(0.035, 0.035), 0.16, Palette.MAT_IVORY, 0.0, 0.8)
				E.dome(sp, p + Vector3(0.0, 0.16, 0.0), Vector3(0.05, 0.05, 0.05), Palette.GLOW_CYAN, 2, 6, false)
	return sp.to_mesh()


## 這個零件的腳印（`pts` 是地圖座標 px 的外框頂點）碰到的格，有任何一格有東西（`occ`）或是不許擺的（`keep_clear`）嗎？
static func _footprint_taken(pts: PackedVector2Array, px: float, occ: Dictionary, keep_clear: Dictionary) -> bool:
	if occ.is_empty() and keep_clear.is_empty():
		return false
	var lo := pts[0]
	var hi := pts[0]
	for v: Vector2 in pts:
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	for cy in range(floori(lo.y / px), floori(hi.y / px) + 1):
		for cx in range(floori(lo.x / px), floori(hi.x / px) + 1):
			var c := Vector2i(cx, cy)
			if occ.has(c) or keep_clear.has(c):
				return true
	return false


## 岩石的顏色：2D 的岩是「比地再暗一階」的底噪；3D 的岩要讓人看得出是一塊東西，所以提亮一階。
static func _rock(col: Color) -> Color:
	return Palette.alpha(col, 1.0).lightened(0.20)


static func _area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


# ── 雜訊 ────────────────────────────────────────────────────────────────

## 把雜訊的對比拉開：值雜訊疊幾層之後多半擠在 0.3–0.7 之間，直接乘振幅，整張圖只剩振幅的一小截（量過：熔渣關最高 0.33 格，
## 振幅明明是 0.42）。以 0.5 為中心放大再過 smoothstep，高處更高、低處更低、中間是緩坡，起伏才真的撐滿 `amp`。
static func _stretch(v: float) -> float:
	var k := clampf((v - 0.5) * 2.2 + 0.5, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


## 疊幾層的值雜訊 → [0, 1)。
static func _fbm(x: float, y: float, salt: int, oct: int) -> float:
	var f := 1.0
	var a := 1.0
	var sum := 0.0
	var norm := 0.0
	for o in oct:
		sum += a * _vnoise(x * f, y * f, salt + o * 17)
		norm += a
		f *= 2.03
		a *= 0.5
	return sum / norm


## 格點上是整數雜湊、格點之間平滑內插（雙線性 ＋ smoothstep）。
static func _vnoise(x: float, y: float, salt: int) -> float:
	var xi := floori(x)
	var yi := floori(y)
	var fx := x - float(xi)
	var fy := y - float(yi)
	var u := fx * fx * (3.0 - 2.0 * fx)
	var v := fy * fy * (3.0 - 2.0 * fy)
	var a := Terrain.noise(xi, yi, salt)
	var b := Terrain.noise(xi + 1, yi, salt)
	var c := Terrain.noise(xi, yi + 1, salt)
	var d := Terrain.noise(xi + 1, yi + 1, salt)
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)
