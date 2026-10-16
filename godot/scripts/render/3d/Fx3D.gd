class_name Fx3D
extends RefCounted
## ★ 3D 特效的幾何（B4.3）：開火、命中、碎片爆、護盾、血條、落影——傾斜之後從地面貼圖搬到 3D 裡。
##
## 為什麼要搬：2D 的特效全畫在地面上。傾斜後，貼地的彈道會躺在建築腳下（炮口應該在塔頂）、命中的火花落在敵人腳邊
## （應該在身上）、血量弧被前面的塔擋住。這個檔案只負責**把同一組參數變成 3D 的幾何**；開火的時間軸、顏色、
## 形狀的規格全部沿用 2D（`Stage2D._draw_shots()` 等），這裡沒有任何新的美術 token，也不新增任何模擬狀態。
##
## ── 兩種幾何 ────────────────────────────────────────────────────────────
##   · **面向相機的**（billboard）：火花、碎片、閃光、護盾泡、血條。呼叫端給相機的右軸 `r` 與上軸 `u`（旋轉之後右軸不再恆為 +X，
##     由 `Stage3D` 每幀給），形狀在 (r, u) 平面上展開——不靠著色器的 billboard，所以位置可以先算好再 lift 一次。
##   · **貼地的**：濺射環、落影——躺在水平面上（xz）。
##   彈道與光束是**帶狀**的（沿線、朝向相機的那一側加寬）。
## 單位一律是格；2D 的像素尺寸用 `px()` 換算。顏色帶 alpha（淡出）；著色器做 alpha 混合、不寫深度。

## 一般特效：做深度測試（被前面的建築擋住是對的）、不寫深度。
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
"""

## 永遠看得見的：血條（它是狀態讀數，不該被建築擋住——與三態徽章同一條理由）。
const TOP_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
"""

## 特效在 3D 裡放大多少（相對於 2D 的像素尺寸）：3D 裡一格的螢幕大小隨傾斜縮小，同樣尺寸看起來更小。
const SCALE := 1.25


## 2D 的像素尺寸 → 3D 的格。
static func px(v: float) -> float:
	return v / Shapes.GRID * SCALE


## 一把「筆」：累積帶顏色（含 alpha）的三角形。
class Pen extends RefCounted:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		verts.append(a)
		verts.append(b)
		verts.append(c)
		cols.append(col)
		cols.append(col)
		cols.append(col)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		tri(a, b, c, col)
		tri(a, c, d, col)

	## 面向相機的多邊形：`pts` 是 (r, u) 平面上的 2D 點（格），原點在 `c`。凹的也行（`Geometry2D` 三角化）。
	func poly(c: Vector3, pts: PackedVector2Array, r: Vector3, u: Vector3, col: Color) -> void:
		var idx := Geometry2D.triangulate_polygon(pts)
		for i in range(0, idx.size(), 3):
			tri(
				c + r * pts[idx[i]].x + u * pts[idx[i]].y,
				c + r * pts[idx[i + 1]].x + u * pts[idx[i + 1]].y,
				c + r * pts[idx[i + 2]].x + u * pts[idx[i + 2]].y, col
			)

	## 面向相機的實心圓。
	func disc(c: Vector3, rad: float, r: Vector3, u: Vector3, col: Color, seg: int = 16) -> void:
		for i in seg:
			var a0 := TAU * float(i) / float(seg)
			var a1 := TAU * float(i + 1) / float(seg)
			tri(
				c,
				c + (r * cos(a0) + u * sin(a0)) * rad,
				c + (r * cos(a1) + u * sin(a1)) * rad, col
			)

	## 面向相機的圓環（外半徑 `rad`、線寬 `thick`，線的中心在 `rad`）。
	func ring(c: Vector3, rad: float, thick: float, r: Vector3, u: Vector3, col: Color, seg: int = 24) -> void:
		var ro := rad + thick * 0.5
		var ri := maxf(0.0, rad - thick * 0.5)
		for i in seg:
			var a0 := TAU * float(i) / float(seg)
			var a1 := TAU * float(i + 1) / float(seg)
			var d0 := r * cos(a0) + u * sin(a0)
			var d1 := r * cos(a1) + u * sin(a1)
			quad(c + d0 * ri, c + d0 * ro, c + d1 * ro, c + d1 * ri, col)

	## 面向相機的**封閉折線**（`pts` 是 (r, u) 平面上的點，頭尾相接），線寬 `thick`。
	func outline(c: Vector3, pts: PackedVector2Array, thick: float, r: Vector3, u: Vector3, col: Color) -> void:
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			var d := b - a
			if d.length_squared() < 1.0e-10:
				continue
			var n := Vector2(-d.y, d.x).normalized() * thick * 0.5
			quad(
				c + r * (a.x + n.x) + u * (a.y + n.y), c + r * (b.x + n.x) + u * (b.y + n.y),
				c + r * (b.x - n.x) + u * (b.y - n.y), c + r * (a.x - n.x) + u * (a.y - n.y), col
			)

	## 躺在水平面上的圓環（濺射環）。
	func flat_ring(c: Vector3, rad: float, thick: float, col: Color, seg: int = 28) -> void:
		ring(c, rad, thick, Vector3.RIGHT, Vector3.BACK, col, seg)

	## 躺在水平面上的實心圓（落影）。
	func flat_disc(c: Vector3, rad: float, col: Color, seg: int = 14) -> void:
		disc(c, rad, Vector3.RIGHT, Vector3.BACK, col, seg)

	## 沿 a→b 的帶，**朝向相機的那一側加寬**（`f` ＝ 相機前方）。寬度 `w`（格）。
	func ribbon(a: Vector3, b: Vector3, w: float, f: Vector3, col: Color) -> void:
		var d := b - a
		var side := d.cross(f)
		if d.length_squared() < 1.0e-10 or side.length_squared() < 1.0e-10:
			return
		side = side.normalized() * w * 0.5
		quad(a - side, a + side, b + side, b - side, col)

	func is_empty() -> bool:
		return verts.is_empty()

	## 寫進一個**重複使用**的網格（每幀換內容；不每幀配一個新的 `ArrayMesh`）。
	func to_mesh(mesh: ArrayMesh) -> void:
		mesh.clear_surfaces()
		if verts.is_empty():
			return
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = cols
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## 單位半徑、躺在水平面上的圓盤（頂點色純白；實例色決定顏色與透明度）。落影用——一個 `MultiMesh`，不為每隻敵人各建一圈幾何。
static func disc_mesh(seg: int = 12) -> ArrayMesh:
	var pen := Pen.new()
	pen.flat_disc(Vector3.ZERO, 1.0, Color.WHITE, seg)
	var mesh := ArrayMesh.new()
	pen.to_mesh(mesh)
	return mesh


## 血條：面向相機的細長條。`frac` ＝ 剩下的血量比例；底（深色）→ 損失的部分（`lost`）→ 剩下的（`fill`）。
## 中心在 `c`，寬 `w`、高 `h`（格）。
static func hp_bar(pen: Pen, c: Vector3, w: float, h: float, frac: float, r: Vector3, u: Vector3) -> void:
	var f := clampf(frac, 0.0, 1.0)
	var pad := h * 0.35
	var hw := w * 0.5
	var hh := h * 0.5
	pen.quad(
		c - r * (hw + pad) - u * (hh + pad), c + r * (hw + pad) - u * (hh + pad),
		c + r * (hw + pad) + u * (hh + pad), c - r * (hw + pad) + u * (hh + pad), Palette.alpha(Palette.BG_DEEP, 0.92)
	)
	pen.quad(
		c - r * hw - u * hh, c + r * hw - u * hh, c + r * hw + u * hh, c - r * hw + u * hh,
		Palette.alpha(Palette.TIDE_DEEP, 1.0)
	)
	if f > 0.0:
		var x1 := -hw + w * f
		pen.quad(
			c + r * -hw - u * hh, c + r * x1 - u * hh, c + r * x1 + u * hh, c + r * -hw + u * hh,
			Palette.alpha(Palette.TIDE_MAGENTA, 1.0)
		)


# ── 攻擊特效（B4.4.2）：加亮的光暈、拖尾的彈、貫穿的光束、命中的火花與衝擊波 ─────────────────────────
#
# 使用者（2026-10-16）：「攻擊特效（包含射擊、命中特效）」要加強。以前的特效是幾條平塗的色帶與一顆四角星——
# 彈是一段短線、命中是一顆星，沒有光、沒有拖尾、沒有衝擊。現在每個特效分兩層畫：
#   · `pen`  ＝ 一般的 alpha 混合（實心的核、輪廓、碎片）；
#   · `glow` ＝ **加亮**混合（`GLOW_SHADER`）：光暈、拖尾的亮部、命中的閃光。疊在一起會更亮，才讀得出「在發光」。
# 形狀與時間軸仍由開火的資料決定（`s.shots` 的 `by`／`ttl`／`target`），這裡**沒有任何新的模擬狀態**，顏色仍全是既有的 token。
# 規模由塔的傷害決定（`power`：傷害 18 ≈ 1.0、長哨 52 ≈ 1.6）——重砲的彈大一圈、命中的衝擊重一點。

## 加亮混合：光暈、拖尾的亮部、命中的閃光。`ALPHA` 就是強度（疊加在底色上，不遮住東西）。
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
"""


## 塔的火力 → 特效的規模（0.8–1.7）。
static func power_of(dmg: float) -> float:
	return clampf(0.55 + dmg / 40.0, 0.8, 1.7)


## 砲口：一朵往前噴的閃光（朝 `dir` 的三道火舌 ＋ 四角星 ＋ 光暈）。`k` ＝ 1 → 0（越新越亮）。
static func muzzle(pen: Pen, glow: Pen, at: Vector3, dir: Vector3, k: float, power: float, r: Vector3, u: Vector3, f: Vector3, col: Color) -> void:
	glow.disc(at, px((5.0 + 6.0 * k) * power), r, u, Palette.alpha(col, 0.50 * k))
	pen.poly(at, Shapes.star(Vector2.ZERO, px((3.0 + 6.0 * k) * power), px((1.2 + 2.4 * k) * power), 4, 0.0), r, u, Palette.alpha(Palette.TEXT_PRIMARY, 0.95 * k))
	var d := dir.normalized()
	for i in 3:
		var s := (float(i) - 1.0) * 0.38
		var side := d.cross(f)
		var spread := (d + side.normalized() * s).normalized() if side.length_squared() > 1.0e-8 else d
		var len := px((9.0 + 15.0 * k) * power) * (1.0 - 0.25 * absf(s))
		glow.ribbon(at, at + spread * len, px(2.6 * power), f, Palette.alpha(col, 0.75 * k))


## 彈：沿一道微微拋起的弧飛向目標，後面拖一條漸隱的尾，彈頭一顆亮核加光暈。
## `t` ＝ 這一發的時間軸（0 出膛 → 1 結束）；0–0.6 在飛，之後只剩殘光。`arc` ＝ 弧的最高點（格，已乘 lift）。
static func bolt(pen: Pen, glow: Pen, pa: Vector3, pb: Vector3, t: float, power: float, arc: float, r: Vector3, u: Vector3, f: Vector3, col: Color) -> void:
	var total := pa.distance_to(pb)
	if total < 0.001:
		return
	var fly := clampf(t / 0.6, 0.0, 1.0)
	var s_head := 1.0 - pow(1.0 - fly, 2.0)  # ease out
	var fade := 1.0 - clampf((t - 0.6) / 0.4, 0.0, 1.0)
	var trail := minf(px(46.0 * power), total * 0.55) / total
	var segs := 6
	var prev := _arc_point(pa, pb, s_head, arc)
	for j in range(1, segs + 1):
		var sj := maxf(0.0, s_head - trail * float(j) / float(segs))
		var p := _arc_point(pa, pb, sj, arc)
		var k := 1.0 - float(j - 1) / float(segs)
		var w := px(3.6 * power) * k
		pen.ribbon(p, prev, w, f, Palette.alpha(col, 0.50 * k * fade))
		glow.ribbon(p, prev, w * 2.4, f, Palette.alpha(col, 0.22 * k * fade))
		prev = p
	var head := _arc_point(pa, pb, s_head, arc)
	glow.disc(head, px(8.5 * power), r, u, Palette.alpha(col, 0.55 * fade))
	pen.disc(head, px(3.4 * power), r, u, Palette.alpha(Palette.TEXT_PRIMARY, fade), 10)


## 光束（貫穿）：外圈光暈、亮核、沿線往目標跑的亮段；兩端各一圈。
static func beam(pen: Pen, glow: Pen, pa: Vector3, pb: Vector3, t: float, power: float, r: Vector3, u: Vector3, f: Vector3, col: Color) -> void:
	var fade := 1.0 - t
	glow.ribbon(pa, pb, px(15.0 * power), f, Palette.alpha(col, 0.20 * fade))
	glow.ribbon(pa, pb, px(7.0 * power), f, Palette.alpha(col, 0.45 * fade))
	pen.ribbon(pa, pb, px((1.2 + 2.4 * fade) * power), f, Palette.alpha(Palette.TEXT_PRIMARY, 0.55 + 0.45 * fade))
	var d := pb - pa
	var total := d.length()
	if total < 0.001:
		return
	# 三道亮段沿線往目標跑（速度比光束消退快：看得出方向）。
	var dl := minf(px(26.0), total * 0.3) / total
	for k in 3:
		var s0 := fposmod(t * 2.4 + float(k) / 3.0, 1.0)
		var s1 := minf(1.0, s0 + dl)
		glow.ribbon(pa + d * s0, pa + d * s1, px(5.0 * power), f, Palette.alpha(Palette.TEXT_PRIMARY, 0.55 * fade))
	glow.ring(pb, px((5.0 + 9.0 * t) * power), px(1.8), r, u, Palette.alpha(col, 0.6 * fade))


## 命中：一團閃光、四角星、往四面八方射的火花線、一圈擴張的環。`k` ＝ 1 → 0（越新越亮）；`seed` 決定火花的角度（零 RNG）。
static func impact(pen: Pen, glow: Pen, at: Vector3, k: float, power: float, seed_id: int, r: Vector3, u: Vector3, f: Vector3, col: Color) -> void:
	var e := 1.0 - k
	glow.disc(at, px((4.0 + 7.0 * e) * power), r, u, Palette.alpha(col, 0.50 * k))
	pen.poly(at, Shapes.star(Vector2.ZERO, px((3.0 + 6.0 * e) * power), px((1.2 + 2.4 * e) * power), 4, PI * 0.25), r, u, Palette.alpha(Palette.TEXT_PRIMARY, 0.95 * k))
	var n := 7
	var base := float(seed_id) * 0.83
	for i in n:
		var a := base + TAU * float(i) / float(n)
		var dv := r * cos(a) + u * sin(a)
		var r0 := px((2.5 + 8.0 * e) * power)
		var r1 := px((6.0 + 17.0 * e * (0.7 + 0.3 * float((i * 5) % 3) / 2.0)) * power)
		glow.ribbon(at + dv * r0, at + dv * r1, px(1.7 * power) * (1.0 - 0.5 * e), f, Palette.alpha(Palette.TEXT_PRIMARY, 0.85 * k))
	pen.ring(at, px((4.0 + 10.0 * e) * power), px(1.4), r, u, Palette.alpha(col, 0.5 * k))


## 衝擊波（濺射、死亡）：貼地擴張的環 ＋ 一圈較快較淡的外環 ＋ 中心的閃光。`radius` ＝ 最終半徑（格）、`t` ＝ 0 → 1。
static func shockwave(pen: Pen, glow: Pen, c: Vector3, radius: float, t: float, col: Color) -> void:
	var e := 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)
	var fade := 1.0 - t
	pen.flat_ring(c, radius * e, px(2.4 + 3.0 * fade), Palette.alpha(col, 0.30 + 0.50 * fade))
	glow.flat_ring(c, radius * minf(1.0, e * 1.12), px(5.0 + 5.0 * fade), Palette.alpha(col, 0.20 * fade))
	if t < 0.5:
		glow.flat_disc(c, radius * 0.45 * (1.0 - t * 1.6), Palette.alpha(col, 0.55 * (1.0 - t * 2.0)))


## 碎片：`p` 這一刻的位置、`size` 邊長（格）、`kind` ＝ 0 三角碎片 / 1 菱形 / 2 小水珠；`spin` ＝ 自轉角。
static func shard(pen: Pen, p: Vector3, size: float, kind: int, spin: float, r: Vector3, u: Vector3, col: Color) -> void:
	match kind:
		0:
			pen.poly(p, PackedVector2Array([
				Vector2(size * 1.4, 0.0).rotated(spin), Vector2(size, 0.0).rotated(spin + 2.3), Vector2(size * 0.8, 0.0).rotated(spin + 4.1),
			]), r, u, col)
		1:
			pen.poly(p, PackedVector2Array([
				Vector2(size * 1.3, 0.0).rotated(spin), Vector2(0.0, size * 0.55).rotated(spin), Vector2(-size * 1.3, 0.0).rotated(spin), Vector2(0.0, -size * 0.55).rotated(spin),
			]), r, u, col)
		_:
			pen.disc(p, size * 0.7, r, u, col, 6)


static func _arc_point(pa: Vector3, pb: Vector3, s: float, arc: float) -> Vector3:
	return pa.lerp(pb, s) + Vector3(0.0, arc * 4.0 * s * (1.0 - s), 0.0)

