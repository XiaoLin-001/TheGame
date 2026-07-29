extends RefCounted
## 建造操作：把玩家的點擊翻譯成對 `SessionState` 的變更（`30_TECH_DESIGN.md` §2.1）。
##
## 職責邊界：**合法性判斷在 `sim/Build.gd`（純函式、可測試），這裡只管錢與落地。**
## 文案也在這裡——`sim/` 回傳原因碼，中文字串不進模擬層。

const Build := preload("res://scripts/sim/Build.gd")
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
	Build.MAX_LEVEL: "這條導管已經是最高級（cap 28）",
	Build.NO_ORE: "礦砂不夠",
	Build.NO_ALLOY: "合金不夠——合金要蓋熔爐、而且熔爐要接到核心才入帳",
	Build.LOCKED: "這一關還沒解鎖這種節點",
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
	var code: String = Build.can_connect(s.sets, s.conduit_keys(), a, b)
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


## 拆除：節點或導管都走這裡，返還 75%。
## `point`（格為單位的浮點座標）只在「這一格沒有節點」時才用得上——
## 它讓拆導管和加粗一樣點得準（B1.2.1）。省略時退回格中心。
static func demolish(s: RefCounted, cell: Vector2i, point: Vector2 = Vector2(-999, -999)) -> String:
	var n: Dictionary = s.node_at(cell)
	if not n.is_empty():
		if n["type"] == "core":
			return Build.OCCUPIED  # 核心拆不得
		var type := String(n["type"])
		s.ore += floorf(float(NodeDefs.cost(type)) * REFUND)
		s.alloy += floorf(float(NodeDefs.alloy_cost(type)) * REFUND)
		s.remove_node_at(cell)
		return Build.OK
	var ci: int = s.conduit_near(Vector2(cell) if point.x < -900.0 else point)
	if ci >= 0:
		var c: Dictionary = s.conduits[ci]
		var spent := Build.conduit_cost(c["a"], c["b"])
		var spent_alloy := 0
		for lv in range(int(c["level"])):
			spent += Build.upgrade_cost(lv)
			spent_alloy += Build.upgrade_alloy(lv)
		s.ore += floorf(float(spent) * REFUND)
		s.alloy += floorf(float(spent_alloy) * REFUND)
		s.remove_conduit(ci)
		return Build.OK
	return Build.OCCUPIED


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
	for op: Array in ops:
		if String(op[0]) != "wait":
			batch.append(op)
			continue
		failures.append_array(apply_ops(s, batch))
		batch = []
		for _i in int(op[1]):
			step.call(s)
	failures.append_array(apply_ops(s, batch))
	return failures


## 兩端 → 導管索引。找不到回 −1（`upgrade()` 會擋下）。
static func _index_of(s: RefCounted, a: Vector2i, b: Vector2i) -> int:
	var key := Build.conduit_key(a, b)
	for i in s.conduits.size():
		var c: Dictionary = s.conduits[i]
		if Build.conduit_key(c["a"], c["b"]) == key:
			return i
	return -1


## 放置前的預覽（DoD：`+X/秒` 與總耗能變化）。
## 回傳 `{cost, ok, reason, lines: [String]}`——**在花錢之前就看得到後果**。
static func preview_place(s: RefCounted, type: String, cell: Vector2i) -> Dictionary:
	var code: String = Build.can_place(s.sets, s.occupied(), type, cell)
	var cost := NodeDefs.cost(type)
	var alloy := NodeDefs.alloy_cost(type)
	var def := NodeDefs.of(type)
	var lines: Array[String] = [price_text(type)]

	if def.has("ore_out"):
		lines.append("＋%.0f 礦砂/秒（要接到核心才入帳）" % float(def["ore_out"]))
	if def.has("ore_in"):
		lines.append("−%.0f 礦砂/秒（燃料）" % float(def["ore_in"]))
	if def.has("power_out"):
		lines.append("＋%.0f 能量/秒" % float(def["power_out"]))
	if def.has("alloy_out"):
		lines.append("＋%.0f 合金/秒（要接到核心才入帳）" % float(def["alloy_out"]))
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
		lines.append("交戰時 −%.0f 能量/秒（待機 0）" % float(def["engage_power"]))

	# 總供需變化：本作最重要的資訊通道，**在花錢之前**就要看得到（§3.1）。
	var supply_now := float(s.rates.get("power_supply", 0.0))
	var demand_now := float(s.rates.get("power_demand", 0.0))
	var d_supply := float(def.get("power_out", 0.0))
	var d_demand := _power_demand_of(type)
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
static func _power_demand_of(type: String) -> float:
	var def := NodeDefs.of(type)
	if def.has("capacity"):
		return Build.CAP_BASE
	return float(def.get("power_in", 0.0)) + float(def.get("engage_power", 0.0))
