class_name Glyphs
extends RefCounted
## ★ 節點的圖形（B3.11）：**幾何是純函式，上色是體積語言。**
##
## ── 為什麼從 `Battle._draw_node_body()` 抽出來 ──────────────────────────
## B3.10 的收尾寫著：「要真的守住形狀，得先把那十三段輪廓抽成純函式」。
## 這一批做了，理由有三個，由重到輕：
##   ① **同一份幾何要在四個地方畫**：地圖上的節點、擺放預覽、名冊的卡片、
##      標題畫面的背景。B3.4 已經證明過「抄一份」的下場（加第十五種時只有一邊
##      記得加，而漏掉的那一邊症狀是隱形）。
##   ② **上色要統一**：落影／受光面／輪廓是套在每一個多邊形上的同一套規則，
##      放在 `match` 的每一個分支裡就是 13 × 3 行會漂的東西。幾何只回傳
##      「哪些多邊形、什麼顏色」，上色在 `paint()` 一處做完。
##   ③ **斷言得到**：`hud_test` 逐型別逐級拿 `extent()` 對 `Shapes.body_extent()`
##      那張表——B3.10 那句「改輪廓要一起改」從叮嚀變成紅燈。
##
## ── 零件（part）的形狀 ────────────────────────────────────────────────
## 每一筆是一個字典，`kind` 決定畫法：
##   `fill`  實心多邊形，**吃體積語言**（背光面 ＋ 受光面 ＋ 輪廓 ＋ 落影）
##   `flat`  實心多邊形，**不上陰影**——燈、芯、心跳這種「發光的東西」
##   `line`  折線（閉合的自己把第一點補在尾巴），有落影、沒有受光面
##   `arc`   圓弧，儀表用（儲槽的充能弧），不上陰影
## 座標一律是**地圖 px、以格心 `p` 為中心**；縮放交給呼叫端的 `draw_set_transform`。
##
## ── 三條不變量 ──────────────────────────────────────────────────────
##   · **只讀 `NodeDefs` 既有的機制欄位**，不新增美術資料（§1.7 統御規則）。
##   · **零 RNG、由 tick 驅動**：`tick` 只餵給核心的心跳（`Motion.pulse01`）。
##   · 對不到的型別回傳**空陣列**，呼叫端據此標 `_no_glyph`——漏一種的症狀
##     必須是紅燈不是隱形（B2.4 中過三次）。

const Build := preload("res://scripts/sim/Build.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Maps := preload("res://data/Maps.gd")

## 圓改用多少邊的正多邊形畫。**圓也走多邊形**是為了讓它吃到同一套受光面裁切；
## 28 邊在 11px 半徑上和 `draw_circle` 分不出來。
const CIRCLE_SIDES := 28


## 從一筆節點字典建圖形。**只需要 `type`**；`level`／`hp`／`charge` 缺了就當作
## 0 級、滿血、空槽（擺放預覽與名冊卡片傳進來的正是這種字典）。
static func build_for(n: Dictionary, p: Vector2, tick: int) -> Array:
	var type := String(n.get("type", ""))
	var lv := int(n.get("level", 0))
	var full := NodeDefs.hp(type)
	var hurt: bool = float(n.get("hp", full)) < full
	var frac := 0.0
	if type == "silo":
		frac = float(n.get("charge", 0.0)) / maxf(1.0, float(NodeDefs.of("silo")["capacity"]))
	return build(
		type, lv,
		Build.step_count(type, lv, Build.STEP_POWER),
		Build.step_count(type, lv, Build.STEP_ROF),
		Build.step_count(type, lv, Build.STEP_RANGE),
		Build.step_count(type, lv, Build.STEP_SPLASH),
		p, hurt, frac, tick
	)


## 這一筆節點要套的縮放（B3.10 的 `fit_scale`，量 `body_extent`）。
static func scale_for(n: Dictionary) -> float:
	var type := String(n.get("type", ""))
	var lv := int(n.get("level", 0))
	return Shapes.fit_scale(Shapes.body_extent(
		type, lv,
		Build.step_count(type, lv, Build.STEP_POWER),
		Build.step_count(type, lv, Build.STEP_ROF),
		Build.step_count(type, lv, Build.STEP_RANGE),
		Build.step_count(type, lv, Build.STEP_SPLASH)
	), lv)


## ★ 十三種節點 ＋ 核心的幾何。**級數驅動的是輪廓自己的參數**（B3.9.4）：
##   出力 → 更厚重（層數／齒數／邊數／配重）
##   射速 → 更多管口（砲口／橫桿／吊索）
##   射程 → 更高更長（軸向拉長／輻條）
##   濺射 → 更尖（尖角更多更深）
## 輪廓的**最遠點**必須對得上 `Shapes.body_extent()`（`hud_test` 在對）。
static func build(
	type: String, lv: int, n_pow: int, n_rof: int, n_rng: int, n_spl: int,
	p: Vector2, hurt: bool, charge_frac: float, tick: int
) -> Array:
	var out: Array = []
	match type:
		"core":
			# ★ **最大的幾何體**，`order.bright` 描邊（§1.6）；48 ＝ 1.5 格（§7.1 A-4）。
			#   受擊時整體閃 `warn.orange`——核心掉血是這一局唯一不可逆的事。
			var body: Color = Palette.WARN_ORANGE if hurt else Palette.ORDER_BRIGHT
			var alarm := Motion.pulse01(tick, Motion.BASE * 4.0, 0.5) if hurt else 1.0
			var beat := Motion.pulse01(tick, Motion.AMBIENT * 2.0, 0.55)
			var shell := Shapes.chamfer_square(p, 24.0, 4.0)
			out.append(_fill(shell, Palette.BG_RAISED))
			# 內層的斜格：讓它讀起來是「一座設施」，不是一塊有框的方塊。
			out.append(_line(_closed(Shapes.ngon(p, 17.0, 4, 0.0)), Palette.ORDER_DIM, 1.5, false))
			out.append(_line(_closed(shell), Palette.alpha(body, alarm), 3.0, false))
			# 極慢的呼吸＝這張圖的心跳。**不是警示**（警示是橙色而且更急）。
			out.append(_flat(
				Shapes.chamfer_square(p, 8.0, 1.5), Palette.alpha(body, alarm if hurt else beat)
			))
		"extractor":
			# 圓 → **齒輪**（每級一齒）。中心的亮芯是鑽頭。
			if lv == 0:
				out.append(_fill(Shapes.ngon(p, 11.0, CIRCLE_SIDES), Palette.ORDER_CYAN))
				out.append(_flat(Shapes.ngon(p, 3.5, 12), Palette.ORDER_BRIGHT))
			else:
				out.append(_fill(Shapes.gear(p, 11.5, 4 + n_pow, 3.0), Palette.ORDER_CYAN))
				out.append(_flat(Shapes.ngon(p, 4.0, 12), Palette.ORDER_BRIGHT))
		"generator":
			# 方 → **切角 → 八邊**（每級削 1.7px）。琥珀專屬於能量（§1.1 配色紀律 2）。
			out.append(_fill(
				Shapes.chamfer_square(p, 11.0, 1.7 * float(n_pow)), Palette.ENERGY_AMBER
			))
			# 蝕刻在面上的線圈：發電機是「機器」不是「一塊金色」。
			out.append(_line(
				_closed(Shapes.ngon(p, 6.0, 4, 0.0)), Palette.shade(Palette.ENERGY_AMBER), 1.5, false
			))
		"smelter":
			# 六邊 → **六芒**（每級把交錯的角往內收）。內圈琥珀＝它待機也在吃電。
			var hexp: PackedVector2Array = (
				Shapes.ngon(p, 12.0, 6) if lv == 0
				else Shapes.star(p, 12.0 + 0.6 * float(n_pow), 12.0 - 1.4 * float(n_pow), 6)
			)
			out.append(_fill(hexp, Palette.ALLOY_STEEL))
			out.append(_arc(p, 6.5, Palette.alpha(Palette.ENERGY_AMBER, 0.35), 2.0))
			out.append(_flat(Shapes.ngon(p, 5.0, 16), Palette.ENERGY_AMBER))
		"relay":
			# 菱 → **越來越尖的四芒**。中心一點＝接點。
			var dia: PackedVector2Array = (
				Shapes.ngon(p, 8.0, 4) if lv == 0
				else Shapes.star(p, 8.0 + float(n_pow), 8.0 - 1.2 * float(n_pow), 4)
			)
			out.append(_fill(dia, Palette.ORDER_DIM))
			out.append(_flat(Shapes.ngon(p, 2.0, 8), Palette.ORDER_CYAN))
		"silo":
			# 圓槽 → **打成多邊形的槽**（每級少一個面）。槽身有一層淡淡的填色，
			# 讀起來是一個容器，不是一個空圈；充能弧照舊在外圈。
			out.append(_flat(Shapes.ngon(p, 10.5, 32), Palette.alpha(Palette.ORDER_DIM, 0.28)))
			if lv == 0:
				out.append(_line(_closed(Shapes.ngon(p, 12.0, 32)), Palette.ORDER_DIM, 2.0, true))
			else:
				out.append(_line(
					_closed(Shapes.ngon(p, 12.5, maxi(5, 12 - n_pow), -PI * 0.5)),
					Palette.ORDER_DIM, 2.4, true
				))
			if charge_frac > 0.0:
				out.append(_arc_span(
					p, 12.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(charge_frac, 0.0, 1.0),
					Palette.ENERGY_AMBER, 4.0
				))
		"anchor":
			# ★ 上寬下窄的梯形＝**打進地裡的樁**（B2.4.8）。
			#   出力 → 多疊一層；射速 → 頂端多兩管；射程 → 整支拉高。
			var top := -9.0 - 2.2 * float(n_rng)
			var tiers := 1 + n_pow
			for k in tiers:
				var t0 := lerpf(top, 10.0, float(k) / float(tiers))
				var t1 := lerpf(top, 10.0, float(k + 1) / float(tiers)) - (1.4 if k < tiers - 1 else 0.0)
				var wa := lerpf(11.0, 6.0, float(k) / float(tiers)) - 0.9 * float(k)
				var wb := lerpf(11.0, 6.0, float(k + 1) / float(tiers)) - 0.9 * float(k)
				out.append(_fill(PackedVector2Array([
					p + Vector2(-wa, t0), p + Vector2(wa, t0),
					p + Vector2(wb, t1), p + Vector2(-wb, t1),
				]), Palette.ORDER_CYAN))
			for k in n_rof * 2:
				var mx := -7.5 + 15.0 * float(k) / float(maxi(n_rof * 2 - 1, 1))
				out.append(_fill(
					Shapes.rect(p + Vector2(mx - 1.6, top - 6.0), Vector2(3.2, 7.0)),
					Palette.ORDER_CYAN
				))
		"prism":
			# 三角＝稜鏡。出力 → 多一個切面；射程 → 拉高；射速 → 從中間裂成兩瓣。
			var poly := Shapes.ngon(p, 11.0, 3 + n_pow, -PI * 0.5)
			var hk := (12.0 + 2.2 * float(n_rng)) / 11.0
			var tall := PackedVector2Array()
			for v: Vector2 in poly:
				tall.append(Vector2(v.x, p.y + (v.y - p.y) * hk))
			out.append(_fill(tall, Palette.ALLOY_STEEL))
			for k in n_rof:
				# 裂縫用背景色切出去——**輪廓真的斷開**，不是在上面畫一條線。
				out.append(_line(PackedVector2Array([
					p + Vector2(-3.0 + 6.0 * float(k), -13.0 * hk),
					p + Vector2(-3.0 + 6.0 * float(k), 8.0 * hk),
				]), Palette.BG_PANEL, 2.0, false))
		"knell":
			# 同心圓＝場。出力 → 圈變成越來越尖的多邊形；射程 → 多一圈往外長。
			var rings := 2 + n_rng
			var sides := 24 if n_pow == 0 else maxi(5, 11 - 2 * n_pow)
			for k in rings:
				var r := lerpf(5.0, 13.0, float(k) / float(maxi(rings - 1, 1)))
				out.append(_line(
					_closed(Shapes.ngon(p, r, sides, -PI * 0.5)), Palette.ORDER_CYAN, 2.0, true
				))
			out.append(_flat(Shapes.ngon(p, 2.5, 12), Palette.ORDER_BRIGHT))
		"reclaimer":
			# 空心方 ＋ 內圓。出力 → 外框多一邊；射程／射速 → 內圓長大。
			if lv == 0:
				out.append(_line(
					_closed(Shapes.rect(p - Vector2(10.0, 10.0), Vector2(20.0, 20.0))),
					Palette.ORDER_CYAN, 2.0, true
				))
			else:
				out.append(_line(
					_closed(Shapes.ngon(p, 13.5, 4 + n_pow, PI * 0.25 if n_pow == 0 else 0.0)),
					Palette.ORDER_CYAN, 2.0, true
				))
			out.append(_fill(
				Shapes.ngon(p, 6.0 + 1.3 * float(n_rng) + 0.9 * float(n_rof), CIRCLE_SIDES),
				Palette.ORDER_BRIGHT
			))
		"breaker":
			# ★ 四角爆散星＝濺射（B2.4.8）。濺射 → 多一個尖；出力 → 挖得更深；射程 → 更大。
			out.append(_fill(Shapes.star(
				p, 13.0 + 1.2 * float(n_rng), maxf(5.0 - 0.8 * float(n_pow), 2.4), 4 + n_spl
			), Palette.ALLOY_STEEL))
			out.append(_flat(Shapes.ngon(p, 2.6, 8), Palette.ORDER_DIM))
		"longcall":
			# 細長的桅杆，橫桿在**頂端**＝一座瞭望塔（B2.4.6）。
			#   射程 → 更高；射速 → 多一根橫桿；出力 → 桿身更粗。
			var hh := 13.0 + 2.6 * float(n_rng)
			var mw := 3.0 + 0.9 * float(n_pow)
			out.append(_fill(
				Shapes.rect(p - Vector2(mw, hh), Vector2(mw * 2.0, hh + 13.0)), Palette.ORDER_CYAN
			))
			for k in 1 + n_rof:
				var bw := 8.0 - 1.4 * float(k)
				out.append(_fill(
					Shapes.rect(p + Vector2(-bw, -hh + 5.0 * float(k)), Vector2(bw * 2.0, 4.0)),
					Palette.ORDER_CYAN
				))
		"frostreef":
			# 六芒星（穿心線）＝發散，和潮鳴的同心圓同一族但認得出是兩隻。
			#   射程 → 多一條輻條、伸得更長；出力 → 更粗 ＋ 中心軸。
			var spokes := 3 + n_rng
			var w := 2.5 + 0.7 * float(n_pow)
			for k in spokes:
				var arm := Vector2(12.0 + 0.9 * float(n_rng), 0).rotated(PI * float(k) / float(spokes))
				out.append(_line(PackedVector2Array([p - arm, p + arm]), Palette.ALLOY_STEEL, w, true))
			out.append(_fill(
				Shapes.ngon(p, 2.4 + 0.9 * float(n_pow), 12), Palette.ALLOY_STEEL
			))
		"ballast":
			# 倒三角 ＋ 頂桿＝一塊吊著的配重（B2.4.6）。
			#   出力 → 多疊一塊配重；射程 → 吊桿更長；射速 → 多一條吊索。
			var bw2 := 13.0 + 1.6 * float(n_rng)
			out.append(_fill(
				Shapes.rect(p + Vector2(-bw2, -12.0), Vector2(bw2 * 2.0, 4.0)), Palette.ALLOY_STEEL
			))
			for k in n_rof:
				var hx := -6.0 + 12.0 * float(k) / float(maxi(n_rof - 1, 1))
				out.append(_line(PackedVector2Array([
					p + Vector2(hx, -12.0), p + Vector2(hx, -5.0),
				]), Palette.ALLOY_STEEL, 1.8, false))
			for k in 1 + n_pow:
				var t := -5.0 + 3.4 * float(k)
				var hw := 11.0 - 2.8 * float(k)
				out.append(_fill(PackedVector2Array([
					p + Vector2(-hw, t), p + Vector2(hw, t),
					p + Vector2(0.0, t + 17.0 - 3.4 * float(k)),
				]), Palette.ALLOY_STEEL))
		_:
			pass   # 空陣列＝呼叫端標 `_no_glyph`
	return out


# ── 零件的建構子（讓上面那段讀起來是幾何，不是字典）──────────────────────

static func _fill(pts: PackedVector2Array, col: Color) -> Dictionary:
	return {"kind": "fill", "pts": pts, "col": col}


static func _flat(pts: PackedVector2Array, col: Color) -> Dictionary:
	return {"kind": "flat", "pts": pts, "col": col}


static func _line(pts: PackedVector2Array, col: Color, w: float, shadow: bool) -> Dictionary:
	return {"kind": "line", "pts": pts, "col": col, "w": w, "shadow": shadow}


static func _arc(c: Vector2, r: float, col: Color, w: float) -> Dictionary:
	return _arc_span(c, r, 0.0, TAU, col, w)


static func _arc_span(c: Vector2, r: float, a0: float, a1: float, col: Color, w: float) -> Dictionary:
	return {"kind": "arc", "c": c, "r": r, "a0": a0, "a1": a1, "col": col, "w": w}


## 閉合：把第一點補到尾巴。`draw_polyline` 不會自己封口。
static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if not pts.is_empty():
		out.append(pts[0])
	return out


# ── 上色：體積語言（`20_ART_DIRECTION.md` §1.6b）───────────────────────────
#
# 兩趟。**落影全部先畫、塔身全部後畫**：一座塔的影子偏出格線那兩個像素，
# 只准壓在背景與導管上，不准壓在鄰居已經畫好的血條與徽章上。
# 地圖上（`Battle._draw_nodes()`）兩趟跨全部節點；單一圖形（預覽、卡片）
# 用 `paint()` 一次做完。

## 落影：`fill` 與有 `shadow` 的 `line` 往右下偏一筆深色。
static func paint_shadows(ci: CanvasItem, parts: Array) -> void:
	var col := Palette.shadow()
	for part: Dictionary in parts:
		match String(part["kind"]):
			"fill":
				ci.draw_colored_polygon(_shift(part["pts"], Shapes.SHADOW_OFF), col)
			"line":
				if bool(part.get("shadow", false)):
					ci.draw_polyline(_shift(part["pts"], Shapes.SHADOW_OFF), col, float(part["w"]))
			_:
				pass


## 塔身。`fill` ＝ 背光面（全形壓暗）→ 受光面（沿光線切一半，畫本色）→ 輪廓。
## 光線一律以**格心**為軸切（`Shapes.clip_half()` 的原註：凹多邊形要以核為軸）。
static func paint_bodies(ci: CanvasItem, parts: Array, origin: Vector2) -> void:
	for part: Dictionary in parts:
		var col: Color = part["col"]
		match String(part["kind"]):
			"fill":
				var pts: PackedVector2Array = part["pts"]
				if pts.size() < 3:
					continue
				ci.draw_colored_polygon(pts, Palette.shade(col))
				var lit := Shapes.clip_half(pts, origin, Shapes.LIGHT_DIR)
				if lit.size() >= 3:
					ci.draw_colored_polygon(lit, col)
				ci.draw_polyline(_closed(pts), Palette.contour(col), 1.0)
			"flat":
				var fpts: PackedVector2Array = part["pts"]
				if fpts.size() >= 3:
					ci.draw_colored_polygon(fpts, col)
			"line":
				ci.draw_polyline(part["pts"], col, float(part["w"]))
			"arc":
				ci.draw_arc(
					part["c"], float(part["r"]), float(part["a0"]), float(part["a1"]), 32, col,
					float(part["w"])
				)
			_:
				pass


## 兩趟一次做完（單一圖形用）。
static func paint(ci: CanvasItem, parts: Array, origin: Vector2) -> void:
	paint_shadows(ci, parts)
	paint_bodies(ci, parts, origin)


static func _shift(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v: Vector2 in pts:
		out.append(v + by)
	return out


## 這組零件離 `p` 最遠伸到哪（**棋盤距離**，因為格子是方的）。**量的是輪廓**：
## `fill`、`flat`、有落影的 `line`（槽壁、場環、輻條）與弧，線算半個線寬。
## 沒有落影的 `line` 是**畫在面上的細節**（線圈、裂縫、吊索），不算輪廓；
## 落影本身與 1px 輪廓線也不算（前者是底層的一筆、後者是半個像素）。
## `hud_test` 拿它對 `Shapes.body_extent()`。
static func extent(parts: Array, p: Vector2) -> float:
	var far := 0.0
	for part: Dictionary in parts:
		match String(part["kind"]):
			"fill", "flat", "line":
				if String(part["kind"]) == "line" and not bool(part.get("shadow", false)):
					continue
				var pad: float = float(part.get("w", 0.0)) * 0.5
				for v: Vector2 in (part["pts"] as PackedVector2Array):
					far = maxf(far, maxf(absf(v.x - p.x), absf(v.y - p.y)) + pad)
			"arc":
				far = maxf(far, float(part["r"]) + float(part["w"]) * 0.5)
			_:
				pass
	return far


# ── 畫在 UI 裡的兩個小視圖 ───────────────────────────────────────────────

## ★ 一格的角色圖形（名冊卡片、圖鑑）。**走同一支 `build()`**，所以卡片上的
## 那隻和地圖上蓋出來的那隻不可能長得不一樣。
class View extends Control:
	var type: String = ""
	var level: int = 0

	func _init(t: String = "", px: float = 48.0) -> void:
		type = t
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var parts: Array = Glyphs.build_for({"type": type, "level": level}, Vector2.ZERO, 0)
		if parts.is_empty():
			return
		# 一格 32px 放大到這個視圖的短邊；圖形以格心為原點，所以原點擺在正中央。
		var k: float = minf(size.x, size.y) / Shapes.GRID
		draw_set_transform(size * 0.5, 0.0, Vector2(k, k))
		Glyphs.paint(self, parts, Vector2.ZERO)


## ★ 一張關卡的縮圖（戰役卡片）：路徑帶、侵蝕暈、橋、礦點、核心。
## 和主畫面**同一套編碼、不另發明**（§1.8 小地圖的同一條）：紫帶＝路、青塊＝橋、
## 暗青圈＝礦、亮青方＝核心。它答的是「這一關的地形長什麼樣」，不畫波次。
class MapView extends Control:
	const MapsData := preload("res://data/Maps.gd")
	var map: Dictionary = {}

	func _init(m: Dictionary = {}, w: float = 204.0) -> void:
		map = m
		var sz: Vector2i = m.get("size", Vector2i(36, 19))
		custom_minimum_size = Vector2(w, w * float(sz.y) / float(maxi(sz.x, 1)))
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if map.is_empty():
			return
		var sz: Vector2i = map.get("size", Vector2i(36, 19))
		var k: float = size.x / float(maxi(sz.x, 1))
		# ★ 地貌（B3.13）：縮圖的地是主畫面那一種再壓暗三成（卡片本身是 bg.panel），
		#   只畫大件（`detail = 0`）——6px 的格上細線只是噪點。
		draw_rect(Rect2(Vector2.ZERO, size), Terrain.ground(map).darkened(0.3))
		Terrain.paint(self, Terrain.build(map, k, 0))
		var path: Array = MapsData.path_of(map)
		var pset: Dictionary = {}
		for c: Vector2i in path:
			pset[c] = true
		# 侵蝕暈：路徑外一格（和主畫面同一個半徑，`Tide.BLAST`＝1）。
		var halo := Palette.alpha(Palette.TIDE_DEEP, 0.22)
		for c: Vector2i in path:
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var n := c + Vector2i(dx, dy)
					if pset.has(n) or n.x < 0 or n.y < 0 or n.x >= sz.x or n.y >= sz.y:
						continue
					draw_rect(Rect2(Vector2(n) * k, Vector2(k, k)), halo)
		var band := Palette.alpha(Palette.TIDE_DEEP, 0.8)
		for c: Vector2i in path:
			draw_rect(Rect2(Vector2(c) * k, Vector2(k, k)), band)
		for c: Vector2i in map.get("crossings", []):
			draw_rect(Rect2(Vector2(c) * k, Vector2(k, k)), Palette.ORDER_CYAN)
		for c: Vector2i in map.get("ore", []):
			draw_arc((Vector2(c) + Vector2(0.5, 0.5)) * k, k * 0.36, 0.0, TAU, 12, Palette.ORDER_DIM, 1.0)
		var core: Vector2i = map.get("core", Vector2i.ZERO)
		draw_rect(
			Rect2((Vector2(core) + Vector2(0.5, 0.5)) * k - Vector2(k, k) * 0.75, Vector2(k, k) * 1.5),
			Palette.ORDER_BRIGHT
		)
		draw_rect(Rect2(Vector2.ZERO, size), Palette.BORDER_SUBTLE, false, 1.0)
