class_name BattleDrawNetwork
extends RefCounted
## 產線層繪圖：導管、流動珠、節點本體、三態徽章、能量條。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

const BattleController := preload("res://scripts/game/BattleController.gd")
const Build := preload("res://scripts/sim/Build.gd")
const Glyphs := preload("res://scripts/render/Glyphs.gd")
const Motion := preload("res://scripts/render/Motion.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const SessionState := preload("res://scripts/game/SessionState.gd")

## 流動珠（`20_ART_DIRECTION.md` §1.4a）：珠距、每單位流率的行進速度（px/秒）、
## 低於此流率就完全不畫。20/秒的幹線 ＝ 120 px/秒，一格 32px 約走四分之一秒。
const BEAD_GAP := 20.0

const BEAD_SPEED := 6.0

const BEAD_MIN_RATE := 0.05

## ★ 本幀「畫不出圖形」的節點類型（B2.4.6）。`_draw_nodes()` 的 match 每漏一種
## 就往這裡記一筆，`TL_CLICKTEST` 拿它當斷言。**這不是防禦性程式碼，是一支感測器**
## ——漏掉一種的後果是那座塔在地圖上完全隱形（蓋得下去、會開火、會吃電、會被
## 打壞，就是看不見），而十五支測試沒有一支會紅：它們驗數值與流量，沒有一支看畫面。
var no_glyph: Dictionary = {}

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


func draw_conduits() -> void:
	var flows: Dictionary = battle.s.rates["conduit_flow"]
	var sat: Dictionary = battle.s.rates["satisfaction"]
	for c: Dictionary in battle.s.conduits:
		var bonus := float(battle.s.mods["cap_bonus"])
		var cap := Build.conduit_cap(int(c["level"]), bonus)
		var flow := float(flows.get(c["id"], 0.0))
		var to_node: Dictionary = battle.s.node_at(c["b"])
		var starving := (
			not to_node.is_empty() and float(sat.get(to_node["id"], 1.0)) < 0.95 and flow > 0.0
		)
		# 線寬的分母是**全遊戲的最大 cap**，不是這條線自己的——粗細因此在
		# 全圖上可以互相比較，而且加粗一條線之後它會真的變粗（B1.1 使用者回報）。
		var w := Shapes.conduit_width(flow, Build.conduit_cap(Build.CAP_MAX_LEVEL, bonus))
		# 受損：先鋪一圈 warn.orange 光暈。**線被打斷之前要先看得出它在挨打**，
		# 否則產能中斷對玩家來說會是憑空發生的。
		if float(c["hp"]) < 40.0:
			var hurt := 1.0 - float(c["hp"]) / 40.0
			battle.draw_line(
				battle.cam.center(c["a"]), battle.cam.center(c["b"]),
				Palette.alpha(Palette.WARN_ORANGE, 0.25 + 0.55 * hurt), w + 6.0
			)
		battle.draw_line(battle.cam.center(c["a"]), battle.cam.center(c["b"]), Palette.conduit(flow, cap, starving), w)
		# 升級過的幹線在端點加刻度，讓「我升過這條」在無數值下也看得見。
		# **垂直短刻線，不是圓點**：圓點會和流動珠混成同一個東西，而兩者語意相反
		# （固定的線材等級 vs 變動的流量）——`20_ART_DIRECTION.md` §1.4a。
		var pa := battle.cam.center(c["a"])
		var pb := battle.cam.center(c["b"])
		var perp := (pb - pa).normalized().orthogonal()
		# ★ B1.6.1：刻度必須**明確伸出管緣**。原本固定 ±5px，而滿載的管子
		#   本身就有 8px 寬——刻度只比它寬一點點，畫成近白青之後讀起來是
		#   「管子這裡破了一個洞」（使用者回報「有破圖」）。
		#   現在長度跟著線寬走並固定外露 3px，而且貼在起點端而不是線長 12%
		#   那個沒有意義的位置：等級是這條線的屬性，標在接頭上才讀得出來。
		var reach := w * 0.5 + 3.0
		var tick_w := maxf(1.5, 2.0 / maxf(0.2, battle.cam.zoom))
		var step := maxf(3.0, 4.0 / maxf(0.2, battle.cam.zoom))
		# 起點要**閃過節點自己的圖形**：節點最大到半徑 13（碎浪的外框），
		# 貼太近就被畫在它底下看不見（第一版貼 6px，截圖當場抓到）。
		# 短線上再夾一次，免得刻度跑過中點看起來像掛在另一端。
		var span := pa.distance_to(pb)
		var head := minf(17.0, span * 0.32)
		for i in range(int(c["level"])):
			var at := pa + (pb - pa).normalized() * (head + step * float(i))
			battle.draw_line(at - perp * reach, at + perp * reach, Palette.ORDER_BRIGHT, tick_w)
		# ★ 流動珠：礦砂／能量／合金各一列，各自往自己的淨流向跑（§1.4a）。
		var net: Vector3 = (battle.s.rates["conduit_net"] as Dictionary).get(c["id"], Vector3.ZERO)
		# 只有一種資源在跑時**走線的正中央**：多數導管都是這種，
		# 硬要分排會讓珠子懸在細線外面，看起來像掉出來的東西。
		# 三種同時跑的線（熔爐那條）中間讓給合金，礦砂與能量各退一邊。
		# ★ B1.6.1：珠子**一律走中線**，多種資源沿長度錯開相位，不再各佔一排。
		#
		# 原本是垂直偏移 `w * 0.45 + 1.0`，而它沒有夾在管子裡：8px 寬的線上
		# 偏移 4.6 ＋ 珠半徑 2.6 ＋ 光暈 1.2 ＝ 8.4，遠超過半寬 4——**珠子兩側
		# 都掛在管子外面**，看起來像從管子裡漏出來的（使用者回報「有破圖」）。
		#
		# 夾住偏移不是辦法：真的夾進去之後三排珠子會擠成一團更難讀。
		# 改成共用中線、**相位錯開**：白、琥珀、紫依序前進，位置不再承載資訊
		# （那本來也不是它該講的事），顏色照樣分得出是哪一種資源。
		var lanes: Array = []
		for pair: Array in [
			[net.x, Palette.TEXT_PRIMARY], [net.y, Palette.ENERGY_AMBER],
			[net.z, Palette.ALLOY_VIOLET],
		]:
			if absf(float(pair[0])) >= BEAD_MIN_RATE:
				lanes.append(pair)
		# 礦砂珠用 `text.primary`（近白）而不是 `order.bright`：導管本身就是亮青，
		# 亮青珠子在亮青線上只讀得出「這裡有個洞」，讀不出「有東西在跑」。
		# 能量珠的琥珀、合金珠的紫本來就與線色分屬不同色相，維持配色紀律 2。
		for i in lanes.size():
			_draw_beads(
				pa, pb, float(lanes[i][0]), lanes[i][1], w,
				float(i) / float(lanes.size())
			)


## ★ 流動珠（`20_ART_DIRECTION.md` §1.4a）。線寬與顏色說的是「這條線有多滿」，
## 沒有任何元素在說「東西正在動」——一張靜態的粗線看起來是接線圖，不是產線。
##
## **這不是實體物品搬運。** 珠子的位置由已解出的流率 ＋ 經過的模擬秒數推算，
## 模擬層一無所知，珠子不參與任何判定（`10_GDD.md` §3.1 鎖定：流量網路）。
## 一旦它變成有位置有狀態的實體，`O(物品數)` 的效能與確定性負債就回來了。
##
## `amount` 帶號：正＝沿 a→b、負＝反向。速度 ∝ 流率，間距固定。
##
## ponytail: 每顆珠子兩個 `draw_circle` ＝ 每幀約 `導管數 × 線長/20 × 2` 次繪製。
## M0 一屏（13 條導管）約 500 次，無感；`30_TECH_DESIGN.md` §5 的壓力情境
## （2000 條導管）會爆到六位數。到那時改成單一 `draw_multiline` 批繪或
## 用 shader 把相位推進 GPU——**在量到之前不要先做**。
## `lane_phase` 是 0..1 的相位偏移：多種資源在同一條線上時用它錯開，
## 於是白、琥珀、紫依序前進而不是疊在一起（B1.6.1）。
func _draw_beads(
	a: Vector2, b: Vector2, amount: float, col: Color, width: float,
	lane_phase: float = 0.0
) -> void:
	if absf(amount) < BEAD_MIN_RATE:
		return  # 沒在流動的線必須是靜止的——這是「哪裡斷了」最快的讀法
	var span := a.distance_to(b)
	if span < 1.0:
		return
	var u := (b - a) / span
	# 相位用模擬秒數推（tick 數 ＋ 幀內插值），不用系統時間：
	# 渲染可以不確定，但別引入新的亂數源。`TL_SHOT` 下模擬凍結 → 珠子也凍結。
	var t := (float(battle.s.tick_count) + battle.accum / BattleController.TICK) * BattleController.TICK
	# 珠子大小跟著線寬走：這樣它**強化**「線寬＝流量」而不是把線戳成虛線。
	# 固定大小的珠子在 2px 的細線上會蓋掉整條線，粗細那條資訊就沒了（R-3）。
	# ★ 上限收到半寬：珠子不得比管子胖，否則它就是「管子上的腫塊」。
	var r := clampf(width * 0.30, 1.4, width * 0.5)
	# ★ 描邊是**螢幕固定粗細**（B1.6.1）。原本是固定 +1.2 地圖 px：在 r=1.4 的
	#   細線上，光暈佔了直徑的 46%，讀起來是「管子上的洞」而不是「在跑的東西」；
	#   而放大到 300% 時它又變成一圈很粗的黑框。1px 螢幕在任何倍率下都只是描邊。
	var edge := 1.0 / maxf(0.2, battle.cam.zoom)
	var x := fposmod(t * amount * BEAD_SPEED + lane_phase * BEAD_GAP, BEAD_GAP)
	while x < span:
		var p := a + u * x
		# **深色描邊是這個元素能被看見的唯一原因**：導管本身就是亮青，
		# 亮青珠子畫在亮青線上等於沒畫（使用者實看 B0.6 時反映的正是這件事）。
		battle.draw_circle(p, r + edge, Palette.BG_DEEP)
		battle.draw_circle(p, r, col)
		x += BEAD_GAP


func draw_nodes() -> void:
	# ★ B3.11：**兩趟**。落影全部先畫、塔身全部後畫——一座塔的影子偏出格線那兩個
	#   像素只准壓在背景與導管上，不准壓在鄰居已經畫好的血條與徽章上
	#   （`Shapes.SHADOW_OFF` 的原註；`body_extent()` 守的正是那一格）。
	#   幾何每幀建一次（`Glyphs.build_for()`），兩趟共用同一份。
	var rows: Array = []
	for n: Dictionary in battle.s.nodes:
		var at := battle.cam.center(n["cell"])
		var parts: Array = Glyphs.build_for(n, at, battle.s.tick_count)
		if parts.is_empty():
			# 對不到的型別＝隱形的塔。記下來讓 `_glyph_selftest` 變紅（B2.4.6）。
			no_glyph[String(n["type"])] = true
			continue
		rows.append([n, at, Glyphs.scale_for(n), parts])
	for row: Array in rows:
		_scaled(row[1], float(row[2]), true)
		Glyphs.paint_shadows(battle, row[3])
		_scaled(row[1], float(row[2]), false)
	for row: Array in rows:
		var nd: Dictionary = row[0]
		var p: Vector2 = row[1]
		var full := NodeDefs.hp(String(nd["type"]))
		var lv := int(nd.get("level", 0))
		# ★ B3.10：血條也夾在半格內——它畫在塔身下緣，跟著沒有上限的體積通道長
		#   就會落進下面那一格（塔身本身由 `Shapes.fit_scale()` 夾住）。
		var bar_sc := minf(Shapes.level_scale(lv), Shapes.GRID * 0.5 / 15.0)
		if float(nd["hp"]) < full:
			# **血條不是圓環**：儲槽的充能也是琥珀色圓弧，兩個圓弧疊在同一顆
			# 12px 的節點上肉眼分不出來。形狀不同才分得開。
			var frac := clampf(float(nd["hp"]) / full, 0.0, 1.0)
			var bar := Vector2(24.0, 3.0)
			var bar_at := p + Vector2(-bar.x * 0.5, 15.0 * bar_sc)
			battle.draw_rect(Rect2(bar_at, bar), Palette.alpha(Palette.BG_DEEP, 0.8))
			battle.draw_rect(Rect2(bar_at, Vector2(bar.x * frac, bar.y)), Palette.WARN_ORANGE)
		_scaled(p, float(row[2]), true)
		Glyphs.paint_bodies(battle, row[3], p)
		_scaled(p, float(row[2]), false)
		battle.fight.draw_threat(nd["cell"], p)
		_draw_engaged(nd, p)
		# ★ B3.9.3：零件長在塔身周圍而不是頭上那一條帶子，所以缺料徽章（y −16 起）
		#   不必再讓位——它是**地圖上唯一指出瓶頸的元素**。
		_draw_badge(nd, p)


## ★ 「以某一格為中心放大 `sc` 倍」的畫布變換，開／關（B3.9.2a）。
##
## ⚠ **`draw_set_transform()` 是取代，不是疊加**（使用者回報「升級完之後鼠標跟
##   遊戲指定的格子會有 offset，升級的東西會不見」）。B3.9 這裡直接蓋掉了
##   `_draw()` 開頭那一層地圖變換（原點＋縮放），於是①升過級的塔畫到別的地方去，
##   ②還原成**單位矩陣**使那一幀後面畫的每一樣東西都少掉原點與縮放。
##   算式收在 `Shapes.level_xform()`（`hud_test` 釘著），這裡只負責開與關——
##   而**關一定要關回地圖那一層**，不是關回單位矩陣。
##   `sc == 1.0`（0 級、預覽）時兩邊都是空操作。
func _scaled(p: Vector2, sc: float, on: bool) -> void:
	if sc == 1.0:
		return
	if on:
		battle.draw_set_transform_matrix(Shapes.level_xform(battle.cam.map_origin(), battle.cam.zoom, p, sc))
	else:
		battle.draw_set_transform(battle.cam.map_origin(), 0.0, Vector2(battle.cam.zoom, battle.cam.zoom))


## ★ 一座節點**畫成什麼樣子**——只看型別，不看它蓋起來沒有（B3.4）。
##
## 擺放預覽走的是它：十四種節點各有自己的幾何，抄一份的下場是日後加第十五種時
## 只有一邊記得加——而漏掉的那一邊**症狀是隱形而不是報錯**（`_no_glyph` 就是
## 為此而生）。B3.11 起幾何本身在 `Glyphs.build()`（純函式，名冊與標題畫面也用
## 同一份），這裡只剩「建、縮放、上色」三步。
##
## `n` 只需要 `type`；`hp`／`charge`／`level` 缺了就當作滿血、空槽、0 級。
func draw_node_body(n: Dictionary, p: Vector2) -> void:
	var parts: Array = Glyphs.build_for(n, p, battle.s.tick_count)
	if parts.is_empty():
		no_glyph[String(n["type"])] = true
		return
	var sc := Glyphs.scale_for(n)
	_scaled(p, sc, true)
	Glyphs.paint(battle, parts, p)
	_scaled(p, sc, false)


## ★ 交戰指示：**琥珀＝能量**（配色紀律 2）。有環＝這座塔本 tick 正在吃電。
## 它只講「在不在吃電」；「吃不吃得飽」由三態徽章講（B0.6 前這裡還多畫一段
## 橙色缺口弧，那和 `缺料` 徽章編碼的是同一件事，留一個就好）。
func _draw_engaged(n: Dictionary, p: Vector2) -> void:
	if battle.engaged.get(int(n["id"]), false):
		# ★ B3.9：半徑跟著級數長，否則滿級的塔會把環頂穿。
		# ★ B3.10：但夾在半格內——它是交戰指示不是射程圈，越過格線就變成
		#   「這一格和隔壁那一格都在吃電」。
		battle.draw_arc(p, minf(15.0 * Shapes.level_scale(int(n.get("level", 0))), Shapes.GRID * 0.5),
			0.0, TAU, 32, Palette.ENERGY_AMBER, 2.0)


## ★ 節點三態徽章（`10_GDD.md` §3.1）。**`正常` 不畫任何東西**——徽章是例外
## 標記，一屏 14 個節點全掛上「我很好」等於把要找的那兩個埋進雜訊裡。
## 靠**形狀**分辨而不只是顏色：倒三角＝空的（缺料）、正三角＝滿的（滿溢）。
##
## ★ **缺料再分兩種**（B2.4.8，遊玩測試 P2-1）：倒三角＝缺礦砂、閃電＝缺電。
##   舊版兩種共用一個橙色倒三角，於是這個「地圖上唯一指出瓶頸的元素」
##   說得出誰在餓、說不出餓的是什麼——而那正是全案核心命題的那一刀。
##   形狀與顏色**同時**不同（§1.6 說換顏色不夠、要換形狀，這裡兩個都換）：
##   閃電走 `energy.amber`，因為 §1.1 配色紀律 2 說琥珀專屬於能量——
##   這一次那條紀律是在幫忙，不是在擋路。
func _draw_badge(n: Dictionary, p: Vector2) -> void:
	match int((battle.s.rates["node_state"] as Dictionary).get(int(n["id"]), SessionState.NORMAL)):
		SessionState.STARVED:
			battle.draw_colored_polygon(PackedVector2Array([
				p + Vector2(-7, -25), p + Vector2(7, -25), p + Vector2(0, -16)
			]), Palette.WARN_ORANGE)
		SessionState.STARVED_POWER:
			# 五點折線的閃電。**不用描邊**：14px 高的東西加外框只會糊掉。
			battle.draw_colored_polygon(PackedVector2Array([
				p + Vector2(2, -27), p + Vector2(-6, -19), p + Vector2(-1, -19),
				p + Vector2(-3, -13), p + Vector2(6, -22), p + Vector2(1, -22),
			]), Palette.ENERGY_AMBER)
		SessionState.OVERFLOW:
			battle.draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -25), p + Vector2(7, -16), p + Vector2(-7, -16)
			]), Palette.ORDER_BRIGHT)


## ★ 能量列（`10_GDD.md` §6.2 硬性要求 1）：**全畫面最醒目的元件，而且是一條
## 圖形不是一串數字**——長度即資訊，所以它在 `TL_NAKED` 下要留著。
## 琥珀＝供給、右側橙色＝短少的部分（脈動）、細刻度＝需求落在哪裡。
func draw_energy_bar() -> void:
	var r: Dictionary = battle.s.rates
	var supply := float(r["power_supply"])
	var demand := float(r["power_demand"])
	var span := maxf(1.0, maxf(supply, demand))
	# ★ 跨滿**框架**而不是跨滿地圖（B1.2.2）：框架恆定，所以這條「全畫面最醒目
	#   的元件」在每一關都是同一個長度，長度即資訊那句話才跨關成立。
	var w := BattleCamera.FRAME.size.x
	var at := Vector2(BattleCamera.FRAME.position.x, BattleCamera.FRAME.position.y - 12.0)
	# ★ B3.11：一圈深色的底框——琥珀條和頂欄的字都亮，中間要有一條暗線分開。
	battle.draw_rect(
		Rect2(at - Vector2(1.0, 1.0), Vector2(w + 2.0, 10.0)), Palette.alpha(Palette.BG_DEEP, 0.75)
	)
	battle.draw_rect(Rect2(at, Vector2(w, 8.0)), Palette.BG_RAISED)
	battle.draw_rect(Rect2(at, Vector2(w * supply / span, 8.0)), Palette.ENERGY_AMBER)
	if demand > supply:
		# 脈動走 `Motion`（§4.1 時長階、§4.4 可跳過）。B1.6 之前這裡是
		# `sin(tick * 0.4)`、敵人是 `sin(tick * 0.25)`——兩個係數沒有任何理由
		# 不同，看起來卻像兩件不同的事，而且都繞過了 `reduce_motion`。
		var pulse := Motion.pulse01(battle.s.tick_count, Motion.AMBIENT * 0.5, 0.55)
		var x := w * supply / span
		battle.draw_rect(
			Rect2(at + Vector2(x, 0.0), Vector2(w * demand / span - x, 8.0)),
			Palette.alpha(Palette.WARN_ORANGE, pulse)
		)
	battle.draw_rect(Rect2(at + Vector2(w * demand / span - 1.0, -3.0), Vector2(2.0, 14.0)),
		Palette.TEXT_PRIMARY)
