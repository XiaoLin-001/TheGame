extends RefCounted
## 建造操作：把玩家的點擊翻譯成對 `SessionState` 的變更（`30_TECH_DESIGN.md` §2.1）。
##
## 職責邊界：**合法性判斷在 `sim/Build.gd`（純函式、可測試），這裡只管錢與落地。**
## 文案也在這裡——`sim/` 回傳原因碼，中文字串不進模擬層。

const Build := preload("res://scripts/sim/Build.gd")
const Blueprint := preload("res://scripts/sim/Blueprint.gd")
const NodeDefs := preload("res://data/NodeDefs.gd")

## 拆除返還比例。失敗只花時間（紅線 R1）的一致延伸：試錯的代價要小。
const REFUND := 0.75

const REASONS := {
	Build.OUT_OF_BOUNDS: "超出地圖範圍",
	Build.ON_PATH: "敵人路徑上不能蓋節點（跨越點也不行，橋上只能鋪導管）",
	Build.OCCUPIED: "這一格已經有東西了",
	Build.NEEDS_ORE_CELL: "採集器只能蓋在礦點上",
	Build.ORE_CELL_RESERVED: "礦點只留給採集器",
	Build.NOT_STRAIGHT: "導管只能走水平／垂直／45°——轉彎要先放一個中繼",
	Build.SAME_NODE: "起點與終點是同一個節點",
	Build.CROSSES_PATH: "導管要過敵人路徑，只能走跨越點（橋）",
	Build.DUPLICATE: "這兩個節點之間已經有一條導管了",
	# 不寫死 28：科技「導管擴容」會把基礎值推上去（B1.3），寫死的數字會變成謊話。
	Build.MAX_LEVEL: "這條導管已經加粗到最高級了",
	Build.NO_ORE: "礦砂不夠",
	Build.NO_ALLOY: "合金不夠——合金要蓋熔爐、而且熔爐要接到核心才入帳",
	Build.LOCKED: "這一關還沒解鎖這種節點",
	Build.OVERLAPS: "這條線會和一條既有導管疊在一起——改個走法，或先放一個中繼繞開",
}


static func reason_text(code: String) -> String:
	return String(REASONS.get(code, code))


## 放置節點。回傳原因碼（空字串＝成功）。
static func place(s: RefCounted, type: String, cell: Vector2i) -> String:
	var code: String = Build.can_place(s.sets, s.occupied(), type, cell)
	if code != Build.OK:
		return code
	var cost := NodeDefs.cost(type)
	var alloy := NodeDefs.alloy_cost(type)
	if s.ore < float(cost):
		return Build.NO_ORE
	if s.alloy < float(alloy):
		return Build.NO_ALLOY
	s.ore -= float(cost)
	s.alloy -= float(alloy)
	s.add_node(type, cell)
	return Build.OK


## 拉導管。兩端都必須已經有節點。
static func lay_conduit(s: RefCounted, a: Vector2i, b: Vector2i) -> String:
	if s.node_at(a).is_empty() or s.node_at(b).is_empty():
		return Build.SAME_NODE if a == b else Build.OCCUPIED
	var code: String = Build.can_connect(s.sets, s.conduit_keys(), a, b, s.conduit_cells())
	if code != Build.OK:
		return code
	var cost := Build.conduit_cost(a, b)
	if s.ore < float(cost):
		return Build.NO_ORE
	s.ore -= float(cost)
	s.add_conduit(a, b)
	return Build.OK


## 幹線加粗（局內升級，§7.2）。**這是一個和「多蓋一座採集器」競爭的取捨**，
## 1 級花的是同一份礦砂；2/3 級**還要合金**（B1.1）——於是後半段的加粗和
## 蓋碎浪搶同一份合金，核心取捨在第三種資源上再演一次。
static func upgrade(s: RefCounted, index: int) -> String:
	if index < 0 or index >= s.conduits.size():
		return Build.OCCUPIED
	var c: Dictionary = s.conduits[index]
	var level := int(c["level"])
	if level >= Build.CAP_MAX_LEVEL:
		return Build.MAX_LEVEL
	var cost := Build.upgrade_cost(level)
	var alloy := Build.upgrade_alloy(level)
	if s.ore < float(cost):
		return Build.NO_ORE
	if s.alloy < float(alloy):
		return Build.NO_ALLOY
	s.ore -= float(cost)
	s.alloy -= float(alloy)
	c["level"] = level + 1
	return Build.OK


## ★ 局內臨時升級一座建築（`10_GDD.md` §4.3、B3.5）。
##
## 耗能 ×1.25/級（`Build.node_scale()`），效果只長那一級指定的那一項
## （`Build.effect_scale()` 等，B3.8），**最多 5 級**（B3.9），隨局結束消失。
## 買到的是集中（更少格子、更少導管），不是效率——理由寫在 `Build.gd` 那一段。
##
## **核心升不得**：它沒有產出也沒有耗能，`node_scale()` 對它是空操作，
## 而一顆「5 級核心」會讓玩家以為血量變多了。擋在這裡而不是靠 UI 不畫那顆鈕
## ——藍圖展開與重播都繞得過 UI（`Build.can_place()` 的同一條理由）。
static func upgrade_node(s: RefCounted, cell: Vector2i) -> String:
	var n: Dictionary = s.node_at(cell)
	if n.is_empty():
		return Build.OCCUPIED
	var type := String(n["type"])
	if type == "core":
		return Build.OCCUPIED
	var level := int(n.get("level", 0))
	if level >= Build.NODE_MAX_LEVEL:
		return Build.MAX_LEVEL
	var cost := Build.node_upgrade_cost(NodeDefs.cost(type), level)
	if s.ore < float(cost):
		return Build.NO_ORE
	s.ore -= float(cost)
	n["level"] = level + 1
	return Build.OK


## ★ 拆掉會退多少（礦砂, 合金）。**退款規則只有這一份**（B3.7）。
##
## 檢視面板的拆除鈕要把數字寫在鈕上，而「鈕上寫的」和「真的退的」各算一份的話，
## 遲早會有一次不一樣——那種缺陷玩家會當成偷他的錢。
static func node_refund(type: String) -> Vector2i:
	return Vector2i(
		int(floorf(float(NodeDefs.cost(type)) * REFUND)),
		int(floorf(float(NodeDefs.alloy_cost(type)) * REFUND))
	)


## 同上，導管版。導管退的是**鋪設價 ＋ 已買的每一級加粗**。
static func conduit_refund(c: Dictionary) -> Vector2i:
	var spent := Build.conduit_cost(c["a"], c["b"])
	var spent_alloy := 0
	for lv in range(int(c["level"])):
		spent += Build.upgrade_cost(lv)
		spent_alloy += Build.upgrade_alloy(lv)
	return Vector2i(int(floorf(float(spent) * REFUND)), int(floorf(float(spent_alloy) * REFUND)))


## 拆一條導管（**指標版**，B3.7）。檢視面板已經知道玩家選的是哪一條，
## 不必再用座標猜一次——用座標猜的那條路徑（`demolish()`）留給模式點擊。
static func demolish_conduit(s: RefCounted, index: int) -> String:
	if index < 0 or index >= s.conduits.size():
		return Build.OCCUPIED
	var refund := conduit_refund(s.conduits[index])
	s.ore += float(refund.x)
	s.alloy += float(refund.y)
	s.remove_conduit(index)
	return Build.OK


## 拆一座建築，返還 75%。導管走 `demolish_conduit()`。
##
## ★ B3.7.1 起這裡不再兼管導管。舊簽章有一個 `point`（格為單位的浮點座標），
## 用來在「這一格沒有節點」時**猜**玩家指的是哪一條線（B1.2.1）——那是拆除模式
## 唯一的入口形狀。模式拿掉之後，唯一的呼叫端是檢視面板，而**面板已經知道
## 玩家選的是哪一個東西**，不必再用座標猜一次。
static func demolish(s: RefCounted, cell: Vector2i) -> String:
	var n: Dictionary = s.node_at(cell)
	if n.is_empty():
		return Build.OCCUPIED
	if n["type"] == "core":
		return Build.OCCUPIED  # 核心拆不得
	var refund := node_refund(String(n["type"]))
	s.ore += float(refund.x)
	s.alloy += float(refund.y)
	s.remove_node_at(cell)
	return Build.OK


## ★ 藍圖展開的**事前檢查**（B2.3、`10_GDD.md` §3.7）。
##
## 回傳 `{ok, ore_short, alloy_short, blocked}`：差多少礦砂、差多少合金、
## 哪幾格蓋不下去。**不改變任何狀態**。
##
## ── 為什麼是「全有全無」──────────────────────────────────────────
## 藍圖是一個單位，不是一疊各自獨立的指令。半套展開會**花掉資源換到一個
## 接不起來的殘骸**——玩家看到的是「錢少了、東西沒蓋好」，而且拆掉只退 75%。
## 所以先整份驗過，一格不合就一格都不放，並且說出是哪一格、差多少
## （§3.7「資源不足則顯示缺口」）。
##
## ── 為什麼要自己投影一份 occupied，而不是直接試著蓋 ────────────────
## 藍圖自己的節點會互相佔位、自己的導管會互相判重疊。拿當前狀態去問
## `can_place()` 只會得到「第一格可以」——後面的都還沒放上去。
## 所以這裡把已放進去的部分**投影**進檢查用的集合裡，一格一格往下走，
## 走的順序和 `ops_at()` 完全一樣（節點全部先於導管）。
static func blueprint_check(s: RefCounted, bp: Dictionary, origin: Vector2i) -> Dictionary:
	var need: Dictionary = Blueprint.cost(bp)
	var blocked: Array[Vector2i] = []
	var occupied: Dictionary = s.occupied()
	var keys: Dictionary = s.conduit_keys()
	var cells: Array = s.conduit_cells()
	for op: Array in Blueprint.ops_at(bp, origin):
		if String(op[0]) == "place":
			var cell: Vector2i = op[2]
			if Build.can_place(s.sets, occupied, String(op[1]), cell) != Build.OK:
				blocked.append(cell)
				continue
			occupied[cell] = true
		else:
			var a: Vector2i = op[1]
			var b: Vector2i = op[2]
			# 兩端只要有一端沒蓋成，這條線本來就接不起來——不重複記一次
			# （玩家要看的是「哪一格擋住了」，不是被它連累的每一條線）。
			if not occupied.has(a) or not occupied.has(b):
				continue
			if Build.can_connect(s.sets, keys, a, b, cells) != Build.OK:
				blocked.append(a)
				continue
			keys[Build.conduit_key(a, b)] = true
			cells.append(Build.line_cells(a, b))
	var ore_short := maxi(0, int(need["ore"]) - int(floorf(s.ore)))
	var alloy_short := maxi(0, int(need["alloy"]) - int(floorf(s.alloy)))
	return {
		"ok": blocked.is_empty() and ore_short == 0 and alloy_short == 0,
		"ore_short": ore_short,
		"alloy_short": alloy_short,
		"blocked": blocked,
	}


## 展開一張藍圖。**檢查不過就一格都不放**，回傳給玩家看的那句話。
static func blueprint_place(s: RefCounted, bp: Dictionary, origin: Vector2i) -> String:
	if Blueprint.is_empty(bp):
		return "✕ 這張藍圖是空的"
	var chk := blueprint_check(s, bp, origin)
	if not bool(chk["ok"]):
		return blueprint_reason(chk)
	var fails: Array = apply_ops(s, Blueprint.ops_at(bp, origin))
	# 走到這裡還失敗＝檢查與實際放置對不上，那是缺陷不是玩家的問題。
	# **不要吞掉**：靜靜失敗的建造正是 `apply_ops()` 回傳失敗清單的理由。
	if not fails.is_empty():
		return "✕ 展開時有 %d 步失敗（請回報）" % fails.size()
	return ""


## 缺口的說法。**先講資源、再講格子**：資源不足是玩家等一下就能解決的，
## 位置不對要他移動滑鼠——兩件事的下一步不一樣，混成一句話等於都沒講。
static func blueprint_reason(chk: Dictionary) -> String:
	var parts: Array[String] = []
	if int(chk["ore_short"]) > 0:
		parts.append("礦砂差 %d" % int(chk["ore_short"]))
	if int(chk["alloy_short"]) > 0:
		parts.append("合金差 %d" % int(chk["alloy_short"]))
	var blocked: Array = chk["blocked"]
	if not blocked.is_empty():
		parts.append("有 %d 格蓋不下（%s…）" % [blocked.size(), blocked[0]])
	return "✕ " + "，".join(parts) if not parts.is_empty() else ""


## 重播一組建造指令（`data/Maps.gd` 的示範佈局、日後的藍圖與重播都走這裡）。
## 回傳失敗的指令索引與原因碼——**靜靜失敗的建造腳本會產生騙人的截圖**。
static func apply_ops(s: RefCounted, ops: Array) -> Array:
	var failures: Array = []
	for i in ops.size():
		var op: Array = ops[i]
		var code := ""
		match String(op[0]):
			"place":
				code = place(s, String(op[1]), op[2])
			"conduit":
				code = lay_conduit(s, op[1], op[2])
			"upgrade":
				# 以兩端指定，不用索引：索引會隨前面的指令漂移，
				# 一改示範佈局就會靜靜地加粗到別條線上。
				var idx := _index_of(s, op[1], op[2])
				for _lv in int(op[3]):
					code = upgrade(s, idx)
					if code != Build.OK:
						break
			_:
				code = "unknown_op"
		if code != Build.OK:
			failures.append({"index": i, "op": op[0], "reason": code})
	return failures


## ★ 帶時間軸的建造腳本（B1.2）：`["wait", ticks]` 之間的指令一次套用，
## 然後推 N 個 tick 讓產線自己賺錢，再蓋下一段。
##
## **分段建造才是玩家真正的樣子。** 一口氣全蓋起來會逼得關卡的起始礦砂虛高，
## 而起始礦砂是玩家看得見的關卡參數（§7.7）——虛高等於偷偷把難度調低。
##
## `step` 是 `Callable(s)`：這支檔案不 preload `BattleController`（它 preload
## 回這裡，繞成一圈）。回傳的失敗索引是**該段之內**的索引。
static func apply_timeline(s: RefCounted, ops: Array, step: Callable) -> Array:
	var failures: Array = []
	var batch: Array = []
	var seg := 1
	for op: Array in ops:
		if String(op[0]) != "wait":
			batch.append(op)
			continue
		failures.append_array(_tag(apply_ops(s, batch), seg))
		batch = []
		seg += 1
		for _i in int(op[1]):
			step.call(s)
	failures.append_array(_tag(apply_ops(s, batch), seg))
	return failures


## ★ 給每一筆失敗補上段號（B3.3b、RG-168 的第二半）。
##
## `apply_ops()` 回的 `index` 是**段內**的序號，而一份腳本有好幾段——
## 光有 `index` 的話，「第 0 筆 place 失敗」在七段的腳本裡有七個候選，
## 而讀的人（或工具）只能猜。第一版的試跑台就是這樣把「碎浪煉不出合金」
## 顯示成「第 1 段的中繼蓋不起來」，害我去查一格根本沒問題的地圖。
## 段號由這裡發，因為**只有這裡知道現在跑到第幾段**。
static func _tag(failures: Array, seg: int) -> Array:
	for f: Variant in failures:
		(f as Dictionary)["seg"] = seg
	return failures


## 兩端 → 導管索引。找不到回 −1（`upgrade()` 會擋下）。
static func _index_of(s: RefCounted, a: Vector2i, b: Vector2i) -> int:
	var key := Build.conduit_key(a, b)
	for i in s.conduits.size():
		var c: Dictionary = s.conduits[i]
		if Build.conduit_key(c["a"], c["b"]) == key:
			return i
	return -1


## 整數就寫整數，有小數才寫一位。
##
## ★ 等級軸（B2.7）讓這些數字第一次可能不是整數（6 → 7.44）。一律 `%.1f` 的話
## 沒買等級的玩家會看到「＋6.0 礦砂/秒」——那是為了 8% 的情況去弄髒 92% 的情況；
## 一律 `%.0f` 則是把 7.44 顯示成 7，那是一個**說謊的數字**，而這一列的全部工作
## 就是「在花錢之前看得到後果」。
static func _num(v: float) -> String:
	return "%.0f" % v if is_equal_approx(v, roundf(v)) else "%.1f" % v


## 放置前的預覽（DoD：`+X/秒` 與總耗能變化）。
## 回傳 `{cost, ok, reason, lines: [String]}`——**在花錢之前就看得到後果**。
static func preview_place(s: RefCounted, type: String, cell: Vector2i) -> Dictionary:
	var code: String = Build.can_place(s.sets, s.occupied(), type, cell)
	var cost := NodeDefs.cost(type)
	var alloy := NodeDefs.alloy_cost(type)
	var def := NodeDefs.of(type)
	var lines: Array[String] = [price_text(type)]

	# ★ 等級軸的生產乘數（B2.7）。**提示列上的數字要和局內實際跑的一致**——
	#   這幾行是「在花錢之前就看得到後果」的全部內容，差 8% 就是差在那裡。
	var pm := float(s.mods["produce_mult"])
	if def.has("ore_out"):
		var bonus := float(s.mods["extractor_ore"]) if type == "extractor" else 0.0
		lines.append("＋%s 礦砂/秒（要接到核心才入帳）" % _num((float(def["ore_out"]) + bonus) * pm))
	if def.has("ore_in"):
		lines.append("−%.0f 礦砂/秒（燃料）" % float(def["ore_in"]))
	if def.has("power_out"):
		lines.append("＋%s 能量/秒" % _num(float(def["power_out"]) * pm))
	if def.has("alloy_out"):
		lines.append("＋%s 合金/秒（要接到核心才入帳）" % _num(float(def["alloy_out"]) * pm))
	# 熔爐的 `power_in` 是**待機也吃**的，不是交戰耗能——說法要和塔區分開，
	# 不然玩家會以為它跟塔一樣沒事不耗電。
	if def.has("power_in"):
		lines.append("−%.0f 能量/秒（一直吃，不分準備期或波次期）" % float(def["power_in"]))
	if def.has("capacity"):
		lines.append("緩衝 %.0f 能量" % float(def["capacity"]))
	# ★ 塔：**交戰耗能才是要買的東西**，待機 0 要一起講——
	# 只寫「−20 能量/秒」會讓玩家以為蓋了就一直漏電（§7.4）。
	# 射程／射速／傷害不寫進來：提示列是一行，塞進去只會把上面那些擠掉，
	# 而且射程在滑鼠底下已經畫成一個圈了（`screens/Battle.gd` 的放置預覽）。
	if def.has("engage_power"):
		# 科技「能量效率」買的就是這一個數字（B1.3）——預覽不跟著變的話，
		# 玩家會從最重要的那條資訊上讀到未打折的舊值。
		lines.append(
			"交戰時 −%.1f 能量/秒（待機 0）"
			% (float(def["engage_power"]) * float(s.mods["engage_mult"]))
		)

	# 總供需變化：本作最重要的資訊通道，**在花錢之前**就要看得到（§3.1）。
	var supply_now := float(s.rates.get("power_supply", 0.0))
	var demand_now := float(s.rates.get("power_demand", 0.0))
	var d_supply := float(def.get("power_out", 0.0)) * pm
	var d_demand := _power_demand_of(type, float(s.mods["cap_bonus"]), float(s.mods["engage_mult"]))
	if not is_zero_approx(d_supply):
		lines.append("總能量供給 %.0f → %.0f /秒" % [supply_now, supply_now + d_supply])
	if not is_zero_approx(d_demand):
		var when := "（交戰時）" if def.has("engage_power") else ""
		lines.append("總能量需求 %.0f → %.0f /秒%s" % [demand_now, demand_now + d_demand, when])

	if code != Build.OK:
		lines.append("✕ " + reason_text(code))
	elif s.ore < float(cost):
		lines.append("✕ " + reason_text(Build.NO_ORE))
	elif s.alloy < float(alloy):
		lines.append("✕ " + reason_text(Build.NO_ALLOY))

	return {
		"cost": cost,
		"alloy": alloy,
		"ok": code == Build.OK and s.ore >= float(cost) and s.alloy >= float(alloy),
		"reason": code,
		"lines": lines,
	}


## 一種節點的價牌。**只有真的要合金的才會出現第二個數字**——
## 給每一顆鈕都掛上「＋0 合金」只會讓那三個真的要合金的東西沉下去。
static func price_text(type: String) -> String:
	var alloy := NodeDefs.alloy_cost(type)
	if alloy <= 0:
		return "%s　%d 礦砂" % [NodeDefs.label(type), NodeDefs.cost(type)]
	return "%s　%d 礦砂 ＋ %d 合金" % [NodeDefs.label(type), NodeDefs.cost(type), alloy]


## 這個類型會替全網增加多少能量需求。
## 儲槽的充能需求不是固定值——它受**自己那條導管的 cap** 約束（§3.1），
## 線還沒拉之前只能以基礎 cap 估。
## 塔給的是**交戰時**的峰值：本作的約束是峰值電力，不是平均電力（§3.3）。
static func _power_demand_of(type: String, cap_bonus := 0.0, engage_mult := 1.0) -> float:
	var def := NodeDefs.of(type)
	if def.has("capacity"):
		return Build.CAP_BASE + cap_bonus
	return (
		float(def.get("power_in", 0.0))
		+ float(def.get("engage_power", 0.0)) * engage_mult
	)
