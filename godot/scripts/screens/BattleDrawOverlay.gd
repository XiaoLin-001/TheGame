class_name BattleDrawOverlay
extends RefCounted
## 互動層繪圖：選取、懸停預覽、拉線導引。
##
## 由 `Battle.gd` 拆出（B3.14）：只改搬家，不改行為。

const Blueprint := preload("res://scripts/sim/Blueprint.gd")
const Build := preload("res://scripts/sim/Build.gd")
const BuildController := preload("res://scripts/game/BuildController.gd")
const FlowNetwork := preload("res://scripts/sim/FlowNetwork.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")
const Readout := preload("res://scripts/game/Readout.gd")

var battle: BattleScreen


func _init(screen: BattleScreen) -> void:
	battle = screen


## ★ 被選取那一座：射程圈 ＋ **正在餵它電的那幾台**（B3.6）。
##
## 三個記號各答一個問題，而且**形狀各不相同**（§4.3b：同一張圖上的兩個訊息，
## 換顏色不夠）：
##   · 選取本身 ＝ 那一格的**方框**（和擺放預覽的框同一個語彙）
##   · 射程 ＝ 一個**圓弧**
##   · 供電來源 ＝ 來源那一格的**菱形**，加上沿途導管的高亮
##
## 供電鏈逆著本 tick 的**實際流向**走（`FlowNetwork.upstream_power()`），
## 不是「有沒有連著」——一座塔可能連著五條線而這一刻只有兩條在餵它。
func draw_selection() -> void:
	# ★ 選著一條導管（B3.7）：把它整條描出來。用**外框而不是換色**——導管自己的
	#   顏色正在講流量與滿載（§1.4a），塗掉它等於為了指出一條線而讓它不能讀。
	var wi := battle.inspect.sel_wire_index()
	if wi >= 0:
		var sc: Dictionary = battle.s.conduits[wi]
		var a := battle.cam.center(sc["a"])
		var b := battle.cam.center(sc["b"])
		# ⚠ **外框要明確伸出管緣**，而管緣的位置隨流量走（2–8px）。
		#   第一版寫死 ±7px，於是選一條滿載的幹線時外框正好壓在它自己的邊上——
		#   截圖當場看不出哪一條被選中。`_draw_conduits()` 的刻度在 B1.6.1 踩過
		#   一模一樣的坑，那裡的解法是 `w * 0.5 + 3`，這裡照抄。
		var bonus := float(battle.s.mods["cap_bonus"])
		var w := Shapes.conduit_width(
			float((battle.s.rates["conduit_flow"] as Dictionary).get(sc["id"], 0.0)),
			Build.conduit_cap(Build.CAP_MAX_LEVEL, bonus)
		)
		var n := (b - a).normalized().orthogonal() * (w * 0.5 + 4.0)
		var t := (b - a).normalized() * (w * 0.5 + 4.0)
		battle.draw_polyline(PackedVector2Array([
			a + n - t, b + n + t, b - n + t, a - n - t, a + n - t,
		]), Palette.ORDER_BRIGHT, 2.0)
		return
	if battle.selected.x < 0:
		return
	var n: Dictionary = battle.s.node_at(battle.selected)
	if n.is_empty():
		return
	var c := battle.cam.center(battle.selected)
	var g := Vector2(Shapes.GRID, Shapes.GRID)
	battle.draw_rect(Rect2(battle.cam.world(battle.selected), g), Palette.ORDER_BRIGHT, false, 2.0)

	# ★ B3.8：圈要畫**升過的射程**。讀表上的原值會讓玩家看到一個和實際打得到
	#   的範圍不一樣的圈——而擺位正是他用這個圈在做的決定。
	var rng := Build.node_range(String(n["type"]), int(n.get("level", 0)))
	if rng > 0.0:
		# 半透明填色 ＋ 實線邊：只有邊的話，兩座塔的射程圈交疊時看不出誰罩到哪。
		battle.draw_circle(c, rng * Shapes.GRID, Palette.alpha(Palette.ORDER_CYAN, 0.07))
		battle.draw_arc(c, rng * Shapes.GRID, 0.0, TAU, 64, Palette.alpha(Palette.ORDER_BRIGHT, 0.7), 2.0)

	var chain := FlowNetwork.upstream_power(battle.s.conduits, Readout.energy_net(battle.s), battle.selected, Readout.power_sources(battle.s))
	var lit: Dictionary = chain["conduits"]
	for ci in battle.s.conduits.size():
		var cd: Dictionary = battle.s.conduits[ci]
		if not lit.has(cd["id"]):
			continue
		battle.draw_line(battle.cam.center(cd["a"]), battle.cam.center(cd["b"]),
			Palette.alpha(Palette.ENERGY_AMBER, 0.55), 6.0)
	# 來源畫琥珀菱形（琥珀專屬能量，§1.1 配色紀律 2）——它答的是「電從哪來」。
	for cell: Variant in (chain["sources"] as Dictionary):
		var sc := battle.cam.center(cell)
		battle.draw_polyline(PackedVector2Array([
			sc + Vector2(0, -20), sc + Vector2(20, 0), sc + Vector2(0, 20),
			sc + Vector2(-20, 0), sc + Vector2(0, -20),
		]), Palette.ENERGY_AMBER, 2.5)


func draw_hover() -> void:
	if not battle.cam.in_map(battle.hover):
		return
	var p := battle.cam.world(battle.hover)
	var g := Vector2(Shapes.GRID, Shapes.GRID)
	# ★ 游標壓在導管上時，**不畫落點預覽，改把那條線點亮**（B3.7）。
	#   一次點擊只能做一件事，而畫面得先說出它會做哪一件——B3.4 才剛把落點預覽
	#   做成「畫那隻角色本人」，若它在會被導管攔下的地方照樣現身，那是畫面在說謊。
	var hover_wire: int = -1
	if battle.mode == BattleScreen.Mode.BUILD and battle.bp_index < 0 and battle.drag_from.x < 0:
		hover_wire = battle.s.conduit_near(battle.hover_p, BattleInput.WIRE_PICK)
	if hover_wire >= 0:
		var hc: Dictionary = battle.s.conduits[hover_wire]
		battle.draw_line(battle.cam.center(hc["a"]), battle.cam.center(hc["b"]),
			Palette.alpha(Palette.ORDER_BRIGHT, 0.45), 8.0)
	elif battle.mode == BattleScreen.Mode.BUILD and battle.build_type == "" and battle.bp_index < 0:
		# ★ B3.7.1：手上什麼都沒拿——**不畫落點預覽**。畫了就是承諾點下去會蓋東西，
		#   而這一刻不會。淡框仍然畫，游標在哪一格還是要看得見。
		battle.draw_rect(Rect2(p, g), Palette.BORDER_STRONG, false, 2.0)
	elif battle.mode == BattleScreen.Mode.BUILD:
		var pv := BuildController.preview_place(battle.s, battle.build_type, battle.hover)
		var col: Color = Palette.OK_GREEN if pv["ok"] else Palette.WARN_ORANGE
		battle.draw_rect(Rect2(p, g), Palette.alpha(col, 0.18))
		battle.draw_rect(Rect2(p, g), col, false, 2.0)
		# ★ **手上那一隻長什麼樣子，就畫什麼樣子**（B3.4）。
		#
		# 原本這裡只有上面那個框，於是玩家在做全遊戲最主要的那個決定
		# （這一格擺誰）的當下，看到的是一個和別種節點一模一樣的方框。
		# §1.6 花了整節在講「形狀要說得出這隻角色是什麼」——梯形是打進地裡的樁、
		# 三角是稜鏡、四角爆散星是濺射——而那些形狀在**最需要它們的那一刻**缺席。
		#
		# 走 `_draw_node_body()`（和真的節點同一支函式），不另外畫一份：
		# 抄一份的下場是加第十五種節點時只有一邊記得加，而漏掉的那一邊
		# 症狀是隱形不是報錯（B2.4 中過三次，`_no_glyph` 就是為此而生）。
		battle.network.draw_node_body({"type": battle.build_type}, battle.cam.center(battle.hover))
		# 塔的射程要**在花錢之前**看得到——擺位是本作的主要決策，
		# 讓玩家蓋完才發現打不到路徑等於逼他拆（§3.5 塔的擺位）。
		var r := float(NodeDefs.of(battle.build_type).get("range", 0.0))
		if r > 0.0:
			battle.draw_arc(
				battle.cam.center(battle.hover), r * Shapes.GRID, 0.0, TAU, 64,
				Palette.alpha(col, 0.45), 1.5
			)
	else:
		battle.draw_rect(Rect2(p, g), Palette.BORDER_STRONG, false, 2.0)
	# ★ 藍圖（B2.3）。框選中畫橡皮筋框；手上有藍圖時畫它的落點。
	if battle.bp_from.x >= 0:
		var lo := Vector2i(mini(battle.bp_from.x, battle.hover.x), mini(battle.bp_from.y, battle.hover.y))
		var hi := Vector2i(maxi(battle.bp_from.x, battle.hover.x), maxi(battle.bp_from.y, battle.hover.y))
		var rect := Rect2(battle.cam.world(lo), Vector2(hi - lo + Vector2i.ONE) * Shapes.GRID)
		battle.draw_rect(rect, Palette.alpha(Palette.ORDER_CYAN, 0.12))
		battle.draw_rect(rect, Palette.ORDER_CYAN, false, 2.0)
	elif battle.bp_index >= 0:
		var list := battle.bp.blueprints()
		if battle.bp_index < list.size():
			# **每一格各自上色**：綠＝放得下、橘＝這一格擋住了。整份一個顏色
			# 只能說「不行」，指不出是哪一格——而那正是玩家的下一步要知道的事。
			var chk := BuildController.blueprint_check(battle.s, list[battle.bp_index], battle.hover)
			var bad: Dictionary = {}
			for c: Vector2i in (chk["blocked"] as Array):
				bad[c] = true
			for c: Vector2i in Blueprint.cells_at(list[battle.bp_index], battle.hover):
				var col: Color = Palette.WARN_ORANGE if bad.has(c) else Palette.OK_GREEN
				battle.draw_rect(Rect2(battle.cam.world(c), g), Palette.alpha(col, 0.22))
				battle.draw_rect(Rect2(battle.cam.world(c), g), col, false, 2.0)
	var cf := battle.drag_from
	if cf.x >= 0:
		battle.draw_rect(Rect2(battle.cam.world(cf), g), Palette.ORDER_BRIGHT, false, 2.0)
		_draw_connect_guides(cf)
		# ★ 預覽線依**合法性**上色。B0.7.2 之前不管連不連得成都畫一條亮線，
		#   那是在畫一條不可能存在的導管——玩家只能點下去才知道不行。
		var code: String = Build.can_connect(
		battle.s.sets, battle.s.conduit_keys(), cf, battle.hover, battle.s.conduit_cells()
	)
		var legal: bool = code == Build.OK and not battle.s.node_at(battle.hover).is_empty()
		battle.draw_line(
			battle.cam.center(cf), battle.cam.center(battle.hover),
			Palette.alpha(Palette.OK_GREEN if legal else Palette.WARN_ORANGE, 0.7), 2.0
		)


## ★ 連線的八條方向導引（`10_GDD.md` §3.2「導管只能走水平／垂直／45°」）。
##
## 使用者回報「沒有辦法 45 度放置管道」——規則其實是通的，**難的是用肉眼在
## 網格上找出正斜角**（要 |dx| 恰好等於 |dy|）。一條規則如果只能靠試錯才知道
## 自己有沒有踩中，那它在體感上就等於壞掉。把八條合法方向直接畫出來，
## 「45°」從一句文字變成畫面上看得到的四條斜線。
func _draw_connect_guides(anchor: Vector2i) -> void:
	var from := battle.cam.center(anchor)
	var col := Palette.alpha(Palette.ORDER_DIM, 0.5)
	var size: Vector2i = battle.s.map["size"]
	for d: Vector2i in [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
	]:
		var end := anchor
		while battle.cam.in_map(end + d):
			end += d
		if end != anchor:
			battle.draw_line(from, battle.cam.center(end), col, 1.0)
