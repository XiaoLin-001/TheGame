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
}


static func reason_text(code: String) -> String:
	return String(REASONS.get(code, code))


## 放置節點。回傳原因碼（空字串＝成功）。
static func place(s: RefCounted, type: String, cell: Vector2i) -> String:
	var code: String = Build.can_place(s.sets, s.occupied(), type, cell)
	if code != Build.OK:
		return code
	var cost := NodeDefs.cost(type)
	if s.ore < float(cost):
		return Build.NO_ORE
	s.ore -= float(cost)
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
## 所以它花的是同一份礦砂，沒有另外的貨幣。
static func upgrade(s: RefCounted, index: int) -> String:
	if index < 0 or index >= s.conduits.size():
		return Build.OCCUPIED
	var c: Dictionary = s.conduits[index]
	var level := int(c["level"])
	if level >= Build.CAP_MAX_LEVEL:
		return Build.MAX_LEVEL
	var cost := Build.upgrade_cost(level)
	if s.ore < float(cost):
		return Build.NO_ORE
	s.ore -= float(cost)
	c["level"] = level + 1
	return Build.OK


## 拆除：節點或導管都走這裡，返還 75%。
static func demolish(s: RefCounted, cell: Vector2i) -> String:
	var n: Dictionary = s.node_at(cell)
	if not n.is_empty():
		if n["type"] == "core":
			return Build.OCCUPIED  # 核心拆不得
		s.ore += floorf(float(NodeDefs.cost(String(n["type"]))) * REFUND)
		s.remove_node_at(cell)
		return Build.OK
	var ci: int = s.conduit_at(cell)
	if ci >= 0:
		var c: Dictionary = s.conduits[ci]
		var spent := Build.conduit_cost(c["a"], c["b"])
		for lv in range(int(c["level"])):
			spent += Build.upgrade_cost(lv)
		s.ore += floorf(float(spent) * REFUND)
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
			_:
				code = "unknown_op"
		if code != Build.OK:
			failures.append({"index": i, "op": op[0], "reason": code})
	return failures


## 放置前的預覽（DoD：`+X/秒` 與總耗能變化）。
## 回傳 `{cost, ok, reason, lines: [String]}`——**在花錢之前就看得到後果**。
static func preview_place(s: RefCounted, type: String, cell: Vector2i) -> Dictionary:
	var code: String = Build.can_place(s.sets, s.occupied(), type, cell)
	var cost := NodeDefs.cost(type)
	var def := NodeDefs.of(type)
	var lines: Array[String] = ["%s　%d 礦砂" % [NodeDefs.label(type), cost]]

	if def.has("ore_out"):
		lines.append("＋%.0f 礦砂/秒（要接到核心才入帳）" % float(def["ore_out"]))
	if def.has("ore_in"):
		lines.append("−%.0f 礦砂/秒（燃料）" % float(def["ore_in"]))
	if def.has("power_out"):
		lines.append("＋%.0f 能量/秒" % float(def["power_out"]))
	if def.has("capacity"):
		lines.append("緩衝 %.0f 能量" % float(def["capacity"]))

	# 總供需變化：本作最重要的資訊通道，**在花錢之前**就要看得到（§3.1）。
	var supply_now := float(s.rates.get("power_supply", 0.0))
	var demand_now := float(s.rates.get("power_demand", 0.0))
	var d_supply := float(def.get("power_out", 0.0))
	var d_demand := _power_demand_of(type)
	if not is_zero_approx(d_supply):
		lines.append("總能量供給 %.0f → %.0f /秒" % [supply_now, supply_now + d_supply])
	if not is_zero_approx(d_demand):
		lines.append("總能量需求 %.0f → %.0f /秒" % [demand_now, demand_now + d_demand])

	if code != Build.OK:
		lines.append("✕ " + reason_text(code))
	elif s.ore < float(cost):
		lines.append("✕ " + reason_text(Build.NO_ORE))

	return {
		"cost": cost,
		"ok": code == Build.OK and s.ore >= float(cost),
		"reason": code,
		"lines": lines,
	}


## 這個類型會替全網增加多少**持續**能量需求。
## 儲槽的充能需求不是固定值——它受**自己那條導管的 cap** 約束（§3.1），
## 線還沒拉之前只能以基礎 cap 估。塔的交戰耗能（待機 0）是 B0.5 才進來的。
static func _power_demand_of(type: String) -> float:
	var def := NodeDefs.of(type)
	if def.has("capacity"):
		return Build.CAP_BASE
	return float(def.get("power_in", 0.0))
