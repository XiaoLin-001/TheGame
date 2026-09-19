class_name Terrain
extends RefCounted
## ★ 地貌（B3.13，`20_ART_DIRECTION.md` §1.6c）：每張圖一種「地」——底色、紋理、裝飾。
##
## ── 三條不變量 ──────────────────────────────────────────────────────
## **① 只落在不承載資訊的格。** 路徑、侵蝕暈（路徑外一格）、礦點、核心與它的八鄰
##    一律不放——那些格上的每一個像素都已經在講一件事（傷害半徑、可採、要守的東西）。
##    裝飾是底噪，底噪壓到訊息就是缺陷。`allowed_cells()` 是唯一的判定，`hud_test`
##    逐件逐點在對。
## **② 靜態、零 RNG。** 所有位置與形狀都是「地圖 id ＋ 格座標」的整數雜湊（`noise()`），
##    同一張圖在任何機器上長一樣；`TL_SHOT` 拍得出同一張。路面不動（§1.6：會動的
##    東西留給敵人本體）。
## **③ 只用底色階與三個地貌 token（岩、苔、殼）。** 不碰品紅／橙／琥珀——那三個是威脅與
##    能量的通道（§1.1）。**沒有例外**：第一版的殼場用 `tide.deep`，截圖上是一地的粉紅點
##    落在真的敵人旁邊，當場改掉。
## **④ 每一件都留在自己的 3×3 之內**：非大件的最遠點 ≤ 半格（不出自己那一格），
##    大件（`_roomy()` 八鄰都可放才准）≤ 1.5 格。`hud_test` 在十二張手作圖與
##    二十張無盡圖上逐點在量——無盡圖是亂數，只量手作圖的話「剛好沒碰到」會是假綠燈。
##
## ── 為什麼不是貼圖 ──────────────────────────────────────────────────
## §6.1 零外部圖檔。紋理是幾何：沙紋是正弦折線、岩礁是多邊形加等高線、熔渣是
## 隨機走的裂縫、苔是一撮圓點、殼是六邊形、流是流線與渦。**都在網格線之下**——
## 玩家的線與塔永遠畫在它上面。
##
## ── 零件（part）───────────────────────────────────────────────────
##   `fill` 實心多邊形　`line` 折線　`disc` 圓　`arc` 圓弧
## 座標是 px（一格 ＝ `px`），所以主畫面（32px）與縮圖（約 6px）走同一支 `build()`。
## `detail = 0` 只出大件（縮圖）；`1` 全部。

const MapsData := preload("res://data/Maps.gd")

## 八種地貌。**地圖資料寫它的 `biome`**（`data/Campaign.gd`、`data/Maps.gd`）；
## 無盡圖由 `MapGen` 用種子挑（那一份清單在 sim 層，render 不回頭依賴它）。
const BIOMES: Array[String] = [
	"shoal", "reef", "slag", "moss", "shell", "current", "riptide", "trench",
]
const DEFAULT := "shoal"


static func biome_of(map: Dictionary) -> String:
	var b := String(map.get("biome", DEFAULT))
	return b if BIOMES.has(b) else DEFAULT


static func ground(map: Dictionary) -> Color:
	return Palette.ground(biome_of(map))


## 整數雜湊 → [0, 1)。純粹是座標與鹽的函式（不變量 ②）。
static func noise(x: int, y: int, salt: int) -> float:
	var h := x * 374761393 + y * 668265263 + salt * 1274126177
	h = (h ^ (h >> 13)) * 1103515245
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0


## 可以放裝飾的格（不變量 ①）。
static func allowed_cells(map: Dictionary) -> Dictionary:
	var size: Vector2i = map.get("size", Vector2i.ZERO)
	var block: Dictionary = {}
	for c: Vector2i in MapsData.path_of(map):
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				block[c + Vector2i(dx, dy)] = true
	for c: Vector2i in map.get("ore", []):
		block[c] = true
	var core: Vector2i = map.get("core", Vector2i.ZERO)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			block[core + Vector2i(dx, dy)] = true
	var out: Dictionary = {}
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if not block.has(c):
				out[c] = true
	return out


static func build(map: Dictionary, px: float, detail: int) -> Array:
	var ctx := {
		"ok": allowed_cells(map),
		"salt": String(map.get("id", "")).hash() & 0xFFFF,
		"size": map.get("size", Vector2i.ZERO),
		"px": px,
		"detail": detail,
	}
	var out: Array = []
	match biome_of(map):
		"reef":
			_reef(out, ctx)
		"slag":
			_slag(out, ctx)
		"moss":
			_moss(out, ctx)
		"shell":
			_shell(out, ctx)
		"current":
			_current(out, ctx, false)
		"riptide":
			_current(out, ctx, true)
		"trench":
			_trench(out, ctx)
		_:
			_shoal(out, ctx)
	return out


static func paint(ci: CanvasItem, parts: Array) -> void:
	for part: Dictionary in parts:
		var col: Color = part["col"]
		match String(part["kind"]):
			"fill":
				var pts: PackedVector2Array = part["pts"]
				if pts.size() >= 3:
					ci.draw_colored_polygon(pts, col)
			"line":
				var lpts: PackedVector2Array = part["pts"]
				if lpts.size() >= 2:
					ci.draw_polyline(lpts, col, float(part["w"]))
			"disc":
				ci.draw_circle(part["c"], float(part["r"]), col)
			"arc":
				ci.draw_arc(
					part["c"], float(part["r"]), float(part["a0"]), float(part["a1"]), 20, col,
					float(part["w"])
				)
			_:
				pass


# ── 八種地貌 ─────────────────────────────────────────────────────────

## 淺灘：沙洲（淡一階的圓斑）＋ 橫向的沙紋。
static func _shoal(out: Array, ctx: Dictionary) -> void:
	var px := float(ctx["px"])
	var size: Vector2i = ctx["size"]
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if _n(ctx, c, 1) > 0.91 and _roomy(ctx, c):
				out.append(_fill(
					_blob(ctx, _mid(ctx, c), px * 0.95, 8, 0.18, c, 2),
					Palette.alpha(Palette.BG_RAISED, 0.3)
				))
	if int(ctx["detail"]) < 1:
		return
	var col := Palette.alpha(Palette.BORDER_SUBTLE, 0.6)
	var row := 0
	var y0 := 0.7
	while y0 < float(size.y):
		var pts := PackedVector2Array()
		var xx := 0.0
		while xx <= float(size.x):
			var yy := (
				y0 + 0.16 * sin(xx * 0.9 + float(row) * 1.7)
				+ 0.09 * sin(xx * 0.37 + float(row) * 0.6)
			)
			pts.append(Vector2(xx, yy) * px)
			xx += 0.25
		_walk(out, ctx, pts, col, 1.0)
		row += 1
		y0 += 1.6 + 0.6 * noise(row, 0, int(ctx["salt"]))


## 岩礁：露出地面的岩塊（深色多邊形 ＋ 岩色邊 ＋ 一圈等高線）＋ 碎石。
static func _reef(out: Array, ctx: Dictionary) -> void:
	var px := float(ctx["px"])
	var size: Vector2i = ctx["size"]
	var detail := int(ctx["detail"])
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if not _free(ctx, c):
				continue
			var n1 := _n(ctx, c, 1)
			if n1 > 0.93:
				var big := _roomy(ctx, c)
				# 小岩 0.36 × 1.22（抖動上限）＝ 0.44 格 ≤ 半格：不出自己那一格（不變量 ④）。
				var r := px * (0.9 if big else 0.36) * (0.8 + 0.2 * _n(ctx, c, 3))
				var at := _mid(ctx, c)
				if big:
					at += (Vector2(_n(ctx, c, 4), _n(ctx, c, 5)) - Vector2(0.5, 0.5)) * px * 0.2
				var pts := _blob(ctx, at, r, 7, 0.22, c, 6)
				out.append(_fill(pts, Palette.alpha(Palette.BG_DEEP, 0.8)))
				out.append(_line(_closed(pts), Palette.alpha(Palette.ROCK, 0.75), 1.5))
				if detail >= 1:
					out.append(_line(
						_closed(_scaled(pts, at, 0.58)), Palette.alpha(Palette.ROCK, 0.35), 1.0
					))
			elif n1 > 0.85 and detail >= 1:
				var at2 := _mid(ctx, c) + (Vector2(_n(ctx, c, 7), _n(ctx, c, 8)) - Vector2(0.5, 0.5)) * px * 0.7
				out.append(_disc(at2, px * (0.04 + 0.04 * _n(ctx, c, 9)), Palette.alpha(Palette.ROCK, 0.6)))


## 熔渣：冷卻的渣堆（深色六邊）＋ 隨機走向的裂縫（帶一條分支）。
static func _slag(out: Array, ctx: Dictionary) -> void:
	var px := float(ctx["px"])
	var size: Vector2i = ctx["size"]
	var detail := int(ctx["detail"])
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if not _free(ctx, c):
				continue
			var n1 := _n(ctx, c, 1)
			if n1 > 0.94:
				var pts := _blob(ctx, _mid(ctx, c), px * 0.4, 6, 0.15, c, 2)
				# 縮圖（`detail = 0`）上深色的渣堆壓在深色的地上讀不出來 → 填岩色。
				out.append(_fill(
					pts, Palette.alpha(Palette.ROCK, 0.8) if detail == 0 else Palette.alpha(Palette.BG_DEEP, 0.9)
				))
				out.append(_line(_closed(pts), Palette.alpha(Palette.ROCK, 0.7), 1.0))
			if detail >= 1 and n1 > 0.84:
				var p := _mid(ctx, c) + (Vector2(_n(ctx, c, 5), _n(ctx, c, 6)) - Vector2(0.5, 0.5)) * px * 0.6
				var ang := TAU * _n(ctx, c, 7)
				var pts2 := PackedVector2Array([p])
				var steps := 4 + int(_n(ctx, c, 8) * 4.0)
				for k in steps:
					ang += (_n(ctx, c, 10 + k) - 0.5) * 1.6
					p += Vector2(cos(ang), sin(ang)) * px * (0.3 + 0.4 * _n(ctx, c, 20 + k))
					pts2.append(p)
				_walk(out, ctx, pts2, Palette.alpha(Palette.BG_DEEP, 0.95), 2.0)
				if steps > 5:
					var b := pts2[2]
					var bang := TAU * _n(ctx, c, 30)
					_walk(out, ctx, PackedVector2Array([
						b, b + Vector2(cos(bang), sin(bang)) * px * 0.35,
						b + Vector2(cos(bang + 0.5), sin(bang + 0.5)) * px * 0.6,
					]), Palette.alpha(Palette.BG_DEEP, 0.85), 1.2)


## 苔灘：一片片苔（暗綠的圓斑）＋ 斑上一撮圓點。
static func _moss(out: Array, ctx: Dictionary) -> void:
	var px := float(ctx["px"])
	var size: Vector2i = ctx["size"]
	var detail := int(ctx["detail"])
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if not _free(ctx, c) or _n(ctx, c, 1) <= 0.85:
				continue
			var at := _mid(ctx, c) + (Vector2(_n(ctx, c, 2), _n(ctx, c, 3)) - Vector2(0.5, 0.5)) * px * 0.2
			# 八鄰都可放才長大斑（0.55 × 1.25 ＋ 0.1 ＝ 0.79 格）；否則 0.3 × 1.25 ＋ 0.1
			# ＝ 0.475 格，不出自己那一格（不變量 ④）。
			var r := px * (0.55 if _roomy(ctx, c) else 0.3) * (0.7 + 0.3 * _n(ctx, c, 4))
			out.append(_fill(
				_blob(ctx, at, r, 7, 0.25, c, 5),
				Palette.alpha(Palette.MOSS, 0.32 if detail == 0 else 0.22)
			))
			if detail < 1:
				continue
			var dots := 5 + int(_n(ctx, c, 6) * 4.0)
			for k in dots:
				var q := _mid(ctx, c) + (
					Vector2(_n(ctx, c, 40 + k), _n(ctx, c, 60 + k)) - Vector2(0.5, 0.5)
				) * px * 0.78
				out.append(_disc(q, px * (0.035 + 0.045 * _n(ctx, c, 80 + k)), Palette.alpha(Palette.MOSS, 0.55)))


## 殼場：潮退之後留下的殼——散落的六邊形（空心為主，偶爾填實）與 V 形的碎片。
## 顏色是中性的 `SHELL`（不是 `tide.deep`，見不變量 ③）。
static func _shell(out: Array, ctx: Dictionary) -> void:
	var px := float(ctx["px"])
	var size: Vector2i = ctx["size"]
	var detail := int(ctx["detail"])
	var col := Palette.alpha(Palette.SHELL, 0.7)
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if not _free(ctx, c):
				continue
			var n1 := _n(ctx, c, 1)
			if detail == 0:
				if n1 > 0.88:
					out.append(_fill(_hex(_mid(ctx, c), px * 0.32, TAU * _n(ctx, c, 3)), Palette.SHELL))
				continue
			if n1 <= 0.8:
				continue
			var at := _mid(ctx, c) + (Vector2(_n(ctx, c, 2), _n(ctx, c, 3)) - Vector2(0.5, 0.5)) * px * 0.5
			var r := px * (0.1 + 0.09 * _n(ctx, c, 4))
			var hexp := _hex(at, r, TAU * _n(ctx, c, 5))
			if _n(ctx, c, 6) > 0.65:
				out.append(_fill(hexp, Palette.alpha(Palette.SHELL, 0.3)))
			out.append(_line(_closed(hexp), col, 1.0))
			if n1 > 0.96:
				var v := _mid(ctx, c) + (Vector2(_n(ctx, c, 7), _n(ctx, c, 8)) - Vector2(0.5, 0.5)) * px * 0.5
				var a := TAU * _n(ctx, c, 9)
				out.append(_line(PackedVector2Array([
					v + Vector2(cos(a), sin(a)) * px * 0.16, v,
					v + Vector2(cos(a + 1.2), sin(a + 1.2)) * px * 0.16,
				]), col, 1.0))


## 流域／亂流：流線（橫向的長波）＋ 渦（三段越繞越大的弧）。
## 亂流多一組直向的流線、渦更密、振幅更大——兩張圖的差別在紋理不在顏色。
static func _current(out: Array, ctx: Dictionary, wild: bool) -> void:
	var px := float(ctx["px"])
	var size: Vector2i = ctx["size"]
	var salt := int(ctx["salt"])
	var thr := 0.86 if wild else 0.93
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if not _free(ctx, c) or _n(ctx, c, 1) <= thr:
				continue
			var p := _mid(ctx, c)
			var spin := 1.0 if _n(ctx, c, 2) > 0.5 else -1.0
			var base := TAU * _n(ctx, c, 3)
			for k in 3:
				var a0 := base + spin * float(k) * 1.1
				out.append(_arc(
					p, px * (0.12 + 0.11 * float(k)), a0, a0 + spin * (3.4 + 0.5 * float(k)),
					Palette.alpha(Palette.BORDER_STRONG, 0.5), 1.2
				))
	if int(ctx["detail"]) < 1:
		return
	var col := Palette.alpha(Palette.BORDER_STRONG, 0.32)
	var amp := 0.5 if wild else 0.3
	var row := 0
	var y0 := 0.5
	while y0 < float(size.y):
		var pts := PackedVector2Array()
		var xx := 0.0
		while xx <= float(size.x):
			var yy := (
				y0 + amp * sin(xx * 0.33 + float(row) * 2.1 + float(salt % 7))
				+ amp * 0.5 * sin(xx * 0.9 + float(row) * 0.7)
			)
			pts.append(Vector2(xx, yy) * px)
			xx += 0.25
		_walk(out, ctx, pts, col, 1.0)
		row += 1
		y0 += 1.4 + 0.5 * noise(row, 1, salt)
	if not wild:
		return
	var colm := 0
	var x0 := 1.0
	while x0 < float(size.x):
		var pts := PackedVector2Array()
		var yy2 := 0.0
		while yy2 <= float(size.y):
			var xx2 := x0 + 0.35 * sin(yy2 * 0.5 + float(colm) * 1.3) + 0.15 * sin(yy2 * 1.3)
			pts.append(Vector2(xx2, yy2) * px)
			yy2 += 0.25
		_walk(out, ctx, pts, Palette.alpha(Palette.BORDER_STRONG, 0.22), 1.0)
		colm += 1
		x0 += 3.0 + 1.5 * noise(colm, 2, salt)


## 海溝：**等深線**——幾個深點，各自一圈圈往外的閉合曲線（半徑 1.1 格一階，
## 兩個低頻正弦讓它不是正圓），深點本身一個小十字（製圖上的水深點）。
## 這是八種裡唯一「讀起來像圖紙」的一種，正好接上 §2 的一句話氣質：冷靜的工程製圖。
## 深點彼此至少隔 9 格，免得兩組等深線交叉成一團（真的等深線不交叉）。
static func _trench(out: Array, ctx: Dictionary) -> void:
	var px := float(ctx["px"])
	var size: Vector2i = ctx["size"]
	var salt := int(ctx["salt"])
	var detail := int(ctx["detail"])
	var want := maxi(2, int(float(size.x * size.y) / 170.0))
	var centres: Array[Vector2] = []
	var tries := 0
	while centres.size() < want and tries < want * 12:
		# 深點落在**格心**：十字的兩臂（0.16 格）才留得在那一格裡（不變量 ④），
		# 等深線也以同一點為心——十字與圈對不齊的話 3× 近照一眼就看得出來。
		var q := Vector2(
			floor(1.0 + noise(tries, 0, salt) * float(size.x - 2)) + 0.5,
			floor(1.0 + noise(tries, 1, salt) * float(size.y - 2)) + 0.5
		)
		tries += 1
		var far := true
		for o: Vector2 in centres:
			if o.distance_to(q) < 9.0:
				far = false
		if far:
			centres.append(q)
	var rings := 4 if detail >= 1 else 3
	for i in centres.size():
		var o: Vector2 = centres[i]
		for k in rings:
			var r := 1.1 * float(k + 1)
			var pts := PackedVector2Array()
			var n := 64
			for j in n + 1:
				var a := TAU * float(j) / float(n)
				var rr := r * (
					1.0 + 0.09 * sin(a * 2.0 + float(i) * 1.9 + float(k) * 0.4)
					+ 0.05 * sin(a * 3.0 - float(i) * 0.7)
				)
				pts.append((o + Vector2(cos(a), sin(a)) * rr) * px)
			var a_ring := 0.42 - 0.06 * float(k) if detail >= 1 else 0.7
			_walk(out, ctx, pts, Palette.alpha(Palette.BORDER_STRONG, a_ring), 1.0)
		var oc := Vector2i(int(floor(o.x)), int(floor(o.y)))
		if detail >= 1 and _free(ctx, oc):
			var at := o * px
			var arm := px * 0.16
			out.append(_line(PackedVector2Array([at - Vector2(arm, 0), at + Vector2(arm, 0)]),
				Palette.alpha(Palette.BORDER_STRONG, 0.6), 1.0))
			out.append(_line(PackedVector2Array([at - Vector2(0, arm), at + Vector2(0, arm)]),
				Palette.alpha(Palette.BORDER_STRONG, 0.6), 1.0))


# ── 幾何小工具 ───────────────────────────────────────────────────────

static func _free(ctx: Dictionary, c: Vector2i) -> bool:
	return (ctx["ok"] as Dictionary).has(c)


## 這一格與八個鄰居都可以放：伸出格外的大件才准放。
static func _roomy(ctx: Dictionary, c: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if not _free(ctx, c + Vector2i(dx, dy)):
				return false
	return true


static func _mid(ctx: Dictionary, c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * float(ctx["px"])


static func _n(ctx: Dictionary, c: Vector2i, k: int) -> float:
	return noise(c.x, c.y, int(ctx["salt"]) * 31 + k)


## 半徑逐頂點抖動的多邊形（岩塊、沙洲、苔斑）。
static func _blob(
	ctx: Dictionary, at: Vector2, r: float, sides: int, amp: float, c: Vector2i, k: int
) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rot := TAU * _n(ctx, c, k)
	for i in sides:
		var a := rot + TAU * float(i) / float(sides)
		var rr := r * (1.0 - amp + 2.0 * amp * _n(ctx, c, k * 7 + i))
		pts.append(at + Vector2(cos(a), sin(a)) * rr)
	return pts


static func _hex(at: Vector2, r: float, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := rot + TAU * float(i) / 6.0
		pts.append(at + Vector2(cos(a), sin(a)) * r)
	return pts


static func _scaled(pts: PackedVector2Array, at: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v: Vector2 in pts:
		out.append(at + (v - at) * k)
	return out


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if not pts.is_empty():
		out.append(pts[0])
	return out


## 一條折線只在可放的格上留下：碰到不可放的格就斷開，之後再接一段新的。
## 相鄰兩點如果同時跨了 x 與 y，斜跨的那兩個角格也要可放——否則線會切過暈的角。
static func _walk(out: Array, ctx: Dictionary, pts: PackedVector2Array, col: Color, w: float) -> void:
	var px := float(ctx["px"])
	var run := PackedVector2Array()
	for i in pts.size():
		var p := pts[i]
		var cell := Vector2i(int(floor(p.x / px)), int(floor(p.y / px)))
		var good := _free(ctx, cell)
		if good and not run.is_empty():
			var q := run[run.size() - 1]
			var pc := Vector2i(int(floor(q.x / px)), int(floor(q.y / px)))
			if pc.x != cell.x and pc.y != cell.y:
				good = _free(ctx, Vector2i(pc.x, cell.y)) and _free(ctx, Vector2i(cell.x, pc.y))
		if good:
			run.append(p)
		if not good or i == pts.size() - 1:
			if run.size() >= 2:
				out.append(_line(run, col, w))
			run = PackedVector2Array()


static func _fill(pts: PackedVector2Array, col: Color) -> Dictionary:
	return {"kind": "fill", "pts": pts, "col": col}


static func _line(pts: PackedVector2Array, col: Color, w: float) -> Dictionary:
	return {"kind": "line", "pts": pts, "col": col, "w": w}


static func _disc(c: Vector2, r: float, col: Color) -> Dictionary:
	return {"kind": "disc", "c": c, "r": r, "col": col}


static func _arc(c: Vector2, r: float, a0: float, a1: float, col: Color, w: float) -> Dictionary:
	return {"kind": "arc", "c": c, "r": r, "a0": a0, "a1": a1, "col": col, "w": w}
