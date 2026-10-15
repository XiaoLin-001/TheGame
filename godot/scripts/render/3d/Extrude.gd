class_name Extrude
extends RefCounted
## ★ 3D 網格的積木與烘焙光照（B4.1 → B4.2）。
##
## 這個檔案不知道「哪一種建築」：它只提供**把幾何變成帶顏色的三角形**的東西——
##   · `Soup`：頂點色網格的累積器（`face()`／`poly()` 會把**烘焙光照**算進頂點色）；
##   · 積木：`box`／`frustum`（柱、錐、截頭錐）／`dome`（半球）／`annulus`（環）／`spike`（尖刺）／`poly_prism`（任意輪廓擠出）；
##   · `glyph_mesh()`：**後備**——把 2D 零件清單（`Glyphs.build()`）直接擠出成柱。新增一種節點還沒寫 3D 配方時
##     （`Models`），它至少不會是隱形的塔；`stage3d_test` 另外要求每一種都有配方。
##   · 徽章（billboard）的網格與著色器。
## 建築與敵人的**配方**在 `Models.gd`，地形在 `Relief.gd`。
##
## ── 烘焙光照 ────────────────────────────────────────────────────────────
## 沒有光源、沒有貼圖、沒有法線：每一個面的顏色在建網格時就算好（`shade()`）——
##   面色 ＝ 材質色 × 受光（環境 ＋ 漫射，光從左上前方來）× 離地遮蔽（越靠近地面越暗，是便宜的接觸陰影），
## 暗部**偏藍**（`Palette.MAT_SHADOW`）而不是單純變黑。發光的東西（`lit = false`）原色輸出。
## 好處：同一個畫面在任何機器上、任何時刻都是同一組像素（截圖才能當回歸基準），而且 `gl_compatibility` 上
## 一個 draw call 就能畫一整座建築。
##
## ── 高度與 lift ─────────────────────────────────────────────────────────
## 格為單位（1 ＝ 一格寬）。「傾斜」把高度乘上 `lift`（0..1）：俯瞰時 lift ＝ 0，網格退化成貼地的平面，
## 看起來就是 2D 的那張圖；傾斜得越多，越高。乘法在頂點著色器裡（`SHADER`），不在網格裡——所以網格只建一次，
## 傾斜是免費的。`UV.x` 放「疊層序」：同一個平面上疊著的幾層靠一個**不隨 lift 縮放**的小偏移分開，
## 否則 lift 趨近 0 時它們會 z-fighting。

## 疊層之間的間距（格）。不隨 lift 縮放（見檔頭）。
const LAYER_GAP := 0.0025
## 光來的方向（世界座標，指向光源）：左上、略朝相機（相機在 +z 側看向 −z）。
const LIGHT := Vector3(-0.55, 0.78, 0.30)
## 環境光：背光面仍有的亮度比例。
const AMBIENT := 0.50
## 離地多高以內開始變暗（格）、最暗的比例。
const AO_HEIGHT := 0.16
const AO_MIN := 0.76

## 頂點著色器：`lift` 乘高度，疊層偏移不乘。**顏色不看光**——烘好的。
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float lift = 1.0;
void vertex() {
	VERTEX.y = VERTEX.y * lift + UV.x * 0.0025;
}
void fragment() {
	ALBEDO = COLOR.rgb;
}
"""

## 徽章的著色器：**billboard**（面向相機）、不做深度測試（永遠看得見——它是警示，不該被建築擋住）、不看光。
## 網格原點＝徽章中心；`MODEL_MATRIX` 的位移就是它在世界裡的位置。
const BADGE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	ALBEDO = COLOR.rgb;
}
"""


# ── 烘焙光照 ────────────────────────────────────────────────────────────

## 材質色 `col`、面的法線 `n`、頂點高度 `y` → 烘好的頂點色。
static func shade(col: Color, n: Vector3, y: float) -> Color:
	var d := clampf(n.normalized().dot(LIGHT.normalized()), 0.0, 1.0)
	var s := (AMBIENT + (1.0 - AMBIENT) * d) / (AMBIENT + (1.0 - AMBIENT) * 0.93)
	var ao := lerpf(AO_MIN, 1.0, clampf(y / AO_HEIGHT, 0.0, 1.0))
	var k := minf(s * ao, 1.04)
	var lit := Palette.alpha(col, 1.0)
	lit.r *= k
	lit.g *= k
	lit.b *= k
	return lit.lerp(Palette.alpha(Palette.MAT_SHADOW, 1.0), clampf((1.0 - k) * 0.30, 0.0, 0.4))


# ── 累積器 ──────────────────────────────────────────────────────────────

class Soup extends RefCounted:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()

	## 一個三角形，**頂點色原樣**（不烘光照）。
	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, layer: int = 0) -> void:
		# ★ 不做 sRGB↔線性轉換：相容性渲染器不會在輸出時做 sRGB 編碼，所以烘進頂點的色值就是螢幕上的色值——
		#   與地面貼圖（它也是原樣輸出）同一條路，兩者才對得齊（轉了一次，建築會比 2D 暗一截，
		#   量過：琥珀 (255,200,87) 變 (255,147,21)）。
		var opaque := Palette.alpha(col, 1.0)
		for p: Vector3 in [a, b, c]:
			verts.append(p)
			cols.append(opaque)
			uvs.append(Vector2(float(layer), 0.0))

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, layer: int = 0) -> void:
		tri(a, b, c, col, layer)
		tri(a, c, d, col, layer)

	## 三角形，每個頂點依法線與自己的高度烘光照。`lit = false` ＝ 發光，原色。
	func lit_tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color, lit: bool, layer: int = 0) -> void:
		for p: Vector3 in [a, b, c]:
			verts.append(p)
			cols.append(Extrude.shade(col, n, p.y) if lit else Palette.alpha(col, 1.0))
			uvs.append(Vector2(float(layer), 0.0))

	## 一個**凸**平面多邊形（扇形三角化），法線明給。
	func face(pts: Array, n: Vector3, col: Color, lit: bool = true, layer: int = 0) -> void:
		for i in range(1, pts.size() - 1):
			lit_tri(pts[0], pts[i], pts[i + 1], n, col, lit, layer)

	## 一個凸平面多邊形，法線由頂點算、再翻成「背向 `inside`」（實心體內部的一點）。
	func poly(pts: Array, inside: Vector3, col: Color, lit: bool = true, layer: int = 0) -> void:
		if pts.size() < 3:
			return
		var n := Vector3.ZERO
		for i in range(1, pts.size() - 1):
			n = (pts[i] - pts[0]).cross(pts[i + 1] - pts[0])
			if n.length_squared() > 1.0e-10:
				break
		if n.length_squared() < 1.0e-10:
			return
		n = n.normalized()
		var mid := Vector3.ZERO
		for p: Vector3 in pts:
			mid += p
		mid /= float(pts.size())
		if n.dot(mid - inside) < 0.0:
			n = -n
		face(pts, n, col, lit, layer)

	func is_empty() -> bool:
		return verts.is_empty()

	func to_mesh() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if verts.is_empty():
			return mesh
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


## 這個網格有幾個三角形。
static func triangle_count(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


# ── 積木 ────────────────────────────────────────────────────────────────
# 座標一律是**格**；`c` 是底面中心（y ＝ 底面高度）。每一塊都是封閉的實心體（沒有底面：它貼著地或疊在別的東西上）。

## 長方體（可繞 y 轉 `yaw`、頂面縮成 `top_k` 倍）。`half`＝底面的半邊長（x, z），`h`＝高。
static func box(
	sp: Soup, c: Vector3, half: Vector2, h: float, col: Color, yaw: float = 0.0, top_k: float = 1.0,
	lit: bool = true, layer: int = 0
) -> void:
	var b: Array[Vector3] = []
	var t: Array[Vector3] = []
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for k: Vector2 in corners:
		var o := (k * half).rotated(yaw)
		var ot := (k * half * top_k).rotated(yaw)
		b.append(c + Vector3(o.x, 0.0, o.y))
		t.append(c + Vector3(ot.x, h, ot.y))
	var inside := c + Vector3(0.0, h * 0.5, 0.0)
	for i in 4:
		var j := (i + 1) % 4
		sp.poly([b[i], b[j], t[j], t[i]], inside, col, lit, layer)
	sp.face([t[0], t[1], t[2], t[3]], Vector3.UP, col, lit, layer)


## 截頭錐／柱／錐：底半徑 `r0`、頂半徑 `r1`（x, z 兩軸可不同＝橢圓）、`sides` 邊、高 `h`。`r1` ＝ 0 ＝ 錐。
static func frustum(
	sp: Soup, c: Vector3, r0: Vector2, r1: Vector2, h: float, sides: int, col: Color, yaw: float = 0.0,
	lit: bool = true, layer: int = 0
) -> void:
	var n := maxi(sides, 3)
	var inside := c + Vector3(0.0, h * 0.5, 0.0)
	var cap_pts: Array[Vector3] = []
	var bot: Array[Vector3] = []
	var top: Array[Vector3] = []
	for i in n:
		var a := yaw + TAU * float(i) / float(n)
		bot.append(c + Vector3(cos(a) * r0.x, 0.0, sin(a) * r0.y))
		top.append(c + Vector3(cos(a) * r1.x, h, sin(a) * r1.y))
	for i in n:
		var j := (i + 1) % n
		if r1.x < 0.0005 and r1.y < 0.0005:
			sp.poly([bot[i], bot[j], top[i]], inside, col, lit, layer)
		else:
			sp.poly([bot[i], bot[j], top[j], top[i]], inside, col, lit, layer)
	if r1.x >= 0.0005 or r1.y >= 0.0005:
		for p: Vector3 in top:
			cap_pts.append(p)
		sp.face(cap_pts, Vector3.UP, col, lit, layer)


## 半球（或半橢球）：`r`＝（x, y, z）三軸半徑；`lat` 圈、`lon` 邊。每個面平面著色（低多邊形的手感）。
## `down` ＝ 倒過來（碗）。
static func dome(
	sp: Soup, c: Vector3, r: Vector3, col: Color, lat: int = 3, lon: int = 8, lit: bool = true,
	down: bool = false, layer: int = 0
) -> void:
	var sgn := -1.0 if down else 1.0
	var rings: Array = []
	for k in lat + 1:
		var phi := (PI * 0.5) * float(k) / float(lat)
		var ring: Array[Vector3] = []
		for i in lon:
			var a := TAU * float(i) / float(lon)
			ring.append(c + Vector3(cos(a) * cos(phi) * r.x, sgn * sin(phi) * r.y, sin(a) * cos(phi) * r.z))
		rings.append(ring)
	for k in lat:
		var lo: Array = rings[k]
		var hi: Array = rings[k + 1]
		for i in lon:
			var j := (i + 1) % lon
			var inside := c + Vector3(0.0, sgn * 0.0, 0.0)
			if k == lat - 1:
				sp.poly([lo[i], lo[j], hi[i]], inside, col, lit, layer)
			else:
				sp.poly([lo[i], lo[j], hi[j], hi[i]], inside, col, lit, layer)


## 空心的環（短管）：外牆、內牆、頂面。`r_out`／`r_in` 半徑，`h` 高。
static func annulus(
	sp: Soup, c: Vector3, r_out: float, r_in: float, h: float, sides: int, col: Color,
	lit: bool = true, layer: int = 0
) -> void:
	var n := maxi(sides, 3)
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var am := (a0 + a1) * 0.5
		var o0 := Vector3(cos(a0) * r_out, 0.0, sin(a0) * r_out)
		var o1 := Vector3(cos(a1) * r_out, 0.0, sin(a1) * r_out)
		var i0 := Vector3(cos(a0) * r_in, 0.0, sin(a0) * r_in)
		var i1 := Vector3(cos(a1) * r_in, 0.0, sin(a1) * r_in)
		var up := Vector3(0.0, h, 0.0)
		sp.face([c + o0, c + o1, c + o1 + up, c + o0 + up], Vector3(cos(am), 0.0, sin(am)), col, lit, layer)
		sp.face([c + i1, c + i0, c + i0 + up, c + i1 + up], Vector3(-cos(am), 0.0, -sin(am)), col, lit, layer)
		sp.face([c + o0 + up, c + o1 + up, c + i1 + up, c + i0 + up], Vector3.UP, col, lit, layer)


## 尖刺（錐）：底面中心 `base`、方向 `dir`、長 `len`、底半徑 `r`、`sides` 邊。
static func spike(
	sp: Soup, base: Vector3, dir: Vector3, len: float, r: float, col: Color, sides: int = 4,
	lit: bool = true, layer: int = 0
) -> void:
	var d := dir.normalized()
	var u := d.cross(Vector3.UP)
	if u.length_squared() < 0.01:
		u = d.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := d.cross(u).normalized()
	var apex := base + d * len
	var inside := base + d * (len * 0.3)
	var ring: Array[Vector3] = []
	for i in sides:
		var a := TAU * float(i) / float(sides)
		ring.append(base + (u * cos(a) + v * sin(a)) * r)
	for i in sides:
		sp.poly([ring[i], ring[(i + 1) % sides], apex], inside, col, lit, layer)


## 任意輪廓擠出成柱：`pts`（格，相對 `c` 的 xz）、底高 `y0`、頂高 `y1`。頂面三角化（凹的也行）。
static func poly_prism(
	sp: Soup, c: Vector3, pts: PackedVector2Array, y0: float, y1: float, col: Color,
	lit: bool = true, layer: int = 0
) -> void:
	var n := pts.size()
	if n < 3:
		return
	var area := 0.0
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var e := b - a
		if e.length_squared() < 1.0e-8:
			continue
		var nrm := (Vector2(e.y, -e.x) if area > 0.0 else Vector2(-e.y, e.x)).normalized()
		sp.face([
			c + Vector3(a.x, y0, a.y), c + Vector3(b.x, y0, b.y),
			c + Vector3(b.x, y1, b.y), c + Vector3(a.x, y1, a.y),
		], Vector3(nrm.x, 0.0, nrm.y), col, lit, layer)
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		for i in range(1, n - 1):
			idx.append(0)
			idx.append(i)
			idx.append(i + 1)
	for t in range(0, idx.size(), 3):
		sp.lit_tri(
			c + Vector3(pts[idx[t]].x, y1, pts[idx[t]].y),
			c + Vector3(pts[idx[t + 1]].x, y1, pts[idx[t + 1]].y),
			c + Vector3(pts[idx[t + 2]].x, y1, pts[idx[t + 2]].y), Vector3.UP, col, lit, layer
		)


## 輪廓往內縮成 `k` 倍並抬高的「丘」（岩石、貝殼）：直壁到 `h0`，再斜到 `h1`。輪廓以自己的中心為縮放中心。
static func poly_mound(
	sp: Soup, c: Vector3, pts: PackedVector2Array, h0: float, h1: float, k: float, col: Color,
	lit: bool = true, layer: int = 0
) -> void:
	var n := pts.size()
	if n < 3:
		return
	var mid := Vector2.ZERO
	for v: Vector2 in pts:
		mid += v
	mid /= float(n)
	var inner := PackedVector2Array()
	for v: Vector2 in pts:
		inner.append(mid + (v - mid) * k)
	var inside := c + Vector3(mid.x, h1 * 0.5, mid.y)
	for i in n:
		var j := (i + 1) % n
		var a := c + Vector3(pts[i].x, -0.04, pts[i].y)
		var b := c + Vector3(pts[j].x, -0.04, pts[j].y)
		var a1 := c + Vector3(pts[i].x, h0, pts[i].y)
		var b1 := c + Vector3(pts[j].x, h0, pts[j].y)
		var a2 := c + Vector3(inner[i].x, h1, inner[i].y)
		var b2 := c + Vector3(inner[j].x, h1, inner[j].y)
		sp.poly([a, b, b1, a1], inside, col, lit, layer)
		sp.poly([a1, b1, b2, a2], inside, col, lit, layer)
	var top: Array[Vector3] = []
	for v: Vector2 in inner:
		top.append(c + Vector3(v.x, h1, v.y))
	sp.face(top, Vector3.UP, col, lit, layer)


# ── 後備：把 2D 零件清單直接擠出 ───────────────────────────────────────

## 一座節點的後備網格：`parts` 是 `Glyphs.build()` 的輸出（座標以**原點**為中心，所以呼叫端傳 `p = Vector2.ZERO`）；
## `h` 是柱高（格）、`sc` 是 `Glyphs.scale_for()`。頂面＝2D 的那張圖（背光全形 ＋ 受光一半 ＋ 輪廓），側面依光源取值。
## 回傳空網格 ＝ 沒有零件。**這不是正式的造型**——正式的在 `Models`。
static func glyph_mesh(parts: Array, h: float, sc: float) -> ArrayMesh:
	var soup := Soup.new()
	for part: Dictionary in parts:
		var col: Color = part["col"]
		match String(part["kind"]):
			"fill":
				_glyph_prism(soup, _scaled(part["pts"], sc), 0.0, h, col, 0)
			"flat":
				_glyph_cap(soup, _scaled(part["pts"], sc), h, _opaque(col), 4)
			"line":
				var lpts := _scaled(part["pts"], sc)
				var w: float = float(part["w"]) * sc
				if bool(part.get("shadow", false)):
					for i in range(lpts.size() - 1):
						var seg := _segment_quad(lpts[i], lpts[i + 1], w)
						if seg.size() >= 4:
							_glyph_prism(soup, seg, 0.0, h * 0.8, _opaque(col), 1, false)
				else:
					for i in range(lpts.size() - 1):
						var seg2 := _segment_quad(lpts[i], lpts[i + 1], w)
						if seg2.size() >= 4:
							_glyph_cap(soup, seg2, h, _opaque(col), 5)
			_:
				pass
	return soup.to_mesh()


static func _glyph_prism(
	soup: Soup, pts: PackedVector2Array, base: float, top: float, col: Color, layer: int, outline: bool = true
) -> void:
	if pts.size() < 3:
		return
	_glyph_cap(soup, pts, top, Palette.shade(col), layer)
	var lit := Shapes.clip_half(pts, Vector2.ZERO, Shapes.LIGHT_DIR)
	if lit.size() >= 3:
		_glyph_cap(soup, lit, top, col, layer + 1)
	if outline:
		var closed := pts.duplicate()
		closed.append(pts[0])
		for i in range(closed.size() - 1):
			var seg := _segment_quad(closed[i], closed[i + 1], 1.0)
			if seg.size() >= 4:
				_glyph_cap(soup, seg, top, Palette.contour(col), layer + 2)
	var n := pts.size()
	var area := 0.0
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var dark := Palette.shade(col)
	var lit_col := col.darkened(0.06)
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var e := b - a
		if e.length_squared() < 0.0001:
			continue
		var nrm := (Vector2(e.y, -e.x) if area > 0.0 else Vector2(-e.y, e.x)).normalized()
		var t := clampf(0.5 + 0.7 * nrm.dot(Shapes.LIGHT_DIR), 0.0, 1.0)
		soup.quad(_w(a, base), _w(b, base), _w(b, top), _w(a, top), dark.lerp(lit_col, t), layer)


static func _glyph_cap(soup: Soup, pts: PackedVector2Array, y: float, col: Color, layer: int) -> void:
	if pts.size() < 3:
		return
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		idx = PackedInt32Array()
		for i in range(1, pts.size() - 1):
			idx.append(0)
			idx.append(i)
			idx.append(i + 1)
	for t in range(0, idx.size(), 3):
		soup.tri(_w(pts[idx[t]], y), _w(pts[idx[t + 1]], y), _w(pts[idx[t + 2]], y), col, layer)


static func _segment_quad(a: Vector2, b: Vector2, w: float) -> PackedVector2Array:
	var d := b - a
	if d.length_squared() < 0.0001:
		return PackedVector2Array()
	var u := d.normalized()
	var n := Vector2(-u.y, u.x) * (w * 0.5)
	var ext := u * (w * 0.5)
	return PackedVector2Array([a - ext + n, b + ext + n, b + ext - n, a - ext - n])


static func _scaled(pts: PackedVector2Array, sc: float) -> PackedVector2Array:
	if sc == 1.0:
		return pts
	var out := PackedVector2Array()
	for v: Vector2 in pts:
		out.append(v * sc)
	return out


## 半透明色與一個底色先混好。零件的 alpha 是「蓋在地上」的語意；3D 網格不排序，所以在建網格時就混掉。
static func _opaque(col: Color, under: Color = Palette.BG_PANEL) -> Color:
	if col.a >= 0.999:
		return col
	return Palette.alpha(under, 1.0).lerp(Palette.alpha(col, 1.0), col.a)


## 2D 零件座標（px）→ 3D（格）。2D 的 y 往下 ＝ 世界的 +z。
static func _w(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x / Shapes.GRID, y, p.y / Shapes.GRID)


# ── 徽章 ────────────────────────────────────────────────────────────────

## ★ 三態徽章的 3D 版（B4.1c）：**和 2D 同一組座標與顏色**（`Stage2D._draw_badge`），做成**面向相機**的小記號。
## 網格的原點是徽章中心、x 向右、y 向上（單位：格），由 `BADGE_SHADER` 的 billboard 著色器擺到相機的右／上軸上。
## 為什麼要離開地面：貼地的徽章在傾斜後會被它前面的建築擋住（塔高 0.4–0.8 格，擋住的範圍到北邊 1 格多），而它是
## 「地圖上唯一指出瓶頸的元素」。`kind`：`starved`（缺礦砂）、`power`（缺電）、`overflow`（滿溢）。
static func badge_mesh(kind: String) -> ArrayMesh:
	var soup := Soup.new()
	var pts := PackedVector2Array()
	var col := Palette.WARN_ORANGE
	match kind:
		"starved":
			pts = PackedVector2Array([Vector2(-7.0, -25.0), Vector2(7.0, -25.0), Vector2(0.0, -16.0)])
		"power":
			pts = PackedVector2Array([
				Vector2(2.0, -27.0), Vector2(-6.0, -19.0), Vector2(-1.0, -19.0),
				Vector2(-3.0, -13.0), Vector2(6.0, -22.0), Vector2(1.0, -22.0),
			])
			col = Palette.ENERGY_AMBER
		"overflow":
			pts = PackedVector2Array([Vector2(0.0, -25.0), Vector2(7.0, -16.0), Vector2(-7.0, -16.0)])
			col = Palette.ORDER_BRIGHT
		_:
			return soup.to_mesh()
	# 中心＝頂點的外接框中心；先畫一圈深色的底（讓記號在任何地面上都讀得出來），再畫記號本身。
	var lo := pts[0]
	var hi := pts[0]
	for v: Vector2 in pts:
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	var mid := (lo + hi) * 0.5
	_billboard_poly(soup, pts, mid, 1.35, Palette.BG_DEEP)
	_billboard_poly(soup, pts, mid, 1.0, col)
	return soup.to_mesh()


## 一個 2D 多邊形（px）→ 面向相機的平面片（格；原點在 `mid`，y 向上），以 `k` 倍放大。
static func _billboard_poly(soup: Soup, pts: PackedVector2Array, mid: Vector2, k: float, col: Color) -> void:
	var local := PackedVector2Array()
	for v: Vector2 in pts:
		local.append((v - mid) * k)
	var idx := Geometry2D.triangulate_polygon(local)
	for t in range(0, idx.size(), 3):
		var a: Vector2 = local[idx[t]]
		var b: Vector2 = local[idx[t + 1]]
		var c: Vector2 = local[idx[t + 2]]
		soup.tri(
			Vector3(a.x / Shapes.GRID, -a.y / Shapes.GRID, 0.0),
			Vector3(b.x / Shapes.GRID, -b.y / Shapes.GRID, 0.0),
			Vector3(c.x / Shapes.GRID, -c.y / Shapes.GRID, 0.0), col, 0
		)
