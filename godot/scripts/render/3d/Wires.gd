class_name Wires
extends RefCounted
## ★ 3D 導管（B4.3）：傾斜之後，導管從「地面貼圖上的一條線」變成**有厚度、躺在地上的管子**。
##
## ── 資訊通道一個都不能少（`20_ART_DIRECTION.md` §1.4a、R-3）──────────────────────────────
## 導管是整個遊戲最重要的讀數：**線寬＝流量、顏色＝滿載程度與缺電、小刻度＝線材等級、橙色光暈＝挨打、珠子＝流向**。
## 3D 版逐項保留：
##   · 寬度、顏色用的是 2D 同一組算式（`Shapes.conduit_width()`、`Palette.conduit()`），呼叫端傳進來；
##   · **頂面不吃光照**（頂面的頂點色是純白，乘上實例色就是原色），所以俯瞰時管子的顏色與 2D 的線逐像素同色；
##     側面與兩端壓暗並偏藍（烘焙光照的同一個慣例），那是 3D 加的立體感；
##   · 等級刻度是管子上的**環箍**（比管子寬、比管子高一點，亮青）；受損光暈是管底下一條較寬的橙帶；
##   · 高度全部在頂點著色器乘 `lift`（`SHADER`），俯瞰時管子退化成貼地的帶——與 2D 的線同寬。
##
## ── 為什麼是 MultiMesh ────────────────────────────────────────────────────
## 一條管子由幾個**單位方盒的實例**組成（一段管身一個、每級一個環箍、受損時每段多一條光暈）。整張圖所有導管是**一個**
## `MultiMesh`＝一個 draw call，重建只是寫一塊緩衝區（`chunk()` 每條導管算一次、簽章沒變不重算）。
## 原本每條導管一個 `MeshInstance3D`：壓力場景 2045 條就是 2045 個 draw call，而且每次簽章變了要重建整個網格。
##
## ── 路徑：貼著地形走 ───────────────────────────────────────────────────────
## 管子沿著 a→b 每 `SAMPLE` 格取一個點，**管底高度 ＝ 那個點附近（±0.3 格）各格頂面的最高者 ＋ 間隙**——
## 所以管子永遠在地形之上，過梯田的高低差時是一小段斜坡，過橋時抬到橋面上。（路徑只管**管底**，與管寬無關：
## 流量一變管子變粗，路徑不必重算，管心 ＝ 管底 ＋ 半個管厚。）兩端落在節點格的中心，被建築本體蓋住
## （「管子接進機器」）。共線且等高的中間點併掉，一條直線平地上的導管就是一個方盒。
## 珠子（`Stage3D`）沿同一條路徑滾：`height_on()` 給出路徑上某一點的管底高度。
##
## 單位：格；座標與 `Models`／`Relief` 同一套（`Vector3(格.x, 高, 格.y)`，格心在 +0.5）。

const E := preload("res://scripts/render/3d/Extrude.gd")

## 沿線取樣間距（格）。
const SAMPLE := 0.5
## 管底離地面的間隙（格）。
const CLEAR := 0.012
## 取高度時看點周圍多遠的格（格）：點在格邊上時，兩側的格都算。
const REACH := 0.3
## 管厚 ÷ 管寬（偏扁：傾斜時看得到側面，又不像一根水管）；最薄不低於 `MIN_THICK`。
const THICK_K := 0.75
const MIN_THICK := 2.4 / 32.0
## 等級環箍：起點離接頭的距離、環與環的間距、環的厚度（沿管）、比管緣多伸出的量（都是 px，與 2D 同一組）。
const COLLAR_HEAD := 17.0
const COLLAR_STEP := 4.5
const COLLAR_THICK := 2.0
const COLLAR_REACH := 3.0
## 受損光暈比管子多寬（px，總寬；與 2D 的 `w + 6` 同一組）。
const HALO_EXTRA := 6.0
## 光暈的厚度（格）。
const HALO_THICK := 0.012
## 每個實例在緩衝區裡佔幾個浮點數（3×4 的變換 ＋ 顏色）。
const FLOATS := 16

## 管子的著色器：實例的變換在**世界座標**裡乘 `lift`（所以斜坡與厚度都跟著壓扁，俯瞰時整條管子貼地），
## 再加一個不乘 lift 的小偏移，免得 lift 趨近 0 時與地面 z-fighting。顏色＝實例色 × 單位方盒的頂點色（頂面純白）。
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float lift = 1.0;
void vertex() {
	vec4 w = MODEL_MATRIX * vec4(VERTEX, 1.0);
	w.y = w.y * lift + 0.004;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * w;
}
void fragment() {
	ALBEDO = COLOR.rgb;
}
"""

## 珠子用的著色器：不吃 lift（位置由呼叫端算好、球本身不該被壓扁）；顏色＝實例色 × 頂點色。
const BEAD_SHADER := """
shader_type spatial;
render_mode unshaded;
void fragment() {
	ALBEDO = COLOR.rgb;
}
"""


## 管子的路徑：`Vector3(x, 管底高度, z)`，高度未乘 lift。
static func route(rel: Dictionary, a: Vector2i, b: Vector2i) -> PackedVector3Array:
	var pa := Vector2(a) + Vector2(0.5, 0.5)
	var pb := Vector2(b) + Vector2(0.5, 0.5)
	var n := maxi(1, ceili(pa.distance_to(pb) / SAMPLE))
	var pts: Array[Vector3] = []
	for i in n + 1:
		var p := pa.lerp(pb, float(i) / float(n))
		pts.append(Vector3(p.x, _ground_y(rel, p) + CLEAR, p.y))
	var out := PackedVector3Array()
	out.append(pts[0])
	for i in range(1, pts.size() - 1):
		# 前後等高 ＝ 直的一段中間的點，不需要。
		if absf(pts[i].y - pts[i - 1].y) > 1.0e-4 or absf(pts[i].y - pts[i + 1].y) > 1.0e-4:
			out.append(pts[i])
	out.append(pts[pts.size() - 1])
	return out


## 一個點附近的地面高度（最高者）。
static func _ground_y(rel: Dictionary, p: Vector2) -> float:
	var y := 0.0
	for dx: float in [-REACH, REACH]:
		for dy: float in [-REACH, REACH]:
			y = maxf(y, Relief.top_at(rel, Vector2i(floori(p.x + dx), floori(p.y + dy))))
	return y


## 管寬（px）→ 半個管厚（格）。
static func half_height(w_px: float) -> float:
	return maxf(w_px / 32.0 * THICK_K, MIN_THICK) * 0.5


## 路徑上離起點水平距離 `d`（格）處的管底高度（線性內插；超出就夾在兩端）。
static func height_on(rt: PackedVector3Array, d: float) -> float:
	var acc := 0.0
	for i in range(1, rt.size()):
		var seg := Vector2(rt[i].x - rt[i - 1].x, rt[i].z - rt[i - 1].z).length()
		if d <= acc + seg or i == rt.size() - 1:
			var k := clampf((d - acc) / maxf(seg, 1.0e-6), 0.0, 1.0)
			return lerpf(rt[i - 1].y, rt[i].y, k)
		acc += seg
	return rt[0].y


## 路徑的水平總長（格）。
static func length_of(rt: PackedVector3Array) -> float:
	var acc := 0.0
	for i in range(1, rt.size()):
		acc += Vector2(rt[i].x - rt[i - 1].x, rt[i].z - rt[i - 1].z).length()
	return acc


## 一條導管的實例資料：每個實例 `FLOATS`（16）個浮點數——**變換（3×4，列優先）＋ 顏色（r, g, b, a）**。
## `bottom`＝`route()` 的路徑（管底）、`w_px`＝管寬（px）、`col`＝管色（`Palette.conduit()`）、`level`＝線材等級
## （環箍的數量）、`hurt`＝受損程度 0..1（> 0 就在管底鋪橙色光暈）。
## 順序：光暈（若有）→ 管身（每段一個）→ 環箍。**管身的顏色就是 `col`**（頂面純白 × `col` ＝ 原色）。
static func chunk(bottom: PackedVector3Array, w_px: float, col: Color, level: int, hurt: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	if bottom.size() < 2:
		return buf
	var w := w_px / 32.0
	var hh := half_height(w_px)
	var thick := hh * 2.0
	var d3 := bottom[bottom.size() - 1] - bottom[0]
	var dir := Vector2(d3.x, d3.z).normalized()
	var fwd := Vector3(dir.x, 0.0, dir.y)
	var perp := Vector3(-dir.y, 0.0, dir.x)
	var up := Vector3.UP

	# 受損光暈：管底下一條較寬的橙帶（先混進地面的暗色，不排序）。
	if hurt > 0.0:
		var hcol := Palette.alpha(Palette.BG_PANEL, 1.0).lerp(
			Palette.alpha(Palette.WARN_ORANGE, 1.0), 0.25 + 0.55 * clampf(hurt, 0.0, 1.0)
		)
		var hw := (w_px + HALO_EXTRA) / 32.0
		var last := bottom.size() - 1
		for i in range(1, bottom.size()):
			var a := bottom[i - 1]
			var b := bottom[i]
			var seg := Vector3(b.x - a.x, 0.0, b.z - a.z)
			# 兩端各多伸出半個光暈寬（圓頭）。
			var len := seg.length()
			var mid := (a + b) * 0.5 + Vector3(0.0, HALO_THICK * 0.5, 0.0)
			if i == 1:
				len += hw * 0.5
				mid -= fwd * hw * 0.25
			if i == last:
				len += hw * 0.5
				mid += fwd * hw * 0.25
			_push(buf, fwd * len, up * HALO_THICK, perp * hw, mid, hcol)

	# 管身：每段一個方盒（沿路徑方向、坡度跟著走）。段與段之間多重疊一點，坡度轉折處才不會露縫。
	for i in range(1, bottom.size()):
		var a := bottom[i - 1] + Vector3(0.0, hh, 0.0)
		var b := bottom[i] + Vector3(0.0, hh, 0.0)
		var seg := b - a
		var ux := seg / maxf(seg.length(), 1.0e-6)
		var uy := perp.cross(ux).normalized()
		_push(buf, ux * (seg.length() + hh), uy * thick, perp * w, (a + b) * 0.5, col)

	# 等級環箍：比管子寬、略高，亮青（`order.bright`）；從接頭（a 端）往外一圈一圈。
	if level > 0:
		var total := length_of(bottom)
		var head := minf(COLLAR_HEAD, total * 32.0 * 0.32) / 32.0
		var reach := w + 2.0 * COLLAR_REACH / 32.0
		for k in level:
			var d := head + COLLAR_STEP / 32.0 * float(k)
			var c := Vector3(bottom[0].x + fwd.x * d, height_on(bottom, d) + hh, bottom[0].z + fwd.z * d)
			_push(buf, fwd * (COLLAR_THICK / 32.0), up * (thick + 0.012), perp * reach, c, Palette.ORDER_BRIGHT)
	return buf


## 寫一個實例：三個軸向（已含縮放）、中心、顏色。
static func _push(buf: PackedFloat32Array, bx: Vector3, by: Vector3, bz: Vector3, o: Vector3, col: Color) -> void:
	buf.append_array(PackedFloat32Array([
		bx.x, by.x, bz.x, o.x,
		bx.y, by.y, bz.y, o.y,
		bx.z, by.z, bz.z, o.z,
		col.r, col.g, col.b, 1.0,
	]))


## 單位方盒（[-0.5, 0.5]³）：頂點色是**灰階的光照**——頂面純白（乘上實例色就是原色）、側面與兩端壓暗並偏藍、底面最暗。
static func box_mesh() -> ArrayMesh:
	var sp := E.Soup.new()
	var side := Color.WHITE.darkened(0.22).lerp(Palette.MAT_SHADOW, 0.10)
	var ends := Color.WHITE.darkened(0.12).lerp(Palette.MAT_SHADOW, 0.06)
	var low := Color.WHITE.darkened(0.45).lerp(Palette.MAT_SHADOW, 0.16)
	var h := 0.5
	# +y 頂面、-y 底面
	sp.quad(Vector3(-h, h, -h), Vector3(h, h, -h), Vector3(h, h, h), Vector3(-h, h, h), Color.WHITE)
	sp.quad(Vector3(-h, -h, -h), Vector3(h, -h, -h), Vector3(h, -h, h), Vector3(-h, -h, h), low)
	# ±z 兩側
	sp.quad(Vector3(-h, -h, h), Vector3(h, -h, h), Vector3(h, h, h), Vector3(-h, h, h), side)
	sp.quad(Vector3(-h, -h, -h), Vector3(h, -h, -h), Vector3(h, h, -h), Vector3(-h, h, -h), side)
	# ±x 兩端
	sp.quad(Vector3(h, -h, -h), Vector3(h, -h, h), Vector3(h, h, h), Vector3(h, h, -h), ends)
	sp.quad(Vector3(-h, -h, -h), Vector3(-h, -h, h), Vector3(-h, h, h), Vector3(-h, h, -h), ends)
	return sp.to_mesh()


## 流動珠的網格：單位半徑的小球（上下各一個半球，烘進**灰階**的光照；實例顏色 × 頂點色 ＝ 帶陰影的色）。
static func bead_mesh() -> ArrayMesh:
	var sp := E.Soup.new()
	E.dome(sp, Vector3.ZERO, Vector3.ONE, Color.WHITE, 3, 10, true, false, 4)
	E.dome(sp, Vector3.ZERO, Vector3.ONE, Color.WHITE, 3, 10, true, true, 4)
	return sp.to_mesh()
