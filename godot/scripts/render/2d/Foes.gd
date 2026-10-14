class_name Foes
extends RefCounted
## ★ 敵人的圖形（B3.12）：**幾何是純函式，全部由既有的機制欄位推導。**
##
## ── 為什麼從 `Battle._draw_enemies()` 抽出來 ─────────────────────────
## 和 `Glyphs`（B3.11）同一組理由：同一份幾何要在兩個地方畫（地圖、標題背景），
## 而 `Main._bg_blob()` 已經是抄的一份——抄一份的下場 B3.4 證明過。
## 抽成純函式之後 `hud_test` 才斷言得到 §1.7 那條規則：
## **「敵人的差異化只能用不增加行進軸 footprint 的手段」**——它從叮嚀變成紅燈。
##
## ── 統御規則不變（§1.7）───────────────────────────────────────────
## **沒有以型別名為鍵的 `match`**。六隻各不相同，靠的是六個欄位各對一個部件：
##   預設              9 邊柔性水滴 ＋ 會漂的**核**（`tide.deep` 半透明的圓，在體內晃）
##   `armor > 0`       6 邊硬稜角、波動 ±7%、3px 甲板 ＋ 兩道**縫線**（甲板分成三片）
##   `speed > 1.2`     垂直行進方向壓扁 ×0.55 ＋ 沿行進軸的**亮痕**（原本是一顆圓）
##   `swift`           4 邊的**鏢**（長軸沿行進方向）＋ 菱形亮核 ＋ 兩側的**流痕**
##   `regen > 0`       體內一層會呼吸的**內膜** ＋ 四條把內膜縫到外膜的線
##   `pack > 1`        **一團**：三瓣各自波動的小葉，整團仍在 r 之內
## 所以 M3 的第 7 隻敵人拿到什麼欄位就長出什麼——不必補美術、也不可能說謊。
## 對不到任何欄位的型別（連 `radius` 都沒有）畫成預設的漂蟲樣，**不是空的**：
## 敵人漏畫的症狀是「打不到的東西在啃核心」，比塔漏畫嚴重得多。
##
## ── 混沌側不吃體積語言（§1.6b）──────────────────────────────────────
## 沒有落影、沒有受光面。1px `tide.deep` 輪廓 ＋ 會走的波動就是它的「膜」。
## 全部零件都在品紅色相內：本體 `tide.magenta`、暗階 `tide.deep`、亮階 `tide.bright`。
##
## ── 零件（part）───────────────────────────────────────────────────
##   `fill`  實心多邊形（`body: true` 的是本體，受擊時換成 `Palette.tide_hit()`）
##   `line`  折線（閉合的自己把第一點補在尾巴）
##   `disc`  圓
## 座標一律是**地圖 px**；`dir` 是行進方向的單位向量，所有形狀都相對它生成，
## 所以轉彎時整隻跟著轉（方向本身由 `Tide.heading_of()` 平滑過渡）。
##
## ── 零 RNG ─────────────────────────────────────────────────────────
## 波動與脈動只是 `time_s`（tick 秒）與 `id` 的函式；`reduce` 時相位凍住（§4.4）。

## 「看起來快」的門檻（格／秒）。**值的唯一來源**——`Battle` 與 `Main` 都讀這裡。
const SWIFT_SPEED := 1.2
## 波動振幅：柔性 ±15%、硬殼 ±7%、鏢 ±10%。兩個頻率疊加後最遠約 1.45 倍振幅。
const AMP_SOFT := 0.15
const AMP_HARD := 0.07
const AMP_DART := 0.10
## ★ 行進軸 footprint 的上限：任何零件離中心沿行進軸不得超過 `r × FOOT`。
## 柔性波動最遠 1.2175 r，留一點餘裕；`hud_test` 逐型別逐方向逐時刻在量。
const FOOT := 1.25
## 波動相位前進的速度（每秒弧度）。
const FLOW := 2.6


## 一隻敵人的全部零件。`def` 是 `Enemies.of(type)`；`type` 只拿來當種子的一部分
## （同型的兩隻靠 `id` 錯開）。`time_s` ＝ tick 秒 ＋ tick 內已過的秒數。
static func build(
	def: Dictionary, id: int, p: Vector2, dir: Vector2, time_s: float, hit: bool
) -> Array:
	var r := float(def.get("radius", 9.0))
	var d := dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	var n := Vector2(-d.y, d.x)
	var seed_k := float(id)
	var tick := int(floor(time_s / Motion.TICK))
	var pulse := Motion.pulse(tick, Motion.AMBIENT, 0.12, seed_k)
	var flow := 0.0 if Motion.reduce else time_s * FLOW
	var armored: bool = float(def.get("armor", 0.0)) > 0.0
	var swift: bool = bool(def.get("swift", false))
	var fast: bool = float(def.get("speed", 1.0)) > SWIFT_SPEED
	var regen: bool = float(def.get("regen", 0.0)) > 0.0
	var pack := int(def.get("pack", 1))
	var body_col := Palette.tide_hit() if hit else Palette.TIDE_MAGENTA
	var out: Array = []

	# ── 一團（群體）：三瓣小葉，各自波動。整團的最遠點 0.42 r ＋ 0.62 r × 1.22 ≈ 1.18 r ──
	if pack > 1:
		var lobes := mini(pack, 3)
		for k in lobes:
			var ang := TAU * float(k) / float(lobes) + seed_k * 0.9
			var c := p + (d * cos(ang) + n * sin(ang)) * r * 0.42
			var lobe := _blob(c, r * pulse * 0.62, 7, AMP_SOFT, seed_k + float(k) * 7.3, flow, 0.0, d, n)
			out.append(_fill(lobe, body_col, true))
			out.append(_line(_closed(lobe), Palette.alpha(Palette.TIDE_DEEP, 0.9), 1.0))
			if armored:
				out.append(_line(_closed(lobe), Palette.TIDE_DEEP, 3.0))
		return out

	# ── 本體：邊數、振幅、壓扁全由欄位決定 ──
	var sides := 9
	var amp := AMP_SOFT
	var squash := 0.0
	if armored:
		sides = 6
		amp = AMP_HARD
	if swift:
		sides = 4
		amp = AMP_DART
		squash = 0.5
	elif fast:
		sides = 7
		squash = 0.45
	var pts := _blob(p, r * pulse, sides, amp, seed_k, flow, squash, d, n)
	out.append(_fill(pts, body_col, true))
	# 膜：1px 深邊。16px 的品紅團壓在紫色路徑帶上會糊進帶子裡（B3.11）。
	out.append(_line(_closed(pts), Palette.alpha(Palette.TIDE_DEEP, 0.9), 1.0))

	# ── 甲板 ＋ 縫線（護甲）：同形 3px 鎖邊，兩道平行行進軸的線把它分成三片 ──
	if armored:
		out.append(_line(_closed(pts), Palette.TIDE_DEEP, 3.0))
		var reach := r * pulse * 0.62
		for side_k: float in [-0.36, 0.36]:
			var off := n * (r * pulse * side_k)
			out.append(_line(
				PackedVector2Array([p + off - d * reach, p + off + d * reach]),
				Palette.alpha(Palette.TIDE_DEEP, 0.85), 1.5
			))

	# ── 鏢（免疫減速）：菱形亮核 ＋ 兩側各一道流痕（沿行進軸、貼在體側） ──
	if swift:
		var core := maxf(1.0, r * pulse * 0.45)
		out.append(_line(PackedVector2Array([
			p - d * core * 1.3, p + n * core, p + d * core * 1.3, p - n * core, p - d * core * 1.3,
		]), Palette.TIDE_BRIGHT, 2.0))
		var slide := r * 0.12 * sin(flow * 2.0 + seed_k)
		for side_k: float in [-1.0, 1.0]:
			var off := n * (r * 0.78 * side_k)
			out.append(_line(
				PackedVector2Array([p + off - d * (r * 0.38) + d * slide, p + off + d * (r * 0.12) + d * slide]),
				Palette.alpha(Palette.TIDE_BRIGHT, 0.6), 1.0
			))
	# ── 亮痕（快）：核沿行進軸拉成一道，前端一點更亮 ──
	elif fast:
		var half := r * pulse * 0.55
		out.append(_line(
			PackedVector2Array([p - d * half, p + d * half]), Palette.TIDE_BRIGHT, maxf(1.5, r * 0.3)
		))
		out.append(_disc(p + d * (half * 0.55), maxf(1.0, r * 0.22), Palette.TIDE_BRIGHT))

	# ── 內膜 ＋ 縫線（再生）：體內一層會呼吸的亮線，四條線把它縫到外膜 ──
	if regen:
		var beat := Motion.pulse01(tick, Motion.AMBIENT, 0.0, seed_k)
		var inner := _blob(p, r * pulse * 0.58, sides, amp, seed_k + 2.1, flow * 1.3, squash, d, n)
		out.append(_line(_closed(inner), Palette.alpha(Palette.TIDE_BRIGHT, 0.3 + 0.55 * beat), 2.0))
		var step := maxi(1, sides / 4)
		for j in range(0, sides, step):
			if j >= inner.size() or j >= pts.size():
				break
			out.append(_line(
				PackedVector2Array([inner[j], pts[j]]), Palette.alpha(Palette.TIDE_DEEP, 0.6), 1.0
			))

	# ── 核（預設）：一顆半透明的深色圓在體內漂——「裡面有東西在動」 ──
	if not (armored or fast or regen):
		var drift := (
			d * (r * 0.18 * sin(flow * 0.7 + seed_k))
			+ n * (r * 0.18 * cos(flow * 0.5 + seed_k * 1.3))
		)
		out.append(_disc(p + drift, maxf(1.0, r * pulse * 0.28), Palette.alpha(Palette.TIDE_DEEP, 0.45)))
	return out


## 波動的多邊形：以 `d` 為 0° 的方向生成，所以整隻跟著行進方向轉。
## `squash` 把垂直行進方向那一軸壓扁（footprint 只會變小，§1.7）。
## 值域收在約 ±1.45 amp：再寬就會有頂點塌進去，變成尖角旗子而不是水滴。
static func _blob(
	c: Vector2, r: float, sides: int, amp: float, seed_k: float, flow: float,
	squash: float, d: Vector2, n: Vector2
) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in sides:
		var a := TAU * float(k) / float(sides)
		var wobble := (
			1.0 + amp * sin(seed_k * 3.7 + a * 2.0 + flow)
			+ amp * 0.45 * sin(a * 3.0 - flow * 1.7 + seed_k)
		)
		var rr := r * wobble
		pts.append(c + d * (cos(a) * rr) + n * (sin(a) * rr * (1.0 - squash)))
	return pts


static func _fill(pts: PackedVector2Array, col: Color, body: bool) -> Dictionary:
	return {"kind": "fill", "pts": pts, "col": col, "body": body}


static func _line(pts: PackedVector2Array, col: Color, w: float) -> Dictionary:
	return {"kind": "line", "pts": pts, "col": col, "w": w}


static func _disc(c: Vector2, r: float, col: Color) -> Dictionary:
	return {"kind": "disc", "c": c, "r": r, "col": col}


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if not pts.is_empty():
		out.append(pts[0])
	return out


## 畫出來。沒有兩趟——混沌側沒有落影。
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
			_:
				pass


## 本體的閉合輪廓（一團會有三條）。狀態描邊（減速的青圈）畫在這上面。
static func outlines(parts: Array) -> Array:
	var out: Array = []
	for part: Dictionary in parts:
		if String(part["kind"]) == "fill" and bool(part.get("body", false)):
			out.append(_closed(part["pts"]))
	return out


## 這組零件沿 `axis` 離 `p` 最遠伸到哪（線算半個線寬、圓算半徑）。
## `hud_test` 拿它對 `FOOT × r`：行進軸上不得超出。
static func extent_along(parts: Array, p: Vector2, axis: Vector2) -> float:
	var u := axis.normalized()
	var far := 0.0
	for part: Dictionary in parts:
		match String(part["kind"]):
			"fill":
				for v: Vector2 in (part["pts"] as PackedVector2Array):
					far = maxf(far, absf((v - p).dot(u)))
			"line":
				var hw := float(part["w"]) * 0.5
				for lv: Vector2 in (part["pts"] as PackedVector2Array):
					far = maxf(far, absf((lv - p).dot(u)) + hw)
			"disc":
				far = maxf(far, absf(((part["c"] as Vector2) - p).dot(u)) + float(part["r"]))
			_:
				pass
	return far
