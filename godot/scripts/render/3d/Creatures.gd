class_name Creatures
extends RefCounted
## ★ 敵人的生物造型（B4.5）。
##
## 使用者（2026-10-16）：「敵人模型（可以是魔物化一點，或是怎麼樣都行，就是不要只有這種單調的幾何圖形）」。
## 以前的敵人是一顆半橢球加幾根刺——六種只差在刺的位置。現在每一種是**一隻東西**：有身體的輪廓、四肢、眼睛、會動的部位。
##
## ── 哪一類生物，由機制欄位推導（沒有以型別名為鍵的 `match`，和 `Models.foe_motion()` 同一條路）──────────────
##   armor > 0     螃蟹（`crab`）  ：寬扁的殼、背上三片甲板與骨刺、兩隻大螯、六條腿（三腳架步態）、眼柄。慢而硬。
##   swift         魟（`ray`）     ：菱形的身子、兩片會拍動的翅、頭上兩根角、一條帶倒刺的長尾。免疫減速的那一隻。
##   speed > 1.2   鰻（`eel`）     ：放樣的紡錘身、一道行進波往尾巴傳、背鰭與胸鰭、尾鰭、鰓裡一點亮。快。
##   regen > 0     蝸牛（`snail`） ：低伏的軟身、背上螺旋的殼、殼口露出發光的心、兩根眼柄。
##   pack > 1      蛞蝓（`slugs`） ：一團三隻小蛞蝓（尺蠖式拱背），觸角頂端發亮。擠成一團是它的武器。
##   其餘          水母（`jelly`） ：會收縮的傘、一圈觸手與幾條口腕、傘上的斑。柔軟的漂蟲。
##
## ── 動畫：`FRAMES` 張網格輪流換 ───────────────────────────────────────────────────────────────────
## 腿的步態、觸手的擺動、翅的拍動、身體的波浪——都要**形狀本身在變**，整隻縮放（`Models.foe_pose`）做不到。
## 做法是同一隻預先烤 `FRAMES` 個相位的網格，`Stage3D` 依時間換 `MeshInstance3D.mesh`（換一個指標，不重建）。
## 相位 0 ＝ 靜止的樣子（`reduce_motion` 時永遠用它）。
##
## ── 約束 ──────────────────────────────────────────────────────────────────────────────────────────
##   · 配色一律在品紅—紫的色相帶內（`Palette.FOE_*`、`TIDE_DEEP` 與它們的 lerp／明暗）：敵人專屬色，不用橙、不用青（鎖定的設計）。
##   · 朝 +X；原點在地面；高度不超過 `Models.FOE_HEIGHT`；沿 x 不超出自己的半徑太多（`stage3d_test` 量）。
##   · 一隻不超過約 700 個三角形（壓力場景一次兩百隻）。
##   · 眼睛、心、觸角尖端是**發光**的（`lit = false`），其餘吃烘焙光照。

const E := preload("res://scripts/render/3d/Extrude.gd")

## 一個動作循環烤幾張網格。
const FRAMES := 6

## 造型比資料裡的半徑（`radius`，碰撞與落影用）大多少：一格 32 px，半徑 8–12 px 的生物在預設的全景倍率下只有 16–24 px，
## 四肢與觸手細到看不見；放大 1.3 倍，輪廓才在預設倍率下讀得出是一隻什麼東西。**不影響任何模擬數值**（半徑、射程、判定一律不動）。
const SCALE := 1.3


## 這一隻是哪一類生物——從機制欄位推導。
static func kind_of(def: Dictionary) -> String:
	if float(def.get("armor", 0.0)) > 0.0:
		return "crab"
	if bool(def.get("swift", false)):
		return "ray"
	if float(def.get("speed", 1.0)) > Foes.SWIFT_SPEED:
		return "eel"
	if float(def.get("regen", 0.0)) > 0.0:
		return "snail"
	if int(def.get("pack", 1)) > 1:
		return "slugs"
	return "jelly"


## 把一隻生物畫進 `sp`。`r` ＝ 半徑（格）、`frame` ＝ 動作循環的第幾張（0..FRAMES-1）。
static func build(kind: String, sp: E.Soup, radius: float, body: Color, belly: Color, accent: Color, frame: int) -> void:
	var ph := TAU * float(posmod(frame, FRAMES)) / float(FRAMES)
	var r := radius * SCALE
	match kind:
		"crab":
			_crab(sp, r, body, belly, accent, ph)
		"ray":
			_ray(sp, r, body, belly, accent, ph)
		"eel":
			_eel(sp, r, body, belly, accent, ph)
		"snail":
			_snail(sp, r, body, belly, accent, ph)
		"slugs":
			for k in 3:
				var a := TAU * float(k) / 3.0 + 0.5
				_slug(sp, Vector3(cos(a) * r * 0.50, 0.0, sin(a) * r * 0.50), r * 0.80, body, belly, accent, ph + float(k) * 2.1)
		_:
			_jelly(sp, r, body, belly, accent, ph)


## 兩顆發光的眼睛（朝前、左右對稱）。
static func _eyes(sp: E.Soup, at: Vector3, spread: float, rad: float) -> void:
	for s: float in [-1.0, 1.0]:
		E.dome(sp, at + Vector3(0.0, 0.0, s * spread), Vector3(rad, rad, rad), Palette.FOE_EYE, 2, 6, false)


# ── 水母（漂蟲）──────────────────────────────────────────────────────────

static func _jelly(sp: E.Soup, r: float, body: Color, belly: Color, accent: Color, ph: float) -> void:
	var pump := sin(ph)
	var y0 := 0.72 * r
	var rb := r * (0.95 - 0.07 * pump)
	var hb := r * (0.50 + 0.09 * pump)
	var tent := accent.lerp(body, 0.30)
	# 傘：半橢球 ＋ 一圈亮的邊裙 ＋ 暗的內側。
	E.dome(sp, Vector3(0.0, y0, 0.0), Vector3(rb, hb, rb), body, 4, 10)
	E.frustum(sp, Vector3(0.0, y0 - 0.07 * r, 0.0), Vector2(rb * 1.03, rb * 1.03), Vector2(rb * 0.99, rb * 0.99), 0.07 * r, 10, accent)
	E.dome(sp, Vector3(0.0, y0 - 0.03 * r, 0.0), Vector3(rb * 0.82, r * 0.34, rb * 0.82), belly, 2, 10, true, true)
	# 傘上三點斑。
	for k in 3:
		var a := TAU * float(k) / 3.0 + 0.4
		E.dome(sp, Vector3(cos(a) * rb * 0.42, y0 + hb * 0.80, sin(a) * rb * 0.42), Vector3(r * 0.10, r * 0.05, r * 0.10), accent.lerp(body, 0.2), 2, 6)
	# 外圈觸手：從邊裙垂到傘的**外面**（從上往下看要看得到），往後拖、左右擺（相位逐條錯開）。
	for k in 9:
		var a := TAU * float(k) / 9.0 + 0.2
		var wob := sin(ph + float(k) * 0.9)
		var p0 := Vector3(cos(a) * rb * 0.96, y0 - 0.06 * r, sin(a) * rb * 0.96)
		var p1 := Vector3(cos(a) * rb * 1.10 - 0.95 * r, 0.03 * r, sin(a) * rb * 1.25 + wob * 0.22 * r)
		E.tube(sp, E.curve(p0, p1, Vector3(-0.35 * r, -0.22 * r, wob * 0.26 * r), 5), r * 0.07, r * 0.02, tent, 4)
	# 口腕：四條較粗較長的，從傘心往後拖出傘外（飄帶一樣的尾）。
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.8
		var wob := sin(ph + float(k) * 1.7)
		var p0 := Vector3(cos(a) * rb * 0.20 - 0.1 * r, y0 - 0.04 * r, sin(a) * rb * 0.24)
		var p1 := Vector3(-1.75 * r + cos(a) * rb * 0.10, 0.05 * r, sin(a) * rb * 0.35 + wob * 0.20 * r)
		E.tube(sp, E.curve(p0, p1, Vector3(-0.40 * r, -0.30 * r, wob * 0.28 * r), 6), r * 0.11, r * 0.025, accent.lerp(belly, 0.25), 5)
	# 眼要貼在傘面上（傘面高度隨前後左右而不同），不是埋在傘裡。
	var ex := 0.60
	var ez := 0.30
	var ey := hb * sqrt(maxf(0.0, 1.0 - ex * ex - ez * ez))
	_eyes(sp, Vector3(rb * ex, y0 + ey * 0.95, 0.0), rb * ez, r * 0.12)


# ── 螃蟹（甲殼）──────────────────────────────────────────────────────────

static func _crab(sp: E.Soup, r: float, body: Color, belly: Color, accent: Color, ph: float) -> void:
	var yb := 0.42 * r
	var shell := Palette.FOE_SHELL.darkened(0.12)
	var limb := belly.lerp(body, 0.35)
	# 殼：放樣的寬扁身子（z 向最寬）。
	var spine: Array = [
		Vector3(-0.95 * r, yb, 0.0), Vector3(-0.55 * r, yb + 0.02 * r, 0.0), Vector3(-0.10 * r, yb + 0.05 * r, 0.0),
		Vector3(0.40 * r, yb + 0.04 * r, 0.0), Vector3(0.92 * r, yb - 0.02 * r, 0.0),
	]
	var radii: Array = [
		Vector2(0.30 * r, 0.16 * r), Vector2(0.78 * r, 0.40 * r), Vector2(0.98 * r, 0.50 * r),
		Vector2(0.86 * r, 0.44 * r), Vector2(0.34 * r, 0.20 * r),
	]
	E.loft(sp, spine, radii, 10, body, belly)
	# 背上三片甲板 ＋ 緋紅的縫 ＋ 一排骨刺。
	for k in 3:
		var x := (float(k) - 1.0) * r * 0.46
		E.dome(sp, Vector3(x, yb + 0.22 * r, 0.0), Vector3(r * 0.30, r * 0.30, r * 0.64), shell, 2, 8, true, false, 1)
		E.box(sp, Vector3(x + r * 0.22, yb + 0.20 * r, 0.0), Vector2(r * 0.02, r * 0.50), r * 0.20, accent, 0.0, 1.0, true, 2)
	for k in 4:
		var x := (float(k) - 1.5) * r * 0.38
		E.spike(sp, Vector3(x, yb + 0.46 * r, 0.0), Vector3(-0.2, 1.0, 0.0), r * 0.28, r * 0.07, Palette.FOE_BONE, 4)
	# 眼柄（兩根，頂端發光）。
	for s: float in [-1.0, 1.0]:
		var base := Vector3(0.78 * r, yb + 0.18 * r, s * 0.30 * r)
		var tip := Vector3(0.98 * r, yb + 0.50 * r, s * 0.34 * r)
		E.tube(sp, E.curve(base, tip, Vector3(0.05 * r, 0.0, 0.0), 2), r * 0.05, r * 0.04, limb, 4)
		E.dome(sp, tip + Vector3(0.0, 0.02 * r, 0.0), Vector3(r * 0.10, r * 0.10, r * 0.10), Palette.FOE_EYE, 2, 6, false)
	# 兩隻大螯：臂（肩 → 肘 → 腕）＋ 兩片鉗。
	var claw := Palette.FOE_SHELL.lightened(0.18)
	for s: float in [-1.0, 1.0]:
		var sh := Vector3(0.70 * r, yb - 0.02 * r, s * 0.80 * r)
		var el := Vector3(1.20 * r, yb + 0.04 * r, s * 1.05 * r)
		var tp := Vector3(1.36 * r, yb + 0.02 * r, s * 0.60 * r)
		E.tube(sp, [sh, el, tp], r * 0.11, r * 0.075, claw, 5)
		E.spike(sp, tp, Vector3(1.0, 0.45, -s * 0.25), r * 0.32, r * 0.08, Palette.FOE_BONE, 4)
		E.spike(sp, tp, Vector3(1.0, -0.15, s * 0.35), r * 0.30, r * 0.08, Palette.FOE_BONE, 4)
	# 六條腿：三腳架步態（對角兩組輪流抬起、前後擺）。
	for s: float in [-1.0, 1.0]:
		for i in 3:
			var x := (float(i) - 1.0) * r * 0.48
			var grp := (i + (0 if s > 0.0 else 1)) % 2
			var ang := ph + float(grp) * PI
			var swing := cos(ang) * 0.16 * r
			var lift := maxf(0.0, sin(ang)) * 0.15 * r
			var hip := Vector3(x, yb - 0.04 * r, s * 0.80 * r)
			var knee := Vector3(x + 0.10 * r + swing * 0.4, yb + 0.16 * r + lift * 0.8, s * 1.28 * r)
			var foot := Vector3(x + 0.14 * r + swing, 0.01 + lift, s * 1.52 * r)
			E.tube(sp, [hip, knee, foot], r * 0.07, r * 0.035, limb, 4)


# ── 鰻（熾泳）────────────────────────────────────────────────────────────

static func _eel(sp: E.Soup, r: float, body: Color, belly: Color, accent: Color, ph: float) -> void:
	# 紡錘身：一道行進波從頭傳到尾（振幅往尾巴越來越大）。
	var prof: Array = [
		Vector2(0.16, 0.16), Vector2(0.30, 0.30), Vector2(0.38, 0.40), Vector2(0.38, 0.42),
		Vector2(0.32, 0.36), Vector2(0.22, 0.26), Vector2(0.12, 0.17), Vector2(0.04, 0.08),
	]
	var n := prof.size()
	var spine: Array = []
	var radii: Array = []
	for i in n:
		var t := float(i) / float(n - 1)
		var amp := (0.06 + 0.26 * t * t) * r
		spine.append(Vector3(lerpf(1.25, -1.45, t) * r, 0.44 * r, amp * sin(TAU * t * 0.9 - ph)))
		radii.append((prof[i] as Vector2) * r)
	E.loft(sp, spine, radii, 8, body, belly)
	# 背鰭：沿背脊的一排尖，往後倒。
	for i in range(2, 7):
		var base: Vector3 = (spine[i] as Vector3) + Vector3(0.0, (radii[i] as Vector2).y * 0.9, 0.0)
		E.spike(sp, base, Vector3(-0.5, 1.0, 0.0), r * (0.40 - 0.04 * float(i - 2)), r * 0.06, accent, 3)
	# 胸鰭：兩側各一片往後掠。
	for s: float in [-1.0, 1.0]:
		var pb: Vector3 = (spine[2] as Vector3) + Vector3(0.0, -0.05 * r, s * (radii[2] as Vector2).x * 0.9)
		E.spike(sp, pb, Vector3(-0.6, -0.1 + 0.12 * sin(ph + s), s * 1.0), r * 0.7, r * 0.08, accent, 3)
	# 尾鰭：沿尾端的方向扇出三片。
	var tail: Vector3 = spine[n - 1]
	for dy: float in [0.8, 0.0, -0.6]:
		E.spike(sp, tail, Vector3(-1.0, dy, 0.0), r * 0.55, r * 0.06, accent, 3)
	# 眼（兩側）、鰓裡一點亮（熾泳的「熾」）、下顎的牙。
	var eye_c: Vector3 = (spine[1] as Vector3) + Vector3(0.05 * r, (radii[1] as Vector2).y * 0.30, 0.0)
	_eyes(sp, eye_c, (radii[1] as Vector2).x * 0.85, r * 0.07)
	for s: float in [-1.0, 1.0]:
		var gp: Vector3 = (spine[2] as Vector3) + Vector3(0.10 * r, 0.0, s * (radii[2] as Vector2).x * 0.95)
		E.dome(sp, gp, Vector3(r * 0.05, r * 0.10, r * 0.05), Palette.FOE_HEART, 2, 5, false)
		E.spike(sp, (spine[0] as Vector3) + Vector3(0.0, -0.05 * r, s * 0.10 * r), Vector3(1.0, -0.3, s * 0.25), r * 0.22, r * 0.035, Palette.FOE_BONE, 3)


# ── 魟（潛涌）────────────────────────────────────────────────────────────

static func _ray(sp: E.Soup, r: float, body: Color, belly: Color, accent: Color, ph: float) -> void:
	var yb := 0.50 * r
	var spine: Array = [
		Vector3(0.85 * r, yb, 0.0), Vector3(0.40 * r, yb + 0.03 * r, 0.0), Vector3(0.0, yb + 0.04 * r, 0.0),
		Vector3(-0.40 * r, yb + 0.02 * r, 0.0), Vector3(-0.70 * r, yb, 0.0),
	]
	var radii: Array = [
		Vector2(0.12 * r, 0.07 * r), Vector2(0.34 * r, 0.15 * r), Vector2(0.40 * r, 0.18 * r),
		Vector2(0.26 * r, 0.12 * r), Vector2(0.06 * r, 0.05 * r),
	]
	E.loft(sp, spine, radii, 8, body, belly)
	# 兩片翅：從身側往外掠；翅尖拍得比翅根大（相位沿翅展往後延遲）。
	for s: float in [-1.0, 1.0]:
		var wsp: Array = []
		var wr: Array = []
		for k in 5:
			var t := float(k) / 4.0
			var flap := sin(ph - t * 1.1) * (0.12 + 0.50 * t * t) * r
			wsp.append(Vector3(-0.04 * r - 0.12 * r * float(k), yb - 0.02 * r + flap, s * (0.25 + 0.43 * float(k)) * r))
			wr.append(Vector2(lerpf(0.55, 0.10, t) * r, lerpf(0.07, 0.02, t) * r))
		E.loft(sp, wsp, wr, 6, body, belly.lerp(body, 0.4))
	# 頭上兩根角、兩顆眼。
	for s: float in [-1.0, 1.0]:
		E.spike(sp, Vector3(0.85 * r, yb, s * 0.10 * r), Vector3(1.0, 0.1, s * 0.55), r * 0.35, r * 0.05, accent, 3)
	_eyes(sp, Vector3(0.52 * r, yb + 0.14 * r, 0.0), r * 0.16, r * 0.06)
	# 尾：細長、擺動、末端一根倒刺 ＋ 一點亮。
	var tail: Array = []
	for i in 6:
		tail.append(Vector3(-0.70 * r - 0.25 * r * float(i), yb - 0.015 * r * float(i), sin(ph - float(i) * 0.8) * 0.10 * r * float(i) / 5.0))
	E.tube(sp, tail, r * 0.06, r * 0.012, belly.lerp(body, 0.3), 4)
	var tip: Vector3 = tail[5]
	E.spike(sp, tip, Vector3(-1.0, 0.0, 0.0), r * 0.25, r * 0.04, Palette.FOE_BONE, 3)
	E.dome(sp, tip + Vector3(0.0, 0.0, 0.0), Vector3(r * 0.05, r * 0.05, r * 0.05), Palette.FOE_HEART, 2, 5, false)


# ── 蛞蝓（苔群，一團三隻）──────────────────────────────────────────────

static func _slug(sp: E.Soup, off: Vector3, m: float, body: Color, belly: Color, accent: Color, ph: float) -> void:
	var spine: Array = []
	var radii: Array = []
	var segs := 5
	for i in segs:
		var t := float(i) / float(segs - 1)
		var hump := maxf(0.0, sin(ph - t * 2.4)) * 0.28 * m  # 尺蠖式拱背：一個拱沿身體往後傳
		var rad := lerpf(0.58, 0.14, t * t) * m
		spine.append(off + Vector3(lerpf(0.80, -0.85, t) * m, rad * 0.8 + hump, 0.0))
		radii.append(Vector2(rad * 0.95, rad))
	E.loft(sp, spine, radii, 7, body, belly)
	# 背上三簇苔。
	for i in range(1, 4):
		var base: Vector3 = (spine[i] as Vector3) + Vector3(0.0, (radii[i] as Vector2).y * 0.85, 0.0)
		E.spike(sp, base, Vector3(-0.3, 1.0, 0.0), m * 0.34, m * 0.07, accent, 3)
	# 觸角（頂端發光）與眼。
	var head: Vector3 = spine[0]
	for s: float in [-1.0, 1.0]:
		var base := head + Vector3(0.20 * m, (radii[0] as Vector2).y * 0.65, s * 0.18 * m)
		var tip := base + Vector3(0.34 * m, 0.46 * m, s * 0.12 * m)
		E.tube(sp, [base, tip], m * 0.04, m * 0.025, belly.lerp(accent, 0.3), 4)
		E.dome(sp, tip, Vector3(m * 0.07, m * 0.07, m * 0.07), Palette.FOE_EYE, 2, 5, false)
	_eyes(sp, head + Vector3(0.30 * m, (radii[0] as Vector2).y * 0.20, 0.0), (radii[0] as Vector2).x * 0.78, m * 0.07)


# ── 蝸牛（癒殼）──────────────────────────────────────────────────────────

static func _snail(sp: E.Soup, r: float, body: Color, belly: Color, accent: Color, ph: float) -> void:
	var yb := 0.20 * r
	var soft := belly.lerp(body, 0.35)
	# 軟身：低伏的腳（頭在前）。
	var spine: Array = [
		Vector3(0.95 * r, yb, 0.0), Vector3(0.55 * r, yb + 0.04 * r, 0.0), Vector3(0.0, yb + 0.02 * r, 0.0),
		Vector3(-0.55 * r, yb, 0.0), Vector3(-0.95 * r, yb - 0.02 * r, 0.0),
	]
	var radii: Array = [
		Vector2(0.16 * r, 0.12 * r), Vector2(0.42 * r, 0.18 * r), Vector2(0.52 * r, 0.20 * r),
		Vector2(0.38 * r, 0.14 * r), Vector2(0.08 * r, 0.05 * r),
	]
	E.loft(sp, spine, radii, 8, soft, Palette.TIDE_DEEP)
	# 殼：四個越疊越小、略微錯開的扁圓頂（螺旋）。
	for k in 4:
		var c := Vector3(-0.15 * r - 0.02 * r * float(k), 0.30 * r + 0.20 * r * float(k), 0.07 * r * sin(float(k) * 1.9))
		var rr := (0.64 - 0.14 * float(k)) * r
		E.dome(sp, c, Vector3(rr, rr * 0.55, rr * 0.95), body.lightened(0.05 * float(k % 2)), 3, 9, true, false, 1)
	# 殼口露出發光的心 ＋ 殼緣一圈骨白的點。
	E.dome(sp, Vector3(0.30 * r, 0.46 * r, 0.0), Vector3(r * 0.20, r * 0.20, r * 0.22), Palette.FOE_HEART, 2, 8, false)
	for k in 5:
		var a := PI * (0.55 + 0.9 * float(k) / 4.0)
		E.dome(sp, Vector3(-0.15 * r + cos(a) * r * 0.58, 0.32 * r, sin(a) * r * 0.58), Vector3(r * 0.05, r * 0.04, r * 0.05), Palette.FOE_BONE, 2, 5, false)
	# 兩根眼柄（輕輕擺）。
	for s: float in [-1.0, 1.0]:
		var base := Vector3(0.82 * r, yb + 0.12 * r, s * 0.16 * r)
		var tip := Vector3(1.00 * r, 0.62 * r + 0.04 * r * sin(ph + s), s * 0.20 * r)
		E.tube(sp, E.curve(base, tip, Vector3(0.04 * r, 0.0, s * 0.03 * r), 3), r * 0.05, r * 0.035, soft, 4)
		E.dome(sp, tip + Vector3(0.0, 0.02 * r, 0.0), Vector3(r * 0.08, r * 0.08, r * 0.08), Palette.FOE_EYE, 2, 6, false)
