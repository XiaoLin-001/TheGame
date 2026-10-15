class_name Models
extends RefCounted
## ★ 3D 造型配方（B4.2）：十四種建築、六種敵人，**各自手作**——多種材質拼起來，不是把 2D 的輪廓擠高。
##
## 使用者（2026-10-15）：「建模做完整一點」「角色配色不要這麼單調，更像是人做出來的」。
##
## ── 配方吃什麼 ──────────────────────────────────────────────────────────
## 和 2D 的 `Glyphs`／`Foes` 吃**同一組輸入**，所以 2D 與 3D 不會各說各話：
##   · 建築：型別 ＋ 級數驅動的**步數**（`Build.step_count()` 的出力／射速／射程／濺射），以及受傷、儲槽充能、核心心跳。
##     出力 → 更厚重（齒數、層數、線圈、邊數）；射速 → 更多管口／橫桿；射程 → 更高更長；濺射 → 更多尖刺。
##   · 敵人：`Enemies.of()` 的**機制欄位**（`armor`／`speed`／`swift`／`regen`／`pack`／`radius`），**沒有以型別名為鍵的 `match`**
##     （`20_ART_DIRECTION.md` §1.7 的統御規則）。第 7 隻敵人拿到什麼欄位，就長出什麼零件。
## 輪廓與 2D 一致的是**佔地**（一座塔留在自己那一格，核心 1.5 格）；`stage3d_test` 逐型別量網格的外接框。
##
## ── 顏色 ──────────────────────────────────────────────────────────────
## 全部取自 `Palette` 的材質色票（`MAT_*`、`GLOW_*`、`FOE_*`），**這個檔案沒有任何色值字面量**。玩家側仍是冷色＋琥珀
## （琥珀＝能量，所以只有發電機的本體、發光槽、儲槽的充能條、熔爐的口用它）；敵人整組在品紅—紫色相帶內，
## 只在這條色相帶裡變明度與飽和度。
##
## ── 座標 ──────────────────────────────────────────────────────────────
## 格為單位，原點＝格中心的地面、y 向上；敵人朝 +X。沒有配方的型別由呼叫端退回 `Extrude.glyph_mesh()`（不會隱形）。

const Build := preload("res://scripts/sim/Build.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")

const E := preload("res://scripts/render/3d/Extrude.gd")

## 每種建築 0 級的高度（格）：**拾取用的方盒高度**，也是 `stage3d_test` 的「每種都有造型」清單。
## 模型本身的最高點不超過它 ＋ 一級一點（`HEIGHT_PER_LEVEL`）。
const HEIGHT := {
	"core": 0.86,
	"extractor": 0.46,
	"generator": 0.56,
	"smelter": 0.66,
	"relay": 0.52,
	"silo": 0.56,
	"anchor": 0.58,
	"prism": 0.66,
	"knell": 0.34,
	"reclaimer": 0.46,
	"breaker": 0.58,
	"longcall": 0.98,
	"frostreef": 0.48,
	"ballast": 0.54,
}
const HEIGHT_PER_LEVEL := 0.03
## 敵人身高（格）：不超過路徑旁一格的建築。
const FOE_HEIGHT := 0.46
## 敵人的最小半徑（格）：2D 裡最小的（苔群 5px、潛涌 6px）靠亮核與輪廓撐得起來，3D 的小東西沒有那些，要大一點才看得見。
const MIN_FOE_RADIUS := 0.24


static func has_recipe(type: String) -> bool:
	return HEIGHT.has(type)


## 一座節點的拾取高度（格）。
static func height_of(type: String, level: int) -> float:
	return float(HEIGHT.get(type, 0.3)) + HEIGHT_PER_LEVEL * float(maxi(level, 0))


## 一筆節點字典 → 網格（讀的欄位與 `Glyphs.build_for()` 相同）。回傳空網格 ＝ 沒有配方。
static func node(n: Dictionary, tick: int) -> ArrayMesh:
	var type := String(n.get("type", ""))
	var lv := int(n.get("level", 0))
	var full := NodeDefs.hp(type)
	var hurt: bool = float(n.get("hp", full)) < full
	var frac := 0.0
	if type == "silo":
		frac = float(n.get("charge", 0.0)) / maxf(1.0, float(NodeDefs.of("silo")["capacity"]))
	return build(
		type, lv,
		Build.step_count(type, lv, Build.STEP_POWER), Build.step_count(type, lv, Build.STEP_ROF),
		Build.step_count(type, lv, Build.STEP_RANGE), Build.step_count(type, lv, Build.STEP_SPLASH),
		hurt, frac, tick
	)


static func build(
	type: String, lv: int, pw: int, rof: int, rng: int, spl: int, hurt: bool, frac: float, tick: int
) -> ArrayMesh:
	var sp := E.Soup.new()
	match type:
		"core":
			_core(sp, hurt, tick)
		"extractor":
			_extractor(sp, lv, pw)
		"generator":
			_generator(sp, pw)
		"smelter":
			_smelter(sp, pw)
		"relay":
			_relay(sp, pw)
		"silo":
			_silo(sp, pw, frac)
		"anchor":
			_anchor(sp, pw, rof, rng)
		"prism":
			_prism(sp, pw, rof, rng)
		"knell":
			_knell(sp, pw, rng)
		"reclaimer":
			_reclaimer(sp, pw, rof, rng)
		"breaker":
			_breaker(sp, pw, rng, spl)
		"longcall":
			_longcall(sp, pw, rof, rng)
		"frostreef":
			_frostreef(sp, pw, rng)
		"ballast":
			_ballast(sp, pw, rof, rng)
		_:
			pass
	return sp.to_mesh()


# ── 建築 ────────────────────────────────────────────────────────────────

## 核心：最大的一塊（1.5 格）。階梯式的台基 ＋ 八角的身 ＋ 頂上浮著發光的水晶、四角的柱燈。
## 受擊時水晶換成 `warn.orange`——核心掉血是這一局唯一不可逆的事。
static func _core(sp: E.Soup, hurt: bool, tick: int) -> void:
	var crystal := Palette.WARN_ORANGE if hurt else Palette.GLOW_CYAN
	var beat := Motion.pulse01(tick, Motion.AMBIENT * 2.0, 0.55)
	E.box(sp, Vector3.ZERO, Vector2(0.73, 0.73), 0.07, Palette.MAT_STEEL_DARK, 0.0, 0.97)
	E.box(sp, Vector3(0, 0.07, 0), Vector2(0.64, 0.64), 0.09, Palette.MAT_IVORY, 0.0, 0.92)
	E.box(sp, Vector3(0, 0.16, 0), Vector2(0.54, 0.54), 0.10, Palette.MAT_NAVY, 0.0, 0.94)
	E.frustum(sp, Vector3(0, 0.26, 0), Vector2(0.44, 0.44), Vector2(0.36, 0.36), 0.22, 8, Palette.MAT_STEEL, TAU / 16.0)
	E.annulus(sp, Vector3(0, 0.48, 0), 0.40, 0.26, 0.05, 8, Palette.MAT_IVORY)
	# 四個角：柱＋發光的頂。
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			E.box(sp, Vector3(0.58 * sx, 0.07, 0.58 * sz), Vector2(0.07, 0.07), 0.30, Palette.MAT_IVORY, 0.0, 0.8)
			E.frustum(sp, Vector3(0.58 * sx, 0.37, 0.58 * sz), Vector2(0.05, 0.05), Vector2(0.0, 0.0), 0.07, 4, Palette.GLOW_CYAN, PI * 0.25, false)
	# 水晶：上下兩個錐（八面體），脈動的亮度。
	var glow := crystal.lerp(Palette.GLOW_CYAN if not hurt else Palette.ENERGY_AMBER, beat * 0.5)
	E.frustum(sp, Vector3(0, 0.53, 0), Vector2(0.17, 0.17), Vector2(0.0, 0.0), 0.31, 4, glow, PI * 0.25, false)
	E.frustum(sp, Vector3(0, 0.47, 0), Vector2(0.0, 0.0), Vector2(0.17, 0.17), 0.06, 4, glow, PI * 0.25, false)


## 採集器：鑽井架。八角底座 ＋ 青色的機殼 ＋ 一圈齒輪（一級一齒）＋ 三腳架 ＋ 發光的鑽頭。
static func _extractor(sp: E.Soup, lv: int, pw: int) -> void:
	E.frustum(sp, Vector3.ZERO, Vector2(0.38, 0.38), Vector2(0.34, 0.34), 0.07, 8, Palette.MAT_STEEL_DARK, TAU / 16.0)
	E.frustum(sp, Vector3(0, 0.07, 0), Vector2(0.31, 0.31), Vector2(0.26, 0.26), 0.15, 8, Palette.ORDER_CYAN, TAU / 16.0)
	# 齒輪：級數越高齒越多。
	var teeth := 5 + pw + lv
	var gear := Shapes.gear(Vector2.ZERO, 0.30 * Shapes.GRID, teeth, 3.0)
	var g := PackedVector2Array()
	for v: Vector2 in gear:
		g.append(v / Shapes.GRID)
	E.poly_prism(sp, Vector3(0, 0, 0), g, 0.22, 0.27, Palette.MAT_STEEL)
	E.annulus(sp, Vector3(0, 0.27, 0), 0.14, 0.09, 0.03, 8, Palette.MAT_COPPER)
	# 三腳架 ＋ 中軸 ＋ 發光的鑽頭。
	for k in 3:
		var a := TAU * float(k) / 3.0 + PI * 0.5
		var base := Vector3(cos(a) * 0.20, 0.27, sin(a) * 0.20)
		E.spike(sp, base, Vector3(-cos(a) * 0.45, 1.0, -sin(a) * 0.45), 0.20, 0.025, Palette.MAT_STEEL_DARK, 4)
	E.frustum(sp, Vector3(0, 0.27, 0), Vector2(0.05, 0.05), Vector2(0.04, 0.04), 0.14, 6, Palette.MAT_IRON)
	E.dome(sp, Vector3(0, 0.41, 0), Vector3(0.06, 0.05, 0.06), Palette.GLOW_CYAN, 2, 6, false)


## 發電機：鑄鐵底座 ＋ 琥珀的機身（能量）＋ 通風柵 ＋ 銅線圈（一級一圈，最多三圈）＋ 避雷針 ＋ 發光的槽。
static func _generator(sp: E.Soup, pw: int) -> void:
	E.box(sp, Vector3.ZERO, Vector2(0.38, 0.34), 0.06, Palette.MAT_IRON)
	E.box(sp, Vector3(0, 0.06, 0), Vector2(0.33, 0.29), 0.22, Palette.ENERGY_AMBER, 0.0, 0.93)
	# 通風柵（朝南）：三條深色的橫槽。
	for k in 3:
		E.box(sp, Vector3(0, 0.10 + 0.055 * float(k), 0.285), Vector2(0.20, 0.012), 0.022, Palette.MAT_IRON, 0.0, 1.0, true, 2)
	# 側面發光的槽。
	E.box(sp, Vector3(0.325, 0.12, 0), Vector2(0.01, 0.13), 0.10, Palette.GLOW_AMBER, 0.0, 1.0, false, 2)
	E.box(sp, Vector3(-0.325, 0.12, 0), Vector2(0.01, 0.13), 0.10, Palette.GLOW_AMBER, 0.0, 1.0, false, 2)
	# 線圈：銅環一圈圈疊上去。
	var coils := clampi(1 + pw, 1, 3)
	for k in coils:
		E.annulus(sp, Vector3(0, 0.28 + 0.06 * float(k), 0), 0.19 - 0.02 * float(k), 0.12, 0.045, 10, Palette.MAT_COPPER)
	E.spike(sp, Vector3(0, 0.28 + 0.06 * float(coils), 0), Vector3.UP, 0.16, 0.022, Palette.MAT_STEEL, 4)
	E.dome(sp, Vector3(0, 0.28 + 0.06 * float(coils) + 0.16, 0), Vector3(0.035, 0.035, 0.035), Palette.GLOW_AMBER, 2, 6, false)


## 熔爐：六角的爐身 ＋ 朝南的爐口（發光）＋ 煙囪（出力高的兩根）＋ 銅箍。
static func _smelter(sp: E.Soup, pw: int) -> void:
	E.frustum(sp, Vector3.ZERO, Vector2(0.38, 0.38), Vector2(0.35, 0.35), 0.09, 6, Palette.MAT_STEEL_DARK)
	E.frustum(sp, Vector3(0, 0.09, 0), Vector2(0.34, 0.34), Vector2(0.27, 0.27), 0.26, 6, Palette.ALLOY_STEEL)
	E.annulus(sp, Vector3(0, 0.20, 0), 0.325, 0.28, 0.035, 6, Palette.MAT_COPPER)
	# 爐口：深色的框 ＋ 發光的芯。
	E.box(sp, Vector3(0, 0.10, 0.27), Vector2(0.11, 0.025), 0.14, Palette.MAT_IRON, 0.0, 1.0, true, 1)
	E.box(sp, Vector3(0, 0.115, 0.30), Vector2(0.07, 0.01), 0.10, Palette.GLOW_AMBER, 0.0, 1.0, false, 2)
	# 煙囪。
	var stacks := 1 + (1 if pw >= 2 else 0)
	for k in stacks:
		var x := 0.12 - 0.20 * float(k)
		E.frustum(sp, Vector3(x, 0.35, -0.08), Vector2(0.075, 0.075), Vector2(0.06, 0.06), 0.28, 8, Palette.MAT_IRON)
		E.annulus(sp, Vector3(x, 0.63, -0.08), 0.075, 0.045, 0.035, 8, Palette.MAT_COPPER)
	E.dome(sp, Vector3(0, 0.35, 0.02), Vector3(0.12, 0.05, 0.12), Palette.MAT_STEEL, 2, 8)


## 中繼：藍黑的柱 ＋ 底座 ＋ 浮著的菱形（青綠，尖端發光）。出力每級多一對側尖。
## 2D 的中繼是 16px 寬的菱形（半格），3D 取同樣的佔地（半寬約 0.25）——小於這個，fit 倍率下就看不見了。
static func _relay(sp: E.Soup, pw: int) -> void:
	E.box(sp, Vector3.ZERO, Vector2(0.27, 0.27), 0.06, Palette.MAT_STEEL_DARK, PI * 0.25, 0.9)
	E.frustum(sp, Vector3(0, 0.06, 0), Vector2(0.13, 0.13), Vector2(0.09, 0.09), 0.16, 6, Palette.MAT_NAVY)
	E.annulus(sp, Vector3(0, 0.15, 0), 0.14, 0.07, 0.03, 6, Palette.MAT_IVORY)
	var r := 0.22
	E.frustum(sp, Vector3(0, 0.22, 0), Vector2(r, r), Vector2(0.0, 0.0), 0.22, 4, Palette.MAT_TEAL, PI * 0.25)
	E.frustum(sp, Vector3(0, 0.12, 0), Vector2(0.0, 0.0), Vector2(r, r), 0.10, 4, Palette.MAT_TEAL_DARK, PI * 0.25)
	E.frustum(sp, Vector3(0, 0.44, 0), Vector2(0.04, 0.04), Vector2(0.0, 0.0), 0.08, 4, Palette.GLOW_CYAN, PI * 0.25, false)
	for k in mini(pw, 4):
		var a := TAU * float(k) / 4.0
		E.spike(sp, Vector3(cos(a) * 0.20, 0.25, sin(a) * 0.20), Vector3(cos(a), 0.3, sin(a)), 0.13, 0.025, Palette.GLOW_CYAN, 3, false)


## 儲槽：陶白的罐身 ＋ 青綠的箍 ＋ 鋼的圓頂 ＋ 一條會隨充能長高的琥珀槽（能量）。出力越高，罐身邊數越少（越粗獷）。
static func _silo(sp: E.Soup, pw: int, frac: float) -> void:
	var sides := maxi(6, 12 - pw)
	E.frustum(sp, Vector3.ZERO, Vector2(0.40, 0.40), Vector2(0.37, 0.37), 0.06, sides, Palette.MAT_STEEL_DARK)
	E.frustum(sp, Vector3(0, 0.06, 0), Vector2(0.35, 0.35), Vector2(0.34, 0.34), 0.30, sides, Palette.MAT_IVORY)
	E.annulus(sp, Vector3(0, 0.12, 0), 0.355, 0.33, 0.035, sides, Palette.MAT_TEAL)
	E.annulus(sp, Vector3(0, 0.28, 0), 0.350, 0.33, 0.035, sides, Palette.MAT_TEAL)
	E.dome(sp, Vector3(0, 0.36, 0), Vector3(0.34, 0.15, 0.34), Palette.MAT_STEEL, 3, sides)
	E.frustum(sp, Vector3(0, 0.50, 0), Vector2(0.03, 0.03), Vector2(0.025, 0.025), 0.06, 6, Palette.MAT_IRON)
	# 充能表：深色的軌 ＋ 琥珀的條。
	E.box(sp, Vector3(0.0, 0.10, 0.355), Vector2(0.035, 0.012), 0.24, Palette.MAT_IRON, 0.0, 1.0, true, 1)
	if frac > 0.0:
		E.box(sp, Vector3(0.0, 0.10, 0.366), Vector2(0.025, 0.008), 0.24 * clampf(frac, 0.0, 1.0), Palette.GLOW_AMBER, 0.0, 1.0, false, 2)


## 錨：打進地裡的樁——**上寬下窄**：一層一層往上張開（出力每級多一層），頂端一塊鑄鐵頂板與一排砲管（射速），射程拉高。
static func _anchor(sp: E.Soup, pw: int, rof: int, rng: int) -> void:
	var tiers := 1 + pw
	var th := 0.22 + 0.03 * float(rng)
	var y := 0.0
	for k in tiers:
		var bottom := 0.12 + 0.035 * float(k)
		var col := Palette.MAT_TEAL if k % 2 == 0 else Palette.MAT_STEEL
		E.frustum(sp, Vector3(0, y, 0), Vector2(bottom, bottom), Vector2(bottom + 0.10, bottom + 0.10), th, 6, col, PI / 6.0)
		E.annulus(sp, Vector3(0, y + th - 0.025, 0), bottom + 0.105, bottom + 0.06, 0.025, 6, Palette.MAT_IRON)
		y += th
	var wide := 0.12 + 0.035 * float(tiers - 1) + 0.10
	E.box(sp, Vector3(0, y, 0), Vector2(wide + 0.06, wide - 0.04), 0.05, Palette.MAT_IRON, 0.0, 0.96)
	E.box(sp, Vector3(0, y + 0.05, 0), Vector2(wide + 0.03, wide - 0.07), 0.02, Palette.ORDER_CYAN, 0.0, 0.96)
	var barrels := 2 + rof * 2
	for k in barrels:
		var x := lerpf(-wide, wide, float(k) / float(maxi(barrels - 1, 1)))
		E.frustum(sp, Vector3(x, y + 0.07, 0), Vector2(0.034, 0.034), Vector2(0.027, 0.027), 0.15, 6, Palette.MAT_COPPER)
		E.frustum(sp, Vector3(x, y + 0.22, 0), Vector2(0.036, 0.036), Vector2(0.036, 0.036), 0.025, 6, Palette.MAT_IRON)


## 稜鏡：一座水晶塔。鋼的底座 ＋ 多邊的水晶柱（出力每級多一個切面）＋ 尖頂（射程拉高）＋ 底下的碎晶；射速＝裂縫。
static func _prism(sp: E.Soup, pw: int, rof: int, rng: int) -> void:
	E.frustum(sp, Vector3.ZERO, Vector2(0.32, 0.32), Vector2(0.28, 0.28), 0.06, 6, Palette.MAT_STEEL_DARK)
	var sides := 3 + pw
	var body := 0.26 + 0.05 * float(rng)
	E.frustum(sp, Vector3(0, 0.06, 0), Vector2(0.23, 0.23), Vector2(0.18, 0.18), body, sides, Palette.ALLOY_STEEL, -PI * 0.5)
	E.frustum(sp, Vector3(0, 0.06 + body, 0), Vector2(0.18, 0.18), Vector2(0.0, 0.0), 0.20 + 0.03 * float(rng), sides, Palette.MAT_IVORY, -PI * 0.5)
	# 裂縫：射速每級一道，深色的薄片穿過水晶。
	for k in rof:
		E.box(sp, Vector3(0, 0.10, 0), Vector2(0.012, 0.25), body * 0.8, Palette.MAT_IRON, TAU * float(k) / float(maxi(rof, 1)) * 0.5, 1.0, true, 1)
	# 碎晶：底座邊上的三片，高矮不一。
	var shards: Array[Vector3] = [Vector3(0.24, 0.10, 0.12), Vector3(-0.22, 0.07, 0.16), Vector3(-0.05, 0.13, -0.26)]
	for k in shards.size():
		var sh: Vector3 = shards[k]
		E.frustum(sp, Vector3(sh.x, 0.06, sh.z), Vector2(0.05, 0.05), Vector2(0.0, 0.0), sh.y + 0.08, 4, Palette.MAT_TEAL, float(k))


## 潮鳴：一圈圈往外擴的階梯（同心的場）＋ 中央的鐘（陶白）與發光的尖。圈數＝射程，出力高則圈變成多邊形。
static func _knell(sp: E.Soup, pw: int, rng: int) -> void:
	var rings := 2 + rng
	var sides := 18 if pw == 0 else maxi(5, 11 - 2 * pw)
	for k in rings:
		var r := lerpf(0.40, 0.14, float(k) / float(maxi(rings - 1, 1)) * 0.85)
		var col := Palette.ORDER_CYAN if k % 2 == 0 else Palette.MAT_TEAL_DARK
		E.frustum(sp, Vector3(0, 0.05 * float(k), 0), Vector2(r, r), Vector2(r - 0.03, r - 0.03), 0.05, sides, col, -PI * 0.5)
	var top := 0.05 * float(rings)
	E.dome(sp, Vector3(0, top, 0), Vector3(0.12, 0.11, 0.12), Palette.MAT_IVORY, 3, 8)
	E.frustum(sp, Vector3(0, top + 0.10, 0), Vector2(0.025, 0.025), Vector2(0.0, 0.0), 0.12, 4, Palette.GLOW_CYAN, 0.0, false)


## 回收者：方框架 ＋ 浮在中間的發光球。柱是青綠的、箍是銅；出力讓框多一邊，射程與射速讓球長大。
static func _reclaimer(sp: E.Soup, pw: int, rof: int, rng: int) -> void:
	var posts := 4 + pw
	E.box(sp, Vector3.ZERO, Vector2(0.34, 0.34), 0.05, Palette.MAT_STEEL_DARK, PI * 0.25, 0.92)
	for k in posts:
		var a := TAU * float(k) / float(posts) + PI * 0.25
		E.box(sp, Vector3(cos(a) * 0.27, 0.05, sin(a) * 0.27), Vector2(0.04, 0.04), 0.26, Palette.MAT_TEAL, a, 0.85)
	E.annulus(sp, Vector3(0, 0.29, 0), 0.30, 0.24, 0.035, posts * 2, Palette.MAT_COPPER)
	E.annulus(sp, Vector3(0, 0.10, 0), 0.28, 0.24, 0.025, posts * 2, Palette.MAT_IVORY)
	var r := 0.10 + 0.012 * float(rng) + 0.008 * float(rof)
	E.dome(sp, Vector3(0, 0.20, 0), Vector3(r, r, r), Palette.GLOW_CYAN, 3, 10, false)
	E.dome(sp, Vector3(0, 0.20, 0), Vector3(r, r, r), Palette.GLOW_CYAN, 3, 10, false, true)


## 碎浪：鋼的爆散球（釘頭錘）。中央一顆暗鋼的球，水平一圈尖刺（濺射每級多一根），斜上方四根；射程讓刺更長。
static func _breaker(sp: E.Soup, pw: int, rng: int, spl: int) -> void:
	E.frustum(sp, Vector3.ZERO, Vector2(0.28, 0.28), Vector2(0.22, 0.22), 0.07, 8, Palette.MAT_IRON, TAU / 16.0)
	var core_y := 0.20
	var r := 0.15 + 0.01 * float(pw)
	E.dome(sp, Vector3(0, core_y, 0), Vector3(r, r, r), Palette.MAT_STEEL_DARK, 3, 10)
	E.dome(sp, Vector3(0, core_y, 0), Vector3(r, r, r), Palette.MAT_STEEL_DARK, 3, 10, true, true)
	var spikes := 6 + spl * 2
	var spike_len := 0.26 + 0.02 * float(rng)
	for k in spikes:
		var a := TAU * float(k) / float(spikes)
		E.spike(sp, Vector3(cos(a) * r * 0.8, core_y, sin(a) * r * 0.8), Vector3(cos(a), 0.0, sin(a)), spike_len, 0.045, Palette.ALLOY_STEEL, 4)
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		E.spike(sp, Vector3(cos(a) * r * 0.55, core_y + r * 0.7, sin(a) * r * 0.55), Vector3(cos(a), 1.1, sin(a)), spike_len * 0.9, 0.04, Palette.MAT_IVORY, 4)
	E.spike(sp, Vector3(0, core_y + r * 0.9, 0), Vector3.UP, spike_len * 0.8, 0.045, Palette.GLOW_CYAN, 4, false)


## 長哨：一支桅杆，**橫桿在頂端**＝瞭望塔。桿身（陶白＋青綠的箍）射程越高越長；橫桿（射速每級一根）；頂上的發光燈。
static func _longcall(sp: E.Soup, pw: int, rof: int, rng: int) -> void:
	E.box(sp, Vector3.ZERO, Vector2(0.24, 0.24), 0.07, Palette.MAT_STEEL_DARK, PI * 0.25, 0.9)
	E.frustum(sp, Vector3(0, 0.07, 0), Vector2(0.15, 0.15), Vector2(0.10, 0.10), 0.10, 8, Palette.MAT_IRON)
	var h := 0.55 + 0.10 * float(rng)
	var r0 := 0.075 + 0.008 * float(pw)
	E.frustum(sp, Vector3(0, 0.17, 0), Vector2(r0, r0), Vector2(r0 * 0.6, r0 * 0.6), h, 8, Palette.MAT_IVORY)
	var bands := 3 + rng
	for k in bands:
		var y := 0.17 + h * (float(k) + 0.5) / float(bands)
		var r := lerpf(r0, r0 * 0.6, (y - 0.17) / h) + 0.012
		E.annulus(sp, Vector3(0, y, 0), r, r - 0.025, 0.03, 8, Palette.MAT_TEAL if k % 2 == 0 else Palette.MAT_COPPER)
	var top := 0.17 + h
	for k in 1 + rof:
		var w := 0.19 - 0.035 * float(k)
		E.box(sp, Vector3(0, top - 0.015 - 0.065 * float(k), 0), Vector2(w, 0.02), 0.03, Palette.MAT_TEAL, 0.0, 1.0)
	E.spike(sp, Vector3(0, top, 0), Vector3.UP, 0.12, 0.018, Palette.MAT_STEEL, 4)
	E.dome(sp, Vector3(0, top + 0.12, 0), Vector3(0.035, 0.035, 0.035), Palette.GLOW_CYAN, 2, 6, false)


## 霜礁：冰晶叢。一根最高的中心柱，周圍輻射出的碎冰（射程每級多一根），出力讓晶體更粗。顏色是冰藍到近白。
static func _frostreef(sp: E.Soup, pw: int, rng: int) -> void:
	E.frustum(sp, Vector3.ZERO, Vector2(0.34, 0.34), Vector2(0.26, 0.26), 0.07, 8, Palette.MAT_STEEL_DARK, TAU / 16.0)
	var thick := 0.09 + 0.012 * float(pw)
	E.spike(sp, Vector3(0, 0.06, 0), Vector3.UP, 0.34 + 0.02 * float(rng), thick, Palette.MAT_IVORY, 5)
	var shards := 5 + rng
	for k in shards:
		var a := TAU * float(k) / float(shards) + 0.4
		var tall := 0.26 + 0.09 * (0.5 + 0.5 * sin(float(k) * 2.3))
		var col := Palette.ALLOY_STEEL if k % 2 == 0 else Palette.MAT_TEAL
		E.spike(sp, Vector3(cos(a) * 0.25, 0.06, sin(a) * 0.25), Vector3(cos(a) * 0.45, 1.0, sin(a) * 0.45), tall, thick * 0.85, col, 4)
	E.spike(sp, Vector3(0, 0.06 + 0.34 + 0.02 * float(rng) - 0.04, 0), Vector3.UP, 0.05, 0.02, Palette.GLOW_CYAN, 4, false)


## 定潮：一座吊著配重的門架。鑄鐵的框 ＋ 吊著的配重（出力每級多一塊，鏽色與鋼交替）＋ 吊索（射速每級一條）。
static func _ballast(sp: E.Soup, pw: int, rof: int, rng: int) -> void:
	var h := 0.40 + 0.03 * float(rng)
	E.box(sp, Vector3.ZERO, Vector2(0.36, 0.30), 0.05, Palette.MAT_STEEL_DARK, 0.0, 0.95)
	E.box(sp, Vector3(-0.30, 0.05, 0), Vector2(0.035, 0.035), h, Palette.MAT_IRON, 0.0, 0.8)
	E.box(sp, Vector3(0.30, 0.05, 0), Vector2(0.035, 0.035), h, Palette.MAT_IRON, 0.0, 0.8)
	E.box(sp, Vector3(0, 0.05 + h, 0), Vector2(0.36, 0.04), 0.045, Palette.MAT_IRON)
	E.box(sp, Vector3(0, 0.05 + h + 0.045, 0), Vector2(0.30, 0.02), 0.02, Palette.MAT_TEAL)
	var chains := maxi(rof, 1)
	for k in chains:
		var x := -0.15 + 0.30 * float(k) / float(maxi(chains - 1, 1)) if chains > 1 else 0.0
		E.box(sp, Vector3(x, 0.05 + h - 0.12, 0), Vector2(0.008, 0.008), 0.12, Palette.MAT_COPPER)
	var blocks := 1 + pw
	var y := 0.05 + h - 0.12
	for k in blocks:
		var w := lerpf(0.20, 0.10, float(k) / float(maxi(blocks, 1)))
		var bh := 0.085
		y -= bh
		var col := Palette.MAT_RUST if k % 2 == 0 else Palette.MAT_STEEL
		E.frustum(sp, Vector3(0, y, 0), Vector2(w, w * 0.8), Vector2(w * 0.8, w * 0.65), bh, 4, col, PI * 0.25)


# ── 敵人 ────────────────────────────────────────────────────────────────

## 一種敵人的網格。**由機制欄位推導，沒有以型別名為鍵的 `match`**：`armor` → 殼與骨刺、`swift` → 鏢形與側鰭、
## `speed > SWIFT_SPEED` → 流線型與尾鰭、`regen` → 發光的心與縫線、`pack` → 三瓣、預設 → 柔軟的漂蟲（眼睛與觸足）。
## `variant`（0..3，呼叫端用敵人 id 取）讓同一型的幾隻**長得不完全一樣**：色相在品紅帶內小幅位移、明度略不同。
## 朝 +X；原點在地面。
static func foe(def: Dictionary, variant: int = 0) -> ArrayMesh:
	var sp := E.Soup.new()
	var r := maxf(float(def.get("radius", 9.0)) / Shapes.GRID, MIN_FOE_RADIUS)
	var armored: bool = float(def.get("armor", 0.0)) > 0.0
	var swift: bool = bool(def.get("swift", false))
	var fast: bool = float(def.get("speed", 1.0)) > Foes.SWIFT_SPEED
	var regen: bool = float(def.get("regen", 0.0)) > 0.0
	var pack := int(def.get("pack", 1))
	# 配色（全在品紅—紫帶內）：身、腹、亮部。
	var body := Palette.FOE_CORAL
	var belly := Palette.TIDE_DEEP
	var accent := Palette.FOE_ROSE
	if armored:
		body = Palette.FOE_SHELL
		belly = Palette.TIDE_DEEP
		accent = Palette.FOE_CRIMSON
	elif swift:
		body = Palette.FOE_VIOLET
		belly = Palette.FOE_SHELL
		accent = Palette.FOE_LILAC
	elif fast:
		body = Palette.FOE_CRIMSON
		belly = Palette.FOE_SHELL
		accent = Palette.FOE_ROSE
	elif regen:
		body = Palette.FOE_LILAC
		belly = Palette.FOE_VIOLET
		accent = Palette.FOE_HEART
	elif pack > 1:
		body = Palette.FOE_ROSE
		belly = Palette.TIDE_DEEP
		accent = Palette.FOE_LILAC
	# 變體：色相 ±、明度 ±（整數雜湊，零 RNG）。
	var v := variant % 4
	body = _vary(body, v)
	accent = _vary(accent, v + 1)

	if pack > 1:
		for k in mini(pack, 3):
			var a := TAU * float(k) / float(mini(pack, 3)) + 0.5
			var off := Vector3(cos(a) * r * 0.42, 0.0, sin(a) * r * 0.42)
			_blob(sp, off, r * 0.62, 1.0, 0.85, body, belly, accent, true)
			for s: float in [-1.0, 1.0]:
				E.dome(sp, off + Vector3(r * 0.62 * 0.5, r * 0.62 * 0.5, s * r * 0.62 * 0.3), Vector3(r * 0.07, r * 0.07, r * 0.07), Palette.FOE_EYE, 2, 5, false)
		return sp.to_mesh()

	var len_k := 1.0
	var wid_k := 0.9
	var hgt_k := 0.78
	if swift:
		len_k = 1.3
		wid_k = 0.62
		hgt_k = 0.72
	elif fast:
		len_k = 1.2
		wid_k = 0.66
		hgt_k = 0.74
	elif armored:
		len_k = 1.0
		wid_k = 1.0
		hgt_k = 0.85
	_blob(sp, Vector3.ZERO, r, len_k, wid_k, body, belly, accent, true, hgt_k)

	if armored:
		# 殼：背上三片隆起的甲板（暗李紫）＋ 緋紅的縫 ＋ 一排骨刺。
		for k in 3:
			var x := (float(k) - 1.0) * r * 0.46
			E.dome(sp, Vector3(x, r * hgt_k * 0.55, 0), Vector3(r * 0.30, r * 0.34, r * 0.66), Palette.FOE_SHELL.darkened(0.12), 2, 8, true, false, 1)
			E.box(sp, Vector3(x + r * 0.23, r * hgt_k * 0.50, 0), Vector2(r * 0.02, r * 0.55), r * 0.30, accent, 0.0, 1.0, true, 2)
		for k in 4:
			var x := (float(k) - 1.5) * r * 0.38
			E.spike(sp, Vector3(x, r * hgt_k * 0.92, 0), Vector3(-0.2, 1.0, 0.0), r * 0.34, r * 0.07, Palette.FOE_BONE, 4)
	if swift:
		# 鏢：前端一根尖、兩側的鰭往後掠、尾部發光。
		E.spike(sp, Vector3(r * len_k * 0.7, r * hgt_k * 0.3, 0), Vector3.RIGHT, r * 0.8, r * 0.16, accent, 4)
		for s: float in [-1.0, 1.0]:
			E.spike(sp, Vector3(-r * 0.1, r * hgt_k * 0.35, s * r * wid_k * 0.8), Vector3(-1.0, 0.1, s * 1.3), r * 0.8, r * 0.07, accent, 3)
		E.dome(sp, Vector3(-r * len_k * 0.85, r * hgt_k * 0.35, 0), Vector3(r * 0.14, r * 0.14, r * 0.14), Palette.FOE_HEART, 2, 6, false)
	elif fast:
		# 流線型：尾鰭往後翹、背上一道亮痕。
		E.spike(sp, Vector3(-r * len_k * 0.8, r * hgt_k * 0.25, 0), Vector3(-1.0, 0.7, 0.0), r * 0.7, r * 0.12, Palette.FOE_VIOLET, 3)
		E.box(sp, Vector3(0.0, r * hgt_k * 0.74, 0), Vector2(r * len_k * 0.55, r * 0.07), r * 0.06, accent, 0.0, 0.8, false, 2)
	if regen:
		# 發光的心（背上一顆）＋ 一圈縫線點。
		E.dome(sp, Vector3(0.0, r * hgt_k * 0.62, 0), Vector3(r * 0.34, r * 0.30, r * 0.34), Palette.FOE_HEART, 2, 8, false)
		for k in 6:
			var a := TAU * float(k) / 6.0
			E.dome(sp, Vector3(cos(a) * r * 0.55, r * hgt_k * 0.50, sin(a) * r * 0.55), Vector3(r * 0.07, r * 0.05, r * 0.07), Palette.FOE_BONE, 2, 5, false)
	if not (armored or swift or fast or regen):
		# 柔軟的漂蟲：一圈短短的觸足 ＋ 背上兩顆淺色的斑。
		for k in 7:
			var a := TAU * float(k) / 7.0 + 0.3
			E.spike(sp, Vector3(cos(a) * r * 0.82, 0.02, sin(a) * r * 0.78), Vector3(cos(a), -0.2, sin(a)), r * 0.38, r * 0.09, belly, 3)
		for k in 2:
			E.dome(sp, Vector3(-r * 0.15 + r * 0.3 * float(k), r * hgt_k * 0.72, (float(k) - 0.5) * r * 0.5), Vector3(r * 0.11, r * 0.06, r * 0.11), accent, 2, 6, true)
	# 眼睛（兩顆發光的點，朝前）。
	var ex := r * len_k * 0.55
	var ey := r * hgt_k * 0.58
	for s: float in [-1.0, 1.0]:
		E.dome(sp, Vector3(ex, ey, s * r * wid_k * 0.36), Vector3(r * 0.11, r * 0.11, r * 0.11), Palette.FOE_EYE, 2, 6, false)
	return sp.to_mesh()


## 一只半橢球的身子（`_blob`）：上半是身（受光），下緣一圈暗的腹裙，背上加一圈亮的描邊；`cap_eyes` 預留。
static func _blob(
	sp: E.Soup, off: Vector3, r: float, len_k: float, wid_k: float, body: Color, belly: Color,
	accent: Color, _eyes: bool, hgt_k: float = 0.78
) -> void:
	E.frustum(sp, off, Vector2(r * len_k, r * wid_k), Vector2(r * len_k * 0.97, r * wid_k * 0.97), r * 0.10, 9, belly, 0.0)
	E.dome(sp, off + Vector3(0.0, r * 0.10, 0.0), Vector3(r * len_k * 0.97, r * hgt_k, r * wid_k * 0.97), body, 3, 9)
	# 背上一圈淡淡的亮帶（不發光，只是明度高一階）。
	E.dome(sp, off + Vector3(0.0, r * 0.10 + r * hgt_k * 0.86, 0.0), Vector3(r * len_k * 0.42, r * hgt_k * 0.16, r * wid_k * 0.42), accent.lerp(body, 0.35), 2, 8, true, false, 1)


## 同一型的一隻小幅度變色：色相在品紅帶內位移、明度略不同。
static func _vary(c: Color, k: int) -> Color:
	var j := (k % 4) - 1
	var out := Color.from_hsv(fposmod(c.h + 0.012 * float(j), 1.0), c.s, c.v)
	return out.lightened(0.05 * float(j)) if j >= 0 else out.darkened(0.05 * float(-j))
