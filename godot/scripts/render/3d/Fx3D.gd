class_name Fx3D
extends RefCounted
## ★ 3D 特效的幾何（B4.3）：開火、命中、碎片爆、護盾、血條、落影——傾斜之後從地面貼圖搬到 3D 裡。
##
## 為什麼要搬：2D 的特效全畫在地面上。傾斜後，貼地的彈道會躺在建築腳下（炮口應該在塔頂）、命中的火花落在敵人腳邊
## （應該在身上）、血量弧被前面的塔擋住。這個檔案只負責**把同一組參數變成 3D 的幾何**；開火的時間軸、顏色、
## 形狀的規格全部沿用 2D（`Stage2D._draw_shots()` 等），這裡沒有任何新的美術 token，也不新增任何模擬狀態。
##
## ── 兩種幾何 ────────────────────────────────────────────────────────────
##   · **面向相機的**（billboard）：火花、碎片、閃光、護盾泡、血條。呼叫端給相機的右軸 `r` 與上軸 `u`（本舞台沒有旋轉，
##     右軸恆為 +X），形狀在 (r, u) 平面上展開——不靠著色器的 billboard，所以位置可以先算好再 lift 一次。
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
