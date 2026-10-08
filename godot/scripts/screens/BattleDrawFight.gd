class_name BattleDrawFight
extends RefCounted
## 戰鬥層繪圖：敵人、彈丸、碎片、護盾、開打漣漪、受威脅標記。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

const BattleController := preload("res://scripts/game/BattleController.gd")
const Enemies := preload("res://data/Enemies.gd")
const Foes := preload("res://scripts/render/Foes.gd")
const Motion := preload("res://scripts/render/Motion.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Tide := preload("res://scripts/sim/Tide.gd")

## ★ 開打漣漪的壽命（秒，B3.11）。號令音 `wave_start` 有 1.7 秒，漣漪比它短——
## 它只負責「潮從**這裡**進來」那一眼，說完就讓位給敵人本體。
const RIPPLE_SEC := 1.2

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


## 開火線。留 `SHOT_TTL` 個 tick 並隨之淡出——瞬間閃一下的線等於沒畫。
## ★ 四種開火形態（B1.6.3，`20_ART_DIRECTION.md` §1.7）：彈丸＝物理、光束＝能量、
## 濺射環、回收珠。**形態由 `NodeDefs` 既有的機制欄位推導，不新增美術欄位。**
## 琥珀專屬於能量這個**資源**（§1.1 配色紀律），所以能量傷害用形狀（光束）不用
## 顏色講；回收者那顆琥珀珠是唯一的例外，而它是對的：那顆珠真的是能量，正在流回電網。
##
## ★ B3.11 補上開火的**兩端**：砲口一閃（`_shot_muzzle`）與命中一濺（`_shot_impact`）。
##   原本一發彈丸是「憑空出現、憑空消失」——出手與落點都沒有回饋，玩家看得到線，
##   看不到「打到了」。兩者都是 0.2 秒、十來個像素的東西，`reduce` 時不畫（§4.4）。
func draw_shots() -> void:
	var frac := battle.accum / BattleController.TICK
	for sh: Dictionary in battle.s.shots:
		# 沒有 `by` 的一律當錨（`TL_CLICKTEST` 手塞的那一發）。
		var def := NodeDefs.of(String(sh.get("by", "anchor")))
		var a := battle.cam.center(sh["from"])
		# ★ 落點鎖定敵人本體（B3.12，`_shot_anchor()`）。B3.11 吸附到「那一格裡的
		#   敵人」還不夠：彈丸活 3 個 tick，敵人這期間走出那一格就退回了格心。
		var b := _shot_anchor(sh, "target", "prog", "to")
		var t := Motion.progress(BattleController.SHOT_TTL, int(sh["ttl"]), frac)
		var fade := 1.0 - t
		var beam: bool = bool(def.get("pierce", false))
		_shot_muzzle(a, t, beam)
		if beam:
			_shot_beam(a, b, fade)
			continue
		_shot_bolt(a, b, t, fade)
		_shot_impact(b, t)
		# 濺射環只掛在這一發濺射的**第一筆**記錄上（`BattleController`），
		# 所以這裡畫幾次就是幾發，不會被打中的隻數放大。
		if sh.has("splash_at"):
			_shot_splash(
				_shot_anchor(sh, "splash_target", "splash_prog", "splash_at"),
				t, fade, float(def.get("splash", 0.0))
			)
		if float(def.get("reclaim", 0.0)) > 0.0:
			_shot_reclaim(a, b, t)


## 一發的落點（B3.12）。**鎖定敵人本體**：記錄裡有 `target`（敵人 id）就畫在那一隻
## **此刻**的位置——彈丸活 3 個 tick，敵人在這期間會走出原本那一格，退回格心的話
## 彈頭與火花就落在它身後半格到一格（使用者回報「特效跑掉、不往敵人身上打」）。
## 那一隻已經死了就畫在它**被打中時**的位置（`prog`，碎片爆也在那裡）；
## 兩者都沒有（`TL_CLICKTEST` 手塞的那一發）才退回格心。
func _shot_anchor(sh: Dictionary, id_key: String, prog_key: String, cell_key: String) -> Vector2:
	if sh.has(id_key):
		var i: int = battle.enemy_index.get(int(sh[id_key]), -1)
		if i >= 0 and i < battle.s.enemies.size():
			return _enemy_pos(battle.s.enemies[i], i)
	if sh.has(prog_key):
		return _path_px(float(sh[prog_key]))
	return battle.cam.center(sh[cell_key])


## id → `s.enemies` 索引，每幀建一次（B3.12）。彈丸記的是 id（敵人會死、陣列會縮），
## 畫的時候要找得到那一隻此刻在哪。
func index_enemies() -> Dictionary:
	var out: Dictionary = {}
	for i in battle.s.enemies.size():
		out[int((battle.s.enemies[i] as Dictionary)["id"])] = i
	return out


## 砲口閃光：出手那一瞬在塔上開一顆亮青的菱形，半個 `SHOT_TTL` 內收掉。
## 菱形是秩序側的語彙（四個角、對齊軸），和敵人那邊的圓形閃光分得開。
## 光束（稜鏡）多一圈柔光——它的出手是「整條亮起」，源頭要更亮一點才讀得出方向。
func _shot_muzzle(a: Vector2, t: float, beam: bool) -> void:
	if Motion.reduce or t >= 0.5:
		return
	var k := 1.0 - t / 0.5
	if beam:
		battle.draw_circle(a, 4.0 + 4.0 * k, Palette.alpha(Palette.ORDER_BRIGHT, 0.35 * k))
	battle.draw_colored_polygon(
		Shapes.ngon(a, 3.0 + 5.0 * k, 4, 0.0), Palette.alpha(Palette.ORDER_BRIGHT, 0.85 * k)
	)


## 命中火花：彈丸抵達的那一刻在落點炸開一顆四角星，擴張並淡出。
## 起點在 `t = 0.6`——`ease_out_cubic(0.6) ≈ 0.94`，彈頭已經貼到目標。
func _shot_impact(b: Vector2, t: float) -> void:
	if Motion.reduce or t < 0.6:
		return
	var k := (1.0 - t) / 0.4
	var r := 3.0 + 6.0 * (1.0 - k)
	battle.draw_colored_polygon(
		Shapes.star(b, r, r * 0.4, 4, PI * 0.25), Palette.alpha(Palette.ORDER_BRIGHT, 0.9 * k)
	)


## 能量貫穿（稜鏡）：**整條線一次亮到底**，寬度 3→1 衰減。
## 貫穿本來就是「這條軸線上的都被打到」，光束是它唯一誠實的畫法。
## 同一 tick 會有多發（每個目標一發）疊在同一條軸線上——那不是缺陷，
## 疊出來的亮度差正好說明「近的那幾隻被打得比較集中」。
func _shot_beam(a: Vector2, b: Vector2, fade: float) -> void:
	battle.draw_line(a, b, Palette.alpha(Palette.ORDER_BRIGHT, 0.10 + 0.18 * fade), 6.0)
	battle.draw_line(a, b, Palette.alpha(Palette.ORDER_BRIGHT, 0.35 + 0.65 * fade), 1.0 + 2.0 * fade)


## 物理彈丸（錨／回收者／碎浪）：**短促實心的一段沿線飛行**，不是整條線亮起。
## 「有質量的東西飛過去」和「一束光」的差別全在這裡——整條線亮起讀起來
## 永遠是能量，不管畫成什麼顏色。
func _shot_bolt(a: Vector2, b: Vector2, t: float, fade: float) -> void:
	var dir := (b - a)
	var len := dir.length()
	if len < 0.001:
		return
	dir /= len
	# 彈丸長度上限 14px：短程時不可以比整條彈道還長，否則它就變回一條線了。
	var bolt := minf(14.0, len * 0.45)
	var head := a + dir * (bolt + (len - bolt) * Motion.ease_out_cubic(t))
	battle.draw_line(head - dir * bolt, head, Palette.alpha(Palette.ORDER_CYAN, 0.45 + 0.55 * fade), 3.0)


## 濺射（碎浪）：命中點一圈**擴張環**，半徑就是資料裡的 `splash` 格。
## ★ 這個範圍原本玩家**完全看不到**——碎浪比錨貴、吃三座錨的電，
## 而它唯一的賣點（打到一整段隊列）在畫面上沒有任何證據。
func _shot_splash(at: Vector2, t: float, fade: float, splash: float) -> void:
	var r := splash * Shapes.GRID * Motion.ease_out_cubic(t)
	battle.draw_arc(at, r, 0.0, TAU, 28, Palette.alpha(Palette.ORDER_CYAN, 0.15 + 0.45 * fade), 2.0)


## 回收（回收者）：命中後一顆 `energy.amber` 珠**回流到塔**。
## 方向是反的——它送回來的東西才是這座塔存在的理由（§7.4「打破峰值約束
## 的鑰匙」）。走 `t` 的後半段：先看到打中，才看到收回來，因果順序不能反。
func _shot_reclaim(a: Vector2, b: Vector2, t: float) -> void:
	if t < 0.4:
		return
	var k := (t - 0.4) / 0.6
	battle.draw_circle(b.lerp(a, Motion.ease_out_cubic(k)), 3.0, Palette.alpha(Palette.ENERGY_AMBER, 1.0 - k))


## 敵潮屬於**混沌**側（`20_ART_DIRECTION.md` §0）：不規則凸包、不對齊網格、
## 呼吸式脈動。玩家的一切則是正圓正方、嚴格對齊——這個對比就是主題本身。
## ★ B3.12：幾何搬進 `render/Foes.gd`（純函式、全由機制欄位推導；`hud_test` 量它
##   的行進軸 footprint）。這裡只剩**狀態**：受擊亮階、被光環抓住的青圈、血量弧
##   ——三者各答一題、形狀各不相同（§4.3b）。
func draw_enemies() -> void:
	var now := _time_s()
	for i in battle.s.enemies.size():
		var e: Dictionary = battle.s.enemies[i]
		var def := Enemies.of(String(e["type"]))
		var p := _enemy_pos(e, i)
		var r := float(def.get("radius", 9.0))
		# ★ 受擊一閃（B3.11）：這一 tick 有彈落在它身上，本體往亮階推 0.2 秒。
		#   純渲染推導（`_hit_ids`），仍在品紅色相內、不動用橙（§1.7）。
		var hit: bool = battle.hit_ids.has(int(e["id"]))
		var parts: Array = Foes.build(def, int(e["id"]), p, _enemy_dir(e, i), now, hit)
		Foes.paint(battle, parts)
		# ★ 被潮鳴抓住的敵人：輪廓描一圈 `order.cyan`（B1.8）。**標在敵人身上而不是
		#   塔上**——減速作用在它身上，標在這裡因果才讀得出來。
		var slow := 0.0 if i >= battle.auras.size() else (battle.auras[i] as Vector2).x
		if slow > 0.01:
			for rim: PackedVector2Array in Foes.outlines(parts):
				battle.draw_polyline(rim, Palette.alpha(Palette.ORDER_CYAN, 0.35 + 1.4 * slow), 2.0)
		# 血量弧。★ 分母是這一隻的 `max_hp`（無盡曲線 × 難度層乘過的），不是表上的原值
		#   ——原本讀表值，第 10 波之後血 2.5 倍的敵人要掉到表值以下才開始有弧。
		var frac := float(e["hp"]) / maxf(1.0, float(e.get("max_hp", def.get("hp", 1.0))))
		if frac < 1.0:
			battle.draw_arc(p, r + 4.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 20, Palette.TIDE_DEEP, 2.0)


## 這一 tick 被打中的敵人（B3.11，B3.12 改成以 **id** 為鍵）：剛生出來（`ttl` 還滿
## 或剛減一格）的那幾發的目標。0.2 秒的亮階，和碎片爆一樣是渲染層的事，不進
## `state_hash()`。沒有 `target` 的那一發（`TL_CLICKTEST` 手塞的）退回「那一格裡的第一隻」。
func hit_ids_of() -> Dictionary:
	var out: Dictionary = {}
	for sh: Dictionary in battle.s.shots:
		if int(sh["ttl"]) < BattleController.SHOT_TTL - 1:
			continue
		if sh.has("target"):
			out[int(sh["target"])] = true
			continue
		var i := battle.enemy_cells.find(sh["to"])
		if i >= 0 and i < battle.s.enemies.size():
			out[int((battle.s.enemies[i] as Dictionary)["id"])] = true
	return out


## ★ 開打的漣漪（B3.11）。號令有聲音（`wave_start`）但畫面上沒有對應物：
## 潮從入口湧進來那一刻，在路徑起點放兩圈擴張的品紅環——它答的是「潮從**哪裡**
## 進來」，新玩家的第一個問題（§1.6 來襲箭羽的同一題，這是它的動態版）。
## 零 RNG、由 `phase_time` 驅動；`reduce` 時不畫（§4.4）。只在 wave 的前 1.2 秒存在。
func draw_ripple() -> void:
	if Motion.reduce or battle.s.phase != "wave" or battle.s.path.is_empty():
		return
	var age: float = float(battle.s.phase_time) + battle.accum
	if age > RIPPLE_SEC:
		return
	var at := battle.cam.center(battle.s.path[0])
	for lag: float in [0.0, 0.25]:
		var k := clampf((age - lag) / (RIPPLE_SEC - lag), 0.0, 1.0)
		if k <= 0.0:
			continue
		var e := Motion.ease_out_cubic(k)
		battle.draw_arc(
			at, 6.0 + 46.0 * e, 0.0, TAU, 32,
			Palette.alpha(Palette.TIDE_MAGENTA, (1.0 - k) * 0.7), 3.0 - 1.5 * k
		)


## ★ 「正在被啃」的格（B1.6，§4.3「一定要動」清單）。
##
## 敵人 walk-by 每 tick 傷害相鄰 1 格（`Tide.BLAST`），但在畫面上**那一刻完全
## 沒有表現**——節點的血條會慢慢變短，而玩家不知道「現在」有東西在被吃。
## 這裡把模擬層每 tick 都在做的同一份判定畫出來，不新增任何狀態。
func threat_cells(cells: Array) -> Dictionary:
	var out: Dictionary = {}
	for c: Vector2i in cells:
		for dx in range(-Tide.BLAST, Tide.BLAST + 1):
			for dy in range(-Tide.BLAST, Tide.BLAST + 1):
				out[c + Vector2i(dx, dy)] = true
	return out


## 正在被啃的節點：脈動的**四角括號**。
##
## ★ **形狀必須和「交戰中」的圓環分得開**（第一版就是圓環，截圖當場抓到——
## 交戰環是琥珀圓環、受擊環是橙色圓環，兩個疊在同一顆 12px 的節點上肉眼
## 分不出來）。這是這個專案第二次踩同一個坑：B0.6 的「血條不是圓環」也是
## 因為儲槽充能弧與血條弧撞在一起。**同一個位置上的兩個訊息，換顏色不夠，
## 要換形狀。**
func draw_threat(cell: Vector2i, p: Vector2) -> void:
	if not battle.threat.has(cell):
		return
	var a := Motion.pulse01(battle.s.tick_count, Motion.BASE * 2.0, 0.3)
	var col := Palette.alpha(Palette.WARN_ORANGE, a)
	var h := Shapes.GRID * 0.5 - 1.0   # 半格：括號貼著這一格的邊界
	var arm := 6.0
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner := p + Vector2(sx * h, sy * h)
			battle.draw_line(corner, corner - Vector2(sx * arm, 0.0), col, 2.0)
			battle.draw_line(corner, corner - Vector2(0.0, sy * arm), col, 2.0)


## ★ 碎片爆（B1.6）。規格直接來自 `20_ART_DIRECTION.md` §161 的反模式清單：
## **「爆炸不用 200 顆粒子。用 3–5 個幾何碎片＋一次縮放閃光」**。
##
## 碎片的形狀服從核心視覺命題（§0 秩序 vs 混沌）——這不是裝飾選擇：
##   `chaos`（敵人消散）＝**不規則三角碎片**、品紅、往外飛並旋轉
##   `order`（建築破裂）＝**正方碎片**、青、往外飛但**不旋轉**（秩序連壞掉都是方的）
## 兩種都配一次縮放閃光環：混沌用實心淡去、秩序用線框擴張。
##
## 零 RNG（`Motion.fragment_dir` 由來源 id 決定方向），所以重播與每日挑戰
## 看到的是同一場爆炸。
## ★ 屏障擋格（B2.1d，使用者指定「類似盾牌隔檔」）。
##
## 畫成**面向來向的一段弧**＋一次白閃：盾牌的語彙是「擋住」，不是「爆開」，
## 所以用弧線而不是圓（圓已經是碎片爆的語彙，兩者不能混）。
## 弧的張角隨減傷比例變大——擋掉四成和擋掉九成看得出差別。
##
## **只在能量傷害被吃掉時出現**，所以它同時回答了「為什麼我打不動」：
## 玩家看到盾就知道換物理傷害的塔（§3.5 的剋制表）。
func draw_shields() -> void:
	var frac := battle.accum / BattleController.TICK
	for sh: Dictionary in battle.s.shields:
		var t := Motion.progress(int(sh["life"]), int(sh["ttl"]), frac)
		var at: Vector2 = (
			Vector2(sh["at"] as Vector2i) * Shapes.GRID
			+ Vector2(Shapes.GRID, Shapes.GRID) * 0.5
		)
		var e := Motion.ease_out_cubic(t)
		# ★ **六邊形的護盾泡**，不是一段弧。
		#   第一版畫成朝 +X 的弧：在 32px 的格子上和敵人自己的輪廓分不開，
		#   而且「朝右」對一隻正在往下走的敵人沒有意義（我手上只有格子，
		#   沒有傷害來向）。改成封閉的六邊形之後**與方向無關**，
		#   而且六邊形是本作既有的「硬」語彙（甲殼就是六邊形，§1.7）。
		var r := Shapes.GRID * (0.62 + 0.22 * e)
		var poly := PackedVector2Array()
		for i in 7:
			var a := TAU * float(i) / 6.0 - PI / 2.0
			poly.append(at + Vector2(cos(a), sin(a)) * r)
		battle.draw_polyline(poly, Palette.alpha(Palette.ORDER_BRIGHT, (1.0 - t) * 0.95), 3.0)
		# 擋掉越多，泡越實：40% 與 90% 看得出差別。
		var fill := clampf(float(sh["frac"]), 0.0, 1.0)
		battle.draw_polyline(poly, Palette.alpha(Palette.ORDER_CYAN, (1.0 - t) * 0.45 * fill), 7.0)
		# 起手一瞬的白閃，讓「就是現在被擋了一下」讀得出來。
		if t < 0.35:
			battle.draw_circle(at, Shapes.GRID * 0.30, Palette.alpha(Palette.ORDER_BRIGHT, (0.35 - t) * 1.6))


func draw_bursts() -> void:
	var frac := battle.accum / BattleController.TICK
	for b: Dictionary in battle.s.bursts:
		var life := int(b["life"])
		var t := Motion.progress(life, int(b["ttl"]), frac)
		# 玩家操作之外的系統事件，用 ease-out：一開始炸得快，尾巴慢慢淡（§4.2）。
		var e := Motion.ease_out_cubic(t)
		var at: Vector2 = (b["at"] as Vector2) * Shapes.GRID + Vector2(Shapes.GRID, Shapes.GRID) * 0.5
		var chaos: bool = String(b["kind"]) == "chaos"
		var col := Palette.TIDE_MAGENTA if chaos else Palette.ORDER_CYAN
		var seed_id := int(b["seed"])

		# ── 一次縮放閃光 ──────────────────────────────────────────────
		var flash := Palette.alpha(col, (1.0 - t) * (0.55 if chaos else 0.75))
		if chaos:
			battle.draw_circle(at, 6.0 + 14.0 * e, flash)
		else:
			battle.draw_arc(at, 4.0 + 18.0 * e, 0.0, TAU, 24, flash, 2.0)

		# ── 3–5 個幾何碎片 ────────────────────────────────────────────
		# 數量也由 id 決定（3/4/5 輪替），免得每一次爆炸的顆數都一樣。
		# ★ **數量不動**（§2 反模式清單擋著「200 顆粒子」），動的是**單片的尺寸、
		#   初速與明度**——§7.3 C-2：「3–5 個看不見的碎片等於沒做」。
		#   fit 倍率下一格只有 32px，原本 4–5px 的碎片是三個像素的事。
		var count := 3 + (absi(seed_id) % 3)
		for i in count:
			var dir := Motion.fragment_dir(seed_id, i, count)
			var p := at + dir * (10.0 + 34.0 * e)
			var r := (8.0 if chaos else 6.5) * (1.0 - 0.6 * t)
			# 生命前 30% 用亮階起亮再落回本色。**明度差在小尺寸下活得下來**——
			# 這正是 `tide.bright` 當初被建立的理由（§1.7），同一條經驗直接套用。
			var bright: Color = Palette.TIDE_BRIGHT if chaos else Palette.ORDER_BRIGHT
			var c := Palette.alpha(bright.lerp(col, minf(1.0, t / 0.3)), 1.0 - t)
			if chaos:
				# 不規則三角＋自轉：混沌連碎片都不對齊。
				var spin := float(seed_id) * 0.7 + t * 3.0
				battle.draw_colored_polygon(PackedVector2Array([
					p + Vector2(r * 1.4, 0).rotated(spin),
					p + Vector2(r, 0).rotated(spin + 2.3),
					p + Vector2(r * 0.8, 0).rotated(spin + 4.1),
				]), c)
			else:
				# 正方、不自轉：秩序的碎片仍然是軸對齊的方塊。
				battle.draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), c)


## 敵人**此刻**的畫面位置（B3.12）。兩件事在這裡：
##   ① **置中於它的格**（`Tide.pos_of()`）：模擬用 `floor(progress)` 當格，原本的畫法
##      從格心往下一格插值——一隻 progress 3.9 的敵人畫在第 4 格正中央，而模擬、
##      射程判定、交戰括號都說它在第 3 格。塔看起來在打射程外的東西。
##   ② **tick 內外推**：模擬 10Hz、畫面 60Hz。原本敵人每 0.1 秒跳一次——§2.4 說的
##      「插值呈現」在敵人身上從來沒有實作（導管粗細有、敵人沒有）。用這一隻本 tick
##      的有效速度往前推 `_accum` 秒：`Tide.advance()` 就是這條線性式，所以到下一
##      tick 正好接上。夾在路徑終點（和模擬一樣不會衝過核心）；`TL_SHOT` 凍結時
##      `_accum` 恆為 0，同參數仍拍出同一張圖。
func _enemy_pos(e: Dictionary, i: int) -> Vector2:
	return _path_px(_enemy_prog(e, i))


## 這一隻此刻的 progress（外推過的）。減速讀本幀的 `_auras`，迅捷免疫（同模擬層）。
func _enemy_prog(e: Dictionary, i: int) -> float:
	var def := Enemies.of(String(e["type"]))
	var slow := 0.0 if i >= battle.auras.size() else (battle.auras[i] as Vector2).x
	if bool(def.get("swift", false)):
		slow = 0.0
	var ahead := float(def.get("speed", 1.0)) * (1.0 - slow) * minf(battle.accum, BattleController.TICK)
	return minf(float(e["progress"]) + ahead, float(battle.s.path.size() - 1))


## 路徑上的連續位置 → 地圖 px。
func _path_px(prog: float) -> Vector2:
	return Tide.pos_of(battle.s.path, prog) * Shapes.GRID + Vector2(Shapes.GRID, Shapes.GRID) * 0.5


## 行進方向（單位向量），轉角處平滑過渡（`Tide.heading_of()`）。
func _enemy_dir(e: Dictionary, i: int) -> Vector2:
	return Tide.heading_of(battle.s.path, _enemy_prog(e, i))


## tick 秒 ＋ tick 內已過的秒數：波動相位的時間軸（零 RNG，`TL_SHOT` 下凍結）。
func _time_s() -> float:
	return float(battle.s.tick_count) * BattleController.TICK + minf(battle.accum, BattleController.TICK)
